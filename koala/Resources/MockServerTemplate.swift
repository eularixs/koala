import Foundation

// MARK: - MockServerTemplate
// Embeds the Next.js 14 template files as Swift string constants.
// These are deployed to Vercel when a new mock server is created.

enum MockServerTemplate {

    // MARK: - package.json

    static let packageJSON = #"""
    {
      "name": "koala-mock-server",
      "version": "0.1.0",
      "private": true,
      "scripts": {
        "dev": "next dev",
        "build": "next build",
        "start": "next start"
      },
      "dependencies": {
        "next": "14.2.29",
        "@vercel/edge-config": "^1.4.0"
      },
      "devDependencies": {
        "typescript": "^5",
        "@types/node": "^20",
        "@types/react": "^18"
      }
    }
    """#

    // MARK: - next.config.js

    static let nextConfig = #"""
    /** @type {import('next').NextConfig} */
    const nextConfig = {
      // No pages router — app router only
    }

    module.exports = nextConfig
    """#

    // MARK: - vercel.json

    static func vercelJSON(serverId: String) -> String {
        #"""
        {
          "env": {
            "KOALA_SERVER_ID": "\#(serverId)"
          },
          "buildCommand": "npm run build",
          "outputDirectory": ".next",
          "framework": "nextjs"
        }
        """#
    }

    /// Shared deployment vercel.json — does not bake serverId since each MockServer
    /// is identified by URL path prefix instead.
    static func vercelJSONShared() -> String {
        #"""
        {
          "buildCommand": "npm run build",
          "outputDirectory": ".next",
          "framework": "nextjs"
        }
        """#
    }

    // MARK: - tsconfig.json

    static let tsconfigJSON = #"""
    {
      "compilerOptions": {
        "lib": ["dom", "dom.iterable", "esnext"],
        "allowJs": true,
        "skipLibCheck": true,
        "strict": true,
        "noEmit": true,
        "esModuleInterop": true,
        "module": "esnext",
        "moduleResolution": "bundler",
        "resolveJsonModule": true,
        "isolatedModules": true,
        "jsx": "preserve",
        "incremental": true,
        "plugins": [{ "name": "next" }],
        "paths": { "@/*": ["./src/*"] }
      },
      "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts"],
      "exclude": ["node_modules"]
    }
    """#

    // MARK: - Route Handler
    // URL routing convention:
    //   Primary:  /api/<path>          — standard Next.js catch-all API route
    //   Alias:    /<projectSlug>/api/<path> — self-documenting slug-prefixed variant
    // Both resolve to the same endpoint by stripping the slug prefix before KV lookup.
    // The Vercel project is dedicated per Koala Project (1:1 mapping), so the slug
    // is redundant but included for clarity in browser/curl usage.

    static func routeTs(serverId: String, projectSlug: String) -> String {
        // NOTE: The dynamic JS eval is intentional — it's a deliberate mock server
        // feature, not untrusted input. The user authors the script in the app.
        // swiftlint:disable line_length
        return #"""
import { kv } from '@vercel/kv'
import { NextRequest, NextResponse } from 'next/server'

const SERVER_ID = process.env.KOALA_SERVER_ID ?? '\#(serverId)'
const PROJECT_SLUG = '\#(projectSlug)'

export const dynamic = 'force-dynamic'

interface KVHeader { key: string; value: string; isEnabled: boolean }
type ConditionSource = 'query' | 'header' | 'bodyJSON' | 'path'
type ConditionOperator = 'equals' | 'notEquals' | 'contains' | 'startsWith' | 'exists' | 'notExists'

interface RuleCondition {
  source: ConditionSource
  key: string
  op: ConditionOperator
  value: string
}

interface ResponseRule {
  id: string
  name: string
  conditions: RuleCondition[]
  statusCode: number
  body: string
  responseHeaders: KVHeader[]
  delayMs: number
  isEnabled: boolean
}

interface EndpointConfig {
  path: string
  method: string
  responseMode: 'staticJSON' | 'dynamicJS'
  staticBody?: string
  dynamicScript?: string
  statusCode: number
  responseHeaders: KVHeader[]
  delayMs: number
  isEnabled: boolean
  rules?: ResponseRule[]
}

