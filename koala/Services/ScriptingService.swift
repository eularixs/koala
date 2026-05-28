import Foundation
@preconcurrency import JavaScriptCore
import Observation

// MARK: - ScriptingError

enum ScriptingError: LocalizedError {
    case timeout
    case engineUnavailable
    case runtime(String)

    var errorDescription: String? {
        switch self {
        case .timeout: return "Script execution exceeded 5s timeout."
        case .engineUnavailable: return "JavaScriptCore engine unavailable."
        case .runtime(let msg): return msg
        }
    }
}

// MARK: - ScriptingService

/// Runs Postman-style pre-request and post-response JavaScript snippets in a
/// sandboxed JSContext. Exposes a `koala.*` API for mutating env/globals/request
/// and asserting on the response.
@MainActor
@Observable
final class ScriptingService {

    /// Hard timeout per execution.
    private let executionTimeout: TimeInterval = 5.0

    init() {}

    // MARK: - Pre-request

    /// Runs the pre-request script. May mutate the in-out request, environment, and globals.
    /// Returns captured `console.log(...)` output.
    @discardableResult
    func runPreRequest(
        script: String,
        request: inout KoalaRequest,
        env: inout KoalaEnvironment?,
        globals: inout [KeyValuePair]
    ) throws -> [String] {
        guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        let ctx = try makeContext()
        var logs: [String] = []
        installConsole(in: ctx, logs: { logs.append($0) })

        let bag = Bag(
            request: request,
            response: nil,
            envVars: envDict(env),
            globalVars: globalsDict(globals),
            captureTest: nil
        )
        installKoalaAPI(in: ctx, bag: bag)

        try evaluateWithTimeout(script: script, context: ctx)

        // Persist mutations
        request = bag.request
        if env != nil {
            applyEnvDict(bag.envVars, into: &env!)
        }
        applyGlobalsDict(bag.globalVars, into: &globals)
        return logs
    }

    // MARK: - Post-response

    /// Runs the post-response/test script after a successful HTTP response.
    /// Returns captured logs and the list of test assertions.
    func runPostResponse(
        script: String,
        request: KoalaRequest,
        response: KoalaResponse,
        env: inout KoalaEnvironment?,
        globals: inout [KeyValuePair]
    ) throws -> (logs: [String], tests: [TestResult]) {
        guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ([], [])
        }
        let ctx = try makeContext()
        var logs: [String] = []
        installConsole(in: ctx, logs: { logs.append($0) })

        var tests: [TestResult] = []
        let bag = Bag(
            request: request,
            response: response,
            envVars: envDict(env),
            globalVars: globalsDict(globals),
            captureTest: { tests.append($0) }
        )
        installKoalaAPI(in: ctx, bag: bag)

        try evaluateWithTimeout(script: script, context: ctx)

