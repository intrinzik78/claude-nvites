# Dispatch: Register @nvites npm scope

**Date:** 2026-03-26
**Workstream:** dev

## Problem

The SDK has been renamed from `@uwz/sdk-ts` to `@nvites/sdk-ts`. The `@nvites` npm scope does not exist yet. It needs to be registered on npmjs.com before the package can be published or referenced externally.

## Reasoning

- Scope registration is a one-time manual step on npmjs.com
- The workspace reference (`"@nvites/sdk-ts": "workspace:*"`) works locally without registration
- Registration is only needed before first publish or if CI needs to resolve it from the registry
- Free for public packages, paid for private org scopes

## Proposed Solution

1. Go to https://www.npmjs.com/org/create and register the `nvites` organization
2. Or register a user scope at https://www.npmjs.com/signup if `@nvites` is available as a user scope
3. Verify with `npm whoami --scope=@nvites`

## Confidence

**High** — straightforward registration, just needs a human with npm credentials