function getValueFromJSONPath(obj: unknown, path: string): unknown {
  if (obj == null) return undefined
  const parts = path.split('.').filter(p => p.length > 0)
  let cur: unknown = obj
  for (const p of parts) {
    if (cur == null || typeof cur !== 'object') return undefined
    cur = (cur as Record<string, unknown>)[p]
  }
  return cur
}

function evaluateOperator(op: ConditionOperator, actual: string | undefined, expected: string): boolean {
  switch (op) {
    case 'exists':     return actual !== undefined && actual !== null
    case 'notExists':  return actual === undefined || actual === null
    case 'equals':     return (actual ?? '') === expected
    case 'notEquals':  return (actual ?? '') !== expected
    case 'contains':   return actual !== undefined && actual.includes(expected)
    case 'startsWith': return actual !== undefined && actual.startsWith(expected)
    default:           return false
  }
}

function resolveActual(
  cond: RuleCondition,
  ctx: {
    query: Record<string, string>
    headers: Record<string, string>
    bodyJSON: unknown
    path: string
  }
): string | undefined {
  switch (cond.source) {
    case 'query':    return ctx.query[cond.key]
    case 'header':   return ctx.headers[cond.key.toLowerCase()]
    case 'path':     return ctx.path
    case 'bodyJSON': {
      const v = getValueFromJSONPath(ctx.bodyJSON, cond.key)
      if (v === undefined || v === null) return undefined
      return typeof v === 'string' ? v : JSON.stringify(v)
    }
  }
}

async function handler(req: NextRequest, params: { path: string[] }): Promise<NextResponse> {
  let segments = params.path
  if (segments[0] === PROJECT_SLUG) {
    segments = segments.slice(1)
  }
  const joinedPath = '/' + segments.join('/')
  const method = req.method.toUpperCase()

  const kvKey = `mock:${SERVER_ID}:endpoint:${method}:${joinedPath}`
  let config: EndpointConfig | null = null
  try {
    config = await kv.get<EndpointConfig>(kvKey)
  } catch (e) {
    return NextResponse.json({ error: 'KV lookup failed', detail: String(e) }, { status: 503 })
  }

  if (!config || !config.isEnabled) {
    return NextResponse.json({ error: 'Not found', path: joinedPath, method }, { status: 404 })
  }

  // Build matching context (lazily parse body only if needed)
  const headerMap: Record<string, string> = {}
  req.headers.forEach((value, key) => { headerMap[key.toLowerCase()] = value })
  const queryMap = Object.fromEntries(req.nextUrl.searchParams.entries())

  let bodyJSON: unknown = undefined
  let bodyParsed = false
  const parseBody = async () => {
    if (bodyParsed) return
    bodyParsed = true
    try {
      const text = await req.text()
      bodyJSON = text.length > 0 ? JSON.parse(text) : undefined
    } catch {
      bodyJSON = undefined
    }
  }

  // Evaluate rules in order — first match wins
  const rules = config.rules ?? []
  for (const rule of rules) {
    if (!rule.isEnabled) continue
    const conds = rule.conditions ?? []
    let allMatch = true
    for (const cond of conds) {
      if (cond.source === 'bodyJSON') await parseBody()
      const actual = resolveActual(cond, {
        query: queryMap,
        headers: headerMap,
        bodyJSON,
        path: joinedPath,
      })
      if (!evaluateOperator(cond.op, actual, cond.value)) {
        allMatch = false
        break
      }
    }
    if (allMatch) {
      if (rule.delayMs > 0) {
        await new Promise(resolve => setTimeout(resolve, rule.delayMs))
      }
      const ruleHeaders = new Headers({ 'Content-Type': 'application/json' })
      for (const h of (rule.responseHeaders ?? [])) {
        if (h.isEnabled && h.key) ruleHeaders.set(h.key, h.value)
      }
      return new NextResponse(rule.body ?? '{}', {
        status: rule.statusCode ?? 200,
        headers: ruleHeaders,
      })
    }
  }

  if (config.delayMs > 0) {
    await new Promise(resolve => setTimeout(resolve, config.delayMs))
  }

  const headers = new Headers({ 'Content-Type': 'application/json' })
  for (const h of (config.responseHeaders ?? [])) {
    if (h.isEnabled && h.key) headers.set(h.key, h.value)
  }

  let body: string
  if (config.responseMode === 'dynamicJS' && config.dynamicScript) {
    try {
      const fn = new Function('request', 'env', config.dynamicScript)
      const requestCtx = {
        method,
        path: joinedPath,
        headers: Object.fromEntries(req.headers.entries()),
        searchParams: Object.fromEntries(req.nextUrl.searchParams.entries()),
      }
      const result = await fn(requestCtx, process.env)
      body = typeof result === 'string' ? result : JSON.stringify(result)
    } catch (e) {
      return NextResponse.json({ error: 'Script error', detail: String(e) }, { status: 500 })
    }
  } else {
    body = config.staticBody ?? '{}'
  }

  return new NextResponse(body, { status: config.statusCode ?? 200, headers })
}

