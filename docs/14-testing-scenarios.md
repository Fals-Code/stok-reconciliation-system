
<!--
File: 14-testing-scenarios.md
Project: Sistem Rekonsiliasi Stok
Status: Approved testing baseline for Phase 1
Version: 1.0.0
Last updated: 2026-07-13
Language: id-ID
Timezone: Asia/Jakarta
Application role model: ADMIN only
Primary source: stok-management-system.pdf
Depends on:
  - 01-project-brief.md
  - 02-product-requirements.md
  - 03-business-rules.md
  - 04-stock-ledger-design.md
  - 05-database-schema.md
  - 06-user-roles-and-flows.md
  - 07-marketplace-simulator.md
  - 08-reconciliation-logic.md
  - 09-return-and-claim-flow.md
  - 10-fefo-batch-allocation.md
  - 11-stock-opname-flow.md
  - 12-notification-rules.md
  - 13-security-and-rls.md
-->

# Testing Scenarios: Sistem Rekonsiliasi Stok

## 1. Tujuan Dokumen

Dokumen ini menetapkan strategi, data, skenario, tooling, prioritas, bukti, dan release gate pengujian untuk Sistem Rekonsiliasi Stok fase 1.

Dokumen ini mengubah requirement pada dokumen `01` sampai `13` menjadi kontrak pengujian yang dapat dijalankan oleh developer, reviewer, dan Admin saat acceptance test.

Sistem tidak dinyatakan benar hanya karena:

- halaman berhasil dibuka;
- CRUD dapat menyimpan data;
- unit test berwarna hijau;
- coverage melewati angka tertentu;
- satu demo happy path selesai;
- tidak ada error di console.

Sistem dinyatakan layak bila pengujian membuktikan bahwa:

1. setiap perubahan quantity fisik memiliki ledger entry;
2. ledger posted tidak dapat diedit atau dihapus;
3. reservasi tidak dianggap sebagai stok keluar;
4. Shopee baru keluar pada `SHIPPED`;
5. TikTok Shop baru keluar pada `IN_TRANSIT`;
6. FEFO memilih batch eligible secara deterministik;
7. transaksi bersamaan tidak menghasilkan stok negatif atau over-allocation;
8. event dan command yang diulang tidak menggandakan effect;
9. bundle tidak memiliki stok tersendiri;
10. retur hanya menambah stok setelah physical receipt;
11. retur masuk `QUARANTINE` sebelum inspection;
12. klaim tidak mengubah stok;
13. stok opname memperbaiki fisik-vs-ledger melalui adjustment, bukan edit saldo;
14. rekonsiliasi menemukan drift dan sumber mismatch;
15. notifikasi tidak menggantikan tindakan domain;
16. Admin hanya dapat mengakses organisasi sendiri;
17. direct write ke ledger, audit, projection, dan posted record ditolak;
18. simulator, impor, dan API masa depan menggunakan pipeline domain yang sama;
19. flow utama dapat digunakan pada desktop dan mobile;
20. deployment live dapat mendemonstrasikan seluruh skenario emas secara stabil.

> **Prinsip pengujian:** test harus membuktikan invariant dan efek database, bukan hanya memeriksa bahwa tombol dapat diklik.

---

## 2. Kedudukan Dokumen

Dokumen ini menjadi sumber kebenaran utama untuk:

- test strategy;
- test level;
- scenario ID;
- test priority;
- test data;
- golden fixtures;
- test isolation;
- concurrency harness;
- CI pipeline;
- test evidence;
- flakiness policy;
- coverage gate;
- performance threshold;
- UAT;
- demo acceptance;
- release criteria.

Aturan domain tetap mengacu pada dokumen sumber masing-masing.

Jika sebuah test bertentangan dengan business rule:

```text
business rule wins
test must be corrected
```

Jika implementasi dan test sama-sama berbeda dari keputusan bisnis:

```text
implementation and test both fail
```

Test tidak boleh mengabadikan bug hanya karena snapshot lama merasa nyaman dengan hasil yang salah.

Keputusan terbaru yang mengikat:

```text
Hanya ada satu user role aplikasi: ADMIN.
```

---

## 3. Mandat Pengujian dari Brief Proyek

Urutan penilaian source project adalah:

1. logika stok benar dan selisih dapat ditelusuri;
2. fitur sesuai cakupan;
3. mudah dipakai operator gudang;
4. kualitas teknis dan deployment stabil.

Strategi pengujian mengikuti prioritas yang sama.

### 3.1 Konsekuensi

- kegagalan invariant stok adalah blocker mutlak;
- happy path tidak cukup;
- skenario pembatalan, retur, manual outbound, duplicate, concurrency, dan opname wajib;
- UI test harus memeriksa bahasa bisnis dan usability;
- deployment test harus dilakukan pada build production;
- traceability dari UI ke ledger dan source wajib diuji;
- tidak ada pencatatan harga pada schema, form, API, atau test data.

---

## 4. Sasaran Pengujian

| ID | Sasaran |
|---|---|
| `TST-GOAL-001` | Setiap requirement P0/P1 memiliki satu atau lebih test otomatis atau acceptance test terdokumentasi. |
| `TST-GOAL-002` | Semua invariant stok diuji pada database dan minimal satu E2E flow. |
| `TST-GOAL-003` | Semua command mutation kritis diuji untuk success, validation failure, duplicate retry, payload conflict, dan unauthorized access. |
| `TST-GOAL-004` | Concurrency diuji menggunakan sesi database/request yang benar-benar paralel. |
| `TST-GOAL-005` | RLS diuji positif dan negatif. |
| `TST-GOAL-006` | Test data dapat dibuat ulang melalui migration dan seed. |
| `TST-GOAL-007` | Test tidak bergantung pada data production. |
| `TST-GOAL-008` | E2E menggunakan locator berbasis role/label atau test ID yang stabil, bukan selector CSS rapuh. |
| `TST-GOAL-009` | Flaky test tidak dibiarkan menjadi kebisingan permanen. |
| `TST-GOAL-010` | Failure menghasilkan artefak yang cukup untuk investigasi. |
| `TST-GOAL-011` | Test suite dapat dijalankan lokal dan CI. |
| `TST-GOAL-012` | Release gate dapat menghentikan deployment saat P0/P1 gagal. |
| `TST-GOAL-013` | Performance test memiliki threshold pass/fail. |
| `TST-GOAL-014` | Accessibility diuji secara otomatis dan manual. |
| `TST-GOAL-015` | UAT/demo pack membuktikan prioritas brief tanpa manipulasi database manual. |

---

## 5. Ruang Lingkup

### 5.1 Termasuk

- static analysis;
- TypeScript typecheck;
- lint;
- unit test;
- component test;
- database structure test;
- database function test;
- RLS test;
- integration test;
- contract test;
- E2E;
- concurrency;
- property-based test;
- migration test;
- security test;
- accessibility test;
- performance/load test;
- reliability/recovery test;
- UAT;
- live demo smoke test.

### 5.2 Tidak Termasuk Fase 1

- pengujian pembayaran;
- nilai inventory;
- marketplace API production;
- native mobile app;
- multi-warehouse;
- serial-number inventory;
- hardware scanner certification;
- disaster recovery lintas region formal;
- penetration test berbayar wajib;
- browser push;
- email/WhatsApp notification;
- accounting integration.

---

## 6. Istilah Normatif

| Istilah | Arti |
|---|---|
| `MUST` | Wajib; kegagalan adalah defect. |
| `MUST NOT` | Dilarang; keberadaan adalah defect. |
| `SHOULD` | Direkomendasikan kuat; penyimpangan membutuhkan alasan. |
| `MAY` | Opsional. |
| P0 | Invariant/security/release blocker. |
| P1 | Flow utama dan feature acceptance. |
| P2 | Edge case penting, UX, operasional tambahan. |
| P3 | Enhancement/cosmetic. |
| Golden fixture | Dataset deterministik dengan hasil yang diketahui. |
| Oracle | Nilai/keadaan yang diharapkan test. |
| Test double | Fake/mock/stub untuk dependency tertentu. |
| Flaky | Hasil berubah tanpa perubahan kode/data yang relevan. |
| Quarantine test | Test sementara dipisahkan karena defect test yang telah ditiketkan. |
| Mutation command | Operasi yang mengubah state domain. |
| State assertion | Pemeriksaan UI/status. |
| Database assertion | Pemeriksaan row, ledger, projection, audit, dan constraint. |
| Negative test | Membuktikan operasi terlarang gagal. |
| Concurrency test | Menjalankan operasi benar-benar paralel. |
| UAT | User Acceptance Testing. |
| Release gate | Kondisi otomatis/manual yang wajib lulus sebelum rilis. |

---

## 7. Prinsip Pengujian

### 7.1 Database Is the Final Oracle for Stock

Untuk quantity fisik:

```text
ledger is the source of truth
```

UI assertion tanpa database assertion tidak cukup untuk mutation P0.

### 7.2 Test Observable Business Effects

Test tidak bergantung pada internal implementation detail yang tidak relevan.

Yang diuji:

- status;
- quantity;
- source reference;
- ledger;
- allocation;
- audit;
- error contract.

### 7.3 Test Negative Space

Setiap command kritis diuji untuk membuktikan bahwa hal berikut tidak terjadi:

```text
no duplicate movement
no negative stock
no cross-organization access
no direct ledger write
no partial transaction
no auto-restock after physical outbound
no sellable return before inspection
```

### 7.4 Deterministic Data

- seed versioned;
- clock controlled;
- IDs test dapat diprediksi atau diambil dari fixture result;
- tidak memakai data “yang kebetulan ada”;
- urutan batch eksplisit;
- setiap test membersihkan atau mengisolasi data.

### 7.5 Real Database for Domain Integration

Mock database tidak membuktikan:

- constraint;
- transaction;
- lock;
- RLS;
- `SECURITY DEFINER`;
- idempotency unique index;
- concurrent update.

Semua hal tersebut diuji pada PostgreSQL/Supabase lokal atau environment test.

### 7.6 Mock Only at External Boundary

Mock boleh digunakan untuk:

- unavailable future marketplace API;
- clock;
- file system pada unit test;
- browser APIs;
- network failure yang sulit dibuat.

Domain database utama tidak dimock pada integration/P0 test.

### 7.7 No Arbitrary Sleep

Dilarang menggunakan `sleep(3000)` untuk “menunggu UI”.

Gunakan:

- web-first assertions;
- event/status polling;
- database condition;
- explicit job completion.

### 7.8 Retry Is Diagnostic, Not Forgiveness

Retry CI boleh membantu menangkap transient browser issue.

Test yang hanya lulus setelah retry:

```text
classified as flaky
must be investigated
```

Retry tidak mengubah failure menjadi bukti kualitas.

---

## 8. Piramida dan Lapisan Test

