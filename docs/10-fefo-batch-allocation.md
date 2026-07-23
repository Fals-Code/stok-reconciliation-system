<!--
File: 10-fefo-batch-allocation.md
Project: Sistem Rekonsiliasi Stok
Status: Phase 2 synced FEFO contract
Version: 1.1.0
Last updated: 2026-07-23
Language: id-ID
Timezone: Asia/Jakarta
Role model: ADMIN only
Primary source: VibeDev Phase 2 Sync Update v2, 13 Juni 2026
Baseline source: stok-management-system.pdf
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
-->

# FEFO Batch Allocation: Sistem Rekonsiliasi Stok

## 1. Tujuan Dokumen

Dokumen ini mendefinisikan desain **First-Expiry-First-Out (FEFO)** dan alokasi batch untuk seluruh outbound produk pada Sistem Rekonsiliasi Stok fase 1.

FEFO digunakan agar produk dengan tanggal kedaluwarsa paling dekat yang masih layak dialokasikan terlebih dahulu. Dalam sistem ini, FEFO bukan sekadar urutan tampilan batch. FEFO adalah aturan domain yang menentukan batch nyata yang dikonsumsi ketika barang benar-benar keluar dari gudang.

Dokumen ini mengatur:

- kapan FEFO dijalankan;
- kapan FEFO tidak dijalankan;
- sumber kebutuhan quantity;
- eligibility batch;
- aturan tanggal kedaluwarsa;
- tie-breaker deterministik;
- split quantity ke beberapa batch;
- interaksi dengan reservasi;
- interaksi dengan bundle;
- interaksi dengan retur;
- interaksi dengan stocktake dan integrity hold;
- concurrency;
- locking;
- idempotensi;
- atomicity;
- ledger posting;
- allocation traceability;
- preview;
- error handling;
- database amendment;
- API dan function boundary;
- rekonsiliasi;
- observability;
- testing.

> **Prinsip utama:** Admin menentukan produk dan quantity yang keluar; sistem menentukan batch dengan FEFO.

Tidak ada pemilihan batch manual untuk outbound penjualan normal.

---

## 2. Kedudukan Dokumen

Dokumen ini menjadi sumber kebenaran utama untuk:

- eligibility batch FEFO;
- urutan FEFO;
- algoritma allocation;
- locking allocation;
- split batch;
- snapshot keputusan allocation;
- integrasi allocation dengan ledger;
- preview dan commit;
- correction dan reversal allocation;
- test allocation.

Urutan sumber kebenaran:

| Topik | Dokumen |
|---|---|
| Masalah dan keputusan klien | `stok-management-system.pdf` |
| Requirement | `02-product-requirements.md` |
| Business rules | `03-business-rules.md` |
| Ledger | `04-stock-ledger-design.md` |
| Database | `05-database-schema.md` |
| User role | `06-user-roles-and-flows.md` |
| Simulator | `07-marketplace-simulator.md` |
| Rekonsiliasi | `08-reconciliation-logic.md` |
| Retur dan klaim | `09-return-and-claim-flow.md` |
| FEFO dan alokasi batch | Dokumen ini |

Keputusan role terbaru:

```text
Hanya ada satu user role aplikasi: ADMIN.
```

`SYSTEM_PROCESS` boleh menjadi actor type untuk proses otomatis, tetapi bukan user role.

---

## 3. Latar Belakang

Source proyek menetapkan:

- sekitar 70 produk skincare;
- setiap batch memiliki tanggal kedaluwarsa;
- operator tidak memilih batch;
- sistem mengalokasikan batch otomatis dengan FEFO;
- bundle tidak memiliki stok tersendiri;
- listing bundle dipecah menjadi produk satuan;
- barang baru dihitung keluar ketika fisik meninggalkan gudang;
- semua movement harus dapat ditelusuri.

Pada Shopee:

```text
physical outbound trigger = SHIPPED
```

Pada TikTok Shop:

```text
physical outbound trigger = IN_TRANSIT
```

Sebelum trigger tersebut:

- pesanan hanya reservasi;
- batch belum dipilih final;
- stok fisik belum berkurang.

Saat trigger tercapai:

- sistem menentukan batch;
- quantity dapat dibagi ke beberapa batch;
- allocation disimpan;
- ledger outbound diposting per batch;
- reservasi dikonsumsi;
- order berubah menjadi physically out;
- seluruh proses berlangsung atomik.

---

## 4. Dasar Operasional FEFO

Organisasi kesehatan dan rantai pasok resmi menggunakan FEFO untuk item bertanggal kedaluwarsa: barang yang paling dahulu kedaluwarsa diprioritaskan keluar, sedangkan FIFO lebih sesuai untuk barang tanpa tanggal kedaluwarsa.

Dalam desain ini:

```text
FEFO priority = earliest eligible expiry date first
```

Bukan:

```text
oldest receipt first
```

Tanggal penerimaan hanya menjadi tie-breaker setelah expiry sama.

Traceability batch memerlukan setidaknya:

- product identity;
- batch/lot number;
- expiry date.

Jika barcode GS1 digunakan kelak, informasi batch/lot dan expiry dapat dibaca dari data carrier yang sesuai. Namun fase 1 tidak mewajibkan hardware scanner atau implementasi penuh GS1.

---

## 5. Sasaran

| ID | Sasaran |
|---|---|
| `FEFO-GOAL-001` | Batch eligible dengan expiry paling dekat dipakai lebih dahulu. |
| `FEFO-GOAL-002` | Batch expired, blocked, archived, quarantine, dan damaged tidak dialokasikan untuk penjualan. |
| `FEFO-GOAL-003` | Satu kebutuhan dapat dibagi ke beberapa batch secara deterministik. |
| `FEFO-GOAL-004` | Total allocation selalu sama dengan quantity outbound. |
| `FEFO-GOAL-005` | Stok tidak cukup menghasilkan kegagalan atomik tanpa movement parsial. |
| `FEFO-GOAL-006` | Dua transaksi konkuren tidak dapat mengalokasikan unit yang sama. |
| `FEFO-GOAL-007` | Preview tidak dianggap sebagai allocation final. |
| `FEFO-GOAL-008` | Allocation final dapat ditelusuri ke order/manual source, transaction, ledger, product, dan batch. |
| `FEFO-GOAL-009` | Bundle dipecah sebelum allocation. |
| `FEFO-GOAL-010` | Reservasi product-level dikonsumsi saat allocation final. |
| `FEFO-GOAL-011` | Alokasi dapat direkonsiliasi dan diuji ulang. |
| `FEFO-GOAL-012` | Koreksi allocation tidak mengedit histori. |
| `FEFO-GOAL-013` | Semua jalur outbound menggunakan allocator domain yang sama. |
| `FEFO-GOAL-014` | Perubahan algorithm version tidak mengubah allocation historis. |
| `FEFO-GOAL-015` | Hasil allocation deterministik untuk snapshot data yang sama. |

---

## 6. Bukan Tujuan

Fase 1 tidak:

- melakukan optimasi lokasi rak;
- menentukan rute picking gudang;
- membuat wave picking;
- membuat cartonization;
- menghitung ongkir;
- menghitung harga;
- menghitung biaya kedaluwarsa;
- mengalokasikan serial number individual;
- memberi Admin kebebasan memilih batch penjualan;
- melakukan soft allocation ke batch sejak order baru masuk;
- mengunci batch selama pesanan masih reservasi;
- menerapkan `SKIP LOCKED` agar transaksi terlihat cepat tetapi diam-diam melanggar FEFO;
- mengalokasikan stok bundle;
- memposting hasil retur SELLABLE ketika provenance belum terverifikasi;
- mengedit allocation historis;
- menghapus ledger karena batch salah;
- memproses negative stock;
- menganggap batch status `ACTIVE` cukup tanpa mengecek expiry secara dinamis.

---

## 7. Terminologi

| Istilah | Definisi |
|---|---|
| FEFO | First-Expiry-First-Out. |
| Allocation request | Permintaan quantity produk yang harus keluar. |
| Candidate batch | Batch yang diperiksa allocator. |
| Eligible batch | Candidate yang memenuhi seluruh aturan. |
| Allocation | Keputusan final quantity per batch. |
| Split allocation | Satu kebutuhan dipenuhi oleh lebih dari satu batch. |
| FEFO rank | Urutan batch dalam keputusan final. |
| Operational date | Tanggal lokal yang dipakai untuk eligibility expiry. |
| Safety buffer | Jumlah hari sebelum expiry ketika batch tidak lagi boleh dijual. |
| Effective last sellable date | Tanggal terakhir batch boleh dialokasikan menurut buffer. |
| Preview | Simulasi read-only allocation. |
| Commit | Allocation final di dalam transaksi. |
| Product lock | Lock pada posisi produk untuk serialisasi singkat. |
| Batch balance lock | Row lock pada balance kandidat. |
| Allocation snapshot | Bukti kondisi yang dipakai saat keputusan final. |
| Allocation group | Semua allocation line dalam satu source command. |
| Hard hold | Pemblokiran mutation karena stocktake atau integrity issue. |
| Source line | Order item atau line outbound manual. |
| All-or-nothing | Tidak ada movement parsial jika seluruh kebutuhan command tidak terpenuhi. |

