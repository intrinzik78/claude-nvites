# Dispatch: Remove UWZ handoffs directory

**Date:** 2026-03-26
**Workstream:** dev

## Problem

The `handoffs/` directory in the monorepo contains 80+ UWZ-specific handoff files across 10+ domains. These document UWZ development history and have no relevance to the nvites project. They add noise and could confuse future orient/handoff skill runs.

## Proposed Solution

Delete the entire `handoffs/` directory contents but keep the directory structure (or at minimum keep `.gitkeep` files in each subdomain directory so the handoff skill has somewhere to write). The DECISIONS.md entries that reference handoff source files are historical provenance — they don't need the files to exist.

## Confidence

**High** — pure cleanup, no code dependencies