| Lapisan | Tujuan | Tool Baseline | Frekuensi |
|---|---|---|---|
| Static | Type, lint, secret, migration lint | TypeScript, ESLint, scanner | Setiap PR |
| Unit | Pure domain function, formula, mapper | Vitest | Setiap PR |
| Component | Form/state/rendering | Vitest + React Testing Library | Setiap PR |
| Database | Schema, constraints, RLS, functions | pgTAP + Supabase CLI | Setiap PR |
| Integration | Server boundary + local Supabase | Vitest/Node test harness | Setiap PR |
| Contract | DTO, event, CSV, error contract | Vitest + schema fixtures | Setiap PR |
| E2E | Flow pengguna pada production build | Playwright | PR/merge/release |
| Concurrency | Lock, idempotency, atomicity | DB/API parallel harness | Merge/nightly |
| Property | Invariant pada data acak | Vitest + generator/SQL harness | Nightly |
| Security | WSTG-derived negative tests | pgTAP, Playwright, manual | Merge/release |
| Accessibility | Keyboard, semantics, errors | Playwright + manual WCAG | Merge/release |
| Performance | Throughput/latency thresholds | k6 | Nightly/release |
| UAT | Kecocokan kebutuhan operasional | Script manual terkontrol | Release |

---

## 9. Toolchain Baseline

### 9.1 Vitest

Digunakan untuk:

- unit test;
- synchronous component test;
- mapper;
- formula;
- validation;
- DTO;
- test helper.

Async Server Components diuji melalui integration/E2E, bukan dipaksa masuk unit test yang tidak membuktikan runtime sebenarnya.

### 9.2 React Testing Library

Digunakan untuk:

- behavior komponen;
- accessible name;
- form validation;
- state;
- keyboard interaction sederhana.

### 9.3 pgTAP dan Supabase CLI

Digunakan untuk:

- schema;
- column;
- constraint;
- index;
- RLS;
- grants;
- database function;
- data integrity.

Command baseline:

```bash
supabase db reset
supabase test db
```

### 9.4 Playwright

Digunakan untuk:

- E2E production build;
- Chromium, Firefox, WebKit;
- desktop/mobile projects;
- isolated browser contexts;
- authenticated storage state;
- web-first assertions;
- trace viewer;
- HTML/JUnit report.

### 9.5 k6

Digunakan untuk:

- load scenario;
- concurrent read/write;
- threshold pass/fail;
- latency percentile;
- error rate;
- workload composition.

### 9.6 OWASP WSTG

Digunakan sebagai checklist manual/otomatis untuk:

- identity;
- authentication;
- authorization;
- session;
- input validation;
- error handling;
- business logic;
- client-side security.

### 9.7 WCAG 2.2

Digunakan untuk:

- status messages;
- error identification;
- focus order;
- keyboard;
- focus visibility;
- semantics.

---

## 10. Struktur Repo yang Direkomendasikan

```text
tests/
├── unit/
│   ├── domain/
│   ├── validation/
│   └── mapping/
├── component/
├── integration/
│   ├── api/
│   ├── commands/
│   └── events/
├── contract/
├── e2e/
│   ├── auth/
│   ├── inventory/
│   ├── marketplace/
│   ├── returns/
│   ├── stocktake/
│   ├── reconciliation/
│   ├── notifications/
│   └── security/
├── concurrency/
├── property/
├── performance/
├── accessibility/
├── fixtures/
├── helpers/
└── reports/

supabase/
├── migrations/
├── seed.sql
└── tests/
    ├── 000_structure.test.sql
    ├── 010_rls.test.sql
    ├── 020_ledger.test.sql
    ├── 030_marketplace.test.sql
    ├── 040_return.test.sql
    ├── 050_stocktake.test.sql
    ├── 060_reconciliation.test.sql
    ├── 070_notification.test.sql
    └── 080_security.test.sql
```

---

## 11. Test Environment

| Environment | Data | Tujuan | Write |
|---|---|---|---|
| Unit | In-memory | Pure logic | No real DB |
| Local Supabase | Seed deterministic | DB/integration | Yes |
| CI ephemeral | Reset per job | Automated suite | Yes |
| Preview | Synthetic isolated org | E2E/UAT smoke | Yes |
| Demo | Synthetic demo org | Live demonstration | Yes |
| Production | Real data | Post-deploy smoke read + controlled writes | Sangat terbatas |

### 11.1 Larangan

- test otomatis tidak berjalan pada production organization;
- seed tidak boleh menimpa production;
- performance test tidak menggunakan production tanpa persetujuan;
- screenshot/trace tidak boleh memuat PII production;
- test service-role tidak berada di browser.

---

## 12. Test Data Strategy

### 12.1 Dataset Organisasi

```text
ORG_TEST_A
ORG_TEST_B
ORG_DEMO
```

### 12.2 User

```text
ADMIN_A_ACTIVE
ADMIN_A_2_ACTIVE
ADMIN_A_INACTIVE
ADMIN_B_ACTIVE
```

### 12.3 Product Golden Set

```text
SKU-A  normal multi-batch
SKU-B  bundle component
SKU-C  zero stock
SKU-D  missing expiry
SKU-E  blocked batch
SKU-F  expired batch
SKU-G  quarantine return
SKU-H  damaged stock
SKU-I  controlled unidentified return batch
SKU-J  high-contention product
```

### 12.4 Batch Golden Set

```text
A1 expiry +10 days, sellable 5
A2 expiry +30 days, sellable 20
A3 expiry +30 days, earlier receipt, sellable 4
A4 expired, sellable 10
A5 blocked, sellable 10
A6 quarantine 7
A7 damaged 3
A8 unidentified return quarantine 2
```

### 12.5 Listing Golden Set

```text
SHOPEE-SKU-A -> SKU-A
TIKTOK-SKU-A -> SKU-A
SHOPEE-BUNDLE-AB -> 2A + 1B
TIKTOK-BUNDLE-AB -> 2A + 1B
MISSING-MAPPING -> none
```

### 12.6 Clock

Test clock:

```text
2026-07-15T10:00:00+07:00
```

Test yang bergantung waktu menggunakan injected clock atau explicit timestamp.

Jangan menggunakan `now()` yang tidak dikontrol untuk expected value tanpa boundary yang jelas.

---

## 13. Seed dan Reset

Seed harus:

- versioned;
- idempoten terhadap database kosong;
- tidak bergantung pada order manual;
- menghasilkan ID/reference yang dapat dipakai fixture;
- memuat organisasi A/B;
- memuat active/inactive Admin profile;
- memuat product/batch/listing;
- tidak memuat secret;
- tidak memuat data pembeli nyata.

Reset:

```bash
supabase db reset
```

menghasilkan keadaan yang sama.

---

## 14. Test Isolation

### 14.1 Unit

Tidak berbagi mutable global state.

### 14.2 Database

Pilihan:

- reset database per job;
- transaction rollback per test jika kompatibel;
- unique test namespace;
- cleanup terverifikasi.

### 14.3 E2E

- browser context isolated;
- data dibuat melalui fixture/API;
- test dapat berjalan paralel hanya bila dataset tidak berbagi mutable entity;
- test contention diberi serial project khusus;
- tidak bergantung pada urutan test lain.

### 14.4 Time-Based Jobs

Scheduler test memakai:

- explicit evaluation time;
- direct invocation function;
- no waiting days in real time.

---

## 15. Prioritas

| Priority | Definisi | Contoh | Gate |
|---|---|---|---|
| P0 | Invariant, security, data corruption | ledger, FEFO, RLS, idempotency | Semua PR/release |
| P1 | Main flow, acceptance, usability | receipt, return, stocktake UI | Merge/release |
| P2 | Edge operational, browser/device | filter, extra notification | Nightly/release |
| P3 | Cosmetic/enhancement | minor animation | Non-blocking |

P0 yang gagal:

```text
release stops
```

Tidak ada waiver “sementara” untuk P0 stock integrity.

---

## 16. Tags

```text
@p0
@p1
@db
@rls
@ledger
@fefo
@concurrency
@marketplace
@return
@stocktake
@reconciliation
@notification
@security
@a11y
@mobile
@performance
@smoke
@demo
```

Tag memungkinkan subset run.

---

## 17. Format Test Case

```yaml
id: TST-FEFO-002
title: Split allocation across two batches
references:
  - 03-business-rules.md
  - 04-stock-ledger-design.md
  - 10-fefo-batch-allocation.md
priority: P0
level:
  - database
  - integration
preconditions:
  - product A active
  - batch A1 sellable 5 expiry +10
  - batch A2 sellable 20 expiry +30
input:
  requested_qty: 12
steps:
  - post physical outbound
expected:
  domain:
    - allocation A1 = 5
    - allocation A2 = 7
  ledger:
    - A1 SELLABLE -5
    - A2 SELLABLE -7
  projection:
    - no negative
  audit:
    - allocation group and actor recorded
cleanup:
  - reset fixture or rollback
```

---

## 18. Assertion Minimum untuk Mutation P0

Setiap mutation P0 memeriksa:

1. response code;
2. domain status;
3. transaction header;
4. ledger entry;
5. projection;
6. source reference;
7. actor/process;
8. audit;
9. idempotency result;
10. absence of unintended rows;
11. reconciliation invariant bila relevan.

---

## 19. Coverage Policy

Coverage adalah indikator, bukan oracle correctness.

Baseline gate:

```text
global:
  statements >= 80%
  lines >= 80%
  functions >= 80%
  branches >= 75%

critical domain modules:
  branches >= 90%
```

Module kritis:

```text
ledger formulas
FEFO allocator
reservation math
return quantity accounting
stocktake expected/variance
idempotency
authorization helpers
event mapping
```

Uncovered branch pada invariant P0 membutuhkan test atau documented exclusion yang disetujui.

Snapshot coverage tidak menggantikan database/E2E test.

---

## 20. Flakiness Policy

Test flaky:

- diberi issue;
- memiliki owner;
- memiliki deadline;
- artefak disimpan;
- tidak dibiarkan retry hijau berbulan-bulan.

Dilarang memperbaiki flaky dengan:

```text
arbitrary sleep
wider timeout tanpa diagnosis
selector CSS rapuh
skip permanen
```

Playwright:

```text
local retries = 0
CI retries = 1 untuk diagnosis
trace = retain-on-failure / first retry
```

P0 flaky dianggap gagal sampai root cause ditemukan.

---

## 21. Test Evidence

CI artifacts:

- unit coverage;
- pgTAP output;
- Playwright HTML report;
- trace on failure;
- screenshot on failure;
- JUnit XML;
- k6 summary;
- migration log;
- seed version;
- test environment commit SHA;
- failed SQL/DTO sanitized.

No secret or production PII.

---

## 22. CI Pipeline

### 22.1 Pull Request Quick Gate

```text
install
typecheck
lint
unit
component
migration apply
pgTAP P0
integration P0
build production
Playwright smoke Chromium
secret scan
```

### 22.2 Merge Gate

```text
all PR checks
full pgTAP
full integration
Playwright P0/P1 Chromium
security negative suite
migration reset test
```

### 22.3 Nightly

```text
cross-browser E2E
mobile E2E
concurrency
property-based
scheduler/time rules
performance smoke
accessibility sweep
full reconciliation
```

### 22.4 Release Candidate

```text
all P0/P1
full browser matrix
security review
performance thresholds
migration from previous version
backup/restore smoke
UAT
live demo script
```

### 22.5 Post-Deploy

- health endpoint;
- login;
- read stock;
- controlled synthetic transaction on demo org;
- reconciliation check;
- no production destructive test.

---

## 23. Release Gate Matrix

