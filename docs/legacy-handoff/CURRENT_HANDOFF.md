# IBEX 2.0 — Exact Continuation Handoff

Updated: 2026-08-11
Continuation key: `IBEX2-CONTINUE`
Repository: `muhbahkm/ibex-had`
Active executable branch: `spike/android-foundation-v1`
Do not mutate production Supabase. Production Supabase remains READ ONLY unless separately and explicitly authorized.

## Purpose
This file is the authoritative handoff for a fresh ChatGPT conversation. The next conversation must read this file first, then inspect the current branch head and latest Foundation/Android CI before making changes.

## Product direction
IBEX 2.0 is a from-scratch, local-first Android business operating system built in Flutter/Dart with Drift + encrypted SQLite (sqlite3mc). The primary UI is Chat-first, not Chat-only: a conversational operational Agent with typed operational cards, while the Operating Engine remains the only authority allowed to create posted accounting/inventory truth.

The canonical mutation flow is:
User -> Conversation Orchestrator -> Intent Interpreter -> Entity Resolver -> Draft Command -> Operating Engine validation -> Preview -> Explicit Approval -> Typed Post Command -> Operating Engine -> one local DB transaction -> canonical records/audit/result.

The Agent must never write SQL directly, bypass permissions, invent ambiguous entities, or mutate posted truth outside registered application commands.

## Architecture / invariants already established
- Presentation -> Application/Commands -> Domain/IBEX Operating Engine -> repositories/UoW -> encrypted SQLite.
- Local app-private SQLite is runtime truth; cloud is optional future sync/backup only.
- Double-entry accounting.
- Posted financial/inventory truth is immutable; correction/reversal instead of hard edit/delete.
- Money: signed Int64 scale 1e4, half-away-from-zero at defined boundaries.
- FX: Int64 scale 1e8; when transaction currency == base currency, rate must be exactly 1e8.
- Quantity: Int64 scale 1e6, unit precision 0..6.
- Inventory valuation V1: Moving Weighted Average Cost per product + warehouse.
- Negative stock disabled at posting.
- UUID canonical IDs; visible document numbers allocated transactionally.
- Document prefixes currently used: SAL, PUR, SRT, PRT, RCT, PAY, EXP, STX, CNT, JRN.
- Operation idempotency via unique operation IDs.
- Encryption key is generated/stored with `flutter_secure_storage`; encrypted SQLite provider is sqlite3mc.
- Backup/restore spike verifies encrypted database copy + SHA-256 manifest + restore reconciliation.

## Conversational Agent contracts already implemented
- `OperationalDraft` lifecycle with deterministic SHA-256 fingerprint.
- Approval binds to exact draft version/fingerprint.
- Any material revision invalidates prior approval.
- Cancelled/expired drafts cannot post.
- `AgentCommandRegistry` blocks unregistered state-changing commands.
- `OperationalActionFacade` is the bounded write facade for non-sale operational commands.
- Arabic sale intent interpreter supports create sale, revise price, revise quantity, approve, cancel, post.
- Read-only conversational queries exist for customer balance, inventory balance, and supplier balance.
- Arabic entity normalization/search supports definite-article relaxation (`الـ`) and local business scoping.

## UI already implemented
A real Flutter Chat-first visual prototype has been built and previously installed/tested on Android. It includes:
- Arabic RTL conversation shell.
- Bottom composer.
- Operational Sale Draft card.
- Approve / edit / cancel states.
- Draft version/state display.
- Persistent local draft restoration.
- Runtime failure screen instead of plaintext fallback if encrypted DB bootstrap fails.

The earlier visual prototype was successfully built as an Android debug APK and manually viewed on a real phone. The current branch has moved beyond that prototype into a larger executable domain/runtime spike.

## Local encrypted runtime already implemented
- App-private encrypted database bootstrap.
- Secure key create/read/reuse.
- Encrypted reopen/wrong-key rejection.
- Encrypted backup/delete/restore/reconcile gate.
- Disposable Android emulator integration test.
- Seed data strictly for spike/testing only.
- Synthetic FX provider exists strictly for spike/testing and MUST be replaced before production by business-configured date-scoped FX rates visible in preview.

