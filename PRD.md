# 🐨 Koala — Product Requirements Document (PRD)
**Version:** 1.0  
**Status:** Ready for Agent Execution  
**Platform:** macOS (native SwiftUI), backend via Vercel  

---

## 1. Executive Summary

Koala adalah native macOS API client yang menggabungkan kemampuan HTTP testing (seperti Postman), API Mock Server berbasis Vercel, dan sistem kolaborasi tim berbasis push/pull (bukan real-time sync). Seluruh UI mengikuti macOS Human Interface Guidelines — tidak ada Electron, tidak ada WebView wrapper.

---

## 2. Tech Stack

| Layer | Teknologi |
|---|---|
| macOS App | Swift 5.9+, SwiftUI, AppKit (bila perlu) |
| Local Storage | SwiftData (iOS 17+ / macOS 14+) |
| Networking (client) | URLSession + async/await |
| Auth Vercel | OAuth 2.0 via Vercel SSO |
| Mock Server Runtime | Next.js 14 App Router (deployed ke Vercel) |
| Mock Config Storage | Vercel KV (Redis) |
| Collaboration Storage | Vercel KV |
| Keychain | Security framework (token storage) |
| Code Editor | CodeMirror via WKWebView (JSON/JS editor) |
| Import/Export | Swift Codable + JSONSerialization |

---

## 3. Arsitektur Sistem

```
┌─────────────────────────────────────────────────┐
│                 KOALA macOS App                 │
│                                                 │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐  │
│  │ HTTP     │  │  Mock    │  │ Collaboration │  │
│  │ Client   │  │ Builder  │  │  (Push/Pull)  │  │
│  └────┬─────┘  └────┬─────┘  └──────┬───────┘  │
│       │              │               │           │
│  ┌────▼──────────────▼───────────────▼───────┐  │
│  │            VercelService.swift             │  │
│  │        (OAuth Token via Keychain)          │  │
│  └────────────────────┬───────────────────────┘  │
└───────────────────────┼─────────────────────────┘
                        │ Vercel REST API
          ┌─────────────┴──────────────┐
          │                            │
  ┌───────▼──────┐            ┌────────▼────────┐
  │  Vercel KV   │            │  Vercel Deploy  │
  │ (Collections │            │  (Mock Server   │
  │  & Team Sync)│            │   Next.js App)  │
  └──────────────┘            └─────────────────┘
                                       │
                              ┌────────▼────────┐
                              │  Mock Server    │
                              │  Public URL:    │
                              │  koala-xxx.     │
                              │  vercel.app     │
                              └─────────────────┘
```

### Bagaimana Mock Server Bekerja

1. User mendefinisikan endpoint di app (path, method, response JSON/JS)
2. App menyimpan config ke **Vercel KV** via Vercel API
3. Mock Server Next.js di Vercel membaca KV setiap request masuk
4. Tidak perlu redeploy untuk update response — cukup update KV
5. Redeploy hanya saat pertama setup atau perubahan struktur server

### Bagaimana Kolaborasi Bekerja

```
User A                          Vercel KV                        User B
  │                                 │                               │
  ├──[Edit collection lokal]         │                               │
  │                                 │                               │
  ├──[Tekan "Push to Team"]──────────►                               │
  │                      upload JSON │                               │
  │                      + timestamp │                               │
  │                                 │                               │
  │                                 │◄──[Tekan "Pull from Team"]────┤
  │                                 │   download JSON               │
  │                                 │                               │
  │                          [Conflict?]──────────────────────────► │
  │                              show diff + merge UI               │
```

---

## 4. Fitur Lengkap

### 4.1 HTTP Client (Core)

#### Request Builder
- [ ] Method selector: GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS, CONNECT, TRACE, + custom
- [ ] URL bar dengan autocomplete dari history
- [ ] Tabs untuk multiple request sekaligus (seperti browser)
- [ ] Query params editor (key-value + raw)
- [ ] Headers editor (key-value, dengan autocomplete common headers)
- [ ] Authorization:
  - [ ] No Auth
  - [ ] Bearer Token
  - [ ] Basic Auth
  - [ ] API Key (header/query)
  - [ ] OAuth 2.0 (authorization code flow)
  - [ ] AWS Signature