---

## 8. Scope Jalur FEFO

FEFO wajib digunakan untuk outbound dari bucket `SELLABLE` berikut:

```text
MARKETPLACE_SALE
OFFLINE_SALE
BONUS
PROMO
SAMPLE
```

FEFO dapat digunakan untuk reason sellable lain yang ditambahkan kemudian jika:

```text
movement_reason.requires_fefo = true
```

FEFO penjualan tidak digunakan untuk:

```text
DISPOSAL_EXPIRED
DISPOSAL_DAMAGED
RETURN_RECEIPT
RETURN_SELLABLE_INBOUND
STOCKTAKE_ADJUSTMENT
REVERSAL
INTERNAL_BUCKET_TRANSFER
```

Alasan:

- disposal expired menargetkan batch tertentu yang memang expired;
- damaged disposal memakai bucket damaged;
- receipt dan inspection bukan outbound penjualan;
- reversal mengikuti entry original;
- adjustment mengikuti variance/batch hasil opname.

---

## 9. Trigger Allocation

### 9.1 Marketplace

| Channel | Trigger | Sebelum Trigger | Saat Trigger |
|---|---|---|---|
| Shopee | `SHIPPED` | Product reservation | FEFO allocation + ledger outbound |
| TikTok Shop | `IN_TRANSIT` | Product reservation | FEFO allocation + ledger outbound |

### 9.2 Manual Outbound

Untuk:

- offline sale;
- bonus;
- promo;
- sample;

allocation dijalankan saat Admin menekan `Post/Konfirmasi Pengeluaran`.

Draft:

- tidak mengubah stock;
- tidak mengalokasikan batch final;
- boleh menampilkan preview.

### 9.3 Import

Import hanya membentuk command/event.

FEFO final tetap dijalankan pada domain function ketika event mencapai trigger fisik.

### 9.4 Simulator

Simulator menghasilkan event.

Simulator tidak memilih batch dan tidak menulis allocation.

---

## 10. Allocation Request Model

```ts
type AllocationRequest = {
  organizationId: string
  sourceType:
    | 'MARKETPLACE_ORDER'
    | 'MANUAL_OUTBOUND'
    | 'IMPORT'
    | 'SIMULATOR'
  sourceId: string
  sourceLineId: string
  productId: string
  requestedQty: number
  bucketCode: 'SELLABLE'
  operationalAt: string
  channelCode?: 'SHOPEE' | 'TIKTOK_SHOP' | 'OFFLINE' | 'MANUAL'
  reasonCode:
    | 'MARKETPLACE_SALE'
    | 'OFFLINE_SALE'
    | 'BONUS'
    | 'PROMO'
    | 'SAMPLE'
  reservationId?: string
  idempotencyKey: string
  correlationId: string
}
```

Validation:

```text
requestedQty > 0
product active
source valid
organization valid
bucket = SELLABLE
reason requires FEFO
operationalAt valid
idempotency valid
```

---

## 11. Normalisasi Sebelum FEFO

Urutan wajib:

```text
Source data
-> validate source
-> resolve listing
-> expand bundle
-> normalize product lines
-> aggregate duplicate products where policy permits
-> validate reservation/source quantity
-> FEFO allocation
```

FEFO tidak menerima listing marketplace mentah.

FEFO menerima:

```text
internal product_id + requested_qty
```

---

## 12. Bundle

Contoh recipe snapshot:

```text
BUNDLE-GLOW:
2 x PRODUCT-A
1 x PRODUCT-B
```

Pesanan:

```text
3 x BUNDLE-GLOW
```

Normalized:

```text
PRODUCT-A = 6
PRODUCT-B = 3
```

Allocation dijalankan per internal product.

Tidak ada:

```text
batch untuk BUNDLE-GLOW
stock BUNDLE-GLOW
allocation BUNDLE-GLOW
```

Recipe yang dipakai adalah snapshot saat order diterima, bukan recipe aktif saat shipment.

---

## 13. Reservasi dan FEFO

### 13.1 Product-Level Reservation

Reservasi menyimpan:

```text
organization
order item
product
reserved quantity
consumed quantity
released quantity
```

Reservasi tidak menyimpan batch final.

Alasan:

- batch lebih dekat expiry dapat masuk setelah order dibuat;
- batch dapat diblokir sebelum shipment;
- retur sellable dapat menambah batch;
- batch dapat kedaluwarsa sebelum physical outbound;
- batch final harus mencerminkan kondisi saat barang keluar.

### 13.2 Saat Order Baru

```text
sellable physical = unchanged
reserved += qty
available -= qty
batch allocation = none
ledger = none
```

### 13.3 Saat Physical Outbound

```text
FEFO allocation created
sellable physical -= qty
reserved consumed += qty
reserved remaining -= qty
ledger outbound posted
```

### 13.4 Reservasi Tidak Cukup

Untuk marketplace normal:

```text
allocation requested qty
=
valid reservation remaining qty
```

Jika source shipment quantity melebihi reservation:

- reject;
- create exception;
- jangan diam-diam menggunakan unreserved stock.

Policy perluasan quantity harus melalui order correction sebelum shipment.

---

## 14. Operational Date

Tanggal FEFO dihitung dari:

```text
operational_at in Asia/Jakarta
```

```text
operational_date = local date(operational_at)
```

Database menyimpan timestamp UTC.

Function menerima timestamp dan menghitung tanggal lokal secara eksplisit.

Contoh SQL:

```sql
(p_operational_at at time zone 'Asia/Jakarta')::date
```

Jangan menggunakan timezone session yang tidak dikontrol.

---

## 15. Safety Buffer

### 15.1 Definisi

Safety buffer adalah jumlah hari sebelum expiry ketika batch tidak lagi eligible untuk penjualan.

```text
effective_last_sellable_date
=
expiry_date - safety_buffer_days
```

Eligibility:

```text
operational_date <= effective_last_sellable_date
```

### 15.2 Default Fase 1

```text
safety_buffer_days = 0
```

Dengan default ini:

```text
expiry_date >= operational_date
```

Batch dengan expiry pada tanggal yang sama masih eligible secara sistem sampai tanggal lokal tersebut berakhir.

### 15.3 Konfigurasi

Konfigurasi dapat berada pada:

```text
organization default
product override
channel override
```

Precedence:

```text
product-channel override
product override
channel override
organization default
system default
```

Fase 1 boleh hanya memakai organization default.

### 15.4 Snapshot

Allocation menyimpan:

```text
safety_buffer_days_snapshot
operational_date_snapshot
```

Perubahan konfigurasi kemudian tidak mengubah histori.

---

## 16. Batch Eligibility

Batch eligible bila seluruh kondisi berikut benar.

| ID | Kondisi |
|---|---|
| `FEFO-ELG-001` | `organization_id` sama. |
| `FEFO-ELG-002` | `product_id` sama. |
| `FEFO-ELG-003` | Produk aktif. |
| `FEFO-ELG-004` | Produk batch-tracked. |
| `FEFO-ELG-005` | Produk expiry-tracked. |
| `FEFO-ELG-006` | Batch code tersedia. |
| `FEFO-ELG-007` | Expiry date tersedia. |
| `FEFO-ELG-008` | Batch status `ACTIVE`. |
| `FEFO-ELG-009` | Batch tidak blocked. |
| `FEFO-ELG-010` | Batch tidak archived. |
| `FEFO-ELG-011` | Batch RETURN hanya ada setelah provenance dan inspeksi SELLABLE tervalidasi. |
| `FEFO-ELG-012` | Sellable balance lebih dari nol. |
| `FEFO-ELG-013` | Quarantine tidak dianggap sellable. |
| `FEFO-ELG-014` | Damaged tidak dianggap sellable. |
| `FEFO-ELG-015` | Batch belum melewati effective last sellable date. |
| `FEFO-ELG-016` | Tidak ada active integrity/stocktake hold yang memblokir. |
| `FEFO-ELG-017` | Projection telah lolos integrity prerequisite. |
| `FEFO-ELG-018` | Batch bukan target correction yang belum selesai. |

Semua kondisi diperiksa kembali saat commit.

---

## 17. Status Batch dan Expiry Dinamis

`status_code = ACTIVE` tidak cukup.

Query tetap harus mengecek:

```text
expiry_date
```

