# Architecture decision record — Web v1

## Goal

Create a new ChatGPT-style operational interface without coupling UI components to accounting tables.

## Boundary

The existing Flutter application remains untouched in repository root. The new web product lives under `web/` on branch `honey-web-v1` until it is moved to its own repository.

## Trust boundaries

- Browser: untrusted presentation layer.
- Next.js server: authentication/session boundary and application API.
- Domain services: only location allowed to invoke accounting commands.
- PostgreSQL runtime identity: `ibex_app_runtime`, inheriting `ibex_backend` and the RLS marker role.
- Database owner credentials: prohibited from application runtime.

## Authentication

Neon Auth is provisioned on the project's default `neondb` database. Financial data remains in `bahkam_honey`. Neon Auth user IDs are mapped explicitly through the IBEX identity-link layer.

## Command flow

User request → AI parser (next phase) → validated draft → human confirmation → Domain Service → database function → constraints/RLS/audit.

The AI layer will never receive raw SQL capability.

## First command contract

The first production command is `ConfirmSale`, implemented by calling the existing `ibex_had_create_transaction` database function with `transaction_type=sales_invoice` after validating identity and business scope.