| Gate | PR | Merge | Release |
|---|:---:|:---:|:---:|
| Typecheck/lint | Wajib | Wajib | Wajib |
| Unit/component | Wajib | Wajib | Wajib |
| pgTAP P0 | Wajib | Wajib | Wajib |
| Full pgTAP | Opsional | Wajib | Wajib |
| Integration P0 | Wajib | Wajib | Wajib |
| E2E smoke | Wajib | Wajib | Wajib |
| Full P0/P1 E2E | Opsional | Wajib | Wajib |
| Cross-browser | Tidak | Nightly | Wajib |
| Concurrency | Selected | Wajib | Wajib |
| Security manual | Tidak | Selected | Wajib |
| Accessibility | Selected | Wajib | Wajib |
| Performance | Tidak | Smoke | Wajib |
| UAT | Tidak | Tidak | Wajib |

---

## 24. Invariant Global

| ID | Invariant |
|---|---|
| `INV-001` | Setiap perubahan quantity fisik mempunyai ledger entry. |
| `INV-002` | Ledger posted append-only. |
| `INV-003` | Projection dapat dibangun ulang dari ledger. |
| `INV-004` | Saldo bucket tidak negatif. |
| `INV-005` | Reservasi tidak mengubah on-hand. |
| `INV-006` | Available = sellable - active reserved. |
| `INV-007` | Allocation total = physical outbound quantity. |
| `INV-008` | Internal transfer net zero. |
| `INV-009` | Reversal tidak melebihi original. |
| `INV-010` | Duplicate command/event menghasilkan maksimal satu effect. |
| `INV-011` | Batch FEFO yang dipilih eligible pada operational date. |
| `INV-012` | Bundle tidak memiliki stock. |
| `INV-013` | Return expected tidak menambah stock. |
| `INV-014` | Return received masuk quarantine. |
| `INV-015` | Inspection memindahkan quarantine ke sellable/damaged. |
| `INV-016` | Lost/claim tidak menambah stock. |
| `INV-017` | Stocktake adjustment = approved physical - expected. |
| `INV-018` | Data organisasi tidak bocor lintas scope. |
| `INV-019` | Actor dan organization berasal dari trusted context. |
| `INV-020` | Sistem tidak menyimpan harga/nilai uang fase 1. |

---

## 25. Golden Ledger Equation

Untuk setiap product/batch/bucket:

```text
opening
+ inbound
+ return receipt
+ bucket transfer in
+ positive adjustment
+ reversal in
- outbound
- disposal
- bucket transfer out
- negative adjustment
- reversal out
=
ledger balance
```

Untuk product position:

```text
sellable = SUM(batch sellable)
quarantine = SUM(batch quarantine)
damaged = SUM(batch damaged)
reserved = SUM(active reservation remaining)
available = sellable - reserved
```

Test oracle tidak membaca angka dari UI untuk menghitung expected.

---

## 26. P0 Smoke Pack

P0 smoke pack wajib selesai cepat dan membuktikan jalur inti:

| Urutan | Scenario |
|---:|---|
| 1 | Login Admin aktif |
| 2 | Penerimaan maklon |
| 3 | Pesanan baru hanya reservation |
| 4 | Shopee `SHIPPED` FEFO outbound |
| 5 | TikTok `IN_TRANSIT` FEFO outbound |
| 6 | Cancel sebelum shipment |
| 7 | Cancel setelah shipment |
| 8 | Manual bonus |
| 9 | Bundle normalization |
| 10 | Return receipt quarantine |
| 11 | Return inspection sellable/damaged |
| 12 | Return lost + claim no stock |
| 13 | Duplicate event |
| 14 | Insufficient stock rollback |
| 15 | Concurrent last unit |
| 16 | Reversal |
| 17 | Frozen stocktake adjustment |
| 18 | Reconciliation detects drift |
| 19 | Notification expiry/claim |
| 20 | Cross-organization denial |

---

## 27. Canonical Scenario: Penerimaan Maklon

### Preconditions

```text
SKU-A active
Batch A1 valid expiry
Current sellable = 0
```

### Action

Admin posts receipt:

```text
SKU-A / Batch A1 / 20 units
```

### Assertions

```text
stock transaction type = MAKLON_RECEIPT
ledger A1 SELLABLE +20
batch projection = 20
product sellable = 20
available = 20
source document linked
actor Admin linked
audit linked
```

### Negative

Retry same key:

```text
same transaction returned
no second +20
```

---

## 28. Canonical Scenario: Reservation

### Preconditions

```text
SKU-A sellable = 20
reserved = 0
```

### Action

Order quantity 4 created.

### Assertions

```text
sellable = 20
reserved = 4
available = 16
ledger movement count = 0
order = RESERVED
```

---

## 29. Canonical Scenario: Shopee Physical Outbound

### Action

Canonical event:

```text
ORDER_SHIPPED
sourceStatus = SHIPPED
```

### Assertions

```text
FEFO allocation exists
outbound ledger = -4
reservation consumed = 4
sellable decreases by 4
order = PHYSICALLY_OUT
event = PROCESSED
```

Event `READY_TO_SHIP` must not produce the same effect.

---

## 30. Canonical Scenario: TikTok Physical Outbound

Event:

```text
ORDER_IN_TRANSIT
sourceStatus = IN_TRANSIT
```

Expected:

- same physical effects as valid outbound;
- no second outbound at completed;
- earlier statuses only reserve.

---

## 31. Canonical Scenario: Cancel Before Outbound

Expected:

```text
reservation released
available restored
on-hand unchanged
ledger outbound absent
order = CANCELLED_PRE_SHIPMENT
```

---

## 32. Canonical Scenario: Cancel After Outbound

Expected:

```text
outbound remains
no automatic inbound
return obligation/exception created
order = CANCELLED_POST_SHIPMENT
```

---

## 33. Canonical Scenario: Manual Bonus

Input:

```text
reason = BONUS
channel = MANUAL
```

Expected:

- FEFO;
- outbound ledger;
- reason remains bonus;
- not counted as offline sale;
- source document linked.

---

## 34. Canonical Scenario: FEFO Split

Fixture:

```text
A1 expiry +10, balance 5
A2 expiry +30, balance 20
request = 12
```

Expected:

```text
A1 5 rank 1
A2 7 rank 2
ledger total -12
```

---

## 35. Canonical Scenario: Bundle

Input:

```text
2 x BUNDLE-AB
recipe = 2A + 1B
```

Expected:

```text
A = 4
B = 2
no bundle balance
reservations and allocations per component
recipe snapshot stored
```

---

## 36. Canonical Scenario: Return Sellable

Flow:

```text
RETURN_EXPECTED
RETURN_IN_TRANSIT
PHYSICAL_RECEIPT
INSPECT_SELLABLE
```

Expected ledger:

```text
receipt: QUARANTINE +qty
inspection: QUARANTINE -qty, SELLABLE +qty
```

Expected/source events before physical receipt create no movement.

---

## 37. Canonical Scenario: Return Damaged

Expected:

```text
receipt -> QUARANTINE
inspection -> DAMAGED
available unchanged by damaged
```

---

## 38. Canonical Scenario: Return Lost dan Klaim

Expected:

```text
lost quantity recorded
no inbound ledger
claim deadline snapshot stored
claim status changes create no ledger
notification uses claim.deadline_at
```

---

## 39. Canonical Scenario: Duplicate Event

Send same external event and payload twice.

Expected:

```text
first = PROCESSED
second = DUPLICATE
domain effect count = 1
```

Same ID with changed payload:

```text
REJECTED
IDEMPOTENCY_PAYLOAD_MISMATCH
```

---

## 40. Canonical Scenario: Insufficient Stock

Requested eligible quantity exceeds available/eligible stock.

Expected:

```text
no allocation
no ledger
no projection change
no reservation consumption
source status not physically out
```

---

## 41. Canonical Scenario: Concurrent Last Unit

Fixture:

```text
eligible stock = 1
two parallel outbound commands = 1 each
```

Expected:

```text
one success
one business failure
final balance = 0
no negative
no duplicate allocation
```

Test must use two actual connections/requests.

---

## 42. Canonical Scenario: Reversal

Original:

```text
outbound -5
```

Reverse 2:

```text
reversal +2
```

Expected:

- original immutable;
- applied reversal <= original;
- projection reflects net -3;
- source/audit trace preserved.

---

## 43. Canonical Scenario: Frozen Stocktake

Flow:

```text
create
start frozen
snapshot
blind count
review
approve
post
reconcile
```

Expected:

- mutation on scope blocked;
- zero count explicit;
- attempts append-only;
- adjustment atomik;
- posted immutable.

---

## 44. Canonical Scenario: Continuous Stocktake

Flow includes movement after snapshot.

Expected:

```text
expected at count = snapshot + movement to line cutoff
adjustment = physical - expected at count
later movement remains preserved
```

---

## 45. Canonical Scenario: Projection Drift

Corrupt projection only in controlled test fixture.

Expected:

```text
ledger vs projection check fails
critical issue
projection rebuild from ledger
ledger unchanged
verification passes
```

---

## 46. Canonical Scenario: Expiry Notification

Batch enters 90/60/30/expired threshold.

Expected:

- one active episode;
- stage escalates;
- Admin read state reset on escalation;
- zero relevant balance resolves;
- notification never changes stock.

---

## 47. Canonical Scenario: Cross-Organization Access

Admin A requests valid entity B.

Expected:

```text
no data
no mutation
no existence leak beyond safe contract
security log where appropriate
```

---

## 48. Scenario Catalog

## Authentication dan Akun Admin

| ID | Priority | Layer | Scenario | Expected |
|---|---|---|---|---|
| TST-AUTH-001 | P0 | E2E/API/DB | Request tanpa session membuka halaman aplikasi atau endpoint mutasi. | `401`/redirect login; tidak ada perubahan data. |
| TST-AUTH-002 | P0 | API/DB | Profil ada tetapi `is_active = false`. | Akses ditolak segera meskipun session/JWT masih ada. |
| TST-AUTH-003 | P0 | DB | Profil mencoba memakai role selain `ADMIN`. | Constraint menolak row. |
| TST-AUTH-004 | P0 | E2E/API | Admin organisasi A mengganti UUID URL dengan entitas organisasi B. | Data tidak terungkap; mutation ditolak. |
| TST-AUTH-005 | P0 | API | `organization_id`, `actor_user_id`, atau `role` dikirim dari body. | Field ditolak/diabaikan; server memakai context terverifikasi. |
| TST-AUTH-006 | P1 | E2E | Login valid Admin aktif. | Masuk dashboard; actor dan organisasi benar. |
| TST-AUTH-007 | P1 | E2E | Logout melalui command resmi. | Session dihapus; halaman privat tidak dapat dibuka kembali. |
| TST-AUTH-008 | P0 | API/DB | Tindakan sensitif production dilakukan pada `aal1`. | Ditolak dengan `APP_MFA_REQUIRED`. |
| TST-AUTH-009 | P0 | API/DB | Tindakan sensitif production dilakukan pada `aal2`. | Dapat lanjut bila seluruh validasi domain lulus. |
| TST-AUTH-010 | P0 | DB/API | Admin terakhir mencoba menonaktifkan dirinya/akun terakhir. | Ditolak oleh last-admin guard. |
| TST-AUTH-011 | P1 | API | Dua Admin membaca notifikasi yang sama. | Status baca terpisah per akun. |
| TST-AUTH-012 | P1 | E2E | Session kedaluwarsa saat form sensitif terbuka. | Posting ditolak; draft tidak dianggap posted. |
| TST-AUTH-013 | P0 | Build | Bundle client diperiksa terhadap service-role/database secret. | Tidak ditemukan secret server. |
| TST-AUTH-014 | P1 | API | Origin mutation tidak sesuai allowlist. | Request ditolak; tidak ada side effect. |
| TST-AUTH-015 | P2 | E2E | Login error memakai credential salah. | Pesan aman; tidak membocorkan detail akun. |