karena:

- scheduler expired mungkin belum berjalan;
- transaksi melintasi tengah malam;
- data status dapat terlambat;
- batch dapat aktif tetapi tanggalnya sudah lewat.

Sebaliknya, batch `EXPIRED` tidak eligible walaupun expiry date tampak belum lewat. Ini menjadi exception master data dan harus direkonsiliasi.

---

## 18. Batch Tidak Eligible

Reason codes:

```text
WRONG_ORGANIZATION
WRONG_PRODUCT
PRODUCT_INACTIVE
BATCH_TRACKING_DISABLED
EXPIRY_TRACKING_DISABLED
MISSING_BATCH_CODE
MISSING_EXPIRY_DATE
BATCH_BLOCKED
BATCH_EXPIRED_STATUS
BATCH_ARCHIVED
NO_SELLABLE_BALANCE
EXPIRY_DATE_PASSED
SAFETY_BUFFER_REACHED
INTEGRITY_HOLD_ACTIVE
STOCKTAKE_HOLD_ACTIVE
PROJECTION_UNTRUSTED
```

Preview dapat menampilkan alasan exclusion.

Commit error tidak perlu mengembalikan semua batch sensitif ke client. Gunakan DTO aman.

---

## 19. Urutan FEFO Resmi

Urutan:

```sql
order by
  expiry_date asc,
  coalesce(received_first_at, created_at) asc,
  batch_code asc,
  id asc
```

### 19.1 Primary Sort

```text
expiry_date ASC
```

### 19.2 Secondary Sort

```text
received_first_at ASC
```

Digunakan bila expiry sama.

### 19.3 Tertiary Sort

```text
batch_code ASC
```

Memberi urutan stabil yang dapat dibaca manusia.

### 19.4 Final Tie-Breaker

```text
batch_id ASC
```

Menjamin determinisme.

### 19.5 Collation

`batch_code` ordering harus memakai collation yang stabil.

Rekomendasi:

- jangan menjadikan batch code sebagai tie-breaker utama;
- UUID tetap menjadi final tie-breaker;
- test harus berjalan konsisten pada environment.

---

## 20. FEFO Rank

`fefo_rank` adalah urutan batch yang benar-benar dialokasikan dalam source line.

Contoh:

```text
rank 1 -> Batch A, qty 5
rank 2 -> Batch B, qty 7
```

`fefo_rank` bukan rank seluruh kandidat yang excluded.

Untuk forensic audit yang lebih lengkap, candidate snapshot dapat menyimpan urutan seluruh kandidat eligible.

---

## 21. Algoritma Dasar

Input:

```text
requested_qty = Q
```

Candidate:

```text
C1...Cn sorted by FEFO
```

Pseudo-code:

```text
remaining = Q
rank = 1

for candidate in candidates:
  take = min(candidate.sellable_qty, remaining)

  if take > 0:
    append allocation(candidate.batch_id, take, rank)
    remaining -= take
    rank += 1

  if remaining = 0:
    break

if remaining > 0:
  fail INSUFFICIENT_ELIGIBLE_STOCK

persist allocations
post ledger
update projections
```

---

## 22. Split Allocation

Contoh:

```text
Requested = 12

Batch A
expiry = 2026-08-01
sellable = 5

Batch B
expiry = 2026-09-01
sellable = 20
```

Result:

```text
Batch A -> 5
Batch B -> 7
```

Ledger:

```text
Batch A / SELLABLE -5
Batch B / SELLABLE -7
```

Total:

```text
5 + 7 = 12
```

---

## 23. Multi-Line Outbound

Contoh order:

```text
PRODUCT-A = 12
PRODUCT-B = 3
PRODUCT-C = 1
```

Default atomicity:

```text
all source lines succeed
or
entire outbound command fails
```

Jika PRODUCT-C tidak cukup:

- tidak ada allocation A;
- tidak ada allocation B;
- tidak ada allocation C;
- tidak ada ledger;
- reservasi tidak dikonsumsi;
- order tidak berubah physical out.

Ini menghindari paket yang secara database “setengah sudah pergi”.

---

## 24. Aggregasi Duplicate Product Lines

Jika satu order menghasilkan product yang sama dari beberapa listing/bundle:

Pilihan default:

- allocation tetap dicatat per source line untuk traceability;
- lock/availability check dapat menggunakan total per product;
- allocation result dibagi kembali secara deterministik ke source line.

Urutan source line:

```text
source_line_sequence ASC
source_line_id ASC
```

Tujuan:

- total product dicek sekali;
- allocation tetap dapat ditelusuri;
- duplicate components tidak over-allocate.

---

## 25. Preview Allocation

### 25.1 Tujuan

Preview membantu Admin melihat:

- batch yang kemungkinan dipakai;
- expiry;
- quantity split;
- excluded candidates;
- shortage;
- safety buffer;
- expected ledger effect.

### 25.2 Preview Tidak Final

Preview:

- tidak mengunci row jangka panjang;
- tidak membuat allocation;
- tidak membuat ledger;
- tidak mengubah projection;
- tidak mengonsumsi reservation;
- dapat menjadi stale.

UI wajib menampilkan:

```text
Alokasi final dihitung ulang saat diposting.
```

### 25.3 Preview Token

Optional:

```text
preview_id
preview_hash
expires_at
```

Commit tidak mempercayai batch list dari client.

Commit hanya menerima:

```text
source command + confirmation token
```

Server menghitung ulang.

---

## 26. Commit Allocation

Commit wajib:

1. memvalidasi idempotency;
2. lock source;
3. lock product positions;
4. validasi reservation/source quantity;
5. menentukan operational date;
6. memuat config buffer;
7. memilih kandidat;
8. lock candidate balances;
9. mengecek ulang eligibility;
10. menghitung split;
11. memvalidasi total;
12. membuat stock transaction;
13. membuat allocation rows;
14. membuat ledger entries;
15. update batch projection;
16. update product projection;
17. consume reservation;
18. update source status;
19. append audit/status history;
20. commit.

Semua di satu database transaction.

---

## 27. Transaction Isolation

Baseline fase 1:

```text
READ COMMITTED
+
explicit row locks
+
deterministic lock order
+
idempotent retry
```

Alasan:

- skala sekitar 70 produk;
- ratusan paket per hari;
- product-level serialization masih wajar;
- desain mudah dibuktikan;
- PostgreSQL `SELECT ... FOR UPDATE` menunggu row writer/locker lain dan kemudian mengembalikan versi row terbaru yang memenuhi kondisi.

Jika kemudian menggunakan `SERIALIZABLE`:

- tangani serialization failure;
- retry dengan idempotency key sama;
- uji throughput.

---

## 28. Lock Order

Urutan wajib:

1. idempotency command;
2. source order/manual document;
3. reservation rows;
4. product positions, urut `product_id`;
5. batch balance candidates, urut:
   - `product_id`;
   - `expiry_date`;
   - `received_first_at`;
   - `batch_code`;
   - `batch_id`;
6. stock transaction;
7. ledger/projection updates;
8. source status history.

Semua function outbound memakai urutan sama.

---

## 29. Product-Level Lock

Lock:

```sql
select *
from inventory.stock_product_positions
where organization_id = p_organization_id
  and product_id = any(p_product_ids)
order by product_id
for update;
```

Setelah lock:

- recheck sellable;
- recheck reserved;
- recheck available;
- recheck integrity hold.

Product lock mencegah:

- dua reservation/outbound membaca availability yang sama;
- stocktake dan outbound menulis entity sama;
- adjustment dan outbound mengonsumsi stock sama;
- dua outbound mengambil unit terakhir bersamaan.

---

## 30. Candidate Lock Query

Query konseptual:

```sql
select
  b.id as batch_id,
  b.product_id,
  b.batch_code,
  b.expiry_date,
  b.received_first_at,
  bb.sellable_qty,
  bb.version
from catalog.product_batches b
join inventory.stock_batch_balances bb
  on bb.organization_id = b.organization_id
 and bb.product_id = b.product_id
 and bb.batch_id = b.id
where b.organization_id = p_organization_id
  and b.product_id = p_product_id
  and b.status_code = 'ACTIVE'
  and b.expiry_date is not null
  and b.expiry_date - p_safety_buffer_days >= p_operational_date
  and bb.sellable_qty > 0
  and not exists (
    select 1
    from reconciliation.entity_holds h
    where h.organization_id = b.organization_id
      and h.entity_type_code = 'BATCH'
      and h.entity_id = b.id
      and h.status_code = 'ACTIVE'
  )
order by
  b.expiry_date,
  coalesce(b.received_first_at, b.created_at),
  b.batch_code,
  b.id
for update of bb;
```

Setelah rows locked:

- re-evaluate conditions;
- do not trust pre-lock preview;
- calculate split.

