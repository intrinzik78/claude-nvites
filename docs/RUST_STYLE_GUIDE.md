# Rust Code Style Profile

This document defines coding conventions, patterns, and stylistic preferences for this codebase.

---

## 1. Workspace Structure

- **Multi-crate workspace** with shared dependencies
- **Resolver 3** (Rust 2024 edition)
- Each crate follows identical internal organization

---

## 2. Module Organization

### Pattern: mod.rs Gateway with Selective Re-exports

```rust
// enums/mod.rs
mod activity;
mod api_result;
mod error;

pub use activity::ActivityType;
pub use api_result::ApiResult;
pub use error::Error;
```

**Rules:**
- Private module declarations (`mod foo;`)
- Explicit `pub use` re-exports for public API
- Public submodules only when deep access needed (`pub mod sessions;`)
- Standard directory structure: `enums/`, `types/`, `traits/`, `services/`

---

## 3. Naming Conventions

| Element | Convention | Examples |
|---------|------------|----------|
| Files | snake_case | `api_result.rs`, `token_bucket.rs` |
| Structs | PascalCase | `ApiSuccess`, `TokenBucket`, `SessionController` |
| Enums | PascalCase | `Error`, `Decision`, `RefillRate` |
| Enum Variants | PascalCase | `Decision::Approved`, `Error::SessionNotFound` |
| Functions | snake_case, action-oriented | `get_enabled_user()`, `try_connect()`, `to_mime()` |
| Fields | snake_case | `expires_at`, `bucket_capacity`, `session_id` |
| Constants | SCREAMING_SNAKE_CASE | `BLACK_LIST_LIMIT`, `DAY_AS_SECS` |
| Traits | PascalCase with `To` prefix | `ToBase64`, `ToDecision`, `ToBlackListStatus` |
| Type aliases | PascalCase | `Result<T>` |

### Function Naming Prefixes
- `to_*` - Convert self to another type (`to_mime()`, `to_base64_url()`)
- `from_*` - Create Self from another type (`from_mime()`, `from_u8()`)
- `with_*` - Builder/fluent methods (`with_capacity()`, `with_data()`)
- `get_*` / `by_*` - Database queries (`get_enabled_user()`, `by_id_unchecked()`)
- `is_*` - Boolean checks (`is_stale()`, `is_blacklisted()`)

---

## 4. Type Patterns

### Result Type Alias (Every Module)
```rust
type Result<T> = std::result::Result<T, Error>;
```

### Custom Error Enum with derive_more::From
```rust
#[derive(Debug, From)]
pub enum Error {
    // External crate errors with auto-conversion
    #[from]
    ActixJoinError(actix_rt::task::JoinError),

    #[from]
    Base64(base64::DecodeError),

    // Domain-specific errors
    SessionNotFound,
    DatabaseConnection(String),
    ScanStatusOutOfBounds(u8),  // Carries context
}
```

### Generic Response Wrappers
```rust
#[derive(Debug, Serialize, ToSchema)]
pub struct ApiSuccess<T>
where T: Serialize + ToSchema
{
    pub code: u16,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<T>
}
```

### Repr Attribute for Database Enums
```rust
#[repr(u8)]
#[derive(Copy, Clone, Debug, Serialize)]
pub enum ScanStatus {
    Created     = 1,
    Queued      = 2,
    Running     = 3,
    Completed   = 4,
    Failed      = 5,
    NeedsReview = 6
}
```

---

## 5. Import Style

### Hierarchical Grouping
```rust
// 1. Standard library
use std::{
    collections::{HashMap, BinaryHeap},
    sync::{Mutex, RwLock},
    time::{Duration, Instant}
};

// 2. External crates
use actix_web::{web::{Data, Json}, Responder};
use serde::Deserialize;
use utoipa::ToSchema;

// 3. Internal crate imports
use crate::{
    enums::{ApiResult, Error},
    types::{AppState, permissions::WereChecked}
};

// 4. Type alias
type Result<T> = std::result::Result<T, Error>;
```

### Aliasing for Brevity
```rust
use crate::enums::ExtractorError as Error;
```