## Produk, Batch, dan Saldo Awal

| ID | Priority | Layer | Scenario | Expected |
|---|---|---|---|---|
| TST-MST-001 | P0 | DB/API | Membuat produk dengan SKU unik dan batch tracking aktif. | Produk tersimpan dalam organisasi saat ini. |
| TST-MST-002 | P0 | DB | SKU duplikat pada organisasi yang sama. | Unique constraint menolak. |
| TST-MST-003 | P1 | DB | SKU sama pada organisasi berbeda. | Diperbolehkan bila uniqueness berscope organisasi. |
| TST-MST-004 | P0 | DB/API | Batch tanpa expiry untuk produk expiry-tracked. | Ditolak atau masuk exception; tidak eligible FEFO. |
| TST-MST-005 | P0 | DB | Batch menunjuk produk dari organisasi lain. | FK/validasi organisasi menolak. |
| TST-MST-006 | P0 | DB/API | Batch code duplikat pada produk yang sama. | Ditolak sesuai unique key. |
| TST-MST-007 | P1 | API | Batch diblokir dengan reason dan audit. | Saldo tetap ada; FEFO mengecualikan batch. |
| TST-MST-008 | P0 | DB/API | Batch archived masih mempunyai saldo. | Archive ditolak atau reconciliation issue dibuat. |
| TST-MST-009 | P0 | DB/API | Saldo awal diposting. | Ledger transaction `INITIAL_BALANCE`; projection cocok. |
| TST-MST-010 | P0 | DB/API | Saldo awal yang sama di-submit ulang dengan key sama. | Hasil lama dikembalikan; tidak ada entry kedua. |
| TST-MST-011 | P0 | DB/API | Key saldo awal sama tetapi quantity berbeda. | `IDEMPOTENCY_PAYLOAD_MISMATCH`; tanpa movement baru. |
| TST-MST-012 | P1 | E2E | Admin mencari produk berdasarkan SKU/nama. | Hasil sesuai organisasi dan filter. |
| TST-MST-013 | P1 | E2E | Posisi produk menampilkan sellable/reserved/available/quarantine/damaged. | Rumus dan label benar. |
| TST-MST-014 | P0 | DB | Client mencoba update langsung stock balance. | Grant/RLS menolak. |
| TST-MST-015 | P0 | DB | Client mencoba update expiry batch tanpa function. | Ditolak; perubahan hanya melalui command terkontrol. |
| TST-MST-016 | P1 | Reconciliation | Batch status `ACTIVE` tetapi tanggal sudah lewat. | Batch excluded; issue master/expiry terdeteksi. |

## Penerimaan Maklon

| ID | Priority | Layer | Scenario | Expected |
|---|---|---|---|---|
| TST-INB-001 | P0 | API/DB/E2E | Penerimaan satu produk satu batch. | Ledger `MAKLON_RECEIPT` menambah sellable; projection cocok. |
| TST-INB-002 | P0 | API/DB | Satu dokumen penerimaan berisi beberapa produk/batch. | Semua line posted atomik. |
| TST-INB-003 | P0 | DB | Satu line invalid dalam dokumen multi-line. | Seluruh posting rollback. |
| TST-INB-004 | P0 | API/DB | Retry penerimaan identik. | Idempoten; satu transaction. |
| TST-INB-005 | P0 | API/DB | Nomor dokumen sama dengan payload berbeda. | Conflict ditolak. |
| TST-INB-006 | P0 | DB/API | Quantity nol/negatif. | Ditolak sebelum ledger. |
| TST-INB-007 | P0 | DB/API | Batch tidak cocok dengan produk. | Ditolak. |
| TST-INB-008 | P1 | API/E2E | Receipt draft disimpan. | Tidak mengubah stok hingga posted. |
| TST-INB-009 | P0 | DB | Posted receipt dicoba diedit. | Ditolak; koreksi lewat reversal. |
| TST-INB-010 | P0 | DB/API | Receipt direversal sebagian. | Opposite delta tepat; original tetap ada. |
| TST-INB-011 | P1 | Reconciliation | Receipt header posted tanpa ledger. | Issue `HIGH/CRITICAL` dibuat. |
| TST-INB-012 | P1 | E2E | Mobile form receipt menampilkan preview movement. | Admin melihat batch, quantity, dan bucket sebelum posting. |

## Pesanan Marketplace dan Reservasi

| ID | Priority | Layer | Scenario | Expected |
|---|---|---|---|---|
| TST-ORD-001 | P0 | API/DB | Pesanan Shopee baru masuk. | Order dibuat; reservation aktif; stock fisik tidak berubah. |
| TST-ORD-002 | P0 | API/DB | Pesanan TikTok baru masuk. | Order dibuat; reservation aktif; stock fisik tidak berubah. |
| TST-ORD-003 | P0 | DB | `available = sellable - active_reserved` setelah order. | Rumus tepat dan tidak negatif. |
| TST-ORD-004 | P0 | API/DB | Order quantity melebihi available. | Order `STOCK_EXCEPTION`; tidak ada reservation parsial. |
| TST-ORD-005 | P0 | API/DB | Duplicate `ORDER_CREATED` identik. | Satu order/reservation; event kedua duplicate. |
| TST-ORD-006 | P0 | API/DB | External event ID sama, payload berbeda. | Ditolak sebagai conflict. |
| TST-ORD-007 | P0 | API/DB | Shopee mencapai `SHIPPED`. | FEFO allocation dan physical outbound terjadi. |
| TST-ORD-008 | P0 | API/DB | Shopee baru `READY_TO_SHIP`. | Tidak ada physical outbound. |
| TST-ORD-009 | P0 | API/DB | TikTok mencapai `IN_TRANSIT`. | FEFO allocation dan physical outbound terjadi. |
| TST-ORD-010 | P0 | API/DB | TikTok masih `AWAITING_COLLECTION`. | Tidak ada physical outbound. |
| TST-ORD-011 | P0 | API/DB | Order completed setelah outbound. | Tidak ada outbound kedua. |
| TST-ORD-012 | P0 | API/DB | Cancel sebelum outbound. | Reservation dilepas; stock fisik tetap. |
| TST-ORD-013 | P0 | API/DB | Cancel setelah outbound. | Tidak ada auto-restock; return obligation/exception terbentuk. |
| TST-ORD-014 | P0 | API/DB | Event shipment datang sebelum order created. | Ditolak/held sesuai policy; tidak mengarang movement. |
| TST-ORD-015 | P1 | API/DB | Event stale pra-shipment datang setelah physical out. | Diabaikan tercatat; state tidak mundur. |
| TST-ORD-016 | P0 | DB | Order physical out tanpa ledger. | Reconciliation critical. |
| TST-ORD-017 | P0 | DB | Ledger outbound tetapi order belum physical out. | Reconciliation high/critical. |
| TST-ORD-018 | P1 | E2E | Order detail drill-down ke event, reservation, allocation, ledger. | Semua tautan konsisten. |
| TST-ORD-019 | P0 | DB/API | Shipment quantity melebihi reservation. | Ditolak; no movement. |
| TST-ORD-020 | P0 | Concurrency | Dua event shipment identik diproses paralel. | Satu domain effect. |
| TST-ORD-021 | P1 | API/DB | Order line mapping listing hilang. | Exception; no reservation/ledger. |
| TST-ORD-022 | P1 | E2E | Pesan error stok tidak cukup. | Menjelaskan SKU, requested, available/shortage tanpa raw SQL. |

## Pengeluaran Manual

| ID | Priority | Layer | Scenario | Expected |
|---|---|---|---|---|
| TST-MAN-001 | P0 | API/DB/E2E | Penjualan offline diposting. | Reason sale, channel offline, FEFO, ledger outbound. |
| TST-MAN-002 | P0 | API/DB/E2E | Bonus diposting. | Reason bonus terpisah dari channel manual. |
| TST-MAN-003 | P0 | API/DB/E2E | Promo diposting. | Reason promo; traceable source. |
| TST-MAN-004 | P0 | API/DB/E2E | Sampel diposting. | Reason sample; traceable source. |
| TST-MAN-005 | P0 | API/DB | Barang rusak dipindah/keluar sesuai flow. | Bucket/reason benar; tidak tercampur dengan sale. |
| TST-MAN-006 | P0 | API/DB | Barang kedaluwarsa dibuang. | Batch target jelas; ledger `DISPOSAL_EXPIRED`. |
| TST-MAN-007 | P0 | API/DB | Manual outbound melebihi available karena reservation aktif. | Ditolak; reserved stock terlindungi. |
| TST-MAN-008 | P0 | API/DB | Admin mengirim batch ID untuk outbound normal. | Ditolak; batch dipilih sistem. |
| TST-MAN-009 | P0 | API/DB | Duplicate post tombol manual. | Satu transaction. |
| TST-MAN-010 | P0 | DB | Satu line invalid dalam dokumen manual multi-line. | Atomic rollback. |
| TST-MAN-011 | P1 | E2E | Draft manual outbound. | Tidak mengubah stock. |
| TST-MAN-012 | P1 | Reconciliation | Movement reason/channel hilang. | Issue source completeness. |

## FEFO dan Alokasi Batch

| ID | Priority | Layer | Scenario | Expected |
|---|---|---|---|---|
| TST-FEFO-001 | P0 | DB/API | Satu batch eligible memenuhi seluruh quantity. | Batch itu dipilih; rank 1. |
| TST-FEFO-002 | P0 | DB/API | Quantity memerlukan dua batch. | Split tepat; expiry terdekat habis lebih dulu. |
| TST-FEFO-003 | P0 | DB/API | Tiga batch, satu expired paling dekat. | Expired dilewati. |
| TST-FEFO-004 | P0 | DB/API | Batch terdekat blocked. | Blocked dilewati. |
| TST-FEFO-005 | P0 | DB/API | Batch quarantine atau damaged. | Tidak eligible. |
| TST-FEFO-006 | P0 | DB/API | Controlled unidentified return batch. | Tidak eligible. |
| TST-FEFO-007 | P0 | DB/API | Expiry sama, waktu receipt berbeda. | Receipt lebih awal dipilih. |
| TST-FEFO-008 | P0 | DB/API | Expiry dan receipt time sama. | Batch code/ID memberi hasil deterministik. |
| TST-FEFO-009 | P0 | DB/API | Safety buffer menutup batch. | Batch excluded sesuai snapshot config. |
| TST-FEFO-010 | P0 | DB/API | Stok eligible kurang dari kebutuhan. | Seluruh command gagal; tidak ada partial movement. |
| TST-FEFO-011 | P0 | Concurrency | Dua order bersamaan mengambil unit terakhir. | Satu sukses, satu gagal; tidak negatif. |
| TST-FEFO-012 | P0 | Concurrency | Dua transaksi meminta produk A+B dengan urutan input berbeda. | Lock order deterministik; tidak deadlock permanen. |
| TST-FEFO-013 | P0 | DB/API | Preview memilih batch A, lalu A diblokir sebelum commit. | Commit menghitung ulang. |
| TST-FEFO-014 | P0 | DB/API | Batch expiry lebih dekat masuk setelah reservation. | Dipilih saat physical outbound. |
| TST-FEFO-015 | P0 | DB | Allocation total berbeda dari outbound ledger. | Constraint/check/reconciliation gagal. |
| TST-FEFO-016 | P0 | DB | FEFO rank memiliki gap/duplikat. | Ditolak atau terdeteksi. |
| TST-FEFO-017 | P1 | E2E | Allocation result menampilkan batch, expiry, quantity, rank. | Trace dapat dibuka. |
| TST-FEFO-018 | P0 | DB/API | Allocation retry dengan key sama. | Group/transaction sama. |
| TST-FEFO-019 | P0 | DB/API | Correction allocation. | Reversal + repost; row historis immutable. |
| TST-FEFO-020 | P0 | DB/API | Frozen stocktake hold aktif. | Allocator ditolak. |
| TST-FEFO-021 | P0 | DB/API | Reconciliation hold aktif. | Allocator ditolak. |
| TST-FEFO-022 | P1 | Property | Data batch acak. | Semua selected batch eligible, sorted, total exact, no negative. |