---

## 31. Mengapa Tidak `SKIP LOCKED`

`SKIP LOCKED` dapat melewati batch expiry paling dekat yang sedang dikunci transaksi lain.

Contoh:

```text
Batch A expiry 1 Aug, locked
Batch B expiry 1 Sep, free
```

Dengan `SKIP LOCKED`, transaksi kedua dapat mengambil Batch B walaupun Batch A seharusnya lebih dahulu.

Itu:

- mempercepat response;
- tetapi melanggar FEFO;
- mengurangi determinisme;
- menyulitkan rekonsiliasi.

Default:

```text
do not use SKIP LOCKED for normal FEFO allocation
```

Lebih baik:

- tunggu dalam lock timeout wajar;
- retry command;
- tampilkan konflik operasional bila timeout.

`SKIP LOCKED` dapat dipertimbangkan untuk job queue, bukan untuk keputusan FEFO normal.

---

## 32. Lock Timeout

Set lokal dalam transaction:

```sql
set local lock_timeout = '3s';
set local statement_timeout = '15s';
```

Nilai final dikonfigurasi setelah load test.

Jika timeout:

```text
ALLOCATION_LOCK_TIMEOUT
```

Retry:

- maksimum terbatas;
- jitter;
- idempotency key sama;
- jangan regenerate external effect.

---

## 33. Insufficient Stock

Jika:

```text
sum(eligible locked sellable) < requested_qty
```

Hasil:

```text
INSUFFICIENT_ELIGIBLE_STOCK
```

Response dapat menyertakan:

```text
requested_qty
eligible_qty
shortage_qty
```

Tidak ada:

- allocation row;
- ledger;
- projection mutation;
- reservation consumption;
- physical status update.

Transaction rollback.

---

## 34. Physical Sellable vs Available

Untuk order marketplace dengan valid reservation:

- product availability telah dikurangi saat reservasi;
- physical sellable belum berubah;
- outbound mengonsumsi reservation dan sellable bersamaan.

Validation:

```text
reservation_remaining >= outbound_qty
sellable_qty >= outbound_qty
```

Untuk manual outbound tanpa reservation:

```text
available_qty >= outbound_qty
```

Agar manual outbound tidak mengambil stock yang sudah dipesan marketplace.

---

## 35. Manual Outbound dan Reservation Protection

Formula:

```text
available_qty
=
sellable_qty - active_reserved_qty
```

Manual FEFO hanya boleh memakai:

```text
available_qty
```

Bukan seluruh sellable.

Batch allocation tetap memilih dari batch sellable, tetapi total limit product ditentukan available.

Karena reservation product-level tidak terikat batch, batch fisik yang diambil tetap FEFO.

---

## 36. Batch Holds

Hold sources:

```text
MANUAL_BLOCK
QUALITY_HOLD
RECALL_HOLD
STOCKTAKE_HOLD
RECONCILIATION_HOLD
RETURN_UNIDENTIFIED
MASTER_DATA_EXCEPTION
```

Hard hold:

- batch excluded;
- preview menampilkan reason;
- commit mengecek ulang.

Product hold:

- seluruh allocation product gagal.

Organization hold:

- semua outbound gagal.

---

## 37. Stocktake Interaction

### 37.1 Frozen Stocktake

Jika batch/product termasuk scope frozen:

```text
FEFO allocation blocked
```

Error:

```text
STOCKTAKE_HOLD_ACTIVE
```

### 37.2 Continuous Stocktake

Mutation boleh berjalan.

Ledger sequence dicatat agar physical count dapat direkonsiliasi.

### 37.3 Stocktake Adjustment

Adjustment tidak menggunakan FEFO.

Ia menargetkan line product/batch/bucket yang dihitung.

---

## 38. Return Interaction

### 38.1 Return Receipt

Receipt dicatat secara operasional:

```text
received_qty += qty
pending_inspection_qty += qty
stock transaction = none
ledger entry = none
projection delta = 0
```

Receipt tidak membuat batch dan tidak masuk kandidat FEFO. Batch `RETURN` baru hanya dibuat setelah inspeksi `SELLABLE` dengan provenance terverifikasi.

### 38.2 Return Inspected Sellable

Setelah `RETURN_SELLABLE_INBOUND`:

- provenance batch outbound terverifikasi;
- server membuat batch baru dengan `batch_kind_code = RETURN`;
- balance `SELLABLE` batch baru bertambah;
- batch baru dapat menjadi kandidat FEFO pada allocation berikutnya bila status, expiry, dan saldo memenuhi seluruh aturan.

### 38.3 Provenance Belum Terverifikasi

Tidak ada placeholder batch. Hasil `SELLABLE` ditolak sampai provenance terverifikasi.

### 38.4 Damaged Return

Tidak eligible karena klasifikasi `DAMAGED` retur tidak menambah stock bucket atau membuat movement kedua.

### 38.5 Return dengan Source Batch Expired

Jika source batch outbound telah expired:

- hasil `SELLABLE` ditolak;
- hasil `DAMAGED` dapat dicatat untuk audit/klaim tanpa movement stok;
- reconciliation menjelaskan alasan penolakan.

---

## 39. Batch Blocking Setelah Preview

Scenario:

1. preview memilih Batch A;
2. Admin lain memblokir Batch A;
3. commit dijalankan.

Commit:

- menghitung ulang;
- tidak menggunakan Batch A;
- menggunakan kandidat berikutnya jika cukup;
- atau gagal insufficient stock;
- menyimpan hasil final, bukan preview.

UI menampilkan perbedaan jika preview hash berubah.

---

## 40. Batch Baru Setelah Reservasi

Scenario:

1. order reserved saat batch terdekat adalah Batch B;
2. maklon receipt menambah Batch A dengan expiry lebih dekat;
3. order physical out.

Result:

```text
Batch A diprioritaskan
```

Karena final allocation terjadi saat physical outbound.

---

## 41. Expiry pada Tengah Malam

Operational date diambil sekali setelah transaction dimulai.

Simpan:

```text
operational_at
operational_date_snapshot
timezone_snapshot
```

Transaction yang dimulai sebelum tengah malam dan commit sesudah tengah malam tetap menggunakan snapshot operational date yang konsisten untuk command tersebut.

Command retry baru dapat memakai:

- original operational timestamp untuk event yang sama;
- bukan waktu retry.

---

## 42. Batch Expiry Hari yang Sama

Default buffer 0:

```text
expiry_date = operational_date
eligible = true
```

Namun gudang dapat memilih policy lebih ketat melalui safety buffer.

Perubahan policy:

- versioned;
- snapshot;
- tidak mengubah allocation historis.

---

## 43. Missing Expiry

Produk skincare phase 1 wajib expiry-tracked.

Batch tanpa expiry:

```text
not eligible
```

Issue:

```text
MISSING_EXPIRY_DATE
```

Jangan fallback ke FIFO.

Fallback diam-diam akan menciptakan perilaku berbeda pada data yang justru paling membutuhkan perhatian.

---

## 44. Same Expiry and Receipt Time

Jika dua batch memiliki expiry dan received time sama:

```text
batch_code
batch_id
```

menentukan urutan.

Hasil selalu stabil.

---

## 45. Blocked Batch dengan Saldo

Blocked batch tetap muncul pada stock position dan laporan.

Tetapi:

```text
eligible = false
```

Balance tidak dihapus.

Unblock memerlukan:

- Admin;
- reason;
- audit;
- valid master data;
- tidak ada unresolved critical hold.

---

## 46. Archived Batch

Archived batch tidak eligible.

Batch hanya boleh archived bila:

- saldo seluruh bucket nol;
- tidak ada obligation;
- tidak ada active reservation reference;
- audit tersedia.

Jika archived tetapi saldo > 0:

- reconciliation critical;
- allocator excludes;
- Admin harus memperbaiki status, bukan mengabaikan.

---

## 47. Expired Batch Status Job

Job dapat menandai:

```text
ACTIVE -> EXPIRED
```

berdasarkan local date/config.

Allocator tetap mengecek expiry dinamis.

Job bukan satu-satunya kontrol.

---

## 48. Allocation Persistence

Baseline table:

```text
inventory.stock_allocations
```

Allocation row dibuat setelah keputusan final.

Field baseline:

```text
id
organization_id
transaction_id
order_item_id
source_line_ref
product_id
batch_id
allocated_qty
fefo_rank
expiry_date_snapshot
created_at
```

---

## 49. Amendment: Allocation Metadata

Tambahkan:

