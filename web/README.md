# IBEX Honey Web

New conversational operations interface for the `bahkam_honey` Neon database.

## Architecture

Browser → Next.js server → Neon Auth → domain services → `ibex_app_runtime` → `ibex_backend` → RLS/functions → `bahkam_honey`.

The browser never receives a PostgreSQL connection string and never executes SQL directly.

## Current vertical slice

1. Neon Auth server/client wiring.
2. Protected conversational shell.
3. Runtime identity propagation to PostgreSQL (`neon_auth` + user id).
4. Resolve the authenticated Neon user to an IBEX application user through the database identity-link layer.
5. Sales draft contract.
6. Confirm sale through `ibex_had_create_transaction` only; no direct table insert from application code.

## Required environment variables

Copy `.env.example` to `.env.local` and fill:

- `NEON_AUTH_BASE_URL`
- `NEON_AUTH_COOKIE_SECRET` (minimum 32 characters)
- `IBEX_DATABASE_URL` for database `bahkam_honey` using login role `ibex_app_runtime`

The runtime role exists in Neon and inherits only the hardened IBEX backend permissions. Its password must be configured outside source control.

## Identity linking

A newly registered Neon Auth user is not automatically linked to an accounting user. This is intentional. The app returns `ACCOUNT_NOT_LINKED` until an explicit `neon_auth` identity link exists for the matching `ibex_had_users` record. Never auto-link financial identities by email alone.

## Security rules

- No database owner credentials in the app.
- No SQL from client components.
- No direct writes to accounting tables.
- Every database call carries identity context.
- Every new PostgreSQL function must explicitly revoke `PUBLIC EXECUTE` and grant only the intended role.