- [ ] Body types:
  - [ ] JSON (dengan syntax highlighting)
  - [ ] Form URL-encoded
  - [ ] Multipart/form-data (dengan file upload)
  - [ ] Raw (text, XML, HTML, binary)
  - [ ] GraphQL (query + variables editor)
  - [ ] None
- [ ] Pre-request Script (JavaScript, di-run di WKWebView sandbox)
- [ ] Post-response Script / Test Script
- [ ] Send button + keyboard shortcut ⌘↵

#### Response Viewer
- [ ] Status code + badge warna (2xx hijau, 4xx kuning, 5xx merah)
- [ ] Response time, size, status text
- [ ] Body viewer: JSON tree collapsible, raw, preview (HTML), image preview
- [ ] Headers viewer
- [ ] Cookies viewer
- [ ] Save response ke file
- [ ] Copy as cURL
- [ ] Timeline/waterfall (DNS, connect, TLS, TTFB, download)

#### History
- [ ] Simpan semua request terkirim (max 500 lokal)
- [ ] Filter by method, status, URL
- [ ] Replay dari history
- [ ] Hapus history (per item / semua)

### 4.2 Collections & Environment

#### Collections
- [ ] Tree view di sidebar (folder + request)
- [ ] Drag & drop untuk atur ulang
- [ ] Color label per folder/request
- [ ] Duplicate collection/folder/request
- [ ] Rename inline (double click)
- [ ] Search di dalam collection
- [ ] Collection-level auth (inherited ke child)
- [ ] Collection-level variables

#### Environments
- [ ] Create multiple environments (Dev, Staging, Production, dll)
- [ ] Variable: `{{variableName}}` syntax di URL, headers, body
- [ ] Environment switcher di toolbar
- [ ] Global variables (lintas semua environment)
- [ ] Secret variables (tersimpan di Keychain, tidak ikut export)

#### Collection Runner
- [ ] Run semua request di folder/collection secara berurutan
- [ ] Set delay antar request
- [ ] Iterasi dengan data dari CSV/JSON (data-driven testing)
- [ ] Summary hasil run (passed/failed berdasarkan test script)
- [ ] Export hasil run sebagai JSON/CSV

### 4.3 Import & Export

#### Import (Parse & convert ke format Koala internal)
- [ ] **Postman Collection v2.0 / v2.1** (.json)
- [ ] **Insomnia v4** (.json / .yaml)
- [ ] **Apidog** (.json)
- [ ] **OpenAPI 3.x** (.json / .yaml)
- [ ] **Swagger 2.0** (.json / .yaml)
- [ ] **HAR** (HTTP Archive)
- [ ] **cURL** command (paste → parse)

#### Export
- [ ] Postman Collection v2.1
- [ ] OpenAPI 3.0
- [ ] Koala native format (.koala.json)
- [ ] Markdown docs (generate dari collection)

### 4.4 Mock Server (Vercel-powered)

#### Konsep
Setiap "Mock Server" adalah satu Vercel project yang berisi:
- Next.js app dengan catch-all route `/api/[...path]`
- Endpoint configs disimpan di Vercel KV
- Tidak butuh redeploy untuk update response, cukup update KV

#### Setup Flow
```
1. User klik "New Mock Server"
2. Koala buka OAuth Vercel (jika belum login)
3. Koala buat Vercel Project baru via API:
   POST https://api.vercel.com/v9/projects
4. Deploy template Next.js mock server:
   POST https://api.vercel.com/v13/deployments
   (source: GitHub template atau tarball upload)
5. Vercel return URL: https://koala-mock-[hash].vercel.app
6. URL tersimpan di local + KV
```

#### Mock Endpoint Builder
- [ ] Path: `/api/users`, `/api/users/:id`
- [ ] Method: GET, POST, PUT, PATCH, DELETE (multi-select per path)
- [ ] Response Mode:
  - **Static JSON**: input JSON langsung, disimpan ke KV
  - **Dynamic (JS Logic)**: tulis JS function, dieksekusi di Vercel Edge
    ```javascript
    // Contoh dynamic response
    export default function handler(req) {
      if (req.params.id === "1") {
        return { id: 1, name: "Budi" }
      }
      return { error: "Not found" }, 404
    }
    ```
- [ ] Status code (default 200)
- [ ] Response headers custom
- [ ] Delay simulation (ms)
- [ ] Conditional responses berdasarkan request body/query

