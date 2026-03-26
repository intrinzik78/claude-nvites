# Rust SDK Gap: confirm_payment

**Date:** 2026-03-24
**Workstream:** server
**Origin:** surface-command-center orientation — payment dispatch exploration

## Problem

`POST /v1/workflow-instances/{id}/confirm-payment` exists in the OpenAPI spec and server implementation, but `WorkflowInstancesClient` in `sdk-rust` has no `confirm_payment()` method. The TypeScript SDK already has `confirmInstancePayment()` in `sdk-ts/src/api/workflows.ts`.

The command center will need this method once the payment management view is built — staff confirm-payment is a workflow step action invoked through the Rust SDK via Tauri IPC.

## Proposed Solution

Add `confirm_payment(id: i32, epoch: Option<i64>)` to `WorkflowInstancesClient` in `sdk-rust/src/workflows_client.rs`. Mechanical — follows the same pattern as `advance()`, `cancel()`, `pause()`, etc. The endpoint takes an `EpochBody` for optimistic locking and returns empty on success.

**Confidence:** High. The endpoint is stable, the SDK pattern is established, and the TS SDK already validates the shape.

## Context

This was discovered while exploring what the command center needs from `DISPATCH_PAYMENTS.md`. The Slice 6 endpoints (`GET /v1/payments/held`, `POST /v1/payments/{id}/approve`, `POST /v1/payments/{id}/decline`, `GET /v1/bookings/{id}/payments`) will also need Rust SDK wrappers once they ship — but those don't exist yet so they'll come naturally with the slice.