## Business modules implemented in executable spike
### Sales
- `PostSaleCommand` + `PostSaleService`.
- Cash and credit sales.
- Atomic sale + stock movement + journal + payment/AR + audit + operation log.
- Credit sale writes CustomerLedger and does not invent cash receipt.
- Customer receipt service exists separately.
- Customer balance query exists.
- Approved conversational Sale Draft maps to `PostSaleCommand`.
- Deterministic operation ID for approved draft posting to protect retries/idempotency.

### Purchases
- `PostPurchaseCommand` + `PostPurchaseService`.
- Cash and credit purchases.
- Atomic purchase + PURCHASE_IN + journal + cash/AP + supplier ledger/audit.
- WAC recalculation on purchase.
- Duplicate product lines aggregated for balance update while document lines remain detailed.

### Supplier payment
- `PaySupplierCommand` + service.
- PAY document sequence.
- Dr Accounts Payable / Cr Cash.
- Supplier ledger settlement.
- Audit + idempotency.
- Supplier balance query exists.

### Stock transfer
- One STX business document.
- Exactly two canonical stock movements in one transaction: TRANSFER_OUT + TRANSFER_IN.
- Same carrying value, no P/L.
- Source/destination must differ.
- Sufficient stock required.
- Source WAC resets appropriately when source balance is exhausted.

### Sales returns
- Dedicated immutable SRT document, linked to source sale/item.
- Cumulative return quantity cannot exceed source quantity.
- Restores inventory using original sale COGS carrying cost.
- Reverses revenue/COGS accounting.
- Cash sale return creates refund; credit sale return reduces receivable without inventing cash.
- Atomic + idempotent.

### Purchase returns
- Dedicated PRT tables/command/service/test slice has been added after sales returns.
- Schema migration was extended for purchase returns.
- Treat this slice as implemented-but-not-yet-green until the latest CI is repaired and rerun.

### Authorization
- Authorization tables were added: app users, roles, user_roles, role_permissions.
- Schema migration reached v12 for this slice.
- Authorization work is not yet fully wired into every Operating Engine command; do NOT call the authorization layer production-complete yet.

## Database schema status
Current branch schema target is v12. Migrations were progressively added from encrypted v1 snapshots through the current schema. The migration gate asserts preservation of old sale truth and must not invent missing historical base currency/customer fields.

Major local tables now include sales/sale_items, purchases/purchase_items, customer/supplier ledgers, receipts/payments, inventory balances, stock movements, stock transfers, sale returns, purchase returns, operational drafts, master data, audit/operation log, and authorization tables.

## CI history / evidence
Earlier gates were proven green at multiple points, including:
- Foundation analyze/tests for the original sales/agent slice.
- Encrypted migration gate through earlier schema versions.
- Android emulator runtime gate proving Flutter + Drift + sqlite3mc encrypted persistence, secure key persistence during test session, backup/restore, and Android debug build.
- Purchase foundation slice became green before later modules were layered on top.

Do not infer current-head green status from those historical successes.

## EXACT CURRENT HEAD / CURRENT FAILURE
At the time this handoff was written, the active branch head before this handoff commit was:
`2557322c7b84f01027617a53b2014a0a42be2f13`
message: `feat: allow async posting context resolution`

The latest Foundation CI run for that head was:
- Run: `31504637171`
- Result: FAILURE during `flutter analyze`; tests were skipped.

The concrete analyzer errors/warnings were:
1. `lib/presentation/persistent_sale_chat_controller.dart:293:22`
   - `FutureOr<SalePostingContext>` passed where `SalePostingContext` is required.
   - Cause: posting context factory was changed to async-capable but PersistentSaleChatController still passes it synchronously.
   - Expected repair: resolve/await the posting context before calling `workflow.postApproved(...)`, keeping sync factories compatible through FutureOr.
