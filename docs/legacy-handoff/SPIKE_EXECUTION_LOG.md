# IBEX 2.0 — Android Foundation Spike Execution Log

Status: **Active validation — not production-approved**

## 2026-08-11 — Same-head Foundation + Android runtime gates passed

### Accepted head
- Commit: `31e3d8ab44986b6f62ac0f33cae8166afad33191`.
- Foundation run: `31514943699` — **success**.
- Android Runtime run: `31514943707` — **success**.

### Foundation evidence
- Dependency resolution completed.
- Drift generation completed.
- `flutter analyze` completed with no issues.
- Full Flutter test suite completed successfully.
- Encrypted v1 migration gate now validates schema v13 and requires the persisted `fx_rates` table while preserving historical sale truth without inventing missing historical base-currency/customer values.

### Android evidence
- Dependency resolution + Drift generation completed.
- Disposable Android host generated.
- Android debug APK built successfully.
- `ibex-visual-prototype-debug-apk` artifact published.
- KVM-enabled Android emulator started.
- Encrypted persistence integration test completed successfully on Android, covering sqlite3mc persistence and the tested backup/restore/key lifecycle.

### Gate interpretation
This closes the continuation gate documented in `CURRENT_HANDOFF.md`: Foundation and Android Runtime are green on the exact same executable head. This does **not** make the application production-ready. Production hardening continues in the documented priority order, starting with complete authorization enforcement on every state-changing Operating Engine command.

## 2026-08-11 — PostSale hardening slice

### Implemented
- Removed hard-coded YER base-currency assumption from `PostSaleService`; command-owned `baseCurrencyCode` is now authoritative for the spike.
- Added normalized ISO-style 3-letter Latin currency validation at the application boundary.
- Added pre-validation aggregation of requested quantity by product before any stock-affecting write.
- Fixed repeated-product-line handling so canonical inventory balance is updated once per product using the aggregate quantity and aggregate COGS.
- Preserved individual sale lines and stock movement lines for audit/detail while using one canonical balance update per product.
- Added deterministic spike-only failure injection points:
  - `after_sequence`
  - `after_first_inventory_write`
  - `before_commit`
- Added tests proving that injected failures must roll back visible document sequence allocation, sale rows, sale items, stock movements, stock movement items, journal entries, journal lines, payments, operation log, audit log, and inventory balance changes.
- Added recovery expectation that the next successful sale after a rolled-back sequence allocation receives `SAL-2026-000001`, proving no committed numbering gap from the failed transaction.
- Added explicit test that repeated lines for one product cannot collectively overdraw stock.
- Added explicit test that repeated lines within available stock reduce quantity/value correctly.
- Added explicit non-YER base-currency conversion test (`USD` transaction -> `SAR` base) to detect accidental YER coupling.

### Invariants under validation
1. One operation ID creates at most one canonical sale truth.
2. Required stock is validated in aggregate per product, not line-by-line in isolation.
3. Inventory balance mutation occurs once per product per PostSale transaction.
4. Commercial, stock, accounting, payment, audit, operation and numbering effects share one DB transaction.
5. Any injected exception before transaction commit must leave zero partial posted truth.
6. Base currency is business/application context, never a global hard-coded currency.

## 2026-08-11 — Encrypted persistence + migration evidence

### Passed in Linux CI
- sqlite3mc encrypted database creation/open.
- plaintext SQLite header absence check.
- correct-key reopen of persisted operational truth.
- wrong-key rejection.
- encrypted backup creation with SHA-256 manifest validation.
- backup corruption detection before restore.
- backup → delete → restore → reconciliation for sale, inventory, journal, payment, operation log and audit evidence.
- encrypted schema migration from v1 to v2.
- migration preserves historical sale truth and does not invent missing historical base currency.
- Migration Gate CI run `31464336669` completed successfully through dependency resolution, Drift generation, `flutter analyze`, and `flutter test`.

## 2026-08-11 — Android Runtime Gate passed

### Verified on Android emulator
- Android Runtime Gate run `31482010165` completed with conclusion `success`.
- Flutter dependency resolution and Drift generation completed successfully.
- Disposable Android host generation completed successfully.
- Android debug build completed successfully.
- KVM-backed Android emulator startup completed successfully.
- The encrypted persistence integration test completed successfully on the Android emulator.
- The runtime test exercised app-private storage, secure-key creation/read/reuse, sqlite3mc database creation, atomic `PostSale`, close/reopen, encrypted-header check, wrong-key rejection, encrypted backup, database deletion, restore, operational reconciliation, and secure-key persistence during the test session.

