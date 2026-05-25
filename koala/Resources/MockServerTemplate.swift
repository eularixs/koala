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
        "@vercel/kv": "^3.0.0"
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

interface EndpointConfig {
  path: string
  method: string
  responseMode: 'staticJSON' | 'dynamicJS'
  staticBody?: string
  dynamicScript?: string
  statusCode: number
  responseHeaders: Array<{ key: string; value: string; isEnabled: boolean }>
  delayMs: number
  isEnabled: boolean
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
}