#### Simpan & Deploy
- **"Simpan"** = update Vercel KV (instant, tanpa redeploy)
- **"Deploy Ulang"** = trigger Vercel deployment baru (untuk perubahan logic JS)
- Status indicator: 🟢 Live / 🟡 Deploying / 🔴 Error
- Log deployment di in-app panel

#### Mock Server Manager
- [ ] List semua mock servers milik user
- [ ] Start/pause (Vercel tidak support pause, tapi bisa disable via KV flag)
- [ ] Copy URL
- [ ] Delete (hapus Vercel project via API)
- [ ] Environment override untuk mock

### 4.5 Collaboration (Push/Pull via Vercel KV)

#### Konsep
- Tidak ada WebSocket/real-time sync
- Berbasis **manual push/pull** — mirip Git workflow
- Storage: Vercel KV (namespace per workspace)

#### Workspace
- [ ] Buat workspace baru → membuat KV namespace di Vercel
- [ ] Invite member: share Workspace ID + password (simple auth)
- [ ] Member roles: Owner, Editor, Viewer

#### Push to Team
```
User klik "Push" →
  Koala serialize collection ke JSON →
  Upload ke KV: workspace:{id}:collection:{collectionId}
  + metadata: { author, timestamp, message }
```
- [ ] Input "commit message" sebelum push (opsional)
- [ ] Konfirmasi jika ada perubahan yang akan ditimpa

#### Pull from Team
```
User klik "Pull" →
  Download dari KV →
  Bandingkan dengan versi lokal →
  Jika sama: "Already up to date" →
  Jika beda: tampilkan diff UI →
  User pilih: Accept theirs / Keep mine / Merge manual
```

#### Conflict Resolution UI
- Side-by-side diff viewer (Local vs Remote)
- Per-request level conflict (bukan per file)
- "Accept All Remote" / "Keep All Local" / "Merge" per item

#### Version History
- [ ] Simpan 20 versi terakhir di KV (dengan timestamp + author)
- [ ] Rollback ke versi sebelumnya

### 4.6 Vercel Integration

#### Auth
- [ ] OAuth 2.0 flow:
  - Buka browser ke `https://vercel.com/oauth/authorize?...`
  - Redirect ke `koala://oauth/callback`
  - Token disimpan di macOS Keychain (bukan UserDefaults)
- [ ] Token refresh otomatis
- [ ] Logout (hapus token dari Keychain)
- [ ] Tampilkan info akun: nama, email, team

#### Vercel API yang Digunakan
```
POST   /v9/projects                    → Create mock server project
POST   /v13/deployments               → Deploy Next.js template
GET    /v9/projects                    → List user's projects
DELETE /v9/projects/{id}              → Delete project
GET    /v6/deployments                 → List deployments
POST   /v1/edge-config               → (alternatif KV untuk config)
KV API: set/get/delete/list          → Mock config & collaboration
```

---

## 5. UI/UX Design

### Design Principles
- Mengikuti **macOS Human Interface Guidelines** ketat
- Gunakan native components: `NSOutlineView`, `NSSplitView`, `NSToolbar`
- Support **Dark Mode** dan **Light Mode**
- Support **macOS Accent Colors**
- **Sidebar** kiri: Collections/Environments/Mock Servers
- **Main area**: Request editor + Response
- **Inspector** kanan (opsional, bisa collapse)

### Layout Utama
```
┌─────────────────────────────────────────────────────────────┐
│   toolbar: [Koala logo] [workspace picker] ... [vercel badge]│
├──────────────┬──────────────────────────────┬───────────────┤
│  SIDEBAR     │  REQUEST EDITOR               │  INSPECTOR    │
│              │                               │  (collapsible)│
│  ▾ Collections│  [GET ▾] [URL bar        ] [Send]│           │
│    ▾ Users   │  ─────────────────────────    │  Response     │
│      GET /   │  Params │ Headers │ Body │Auth│  headers,     │
│      POST /  │                               │  cookies,     │
│    ▾ Auth    │  [body editor area]           │  timeline     │
│  ────────    │                               │               │
│  Environments│  ─────────────────────────    │               │
│  ────────    │  RESPONSE                     │               │
│  Mock Servers│  200 OK · 124ms · 1.2KB       │               │
│              │  Body │ Headers │ Cookies      │               │
│              │  [JSON tree viewer]           │               │
└──────────────┴──────────────────────────────┴───────────────┘
```