---

## 6. Derive Macros

### Standard Combinations
```rust
// Simple enums
#[derive(Clone, Debug, PartialEq)]

// API response types
#[derive(Debug, Serialize, ToSchema)]

// Database-mapped structs
#[derive(Clone, Debug, FromRow)]

// Error enums
#[derive(Debug, From)]

// Permission/config structs
#[derive(Debug, Clone, Copy, Default, PartialEq)]

// Heap keys (for BinaryHeap)
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
```

---

## 7. Field Visibility

### Private Fields with Public Getters
```rust
#[derive(Debug)]
pub struct AppState {
    database: DatabaseConnection,  // private
    limiter: RateLimiterStatus,    // private
}

impl AppState {
    pub fn database(&self) -> &DatabaseConnection { &self.database }
    pub fn rate_limiter(&self) -> &RateLimiterStatus { &self.limiter }
}
```

### All-Public for Data Transfer Objects
```rust
pub struct UploadedFile {
    pub bytes: u64,
    pub client_file_name: String,
    pub file_type: FileType,
}
```

---

## 8. Function Signatures

### Async Functions (Predominant)
```rust
pub async fn get_enabled_user(
    username: &str,
    database: &DatabaseConnection
) -> Result<Option<User>>
```

### Builder Pattern Methods
```rust
pub fn with_capacity(mut self, capacity: u32) -> Self {
    self.capacity = capacity;
    self
}
```

### Conversion Methods
```rust
pub fn to_mime(&self) -> &'static str
pub fn from_mime(mime_type: &str) -> Result<Self, Error>
```

### Parameter Conventions
- References for borrowed data: `&DatabaseConnection`, `&str`
- `Data<T>` for shared state: `Data<AppState>`
- `Option<T>` for optional parameters
- `impl Into<String>` for flexible string inputs

---

## 9. Error Handling

### Propagation with `?` Operator
```rust
let settings = Settings::default();
let database = DatabaseConnection::new().await?;
let secrets = SecretController::new(settings.master_password.clone(), &database).await?;
```

### Creating Errors with `.ok_or()`
```rust
let user = auth_context_opt
    .to_user()
    .ok_or(Error::MissingUserInAuthContext)?;
```

### Match for Error Handling
```rust
match controller.new_secret(secret, database).await {
    Ok(()) => ApiResult::no_content().to_http(),
    Err(e) => e.to_http_response(),
}
```

### Lock Poison Handling
```rust
let locked_shard = shard_lock.inner
    .lock()
    .map_err(|_e| RateLimitError::PoisonedRateLimiterMap)?;
```

---

## 10. Trait Patterns

### Extension Traits (`ToXxx`)
```rust
pub trait ToBase64 {
    fn to_base64_url(&self) -> String;
}

impl ToBase64 for [u8] {
    fn to_base64_url(&self) -> String {
        BASE64_URL_SAFE_NO_PAD.encode(self)
    }
}
```

### Async Trait Methods
```rust
pub trait VerifyPassword {
    fn verify_password(&self, password: &str)
        -> impl std::future::Future<Output = AuthorizationStatus> + Send;
}
```

### std::error::Error Implementation
```rust
impl std::error::Error for ExtractorError {}

impl Display for ExtractorError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> Result {
        type E = ExtractorError;
        match self {
            E::MimeTypeInvalid => write!(f, "invalid mime type"),
            E::ScanStatusOutOfBounds(id) => write!(f, "invalid scan status: {id}"),
        }
    }
}
```

---

## 11. Documentation Style

### Arrow Comments for Visual Guides
```rust
// export type system ↴
pub mod api;

// import packages ↴
use clap::Parser;

// add api versions here ↴
let collection = RouteCollection;
```

### Doc Comments for Public APIs
```rust
/// api response wrapper, returning the code, message and optional data
#[derive(Debug, Serialize, ToSchema)]
pub struct ApiSuccess<T>

/// set custom code on response
pub fn with_code(mut self, new_code: u16) -> Self

/// CAUTION: does not filter by user status, do not use in workflow that grants permissions
pub async fn by_id_unchecked(id: i64, database: &DatabaseConnection) -> Result<Option<User>>
```