2. Unused `package:drift/drift.dart` import in `test/post_purchase_return_service_test.dart`.
3. Unused `package:drift/drift.dart` import in `test/post_sale_return_service_test.dart`.

The Android Runtime Gate for the same head also failed. Inspect its job/logs after fixing Foundation because it may be failing from the same compile/analyze inconsistency or a downstream Android-specific issue.

IMPORTANT: A fresh conversation must NOT claim the current branch is green until it fixes these issues and verifies both Foundation and Android runtime runs on the new head.

## First actions for the next conversation — execute in this order
1. Fetch branch `spike/android-foundation-v1` and confirm current head (this handoff commit will be newer than `2557322...`).
2. Read this file and `spike/SPIKE_EXECUTION_LOG.md`.
3. Fetch the latest Foundation + Android Runtime workflow runs for the current head.
4. Fix async posting-context mismatch in `persistent_sale_chat_controller.dart` by awaiting/resolving `FutureOr<SalePostingContext>` before `postApproved`.
5. Remove the two unused Drift imports in purchase-return and sale-return tests.
6. Push and wait for Foundation `Generate Drift -> Analyze -> Test` to become green. If it fails, inspect logs and repair; do not skip.
7. Verify Android Runtime Gate green on the exact same head, including debug APK build and encrypted emulator integration test.
8. Only after both are green, document the gate in `spike/SPIKE_EXECUTION_LOG.md` and governance/project-state docs.
9. Then continue production-hardening in this priority order:
   a. Fully wire authorization/permissions into every state-changing command before execution.
   b. Replace synthetic FX with persisted business-configured date-scoped rates + preview snapshot.
   c. Complete Purchase Return CI/edge cases.
   d. Add expense/cash movement engine.
   e. Add reversal/correction commands for posted docs.
   f. Add reports/read models.
   g. Wire purchase/payment/transfer/returns into conversational typed drafts/cards (not direct Agent posting).
   h. Add deterministic business calendar/timezone for document sequence year/date.
   i. Add representative physical-device encryption/Keystore/process-kill/reinstall lifecycle gate.
   j. Build production Android host/signing/release pipeline, not CI-generated disposable host.
   k. Remove/disable spike seed data and synthetic defaults from production runtime.
   l. Add production backup/restore UX and destructive-restore confirmation/reconciliation.
   m. Security/privacy review, dependency pinning/hardening, release build smoke/performance tests.

## Production readiness rule
Never tell the user “100% production ready” merely because CI is green. Production-ready requires, at minimum:
- all required business flows implemented and permission-gated;
- no synthetic FX/seed behavior in production;
- encrypted migration + backup/restore proven;
- representative physical-device tests;
- signed release build and clean-install/upgrade/restore tests;
- accounting/inventory invariant suite green;
- recovery/idempotency/reversal paths green;
- release UI tested on representative devices;
- no known P0/P1 defects;
- production configuration separated from spike/test configuration.

## Production Supabase safety
The old production Supabase project must remain READ ONLY. Do not use it as IBEX 2.0 runtime truth and do not mutate it as part of this continuation. Any future migration/import must be a separately designed, audited, one-way import process into local IBEX 2.0 data with explicit authorization.

## New-chat bootstrap prompt
The user can paste this exact instruction into a new conversation:

`IBEX2-CONTINUE. Continue IBEX 2.0 from GitHub repo muhbahkm/ibex-had. First read spike/CURRENT_HANDOFF.md on branch spike/android-foundation-v1, then spike/SPIKE_EXECUTION_LOG.md and the governance PROJECT_CONTEXT/PROJECT_STATE/DECISIONS docs. Inspect the current branch head and latest Foundation + Android Runtime CI. Do not re-plan from scratch. Fix the current gate first, prove both CI gates green on the same head, then continue the production-hardening sequence documented in CURRENT_HANDOFF.md. Production Supabase is strictly read-only.`