## Bundle

| ID | Priority | Layer | Scenario | Expected |
|---|---|---|---|---|
| TST-BND-001 | P0 | Unit/API/DB | 1 bundle dengan recipe 2A+1B. | Normalized 2A+1B; tidak ada stock bundle. |
| TST-BND-002 | P0 | Unit/API/DB | 3 bundle dengan recipe 2A+1B. | Normalized 6A+3B. |
| TST-BND-003 | P0 | API/DB | Recipe mapping tidak ada. | Order exception; no reservation. |
| TST-BND-004 | P0 | API/DB | Salah satu component stok kurang. | Tidak ada reservation parsial. |
| TST-BND-005 | P0 | DB | Pseudo-product bundle memiliki saldo. | Critical reconciliation. |
| TST-BND-006 | P0 | DB/API | Recipe berubah setelah order masuk. | Order memakai recipe snapshot lama. |
| TST-BND-007 | P0 | DB/API | Bundle dan single listing menghasilkan product sama. | Total product dicek aman; trace source line dipertahankan. |
| TST-BND-008 | P0 | DB/API | Return bundle parsial. | Quantity dinormalisasi ke component snapshot. |
| TST-BND-009 | P1 | E2E | Order detail menampilkan bundle dan breakdown unit. | Keduanya terbaca tanpa stok bundle. |
| TST-BND-010 | P0 | Unit | Recipe quantity nol/negatif/duplicate component. | Validation/normalization deterministik. |

## Retur dan Klaim

| ID | Priority | Layer | Scenario | Expected |
|---|---|---|---|---|
| TST-RET-001 | P0 | API/DB | Expected return dibuat. | Tidak ada stock movement. |
| TST-RET-002 | P0 | API/DB | Physical receipt retur. | `QUARANTINE +qty`. |
| TST-RET-003 | P0 | API/DB | Source marketplace berkata received tanpa konfirmasi fisik. | Tidak ada ledger receipt otomatis. |
| TST-RET-004 | P0 | API/DB | Inspection sellable. | Transfer quarantine ke sellable net zero. |
| TST-RET-005 | P0 | API/DB | Inspection damaged. | Transfer quarantine ke damaged net zero. |
| TST-RET-006 | P0 | API/DB | Mixed inspection. | Quantity split dan status mixed benar. |
| TST-RET-007 | P0 | API/DB | Partial receipt beberapa kali. | Agregat benar; setiap receipt immutable. |
| TST-RET-008 | P0 | API/DB | Receipt melebihi pending return. | Ditolak. |
| TST-RET-009 | P0 | API/DB | Inspection melebihi received uninspected. | Ditolak. |
| TST-RET-010 | P0 | API/DB | Mark lost pada pending arrival. | No ledger; lost quantity bertambah. |
| TST-RET-011 | P0 | API/DB | Mark lost pada quantity sudah received. | Ditolak. |
| TST-RET-012 | P0 | API/DB | Late arrival setelah lost. | Exception + physical receipt; histori lost tetap. |
| TST-RET-013 | P0 | API/DB | Return quantity melebihi physical outbound. | Ditolak. |
| TST-RET-014 | P0 | DB/API | Unknown batch return. | Masuk controlled quarantine; tidak sellable/FEFO. |
| TST-RET-015 | P0 | DB/API | Batch kemudian teridentifikasi. | Quarantine reclassification net zero. |
| TST-RET-016 | P0 | DB/API | Duplicate return event. | Satu return/effect. |
| TST-RET-017 | P0 | DB/API | Receipt double-click. | Satu receipt/ledger. |
| TST-RET-018 | P0 | DB/API | Correction receipt/inspection. | Reversal; original immutable. |
| TST-RET-019 | P0 | API/DB | Klaim eligible dibuat. | Deadline snapshot; no stock effect. |
| TST-RET-020 | P0 | API/DB | Klaim tanpa basis deadline. | Status exception; no guessed date. |
| TST-RET-021 | P0 | API/DB | Klaim disubmit/diselesaikan. | Status berubah; stock tetap. |
| TST-RET-022 | P0 | Scheduler | Deadline 14/7/3/1/due/overdue. | Stage notification tepat, deduplicated. |
| TST-RET-023 | P1 | E2E | Return detail drill-down. | Order, receipt, inspection, claim, ledger terhubung. |
| TST-RET-024 | P0 | Reconciliation | Quantity return tidak balance. | Issue dibuat dengan evidence. |

## Stok Opname

| ID | Priority | Layer | Scenario | Expected |
|---|---|---|---|---|
| TST-STK-001 | P0 | API/DB | Membuat draft stocktake. | Tidak ada stock effect. |
| TST-STK-002 | P0 | DB/API | Start frozen stocktake. | Ledger snapshot + holds atomik. |
| TST-STK-003 | P0 | DB/API | Mutation pada scope frozen. | Ditolak. |
| TST-STK-004 | P0 | DB/API | Start continuous stocktake. | Snapshot tersimpan; operasi tetap berjalan. |
| TST-STK-005 | P0 | DB/API | Submit count continuous. | Server menangkap line cutoff. |
| TST-STK-006 | P0 | E2E/API | Blind count. | Expected/variance tidak bocor dari DTO/UI. |
| TST-STK-007 | P0 | API/DB | Input null. | Tetap not counted, bukan nol. |
| TST-STK-008 | P0 | E2E/API | Input nol tanpa konfirmasi. | Ditolak. |
| TST-STK-009 | P0 | DB/API | Count attempt pertama. | Append-only attempt 1. |
| TST-STK-010 | P0 | DB/API | Recount. | Attempt baru; lama tidak ditimpa. |
| TST-STK-011 | P0 | API/DB | Count melebihi toleransi. | Recount/review required; variance tidak dihapus. |
| TST-STK-012 | P0 | API/DB | Unknown product/batch. | Exception; posting diblokir. |
| TST-STK-013 | P0 | API/DB | Expected frozen. | Sama dengan snapshot. |
| TST-STK-014 | P0 | API/DB | Expected continuous dengan inbound/outbound hingga cutoff. | Formula benar. |
| TST-STK-015 | P0 | API/DB | Approval dibuat. | Snapshot version/hash tersimpan. |
| TST-STK-016 | P0 | API/DB | Count berubah setelah approval. | Approval stale; posting ditolak. |
| TST-STK-017 | P0 | API/DB | Post adjustment multi-line. | Semua line atomik; zero variance tanpa ledger. |
| TST-STK-018 | P0 | API/DB | Duplicate posting request. | Satu transaction. |
| TST-STK-019 | P0 | DB | Posted session diedit. | Ditolak. |
| TST-STK-020 | P0 | API/DB | Projection drift sebelum post. | Rebuild dulu; stocktake tidak dipakai memperbaiki projection. |
| TST-STK-021 | P0 | Reconciliation | Adjustment line tidak cocok variance approved. | Critical issue. |
| TST-STK-022 | P1 | E2E | Mobile count flow. | Task dapat selesai tanpa horizontal scroll utama. |
| TST-STK-023 | P1 | E2E | Movement breakdown. | Setiap agregat dapat dibuka ke ledger. |
| TST-STK-024 | P0 | API/DB | Cancel sesi sebelum post. | Hold dilepas; snapshot/attempt tetap historis. |

## Rekonsiliasi

| ID | Priority | Layer | Scenario | Expected |
|---|---|---|---|---|
| TST-REC-001 | P0 | DB | Ledger sama dengan batch projection. | Check PASS. |
| TST-REC-002 | P0 | DB | Ledger berbeda dengan batch projection. | Critical issue + evidence. |
| TST-REC-003 | P0 | DB | Batch projection berbeda dengan product projection. | Critical issue. |
| TST-REC-004 | P0 | DB | Saldo bucket negatif. | Critical issue/hold. |
| TST-REC-005 | P0 | DB | Reserved melebihi sellable. | Critical issue. |
| TST-REC-006 | P0 | DB | Internal transfer tidak net zero. | Critical issue. |
| TST-REC-007 | P0 | DB | Allocation berbeda dari ledger. | Critical issue. |
| TST-REC-008 | P0 | DB | Duplicate source effect. | Issue high/critical. |
| TST-REC-009 | P0 | DB | Return receipt berbeda dari quarantine inbound. | Issue high. |
| TST-REC-010 | P0 | DB | Reversal melebihi original. | Ditolak/critical issue. |
| TST-REC-011 | P0 | DB | Issue yang sama muncul pada run berikutnya. | Fingerprint update, bukan duplicate open issue. |
| TST-REC-012 | P0 | DB | Issue resolved gagal lagi. | Episode/recurrence linked. |
| TST-REC-013 | P0 | DB | Projection rebuild. | Berasal dari ledger; ledger tidak berubah. |
| TST-REC-014 | P0 | Concurrency | Dua run sejenis bersamaan. | Advisory lock mencegah overlap. |
| TST-REC-015 | P0 | DB | Check error teknis. | Status ERROR, bukan PASS. |
| TST-REC-016 | P1 | E2E | Issue detail. | Expected, actual, difference, evidence, action terlihat. |
| TST-REC-017 | P0 | Scheduler | Daily run gagal/missed. | Failure terlihat; notification dibuat. |
| TST-REC-018 | P0 | DB | Same rule/boundary/version dijalankan ulang. | Hasil deterministik. |

## Notifikasi

