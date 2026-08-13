# IBEX 2.0 — Foundation Spike Package

This package is disposable validation code for `spike/android-foundation-v1`. It is not the production app scaffold.

## Implemented
- `Money` scaled integer contract (`1e4`).
- `Quantity` scaled integer contract (`1e6`).
- `ExchangeRate` scaled integer contract (`1e8`).
- half-away-from-zero integer rounding.
- Latin-digit-only numeric parsing at domain boundaries.
- canonical visible document-number formatter.
- Android secure-storage-backed database-key candidate.
- minimal Drift schema for the first `PostSale` vertical slice.
- transactional document sequence service.
- central `PostSaleCommand` contract.
- central `PostSaleService` that coordinates sale, stock movement, inventory balance projection, journal entry, payment, operation log, and audit inside one Drift transaction.
- idempotent replay behavior by `operation_id`.
- tests for successful atomic posting, journal balance, inventory effect, duplicate operation replay, and insufficient-stock rollback.

## Dependency baseline
- Drift `2.34.3`.
- sqlite3 `3.5.0` using version 3 build hooks; legacy `sqlite3_flutter_libs` / `sqlcipher_flutter_libs` are intentionally not used.
- flutter_secure_storage `10.3.1` as the current Android secure key-storage candidate.
- path_provider `2.1.6`.
- uuid `4.6.0`.

## Validation status
The code has been committed as an executable spike design, but this ChatGPT environment has not run a Flutter toolchain or Android emulator. Therefore generated Drift code, compilation, tests, encrypted SQLite wiring, and device behavior remain **unverified until executed by CI or a representative Android toolchain**.

## Known spike constraints / review findings
- The current vertical slice targets a cash sale and does not yet implement credit sales or partial allocations.
- The current accounting COGS value assumes inventory carrying value is already expressed in the business base currency.
- Duplicate product lines in a single sale need an explicit normalization/aggregation rule before production freeze; current tests use one canonical line per product.
- The command now carries `baseCurrencyCode`; the service must use it rather than assume a fixed business base currency before the slice can pass final review.
- Database encryption wiring is not yet accepted; only the key-storage abstraction/candidate is present.

## Next executable slice
1. Generate Drift code and compile the package on a current Flutter stable toolchain.
2. Fix any analyzer/codegen failures before adding more behavior.
3. Enforce normalized unique product lines or aggregate stock validation by product.
4. Make base-currency conversion fully command/configuration driven.
5. Add document-sequence rollback test that fails after allocation but before commit.
6. Add explicit transaction-failure injection to prove full rollback after partial writes.
7. Select and wire the sqlite3 v3 encryption provider in the spike only.
8. Run tests on representative Android hardware and record evidence.