```sql
alter table inventory.stock_allocations
  add column if not exists allocation_group_id uuid,
  add column if not exists algorithm_code text not null default 'FEFO',
  add column if not exists algorithm_version text not null default '1.0.0',
  add column if not exists operational_date_snapshot date,
  add column if not exists safety_buffer_days_snapshot integer not null default 0,
  add column if not exists batch_code_snapshot text,
  add column if not exists received_first_at_snapshot timestamptz,
  add column if not exists balance_before_snapshot bigint,
  add column if not exists allocation_sequence integer,
  add column if not exists correlation_id uuid;
```

Checks:

```sql
check (algorithm_code = 'FEFO'),
check (safety_buffer_days_snapshot >= 0),
check (balance_before_snapshot is null or balance_before_snapshot >= allocated_qty),
check (allocation_sequence is null or allocation_sequence > 0)
```

Historical snapshot immutable.

---

## 50. Allocation Groups

Recommended table:

```sql
create table inventory.stock_allocation_groups (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  stock_transaction_id uuid not null,
  source_type_code text not null,
  source_id uuid not null,
  algorithm_code text not null default 'FEFO',
  algorithm_version text not null,
  operational_at timestamptz not null,
  operational_date_snapshot date not null,
  timezone_snapshot text not null,
  safety_buffer_config_snapshot jsonb not null,
  requested_summary jsonb not null,
  result_summary jsonb not null,
  idempotency_key text not null,
  request_hash text not null,
  correlation_id uuid not null,
  created_at timestamptz not null default now(),
  created_by uuid,
  process_name text,
  unique (organization_id, idempotency_key),
  check ((created_by is not null) <> (process_name is not null))
);
```

Tujuan:

- menyimpan policy snapshot;
- menghubungkan multi-product allocation;
- membantu audit;
- membantu reconciliation.

---

## 51. Candidate Decision Snapshot

Optional but recommended:

```sql
create table inventory.stock_allocation_candidates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  allocation_group_id uuid not null
    references inventory.stock_allocation_groups(id),
  source_line_ref text not null,
  product_id uuid not null,
  batch_id uuid not null,
  candidate_rank integer not null,
  expiry_date_snapshot date,
  sellable_qty_snapshot bigint not null,
  eligibility_code text not null,
  exclusion_reason_code text,
  allocated_qty bigint not null default 0,
  created_at timestamptz not null default now(),
  check (candidate_rank > 0),
  check (sellable_qty_snapshot >= 0),
  check (allocated_qty >= 0)
);
```

Untuk fase 1, candidate snapshot dapat dibatasi pada:

- kandidat eligible yang dipakai;
- kandidat terdekat yang excluded karena critical reason;
- bukan seluruh batch nol.

---

## 52. Ledger Integration

Untuk setiap allocation:

```text
one negative ledger entry per batch
```

Example:

```text
allocation A -> ledger A / SELLABLE -5
allocation B -> ledger B / SELLABLE -7
```

Allocation total:

```text
SUM(stock_allocations.allocated_qty)
=
ABS(SUM(outbound ledger quantity_delta))
=
source line outbound quantity
```

Foreign references:

```text
allocation.transaction_id -> stock transaction
ledger transaction_id -> stock transaction
allocation.batch_id -> product batch
allocation.order_item_id/source_line_ref -> source line
```

---

## 53. Allocation dan Ledger Atomicity

Dilarang:

- allocation dibuat tanpa ledger;
- ledger dibuat tanpa allocation untuk FEFO outbound;
- projection berubah tanpa keduanya;
- source status berubah dulu lalu transaction gagal;
- reservation dikonsumsi tanpa ledger.

Reconciliation checks wajib menangkap semua pasangan yang hilang.

---

## 54. Source Status Integration

Marketplace:

```text
event received
-> state validation
-> allocation
-> ledger
-> reservation consume
-> order PHYSICALLY_OUT
-> event PROCESSED
```

Semua dalam transaction logical yang sama.

Event tidak boleh ditandai processed sebelum stock transaction sukses.

---

## 55. API Boundary

Recommended:

```text
POST /api/admin/outbound/manual/preview
POST /api/admin/outbound/manual/post
POST /api/admin/orders/:orderId/process-shipment
GET  /api/admin/allocations/:allocationGroupId
GET  /api/admin/products/:productId/fefo-preview
```

Marketplace event processor tidak harus mengekspos endpoint shipment manual ke browser.

---

## 56. Database Functions

Public domain entry points:

```text
api.preview_manual_outbound
api.post_manual_outbound
api.process_marketplace_event
api.get_allocation_trace
```

Internal:

```text
inventory.allocate_fefo
inventory.validate_fefo_candidates
inventory.persist_allocations
inventory.post_outbound_ledger
inventory.consume_reservations
inventory.refresh_stock_projections
```

Client tidak dapat execute internal function langsung.

---

## 57. Function Contract

Conceptual:

```sql
inventory.allocate_fefo(
  p_organization_id uuid,
  p_requests jsonb,
  p_operational_at timestamptz,
  p_source_type_code text,
  p_source_id uuid,
  p_idempotency_key text,
  p_request_hash text,
  p_actor_user_id uuid,
  p_process_name text,
  p_correlation_id uuid
) returns uuid
```

Return:

```text
allocation_group_id
```

Function internal tidak menerima batch selection dari client.

---

## 58. Pseudo Transaction

```sql
begin;

set local lock_timeout = '3s';

-- 1. idempotency
select * from inventory.idempotency_commands
where organization_id = p_org
  and idempotency_key = p_key
for update;

-- 2. source and reservation locks
-- 3. product position locks in deterministic order
-- 4. resolve operational date and policy
-- 5. lock FEFO candidates
-- 6. calculate complete plan
-- 7. fail if any product is short
-- 8. create stock transaction
-- 9. persist allocation group and rows
-- 10. write ledger entries
-- 11. update projections
-- 12. consume reservations
-- 13. update source/status/event
-- 14. audit and idempotency result

commit;
```

---

## 59. Idempotency

Scope:

```text
FEFO_OUTBOUND
```

Key examples:

```text
marketplace-outbound:{channel}:{external_order_id}:{event_id}
manual-outbound:{document_id}:post:{version}
```

Identical retry:

```text
return same allocation_group_id and transaction_id
```

Payload conflict:

```text
IDEMPOTENCY_PAYLOAD_MISMATCH
```

Retry tidak membuat allocation baru.

---

## 60. Request Hash

Hash meliputi:

- source;
- source lines;
- product;
- quantity;
- reason;
- channel;
- operational timestamp;
- reservation reference;
- algorithm version.

Batch result tidak masuk request hash karena diputuskan server saat commit.

---

## 61. Algorithm Version

Simpan:

```text
algorithm_code = FEFO
algorithm_version = 1.0.0
```

Version naik jika:

- eligibility berubah;
- sort order berubah;
- safety buffer semantics berubah;
- source aggregation berubah;
- split behavior berubah;
- lock strategy mengubah hasil;
- same-day expiry policy berubah.

Bug fix yang tidak mengubah hasil untuk data valid dapat menjadi patch version.

---

## 62. Koreksi Allocation

Allocation historis immutable.

Jika batch salah karena data master atau bug:

1. buat reversal terhadap ledger original;
2. apply reversal reference;
3. reverse reservation/source state jika aman;
4. correct master/source;
5. repost outbound menggunakan new command/version;
6. audit;
7. reconciliation.

Tidak:

```text
update stock_allocations set batch_id = ...
```

---

## 63. Reversal Constraints

Reversal quantity:

```text
<= unreversed original allocation quantity
```

Jika stock dari batch replacement sudah digunakan downstream:

- correction dapat gagal;
- create exception;
- lakukan investigation;
- jangan memaksa negative.

---

## 64. Picking Guidance

Allocation result dapat menghasilkan picking list:

```text
Product
Batch
Expiry
Quantity
```

Picking list bukan source of truth baru.

Jika gudang tidak menemukan batch:

- jangan pilih batch lain secara bebas;
- block/exception batch;
- cancel posting jika belum committed;
- jika sudah committed tetapi fisik berbeda, gunakan correction flow.

Idealnya allocation dan physical picking terjadi dalam satu workflow yang waktu jedanya pendek.

---

## 65. Allocation Sebelum atau Setelah Picking

Default fase 1:

```text
allocation final dibuat pada saat Admin/system mengonfirmasi physical outbound
```

Bila proses gudang membutuhkan picking list sebelumnya:

- gunakan preview;
- label `provisional`;
- commit recomputes;
- UI menunjukkan perubahan.

Hard batch reservation sebelum physical outbound berada di luar scope fase 1.

---

## 66. Manual Override

Tidak ada override batch normal.

Admin dapat:

- block batch;
- unblock batch;
- memperbaiki expiry dengan audit;
- memperbaiki batch code;
- memperbaiki receipt;
- menjalankan reversal;
- memproses stocktake.

Admin tidak dapat:

