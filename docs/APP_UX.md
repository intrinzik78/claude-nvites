# App UX — Desktop & Mobile Surfaces

Design and architecture guide for Tauri surfaces.

## Surfaces

| Surface | Audience | Platform |
|---------|----------|----------|
| command-center | Admin (solo dev) | Desktop (Win/macOS) |
| member | Clients — real-time campaign analytics | Mobile (planned) |

## Architecture

Tauri apps communicate with the API server exclusively through `sdk-rust`. No direct database access.

### IPC Flow

1. Svelte frontend invokes a Tauri command (`@tauri-apps/api/core`)
2. Rust command handler calls `sdk-rust` client method
3. SDK makes HTTP request to API server
4. Response flows back through SDK → Rust → Svelte

### Auth

- Login via Tauri command → SDK `sessions().login()`
- Token stored in `AppState.client` (Mutex-wrapped)
- Session expiry detected via `SDKError::Unauthorized` → emits `auth:session-expired` event
- Frontend listens for event, redirects to login

## Command Center

Admin tool for managing campaigns, viewing analytics, and monitoring the system. Currently has: auth, epochs, health, workflows.

## Member (planned)

Client-facing mobile app for real-time campaign analytics. Not yet built.
