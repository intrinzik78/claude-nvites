# Dispatch: QR Frame — Brand Asset + AppState Wiring

**Date:** 2026-03-25
**For:** Joshua
**From:** dev session (qr-frame crate build)

---

## What You Need To Do

The `qr-frame` crate is built, tested, reviewed, and security-audited. It generates branded QR code PNGs by compositing a QR code onto a frame image. What's missing: the brand frame image and the AppState wiring.

### 1. Create the brand frame image

- **Format:** PNG, RGBA (transparency supported but not required)
- **Center region:** The QR code will be placed dead-center. Leave a clear area in the middle sized for the QR. For a typical URL payload at module_size=10, the QR will be ~370x370px (33 modules × 10px + quiet zone). Size your frame accordingly — 500x500 or 600x600 works well.
- **Location:** Place the file at `server/qr-frame/assets/frame.png` (create the `assets/` directory)

### 2. Create the SVG frame (for slice 2)

- Same visual design as the PNG frame, but as an SVG file
- Place at `server/qr-frame/assets/frame.svg`
- The SVG composition (slice 2) will inject QR `<rect>` elements into this template

---

## What To Tell Claude (AppState Wiring Prompt)

When you're ready to wire the `QrGenerator` into AppState, use this as context for the session:

> Wire the `qr-frame` crate into AppState. The crate is at `server/qr-frame/`, already in the workspace and api dependency. Follow the `AuthorizeNetStatus` pattern:
>
> 1. **No status enum needed** — QR generation is always available (no enable/disable toggle like payment gateway). Just store `QrGenerator` directly in AppState.
> 2. Add `qr_generator: Option<qr_frame::types::QrGenerator>` to `AppState` (Option because it's None if frame image isn't available)
> 3. Add getter: `pub fn qr_generator(&self) -> Option<&QrGenerator>`
> 4. Add builder: `pub fn with_qr_generator(mut self, gen: QrGenerator) -> Self`
> 5. In `primary_command.rs` startup: load frame via `include_bytes!("../qr-frame/assets/frame.png")`, construct `QrGenerator::new(bytes, 10)`, set on AppState
> 6. The handler that generates QR codes should wrap the call in `tokio::task::spawn_blocking()` and use the general rate limiter
>
> The frame image is at `server/qr-frame/assets/frame.png`. The `QrGenerator` API:
> - `QrGenerator::new(frame_png: &[u8], module_size: u32) -> Result<QrGenerator>`
> - `QrGenerator::generate_png(data: &str) -> Result<Vec<u8>>`
> - Input data is the full URL: `https://urbanwarzonepaintball.com/waiver?code=XXX-XXX`
> - Max data length: 256 bytes. Module size 10 is the default.

---

## Crate API Reference

```rust
use qr_frame::types::QrGenerator;

// Construct once (startup)
let generator = QrGenerator::new(frame_png_bytes, 10)?;

// Generate per request
let png_bytes: Vec<u8> = generator.generate_png("https://urbanwarzonepaintball.com/waiver?code=ABC-123")?;
```

**Error types:** `QrFrameError::Image`, `QrEncode`, `QrTooLargeForFrame`, `DataTooLong`, `InvalidModuleSize`

**Already wired:** `qr-frame` is in `server/api/Cargo.toml` dependencies and `Error` enum has `#[from] QrFrame(qr_frame::enums::QrFrameError)`.