### Inline Comments for Rationale
```rust
// bucket ttl should exceed the check window or a bucket could respawn after dropping
let time = match self.refill_rate {

// ensure the bucket does not exceed max capacity
self.tokens = self.tokens.min(self.capacity as i32);
```

---

## 12. Code Formatting

### Type Alias in Match Expressions
```rust
type E = Error;
match self {
    E::SessionNotFound => ErrorReason { code: 1000, reason: "session not found".into() },
    E::DatabaseConnection(s) => ErrorReason { code: 1001, reason: s.clone() },
}
```

### Single-Line Match Arms When Short
```rust
match self {
    Self::Business(b) => b.id(),
    Self::Community(c) => c.id(),
    Self::System(s) => s.id()
}
```

### Boolean Match Pattern
```rust
match compared == required {
    true  => Permission::Granted,
    false => Permission::Denied
}
```

---

## 13. Impl Block Organization

### Separate Concerns into Multiple Impl Blocks
```rust
// Construction
impl Session {
    pub fn new(key_set: &KeySet, user: User) -> Self { ... }
}

// Queries
impl Session {
    pub fn is_stale(&self) -> RefreshStatus { ... }
}

// Async/Database operations (separate impl block)
impl UserPermissions {
    pub async fn into_db_as_transaction(...) -> Result<u64> { ... }
    pub async fn by_user_id(...) -> Result<UserPermissions> { ... }
}
```

---

## 14. Constants

### Module-Level Constants
```rust
const BLACK_LIST_TIME: u64   = 60;
const BLACK_LIST_LIMIT: i32  = -25;
const SHARD_FACTOR: usize    = 2;

const DAY_AS_SECS: f32 = 24.0 * 60.0 * 60.0;
const HOUR_AS_SECS: f32 = 60.0 * 60.0;
```

### Inline Hint for Hot Paths
```rust
#[inline]
fn hash(&self, ip_address: &IpAddr) -> usize {
```

---

## 15. Testing

### Conditional Compilation
```rust
#[cfg(test)]
pub mod test {
    use super::*;

    #[test]
    fn builder() { ... }
}
```

### Test Documentation
```rust
/// tests the default builder and associated builder functions
#[test]
fn builder() { ... }

/// stress test successful connections
#[test]
fn test_try_connect() { ... }
```

---

## Summary: Key Style Principles

1. **Explicit over implicit** - Clear type aliases, explicit re-exports, no glob imports
2. **Builder pattern** for complex construction with `with_*` methods
3. **Extension traits** (`ToXxx`) for clean conversions
4. **Comprehensive error enums** with context preservation
5. **Private fields** with public getters for encapsulation
6. **Async-first** design with Actix-web integration
7. **Minimal derives** - only what's needed
8. **Visual documentation** - arrow comments for navigation
9. **Type aliasing** in match expressions for brevity
10. **Modular organization** - enums, types, traits separation

---

## 16. App Layer Patterns

### DatabaseHelper → Transform (Irrefutable Construction)
Database structs that contain lookup IDs use a private `FromRow` helper consumed by `transform()`.
The public struct holds type-safe enums — it can never be constructed with invalid state.

```rust
#[derive(Clone, Debug, FromRow)]
struct DatabaseHelper {
    id: i64,
    status_id: i8,
    privacy_id: i8,
    // ...
}

impl DatabaseHelper {
    fn transform(self) -> Result<AppProject> {
        let status = AppProjectStatus::from_u8(self.status_id as u8)?;
        let privacy = AppProjectPrivacy::from_u8(self.privacy_id as u8)?;
        Ok(AppProject { status, privacy, /* ... */ })
    }
}
```

**Rules:**
- `DatabaseHelper` is **private** to the module — never exposed
- Public struct fields use **enum types**, never raw `i8`
- `transform()` is sync unless additional DB calls are needed
- For `Option<T>` returns: `helper.map(|h| h.transform()).transpose()`
- For `Vec<T>` returns: `helpers.into_iter().map(|h| h.transform()).collect()`