### Mock Server UI
```
┌─────────────────────────────────────────────────────────────┐
│  Mock Servers > "My API Mock"  [🟢 Live] [Copy URL] [Deploy]│
├─────────────────────────────────────────────────────────────┤
│  URL: https://koala-mock-abc123.vercel.app                  │
│                                                             │
│  + Add Endpoint                                             │
│  ────────────────────────────────────────────────────────── │
│  GET    /api/users           [Static JSON] [Edit] [Delete]  │
│  POST   /api/users           [Static JSON] [Edit] [Delete]  │
│  GET    /api/users/:id       [Dynamic JS ] [Edit] [Delete]  │
│  ────────────────────────────────────────────────────────── │
│                               [Simpan ke Vercel ▸]          │
└─────────────────────────────────────────────────────────────┘
```

---

## 6. Data Models (Swift)

```swift
// MARK: - Core Models

struct KoalaRequest: Identifiable, Codable {
    var id: UUID
    var name: String
    var method: HTTPMethod
    var url: String
    var queryParams: [KeyValuePair]
    var headers: [KeyValuePair]
    var auth: AuthConfig
    var body: RequestBody
    var preRequestScript: String?
    var testScript: String?
    var createdAt: Date
    var updatedAt: Date
}

struct Collection: Identifiable, Codable {
    var id: UUID
    var name: String
    var color: String?
    var items: [CollectionItem]  // recursive: folder or request
    var auth: AuthConfig?
    var variables: [KeyValuePair]
}

enum CollectionItem: Codable {
    case folder(Folder)
    case request(KoalaRequest)
}

struct Environment: Identifiable, Codable {
    var id: UUID
    var name: String
    var variables: [EnvVariable]
}

struct EnvVariable: Codable {
    var key: String
    var value: String
    var isSecret: Bool  // secret → disimpan di Keychain
    var isEnabled: Bool
}

// MARK: - Mock Server Models

struct MockServer: Identifiable, Codable {
    var id: UUID
    var name: String
    var vercelProjectId: String
    var deploymentURL: String
    var endpoints: [MockEndpoint]
    var status: MockServerStatus
    var createdAt: Date
}

enum MockServerStatus: String, Codable {
    case live, deploying, error, notDeployed
}

struct MockEndpoint: Identifiable, Codable {
    var id: UUID
    var path: String           // e.g., "/api/users/:id"
    var method: HTTPMethod
    var responseMode: ResponseMode
    var staticResponse: StaticResponse?
    var dynamicScript: String?  // JavaScript
    var statusCode: Int
    var responseHeaders: [KeyValuePair]
    var delayMs: Int
    var isEnabled: Bool
}

enum ResponseMode: String, Codable {
    case staticJSON, dynamicJS
}

struct StaticResponse: Codable {
    var body: String  // raw JSON string
}

// MARK: - Collaboration

struct Workspace: Identifiable, Codable {
    var id: UUID
    var name: String
    var kvNamespace: String  // Vercel KV namespace
    var members: [WorkspaceMember]
    var lastSyncedAt: Date?
}

struct WorkspaceMember: Codable {
    var userId: String
    var role: MemberRole
    var joinedAt: Date
}

enum MemberRole: String, Codable {
    case owner, editor, viewer
}

struct SyncPayload: Codable {
    var workspaceId: String
    var author: String
    var message: String?
    var timestamp: Date
    var collections: [Collection]
    var environments: [Environment]
    var mockServers: [MockServer]
    var version: Int
}
```

---

## 7. Services Architecture

### VercelService.swift
```swift
class VercelService: ObservableObject {
    // Auth
    func startOAuthFlow() async throws -> VercelToken
    func refreshToken() async throws
    func logout()
    func getCurrentUser() async throws -> VercelUser
    
    // Projects
    func createProject(name: String) async throws -> VercelProject
    func deleteProject(id: String) async throws
    func listProjects() async throws -> [VercelProject]
    
    // Deployments
    func deployMockServer(projectId: String, template: MockServerTemplate) async throws -> Deployment
    func getDeploymentStatus(id: String) async throws -> DeploymentStatus
    
    // KV Operations
    func kvSet(key: String, value: Codable) async throws
    func kvGet<T: Codable>(key: String, type: T.Type) async throws -> T?
    func kvDelete(key: String) async throws
    func kvList(prefix: String) async throws -> [String]
}
```

