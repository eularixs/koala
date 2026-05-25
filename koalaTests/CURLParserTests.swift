import XCTest
@testable import koala

final class CURLParserTests: XCTestCase {

    // MARK: - 1. Simple GET

    func test_simpleGET() throws {
        let req = try CURLParser.parse("curl https://api.example.com/users")
        XCTAssertEqual(req.url, "https://api.example.com/users")
        XCTAssertEqual(req.method.rawValue, "GET")
        XCTAssertTrue(req.headers.isEmpty)
        XCTAssertEqual(req.body, .none)
    }

    // MARK: - 2. GET with explicit method and headers

    func test_getWithHeaders() throws {
        let input = "curl -X GET https://api.example.com/items -H 'Accept: application/json' -H 'X-Custom: value'"
        let req = try CURLParser.parse(input)
        XCTAssertEqual(req.method.rawValue, "GET")
        XCTAssertEqual(req.url, "https://api.example.com/items")
        XCTAssertEqual(req.headers.count, 2)
        XCTAssertEqual(req.headers[0].key, "Accept")
        XCTAssertEqual(req.headers[0].value, "application/json")
        XCTAssertEqual(req.headers[1].key, "X-Custom")
        XCTAssertEqual(req.headers[1].value, "value")
    }

    // MARK: - 3. POST with -d JSON

    func test_postWithDataJSON() throws {
        let input = #"curl -X POST https://api.example.com/users -H "Content-Type: application/json" -d "{\"name\":\"Bob\"}""#
        let req = try CURLParser.parse(input)
        XCTAssertEqual(req.method.rawValue, "POST")
        guard case .json(let body) = req.body else {
            return XCTFail("Expected JSON body, got \(req.body)")
        }
        XCTAssertTrue(body.contains("Bob"))
    }

    // MARK: - 4. POST with --data-raw (non-JSON plain text)

    func test_postWithDataRaw() throws {
        let input = "curl -X POST https://example.com/form --data-raw 'name=Alice&age=30'"
        let req = try CURLParser.parse(input)
        XCTAssertEqual(req.method.rawValue, "POST")
        guard case .raw(let content, _) = req.body else {
            return XCTFail("Expected raw body, got \(req.body)")
        }
        XCTAssertEqual(content, "name=Alice&age=30")
    }

    // MARK: - 5. Basic auth via -u

    func test_basicAuthViaUser() throws {
        let input = "curl -u admin:secret123 https://api.example.com/protected"
        let req = try CURLParser.parse(input)
        guard case .basic(let username, let password) = req.auth else {
            return XCTFail("Expected basic auth, got \(req.auth)")
        }
        XCTAssertEqual(username, "admin")
        XCTAssertEqual(password, "secret123")
    }

    // MARK: - 6. Multi-line backslash-continued curl

    func test_multilineBackslashContinuation() throws {
        let input = """
        curl \\
          -X POST \\
          https://api.example.com/data \\
          -H 'Authorization: Bearer tok123' \\
          -H 'Content-Type: application/json' \\
          -d '{"key": "value"}'
        """
        let req = try CURLParser.parse(input)
        XCTAssertEqual(req.method.rawValue, "POST")
        XCTAssertEqual(req.url, "https://api.example.com/data")
        let authHeader = req.headers.first(where: { $0.key == "Authorization" })
        XCTAssertNotNil(authHeader)
        XCTAssertEqual(authHeader?.value, "Bearer tok123")
        guard case .json(let body) = req.body else {
            return XCTFail("Expected JSON body, got \(req.body)")
        }
        XCTAssertTrue(body.contains("value"))
    }

    // MARK: - 7. -G with -d appends data as query string

    func test_GFlagWithData() throws {
        let input = "curl -G https://api.example.com/search -d 'q=hello&page=1'"
        let req = try CURLParser.parse(input)
        XCTAssertEqual(req.method.rawValue, "GET")
        XCTAssertTrue(req.url.contains("q=hello"))
        XCTAssertEqual(req.body, .none)
    }