### Single Table Ownership
Each type owns all SQL for its table. No raw queries in handlers.

```rust
// CORRECT — type owns the query
AppProject::list_by_user(user_id, database).await

// WRONG — raw SQL in handler
sqlx::query_scalar("SELECT COUNT(*) FROM app_project WHERE...")
```

### Zero-Sized Controller Structs
API handlers use zero-sized structs with a single `pub async fn logic(...)` method.

```rust
pub struct ProjectsPost;

impl ProjectsPost {
    pub async fn logic(
        auth: AuthenticatedUser,
        post: web::Json<CreateProjectBody>,
        shared: web::Data<AppState>
    ) -> impl Responder { /* ... */ }
}
```

### Accepted Variant: Multi-Route GET Handlers
GET handlers that serve both a collection and an item (and optionally a binary route) may use `list()`, `by_id()`, and `file()` instead of a single `logic()`. This avoids splitting tightly-related 10-line methods into separate files.

```rust
pub struct AlbumsGet;

impl AlbumsGet {
    pub async fn list(shared: Data<AppState>) -> impl Responder { /* ... */ }
    pub async fn by_id(id: Path<i32>, shared: Data<AppState>) -> impl Responder { /* ... */ }
}
```

Registered as `Get::list` and `Get::by_id` in route_collection.rs. This applies only to read-only GET handlers — mutation handlers (POST/PATCH/DELETE) use the standard `logic()` convention.

### Handler-Level Enum Validation
Validate incoming `i8` → enum at the API boundary. Return `bad_request()` before calling the model.
Insert/update model methods accept enum types and cast to `i8` internally for SQL binds.

```rust
let status = match AppProjectStatus::from_u8(post.status_id as u8) {
    Ok(s) => s,
    Err(_) => return ApiResult::bad_request().to_http()
};
```

### Error Surfacing
Use `to_http_response()` — it selects the correct HTTP status and surfaces the client reason automatically. Internal errors get a generic 500 with no leaked details.

```rust
Err(e) => e.to_http_response(),
```

### Antipattern: Hashing `Utc::now()` Before DB Storage
MySQL DATETIME (without fractional-second precision) **rounds** sub-second values at the ≥500ms boundary. If you hash a timestamp and also store it in a DATETIME column, the DB value can silently shift by +1 second, breaking verification. Truncate before hashing and storing:

```rust
use chrono::SubsecRound;
let ts = Utc::now().trunc_subsecs(0); // safe for hash + DATETIME round-trip
```

### COALESCE for Partial Updates
PATCH endpoints use SQL COALESCE — no dynamic query building needed for optional fields without **explicit consent from user** - ask permission and provide reasoning. work around it when permission is not granted.

```rust
"UPDATE app_project SET name = COALESCE(?, name), status_id = COALESCE(?, status_id) WHERE id = ?"
```

---

## When Generating Code

Follow these rules when writing new Rust code for this codebase:

1. **Always** use the mod.rs gateway pattern with explicit re-exports
2. **Always** define `type Result<T> = std::result::Result<T, Error>;` in each module
3. **Always** use `derive_more::From` for error enums with external error wrapping
4. **Always** use `#[repr(u8)]` for enums that map to database values
5. **Prefer** private fields with public getters for types with invariants
6. **Prefer** `with_*` methods for builder patterns
7. **Prefer** `ToXxx` naming for extension conversion traits
8. **Use** arrow comments for section markers in long files
9. **Use** type aliases in match expressions when arms are long
10. **Follow** rustfmt defaults for spacing (run `cargo fmt`)
11. **Always** use DatabaseHelper → transform pattern for structs with lookup IDs
12. **Always** validate enums at handler boundary, never pass raw `i8` to model insert/update
13. **Always** use `e.to_http_response()` in handler error arms — never call `to_api_error_message()` directly
14. **Never** put raw SQL in handlers — each type owns its table queries
15. **Never** skip `cargo clippy` as the final check before committing