| ID | Priority | Layer | Scenario | Expected |
|---|---|---|---|---|
| TST-NTF-001 | P0 | DB/Scheduler | Batch masuk threshold 90 hari. | Satu episode expiry. |
| TST-NTF-002 | P0 | DB/Scheduler | Episode naik 90->60->30->expired. | Row aktif sama, event escalation, unread reset. |
| TST-NTF-003 | P0 | DB/Scheduler | Saldo relevant batch menjadi nol. | Episode resolved. |
| TST-NTF-004 | P0 | DB/Scheduler | Claim melintasi threshold. | Stage/severity tepat berdasarkan deadline stored. |
| TST-NTF-005 | P0 | DB | Claim disubmit. | Reminder pengajuan resolved; stock tidak berubah. |
| TST-NTF-006 | P0 | DB/Scheduler | Return pending inspection melewati SLA. | Satu active episode. |
| TST-NTF-007 | P0 | DB | Inspection selesai. | Notification resolved. |
| TST-NTF-008 | P0 | DB | High/critical reconciliation issue dibuat. | Notification sesuai severity. |
| TST-NTF-009 | P0 | DB | Admin A mark read. | Admin B tetap unread; source tetap aktif. |
| TST-NTF-010 | P0 | DB | Mark read notification critical. | Severity/lifecycle tidak berubah. |
| TST-NTF-011 | P0 | DB | Cron mengevaluasi kondisi sama berulang. | Tidak membuat active duplicate. |
| TST-NTF-012 | P0 | DB | Outbox processor retry. | Satu notification. |
| TST-NTF-013 | P0 | Integration | Renderer notification gagal. | Domain transaction tetap committed. |
| TST-NTF-014 | P0 | DB | Critical notification disuppress. | Ditolak sesuai policy. |
| TST-NTF-015 | P1 | E2E | Deep link notification. | Membuka entitas source dengan authz ulang. |
| TST-NTF-016 | P1 | E2E/A11y | Status baru diumumkan. | Live region sesuai severity; tidak spam. |
| TST-NTF-017 | P1 | E2E | Realtime mati. | Polling/refetch tetap menampilkan data. |
| TST-NTF-018 | P0 | Reconciliation | Source active tanpa notification wajib. | Missing-notification issue/repair. |

## Simulator Marketplace

| ID | Priority | Layer | Scenario | Expected |
|---|---|---|---|---|
| TST-SIM-001 | P0 | Integration/E2E | Shopee happy path preset. | Event masuk pipeline yang sama; outbound pada SHIPPED. |
| TST-SIM-002 | P0 | Integration/E2E | TikTok happy path preset. | Outbound pada IN_TRANSIT. |
| TST-SIM-003 | P0 | Integration | Simulator membuat event. | Tidak menulis ledger langsung. |
| TST-SIM-004 | P0 | Integration | Seed dan fixture sama. | Event ID/payload deterministik. |
| TST-SIM-005 | P0 | Integration | Duplicate event preset. | Satu effect. |
| TST-SIM-006 | P0 | Integration | Out-of-order preset. | State machine menolak/menangani sesuai policy. |
| TST-SIM-007 | P0 | Integration | Insufficient stock preset. | No partial movement. |
| TST-SIM-008 | P0 | Integration | Bundle preset. | Components dinormalisasi. |
| TST-SIM-009 | P0 | Integration | Return source received preset. | Tidak otomatis physical receipt. |
| TST-SIM-010 | P0 | API | Production simulator disabled. | Endpoint menolak. |
| TST-SIM-011 | P0 | API | Demo org mencoba entity production. | Ditolak. |
| TST-SIM-012 | P1 | E2E | Dry run. | Preview tanpa writes. |
| TST-SIM-013 | P1 | E2E | Commit run partial failure. | Step result/audit jelas; prior processed event tidak dihapus. |
| TST-SIM-014 | P1 | Reconciliation | Reconciliation after scenario. | Expected intentional issue saja yang tersisa. |

## Impor CSV

| ID | Priority | Layer | Scenario | Expected |
|---|---|---|---|---|
| TST-IMP-001 | P0 | API/Integration | CSV valid. | Staging, dry run, post melalui domain pipeline. |
| TST-IMP-002 | P0 | Integration | Campuran row valid/invalid. | Error per row; tidak direct mutation. |
| TST-IMP-003 | P0 | Security | Tipe file spoof/ekstensi salah. | Ditolak. |
| TST-IMP-004 | P0 | Security | Formula CSV `=`, `+`, `-`, `@` pada export. | Dinetralkan sesuai policy. |
| TST-IMP-005 | P0 | API | File melebihi limit. | Ditolak tanpa parsing penuh. |
| TST-IMP-006 | P0 | Integration | Duplicate file/hash/key. | Tidak mem-posting ulang. |
| TST-IMP-007 | P0 | Integration | Key sama payload berbeda. | Conflict. |
| TST-IMP-008 | P0 | Integration | Organization/actor column dalam CSV. | Tidak dipercaya; context server menang. |
| TST-IMP-009 | P0 | Integration | Import order event. | Melewati canonical event processor. |
| TST-IMP-010 | P0 | Integration | Import receipt/outbound invalid. | Tidak menulis ledger langsung. |
| TST-IMP-011 | P1 | E2E | Dry-run summary. | Valid/invalid counts dan sample error jelas. |
| TST-IMP-012 | P1 | E2E | Admin memperbaiki file dan retry. | Job baru/versi linked; audit tersedia. |
| TST-IMP-013 | P0 | DB | Job posted tanpa domain results lengkap. | Reconciliation/notification failure. |
| TST-IMP-014 | P0 | Security | Upload object path lintas org. | RLS/server intent menolak. |
| TST-IMP-015 | P1 | Integration | Encoding/kolom tidak dikenal. | Validation error actionable. |
| TST-IMP-016 | P1 | Performance | File pada batas row size. | Selesai dalam target tanpa memory spike tidak terkendali. |

## Security dan RLS

| ID | Priority | Layer | Scenario | Expected |
|---|---|---|---|---|
| TST-SEC-001 | P0 | pgTAP | `anon` membaca tabel/view aplikasi. | Ditolak. |
| TST-SEC-002 | P0 | pgTAP | Admin membaca data org sendiri. | Diizinkan melalui allowlist. |
| TST-SEC-003 | P0 | pgTAP | Admin membaca data org lain. | Tidak ada row. |
| TST-SEC-004 | P0 | pgTAP | Direct insert ledger. | Ditolak. |
| TST-SEC-005 | P0 | pgTAP | Direct update/delete ledger. | Ditolak. |
| TST-SEC-006 | P0 | pgTAP | Direct delete audit. | Ditolak. |
| TST-SEC-007 | P0 | pgTAP | Function baru masih executable `PUBLIC`. | Test gagal. |
| TST-SEC-008 | P0 | Static/DB | `SECURITY DEFINER` tanpa fixed search path. | Lint/test gagal. |
| TST-SEC-009 | P0 | API | Mass assignment status/quantity/actor. | Field ditolak. |
| TST-SEC-010 | P0 | API | SQL-like search/filter payload. | Diperlakukan sebagai data; no injection. |
| TST-SEC-011 | P0 | E2E/API | IDOR pada return/stocktake/notification/file. | Ditolak tanpa leakage. |
| TST-SEC-012 | P0 | Storage | Evidence bucket public. | Security test/release gate gagal. |
| TST-SEC-013 | P0 | Storage | Signed URL dibuat tanpa entity authz. | Ditolak. |
| TST-SEC-014 | P0 | Storage | SVG/HTML/executable upload. | Ditolak. |
| TST-SEC-015 | P0 | Build | Secret scan repository/client bundle. | Tidak ada secret. |
| TST-SEC-016 | P0 | E2E | App di-embed iframe. | Diblokir CSP/frame policy. |
| TST-SEC-017 | P1 | E2E | CSP dan security headers. | Header baseline tersedia. |
| TST-SEC-018 | P0 | API | Rate limit pada endpoint mahal/sensitif. | Excess request ditolak aman. |
| TST-SEC-019 | P0 | API/DB | Replay sensitive command. | Idempoten. |
| TST-SEC-020 | P0 | DB | Worker function dieksekusi authenticated user. | Ditolak. |
| TST-SEC-021 | P0 | DB | RLS policy helper recursion. | Tidak terjadi; query sukses/deny deterministik. |
| TST-SEC-022 | P0 | E2E | Inactive Admin dengan tab lama mencoba posting. | Ditolak. |
| TST-SEC-023 | P0 | Environment | Preview memakai production secret/DB. | Pipeline guard gagal deployment. |
| TST-SEC-024 | P1 | Manual OWASP | Auth, session, authorization, input, business logic, client-side suite. | Tidak ada finding P0/P1 terbuka. |
| TST-SEC-025 | P0 | DB | Demo org mencoba mutation production org via service wrapper. | Ditolak. |

## UI, Mobile, dan Aksesibilitas

| ID | Priority | Layer | Scenario | Expected |
|---|---|---|---|---|
| TST-UX-001 | P1 | Component/E2E | Form validasi menampilkan error dekat field. | Pesan tekstual dan dapat dibaca assistive tech. |
| TST-UX-002 | P1 | E2E | Urutan fokus form. | Logis dan mempertahankan makna. |
| TST-UX-003 | P1 | E2E | Keyboard-only menyelesaikan flow utama. | Semua kontrol dapat dioperasikan. |
| TST-UX-004 | P1 | E2E | Focus indicator. | Terlihat dan tidak tertutup sticky UI. |
| TST-UX-005 | P1 | E2E | Loading, empty, success, error, duplicate. | Semua state memiliki teks jelas. |
| TST-UX-006 | P1 | E2E | Mobile viewport 360px. | Tidak ada horizontal scroll flow utama. |
| TST-UX-007 | P1 | E2E | Touch target untuk aksi utama. | Dapat digunakan tanpa salah tekan berulang. |
| TST-UX-008 | P1 | E2E | Destructive confirmation. | Menjelaskan dampak dan tidak default-confirm. |
| TST-UX-009 | P1 | E2E | Double-click tombol post. | UI disable + server idempotency. |
| TST-UX-010 | P1 | E2E | Refresh setelah mutation sukses. | State source tetap benar; no duplicate. |
| TST-UX-011 | P1 | E2E | Network timeout pada mutation. | Status tidak mengklaim gagal/sukses tanpa verifikasi. |
| TST-UX-012 | P1 | E2E | Tanggal/waktu. | Ditampilkan Asia/Jakarta konsisten. |
| TST-UX-013 | P2 | Component | Table besar. | Sorting/filtering/pagination benar. |
| TST-UX-014 | P1 | E2E | Drill-down ledger. | Breadcrumb/back navigation menjaga konteks. |
| TST-UX-015 | P1 | A11y | Status message non-modal. | `role=status`/polite semantics. |
| TST-UX-016 | P1 | A11y | Critical alert baru. | Diumumkan sekali tanpa fokus paksa. |
| TST-UX-017 | P1 | A11y | Severity tidak hanya warna. | Icon/text tersedia. |
| TST-UX-018 | P2 | Cross-browser | Chromium, Firefox, WebKit. | P0/P1 flows konsisten. |
| TST-UX-019 | P1 | E2E | Admin gudang menyelesaikan penerimaan/outbound/retur tanpa istilah teknis. | Usability task completion berhasil. |
| TST-UX-020 | P2 | E2E | Large text/zoom. | Konten tetap dapat digunakan. |

## Performa, Reliabilitas, dan Pemulihan