export async function GET(req: NextRequest, { params }: { params: { path: string[] } }) {
  return handler(req, params)
}
export async function POST(req: NextRequest, { params }: { params: { path: string[] } }) {
  return handler(req, params)
}
export async function PUT(req: NextRequest, { params }: { params: { path: string[] } }) {
  return handler(req, params)
}
export async function PATCH(req: NextRequest, { params }: { params: { path: string[] } }) {
  return handler(req, params)
}
export async function DELETE(req: NextRequest, { params }: { params: { path: string[] } }) {
  return handler(req, params)
}
export async function OPTIONS(req: NextRequest, { params }: { params: { path: string[] } }) {
  return handler(req, params)
}
"""#
        // swiftlint:enable line_length
    }

    /// Shared route.ts — reads endpoint config from Edge Config.
    /// First URL segment is the mock-server slug (namespace), rest is the endpoint path.
    /// e.g. /dev-mock/api/users → serverSlug="dev-mock" path="/api/users"
    /// Falls back to project slug for backward compat.
    static func routeTsShared(projectSlug: String) -> String {
        // swiftlint:disable line_length
        return #"""
import { get } from '@vercel/edge-config'
import { NextRequest, NextResponse } from 'next/server'

const PROJECT_SLUG = '\#(projectSlug)'

export const dynamic = 'force-dynamic'

interface KVHeader { key: string; value: string; isEnabled: boolean }
type ConditionSource = 'query' | 'header' | 'bodyJSON' | 'path'
type ConditionOperator = 'equals' | 'notEquals' | 'contains' | 'startsWith' | 'exists' | 'notExists'

interface RuleCondition { source: ConditionSource; key: string; op: ConditionOperator; value: string }
interface ResponseRule {
  id: string
  name: string
  conditions: RuleCondition[]
  statusCode: number
  body: string
  responseHeaders: KVHeader[]
  delayMs: number
  isEnabled: boolean
}
interface EndpointConfig {
  path: string
  method: string
  responseMode: 'staticJSON' | 'dynamicJS'
  staticBody?: string
  dynamicScript?: string
  statusCode: number
  responseHeaders: KVHeader[]
  delayMs: number
  isEnabled: boolean
  rules?: ResponseRule[]
}

function sanitizeKey(s: string): string {
  let out = ''
  for (const ch of s) {
    if (/[a-zA-Z0-9_-]/.test(ch)) out += ch
    else out += '_'
  }
  return out
}

function getValueFromJSONPath(obj: unknown, path: string): unknown {
  if (obj == null) return undefined
  const parts = path.split('.').filter(p => p.length > 0)
  let cur: unknown = obj
  for (const p of parts) {
    if (cur == null || typeof cur !== 'object') return undefined
    cur = (cur as Record<string, unknown>)[p]
  }
  return cur
}

function evaluateOperator(op: ConditionOperator, actual: string | undefined, expected: string): boolean {
  switch (op) {
    case 'exists':     return actual !== undefined && actual !== null
    case 'notExists':  return actual === undefined || actual === null
    case 'equals':     return (actual ?? '') === expected
    case 'notEquals':  return (actual ?? '') !== expected
    case 'contains':   return actual !== undefined && actual.includes(expected)
    case 'startsWith': return actual !== undefined && actual.startsWith(expected)
    default:           return false
  }
}

