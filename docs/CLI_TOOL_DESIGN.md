# CLI Tool Design Pattern

Extracted from `cli-user/` (since removed), applied across all `cli-*` crates.

---

## Purpose

Each CLI is a thin MVC shell around the SDK: **parse → auth → dispatch → cleanup**.

The CLI owns no business logic. It translates terminal input into SDK calls and formats output for humans.

---

## Architecture

| Layer | Role | Implementation |
|-------|------|----------------|
| **Model** | SDK `Client` — handles API calls | `uwz_rust_sdk::types::Client` |
| **View** | Terminal I/O — prompts and output | Zero-sized `View` struct |
| **Controller** | Orchestrator — lifecycle and dispatch | `Controller` with builder pattern |

---

## Module Layout

```
cli-{name}/
├── Cargo.toml
└── src/
    ├── main.rs                  — tokio entry, parse → build → run
    ├── enums/
    │   ├── mod.rs               — gateway re-exports
    │   ├── error.rs             — CliError enum with Display
    │   └── primary_command.rs   — top-level Clap subcommands
    └── types/
        ├── mod.rs               — gateway re-exports
        ├── cli.rs               — root Clap parser struct
        ├── controller.rs        — MVC controller + builder
        ├── view.rs              — terminal I/O helpers
        ├── args/
        │   ├── mod.rs           — gateway re-exports
        │   └── {resource}.rs    — Clap args per resource
        └── commands/
            ├── mod.rs           — gateway re-exports
            └── {resource}.rs    — command handlers per resource
```

---

## Lifecycle

```
main()
 ├─ Cli::parse()                     — clap derives argument tree
 ├─ Controller::build()
 │   .with_model(&url, port)         — SDK client as data model
 │   .with_view()                    — terminal output
 │   .finish()                       — consume builder → Controller
 └─ controller.run(&cli)
     ├─ match cli.command()          — route to command handler
     │   └─ Command::run(controller) — login if needed, call SDK, format output
     └─ auto-logout                  — if Auth::Bearer set, call logout
```

---

## Error Strategy

```rust
#[derive(Debug, From)]
pub enum CliError {
    #[from] SDKError(SDKError),
    #[from] Io(io::Error),
    MissingResponseData,
    // ... CLI-specific variants
}
```

Display prefixes categorize errors for the user:
- `[sdk]` — SDK/API errors
- `[io]` — filesystem or stdin/stdout
- `[view]` — terminal I/O failures
- `[cli]` — argument or configuration issues

---

## Conventions

- Follow `docs/RUST_STYLE_GUIDE.md` for all code patterns
- `mod.rs` gateway with selective re-exports
- `type Result<T> = std::result::Result<T, CliError>;` in each module
- `derive_more::From` for error enum auto-conversion
- Zero-sized command structs with `pub async fn run(controller, args) -> Result<()>`
- View methods return `Result<&View>` or `&View` for fluent chaining
- Builder pattern: `Controller::build().with_model(...).with_view().finish()`