| ID | Priority | Layer | Scenario | Expected |
|---|---|---|---|---|
| TST-PERF-001 | P1 | k6 | Read dashboard/list stock pada beban baseline. | p95 memenuhi threshold; error rate rendah. |
| TST-PERF-002 | P0 | k6/DB | Concurrent marketplace outbound. | No negative/duplicate; latency dalam target. |
| TST-PERF-003 | P0 | Concurrency | 20 command pada produk yang sama. | Total sukses tidak melebihi stock eligible. |
| TST-PERF-004 | P1 | k6 | Mixed read/write workload ratusan paket/hari yang dipercepat. | Sistem stabil; threshold lulus. |
| TST-PERF-005 | P1 | DB | Full reconciliation golden dataset. | Selesai dalam target dan hasil deterministik. |
| TST-PERF-006 | P1 | DB | Expiry/notification sweep. | Tidak full scan tak terkendali; no duplicate. |
| TST-PERF-007 | P1 | Integration | Outbox backlog/retry. | Recovery tanpa duplicate. |
| TST-PERF-008 | P0 | Recovery | Restart setelah timeout command. | Idempotency menemukan hasil existing. |
| TST-PERF-009 | P1 | Migration | Migration + seed + test pada database kosong. | Reproducible. |
| TST-PERF-010 | P1 | Restore | Restore backup ke lingkungan terisolasi. | Ledger/projection/RLS verification lulus. |


# PART B — IMPLEMENTASI TEST

## 49. Unit Test Design

Unit test cocok untuk:

- quantity formula;
- state transition pure function;
- mapper status source ke canonical event;
- bundle expansion;
- FEFO sort key;
- threshold calculation;
- issue fingerprint;
- validation schema;
- error mapping;
- DTO minimization.

Unit test tidak dipakai sebagai satu-satunya bukti:

- transaction;
- RLS;
- lock;
- constraint;
- ledger write;
- Server Component async;
- end-to-end authorization.

---

## 50. Component Test Design

Component test memeriksa:

- label dan accessible name;
- field validation;
- disabled/loading state;
- preview rendering;
- error rendering;
- confirmation dialog;
- empty/list state;
- no accidental stock mutation.

Network/domain side effect dimock hanya pada component boundary.

---

## 51. Database Test Design

Setiap domain database suite mencakup:

```text
structure
positive command
negative validation
idempotency
payload conflict
organization isolation
direct write denial
reconciliation invariant
```

### 51.1 Plan Count

pgTAP file memakai plan yang eksplisit atau `no_plan()` sesuai standar tim.

### 51.2 Actor Context

Test mengatur JWT/session claims atau helper test yang mensimulasikan:

```text
active Admin org A
inactive Admin
active Admin org B
anon
```

### 51.3 Rollback

Test database berjalan dalam transaction test harness dan tidak meninggalkan data.

---

## 52. Contoh pgTAP Structure Test

```sql
begin;

select plan(4);

select has_table('inventory', 'stock_ledger_entries');
select has_column('inventory', 'stock_ledger_entries', 'quantity_delta');
select col_not_null('inventory', 'stock_ledger_entries', 'transaction_id');
select has_index(
  'inventory',
  'stock_ledger_entries',
  'idx_stock_ledger_entries_org_seq'
);

select * from finish();
rollback;
```

Nama index disesuaikan migration final.

---

## 53. Contoh pgTAP RLS Test

```sql
begin;

select plan(2);

-- helper project-specific sets authenticated context for Admin A
select test_helpers.authenticate_as('ADMIN_A_ACTIVE');

select is(
  (
    select count(*)
    from api.product_stock_positions
  ),
  expected_count_for_org_a(),
  'Admin A sees own organization rows'
);

select test_helpers.authenticate_as('ADMIN_B_ACTIVE');

select is(
  (
    select count(*)
    from api.product_stock_positions
    where product_id = fixture_product_a_id()
  ),
  0::bigint,
  'Admin B cannot see organization A product'
);

select * from finish();
rollback;
```

---

## 54. Integration Test Design

Integration test menjalankan:

```text
server command
-> user-scoped Supabase client
-> database function
-> ledger/projection/audit
```

Tidak melalui browser, sehingga cepat tetapi tetap memakai real database.

Cocok untuk:

- Route Handler;
- Server Action service;
- event ingestion;
- import;
- simulator;
- notification outbox;
- job invocation.

---

## 55. Contract Test

Contract yang versioned:

```text
canonical marketplace event
canonical return event
CSV header/schema
API request/response
error code
notification DTO
audit payload
```

Rule:

- unknown critical field ditolak;
- backward-compatible optional field diuji;
- version unsupported ditolak;
- raw source payload tidak menjadi domain contract.

---

## 56. E2E Architecture

Playwright projects:

```text
setup
chromium-desktop
firefox-desktop
webkit-desktop
chromium-mobile
unauthenticated
inactive-admin
```

### 56.1 Authentication State

Setup project menghasilkan storage state per Admin fixture.

Security test tetap melakukan login/session edge case secara langsung.

### 56.2 Locator

Prioritas:

1. role;
2. label;
3. text stable;
4. `data-testid` bila semantic locator tidak cukup.

Dilarang mengandalkan generated CSS class.

### 56.3 Assertions

Gunakan web-first assertion:

```ts
await expect(page.getByRole('status')).toHaveText(/berhasil/i)
```

Jangan membaca DOM sekali lalu `sleep`.

---

## 57. Playwright Artifacts

Configuration baseline:

```text
screenshot = only-on-failure
video = retain-on-failure
trace = retain-on-failure / on-first-retry
reporter = html + junit + line
```

Artifact retention mengikuti kebijakan CI.

---

## 58. E2E Data Setup

Data dibuat melalui:

- test-only fixture endpoint yang server-protected;
- direct test DB fixture;
- domain command;
- seed.

Dilarang setup dengan mengklik seluruh UI untuk setiap test jika tidak sedang menguji setup flow.

UI test fokus pada behavior yang diuji.

---

## 59. Concurrency Test Harness

Concurrency test harus menggunakan:

- dua atau lebih database connection;
- atau dua request paralel;
- barrier agar operasi overlap;
- timeout;
- final invariant query.

Pseudo-code:

```ts
await Promise.allSettled([
  postShipment(orderA),
  postShipment(orderB),
])

expect(await getSellable(product)).toBeGreaterThanOrEqual(0)
expect(await getSuccessfulOutboundQty(product)).toBeLessThanOrEqual(initialQty)
```

`Promise.all` tanpa memastikan overlap database masih dapat lolos secara serial. Gunakan barrier/hook bila perlu.

---

## 60. Deadlock Test

Skenario:

```text
command 1 input order A,B
command 2 input order B,A
```

Implementation harus mengurutkan lock berdasarkan product ID.

Expected:

- no indefinite deadlock;
- satu/both success sesuai stock;
- retry idempoten bila deadlock terdeteksi.

---

## 61. Property-Based Test

Generate:

- inbound;
- reservation;
- cancellation;
- outbound;
- return;
- transfer;
- reversal;
- stocktake adjustment.

Properties:

```text
ledger = projection
no bucket negative
available = sellable - reserved
internal transfer net zero
allocation = outbound
reversal <= original
duplicate effect <= 1
return quantities balance
```

Saat property gagal:

- seed disimpan;
- minimal counterexample disimpan;
- regression test dibuat.

---

## 62. Model-Based State Test

Model sederhana:

```text
ORDER:
RECEIVED
RESERVED
READY
PHYSICALLY_OUT
CANCELLED_PRE
CANCELLED_POST
RETURN_EXPECTED
CLOSED
```

Generate event sequence.

Bandingkan:

- model expected transition;
- system result.

Illegal transition harus ditolak/diabaikan sesuai rule, bukan mengubah state sembarang.

---

## 63. Scheduler dan Time Test

Jalankan rule function dengan explicit evaluation time.

Uji boundary:

```text
one second before threshold
exact threshold
one second after threshold
timezone date rollover
DST not applicable to Asia/Jakarta but timestamp conversion remains explicit
```

Tidak menunggu cron nyata untuk assertion utama.

Cron smoke hanya membuktikan schedule dipasang dan job dapat berjalan.

---

## 64. Accessibility Test

Automated:

- semantic role;
- label;
- duplicate ID;
- form error association;
- color contrast tool bila tersedia;
- keyboard focus smoke.

Manual:

- keyboard-only;
- screen reader spot-check;
- focus order;
- focus not obscured;
- zoom;
- mobile;
- live region behavior;
- error identification.

Automated scanner tidak membuktikan seluruh WCAG.

---

## 65. Security Test Plan

Mengikuti kategori OWASP WSTG:

```text
configuration/deployment
identity
authentication
authorization
session management
input validation
error handling
business logic
client-side
```

Business logic security wajib mencakup:

- direct ledger mutation;
- batch override;
- negative quantity;
- duplicate replay;
- cross-org UUID;
- stale approval;
- return over-receipt;
- stocktake partial post;
- claim mutation of stock;
- simulator production bypass.

---

## 66. Performance Test Workload

Baseline workload untuk skala fase 1:

```text
70 products
hundreds of packages/day
bursty marketplace events
manual operations
scheduled reconciliation
notification sweeps
```

k6 scenarios:

```text
stock_read
order_ingestion
shipment_outbound
manual_outbound
return_receipt
notification_read
```

### 66.1 Initial Thresholds

Baseline proposal:

```text
http_req_failed < 1%
read endpoints p95 < 500 ms
normal write endpoints p95 < 1200 ms
FEFO outbound p95 < 1500 ms
```

Threshold final disesuaikan setelah baseline environment diukur.

Correctness gate remains more important than latency.

A fast negative stock is still negative stock, merely with admirable punctuality.

---

## 67. Performance Data Integrity

Setelah load test:

- run reconciliation;
- assert no negative;
- assert no duplicate effect;
- assert ledger/projection match;
- assert order/ledger relationship;
- assert notification/outbox consistency.

Performance test yang hanya mengukur HTTP 200 tanpa memeriksa data bukan pengujian sistem stok.

---

## 68. Soak Test

Optional release/nightly:

- 30–60 minutes;
- mixed workload;
- scheduled jobs;
- monitor connection, lock wait, memory, errors;
- reconciliation at end.

Target awal disesuaikan environment.

---

## 69. Migration Test

Untuk setiap migration:

1. reset database;
2. apply all migrations;
3. seed;
4. run pgTAP;
5. migrate from previous release snapshot;
6. verify data;
7. run reconstruction/reconciliation;
8. test rollback strategy as forward correction if destructive rollback unsafe.

No manual dashboard-only change.

---

## 70. Backup/Restore Test

Pada environment terisolasi:

1. backup;
2. restore;
3. verify row counts;
4. verify ledger hash/count;
5. verify projection rebuild;
6. verify RLS/grants;
7. login test;
8. E2E smoke.

---

## 71. UAT Preparation

UAT menggunakan:

- demo organization;
- synthetic products;
- scenario checklist;
- expected result;
- observer notes;
- no direct SQL correction during session.

Defect dicatat dengan:

```text
scenario ID
step
expected
actual
screenshot/trace
data reference
severity
```

---

## 72. UAT Tasks untuk Admin Gudang

| Task | Success Criteria |
|---|---|
| Menerima barang maklon | Dapat post dan melihat stock bertambah per batch. |
| Memproses pesanan simulator | Dapat membedakan reservation dan physical outbound. |
| Mencatat bonus | Alasan bonus terlihat dan dapat ditelusuri. |
| Memproses retur | Barang masuk quarantine lalu diputuskan kondisinya. |
| Menangani klaim | Deadline terlihat tanpa mengubah stock. |
| Menjalankan stocktake | Count, variance, review, posting dapat dipahami. |
| Membuka issue rekonsiliasi | Dapat melihat sumber movement pembentuk mismatch. |
| Membaca notifikasi expiry | Dapat membuka batch yang tepat. |
| Menelusuri ledger | Dapat menjawab mengapa saldo berubah. |