function resolveActual(
  cond: RuleCondition,
  ctx: { query: Record<string, string>; headers: Record<string, string>; bodyJSON: unknown; path: string }
): string | undefined {
  switch (cond.source) {
    case 'query':    return ctx.query[cond.key]
    case 'header':   return ctx.headers[cond.key.toLowerCase()]
    case 'path':     return ctx.path
    case 'bodyJSON': {
      const v = getValueFromJSONPath(ctx.bodyJSON, cond.key)
      if (v === undefined || v === null) return undefined
      return typeof v === 'string' ? v : JSON.stringify(v)
    }
  }
}

async function handler(req: NextRequest, params: { path: string[] }): Promise<NextResponse> {
  const segs = params.path ?? []
  const joinedPath = '/' + segs.join('/')
  const method = req.method.toUpperCase()

  const kvKey = `mock_${method}_${sanitizeKey(joinedPath)}`
  let config: EndpointConfig | undefined
  try {
    config = await get<EndpointConfig>(kvKey)
  } catch (e) {
    return NextResponse.json({ error: 'Edge Config lookup failed', detail: String(e) }, { status: 503 })
  }
  if (!config || !config.isEnabled) {
    return NextResponse.json({ error: 'Not found', key: kvKey, path: joinedPath, method }, { status: 404 })
  }

  const headerMap: Record<string, string> = {}
  req.headers.forEach((value, key) => { headerMap[key.toLowerCase()] = value })
  const queryMap = Object.fromEntries(req.nextUrl.searchParams.entries())

  let bodyJSON: unknown = undefined
  let bodyParsed = false
  const parseBody = async () => {
    if (bodyParsed) return
    bodyParsed = true
    try {
      const text = await req.text()
      bodyJSON = text.length > 0 ? JSON.parse(text) : undefined
    } catch {
      bodyJSON = undefined
    }
  }

  const rules = config.rules ?? []
  for (const rule of rules) {
    if (!rule.isEnabled) continue
    let allMatch = true
    for (const cond of (rule.conditions ?? [])) {
      if (cond.source === 'bodyJSON') await parseBody()
      const actual = resolveActual(cond, { query: queryMap, headers: headerMap, bodyJSON, path: joinedPath })
      if (!evaluateOperator(cond.op, actual, cond.value)) { allMatch = false; break }
    }
    if (allMatch) {
      if (rule.delayMs > 0) await new Promise(r => setTimeout(r, rule.delayMs))
      const h = new Headers({ 'Content-Type': 'application/json' })
      for (const hh of (rule.responseHeaders ?? [])) {
        if (hh.isEnabled && hh.key) h.set(hh.key, hh.value)
      }
      return new NextResponse(rule.body ?? '{}', { status: rule.statusCode ?? 200, headers: h })
    }
  }

  if (config.delayMs > 0) await new Promise(r => setTimeout(r, config.delayMs))
  const h = new Headers({ 'Content-Type': 'application/json' })
  for (const hh of (config.responseHeaders ?? [])) {
    if (hh.isEnabled && hh.key) h.set(hh.key, hh.value)
  }

  let body: string
  if (config.responseMode === 'dynamicJS' && config.dynamicScript) {
    try {
      const fn = new Function('request', 'env', config.dynamicScript)
      const ctx = {
        method, path: joinedPath,
        headers: Object.fromEntries(req.headers.entries()),
        searchParams: queryMap
      }
      const result = await fn(ctx, process.env)
      body = typeof result === 'string' ? result : JSON.stringify(result)
    } catch (e) {
      return NextResponse.json({ error: 'Script error', detail: String(e) }, { status: 500 })
    }
  } else {
    body = config.staticBody ?? '{}'
  }
  return new NextResponse(body, { status: config.statusCode ?? 200, headers: h })
}

export async function GET(req: NextRequest, { params }: { params: { path: string[] } }) { return handler(req, params) }
export async function POST(req: NextRequest, { params }: { params: { path: string[] } }) { return handler(req, params) }
export async function PUT(req: NextRequest, { params }: { params: { path: string[] } }) { return handler(req, params) }
export async function PATCH(req: NextRequest, { params }: { params: { path: string[] } }) { return handler(req, params) }
export async function DELETE(req: NextRequest, { params }: { params: { path: string[] } }) { return handler(req, params) }
export async function OPTIONS(req: NextRequest, { params }: { params: { path: string[] } }) { return handler(req, params) }
"""#
        // swiftlint:enable line_length
    }
}