### MockServerService.swift
```swift
class MockServerService: ObservableObject {
    // Setup
    func createMockServer(name: String) async throws -> MockServer
    func deleteMockServer(id: UUID) async throws
    
    // Endpoint Management
    func saveEndpointToVercel(endpoint: MockEndpoint, serverId: UUID) async throws
    // → serialize endpoint → PUT ke Vercel KV:
    // key: "mock:{serverId}:endpoint:{endpointId}"
    
    func saveAllEndpoints(serverId: UUID) async throws
    // → loop semua endpoints → batch update KV
    
    func deployServer(id: UUID) async throws
    // → trigger new Vercel deployment (untuk JS logic changes)
    
    func getServerLogs(id: UUID) async throws -> [LogEntry]
}
```

### CollaborationService.swift
```swift
class CollaborationService: ObservableObject {
    // Workspace
    func createWorkspace(name: String) async throws -> Workspace
    func joinWorkspace(id: String, password: String) async throws -> Workspace
    
    // Sync
    func push(workspace: Workspace, message: String?) async throws
    // → serialize → upload ke KV: "workspace:{id}:latest"
    // → tambah ke history: "workspace:{id}:history:{timestamp}"
    
    func pull(workspace: Workspace) async throws -> SyncPayload
    // → download dari KV → return payload untuk di-merge
    
    func getVersionHistory(workspaceId: String) async throws -> [SyncVersion]
    func rollback(workspaceId: String, version: Int) async throws -> SyncPayload
    
    // Conflict
    func detectConflicts(local: SyncPayload, remote: SyncPayload) -> [Conflict]
    func merge(local: SyncPayload, remote: SyncPayload, resolution: ConflictResolution) -> SyncPayload
}
```

### ImportExportService.swift
```swift
class ImportExportService {
    // Import
    func importPostman(url: URL) throws -> [Collection]
    func importInsomnia(url: URL) throws -> [Collection]
    func importApidog(url: URL) throws -> [Collection]
    func importOpenAPI(url: URL) throws -> [Collection]
    func importSwagger(url: URL) throws -> [Collection]
    func importHAR(url: URL) throws -> [Collection]
    func importFromCURL(string: String) throws -> KoalaRequest
    
    // Export
    func exportToPostman(collections: [Collection]) throws -> Data
    func exportToOpenAPI(collections: [Collection]) throws -> Data
    func exportToKoalaFormat(workspace: Workspace) throws -> Data
    func exportToMarkdown(collections: [Collection]) throws -> String
}
```

---

## 8. Next.js Mock Server Template

File yang di-deploy ke Vercel:

```
koala-mock-template/
├── package.json
├── vercel.json
├── src/
│   └── app/
│       └── api/
│           └── [...path]/
│               └── route.ts
```

### route.ts (catch-all handler)
```typescript
import { kv } from '@vercel/kv'

export async function handler(request: Request, { params }: { params: { path: string[] } }) {
  const path = '/' + params.path.join('/')
  const method = request.method
  const serverId = process.env.KOALA_SERVER_ID!
  
  // Load endpoint config dari KV
  const key = `mock:${serverId}:endpoint:${method}:${path}`
  const config = await kv.get<EndpointConfig>(key)
  
  if (!config || !config.isEnabled) {
    return Response.json({ error: 'Endpoint not found' }, { status: 404 })
  }
  
  // Simulate delay
  if (config.delayMs > 0) {
    await new Promise(r => setTimeout(r, config.delayMs))
  }
  
  // Dynamic JS response
  if (config.responseMode === 'dynamicJS') {
    const fn = new Function('req', 'params', config.dynamicScript!)
    const [body, status] = fn(request, params) ?? [{}, 200]
    return Response.json(body, { 
      status: status ?? config.statusCode,
      headers: Object.fromEntries(config.responseHeaders.map(h => [h.key, h.value]))
    })
  }
  
  // Static JSON response
  return Response.json(JSON.parse(config.staticResponse?.body ?? '{}'), {
    status: config.statusCode,
    headers: Object.fromEntries(config.responseHeaders.map(h => [h.key, h.value]))
  })
}

export const GET = handler
export const POST = handler
export const PUT = handler
export const PATCH = handler
export const DELETE = handler
```

---

## 9. Project Structure (Xcode)