---

## 73. Demo Acceptance Script

### 73.1 Persiapan

- reset demo organization;
- seed fixture;
- verify no open accidental critical issue;
- run P0 smoke;
- record commit SHA.

### 73.2 Live Sequence

1. dashboard stock awal;
2. maklon receipt;
3. order Shopee baru: reservation;
4. Shopee shipped: FEFO split;
5. order TikTok baru dan in-transit;
6. cancel before shipment;
7. cancel after shipment;
8. manual bonus;
9. bundle order;
10. return receipt quarantine;
11. inspection mixed;
12. lost return + claim;
13. duplicate event;
14. stocktake variance;
15. reconciliation drill-down;
16. expiry/claim notification;
17. security cross-org test tidak dipamerkan dengan data sensitif tetapi evidence test tersedia.

### 73.3 Larangan Demo

- mengedit database manual untuk “memperbaiki” angka;
- melewati failed state;
- menyembunyikan open issue;
- memakai production data;
- memakai akun bersama.

---

## 74. Defect Severity

| Severity | Definisi | Contoh |
|---|---|---|
| Blocker | Data corruption/security/release tidak dapat lanjut | ledger ganda, cross-org leak |
| Critical | Flow P0 salah | auto-restock post-shipment |
| High | Flow utama gagal/risiko besar | return inspection tidak dapat post |
| Medium | Workaround tersedia | filter salah |
| Low | Cosmetic | spacing |

P0 test failure minimal `Critical`, sering `Blocker`.

---

## 75. Bug Regression

Setiap bug yang diperbaiki:

1. test reproduksi dibuat;
2. test gagal sebelum fix;
3. fix diterapkan;
4. test lulus;
5. regression masuk suite permanen.

Exception hanya untuk bug visual sangat kecil dengan alasan terdokumentasi.

---

## 76. Test Ownership

| Area | Owner Primer |
|---|---|
| Domain/unit | Developer feature |
| Database/pgTAP | Developer + database reviewer |
| E2E | Developer + QA/reviewer |
| Security | Security reviewer/tech lead |
| UAT | Product/Admin representative |
| Performance | Backend/infra owner |
| Accessibility | Frontend + reviewer |

Tidak ada folder test “milik QA” yang boleh diabaikan developer.

---

## 77. Test Review Checklist

- requirement reference ada;
- priority benar;
- negative case ada;
- test data deterministik;
- assertion database cukup;
- no arbitrary sleep;
- no production data;
- no direct table bypass untuk setup yang menutupi bug;
- error case memeriksa no side effect;
- cleanup/isolation aman;
- test name menjelaskan behavior;
- failure output actionable.

---

## 78. Exit Criteria Phase 1

Fase 1 siap dirilis bila:

1. seluruh P0 lulus;
2. seluruh P1 utama lulus atau waiver non-stock terdokumentasi;
3. tidak ada Blocker/Critical terbuka;
4. pgTAP lulus;
5. RLS negatif lulus;
6. E2E smoke lulus pada production build;
7. full E2E P0/P1 lulus;
8. concurrency lulus;
9. performance threshold lulus;
10. accessibility critical issue tidak ada;
11. migration/seed reproducible;
12. backup/restore smoke lulus;
13. UAT ditandatangani;
14. live demo script lulus;
15. reconciliation akhir tidak memiliki unexpected critical issue.

---

## 79. Release Blockers Absolut

```text
negative stock
duplicate ledger effect
ledger/projection mismatch unexplained
cross-organization access
direct ledger mutation
FEFO selects ineligible batch
cancel post-shipment auto-restocks
return bypasses quarantine
claim changes stock
stocktake partial posting
service-role in client
production simulator uncontrolled
```

Tidak ada “nanti diperbaiki” untuk daftar ini. Gudang tidak menerima argumen bahwa data korup masih MVP.

---

## 80. Traceability ke Dokumen

| Dokumen | Area Test |
|---|---|
| `01-project-brief.md` | Outcome, risk, scoring, scope |
| `02-product-requirements.md` | Acceptance dan NFR |
| `03-business-rules.md` | Decision table dan invariant |
| `04-stock-ledger-design.md` | Ledger, idempotency, reversal |
| `05-database-schema.md` | Schema, constraints, indexes |
| `06-user-roles-and-flows.md` | Admin flow dan E2E |
| `07-marketplace-simulator.md` | Scenario adapter |
| `08-reconciliation-logic.md` | Checks, issue, projection rebuild |
| `09-return-and-claim-flow.md` | Return quantity dan claim |
| `10-fefo-batch-allocation.md` | Eligibility, locking, split |
| `11-stock-opname-flow.md` | Snapshot, count, adjustment |
| `12-notification-rules.md` | Episode, read state, outbox |
| `13-security-and-rls.md` | Auth, RLS, storage, security |
| `14-testing-scenarios.md` | Orkestrasi seluruh test |

---

## 81. Amendment terhadap Dokumen Sebelumnya

### `02-product-requirements.md`

Acceptance scenarios dirujuk ke ID test pada dokumen ini.

### `05-database-schema.md`

Testing section harus memakai:

- pgTAP;
- RLS positive/negative;
- migration reset;
- deterministic seed.

### `07-marketplace-simulator.md`

Preset scenario digunakan sebagai fixture E2E dan integration, bukan sebagai pengganti assertion database.

### `13-security-and-rls.md`

Security acceptance criteria dipetakan ke `TST-SEC-*` dan `TST-AUTH-*`.

---

## 82. Keputusan Terbuka

1. Package property-based test final.
2. Nilai coverage final setelah struktur repo nyata.
3. Browser matrix release minimum.
4. Performance threshold final setelah baseline.
5. Durasi soak test.
6. Apakah second-Admin UAT wajib.
7. File scanning provider.
8. Test runner untuk API integration.
9. Apakah preview deployment memakai Supabase project terpisah.
10. Retention test artifacts.
11. Maximum concurrency test pada CI.
12. Apakah visual regression dimasukkan.
13. Apakah axe otomatis dipakai.
14. Apakah backup/restore dijalankan setiap release atau periodik.
15. Siapa penandatangan UAT final.

Sebelum diputuskan, default aman dokumen ini berlaku.

---

## 83. Referensi Teknis Resmi

### Next.js

1. Testing guides  
   `https://nextjs.org/docs/app/guides/testing`

2. Vitest testing guide  
   `https://nextjs.org/docs/app/guides/testing/vitest`

3. Playwright testing guide  
   `https://nextjs.org/docs/app/guides/testing/playwright`

Next.js mendokumentasikan Vitest untuk unit testing dan Playwright untuk E2E. Async Server Components lebih tepat dibuktikan melalui E2E/integration.

### Supabase

1. Testing overview  
   `https://supabase.com/docs/guides/local-development/testing/overview`

2. Testing and linting with CLI  
   `https://supabase.com/docs/guides/local-development/cli/testing-and-linting`

3. Database testing  
   `https://supabase.com/docs/guides/database/testing`

4. Seeding database  
   `https://supabase.com/docs/guides/local-development/seeding-your-database`

pgTAP digunakan untuk struktur, RLS, function/procedure, dan data integrity. Seed digunakan untuk environment yang dapat direproduksi.

### Playwright

1. Writing tests  
   `https://playwright.dev/docs/writing-tests`

2. Best practices  
   `https://playwright.dev/docs/best-practices`

3. Fixtures  
   `https://playwright.dev/docs/test-fixtures`

4. Authentication  
   `https://playwright.dev/docs/auth`

5. Projects  
   `https://playwright.dev/docs/test-projects`

6. Assertions  
   `https://playwright.dev/docs/test-assertions`

7. Trace viewer  
   `https://playwright.dev/docs/trace-viewer`

8. Retries  
   `https://playwright.dev/docs/test-retries`

9. Reporters  
   `https://playwright.dev/docs/test-reporters`

Playwright menyediakan isolated browser context, project lintas browser/device, auto-waiting/web-first assertions, trace, retry, dan report.

### Vitest

1. Guide  
   `https://vitest.dev/guide/`

2. Mocking  
   `https://vitest.dev/guide/mocking`

3. Mocking requests  
   `https://vitest.dev/guide/mocking/requests`

Mocking dipakai secara selektif pada boundary, bukan untuk menggantikan test PostgreSQL domain.

### PostgreSQL

1. Transaction isolation  
   `https://www.postgresql.org/docs/current/transaction-iso.html`

2. Explicit locking  
   `https://www.postgresql.org/docs/current/explicit-locking.html`

3. Concurrency control  
   `https://www.postgresql.org/docs/current/mvcc.html`

Concurrency test harus memeriksa perilaku nyata transaksi, lock, dan deadlock.

### Grafana k6

1. Thresholds  
   `https://grafana.com/docs/k6/latest/using-k6/thresholds/`

2. Scenarios  
   `https://grafana.com/docs/k6/latest/using-k6/scenarios/`

3. Performance testing tutorial  
   `https://grafana.com/docs/k6/latest/examples/get-started-with-k6/test-for-performance/`

Threshold memberi pass/fail criteria; scenarios memodelkan workload yang berbeda.

### OWASP

1. Web Security Testing Guide  
   `https://owasp.org/www-project-web-security-testing-guide/latest/`

2. Stable WSTG v4.2  
   `https://owasp.org/www-project-web-security-testing-guide/v42/`

### W3C WCAG 2.2

1. Status Messages  
   `https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html`

2. Error Identification  
   `https://www.w3.org/WAI/WCAG22/Understanding/error-identification.html`

3. Focus Order  
   `https://www.w3.org/WAI/WCAG22/Understanding/focus-order.html`

4. Focus Not Obscured  
   `https://www.w3.org/WAI/WCAG22/Understanding/focus-not-obscured-minimum.html`

---

## 84. Ringkasan Keputusan Final

Testing stack fase 1:

```text
TYPECHECK + LINT
VITEST
PGTAP + SUPABASE CLI
INTEGRATION AGAINST REAL LOCAL POSTGRES
PLAYWRIGHT
CONCURRENCY HARNESS
K6
OWASP WSTG
WCAG 2.2
```

Urutan kebenaran test:

```text
BUSINESS RULE
-> DATABASE INVARIANT
-> API/COMMAND EFFECT
-> UI FLOW
```

Test P0 wajib membuktikan database state. E2E membuktikan user flow, bukan menggantikan pgTAP. Mock dipakai pada external boundary, bukan untuk berpura-pura bahwa transaksi dan RLS sudah benar. Retry tidak menyembuhkan flaky test. Coverage tidak menyelamatkan invariant yang tidak diuji.

Release berhenti bila terdapat:

```text
negative stock
duplicate movement
cross-org access
FEFO salah
return bypass quarantine
stocktake partial post
ledger mutable
```

Sistem stok yang diuji hanya lewat happy path adalah spreadsheet dengan kostum lebih mahal. Dokumen ini memastikan aplikasi diuji pada tempat manusia dan transaksi biasanya berkhianat: retry, pembatalan, retur, waktu, hak akses, dan dua request yang datang bersamaan.