- mengirim `batch_id` pada normal outbound;
- memindahkan batch ke urutan depan;
- mengabaikan expiry;
- memilih batch lebih lambat tanpa rule.

Emergency override belum termasuk fase 1.

---

## 67. Near-Expiry Warning

Near-expiry adalah notification, bukan exclusion otomatis.

Config:

```text
near_expiry_days
```

Batch dapat:

- eligible;
- diberi warning;
- tetap diprioritaskan FEFO.

Safety buffer berbeda dari near-expiry warning.

---

## 68. Expired Disposal

Batch expired:

- excluded dari sales FEFO;
- muncul pada expiry work queue;
- disposal menargetkan batch tertentu;
- ledger `DISPOSAL_EXPIRED`;
- tidak menggunakan allocator penjualan.

---

## 69. Data Master Validation

Product:

```text
is_batch_tracked = true
is_expiry_tracked = true
is_active = true
```

Batch:

```text
batch_code non-empty
expiry_date non-null
manufactured_date <= expiry_date
organization/product consistent
```

Receipt:

- batch created or matched;
- expiry captured;
- duplicate batch code prevented per product.

---

## 70. Barcode Readiness

Jika scanner ditambahkan:

- product identifier;
- batch/lot;
- expiry;

dapat dipakai untuk receipt dan verification.

FEFO tetap memakai database batch records.

Barcode tidak boleh langsung menentukan allocation tanpa eligibility check.

---

## 71. Index Strategy

Existing:

```sql
create index idx_product_batches_fefo
on catalog.product_batches
  (organization_id, product_id, expiry_date, received_first_at, batch_code, id)
where status_code = 'ACTIVE';
```

Balance:

```sql
create index idx_stock_batch_balances_sellable
on inventory.stock_batch_balances
  (organization_id, product_id, batch_id)
where sellable_qty > 0;
```

Allocation trace:

```sql
create index idx_stock_allocations_source
on inventory.stock_allocations
  (organization_id, order_item_id, source_line_ref);

create index idx_stock_allocations_batch
on inventory.stock_allocations
  (organization_id, product_id, batch_id, created_at desc);
```

Group:

```sql
create index idx_allocation_groups_source
on inventory.stock_allocation_groups
  (organization_id, source_type_code, source_id);
```

---

## 72. Query Plan Verification

Gunakan:

```text
EXPLAIN (ANALYZE, BUFFERS)
```

pada fixture realistis.

Pastikan:

- batch candidate query memakai index relevan;
- sort tidak membengkak;
- lock order stabil;
- query tidak melakukan full scan tanpa alasan;
- RLS tidak menyebabkan plan buruk.

Jangan mengoptimasi dengan mengorbankan correctness.

---

## 73. Performance Baseline

Target awal, bukan kontrak final:

```text
70 active products
hundreds of packages/day
dozens of batches/product at most
```

Allocation harus:

- transaction singkat;
- tidak memuat seluruh ledger;
- membaca projection;
- lock hanya products/candidates terkait;
- batch insert allocations/ledger entries.

---

## 74. High Contention

Jika product sangat populer:

- product-level lock dapat menjadi bottleneck;
- ukur lock wait;
- optimasi transaksi;
- kurangi pekerjaan non-domain di dalam transaction;
- jangan menghapus lock tanpa bukti desain pengganti.

Future options:

- product-partitioned command queue;
- serializable retry;
- batch-level hard reservations;
- allocation worker.

Tidak diperlukan untuk fase 1 tanpa evidence.

---

## 75. Deadlock Prevention

- deterministic product order;
- deterministic batch order;
- same lock order across functions;
- no user interaction inside transaction;
- no network call inside transaction;
- transaction short;
- retry limited.

---

## 76. Retry Policy

| Error | Retry |
|---|:---:|
| Deadlock detected | Ya, terbatas |
| Serialization failure | Ya, bila digunakan |
| Lock timeout | Ya, terbatas |
| Connection transient | Ya, idempoten |
| Insufficient stock | Tidak |
| Missing expiry | Tidak |
| Blocked batch only | Tidak |
| Illegal source state | Tidak |
| Payload conflict | Tidak |
| Integrity hold | Tidak otomatis |

---

## 77. Error Codes

| Code | Meaning |
|---|---|
| `FEFO_REQUEST_INVALID` | Request invalid |
| `FEFO_PRODUCT_INACTIVE` | Product inactive |
| `FEFO_PRODUCT_NOT_BATCH_TRACKED` | Batch tracking disabled |
| `FEFO_PRODUCT_NOT_EXPIRY_TRACKED` | Expiry tracking disabled |
| `FEFO_NO_ELIGIBLE_BATCH` | Tidak ada candidate eligible |
| `FEFO_INSUFFICIENT_ELIGIBLE_STOCK` | Quantity eligible kurang |
| `FEFO_MISSING_EXPIRY_DATE` | Expiry missing |
| `FEFO_BATCH_BLOCKED` | Candidate blocked |
| `FEFO_BATCH_EXPIRED` | Candidate expired |
| `FEFO_BATCH_ARCHIVED` | Candidate archived |
| `FEFO_INTEGRITY_HOLD_ACTIVE` | Hold active |
| `FEFO_STOCKTAKE_HOLD_ACTIVE` | Frozen stocktake |
| `FEFO_RESERVATION_MISSING` | Reservation missing |
| `FEFO_RESERVATION_INSUFFICIENT` | Reservation remaining kurang |
| `FEFO_AVAILABLE_STOCK_INSUFFICIENT` | Manual available kurang |
| `FEFO_ALLOCATION_TOTAL_MISMATCH` | Total allocation salah |
| `FEFO_ORDER_VIOLATION` | Urutan FEFO dilanggar |
| `FEFO_LEDGER_MISMATCH` | Allocation dan ledger berbeda |
| `FEFO_LOCK_TIMEOUT` | Lock timeout |
| `FEFO_CONCURRENT_UPDATE` | Concurrent conflict |
| `FEFO_IDEMPOTENCY_CONFLICT` | Request hash berbeda |
| `FEFO_SOURCE_STATE_INVALID` | Source belum boleh outbound |
| `FEFO_MANUAL_BATCH_SELECTION_FORBIDDEN` | Client mengirim batch |
| `FEFO_ALGORITHM_VERSION_UNSUPPORTED` | Version tidak tersedia |
| `FEFO_PROJECTION_UNTRUSTED` | Projection integrity gagal |

---

## 78. UI: FEFO Preview

Tampilkan per product:

```text
Requested
Available
Eligible
Shortage
Safety Buffer
Operational Date
```

Candidate table/card:

```text
Rank
Batch
Expiry
Days to Expiry
Sellable
Planned Qty
Status
```

Excluded collapsible:

```text
Batch
Reason
```

Warning:

```text
Preview dapat berubah sebelum posting.
```

---

## 79. UI: Allocation Result

Header:

- allocation group;
- source;
- channel/reason;
- operational time;
- algorithm version;
- transaction;
- actor/process;
- status.

Lines:

- source line;
- product;
- batch;
- expiry snapshot;
- FEFO rank;
- allocated quantity;
- ledger entry;
- balance before/after.

Drill-down:

- order;
- reservation;
- product;
- batch;
- stock transaction;
- ledger;
- reconciliation.

---

## 80. Mobile UX

- allocation split as cards;
- batch and expiry visible;
- no horizontal scroll for primary result;
- preview warning sticky;
- confirm button after validation;
- no batch selector;
- error actionable;
- retry uses same command;
- loading disables duplicate submit.

---

## 81. Security

Every mutation:

- authenticated;
- active Admin or authorized system process;
- organization scoped;
- source ownership checked;
- no client-authoritative batch ID;
- RLS/grants;
- function boundary;
- idempotency;
- audit.

Read access also organization-scoped.

Internal allocation tables not directly writable by browser client.

---

## 82. RLS

Policies:

- Admin sees rows in own organization;
- direct insert/update/delete allocation denied;
- write only through database function;
- service process uses controlled server path;
- no `USING (true)` permissive policy.

---

## 83. Audit Events

```text
FEFO_PREVIEWED
FEFO_ALLOCATION_STARTED
FEFO_CANDIDATES_EVALUATED
FEFO_ALLOCATION_COMMITTED
FEFO_ALLOCATION_FAILED
FEFO_ALLOCATION_RETRIED
FEFO_ALLOCATION_REVERSED
BATCH_BLOCKED
BATCH_UNBLOCKED
SAFETY_BUFFER_CHANGED
FEFO_ALGORITHM_VERSION_CHANGED
```

Audit includes:

- actor/process;
- source;
- requested quantities;
- operational date;
- policy snapshot;
- result;
- error;
- correlation ID.

---

## 84. Observability

Metrics:

