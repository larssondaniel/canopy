# Canopy — Product Brief

## What is Canopy?

Canopy is a native macOS GraphQL client built with Swift and SwiftUI. It is a fast, polished alternative to Electron-based GraphQL clients like Altair GraphQL. Canopy is open source (MIT license) and designed to feel like a first-class Mac app — responsive, keyboard-driven, and visually clean.

The goal is to be the best way to explore a GraphQL schema, write queries, and inspect responses on a Mac.

---

## Tech Stack

- **Language:** Swift
- **UI Framework:** SwiftUI
- **Platform:** macOS only (no iOS, no cross-platform)

---

## Core Features

### 1. Endpoint Configuration
- Text field for the GraphQL endpoint URL
- HTTP verb selector (POST is the default and most common for GraphQL, but GET should be supported)
- Endpoint URL is persisted per tab

### 2. Query Pane
- A text editor for writing GraphQL queries and mutations
- Syntax highlighting for GraphQL
- Support for query variables via a separate input area (JSON format)
- The query pane and variables pane should be resizable

### 3. Request Headers
- Users can add, edit, and remove custom HTTP headers per request
- Common use case: `Authorization: Bearer <token>`, `Content-Type: application/json`
- Headers should be editable in a key-value list UI

### 4. Sending Requests
- A prominent "Run" / "Execute" button (and keyboard shortcut, e.g. Cmd+Enter) to send the query
- Sends the GraphQL query, variables, and headers to the configured endpoint
- Displays a loading state while the request is in flight
- Handles errors gracefully (network errors, GraphQL errors, malformed responses)

### 5. Result Pane
- Displays the JSON response from the server
- Pretty-printed and syntax-highlighted JSON
- Shows response metadata: HTTP status code, response time (ms), response size
- Response headers viewable in a collapsible/secondary section
- The result pane should be resizable relative to the query pane (split view)

### 6. Schema Introspection
- Ability to fetch the GraphQL schema from the endpoint via introspection query
- Manual "Refresh Schema" button to re-fetch
- The schema is used to power the schema explorer and docs browser

### 7. Schema Explorer
- A sidebar or panel that displays the full GraphQL schema as a navigable tree
- Browse types, fields, arguments, enums, interfaces, unions, input types
- Click-to-navigate between types (e.g. clicking a field's return type jumps to that type's definition)
- Search/filter functionality to quickly find types or fields
- This is a key differentiator — it should feel fast and fluid, taking full advantage of native SwiftUI rendering

### 8. API Docs Browser
- Inline documentation pulled from the schema's description fields
- Browsable alongside or integrated with the schema explorer
- Should feel like reading documentation, not inspecting raw schema

### 9. Multiple Tabs
- Support for multiple query tabs within a single window
- Each tab has its own query, variables, headers, endpoint, and result
- Tabs can be opened, closed, and renamed
- Standard macOS tab bar UX (Cmd+T to open, Cmd+W to close)

### 10. Environments
- Define named environments (e.g. "Development", "Staging", "Production")
- Each environment stores a set of variables (key-value pairs)
- Variables can be referenced in the endpoint URL, headers, and query variables using a template syntax (e.g. `{{base_url}}`, `{{auth_token}}`)
- Quick-switch between environments via a dropdown or toolbar control
- Environments are stored locally and persist across sessions

### 11. Collections
- Save queries to named collections for reuse
- A query in a collection includes: name, query text, variables, headers, and associated endpoint
- Collections are browsable in a sidebar
- Queries can be organized into folders/groups within a collection
- Collections are stored locally and persist across sessions

### 12. Authorization
- Dedicated UI for configuring authorization
- Support for common auth methods: Bearer token, Basic auth, API key (as header)
- Auth configuration can be set per-tab or inherited from the environment

---

## Design Principles

1. **Native feel.** Use standard macOS UI patterns — toolbars, sidebars, split views, tab bars, keyboard shortcuts. It should feel like it belongs on a Mac, not like a web app in a wrapper.

2. **Speed.** Instant response to user input. Schema exploration, search, and navigation should be immediate. No loading spinners for local operations.

3. **Keyboard-first.** Power users live on the keyboard. Cmd+Enter to run, Cmd+T for new tab, Cmd+F to search schema, etc.

4. **Clean defaults.** The app should be useful immediately with minimal configuration. Sensible defaults for headers, pretty-printed responses, automatic schema fetch on endpoint change.

5. **Non-destructive.** Never lose user work. Queries, tabs, and environments should persist across app launches. Unsaved queries should survive crashes.

---

## Non-Goals (for now)

- **Subscriptions (WebSocket):** Not in initial scope. May be added later.
- **Cloud sync / team features:** The app is local-only for now. Cloud sync is a potential future paid feature.
- **Plugin system:** No plugin architecture for now. Keep it simple.
- **Windows / Linux support:** This is a Mac-only app. No cross-platform considerations.
- **Code generation:** No GraphQL code generation features.

---

## Project Metadata

- **Name:** Canopy
- **License:** MIT
- **Repository:** GitHub (public)
- **Language:** Swift
- **Platform:** macOS