```
Koala.xcodeproj
Koala/
├── KoalaApp.swift                  # @main entry point
├── AppDelegate.swift               # NSApplicationDelegate
│
├── Models/
│   ├── KoalaRequest.swift
│   ├── Collection.swift
│   ├── Environment.swift
│   ├── MockServer.swift
│   ├── MockEndpoint.swift
│   ├── Workspace.swift
│   ├── SyncPayload.swift
│   └── VercelModels.swift
│
├── Views/
│   ├── MainWindowView.swift        # NavigationSplitView root
│   ├── Sidebar/
│   │   ├── SidebarView.swift
│   │   ├── CollectionTreeView.swift
│   │   ├── EnvironmentListView.swift
│   │   └── MockServerListView.swift
│   ├── Request/
│   │   ├── RequestEditorView.swift
│   │   ├── URLBarView.swift
│   │   ├── ParamsEditorView.swift
│   │   ├── HeadersEditorView.swift
│   │   ├── BodyEditorView.swift
│   │   ├── AuthEditorView.swift
│   │   └── ResponseView.swift
│   ├── Mock/
│   │   ├── MockServerDetailView.swift
│   │   ├── MockEndpointEditorView.swift
│   │   ├── MockServerSetupView.swift
│   │   └── DeploymentStatusView.swift
│   ├── Collaboration/
│   │   ├── WorkspacePickerView.swift
│   │   ├── PushPullView.swift
│   │   ├── ConflictResolutionView.swift
│   │   └── VersionHistoryView.swift
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   ├── VercelAccountView.swift
│   │   └── GeneralSettingsView.swift
│   └── Shared/
│       ├── KeyValueEditorView.swift
│       ├── JSONViewerView.swift
│       ├── CodeEditorView.swift    # WKWebView + CodeMirror
│       └── StatusBadgeView.swift
│
├── Services/
│   ├── VercelService.swift
│   ├── HTTPClientService.swift
│   ├── MockServerService.swift
│   ├── CollaborationService.swift
│   ├── ImportExportService.swift
│   └── KeychainService.swift
│
├── Importers/
│   ├── PostmanImporter.swift
│   ├── InsomniaImporter.swift
│   ├── ApidogImporter.swift
│   ├── OpenAPIImporter.swift
│   └── CURLParser.swift
│
├── ViewModels/
│   ├── RequestViewModel.swift
│   ├── CollectionViewModel.swift
│   ├── MockServerViewModel.swift
│   └── WorkspaceViewModel.swift
│
├── Utilities/
│   ├── VariableResolver.swift      # resolve {{variableName}}
│   ├── ScriptRunner.swift          # run pre/post JS scripts
│   └── URLBuilder.swift
│
└── Resources/
    ├── Assets.xcassets
    ├── koala-mock-template/        # Next.js template files (bundled)
    └── Koala.entitlements

KoalaTests/
KoalaUITests/
```

---

## 10. Vercel OAuth Setup

### Setup di Vercel Developer Console
```
1. Buka https://vercel.com/account/tokens (buat OAuth App)
2. App Name: Koala
3. Redirect URI: koala://oauth/callback
4. Scopes yang dibutuhkan:
   - read:user
   - read:team
   - read:project
   - create:project
   - delete:project
   - read:deployment
   - create:deployment
   - read:kv
   - write:kv
```

### OAuth Flow di Swift
```swift
// 1. Open browser
let authURL = "https://vercel.com/oauth/authorize?client_id=\(clientId)&redirect_uri=koala://oauth/callback&scope=..."
NSWorkspace.shared.open(URL(string: authURL)!)

// 2. Handle callback di AppDelegate
func application(_ app: NSApplication, open urls: [URL]) {
    guard let url = urls.first, url.scheme == "koala",
          url.host == "oauth",
          let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
              .queryItems?.first(where: { $0.name == "code" })?.value
    else { return }
    
    Task { await VercelService.shared.exchangeCode(code) }
}

// 3. Exchange code → token
// POST https://api.vercel.com/v2/oauth/access_token
// Simpan ke Keychain
```

---

## 11. Phased Roadmap

### Phase 1 — Foundation (MVP) [~6-8 minggu]
- [ ] Project setup Xcode, SwiftUI, SwiftData
- [ ] Layout utama: NavigationSplitView + sidebar + main area
- [ ] HTTP Client: request builder, send, response viewer
- [ ] Collections: CRUD, tree view, drag & drop
- [ ] Environments & variable resolution `{{var}}`
- [ ] Import: Postman, OpenAPI
- [ ] History

