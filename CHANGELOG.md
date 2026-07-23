# Changelog

Semua perubahan penting pada **Sistem Rekonsiliasi Stok** dicatat dalam file ini.

Format changelog mengikuti prinsip [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), sedangkan penomoran versi mengikuti [Semantic Versioning 2.0.0](https://semver.org/).

> **Status penting:** versi `0.1.0` adalah baseline spesifikasi, dokumentasi, data demo, dan kontrak implementasi. Entri tersebut tidak menyatakan seluruh fitur aplikasi sudah selesai dikembangkan atau telah dirilis ke production.

---

## Konvensi

### Kategori

Gunakan kategori berikut pada setiap versi bila relevan:

- **Added** untuk fitur, dokumen, endpoint, table, function, test, atau capability baru.
- **Changed** untuk perubahan behavior atau kontrak.
- **Deprecated** untuk capability yang masih tersedia tetapi akan dihapus.
- **Removed** untuk capability yang telah dihapus.
- **Fixed** untuk perbaikan defect.
- **Security** untuk hardening, vulnerability fix, RLS, authorization, secret, atau kontrol keamanan.

### Label Status

Entry besar sebaiknya memakai salah satu label berikut:

```text
[Specification]
[Implemented]
[Released]
[Migration]
[Security]
[Demo]
[Testing]
```

| Label | Arti |
|---|---|
| `[Specification]` | Keputusan telah didokumentasikan, tetapi belum tentu sudah diimplementasikan. |
| `[Implemented]` | Code dan migration sudah tersedia serta melewati test yang dipersyaratkan. |
| `[Released]` | Sudah dipromosikan ke environment release yang disebutkan. |
| `[Migration]` | Mengubah schema, data contract, function, policy, atau deployment state. |
| `[Security]` | Berkaitan dengan Auth, RLS, grants, secret, atau hardening. |
| `[Demo]` | Berkaitan dengan golden fixture, simulator, atau demo. |
| `[Testing]` | Berkaitan dengan test strategy, fixture, atau release gate. |

### Versi

Selama initial development:

```text
0.MINOR.PATCH
```

Pedoman:

- `0.x.0` untuk baseline atau capability besar;
- `0.x.y` untuk perbaikan backward-compatible;
- `1.0.0` hanya setelah domain, schema, deployment, dan operasi dinyatakan stabil;
- breaking change tetap harus ditulis eksplisit meskipun proyek masih berada pada versi `0.x`.

### Tanggal

Gunakan format:

```text
YYYY-MM-DD
```

---

## [Unreleased]

### Added

- `[Migration][Implemented]` Menambahkan migration `202607230017_product_batch_master_data.sql`: normalisasi SKU/kode Batch, lifecycle Product dan Batch, `row_version`, trusted RPC, read model/audit Product-Batch, serta audit immutable `catalog.master_data_audit_events` yang stock-neutral.
- `[Migration][Implemented]` Menambahkan migration `202607230018_product_batch_integration_guardrails.sql`: guardrail trusted untuk Receipt dan Opening Balance, serta resolver scope Stocktake yang membedakan Batch `BLOCKED` dari `ARCHIVED` dan tetap menghitung saldo fisik historis.
- `[Implemented]` Menambahkan workflow Admin `/products`, detail Product, dan detail Batch untuk create/update/archive/reactivate Product serta create/update/block/unblock/archive/reactivate Batch `STANDARD`, dengan feedback persisten dan optimistic concurrency.
- `[Testing]` Menambahkan pgTAP `053_product_batch_master_data.test.sql`, `054_product_batch_integration_guardrails.test.sql`, dan focused smoke `npm run test:product-batch-admin-ui`.
- `[Testing]` Menambahkan cleanup `finally` dan pemilihan fixture bersaldo pada smoke Opening Balance agar pengulangan tidak mencemari projection baru.
- `[Migration][Implemented]` Menambahkan cutover saldo awal immutable dengan lifecycle `DRAFT -> REVIEW -> POSTED`, preview authoritative, posting `INITIAL_BALANCE` atomik, first-stocktake verification evidence, dan exact reversal.
- `[Implemented]` Menambahkan workflow Admin `/opening-balances` untuk draft, review, preview, posting, per-line verification drill-down, reversal, dan cutover pengganti.
- `[Testing]` Menambahkan pgTAP `046` sampai `048` serta smoke `test:opening-balance-ui` dan `test:opening-balance-verification-ui`.
- `[Migration][Implemented]` Menambahkan registry listing marketplace channel-specific, mapping `SINGLE`, recipe bundle versioned, effective boundary, deterministic fingerprint, immutable source-line/component snapshot, dan authoritative normalization melalui migration `202607220013` sampai `202607220016`.
- `[Implemented]` Menambahkan workflow Admin `/marketplace/listings` untuk membuat listing, mengelola draft recipe, preview expansion, aktivasi, retirement, archive, histori versi, blocker, optimistic concurrency, dan feedback persisten.
- `[Implemented][Demo]` Mengubah simulator marketplace agar menerima external listing code dan listing quantity, kemudian memakai normalized event contract yang sama dengan adapter CSV/API/webhook masa depan.
- `[Testing]` Menambahkan pgTAP `049` sampai `052`, smoke `test:marketplace-listing-admin-ui`, dan regression smoke `test:marketplace-listing-simulator-ui`.

### Changed

- `[Specification]` Menetapkan `ACTIVE`/`BLOCKED`/`EXPIRED`/`ARCHIVED` sebagai lifecycle Batch; `SELLABLE`/`QUARANTINE`/`DAMAGED` sebagai bucket fisik; dan `STANDARD`/`RETURN`/`UNIDENTIFIED_RETURN` sebagai kind yang terpisah.
- `[Testing]` Validation baseline bersih untuk perubahan Product/Batch mencatat 23 Product checks, 30 Batch checks, Product/Batch smoke 53, Opening Balance smoke 51, Manual Outbound smoke 48, Marketplace Listing Admin smoke 50, serta pgTAP 54 files/2933 tests. Angka ini bertambah bila coverage bertambah; seluruh suite tetap wajib PASS.
- `[Specification]` Menetapkan saldo awal estimasi tetap `UNVERIFIED` sampai stok opname pertama yang memenuhi exact organization/product/batch/bucket scope diposting.
- `[Specification]` Memisahkan verifikasi fisik dari quantity adjustment: zero variance dapat memverifikasi tanpa membuat ledger movement.
- `[Specification]` Menetapkan koreksi saldo awal melalui exact reversal dan dokumen pengganti, bukan edit atau delete histori.
- `[Specification]` Menetapkan adapter marketplace memakai external listing identity, sedangkan mapping dan bundle expansion dilakukan oleh domain sebelum reservasi atau efek stok.
- `[Specification]` Menetapkan order lama mempertahankan recipe version, mapping fingerprint, dan component snapshot yang dipakai saat ingestion; perubahan recipe hanya berlaku untuk event pada effective period baru.
- `[Specification]` Menetapkan bundle tidak pernah memiliki stok, batch, reservation, allocation, transaction, ledger entry, atau projection sendiri.

### Deprecated

- Belum ada perubahan yang dicatat.

### Removed

- Belum ada perubahan yang dicatat.

### Fixed

- Belum ada perubahan yang dicatat.

### Security

- `[Security]` Menambahkan organization-scoped RLS, trusted RPC boundaries, fixed `search_path`, direct-write denial, stale row-version protection, dan credential-safe local smoke untuk lifecycle marketplace listing.

---

## [0.1.0] - 2026-07-13

### Status Release

```text
Type: Specification baseline
Application implementation: Not implied
Production release: Not implied
Database migration execution: Not implied
```

### Added

#### Brief dan Fondasi Produk

- `[Specification]` Menetapkan [`stok-management-system.pdf`](./stok-management-system.pdf) sebagai brief asli proyek.
- `[Specification]` Menetapkan tujuan utama:
  ```text
  Tidak ada angka stok yang berubah tanpa jejak.
  ```
- `[Specification]` Mendefinisikan masalah selisih antara spreadsheet, catatan sistem, dan barang fisik.
- `[Specification]` Mendefinisikan sumber selisih:
  - pembatalan;
  - retur;
  - barang rusak;
  - barang hilang;
  - bonus;
  - promo;
  - sampel;
  - penjualan offline;
  - saldo awal.
- `[Specification]` Menetapkan stack:
  - Next.js;
  - TypeScript;
  - Supabase;
  - PostgreSQL.
- `[Specification]` Menetapkan fase 1 sebagai sistem unit-only tanpa harga atau nilai uang.

#### Dokumentasi Produk

- `[Specification]` Menambahkan [`01-project-brief.md`](./01-project-brief.md).
- `[Specification]` Menambahkan [`02-product-requirements.md`](./02-product-requirements.md).
- `[Specification]` Menambahkan [`03-business-rules.md`](./03-business-rules.md).
- `[Specification]` Menambahkan [`04-stock-ledger-design.md`](./04-stock-ledger-design.md).
- `[Specification]` Menambahkan [`05-database-schema.md`](./05-database-schema.md).
- `[Specification]` Menambahkan [`06-user-roles-and-flows.md`](./06-user-roles-and-flows.md).
- `[Specification]` Menambahkan [`07-marketplace-simulator.md`](./07-marketplace-simulator.md).
- `[Specification]` Menambahkan [`08-reconciliation-logic.md`](./08-reconciliation-logic.md).
- `[Specification]` Menambahkan [`09-return-and-claim-flow.md`](./09-return-and-claim-flow.md).
- `[Specification]` Menambahkan [`10-fefo-batch-allocation.md`](./10-fefo-batch-allocation.md).
- `[Specification]` Menambahkan [`11-stock-opname-flow.md`](./11-stock-opname-flow.md).
- `[Specification]` Menambahkan [`12-notification-rules.md`](./12-notification-rules.md).
- `[Security]` Menambahkan [`13-security-and-rls.md`](./13-security-and-rls.md).
- `[Testing]` Menambahkan [`14-testing-scenarios.md`](./14-testing-scenarios.md).
- `[Demo]` Menambahkan [`15-demo-script.md`](./15-demo-script.md).
- `[Specification]` Menambahkan [`16-deployment-guide.md`](./16-deployment-guide.md).

#### Repository Entry Point

- `[Specification]` Menambahkan [`README.md`](./README.md) sebagai pintu masuk repository.
- `[Specification]` README merangkum:
  - masalah;
  - keputusan bisnis;
  - scope;
  - arsitektur;
  - local setup;
  - testing;
  - demo;
  - keamanan;
  - deployment.
- `[Specification]` Menambahkan peta dokumentasi dan urutan membaca berdasarkan jenis reviewer.

#### Environment

- `[Specification]` Menambahkan [`.env.example`](./.env.example).
- `[Security]` Memisahkan browser-safe, server-only, privileged, dan CI/CD variables.
- `[Security]` Menambahkan:
  ```text
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
  SUPABASE_SECRET_KEY
  ```
- `[Security]` Menyimpan `SUPABASE_SERVICE_ROLE_KEY` hanya sebagai catatan compatibility legacy.
- `[Specification]` Menambahkan local defaults untuk:
  - Supabase;
  - simulator;
  - deployment metadata;
  - observability;
  - E2E.
- `[Security]` Menambahkan reference production yang menetapkan:
  ```text
  MARKETPLACE_SIMULATOR_ENABLED=false
  MARKETPLACE_SIMULATOR_ALLOW_COMMIT=false
  ```

#### Seed dan Demo Fixture

- `[Demo]` Menambahkan [`seed.sql`](./seed.sql).
- `[Security]` Menambahkan guard:
  ```text
  SEED_PRODUCTION_FORBIDDEN
  ```
- `[Demo]` Menambahkan organisasi:
  ```text
  GLOWLAB_DEMO
  ```
- `[Demo]` Menambahkan channel:
  - `MANUAL`;
  - `SHOPEE`;
  - `TIKTOK_SHOP`;
  - `IMPORT`;
  - `SIMULATOR`;
  - `SYSTEM`.
- `[Demo]` Menambahkan movement reasons untuk inbound, outbound, return, disposal, stocktake, dan reversal.
- `[Demo]` Menambahkan golden products:
  - `SER-NIA-30`;
  - `CLN-GEN-100`;
  - `TNR-HYD-100`.
- `[Demo]` Menambahkan golden batches:
  - `SER-2608-A`;
  - `SER-2612-B`;
  - `CLN-2611-A`;
  - `TNR-2610-A`.
- `[Demo]` Menambahkan bundle recipe:
  ```text
  2 x Serum
  1 x Cleanser
  ```
- `[Demo]` Menambahkan initial balance melalui ledger:
  ```text
  Serum    = 25
  Cleanser = 15
  Toner    = 12
  ```
- `[Specification]` Menambahkan projection rebuild dari ledger.
- `[Security]` Menambahkan private Storage buckets:
  - `evidence`;
  - `imports`;
  - `exports`.
- `[Demo]` Menambahkan notification rule configuration.
- `[Testing]` Menambahkan verification terhadap:
  - lookup;
  - produk;
  - batch;
  - bundle;
  - initial quantity;
  - negative stock;
  - ledger-projection consistency.
- `[Security]` Menetapkan akun Auth demo dibuat melalui trusted Auth Admin API, bukan direct insert ke `auth.users`.

#### Model Stok dan Ledger

- `[Specification]` Menambahkan bucket:
  ```text
  SELLABLE
  QUARANTINE
  DAMAGED
  ```
- `[Specification]` Menambahkan reservation sebagai quantity non-physical.
- `[Specification]` Menetapkan:
  ```text
  available = sellable - active reservation
  ```
- `[Specification]` Menambahkan product-level projection.
- `[Specification]` Menambahkan batch-level projection.
- `[Specification]` Menambahkan append-only ledger.
- `[Specification]` Menambahkan stock transaction dan ledger entries.
- `[Specification]` Menambahkan idempotency command.
- `[Specification]` Menambahkan reversal.
- `[Specification]` Menambahkan adjustment untuk stocktake.
- `[Specification]` Menetapkan projection dapat dibangun ulang dari ledger.

#### Marketplace

- `[Specification]` Menambahkan canonical marketplace events.
- `[Specification]` Menetapkan trigger Shopee:
  ```text
  SHIPPED
  ```
- `[Specification]` Menetapkan trigger TikTok Shop:
  ```text
  IN_TRANSIT
  ```
- `[Specification]` Menambahkan reservation sebelum physical outbound.
- `[Specification]` Menambahkan cancellation sebelum dan sesudah physical outbound.
- `[Specification]` Menambahkan duplicate event handling.
- `[Specification]` Menambahkan same-ID/different-payload conflict.
- `[Specification]` Menambahkan stale event handling.
- `[Specification]` Menambahkan out-of-order event handling.
- `[Specification]` Menambahkan simulator Shopee dan TikTok Shop.
- `[Specification]` Menambahkan CSV import sebagai adapter fase 1.

#### FEFO

- `[Specification]` Menambahkan automatic batch allocation.
- `[Specification]` Menetapkan Admin tidak memilih batch untuk normal outbound.
- `[Specification]` Menambahkan deterministic order:
  ```text
  expiry
  -> receipt time
  -> batch code
  -> batch ID
  ```
- `[Specification]` Menambahkan split allocation.
- `[Specification]` Menambahkan eligibility rules.
- `[Specification]` Menambahkan safety buffer.
- `[Specification]` Menambahkan batch blocking.
- `[Specification]` Menambahkan transaction locking.
- `[Specification]` Menetapkan `SKIP LOCKED` tidak digunakan untuk keputusan FEFO.
- `[Testing]` Menambahkan concurrent-last-unit test.

#### Bundle

- `[Specification]` Menambahkan recipe dan component normalization.
- `[Specification]` Menetapkan bundle tidak mempunyai stock balance.
- `[Specification]` Menambahkan recipe snapshot per order.
- `[Testing]` Menambahkan test yang menolak pseudo-stock bundle.

#### Retur dan Klaim

- `[Specification]` Menambahkan expected return tanpa stock movement.
- `[Specification]` Menambahkan physical receipt ke `QUARANTINE`.
- `[Specification]` Menambahkan inspection ke `SELLABLE` atau `DAMAGED`.
- `[Specification]` Menambahkan partial return.
- `[Specification]` Menambahkan unidentified return batch.
- `[Specification]` Menambahkan lost return tanpa stock movement.
- `[Specification]` Menambahkan late-arrival exception.
- `[Specification]` Menambahkan default claim window TikTok 40 hari.
- `[Specification]` Menetapkan claim tidak membuat ledger.
- `[Specification]` Menambahkan reminder:
  ```text
  14 / 7 / 3 / 1 / 0 hari
  ```

#### Stok Opname

- `[Specification]` Menambahkan mode:
  - `FULL`;
  - `CYCLE`;
  - `AD_HOC`;
  - `POST_INCIDENT`;
  - `POST_MIGRATION`.
- `[Specification]` Menambahkan `FROZEN` dan `CONTINUOUS`.
- `[Specification]` Menambahkan blind count.
- `[Specification]` Menambahkan explicit zero count.
- `[Specification]` Menambahkan append-only count attempts.
- `[Specification]` Menambahkan recount.
- `[Specification]` Menambahkan tolerance review.
- `[Specification]` Menambahkan approval version.
- `[Specification]` Menambahkan atomic adjustment posting.
- `[Specification]` Menambahkan post-stocktake reconciliation.

#### Rekonsiliasi

- `[Specification]` Menambahkan daily reconciliation.
- `[Specification]` Menambahkan stocktake reconciliation.
- `[Specification]` Menambahkan check:
  - ledger vs batch projection;
  - batch vs product projection;
  - reservation;
  - allocation;
  - return;
  - transfer net-zero;
  - reversal;
  - notification;
  - job health.
- `[Specification]` Menambahkan issue fingerprint.
- `[Specification]` Menambahkan issue lifecycle.
- `[Specification]` Menambahkan projection rebuild.
- `[Specification]` Menetapkan ledger tidak diperbaiki dengan rewrite.

#### Notifikasi

- `[Specification]` Menambahkan in-app notification center.
- `[Specification]` Menambahkan expiry stages:
  ```text
  D90
  D60
  D30
  EXPIRED
  ```
- `[Specification]` Menambahkan claim deadline stages.
- `[Specification]` Menambahkan pending return inspection.
- `[Specification]` Menambahkan reconciliation notifications.
- `[Specification]` Menambahkan import, stocktake, event, dan job notifications.
- `[Specification]` Menambahkan notification episode.
- `[Specification]` Menambahkan active deduplication.
- `[Specification]` Menambahkan transactional outbox.
- `[Specification]` Menambahkan realtime refetch dan polling fallback.
- `[Specification]` Menetapkan bahwa status baca bersifat per akun Admin.

#### Security

- `[Security]` Menambahkan Supabase Auth.
- `[Security]` Menambahkan active Admin profile.
- `[Security]` Menambahkan organization-scoped RLS.
- `[Security]` Menambahkan default-deny grants.
- `[Security]` Menambahkan `anon` denial.
- `[Security]` Menambahkan private Storage.
- `[Security]` Menambahkan signed URL.
- `[Security]` Menambahkan CSRF/origin checks.
- `[Security]` Menambahkan IDOR protection.
- `[Security]` Menambahkan input validation.
- `[Security]` Menambahkan mass-assignment prevention.
- `[Security]` Menambahkan replay protection.
- `[Security]` Menambahkan fixed `search_path`.
- `[Security]` Menambahkan revocation untuk `PUBLIC EXECUTE`.
- `[Security]` Menambahkan CSP dan HTTP security headers.
- `[Security]` Menambahkan production invite-only.
- `[Security]` Menambahkan MFA/AAL2 untuk tindakan sensitif.
- `[Security]` Menambahkan environment isolation.
- `[Security]` Menambahkan last-active-Admin guard.
- `[Security]` Menambahkan security release blockers.

#### Testing

- `[Testing]` Menambahkan 278 testing scenarios.
- `[Testing]` Menambahkan global invariants.
- `[Testing]` Menambahkan P0 smoke pack.
- `[Testing]` Menambahkan deterministic golden fixtures.
- `[Testing]` Menambahkan:
  - Vitest;
  - React Testing Library;
  - pgTAP;
  - Playwright;
  - k6.
- `[Testing]` Menambahkan positive dan negative RLS tests.
- `[Testing]` Menambahkan concurrency test requirements.
- `[Testing]` Menambahkan property-based test guidance.
- `[Testing]` Menambahkan accessibility tests.
- `[Testing]` Menambahkan UAT dan demo acceptance.
- `[Testing]` Menambahkan absolute release blockers.

#### Demo

- `[Demo]` Menambahkan runbook demo 18 menit.
- `[Demo]` Menambahkan demo ringkas 8 menit.
- `[Demo]` Menambahkan golden story:
  ```text
  25 initial serum
  +10 maklon
  -8 Shopee shipped
  -1 TikTok in transit
  -2 bonus
  -2 bundle component
  +2 return sellable
  -1 stocktake adjustment
  =
  23 sellable
  ```
- `[Demo]` Menambahkan checkpoints.
- `[Demo]` Menambahkan stop conditions.
- `[Demo]` Menambahkan technical Q&A.
- `[Demo]` Menambahkan fallback evidence pack.

#### Deployment

- `[Specification]` Menambahkan topology:
  ```text
  GitHub
  -> GitHub Actions
  -> Vercel
  -> Supabase Cloud
  ```
- `[Specification]` Menambahkan environment:
  - local;
  - test;
  - preview/staging;
  - demo;
  - production.
- `[Security]` Menambahkan Supabase staging-production isolation.
- `[Migration]` Menambahkan expand-contract strategy.
- `[Migration]` Menambahkan CI-driven production migration.
- `[Specification]` Menambahkan Deployment Checks.
- `[Specification]` Menambahkan promotion.
- `[Specification]` Menambahkan app rollback.
- `[Specification]` Menambahkan database forward-fix policy.
- `[Specification]` Menambahkan backup, restore, RPO, dan RTO.
- `[Specification]` Menambahkan custom domain.
- `[Specification]` Menambahkan custom SMTP.
- `[Specification]` Menambahkan Cron dan job health.
- `[Specification]` Menambahkan health endpoints.
- `[Specification]` Menambahkan post-deploy reconciliation.

### Changed

#### Role Model

- `[Specification]` Menyederhanakan role aplikasi menjadi:
  ```text
  ADMIN
  ```
- `[Specification]` Menghapus kebutuhan runtime role:
  - Operator;
  - Viewer;
  - Approver;
  - Supervisor.
- `[Specification]` Mempertahankan beberapa akun Admin individual untuk:
  - audit;
  - notification read state;
  - session;
  - MFA;
  - deactivation.

#### Notification State

- `[Specification]` Memisahkan lifecycle:
  ```text
  OPEN
  ACKNOWLEDGED
  RESOLVED
  SUPPRESSED
  ```
  dari read state:
  ```text
  UNREAD
  READ
  ARCHIVED
  ```
- `[Specification]` Menetapkan bahwa ketika Admin A membaca notifikasi, Admin B tetap memiliki status bacanya sendiri.
- `[Specification]` Menetapkan escalation mengembalikan notification menjadi unread.

#### Security Model

- `[Security]` Mengubah authorization source menjadi active profile lookup.
- `[Security]` Memisahkan user-scoped client, Auth Admin client, worker, dan migration identity.
- `[Security]` Menetapkan hanya schema `api` yang diekspos.
- `[Security]` Menetapkan direct write ke ledger, projection, audit, dan posted document ditolak.
- `[Security]` Menetapkan production action sensitif membutuhkan MFA/AAL2.

#### Seed Strategy

- `[Demo]` Menetapkan seed hanya untuk local, test, staging, dan isolated demo.
- `[Security]` Menetapkan production opening balance melalui controlled import dan reconciliation.
- `[Security]` Menetapkan Auth bootstrap melalui trusted Auth Admin API.

#### Deployment Strategy

- `[Specification]` Menetapkan Vercel sebagai deployment baseline Next.js.
- `[Specification]` Menetapkan Supabase Cloud sebagai baseline Postgres/Auth/Storage/Cron.
- `[Security]` Menetapkan preview tidak boleh memakai production database.
- `[Security]` Menetapkan simulator production disabled secara default.

### Deprecated

- `[Security]` Menandai legacy Supabase service-role environment variable sebagai compatibility path sementara.
- `[Specification]` Menandai draft multi-role sebagai tidak berlaku untuk fase 1.
- `[Specification]` Menandai direct balance editing sebagai pola yang dilarang.
- `[Specification]` Menandai simulator direct-ledger-write sebagai desain yang tidak berlaku.

### Removed

- `[Specification]` Menghapus stock entity untuk bundle.
- `[Specification]` Menghapus batch selection manual pada normal outbound.
- `[Specification]` Menghapus auto-restock setelah cancellation post-shipment.
- `[Specification]` Menghapus asumsi marketplace status `received` sama dengan physical receipt.
- `[Specification]` Menghapus stock movement dari claim dan lost return.
- `[Security]` Menghapus anonymous application-data access.
- `[Security]` Menghapus service-role sebagai default client request pengguna.

### Fixed

- `[Specification]` Memperjelas bahwa reservation mengurangi available, bukan on-hand.
- `[Specification]` Memperjelas trigger Shopee dan TikTok.
- `[Specification]` Memperjelas return quarantine sebelum inspection.
- `[Specification]` Memperjelas tolerance tidak menghapus variance.
- `[Specification]` Memperjelas mark-as-read tidak menyelesaikan source condition.
- `[Specification]` Memperjelas projection drift diperbaiki dari ledger.
- `[Specification]` Memperjelas claim reminder memakai stored deadline.
- `[Specification]` Memperjelas app rollback tidak otomatis membatalkan database migration.
- `[Documentation]` Menambahkan cross-document navigation.
- `[Documentation]` Menyamakan golden quantities pada seed, testing, demo, dan README.

### Security

- `[Security]` Menambahkan organization isolation.
- `[Security]` Menambahkan private evidence/import/export storage.
- `[Security]` Menambahkan service key server-only requirement.
- `[Security]` Menambahkan environment guards.
- `[Security]` Menambahkan secret scanning requirement.
- `[Security]` Menambahkan negative access tests.
- `[Security]` Menambahkan absolute security release blockers.
- `[Security]` Menambahkan simulator dan seed production guards.
- `[Security]` Menambahkan last Admin protection.
- `[Security]` Menambahkan invite-only dan MFA baseline.

---

## Release Checklist

Sebelum memindahkan item dari `[Unreleased]` ke versi baru:

### Documentation

- [ ] Semua perubahan penting sudah dicatat.
- [ ] Specification dan implementation dibedakan.
- [ ] Breaking change disebutkan eksplisit.
- [ ] Dokumen terkait diperbarui.
- [ ] Relative link tidak rusak.
- [ ] Entry tidak sekadar menyalin seluruh commit.

### Database

- [ ] Migration tersedia.
- [ ] Fresh reset lulus.
- [ ] Upgrade path lulus.
- [ ] RLS dan grants diuji.
- [ ] Backward compatibility ditentukan.
- [ ] Backfill terdokumentasi.
- [ ] Rollback atau forward-fix tersedia.

### Testing

- [ ] Unit/component test lulus.
- [ ] pgTAP lulus.
- [ ] Integration lulus.
- [ ] P0/P1 E2E lulus.
- [ ] Concurrency test lulus.
- [ ] Security negative test lulus.
- [ ] Reconciliation tidak menghasilkan unexpected critical issue.

### Deployment

- [ ] Release version ditentukan.
- [ ] Commit SHA dicatat.
- [ ] Deployment checks lulus.
- [ ] Backup/restore point diverifikasi.
- [ ] Environment target benar.
- [ ] Smoke test lulus.
- [ ] Observation window selesai.
- [ ] Release artifact dicatat.

### Finalisasi Changelog

1. Pindahkan entry dari `[Unreleased]`.
2. Tambahkan:
   ```text
   ## [X.Y.Z] - YYYY-MM-DD
   ```
3. Hapus subsection kosong yang tidak digunakan.
4. Buat section `[Unreleased]` kosong baru.
5. Tambahkan compare/release links setelah URL repository final tersedia.
6. Tag commit:
   ```text
   vX.Y.Z
   ```
7. Pastikan release notes konsisten dengan changelog.

---

## Contoh Entry Berikutnya

```markdown
## [Unreleased]

### Added

- `[Implemented]` Menambahkan posting penerimaan maklon melalui database function atomik.
- `[Testing]` Menambahkan pgTAP untuk idempotency dan projection consistency.

### Changed

- `[Migration]` Menambahkan `source_ref_snapshot` melalui migration backward-compatible.

### Fixed

- `[Implemented]` Memperbaiki duplicate Shopee `SHIPPED` agar tidak membuat outbound kedua.

### Security

- `[Security]` Membatasi function posting kepada active Admin dalam organization scope.
```

---

## Hubungan Changelog dan Commit

Commit message dapat mengikuti Conventional Commits:

```text
feat(scope): description
fix(scope): description
docs(scope): description
refactor(scope): description
test(scope): description
chore(scope): description
```

Contoh:

```text
feat(ledger): add atomic maklon receipt posting
fix(fefo): prevent allocation from blocked batches
docs(seed): document Auth bootstrap requirement
test(rls): add cross-organization denial cases
```

Changelog tidak harus memuat semua commit.

Changelog hanya memuat perubahan penting bagi:

- pengguna;
- Admin;
- reviewer;
- maintainer;
- deployment;
- keamanan;
- data contract.

---

## Tautan Versi

URL repository final belum ditetapkan dalam source proyek.

Setelah tersedia, tambahkan pada akhir file:

```markdown
[Unreleased]: https://github.com/<org>/<repo>/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/<org>/<repo>/releases/tag/v0.1.0
```

Jangan membuat link placeholder aktif sebelum repository benar-benar ada. Riwayat perubahan seharusnya menjelaskan masa lalu, bukan menciptakan portal menuju halaman 404.