        if env != nil {
            applyEnvDict(bag.envVars, into: &env!)
        }
        applyGlobalsDict(bag.globalVars, into: &globals)
        return (logs, tests)
    }

    // MARK: - Context setup

    private func makeContext() throws -> JSContext {
        guard let ctx = JSContext() else { throw ScriptingError.engineUnavailable }
        ctx.exceptionHandler = { context, exception in
            // Surface the most recent exception so test() / matchers can inspect it.
            if let exception, let context {
                context.setObject(exception, forKeyedSubscript: "__koalaLastException" as NSString)
            }
        }
        return ctx
    }

    private func installConsole(in ctx: JSContext, logs: @escaping (String) -> Void) {
        let logFn: @convention(block) (JSValue) -> Void = { value in
            let s = ScriptingService.stringify(value)
            logs(s)
        }
        let console = JSValue(newObjectIn: ctx)
        console?.setObject(logFn, forKeyedSubscript: "log" as NSString)
        console?.setObject(logFn, forKeyedSubscript: "info" as NSString)
        console?.setObject(logFn, forKeyedSubscript: "warn" as NSString)
        console?.setObject(logFn, forKeyedSubscript: "error" as NSString)
        ctx.setObject(console, forKeyedSubscript: "console" as NSString)
    }

    private func installKoalaAPI(in ctx: JSContext, bag: Bag) {
        // env
        let envGet: @convention(block) (String) -> Any? = { name in
            bag.envVars[name] as Any?
        }
        let envSet: @convention(block) (String, Any?) -> Void = { name, value in
            bag.envVars[name] = ScriptingService.toString(value)
        }
        let envObj = JSValue(newObjectIn: ctx)
        envObj?.setObject(envGet, forKeyedSubscript: "get" as NSString)
        envObj?.setObject(envSet, forKeyedSubscript: "set" as NSString)

        // globals
        let gGet: @convention(block) (String) -> Any? = { name in bag.globalVars[name] as Any? }
        let gSet: @convention(block) (String, Any?) -> Void = { name, value in
            bag.globalVars[name] = ScriptingService.toString(value)
        }
        let gObj = JSValue(newObjectIn: ctx)
        gObj?.setObject(gGet, forKeyedSubscript: "get" as NSString)
        gObj?.setObject(gSet, forKeyedSubscript: "set" as NSString)

        // request (read mostly; setters for url/method/body mutate underlying)
        let reqObj = JSValue(newObjectIn: ctx)
        reqObj?.setObject(bag.request.url, forKeyedSubscript: "url" as NSString)
        reqObj?.setObject(bag.request.method.displayName, forKeyedSubscript: "method" as NSString)
        reqObj?.setObject(ScriptingService.headersDict(bag.request.headers), forKeyedSubscript: "headers" as NSString)
        reqObj?.setObject(ScriptingService.bodyString(bag.request.body), forKeyedSubscript: "body" as NSString)
        // setHeader helper
        let setHeader: @convention(block) (String, String) -> Void = { [weak bag] name, value in
            guard let bag else { return }
            if let idx = bag.request.headers.firstIndex(where: { $0.key.caseInsensitiveCompare(name) == .orderedSame }) {
                bag.request.headers[idx].value = value
                bag.request.headers[idx].isEnabled = true
            } else {
                bag.request.headers.append(KeyValuePair(key: name, value: value, isEnabled: true))
            }
        }
        reqObj?.setObject(setHeader, forKeyedSubscript: "setHeader" as NSString)
        let setUrl: @convention(block) (String) -> Void = { [weak bag] url in
            bag?.request.url = url
        }
        reqObj?.setObject(setUrl, forKeyedSubscript: "setUrl" as NSString)

        // response (if present)
        let respObj = JSValue(newObjectIn: ctx)
        if let response = bag.response {
            respObj?.setObject(response.statusCode, forKeyedSubscript: "status" as NSString)
            respObj?.setObject(response.headers, forKeyedSubscript: "headers" as NSString)
            let bodyStr = String(data: response.body, encoding: .utf8) ?? ""
            respObj?.setObject(bodyStr, forKeyedSubscript: "body" as NSString)
            let jsonFn: @convention(block) () -> Any? = {
                guard let obj = try? JSONSerialization.jsonObject(with: response.body, options: [.fragmentsAllowed]) else {
                    return nil
                }
                return obj
            }
            respObj?.setObject(jsonFn, forKeyedSubscript: "json" as NSString)
        }

        // test() — captures assertion result
        let testFn: @convention(block) (String, JSValue) -> Void = { [weak bag] name, fn in
            guard let bag, let capture = bag.captureTest else { return }
            let start = Date()
            // Clear prior exception
            fn.context.setObject(NSNull(), forKeyedSubscript: "__koalaLastException" as NSString)
            let result = fn.call(withArguments: [])
            let duration = Int(Date().timeIntervalSince(start) * 1000)

            // If exception thrown inside fn
            if let exVal = fn.context.objectForKeyedSubscript("__koalaLastException"),
               !exVal.isUndefined, !exVal.isNull {
                let msg = exVal.toString() ?? "assertion failed"
                capture(TestResult(name: name, passed: false, failureMessage: msg, durationMs: duration))
                fn.context.setObject(NSNull(), forKeyedSubscript: "__koalaLastException" as NSString)
                return
            }

            // Truthy check
            let passed: Bool = {
                if let result, !result.isUndefined, !result.isNull {
                    if result.isBoolean { return result.toBool() }
                    return result.toBool() // JS truthiness
                }
                // No return = treat as pass (Postman-style)
                return true
            }()
            capture(TestResult(
                name: name,
                passed: passed,
                failureMessage: passed ? nil : "assertion returned falsy",
                durationMs: duration
            ))
        }

        // expect(actual) — fluent matchers
        let expectFn: @convention(block) (JSValue) -> JSValue = { actual in
            return ScriptingService.makeExpectation(actual: actual, in: actual.context)
        }

        let koala = JSValue(newObjectIn: ctx)
        koala?.setObject(envObj, forKeyedSubscript: "env" as NSString)
        koala?.setObject(gObj, forKeyedSubscript: "globals" as NSString)
        koala?.setObject(reqObj, forKeyedSubscript: "request" as NSString)
        koala?.setObject(respObj, forKeyedSubscript: "response" as NSString)
        koala?.setObject(testFn, forKeyedSubscript: "test" as NSString)
        koala?.setObject(expectFn, forKeyedSubscript: "expect" as NSString)
        ctx.setObject(koala, forKeyedSubscript: "koala" as NSString)
    }

    // MARK: - expect(...) matchers

    private static func makeExpectation(actual: JSValue, in ctx: JSContext?) -> JSValue {
        let obj = JSValue(newObjectIn: ctx)!

        func throwAssert(_ message: String) {
            let err = ctx?.evaluateScript("new Error(\(JSONString(message)))")
            ctx?.exception = err
        }

        let toBe: @convention(block) (JSValue) -> Void = { expected in
            let a = actual.toObject()
            let b = expected.toObject()
            if !ScriptingService.jsEqual(a, b) {
                throwAssert("expected \(ScriptingService.stringify(actual)) toBe \(ScriptingService.stringify(expected))")
            }
        }
        let toEqual: @convention(block) (JSValue) -> Void = { expected in
            let a = actual.toObject()
            let b = expected.toObject()
            if !ScriptingService.deepEqual(a, b) {
                throwAssert("expected \(ScriptingService.stringify(actual)) toEqual \(ScriptingService.stringify(expected))")
            }
        }
        let toContain: @convention(block) (JSValue) -> Void = { expected in
            if actual.isString, let s = actual.toString() {
                let sub = expected.toString() ?? ""
                if !s.contains(sub) {
                    throwAssert("expected \"\(s)\" toContain \"\(sub)\"")
                }
                return
            }
            if actual.isArray {
                let count = Int(actual.forProperty("length").toInt32())
                for i in 0..<count {
                    let item = actual.atIndex(i)
                    if ScriptingService.jsEqual(item?.toObject(), expected.toObject()) { return }
                }
                throwAssert("expected array toContain \(ScriptingService.stringify(expected))")
                return
            }
            throwAssert("toContain only supports string/array")
        }
        let toBeTruthy: @convention(block) () -> Void = {
            if !actual.toBool() {
                throwAssert("expected \(ScriptingService.stringify(actual)) toBeTruthy")
            }
        }
        let toBeGreaterThan: @convention(block) (JSValue) -> Void = { expected in
            let a = actual.toDouble()
            let b = expected.toDouble()
            if !(a > b) {
                throwAssert("expected \(a) toBeGreaterThan \(b)")
            }
        }
        let toMatch: @convention(block) (JSValue) -> Void = { pattern in
            guard let s = actual.toString() else {
                throwAssert("toMatch requires a string actual")
                return
            }
            let patternStr: String
            if pattern.isString {
                patternStr = pattern.toString() ?? ""
            } else {
                // assume RegExp-like; use its .source
                patternStr = pattern.forProperty("source")?.toString() ?? (pattern.toString() ?? "")
            }
            guard let regex = try? NSRegularExpression(pattern: patternStr) else {
                throwAssert("invalid regex: \(patternStr)")
                return
            }
            let range = NSRange(s.startIndex..., in: s)
            if regex.firstMatch(in: s, range: range) == nil {
                throwAssert("expected \"\(s)\" toMatch /\(patternStr)/")
            }
        }

        obj.setObject(toBe, forKeyedSubscript: "toBe" as NSString)
        obj.setObject(toEqual, forKeyedSubscript: "toEqual" as NSString)
        obj.setObject(toContain, forKeyedSubscript: "toContain" as NSString)
        obj.setObject(toBeTruthy, forKeyedSubscript: "toBeTruthy" as NSString)
        obj.setObject(toBeGreaterThan, forKeyedSubscript: "toBeGreaterThan" as NSString)
        obj.setObject(toMatch, forKeyedSubscript: "toMatch" as NSString)
        return obj
    }

    private static func JSONString(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [s], options: [.fragmentsAllowed])
        if let data, let arr = String(data: data, encoding: .utf8), arr.count >= 2 {
            return String(arr.dropFirst().dropLast())
        }
        return "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    // MARK: - Evaluation with timeout

    private func evaluateWithTimeout(script: String, context: JSContext) throws {
        let deadline = Date().addingTimeInterval(executionTimeout)
        let vm = context.virtualMachine
        let deadlineLock = NSLock()
        var finished = false

        // Watchdog: terminate execution if it overruns.
        let watchdog = DispatchQueue.global(qos: .userInitiated)
        watchdog.async {
            while Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
                deadlineLock.lock(); let done = finished; deadlineLock.unlock()
                if done { return }
            }
            // Force-terminate by throwing exception into context
            deadlineLock.lock(); let done = finished; deadlineLock.unlock()
            if !done {
                DispatchQueue.main.async {
                    context.exception = JSValue(object: "Script execution timed out", in: context)
                }
                _ = vm // retain
            }
        }

        context.setObject(NSNull(), forKeyedSubscript: "__koalaLastException" as NSString)
        let result = context.evaluateScript(script)
        deadlineLock.lock(); finished = true; deadlineLock.unlock()

        if let ex = context.exception {
            let msg = ex.toString() ?? "script error"
            context.exception = nil
            if msg.contains("timed out") { throw ScriptingError.timeout }
            throw ScriptingError.runtime(msg)
        }
        _ = result
    }

    // MARK: - Helpers

    private func envDict(_ env: KoalaEnvironment?) -> NSMutableDictionary {
        let d = NSMutableDictionary()
        guard let env else { return d }
        for v in env.variables where v.isEnabled {
            d[v.key] = v.value
        }
        return d
    }

    private func applyEnvDict(_ dict: NSMutableDictionary, into env: inout KoalaEnvironment) {
        for (k, v) in dict {
            guard let key = k as? String else { continue }
            let value = ScriptingService.toString(v)
            if let idx = env.variables.firstIndex(where: { $0.key == key }) {
                env.variables[idx].value = value
            } else {
                env.variables.append(EnvVariable(key: key, value: value, isEnabled: true))
            }
        }
    }

    private func globalsDict(_ globals: [KeyValuePair]) -> NSMutableDictionary {
        let d = NSMutableDictionary()
        for v in globals where v.isEnabled {
            d[v.key] = v.value
        }
        return d
    }

    private func applyGlobalsDict(_ dict: NSMutableDictionary, into globals: inout [KeyValuePair]) {
        for (k, v) in dict {
            guard let key = k as? String else { continue }
            let value = ScriptingService.toString(v)
            if let idx = globals.firstIndex(where: { $0.key == key }) {
                globals[idx].value = value
            } else {
                globals.append(KeyValuePair(key: key, value: value, isEnabled: true))
            }
        }
    }

    fileprivate static func headersDict(_ headers: [KeyValuePair]) -> [String: String] {
        var d: [String: String] = [:]
        for h in headers where h.isEnabled { d[h.key] = h.value }
        return d
    }

    fileprivate static func bodyString(_ body: RequestBody) -> String {
        switch body {
        case .none: return ""
        case .json(let s): return s
        case .raw(let s, _): return s
        case .graphql(let q, let v): return "{\"query\":\(q),\"variables\":\(v)}"
        case .formURLEncoded(let pairs):
            return pairs.filter { $0.isEnabled }.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        case .multipart: return "[multipart]"
        case .binary(let url): return url.path
        }
    }

    fileprivate static func toString(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        if let b = value as? Bool { return b ? "true" : "false" }
        return String(describing: value)
    }

    fileprivate static func stringify(_ value: JSValue) -> String {
        if value.isUndefined { return "undefined" }
        if value.isNull { return "null" }
        if value.isString { return value.toString() ?? "" }
        if value.isBoolean { return value.toBool() ? "true" : "false" }
        if value.isNumber { return value.toNumber()?.stringValue ?? "" }
        if value.isObject {
            if let jsonStr = value.context
                .objectForKeyedSubscript("JSON")?
                .invokeMethod("stringify", withArguments: [value])?.toString() {
                return jsonStr
            }
        }
        return value.toString() ?? ""
    }

    fileprivate static func jsEqual(_ a: Any?, _ b: Any?) -> Bool {
        if a == nil && b == nil { return true }
        if let a = a as? NSNumber, let b = b as? NSNumber { return a == b }
        if let a = a as? String, let b = b as? String { return a == b }
        if let a = a as? String, let b = b as? NSNumber { return a == b.stringValue }
        if let a = a as? NSNumber, let b = b as? String { return a.stringValue == b }
        return String(describing: a) == String(describing: b)
    }

    fileprivate static func deepEqual(_ a: Any?, _ b: Any?) -> Bool {
        if let a = a as? [String: Any], let b = b as? [String: Any] {
            if a.keys.sorted() != b.keys.sorted() { return false }
            for (k, v) in a {
                if !deepEqual(v, b[k]) { return false }
            }
            return true
        }
        if let a = a as? [Any], let b = b as? [Any] {
            if a.count != b.count { return false }
            for i in 0..<a.count {
                if !deepEqual(a[i], b[i]) { return false }
            }
            return true
        }
        return jsEqual(a, b)
    }

    // MARK: - Bag (mutable per-run state shared with JS API closures)

    fileprivate final class Bag {
        var request: KoalaRequest
        let response: KoalaResponse?
        let envVars: NSMutableDictionary
        let globalVars: NSMutableDictionary
        let captureTest: ((TestResult) -> Void)?

        init(
            request: KoalaRequest,
            response: KoalaResponse?,
            envVars: NSMutableDictionary,
            globalVars: NSMutableDictionary,
            captureTest: ((TestResult) -> Void)?
        ) {
            self.request = request
            self.response = response
            self.envVars = envVars
            self.globalVars = globalVars
            self.captureTest = captureTest
        }
    }
}