```text
fefo_allocations_total
fefo_allocated_units_total
fefo_split_allocations_total
fefo_batches_per_allocation
fefo_allocation_duration_ms
fefo_lock_wait_ms
fefo_lock_timeouts_total
fefo_insufficient_stock_total
fefo_no_eligible_batch_total
fefo_expired_exclusions_total
fefo_blocked_exclusions_total
fefo_retries_total
fefo_reversals_total
fefo_order_violations_total
```

Logs:

```json
{
  "event": "fefo_allocation_committed",
  "allocationGroupId": "uuid",
  "sourceId": "uuid",
  "productCount": 3,
  "batchAllocationCount": 5,
  "durationMs": 80,
  "correlationId": "uuid",
  "organizationId": "uuid"
}
```

No PII or secrets.

---

## 85. Rekonsiliasi

Checks minimum:

```text
REC_ALLOCATION_TOTAL
REC_ALLOCATION_BATCH_PRODUCT
REC_EXPIRED_ALLOCATION
REC_BLOCKED_BATCH_ALLOCATION
REC_FEFO_ORDER
REC_OUTBOUND_WITHOUT_LEDGER
REC_LEDGER_WITHOUT_PHYSICAL_STATE
REC_PRE_SHIPMENT_WITH_OUTBOUND
REC_CHANNEL_THRESHOLD
REC_PHYSICALLY_OUT_RESERVATION
REC_BUNDLE_SNAPSHOT_TOTAL
RETURN_INSPECTION_CONSISTENCY
```

Tambahan:

```text
REC_ALLOCATION_POLICY_SNAPSHOT
REC_ALLOCATION_LEDGER_QUANTITY
REC_ALLOCATION_SOURCE_REFERENCE
REC_ALLOCATION_DUPLICATE_EFFECT
REC_FEFO_RANK_SEQUENCE
```

---

## 86. FEFO Reconciliation Logic

Untuk setiap source line:

```text
allocation_total = requested_outbound_qty
```

Untuk setiap allocation:

```text
allocated_qty = abs(outbound ledger qty for same batch/source)
```

Rank:

```text
1..n without gap
```

Eligibility historical:

```text
expiry_date_snapshot - buffer >= operational_date_snapshot
```

Order:

```text
rank_i < rank_j
=> sort_key_i <= sort_key_j
```

---

## 87. Candidate Decision Evidence

Untuk check FEFO order, simpan:

- operational date;
- buffer;
- eligible candidate sort keys;
- sellable snapshot;
- selected quantity;
- exclusion reason.

Tanpa decision evidence, check hanya dapat melakukan best-effort berdasarkan state saat ini, yang mungkin sudah berubah.

---

## 88. Unit Tests

Test:

- operational date;
- safety buffer;
- eligibility;
- sort;
- same expiry;
- split;
- shortage;
- bundle normalization;
- duplicate product lines;
- allocation hash;
- algorithm version;
- error mapping.

---

## 89. Database Tests

| ID | Test |
|---|---|
| `FEFO-DB-001` | Earliest expiry selected |
| `FEFO-DB-002` | Same expiry uses receipt time |
| `FEFO-DB-003` | Final tie-break deterministic |
| `FEFO-DB-004` | Expired excluded |
| `FEFO-DB-005` | Blocked excluded |
| `FEFO-DB-006` | Archived excluded |
| `FEFO-DB-007` | Quarantine excluded |
| `FEFO-DB-008` | Damaged excluded |
| `FEFO-DB-009` | Return sellable tanpa provenance ditolak sebelum batch dibuat |
| `FEFO-DB-010` | Safety buffer works |
| `FEFO-DB-011` | Split exact |
| `FEFO-DB-012` | Insufficient rolls back |
| `FEFO-DB-013` | Allocation equals ledger |
| `FEFO-DB-014` | Reservation consumed |
| `FEFO-DB-015` | Manual respects reserved |
| `FEFO-DB-016` | Duplicate idempotent |
| `FEFO-DB-017` | Payload conflict rejected |
| `FEFO-DB-018` | Cross-org rejected |
| `FEFO-DB-019` | Direct allocation write denied |
| `FEFO-DB-020` | Frozen stocktake blocks |
| `FEFO-DB-021` | Integrity hold blocks |
| `FEFO-DB-022` | Multi-product all-or-nothing |
| `FEFO-DB-023` | Same-day expiry default eligible |
| `FEFO-DB-024` | Missing expiry fails |
| `FEFO-DB-025` | Reversal references original |

---

## 90. Concurrency Tests

### 90.1 Last Unit

```text
sellable = 1
two outbound requests = 1 each
```

Expected:

```text
one succeeds
one fails
no negative
```

### 90.2 Same Product Different Orders

Expected:

- serial product lock;
- each result uses remaining FEFO state;
- no duplicate unit.

### 90.3 Multiple Products Opposite Order

Two commands request A+B and B+A.

Expected:

- deterministic product lock order;
- no deadlock or retry succeeds safely.

### 90.4 Batch Block Concurrently

- allocation and block compete;
- one lock order decides;
- final state consistent;
- no allocation from batch blocked before allocator recheck.

### 90.5 Receipt Concurrently

New earlier-expiry receipt while allocation runs.

Expected:

- result based on consistent lock/snapshot ordering;
- subsequent allocation sees new batch;
- no partial anomaly.

---

## 91. Integration Tests

- Shopee `SHIPPED`;
- TikTok `IN_TRANSIT`;
- manual offline;
- bonus;
- promo;
- sample;
- simulator;
- import;
- return-to-sellable before next outbound;
- stocktake hold;
- reconciliation.

---

## 92. E2E Scenarios

| ID | Scenario |
|---|---|
| `FEFO-E2E-001` | Single batch |
| `FEFO-E2E-002` | Split two batches |
| `FEFO-E2E-003` | Three-batch split |
| `FEFO-E2E-004` | Expired nearest batch skipped |
| `FEFO-E2E-005` | Blocked nearest batch skipped |
| `FEFO-E2E-006` | Missing expiry exception |
| `FEFO-E2E-007` | Same expiry deterministic |
| `FEFO-E2E-008` | Safety buffer |
| `FEFO-E2E-009` | Shopee reservation to outbound |
| `FEFO-E2E-010` | TikTok reservation to outbound |
| `FEFO-E2E-011` | Manual cannot consume reserved stock |
| `FEFO-E2E-012` | Bundle expansion |
| `FEFO-E2E-013` | New earlier batch after reservation |
| `FEFO-E2E-014` | Return sellable becomes candidate |
| `FEFO-E2E-015` | Unknown-provenance sellable return rejected |
| `FEFO-E2E-016` | Concurrent last unit |
| `FEFO-E2E-017` | Preview changes before commit |
| `FEFO-E2E-018` | Frozen stocktake |
| `FEFO-E2E-019` | Duplicate retry |
| `FEFO-E2E-020` | Reversal and repost |

---

## 93. Property-Based Tests

Generate random:

- products;
- batches;
- expiry;
- status;
- balances;
- buffers;
- requests.

Properties:

```text
allocation total = request
all selected batches eligible
sort order nondecreasing
allocation qty > 0
allocation qty <= balance snapshot
no negative balance
ledger total = allocation total
no partial result on shortage
idempotent retry has same result
```

---

## 94. Golden Fixture

Products:

```text
SKU-A normal
SKU-B bundle component
SKU-C no eligible stock
SKU-D missing expiry
SKU-E blocked
SKU-F return provenance unknown
```

Batches:

```text
A1 expiry +10, sellable 5
A2 expiry +30, sellable 20
A3 expiry +30, earlier receipt, sellable 4
A4 expired, sellable 10
A5 blocked, sellable 10
A6 quarantine 7
A7 damaged 3
```

Expected cases versioned in repo.

---

## 95. Acceptance Criteria

### Eligibility

- `FEFO-AC-001`: Only active matching product batches considered.
- `FEFO-AC-002`: Missing expiry excluded.
- `FEFO-AC-003`: Expired excluded.
- `FEFO-AC-004`: Blocked/archived excluded.
- `FEFO-AC-005`: Quarantine/damaged excluded.
- `FEFO-AC-006`: Sellable return tanpa provenance ditolak sebelum batch RETURN dibuat.
- `FEFO-AC-007`: Holds enforced.

### Ordering

- `FEFO-AC-008`: Earliest expiry first.
- `FEFO-AC-009`: Receipt time tie-break.
- `FEFO-AC-010`: Batch code/ID deterministic.
- `FEFO-AC-011`: Safety buffer applied.
- `FEFO-AC-012`: Policy snapshot stored.

### Allocation