### What this proves
The selected Flutter + Drift + sqlite3 3.x + sqlite3mc direction is technically viable on an Android emulator for the tested encrypted local-first slice. The Android packaging path can build and execute the native encrypted SQLite runtime, and the tested secure-storage-backed key flow can reopen the same encrypted database during the integration-test lifecycle.

### What remains unproven
- Representative physical Android device behavior.
- Key persistence across real process death / reboot / upgrade scenarios.
- Android backup/restore interactions and device migration policy.
- Performance on representative low/mid-range devices.
- Production hardening of Android manifest, backup exclusion, release signing, and secure-storage options.

## 2026-08-11 — Chat-first Visual Prototype Gate started

### Implemented
- Replaced the placeholder runtime screen with the first polished Chat-first IBEX shell.
- Arabic RTL is the primary layout direction and all hard-coded visible numeric examples use Latin digits.
- Added responsive behavior: mobile uses a drawer; wide layouts expose a persistent lightweight sidebar.
- Added central conversational workspace, greeting/prompt suggestions, user message bubble, agent response marker, and persistent composer.
- Added a typed Sale Draft Card showing customer, warehouse, product/unit, quantity, SAR price, total, lifecycle warning, and explicit `اعتماد / تعديل / إلغاء` controls.
- Added visual state transitions for awaiting approval, approved, changed/review-required, and cancelled.
- The prototype explicitly states that preview does not create accounting or inventory truth.
- Added widget tests for Arabic RTL rendering, sale-draft content, approval state, material-edit review reset, and composer interaction.
- Android Runtime workflow now publishes the debug APK as the short-lived artifact `ibex-visual-prototype-debug-apk` after a successful Android build. The upload action is pinned to an immutable commit.

### Gate state
The visual shell and interaction tests are committed. Foundation CI and Android build/runtime CI are currently the acceptance gates. The prototype is not declared ready for user installation until both the current static/test run and current APK/runtime run complete successfully and the APK artifact is confirmed present.

### Visual review scope once green
The first hands-on review will focus on hierarchy, Arabic typography, spacing, composer ergonomics, draft-card clarity, approval confidence, mobile drawer behavior, and whether the overall interaction feels like an operational ChatGPT-style product rather than a traditional ERP screen.

### Promotion rule
The emulator gate is **Passed**, but production scaffold promotion still requires representative-device security/runtime validation and the remaining critical foundation gates. The visual prototype may be installed for UX evaluation once its own CI/build gates are green; UX approval does not itself promote spike code to production.

## 2026-08-11 — Purchase + Supplier Engine Gate started

### Implemented in spike branch
- Added supplier master data table scoped by business.
- Added canonical purchase header/items, cash purchase payment, and supplier ledger tables.
- Advanced Drift schema to v7 with additive migration from prior spike schemas.
- Added typed `PostPurchaseCommand` and atomic `PostPurchaseService`.
- Added purchase document numbering using `PUR-{YYYY}-{SEQUENCE}` inside the posting transaction.
- Cash purchase posts inventory debit + cash credit and records a canonical purchase payment.
- Credit purchase requires an explicit supplier, posts inventory debit + accounts-payable credit, and records supplier-ledger liability without a cash payment.
- Purchase receipt creates `PURCHASE_IN` stock movement and increases canonical inventory quantity/value.
- Moving weighted average cost is recomputed from old carrying value plus base-currency purchase value; repeated product lines preserve document detail while updating the canonical product/warehouse balance once.
- Added idempotent replay through the shared operation log and unique purchase operation ID.
- Extended the encrypted migration gate from v1 through v7 and added required-table assertions for purchase/supplier schema.
- Added focused tests for cash purchase, credit purchase, duplicate product lines/WAC, idempotency, and rejection of credit purchase without supplier.

### Current acceptance state
- The previous Arabic local-search Foundation run for commit `4be5748c782d976d7764bb37818d961973aa1b92` completed successfully.
- Foundation run `31500300977` for the purchase/WAC head `b3fb3dfb4149f4f92d30191f4b390f749dfe19e7` has started and is not yet accepted as green.
- Android Runtime run `31500300775` for the same head has been queued/started separately and remains an acceptance gate.

### Promotion rule
Purchase/supplier code remains spike-only until Drift generation, analyzer, unit tests, encrypted migration tests, Android build, and Android encrypted-runtime gate complete successfully on the current head.