### Phase 2 — Vercel Integration [~4-6 minggu]
- [ ] Vercel OAuth flow + Keychain storage
- [ ] Mock Server: create, deploy template
- [ ] Mock Endpoint: static JSON response
- [ ] "Simpan ke Vercel" → update KV
- [ ] Deployment status polling

### Phase 3 — Advanced Mock & Collaboration [~4-6 minggu]
- [ ] Mock: dynamic JS response
- [ ] Mock: delay, conditional response
- [ ] Collaboration: workspace, push, pull
- [ ] Conflict resolution UI
- [ ] Version history + rollback

### Phase 4 — Polish & Extended Import [~3-4 minggu]
- [ ] Import: Insomnia, Apidog, HAR, cURL
- [ ] Export: Postman, OpenAPI, Markdown
- [ ] Collection Runner + test scripts
- [ ] Pre/post request scripts
- [ ] GraphQL support
- [ ] WebSocket client (bonus)
- [ ] App polish, onboarding, empty states

---

## 12. Feasibility Assessment

| Fitur | Feasibility | Catatan |
|---|---|---|
| Native SwiftUI macOS app | ✅ Fully possible | Standard Apple development |
| HTTP Client | ✅ Fully possible | URLSession sudah sangat capable |
| Import Postman/OpenAPI | ✅ Fully possible | JSON parsing straightforward |
| Vercel OAuth | ✅ Fully possible | Vercel punya full OAuth 2.0 |
| Mock Server via Vercel | ✅ Fully possible | Next.js + Vercel KV = solid combo |
| Update mock tanpa redeploy | ✅ Fully possible | KV update = instant |
| Collaboration push/pull | ✅ Fully possible | KV sebagai "remote storage" |
| Real-time sync (WebSocket) | ❌ Tidak diimplementasi | Sesuai spec: manual push/pull |
| Conflict resolution UI | ✅ Possible, tapi complex | Butuh custom diff algorithm |
| Dynamic JS mock response | ⚠️ Partially possible | Vercel Edge Function ada limitasi memory/CPU |

---

## 13. Lingkungan & Dependencies

### macOS App
```
- Xcode 15+
- Swift 5.9+
- macOS 14+ (Sonoma) sebagai minimum deployment target
- SwiftData (built-in)
- No third-party dependencies (pure Apple frameworks)
- WKWebView untuk CodeMirror editor (bundled HTML)
```

### Next.js Mock Server Template
```json
{
  "dependencies": {
    "next": "^14.0.0",
    "@vercel/kv": "^1.0.0"
  },
  "scripts": {
    "build": "next build"
  }
}
```

### vercel.json untuk template
```json
{
  "env": {
    "KOALA_SERVER_ID": "@koala-server-id"
  },
  "buildCommand": "npm run build",
  "framework": "nextjs"
}
```

---

## 14. Catatan untuk Agent

### Prioritas Eksekusi
1. Mulai dengan **Phase 1** secara keseluruhan sebelum Phase 2
2. Jangan implement Vercel integration sebelum HTTP Client berjalan sempurna
3. Mock Server **template Next.js** harus dibuat dan ditest standalone dulu sebelum diintegrasikan ke Swift app

### Environment Variables yang Dibutuhkan
```
VERCEL_CLIENT_ID=xxx        # dari Vercel OAuth App
VERCEL_CLIENT_SECRET=xxx    # dari Vercel OAuth App  
KOALA_KV_URL=xxx           # Vercel KV connection URL
```
Simpan di Xcode scheme environment variables, **jangan hardcode**.

### URL Scheme
Daftarkan `koala` sebagai custom URL scheme di Info.plist:
```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array><string>koala</string></array>
    <key>CFBundleURLName</key>
    <string>com.yourname.koala</string>
  </dict>
</array>
```

### Testing
- Unit test untuk semua Importers (Postman, OpenAPI, dll) — sangat penting
- Unit test untuk VariableResolver
- UI test untuk happy path: send request → lihat response
- Integration test untuk Vercel Service (gunakan Vercel sandbox/test project)

---

*PRD ini dibuat untuk eksekusi oleh local AI agent (Claude Code, Cursor, atau sejenisnya). Setiap section dirancang agar actionable dan self-contained.*

**Nama App: Koala**  
**Bundle ID: com.yourname.koala**  
**App Icon: Koala wajah, minimal, macOS-style**