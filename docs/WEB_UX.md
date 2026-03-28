# Web UX — Website Surface

Design and architecture guide for the nvites.me public website (surface-website).

## Purpose

The website serves two audiences:
- **Public visitors** — marketing pages, campaign landing pages (QR scan destinations)
- **Clients** — portal for account management and profile

## Stack

SvelteKit with server-side rendering. BFF pattern — the SvelteKit server calls the API via `sdk-ts` over Railway's private network. Client-side JS handles interactivity.

## Key pages (planned)

| Route | Purpose | Auth |
|-------|---------|------|
| `/` | Marketing landing | Public |
| `/invite/{uuid}` | QR scan destination — campaign landing | Public |
| `/portal/me` | Client profile | Authenticated |
| `/shop` | Product catalog | Public |

## Patterns

- **MVVM:** page components are views, `.svelte.ts` files are view-models
- **SSR first:** pages load with data from server-side `+page.server.ts`
- **IP forwarding:** BFF sets `X-Real-Client-IP` header via `hooks.server.ts`