    // MARK: - 8. No URL throws

    func test_noURL_throws() {
        XCTAssertThrowsError(try CURLParser.parse("curl -X POST")) { error in
            guard case ImportError.malformed = error else {
                XCTFail("Expected ImportError.malformed, got \(error)")
                return
            }
        }
    }

    // MARK: - 9. User-Agent header

    func test_userAgent() throws {
        let input = "curl -A 'MyApp/1.0' https://example.com"
        let req = try CURLParser.parse(input)
        let ua = req.headers.first(where: { $0.key == "User-Agent" })
        XCTAssertEqual(ua?.value, "MyApp/1.0")
    }

    // MARK: - 10. POST inferred without explicit -X

    func test_inferredPOSTFromBody() throws {
        let input = "curl https://api.example.com/create -d '{\"x\":1}'"
        let req = try CURLParser.parse(input)
        XCTAssertEqual(req.method.rawValue, "POST")
    }

    // MARK: - ANSI-C quoting ($'...') tests

    // 11. $'...' with \! escape decodes to literal '!'
    func test_ansiC_exclamationMark() throws {
        // The Swift string below presents the parser with:
        //   --data-raw $'{"email":"x@x","password":"StrongPass\!"}'
        // where \! inside $'...' must decode to '!'
        let input = #"curl -X POST https://api.example.com/login --data-raw $'{"email":"x@x","password":"StrongPass\!"}'  "#
        let req = try CURLParser.parse(input)
        XCTAssertEqual(req.method.rawValue, "POST")
        switch req.body {
        case .json(let body):
            XCTAssertTrue(body.contains("StrongPass!"), "Body should contain literal '!'")
        case .raw(let body, _):
            XCTAssertTrue(body.contains("StrongPass!"), "Body should contain literal '!'")
        default:
            XCTFail("Expected json or raw body, got \(req.body)")
        }
    }

    // 12. $'...' with \n escape — body has actual newline character
    func test_ansiC_newlineEscape() throws {
        let input = "curl -X POST https://example.com/data --data-raw $'line1\\nline2'"
        let req = try CURLParser.parse(input)
        switch req.body {
        case .raw(let body, _):
            XCTAssertTrue(body.contains("\n"), "Body should contain actual newline")
            XCTAssertTrue(body.contains("line1"))
            XCTAssertTrue(body.contains("line2"))
        default:
            XCTFail("Expected raw body, got \(req.body)")
        }
    }

    // 13. $'...' with \t escape — body has actual tab character
    func test_ansiC_tabEscape() throws {
        let input = "curl -X POST https://example.com/data --data-raw $'tab\\there'"
        let req = try CURLParser.parse(input)
        switch req.body {
        case .raw(let body, _):
            XCTAssertTrue(body.contains("\t"), "Body should contain actual tab")
            XCTAssertTrue(body.contains("tab"))
            XCTAssertTrue(body.contains("here"))
        default:
            XCTFail("Expected raw body, got \(req.body)")
        }
    }

    // 14. Mixed normal single-quoted header and $'...' body in same command
    func test_ansiC_mixedWithNormalQuotes() throws {
        let input = "curl -X POST https://api.example.com/upload -H 'x: y' --data-raw $'hello\\nworld'"
        let req = try CURLParser.parse(input)
        XCTAssertEqual(req.method.rawValue, "POST")
        let xHeader = req.headers.first(where: { $0.key == "x" })
        XCTAssertNotNil(xHeader, "Should have header 'x'")
        XCTAssertEqual(xHeader?.value, "y")
        switch req.body {
        case .raw(let body, _):
            XCTAssertTrue(body.contains("\n"), "Body should contain actual newline from $'...'")
        default:
            XCTFail("Expected raw body, got \(req.body)")
        }
    }
}