- `FEFO-AC-013`: Split supported.
- `FEFO-AC-014`: Total exact.
- `FEFO-AC-015`: Shortage rolls back all.
- `FEFO-AC-016`: Multi-product atomic.
- `FEFO-AC-017`: Bundle expanded first.
- `FEFO-AC-018`: No manual batch selector.
- `FEFO-AC-019`: Preview recomputed at commit.

### Reservation

- `FEFO-AC-020`: Marketplace uses reservation.
- `FEFO-AC-021`: Manual respects available.
- `FEFO-AC-022`: Reservation consumed atomically.
- `FEFO-AC-023`: Pre-shipment no allocation final.

### Ledger

- `FEFO-AC-024`: Entry per allocated batch.
- `FEFO-AC-025`: Allocation references transaction.
- `FEFO-AC-026`: Allocation equals ledger.
- `FEFO-AC-027`: Historical rows immutable.
- `FEFO-AC-028`: Correction uses reversal.

### Concurrency

- `FEFO-AC-029`: No over-allocation.
- `FEFO-AC-030`: Deterministic lock order.
- `FEFO-AC-031`: No normal `SKIP LOCKED`.
- `FEFO-AC-032`: Retry idempotent.
- `FEFO-AC-033`: Lock timeout safe.

### Security and Trace

- `FEFO-AC-034`: Only Admin/system process can initiate.
- `FEFO-AC-035`: Cross-org blocked.
- `FEFO-AC-036`: Client cannot write allocations.
- `FEFO-AC-037`: Drill-down available.
- `FEFO-AC-038`: Algorithm version stored.
- `FEFO-AC-039`: Reconciliation checks pass.
- `FEFO-AC-040`: Mobile result usable.

---

## 96. Release Gates

Do not release if:

- Admin can choose batch normal outbound;
- expired batch can be allocated;
- sellable return tanpa provenance dapat diposting;
- allocation and ledger can diverge;
- insufficient stock leaves partial movement;
- two requests can over-allocate;
- preview is trusted as final;
- bundle allocation uses pseudo-stock;
- manual outbound ignores reservation;
- algorithm version absent;
- idempotency absent;
- direct table writes allowed;
- FEFO tests fail;
- reconciliation cannot verify order.

---

## 97. Definition of Done

Implemented when:

1. canonical allocation request exists;
2. bundle normalization exists;
3. operational date explicit;
4. safety buffer config exists;
5. eligibility rules exist;
6. deterministic sort exists;
7. split allocation exists;
8. product lock exists;
9. candidate lock exists;
10. no normal `SKIP LOCKED`;
11. shortage rollback exists;
12. multi-product atomicity exists;
13. reservation consumption exists;
14. manual availability protection exists;
15. allocation group exists;
16. allocation rows exist;
17. ledger integration exists;
18. projection update exists;
19. source status integration exists;
20. idempotency exists;
21. audit exists;
22. preview exists;
23. drill-down exists;
24. reversal exists;
25. reconciliation exists;
26. pgTAP tests pass;
27. concurrency tests pass;
28. simulator scenarios pass;
29. RLS/grants pass;
30. live demo stable.

---

## 98. Traceability ke Source Proyek

| Source requirement | FEFO design |
|---|---|
| Batch dan expiry per batch | Product batches with expiry |
| FEFO otomatis | System allocator |
| Operator tidak memilih batch | No manual batch input |
| Bundle dihitung satuan | Normalize before FEFO |
| Shopee keluar saat SHIPPED | Trigger integration |
| TikTok keluar saat IN_TRANSIT | Trigger integration |
| Sebelum trigger hanya reservasi | Product-level reservation |
| Ledger pusat | Allocation-linked ledger |
| Drill-down | Source-to-batch trace |
| Retur diputuskan gudang | Only inspected sellable may re-enter FEFO |
| Rekonsiliasi | FEFO allocation checks |
| Hanya Admin | Admin/system process boundary |

---

## 99. Amendment terhadap Dokumen Sebelumnya

### `03-business-rules.md`

Ganti istilah Operator pada batch selection menjadi Admin, dengan hasil tetap:

```text
manual batch selection forbidden
```

### `04-stock-ledger-design.md`

Tambahkan:

- allocation group;
- policy snapshot;
- algorithm version;
- operational date;
- safety buffer.

### `05-database-schema.md`

Tambahkan:

- allocation group;
- allocation metadata;
- candidate snapshot optional;
- `requires_fefo` pada movement reason;
- hold integration.

### `07-marketplace-simulator.md`

Preview scenario harus membedakan:

```text
expected candidate
final committed allocation
```

### `08-reconciliation-logic.md`

Gunakan decision snapshot untuk `REC_FEFO_ORDER`.

### `09-return-and-claim-flow.md`

Pastikan hasil SELLABLE tanpa provenance ditolak sebelum batch RETURN dibuat.

---

## 100. Keputusan Terbuka

1. Safety buffer final untuk tiap produk/channel.
2. Apakah same-day expiry boleh dikirim secara operasional.
3. Apakah batch code memakai case-sensitive ordering.
4. Apakah candidate snapshot penuh disimpan.
5. Lock timeout final.
6. Maximum retry.
7. Whether product-level lock is sufficient after scale growth.
8. Whether preview token is implemented.
9. Whether picker can report batch unavailable before commit.
10. Whether hard batch reservation is needed later.
11. Whether blind picking is allowed.
12. Whether near-expiry warning threshold varies by product.
13. Whether allocation result is printable.
14. Whether barcode scan verification belongs to MVP.
15. Whether full allocation group is exposed via public API.

Until decided, safe defaults in this document apply.

---

## 101. Referensi Teknis Resmi

### WHO

- WHO warehousing guidance defines FEFO for dated items and FIFO for non-dated items.
- WHO storage/transport guidance uses earliest-expiry-first-out as equivalent to FEFO.

### GS1

- GS1 traceability standards support batch/lot-level identification.
- GS1 Application Identifier `10` represents batch/lot.
- GS1 Application Identifier `17` represents expiry date.
- Batch and expiry attributes can support internal traceability and FEFO workflows.

### PostgreSQL

- `SELECT ... FOR UPDATE` locks selected rows against conflicting writers/lockers until transaction end.
- Read Committed re-evaluates row conditions after waiting on concurrent updates.
- Deterministic locking order helps reduce deadlock risk.
- `EXPLAIN` is used to inspect query plans.
- Row-level security can restrict rows by command and role.

### Supabase

- Row Level Security provides defense in depth.
- Database functions are appropriate server-side boundaries for data-intensive domain operations.
- pgTAP can test functions, constraints, RLS policies, and data integrity.

Official source locations are listed in project research notes and should be pinned in repository documentation during implementation.

---

## 102. Ringkasan Keputusan Final

FEFO dijalankan saat barang benar-benar keluar, bukan saat order baru masuk.

```text
ORDER CREATED
-> PRODUCT RESERVATION
-> NO FINAL BATCH
```

```text
PHYSICAL OUTBOUND
-> LOCK PRODUCT
-> LOCK ELIGIBLE BATCHES
-> SORT BY EXPIRY
-> SPLIT IF NEEDED
-> CREATE ALLOCATION
-> POST LEDGER
-> CONSUME RESERVATION
-> UPDATE SOURCE
```

Urutan resmi:

```text
expiry date
received first at
batch code
batch id
```

Batch berikut tidak eligible:

```text
expired
blocked
archived
quarantine
damaged
missing expiry
held
zero sellable
```

Preview hanya memberi perkiraan. Commit menghitung ulang dan mengunci row. `SKIP LOCKED` tidak digunakan untuk FEFO normal karena batch terdekat tidak boleh dilompati hanya karena sedang sibuk selama beberapa milidetik. Sistem persediaan tidak sedang memilih antrean kasir tercepat; ia sedang mempertahankan aturan batch dan jejak fisik.

Allocation historis immutable. Kesalahan diperbaiki melalui reversal dan repost. Setiap quantity yang keluar dapat ditelusuri dari source line ke allocation, batch, stock transaction, ledger, dan reconciliation evidence.

---

## FEFO Setelah Marketplace Listing Normalization

FEFO tidak pernah berjalan pada entity bundle. Urutan marketplace yang berlaku:

```text
external listing
-> effective mapping/recipe version
-> canonical product component snapshot
-> reservation per product
-> FEFO allocation per product
-> ledger outbound per batch
```

Untuk listing quantity lebih dari satu, kebutuhan produk dihitung lebih dahulu dengan `listing_quantity × component_quantity`. Setelah ekspansi berhasil secara atomic, setiap canonical product mengikuti aturan FEFO yang sama dengan produk satuan lain.

Recipe version tidak memengaruhi sorting batch. Historical order tetap menggunakan component snapshot lama meskipun version listing baru sudah aktif. Pembatalan pasca-shipment tidak menjalankan FEFO ulang dan memulihkan exact batch allocation dari shipment asli.
