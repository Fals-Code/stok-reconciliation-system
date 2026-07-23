---
title: "Business Rules - Sistem Rekonsiliasi Stok"
document_id: "03-business-rules"
version: "1.0.0"
status: "Draft for Implementation"
last_updated: "2026-07-12"
language: "id-ID"
timezone: "Asia/Jakarta"
source_of_truth: "stok-management-system.pdf"
depends_on:
  - "01-project-brief.md"
  - "02-product-requirements.md"
---

# Business Rules: Sistem Rekonsiliasi Stok

## 1. Tujuan Dokumen

Dokumen ini menerjemahkan arah produk dan requirement menjadi aturan bisnis yang deterministik. Aturan di sini menjelaskan **kapan suatu tindakan boleh dilakukan, data apa yang wajib tersedia, perubahan apa yang dihasilkan, kondisi apa yang harus ditolak, dan jejak apa yang wajib disimpan**.

Dokumen ini menjadi acuan bersama untuk:

- implementasi domain pada Next.js, TypeScript, dan Supabase/Postgres;
- penyusunan migration, constraint, database function, dan policy;
- pembuatan UI serta pesan kesalahan;
- pengujian unit, integrasi, database, dan acceptance test;
- investigasi selisih stok dan perubahan aturan di masa depan.

> **Prinsip tertinggi:** tidak ada angka stok yang berubah tanpa jejak yang dapat ditelusuri.

## 2. Ruang Lingkup dan Batas

Aturan ini berlaku untuk aplikasi fase 1 dengan karakteristik berikut:

- satu gudang fisik;
- produk skincare dalam satuan unit bulat;
- stok dikelola per produk dan batch;
- tanggal kedaluwarsa wajib per batch;
- kanal marketplace Shopee dan TikTok Shop masuk melalui simulator atau impor CSV;
- belum ada integrasi API langsung;
- tidak ada harga, nilai persediaan, margin, atau kompensasi uang;
- bundle tidak memiliki stok sendiri;
- reservasi dipisahkan dari pergerakan fisik;
- saldo negatif dilarang.

Perubahan terhadap batas tersebut wajib melalui keputusan produk dan pembaruan dokumen. Kode tidak boleh diam-diam memperluas domain, misalnya menambahkan multi-warehouse atau pecahan kuantitas tanpa keputusan eksplisit.

## 3. Kedudukan dan Prioritas Aturan

Jika terjadi konflik, urutan keputusan adalah:

1. keputusan klien yang tercatat pada source project;
2. keputusan baru yang telah disetujui dan dicatat dalam decision log;
3. aturan bisnis pada dokumen ini;
4. requirement pada `02-product-requirements.md`;
5. detail implementasi, UI, dan arsitektur.

Konflik tidak boleh diselesaikan sepihak melalui asumsi di kode. Implementasi harus ditahan pada bagian yang konflik, diberi issue, dan diputuskan melalui change control.

## 4. Istilah Normatif

- **MUST / WAJIB:** tidak boleh dilanggar pada fase 1.
- **MUST NOT / DILARANG:** tindakan harus ditolak.
- **SHOULD / SEBAIKNYA:** diterapkan kecuali ada alasan terdokumentasi.
- **MAY / DAPAT:** opsional dan tidak mengubah invariant.
- **Posted:** transaksi final yang telah menghasilkan movement atau perubahan domain final.
- **Draft:** data belum final dan belum boleh memengaruhi saldo.
- **Movement:** entri ledger yang mengubah kuantitas fisik suatu bucket.
- **Business event:** kejadian domain yang dapat mengubah status, reservasi, atau movement.

## 5. Format Identitas Aturan

Setiap aturan menggunakan format `BR-<DOMAIN>-<NNN>`.

| Domain | Arti |
|---|---|
| `GOV` | tata kelola dan perubahan aturan |
| `INV` | invariant stok dan ledger |
| `QTY` | kuantitas dan rumus saldo |
| `ACL` | pengguna, peran, dan otorisasi |
| `PRD` | produk |
| `BAT` | batch |
| `CUT` | saldo awal dan cutover |
| `RCV` | penerimaan maklon |
| `BND` | bundle |
| `EVT` | event marketplace dan idempotensi |
| `ORD` | pesanan dan status |
| `RSV` | reservasi |
| `OUT` | outbound marketplace dan FEFO |
| `MAN` | outbound manual |
| `RET` | retur |
| `CLM` | klaim retur hilang |
| `EXP` | kedaluwarsa |
| `LED` | ledger dan saldo |
| `REV` | reversal |
| `STK` | stok opname |
| `REC` | rekonsiliasi harian |
| `IMP` | impor CSV |
| `SIM` | simulator |
| `NTF` | notifikasi |
| `AUD` | audit trail |
| `TIM` | waktu dan zona waktu |

## 6. Invariant Global

Invariant berikut tidak memiliki pengecualian melalui UI biasa.

| ID | Aturan | Penegakan minimum | Kode pelanggaran |
|---|---|---|---|
| BR-INV-001 | Setiap perubahan kuantitas fisik MUST menghasilkan movement ledger. | Domain service + database | `STOCK_CHANGE_WITHOUT_LEDGER` |
| BR-INV-002 | Saldo MUST dapat direkonstruksi dari movement yang posted. | Database test + rekonsiliasi | `BALANCE_NOT_RECONSTRUCTIBLE` |
| BR-INV-003 | Movement posted MUST NOT diedit atau dihapus. | Permission + trigger/policy | `POSTED_MOVEMENT_IMMUTABLE` |
| BR-INV-004 | Koreksi movement MUST dilakukan melalui reversal dan, bila diperlukan, transaksi pengganti. | Domain service | `DIRECT_MOVEMENT_CORRECTION_FORBIDDEN` |
| BR-INV-005 | Proses majemuk yang memengaruhi stok MUST atomik: seluruh perubahan berhasil atau seluruhnya gagal. | Database transaction | `PARTIAL_STOCK_COMMIT` |
| BR-INV-006 | Saldo `SELLABLE`, `QUARANTINE`, `DAMAGED`, `RESERVED`, dan `AVAILABLE` MUST NOT negatif. | Constraint + transaction check | `NEGATIVE_STOCK_FORBIDDEN` |
| BR-INV-007 | Kejadian eksternal yang sama MUST NOT menghasilkan efek domain lebih dari sekali. | Unique constraint + idempotency | `DUPLICATE_EVENT` |
| BR-INV-008 | Alasan dan kanal MUST disimpan sebagai atribut terpisah. | Schema + validation | `REASON_CHANNEL_NOT_SEPARATED` |
| BR-INV-009 | Setiap movement MUST mereferensikan tepat satu produk dan satu batch. | Foreign key + not-null | `MOVEMENT_PRODUCT_BATCH_REQUIRED` |
| BR-INV-010 | Semua kuantitas fase 1 MUST berupa bilangan bulat. | Database constraint | `INTEGER_QUANTITY_REQUIRED` |
| BR-INV-011 | Simulator, impor CSV, dan API masa depan MUST memakai pipeline event/domain yang sama. | Architecture test | `BYPASSED_DOMAIN_PIPELINE` |
| BR-INV-012 | Tidak ada fitur fase 1 yang boleh menyimpan harga atau nilai uang. | Schema review + test | `MONETARY_FIELD_OUT_OF_SCOPE` |
| BR-INV-013 | Perubahan master atau transaksi kritis MUST menyimpan actor/proses dan waktu. | Audit service | `ACTOR_OR_TIMESTAMP_MISSING` |
| BR-INV-014 | Data historis yang sudah direferensikan transaksi MUST diarsipkan, bukan dihapus permanen melalui aplikasi. | Foreign key + UI policy | `HISTORICAL_DELETE_FORBIDDEN` |
| BR-INV-015 | Akses dan mutasi MUST ditegakkan pada sisi server/database, bukan hanya dengan menyembunyikan elemen UI. | RLS + server authorization | `SERVER_AUTHORIZATION_REQUIRED` |

## 7. Model Kuantitas dan Bucket

### 7.1 Bucket Fisik

| Bucket | Makna | Dapat dialokasikan untuk penjualan |
|---|---|:---:|
| `SELLABLE` | barang fisik layak jual | Ya |
| `QUARANTINE` | barang fisik menunggu inspeksi/identifikasi | Tidak |
| `DAMAGED` | barang fisik rusak dan masih berada di gudang | Tidak |

`RESERVED` bukan bucket fisik. Reserved adalah komitmen terhadap stok `SELLABLE` untuk pesanan aktif.

### 7.2 Rumus Resmi

```text
on_hand  = sellable + quarantine + damaged
available = sellable - reserved
```

### 7.3 Aturan Kuantitas

| ID | Aturan | Kode pelanggaran |
|---|---|---|
| BR-QTY-001 | Kuantitas input MUST berupa integer nol atau positif pada draft, kecuali movement terhitung menggunakan arah atau signed quantity internal. | `INVALID_QUANTITY` |
| BR-QTY-002 | Transaksi dengan kuantitas nol MUST NOT diposting sebagai movement. | `ZERO_MOVEMENT_FORBIDDEN` |
| BR-QTY-003 | Outbound MUST NOT melebihi saldo bucket sumber. | `INSUFFICIENT_BUCKET_BALANCE` |
| BR-QTY-004 | Reserved aktif MUST NOT melebihi sellable pada produk yang sama. | `RESERVED_EXCEEDS_SELLABLE` |
| BR-QTY-005 | Available MUST dihitung, bukan diketik atau diedit manual. | `DIRECT_AVAILABLE_EDIT_FORBIDDEN` |
| BR-QTY-006 | Ringkasan saldo per produk MUST sama dengan jumlah saldo seluruh batch produk tersebut. | `PRODUCT_BATCH_TOTAL_MISMATCH` |
| BR-QTY-007 | Transfer antar-bucket MUST menjaga `on_hand` tetap sama. | `BUCKET_TRANSFER_UNBALANCED` |
| BR-QTY-008 | Inbound dan outbound fisik MUST mengubah `on_hand` sesuai kuantitas posted. | `ON_HAND_MOVEMENT_MISMATCH` |
| BR-QTY-009 | Kuantitas bundle MUST diekspansi menjadi kuantitas komponen sebelum reservasi atau outbound. | `BUNDLE_NOT_EXPANDED` |
| BR-QTY-010 | Perhitungan dan perbandingan kuantitas MUST dilakukan di database transaction yang sama dengan posting movement. | `STALE_QUANTITY_CHECK` |

### 7.4 Pola Efek Movement

| Movement | Bucket asal | Bucket tujuan | Dampak on hand |
|---|---|---|---:|
| `INITIAL_BALANCE` | eksternal | bucket hasil cutover | bertambah |
| `RECEIPT` | eksternal | `SELLABLE` atau `QUARANTINE` | bertambah |
| `OUTBOUND_MARKETPLACE` | `SELLABLE` | eksternal | berkurang |
| `OUTBOUND_MANUAL` | `SELLABLE` | eksternal | berkurang |
| `RETURN_SELLABLE_INBOUND` | eksternal | batch `RETURN` / `SELLABLE` | bertambah |
| `DISPOSAL_DAMAGED` | `DAMAGED` | eksternal | berkurang |
| `DISPOSAL_EXPIRED` | bucket fisik yang dipilih | eksternal | berkurang |
| `STOCKTAKE_ADJUSTMENT` | bergantung tanda | bucket terkait/eksternal | berubah sesuai selisih |
| `REVERSAL` | kebalikan movement asal | kebalikan movement asal | membalik dampak asal |

## 8. Pengguna, Peran, dan Otorisasi

| ID | Aturan | Penegakan minimum |
|---|---|---|
| BR-ACL-001 | Hanya pengguna aktif dan terautentikasi yang boleh mengakses data operasional. | Auth + RLS |
| BR-ACL-002 | `VIEWER` hanya boleh membaca data yang diizinkan. | RLS + server |
| BR-ACL-003 | `OPERATOR` boleh membuat dan memproses transaksi operasional sesuai scope, tetapi tidak boleh mengubah movement posted. | Server + RLS |
| BR-ACL-004 | Hanya `ADMIN` yang boleh mengelola pengguna, konfigurasi kritis, reversal, dan approval koreksi opname. | Server + RLS |
| BR-ACL-005 | Pengguna yang dinonaktifkan MUST kehilangan akses pada permintaan berikutnya. | Auth/session validation |
| BR-ACL-006 | Service-role key atau secret MUST NOT dikirim ke browser. | Deployment/security test |
| BR-ACL-007 | Actor pada transaksi MUST berasal dari identitas server yang tervalidasi, bukan nilai bebas dari client. | Server-side attribution |
| BR-ACL-008 | Jika pemisahan pembuat dan approver diaktifkan, pembuat koreksi MUST NOT menyetujui koreksinya sendiri. | Workflow validation |
| BR-ACL-009 | Percobaan tindakan tanpa hak MUST ditolak dan dicatat sebagai security audit event. | RLS/server + audit |

## 9. Produk

| ID | Aturan | Kode pelanggaran |
|---|---|---|
| BR-PRD-001 | SKU MUST unik tanpa membedakan spasi tidak bermakna; normalisasi format dilakukan sebelum pengecekan keunikan. | `DUPLICATE_SKU` |
| BR-PRD-002 | Nama produk dan SKU MUST diisi. | `PRODUCT_REQUIRED_FIELDS_MISSING` |
| BR-PRD-003 | Satuan dasar fase 1 MUST `UNIT`. | `UNSUPPORTED_UNIT` |
| BR-PRD-004 | Produk baru MUST memiliki saldo nol sampai ada movement. | `PRODUCT_CREATED_WITH_BALANCE` |
| BR-PRD-005 | Produk yang telah memiliki transaksi MUST NOT dihapus permanen. | `PRODUCT_DELETE_FORBIDDEN` |
| BR-PRD-006 | Produk tidak aktif MUST NOT digunakan pada transaksi baru, tetapi histori tetap terlihat. | `INACTIVE_PRODUCT_FOR_TRANSACTION` |
| BR-PRD-007 | Perubahan nama produk MUST NOT mengubah snapshot nama/referensi historis yang diperlukan audit. | `HISTORY_MUTATED_BY_PRODUCT_EDIT` |
| BR-PRD-008 | Perubahan SKU setelah produk memiliki transaksi hanya boleh melalui prosedur Admin yang terdokumentasi atau ditolak. Default fase 1: ditolak. | `TRANSACTED_SKU_CHANGE_FORBIDDEN` |

## 10. Batch

| ID | Aturan | Kode pelanggaran |
|---|---|---|
| BR-BAT-001 | Kombinasi `product_id + batch_code` MUST unik. | `DUPLICATE_PRODUCT_BATCH` |
| BR-BAT-002 | Tanggal kedaluwarsa MUST diisi sebelum batch menerima saldo sellable. | `EXPIRY_DATE_REQUIRED` |
| BR-BAT-003 | Membuat batch MUST NOT menambah stok. | `BATCH_CREATED_WITH_BALANCE` |
| BR-BAT-004 | Batch `BLOCKED`, effectively expired, atau `ARCHIVED` MUST NOT menjadi kandidat FEFO; `QUARANTINE` dan `DAMAGED` adalah bucket fisik, bukan lifecycle. | `BATCH_NOT_ALLOCATABLE` |
| BR-BAT-005 | Status efektif `EXPIRED` berlaku ketika tanggal operasional lokal telah melewati tanggal kedaluwarsa. | `EXPIRED_STATUS_MISMATCH` |
| BR-BAT-006 | Batch dengan saldo atau histori MUST NOT dihapus permanen. | `BATCH_DELETE_FORBIDDEN` |
| BR-BAT-007 | Perubahan status batch MUST menyimpan alasan, actor, dan waktu. | `BATCH_STATUS_AUDIT_REQUIRED` |
| BR-BAT-008 | Perubahan tanggal kedaluwarsa setelah batch memiliki movement MUST membutuhkan Admin, alasan, dan audit sebelum-sesudah. | `EXPIRY_CHANGE_RESTRICTED` |
| BR-BAT-009 | Batch archived MUST tetap muncul pada ledger dan laporan historis. | `ARCHIVED_BATCH_HISTORY_HIDDEN` |
| BR-BAT-010 | Batch tanpa identitas yang dapat diverifikasi MUST diperlakukan sebagai exception/quarantine, bukan digabung ke batch fiktif umum. | `UNVERIFIED_BATCH_MERGE_FORBIDDEN` |
| BR-BAT-011 | Admin hanya boleh membuat Batch kind `STANDARD`; `RETURN` dibuat return inspection dan `UNIDENTIFIED_RETURN` hanya melalui exception yang sah. | `MANUAL_BATCH_KIND_FORBIDDEN` |
| BR-BAT-012 | Product linkage dan Batch kind MUST immutable setelah Batch dibuat. | `BATCH_PRODUCT_CHANGE_FORBIDDEN` / `BATCH_KIND_CHANGE_FORBIDDEN` |
| BR-BAT-013 | Master-data mutation MUST stock-neutral; ledger append-only tetap source of truth. | `MASTER_DATA_STOCK_EFFECT_FORBIDDEN` |
| BR-BAT-014 | Batch `RETURN` di bawah Product archived tetap historis/terbaca tetapi tidak allocatable sampai Product aktif kembali. | `PRODUCT_INACTIVE_FOR_ALLOCATION` |

## 11. Saldo Awal dan Cutover

| ID | Aturan | Kode pelanggaran |
|---|---|---|
| BR-CUT-001 | Environment produksi MUST memiliki tepat satu cutover posted aktif sebagai titik awal ledger. | `INVALID_ACTIVE_CUTOVER_COUNT` |
| BR-CUT-002 | Cutover MUST memiliki timestamp dan zona waktu yang jelas. | `CUTOVER_TIMESTAMP_REQUIRED` |
| BR-CUT-003 | Saldo awal MUST dicatat per produk, batch, dan bucket fisik. | `CUTOVER_DETAIL_REQUIRED` |
| BR-CUT-004 | Kuantitas saldo awal MUST integer nol atau positif. | `INVALID_CUTOVER_QUANTITY` |
| BR-CUT-005 | Baris nol MAY disimpan pada draft, tetapi MUST NOT menghasilkan movement. | `ZERO_INITIAL_MOVEMENT` |
| BR-CUT-006 | Barang dengan batch belum terverifikasi MUST masuk quarantine dengan referensi exception. | `UNKNOWN_BATCH_NOT_QUARANTINED` |
| BR-CUT-006A | Opening Balance baru MUST menolak Product inactive, Batch archived/effectively expired, dan kind `RETURN`; `UNIDENTIFIED_RETURN` hanya sah pada `QUARANTINE` dengan identity unverified serta exception reference. | `OPENING_BALANCE_*` |
| BR-CUT-007 | Posting cutover MUST menghasilkan `INITIAL_BALANCE` untuk setiap baris positif. | `INITIAL_BALANCE_MOVEMENT_MISSING` |
| BR-CUT-008 | Posting cutover MUST atomik. | `PARTIAL_CUTOVER_POST` |
| BR-CUT-009 | Setelah posted, isi cutover MUST read-only. | `POSTED_CUTOVER_EDIT_FORBIDDEN` |
| BR-CUT-010 | Angka spreadsheet lama hanya pembanding dan MUST NOT menjadi saldo otomatis tanpa validasi fisik. | `LEGACY_BALANCE_USED_AS_TRUTH` |
| BR-CUT-011 | Selisih antara spreadsheet dan hitung fisik MUST ditampilkan, bukan ditutup dengan edit langsung. | `CUTOVER_VARIANCE_HIDDEN` |
| BR-CUT-012 | Setiap baris positif yang diposting MUST mulai sebagai `UNVERIFIED`. | `OPENING_BALANCE_VERIFIED_WITHOUT_COUNT` |
| BR-CUT-013 | Hanya first successfully posted stocktake setelah cutover dengan exact organization/product/batch/bucket scope yang MAY memverifikasi baris. | `OPENING_BALANCE_VERIFICATION_SCOPE_MISMATCH` |
| BR-CUT-014 | Zero-variance stocktake line MUST dapat memverifikasi tanpa membuat `STOCKTAKE_ADJUSTMENT`. | `ZERO_VARIANCE_VERIFICATION_MISSING` |
| BR-CUT-015 | Stok opname sebelum cutover, di luar scope, gagal, belum approved, atau belum posted MUST NOT memverifikasi. | `INVALID_OPENING_BALANCE_VERIFICATION` |
| BR-CUT-016 | Satu opening-balance line MUST memiliki paling banyak satu immutable first-verification application. | `DUPLICATE_OPENING_BALANCE_VERIFICATION` |
| BR-CUT-017 | Verification application MUST menautkan stocktake, approval version, posting, posting line, count attempt, actor/process, dan waktu. | `OPENING_BALANCE_VERIFICATION_LINK_INCOMPLETE` |
| BR-CUT-018 | Status cutover MUST diturunkan sebagai `UNVERIFIED`, `PARTIALLY_VERIFIED`, atau `VERIFIED` tanpa mengubah ledger awal. | `OPENING_BALANCE_VERIFICATION_STATUS_INVALID` |
| BR-CUT-019 | Koreksi cutover posted MUST memakai exact reversal atas product, batch, bucket, dan quantity asal tanpa FEFO atau substitusi. | `OPENING_BALANCE_REVERSAL_MISMATCH` |
| BR-CUT-020 | Original cutover, ledger, verification, dan reversal history MUST tetap immutable; replacement hanya setelah active cutover direversal. | `OPENING_BALANCE_HISTORY_MUTATED` |

## 12. Penerimaan Barang dari Maklon

| ID | Aturan | Kode pelanggaran |
|---|---|---|
| BR-RCV-001 | Penerimaan baru dimulai sebagai draft dan MUST NOT mengubah stok. | `DRAFT_RECEIPT_CHANGED_STOCK` |
| BR-RCV-002 | Penerimaan MUST memiliki tanggal terima, produk, batch, tanggal kedaluwarsa, kuantitas, actor, dan referensi sumber. | `RECEIPT_REQUIRED_FIELDS_MISSING` |
| BR-RCV-003 | Kuantitas penerimaan MUST lebih dari nol. | `RECEIPT_QUANTITY_INVALID` |
| BR-RCV-004 | Batch baru MAY dibuat dalam flow penerimaan setelah validasi keunikan dan kedaluwarsa. | `INVALID_BATCH_ON_RECEIPT` |
| BR-RCV-005 | Default tujuan penerimaan adalah `SELLABLE`; jika inspeksi belum selesai, tujuan MUST `QUARANTINE`. | `INVALID_RECEIPT_BUCKET` |
| BR-RCV-006 | Preview MUST menunjukkan dampak saldo dan batch sebelum posting. | `RECEIPT_PREVIEW_REQUIRED` |
| BR-RCV-007 | Posting penerimaan MUST membuat movement per baris dan seluruh dokumen posted secara atomik. | `PARTIAL_RECEIPT_POST` |
| BR-RCV-008 | Referensi dokumen sumber SHOULD unik dalam konteks supplier/maklon untuk membantu mendeteksi duplikasi. | `POSSIBLE_DUPLICATE_RECEIPT` |
| BR-RCV-009 | Penerimaan posted MUST NOT diedit; kesalahan menggunakan reversal. | `POSTED_RECEIPT_EDIT_FORBIDDEN` |
| BR-RCV-010 | Receipt baru hanya menerima Product aktif dan Batch milik Product tersebut, kind `STANDARD`, lifecycle `ACTIVE`, serta belum effectively expired; Batch `BLOCKED` ditolak sebagai `RECEIPT_BATCH_NOT_ACTIVE`. | `RECEIPT_*` |

## 13. Bundle

| ID | Aturan | Kode pelanggaran |
|---|---|---|
| BR-BND-001 | Bundle hanya berupa resep mapping listing ke produk satuan. | `BUNDLE_STOCK_ENTITY_FORBIDDEN` |
| BR-BND-002 | Setiap komponen resep MUST memiliki produk aktif dan quantity per bundle integer lebih dari nol. | `INVALID_BUNDLE_COMPONENT` |
| BR-BND-003 | Resep MUST memiliki minimal satu komponen. | `EMPTY_BUNDLE_RECIPE` |
| BR-BND-004 | Produk yang sama dalam satu resep SHOULD digabung menjadi satu total komponen sebelum disimpan. | `DUPLICATE_BUNDLE_COMPONENT` |
| BR-BND-005 | Pesanan bundle MUST diekspansi sebelum reservasi. | `BUNDLE_RESERVATION_NOT_EXPANDED` |
| BR-BND-006 | Snapshot resep yang digunakan MUST disimpan pada item pesanan agar perubahan resep tidak mengubah histori. | `BUNDLE_RECIPE_SNAPSHOT_MISSING` |
| BR-BND-007 | Perubahan resep hanya berlaku untuk pesanan baru setelah waktu efektif perubahan. | `BUNDLE_HISTORY_RECALCULATED` |
| BR-BND-008 | Jika listing bundle tidak memiliki mapping aktif, pesanan MUST masuk `STOCK_EXCEPTION` atau `EXCEPTION`. | `BUNDLE_MAPPING_MISSING` |

## 14. Event Marketplace dan Idempotensi

### 14.1 Event Kanonis Minimum

Setiap event kanonis MUST memiliki:

- `source`;
- `external_event_id` atau idempotency key setara;
- `external_order_id`;
- `event_type`;
- `source_status`;
- `occurred_at`;
- `received_at`;
- payload asli atau hash/referensinya;
- versi normalisasi;
- status pemrosesan.

### 14.2 Aturan Event

| ID | Aturan | Kode pelanggaran |
|---|---|---|
| BR-EVT-001 | Kombinasi identitas event sumber MUST unik. | `DUPLICATE_EVENT` |
| BR-EVT-002 | Event duplikat MUST mengembalikan hasil idempoten tanpa efek domain baru. | `DUPLICATE_EVENT_EFFECT` |
| BR-EVT-003 | Payload asli MUST disimpan atau direferensikan untuk audit dan pemrosesan ulang. | `SOURCE_PAYLOAD_MISSING` |
| BR-EVT-004 | Normalisasi MUST menjaga status sumber asli dan mapping ke status kanonis. | `SOURCE_STATUS_LOST` |
| BR-EVT-005 | Event invalid MUST disimpan sebagai `REJECTED` atau `FAILED`, bukan dibuang diam-diam. | `INVALID_EVENT_SILENTLY_DROPPED` |
| BR-EVT-006 | Event yang diproses ulang MUST mempertahankan idempotency key yang sama. | `REPROCESS_CHANGED_IDEMPOTENCY` |
| BR-EVT-007 | Pemrosesan ulang hanya boleh dilakukan role berwenang dan MUST diaudit. | `UNAUTHORIZED_EVENT_REPROCESS` |
| BR-EVT-008 | Event out-of-order MUST dievaluasi terhadap state machine; transisi ilegal ditolak atau dibuat issue. | `ILLEGAL_OUT_OF_ORDER_EVENT` |
| BR-EVT-009 | Satu event MUST memiliki status pemrosesan final yang jelas: `PROCESSED`, `DUPLICATE`, `REJECTED`, atau `FAILED`. | `EVENT_PROCESSING_STATUS_MISSING` |
| BR-EVT-010 | Kegagalan sementara MAY di-retry, tetapi retry MUST idempoten. | `NON_IDEMPOTENT_RETRY` |

## 15. Pesanan dan Status

### 15.1 Status Kanonis

`RECEIVED`, `RESERVED`, `STOCK_EXCEPTION`, `READY`, `PHYSICALLY_OUT`, `CANCELLED_PRE_SHIPMENT`, `CANCELLED_POST_SHIPMENT`, `RETURN_EXPECTED`, `RETURN_IN_PROGRESS`, `CLOSED`, dan `EXCEPTION`.

### 15.2 Aturan Pesanan

| ID | Aturan | Kode pelanggaran |
|---|---|---|
| BR-ORD-001 | Kombinasi `source + external_order_id` MUST unik. | `DUPLICATE_ORDER` |
| BR-ORD-002 | Item pesanan MUST dinormalisasi menjadi produk satuan sebelum reservasi. | `ORDER_ITEM_NOT_NORMALIZED` |
| BR-ORD-003 | Histori status MUST append-only dan MUST NOT ditimpa. | `ORDER_STATUS_HISTORY_MUTATED` |
| BR-ORD-004 | Setiap transisi MUST memiliki event pemicu, actor/proses, dan waktu. | `ORDER_TRANSITION_AUDIT_MISSING` |
| BR-ORD-005 | Transisi yang tidak tercantum dalam state machine MUST ditolak atau diarahkan ke `EXCEPTION`. | `ILLEGAL_ORDER_TRANSITION` |
| BR-ORD-006 | Pesanan MUST NOT menjadi `PHYSICALLY_OUT` tanpa movement outbound lengkap. | `PHYSICAL_OUT_WITHOUT_MOVEMENT` |
| BR-ORD-007 | Pesanan sebelum `PHYSICALLY_OUT` MUST NOT memiliki outbound final. | `PRE_SHIPMENT_OUTBOUND_FOUND` |
| BR-ORD-008 | Status sumber asli MUST tetap dapat dilihat bersama status kanonis. | `SOURCE_ORDER_STATUS_HIDDEN` |
| BR-ORD-009 | Pesanan tidak boleh ditutup jika masih memiliki reservasi, retur, atau exception aktif. | `ORDER_CLOSED_WITH_OPEN_OBLIGATION` |

### 15.3 Decision Table Status Marketplace

| Sumber | Status sumber/event | Kondisi saat ini | Efek domain |
|---|---|---|---|
| Shopee | pesanan baru/terkonfirmasi | belum ada pesanan | buat pesanan, normalisasi item, coba reservasi |
| TikTok Shop | pesanan baru/terkonfirmasi | belum ada pesanan | buat pesanan, normalisasi item, coba reservasi |
| Shopee | `SHIPPED` | reservasi valid | posting outbound FEFO, lepas reservasi, status `PHYSICALLY_OUT` |
| TikTok Shop | `IN_TRANSIT` | reservasi valid | posting outbound FEFO, lepas reservasi, status `PHYSICALLY_OUT` |
| sumber apa pun | status pra-pengiriman | sudah `PHYSICALLY_OUT` | simpan histori; jangan membalik stok; buat issue bila regresi ilegal |
| sumber apa pun | pembatalan parsial/penuh | quantity belum shipped | lepas hanya quantity reservasi yang diminta; tanpa movement fisik; status item/order mempertahankan mixed outcome |
| sumber apa pun | pembatalan parsial/penuh | quantity sudah shipped | exact linked reversal terhadap allocation dan ledger shipment asli; status `CANCELLED_POST_SHIPMENT`; tanpa FEFO ulang atau return otomatis |
| sumber apa pun | event retur | sudah outbound | buat/update proses retur; jangan tambah stok sebelum fisik diterima |

## 16. Reservasi

| ID | Aturan | Kode pelanggaran |
|---|---|---|
| BR-RSV-001 | Reservasi hanya boleh dibuat untuk produk aktif dan kebutuhan kuantitas positif. | `INVALID_RESERVATION_ITEM` |
| BR-RSV-002 | Reservasi mengurangi `AVAILABLE`, tetapi MUST NOT mengubah `ON_HAND` atau membuat movement outbound. | `RESERVATION_CHANGED_PHYSICAL_STOCK` |
| BR-RSV-003 | Reservasi MUST memiliki referensi pesanan dan item pesanan. | `ORPHAN_RESERVATION` |
| BR-RSV-004 | Total reservasi aktif per produk MUST NOT melebihi sellable. | `RESERVED_EXCEEDS_SELLABLE` |
| BR-RSV-005 | Jika available tidak cukup, reservasi MUST gagal secara utuh untuk pesanan dan status menjadi `STOCK_EXCEPTION`, kecuali strategi parsial disetujui kemudian. Default fase 1: tidak ada reservasi parsial. | `PARTIAL_RESERVATION_FORBIDDEN` |
| BR-RSV-006 | Pembatalan pra-pengiriman MUST melepaskan hanya quantity reservasi aktif yang dibatalkan per item; sisa reservasi yang tidak dibatalkan tetap aktif. | `CANCELLED_QUANTITY_RESERVATION_REMAINS` |
| BR-RSV-007 | Posting outbound MUST mengonsumsi dan menutup reservasi terkait dalam transaction yang sama. | `OUTBOUND_RESERVATION_NOT_RELEASED` |
| BR-RSV-008 | Reservasi yang telah dilepas atau dikonsumsi MUST NOT dipakai ulang. | `RESERVATION_REUSE_FORBIDDEN` |
| BR-RSV-009 | Histori pembuatan, pelepasan, dan konsumsi reservasi MUST dapat diaudit. | `RESERVATION_HISTORY_MISSING` |

## 17. FEFO dan Outbound Marketplace

### 17.1 Kelayakan Batch FEFO

Batch eligible hanya jika seluruh kondisi berikut benar:

- produk sesuai;
- status aktif;
- tidak blocked, quarantined, archived, atau expired;
- bucket `SELLABLE` memiliki available positif;
- tanggal kedaluwarsa tersedia dan belum lewat;
- tidak sedang terkunci oleh proses yang belum selesai secara konflik.

### 17.2 Urutan FEFO Resmi

1. tanggal kedaluwarsa paling dekat;
2. tanggal penerimaan pertama lebih awal;
3. ID batch sebagai tie-breaker deterministik.

### 17.3 Aturan Outbound

| ID | Aturan | Kode pelanggaran |
|---|---|---|
| BR-OUT-001 | Trigger keluar fisik Shopee adalah `SHIPPED`. | `INVALID_SHOPEE_OUTBOUND_TRIGGER` |
| BR-OUT-002 | Trigger keluar fisik TikTok Shop adalah `IN_TRANSIT`. | `INVALID_TIKTOK_OUTBOUND_TRIGGER` |
| BR-OUT-003 | Sebelum trigger tersebut, pesanan hanya reservasi dan MUST NOT mengurangi stok fisik. | `EARLY_PHYSICAL_OUTBOUND` |
| BR-OUT-004 | Operator MUST NOT memilih batch pada outbound penjualan normal. | `MANUAL_BATCH_SELECTION_FORBIDDEN` |
| BR-OUT-005 | Sistem MUST mengalokasikan batch dengan urutan FEFO resmi. | `FEFO_ORDER_VIOLATION` |
| BR-OUT-006 | Jika satu batch tidak cukup, alokasi MUST berlanjut ke batch eligible berikutnya. | `FEFO_SPLIT_INCOMPLETE` |
| BR-OUT-007 | Jumlah seluruh alokasi MUST sama dengan kebutuhan item pesanan. | `ALLOCATION_TOTAL_MISMATCH` |
| BR-OUT-008 | Setiap alokasi MUST menghasilkan movement per batch dan relasi ke item pesanan. | `ALLOCATION_MOVEMENT_MISSING` |
| BR-OUT-009 | Jika total stok eligible tidak cukup, seluruh outbound MUST gagal tanpa movement parsial. | `INSUFFICIENT_STOCK_AT_OUTBOUND` |
| BR-OUT-010 | Dua outbound konkuren MUST NOT mengalokasikan unit yang sama. | `CONCURRENT_OVERALLOCATION` |
| BR-OUT-011 | Konflik konkuren MAY di-retry terbatas; hasil retry MUST tetap idempoten. | `UNSAFE_CONCURRENCY_RETRY` |
| BR-OUT-012 | Batch expired MUST dilewati meskipun tanggal kedaluwarsanya paling dekat. | `EXPIRED_BATCH_ALLOCATED` |
| BR-OUT-013 | Alokasi yang terbentuk MUST dapat ditelusuri dari pesanan ke batch dan dari batch ke pesanan. | `ALLOCATION_TRACE_MISSING` |
| BR-OUT-014 | Pelepasan reservasi, movement outbound, alokasi batch, dan perubahan status MUST berada dalam satu transaction. | `OUTBOUND_ATOMICITY_BROKEN` |

### 17.4 Contoh FEFO

```text
Kebutuhan: 12 unit Produk A
Batch A1: available 5, expiry 2026-08-01
Batch A2: available 20, expiry 2026-09-01

Hasil wajib:
- 5 unit dari A1
- 7 unit dari A2
- dua movement outbound
- total alokasi = 12
```

## 18. Pembatalan Pesanan

| ID | Aturan | Kode pelanggaran |
|---|---|---|
| BR-ORD-010 | Pembatalan pra-pengiriman MUST melepaskan hanya quantity reservasi yang dibatalkan per item tanpa membuat stock transaction atau ledger movement. | `PRE_SHIPMENT_CANCEL_MOVEMENT_FOUND` |
| BR-ORD-011 | Pembatalan pasca-pengiriman MUST membuat exact linked reversal terhadap quantity, batch, bucket, allocation, dan ledger entry shipment asli. | `POST_SHIPMENT_CANCEL_REVERSAL_MISMATCH` |
| BR-ORD-012 | Pembatalan pasca-pengiriman MUST NOT menjalankan FEFO ulang, mengganti batch, atau mengedit/menghapus shipment asal. | `POST_SHIPMENT_CANCEL_BATCH_SUBSTITUTION` |
| BR-ORD-013 | Event atau command pembatalan duplikat MUST idempoten dan menghasilkan maksimal satu domain effect. | `DUPLICATE_CANCEL_EFFECT` |
| BR-ORD-014 | Payload berbeda dengan idempotency key yang sama MUST ditolak. | `CANCELLATION_IDEMPOTENCY_CONFLICT` |
| BR-ORD-015 | Pembatalan MUST mendukung quantity parsial per item dan menolak quantity nol, negatif, atau melebihi sisa cancellable. | `CANCELLATION_QUANTITY_INVALID` |
| BR-ORD-016 | Input dengan phase pre/post-shipment yang ambigu MUST ditolak, bukan ditebak. | `CANCELLATION_PHASE_AMBIGUOUS` |
| BR-ORD-017 | Pembatalan pasca-pengiriman MUST NOT otomatis membuat return, receipt, inspection, claim, atau inbound kedua. | `CANCELLATION_MANUFACTURED_RETURN` |
| BR-ORD-018 | Expected return dan post-shipment cancellation MUST NOT memakai quantity shipment yang sama. | `CANCELLATION_RETURN_OVERLAP` |
| BR-ORD-019 | Pesanan yang sudah `CANCELLED_PRE_SHIPMENT` MUST NOT diposting outbound untuk quantity yang telah dibatalkan. | `CANCELLED_QUANTITY_SHIPPED` |

## 19. Outbound Manual

### 19.1 Alasan Minimum

`OFFLINE_SALE`, `BONUS`, `PROMO`, `SAMPLE`, `DAMAGED_DISPOSAL`, dan `EXPIRED_DISPOSAL`.

### 19.2 Aturan

| ID | Aturan | Kode pelanggaran |
|---|---|---|
| BR-MAN-001 | Setiap outbound manual MUST memiliki alasan, kanal, waktu kejadian, produk, kuantitas, actor, dan catatan/referensi sesuai konfigurasi. | `MANUAL_OUTBOUND_FIELDS_MISSING` |
| BR-MAN-002 | Kanal default MAY `MANUAL`, tetapi alasan MUST tetap dipilih terpisah. | `MANUAL_REASON_MISSING` |
| BR-MAN-003 | Penjualan offline, bonus, promo, dan sampel MUST menggunakan FEFO otomatis. | `MANUAL_FEFO_VIOLATION` |
| BR-MAN-004 | Pemusnahan rusak MUST mengambil dari bucket `DAMAGED` pada batch yang dipilih. | `INVALID_DAMAGED_DISPOSAL_SOURCE` |
| BR-MAN-005 | Pemusnahan kedaluwarsa MUST mengambil dari batch expired dan bucket fisik yang benar. | `INVALID_EXPIRED_DISPOSAL_SOURCE` |
| BR-MAN-006 | Kuantitas pemusnahan MUST NOT melebihi saldo bucket sumber. | `DISPOSAL_EXCEEDS_BALANCE` |
| BR-MAN-007 | Preview alokasi dan dampak saldo MUST ditampilkan sebelum posting. | `MANUAL_OUTBOUND_PREVIEW_REQUIRED` |
| BR-MAN-008 | Posting outbound manual MUST atomik dan menghasilkan movement per batch. | `PARTIAL_MANUAL_OUTBOUND` |
| BR-MAN-009 | Referensi wajib dapat dikonfigurasi per alasan, misalnya nomor campaign untuk promo atau tujuan penerima untuk sampel. | `REQUIRED_REASON_REFERENCE_MISSING` |
| BR-MAN-010 | Kesalahan outbound manual posted diperbaiki melalui reversal. | `POSTED_MANUAL_OUTBOUND_EDIT_FORBIDDEN` |

## 20. Retur

### 20.1 Prinsip

Marketplace hanya memberi informasi bahwa retur terjadi. Kondisi fisik ditentukan oleh gudang setelah barang tiba dan diperiksa.

### 20.2 Aturan Retur

| ID | Aturan | Kode pelanggaran |
|---|---|---|
| BR-RET-001 | Membuat retur expected MUST NOT menambah stok. | `EXPECTED_RETURN_RESTOCKED` |
| BR-RET-002 | Retur MUST mereferensikan pesanan dan item outbound asal bila tersedia. | `RETURN_SOURCE_REFERENCE_REQUIRED` |
| BR-RET-003 | Total kuantitas retur aktif/completed MUST NOT melebihi kuantitas outbound yang dapat diretur. | `RETURN_EXCEEDS_OUTBOUND` |
| BR-RET-004 | Penerimaan fisik retur MUST hanya mencatat receipt operasional dan MUST NOT membuat transaction, ledger entry, atau perubahan projection stok. | `RETURN_RECEIPT_CREATED_STOCK` |
| BR-RET-005 | Kuantitas received MUST NOT melebihi expected, kecuali exception Admin yang diaudit. | `RETURN_RECEIVED_EXCEEDS_EXPECTED` |
| BR-RET-006 | Inspeksi hanya boleh dilakukan terhadap unit yang telah diterima dan masih pending inspection. | `INSPECTION_WITHOUT_RECEIPT` |
| BR-RET-007 | Hasil `SELLABLE` MUST membuat tepat satu inbound ke `SELLABLE` pada batch baru bertanda `RETURN`; retry identik MUST NOT menggandakan efek. | `SELLABLE_RETURN_INBOUND_INVALID` |
| BR-RET-008 | Hasil `DAMAGED` MUST dicatat untuk audit/klaim dan MUST NOT membuat transaction, ledger entry, atau perubahan projection stok kedua. | `DAMAGED_RETURN_CREATED_STOCK` |
| BR-RET-009 | Hasil `LOST` hanya boleh untuk barang yang tidak pernah diterima dan MUST NOT membuat inbound. | `LOST_RETURN_CREATED_STOCK` |
| BR-RET-010 | Batch outbound asal MUST disimpan sebagai provenance bila tersedia dan MUST NOT dipakai sebagai batch tujuan inbound retur. | `RETURN_PROVENANCE_MISSING` |
| BR-RET-011 | Jika batch asal tidak dapat diverifikasi, status provenance MUST dicatat sebagai unknown, MUST NOT direkayasa menjadi identitas batch produksi, dan hasil `SELLABLE` MUST ditolak sampai provenance terverifikasi; hasil `DAMAGED` tetap boleh dicatat tanpa movement stok. | `RETURN_PROVENANCE_FABRICATED` |
| BR-RET-012 | Total `received + lost + pending` MUST konsisten dengan kuantitas retur expected. | `RETURN_QUANTITY_RECONCILIATION_FAILED` |
| BR-RET-013 | Retur parsial MUST mempertahankan status progres, bukan langsung closed. | `PARTIAL_RETURN_CLOSED` |
| BR-RET-014 | Bukti inspeksi MAY opsional, tetapi actor, waktu, hasil, dan catatan MUST disimpan. | `RETURN_INSPECTION_AUDIT_MISSING` |
| BR-RET-015 | Retur duplikat MUST idempoten dan tidak membuat movement ganda. | `DUPLICATE_RETURN_EFFECT` |
| BR-RET-016 | Retur dari transaksi historis tetap dapat diselesaikan setelah Product diarchive; inbound sellable memakai Batch `RETURN` baru yang tetap historis/non-allocatable sampai Product direactivate. | `PRODUCT_INACTIVE_FOR_ALLOCATION` |

### 20.3 Decision Table Retur

| Kondisi | Aksi operator | Movement | Status hasil |
|---|---|---|---|
| Retur baru dilaporkan, barang belum tiba | buat expected return | tidak ada | `EXPECTED` |
| Sebagian barang tiba | terima kuantitas aktual | tidak ada; receipt operasional | `PARTIALLY_RECEIVED` |
| Seluruh barang tiba, belum diperiksa | terima fisik | tidak ada; pending inspection operasional | `RECEIVED_PENDING_INSPECTION` |
| Barang diperiksa layak jual | pilih `SELLABLE` | inbound ke batch `RETURN` baru / `SELLABLE` | completed/partial sesuai sisa |
| Barang diperiksa rusak | pilih `DAMAGED` | tidak ada; audit kondisi fisik | completed/partial sesuai sisa |
| Barang tidak pernah tiba | tetapkan `LOST` | tidak ada inbound | `LOST` dan kandidat klaim |
| Batch asal tidak terbaca | catat provenance unknown | tidak ada saat receipt; sellable ditolak sampai provenance terverifikasi, damaged tetap stock-neutral | `EXCEPTION` atau pending provenance review |

## 21. Klaim Retur Hilang

| ID | Aturan | Kode pelanggaran |
|---|---|---|
| BR-CLM-001 | Klaim hanya dibuat untuk kasus yang memenuhi kondisi lost/exception sesuai aturan sumber. | `CLAIM_WITHOUT_ELIGIBLE_CASE` |
| BR-CLM-002 | Tenggat TikTok Shop MUST dihitung 40 hari kalender dari `operations.returns.created_at` milik retur terkait. | `CLAIM_DUE_DATE_INVALID` |
| BR-CLM-003 | Sistem MUST menyimpan tanggal dasar, konfigurasi hari yang dipakai, dan due date hasil perhitungan. | `CLAIM_DUE_DATE_AUDIT_MISSING` |
| BR-CLM-004 | Perubahan konfigurasi jumlah hari MUST NOT mengubah due date klaim existing secara otomatis. | `HISTORICAL_DUE_DATE_MUTATED` |
| BR-CLM-005 | Jika tanggal dasar belum tersedia, klaim MUST berstatus exception dan due date tidak boleh ditebak. | `CLAIM_BASIS_DATE_MISSING` |
| BR-CLM-006 | Status minimal: `NOT_STARTED`, `DUE_SOON`, `SUBMITTED`, `RESOLVED`, `EXPIRED`. | `INVALID_CLAIM_STATUS` |
| BR-CLM-007 | Transisi status klaim MUST menyimpan actor, waktu, dan catatan. | `CLAIM_STATUS_AUDIT_MISSING` |
| BR-CLM-008 | Modul klaim MUST NOT menyimpan nilai kompensasi uang pada fase 1. | `CLAIM_MONEY_OUT_OF_SCOPE` |

## 22. Kedaluwarsa

| ID | Aturan | Kode pelanggaran |
|---|---|---|
| BR-EXP-001 | Sisa hari kedaluwarsa dihitung berdasarkan tanggal operasional `Asia/Jakarta`. | `EXPIRY_TIMEZONE_MISMATCH` |
| BR-EXP-002 | Batch dianggap expired setelah tanggal kedaluwarsa telah lewat pada tanggal lokal. | `EXPIRY_EFFECTIVE_DATE_MISMATCH` |
| BR-EXP-003 | Batch expired MUST NOT masuk reservasi baru atau alokasi outbound penjualan. | `EXPIRED_STOCK_USED_FOR_SALE` |
| BR-EXP-004 | Stok expired yang masih fisik MUST tetap terlihat sampai diposting sebagai disposal. | `EXPIRED_STOCK_HIDDEN` |
| BR-EXP-005 | Default ambang notifikasi adalah 90, 60, dan 30 hari serta expired. | `EXPIRY_THRESHOLD_INVALID` |
| BR-EXP-006 | Batch tanpa saldo fisik tidak perlu menghasilkan notifikasi aktif baru. | `EMPTY_BATCH_EXPIRY_NOTIFICATION` |
| BR-EXP-007 | Notifikasi untuk batch dan ambang yang sama MUST dideduplicasi. | `DUPLICATE_EXPIRY_NOTIFICATION` |
| BR-EXP-008 | Perubahan ambang hanya berlaku untuk evaluasi berikutnya dan MUST diaudit. | `EXPIRY_CONFIG_CHANGE_UNAUDITED` |

## 23. Ledger dan Posisi Stok

### 23.1 Atribut Movement Minimum

Setiap movement MUST menyimpan:

- ID unik;
- produk;
- batch;
- bucket asal dan/atau tujuan;
- kuantitas;
- tipe movement;
- alasan;
- kanal;
- referensi tipe dan ID sumber;
- waktu kejadian bisnis;
- waktu pencatatan sistem;
- actor atau proses;
- correlation/transaction ID;
- movement reversal terkait bila ada.

### 23.2 Aturan Ledger

| ID | Aturan | Kode pelanggaran |
|---|---|---|
| BR-LED-001 | Semua movement posted MUST append-only. | `LEDGER_MUTATION_FORBIDDEN` |
| BR-LED-002 | Movement MUST memiliki alasan dan kanal yang valid dari master aktif atau snapshot historis. | `MOVEMENT_REASON_CHANNEL_INVALID` |
| BR-LED-003 | Movement MUST memiliki referensi sumber yang dapat dibuka atau dijelaskan. | `MOVEMENT_SOURCE_REFERENCE_MISSING` |
| BR-LED-004 | Saldo projection/cache MAY dipakai untuk performa, tetapi MUST dapat dibangun ulang dari ledger. | `UNREBUILDABLE_BALANCE_PROJECTION` |
| BR-LED-005 | Jika projection berbeda dari ledger, ledger menjadi sumber koreksi dan issue rekonsiliasi MUST dibuat. | `LEDGER_PROJECTION_MISMATCH` |
| BR-LED-006 | Movement transfer MUST mencatat bucket asal dan tujuan yang berbeda. | `INVALID_BUCKET_TRANSFER` |
| BR-LED-007 | Movement inbound/outbound MUST memiliki tepat satu sisi eksternal dan satu bucket fisik. | `INVALID_MOVEMENT_DIRECTION` |
| BR-LED-008 | Reference ID dan movement ID MUST unik serta tidak boleh dipakai ulang. | `DUPLICATE_MOVEMENT_ID` |
| BR-LED-009 | Ledger MUST dapat difilter per produk, batch, tipe, alasan, kanal, actor, waktu, dan referensi. | `LEDGER_FILTERABILITY_REQUIRED` |
| BR-LED-010 | Drill-down dua arah antara movement dan dokumen sumber MUST tersedia. | `LEDGER_TRACEABILITY_BROKEN` |
| BR-LED-011 | Export ledger MUST read-only dan mencerminkan filter serta timestamp export. | `LEDGER_EXPORT_INCONSISTENT` |
| BR-LED-012 | Movement yang dibuat proses otomatis MUST menyimpan process identity, bukan actor palsu. | `AUTOMATION_ACTOR_MISATTRIBUTED` |

## 24. Reversal

| ID | Aturan | Kode pelanggaran |
|---|---|---|
| BR-REV-001 | Hanya Admin yang boleh membuat reversal. | `REVERSAL_NOT_AUTHORIZED` |
| BR-REV-002 | Reversal MUST mereferensikan movement/transaksi asal dan alasan koreksi. | `REVERSAL_SOURCE_REQUIRED` |
| BR-REV-003 | Movement asal MUST tetap ada dan terlihat. | `ORIGINAL_MOVEMENT_REMOVED` |
| BR-REV-004 | Dampak reversal MUST tepat kebalikan dari movement asal. | `REVERSAL_AMOUNT_MISMATCH` |
| BR-REV-005 | Satu movement MUST NOT dibalik lebih dari sisa kuantitas yang belum direversal. | `OVER_REVERSAL` |
| BR-REV-006 | Reversal yang menyebabkan saldo bucket negatif MUST ditolak. | `REVERSAL_CAUSES_NEGATIVE_STOCK` |
| BR-REV-007 | Reversal proses majemuk SHOULD dilakukan pada level dokumen/transaksi agar semua movement terkait dibalik konsisten. | `PARTIAL_DOCUMENT_REVERSAL` |
| BR-REV-008 | Reversal MUST atomik dan diaudit. | `REVERSAL_ATOMICITY_BROKEN` |
| BR-REV-009 | Setelah reversal, rekonsiliasi SHOULD dijalankan untuk entitas terdampak. | `POST_REVERSAL_RECONCILIATION_MISSING` |

## 25. Stok Opname

### 25.1 Status

`DRAFT -> COUNTING -> REVIEW -> APPROVED -> POSTED`

Cabang pembatalan: `DRAFT`, `COUNTING`, atau `REVIEW` dapat menjadi `CANCELLED`. Setelah `POSTED`, sesi tidak dapat kembali ke status sebelumnya.

### 25.2 Aturan Opname

| ID | Aturan | Kode pelanggaran |
|---|---|---|
| BR-STK-001 | Sesi opname MUST memiliki scope, waktu mulai, dan pembuat. | `STOCKTAKE_SCOPE_REQUIRED` |
| BR-STK-002 | Saat sesi dimulai, snapshot saldo MUST disimpan per produk, batch, dan bucket. | `STOCKTAKE_SNAPSHOT_MISSING` |
| BR-STK-003 | Snapshot MUST immutable setelah counting dimulai. | `STOCKTAKE_SNAPSHOT_MUTATED` |
| BR-STK-004 | Hitung fisik MUST integer nol atau positif. | `INVALID_PHYSICAL_COUNT` |
| BR-STK-005 | Baris produk/batch tidak dikenal MUST menjadi exception, bukan membuat master otomatis. | `UNKNOWN_COUNT_ITEM_AUTO_CREATED` |
| BR-STK-006 | Expected balance MUST menggunakan snapshot dan, bila operasional tetap berjalan, movement relevan setelah snapshot sampai cutoff perbandingan. | `STOCKTAKE_EXPECTED_BALANCE_INVALID` |
| BR-STK-007 | Selisih dihitung `physical_count - expected_balance`. | `STOCKTAKE_VARIANCE_FORMULA_INVALID` |
| BR-STK-008 | Setiap selisih yang akan diposting MUST memiliki alasan review. | `STOCKTAKE_VARIANCE_REASON_REQUIRED` |
| BR-STK-009 | Koreksi hanya boleh di-approve Admin. | `STOCKTAKE_APPROVAL_REQUIRED` |
| BR-STK-010 | Jika data count atau expected berubah setelah review, approval sebelumnya MUST invalid dan review diulang. | `STALE_STOCKTAKE_APPROVAL` |
| BR-STK-011 | Posting koreksi MUST membuat `STOCKTAKE_ADJUSTMENT` per baris selisih nonnol. | `STOCKTAKE_ADJUSTMENT_MISSING` |
| BR-STK-012 | Posting seluruh sesi MUST atomik. | `PARTIAL_STOCKTAKE_POST` |
| BR-STK-013 | Setelah posted, sesi dan count menjadi read-only. | `POSTED_STOCKTAKE_EDIT_FORBIDDEN` |
| BR-STK-014 | Laporan MUST menampilkan snapshot, movement setelah snapshot, expected, physical, variance, reviewer, approver, dan movement koreksi. | `STOCKTAKE_REPORT_INCOMPLETE` |
| BR-STK-015 | Baris zero variance MUST tetap memiliki count evidence dan posting line, tetapi MUST NOT membuat ledger adjustment. | `ZERO_VARIANCE_LEDGER_MOVEMENT` |
| BR-STK-016 | Verifikasi opening balance MUST menjadi audit effect terpisah dari adjustment quantity dan MUST NOT menambah movement stok. | `OPENING_BALANCE_VERIFICATION_CREATED_MOVEMENT` |

### 25.3 Decision Table Operasional Saat Opname

Karena keputusan apakah gudang berhenti beroperasi masih terbuka, implementasi MUST mendukung salah satu mode yang dipilih secara eksplisit per sesi:

| Mode | Aturan expected balance |
|---|---|
| `FROZEN_OPERATIONS` | expected = snapshot; transaksi terkait scope ditolak selama counting |
| `CONTINUOUS_OPERATIONS` | expected = snapshot + movement posted setelah snapshot sampai cutoff |

Mode tidak boleh ditentukan diam-diam. Sesi MUST menyimpan mode yang digunakan.

## 26. Rekonsiliasi Harian

| ID | Aturan | Severity default |
|---|---|---|
| BR-REC-001 | Projection saldo harus sama dengan penjumlahan ledger. | `CRITICAL` |
| BR-REC-002 | Tidak boleh ada saldo bucket atau available negatif. | `CRITICAL` |
| BR-REC-003 | Event eksternal tidak boleh diproses lebih dari sekali. | `HIGH` |
| BR-REC-004 | Total komponen bundle harus sama dengan snapshot resep item pesanan. | `HIGH` |
| BR-REC-005 | Total alokasi batch harus sama dengan quantity outbound. | `CRITICAL` |
| BR-REC-006 | Pesanan `PHYSICALLY_OUT` harus memiliki movement outbound. | `CRITICAL` |
| BR-REC-007 | Pesanan pra-pengiriman tidak boleh memiliki outbound final. | `CRITICAL` |
| BR-REC-008 | Retur sellable hanya boleh bertambah setelah receipt dan inspection. | `HIGH` |
| BR-REC-009 | Movement harus memiliki alasan, kanal, actor/proses, dan referensi valid. | `HIGH` |
| BR-REC-010 | Transisi status harus mengikuti state machine. | `HIGH` |
| BR-REC-011 | Reserved tidak boleh melebihi sellable. | `CRITICAL` |
| BR-REC-012 | Reversal harus memiliki pasangan valid dan tidak ganda. | `HIGH` |
| BR-REC-013 | Batch expired tidak boleh muncul pada alokasi penjualan. | `HIGH` |
| BR-REC-014 | Retur yang received tetapi belum inspected harus sesuai saldo quarantine. | `HIGH` |
| BR-REC-015 | Setiap run MUST menyimpan waktu, versi rule, hasil, dan durasi. | `INFO` |

### 26.1 Issue Rekonsiliasi

| ID | Aturan | Kode pelanggaran |
|---|---|---|
| BR-REC-016 | Kegagalan rule MUST membuat atau memperbarui issue dengan rule ID dan bukti. | `RECONCILIATION_ISSUE_MISSING` |
| BR-REC-017 | Issue MUST mereferensikan entitas terkait yang dapat di-drill-down. | `RECONCILIATION_ENTITY_MISSING` |
| BR-REC-018 | Menutup issue MUST menyimpan actor, waktu, catatan, dan tindakan koreksi. | `RECONCILIATION_RESOLUTION_AUDIT_MISSING` |
| BR-REC-019 | Issue berulang SHOULD diperbarui atau ditautkan, bukan membuat duplikat tanpa konteks. | `RECONCILIATION_ISSUE_SPAM` |
| BR-REC-020 | `ACCEPTED_RISK` dan `FALSE_POSITIVE` MUST memiliki alasan serta approver berwenang. | `RECONCILIATION_EXCEPTION_REASON_REQUIRED` |
| BR-REC-021 | Issue resolved yang kembali gagal MUST dibuka kembali atau dibuat ulang dengan tautan ke issue lama. | `RECURRING_ISSUE_NOT_TRACKED` |

## 27. Impor CSV

| ID | Aturan | Kode pelanggaran |
|---|---|---|
| BR-IMP-001 | File MUST divalidasi sebelum commit: tipe, ukuran, encoding, header, kolom, dan tipe data. | `IMPORT_FILE_INVALID` |
| BR-IMP-002 | Preview MUST menunjukkan baris valid, invalid, duplikat, dan konflik mapping. | `IMPORT_PREVIEW_REQUIRED` |
| BR-IMP-003 | Upload/preview MUST NOT mengubah data domain. | `IMPORT_PREVIEW_CHANGED_DATA` |
| BR-IMP-004 | Setiap baris event eksternal MUST memiliki idempotency key. | `IMPORT_IDEMPOTENCY_KEY_REQUIRED` |
| BR-IMP-005 | Mode default untuk batch transaksi saling terkait adalah all-or-nothing. | `PARTIAL_IMPORT_COMMIT_FORBIDDEN` |
| BR-IMP-006 | Commit MUST memproses data melalui pipeline domain yang sama dengan event lain. | `IMPORT_BYPASSED_DOMAIN_PIPELINE` |
| BR-IMP-007 | Baris invalid MUST NOT dianggap sukses. | `INVALID_IMPORT_ROW_COMMITTED` |
| BR-IMP-008 | Formula spreadsheet atau konten aktif MUST diperlakukan sebagai teks dan tidak dieksekusi. | `IMPORT_ACTIVE_CONTENT_FORBIDDEN` |
| BR-IMP-009 | Histori impor MUST menyimpan actor, nama/identitas file, hash, waktu, tipe, status, dan ringkasan. | `IMPORT_HISTORY_INCOMPLETE` |
| BR-IMP-010 | Re-upload file yang sama MUST dideteksi; efek transaksi tetap idempoten. | `DUPLICATE_IMPORT_EFFECT` |
| BR-IMP-011 | Laporan kesalahan MUST mencantumkan nomor baris, field, kode, dan pesan perbaikan. | `IMPORT_ERROR_REPORT_INCOMPLETE` |

## 28. Simulator Marketplace

| ID | Aturan | Kode pelanggaran |
|---|---|---|
| BR-SIM-001 | Simulator hanya tersedia pada environment demo atau role Admin yang diberi izin eksplisit. | `SIMULATOR_ACCESS_FORBIDDEN` |
| BR-SIM-002 | Setiap aksi simulator MUST membuat event kanonis. | `SIMULATOR_EVENT_NOT_CANONICAL` |
| BR-SIM-003 | Simulator MUST NOT menulis langsung ke saldo, reservasi, ledger, atau status akhir. | `SIMULATOR_DIRECT_WRITE_FORBIDDEN` |
| BR-SIM-004 | Rule idempotensi dan state transition MUST tetap berlaku pada simulator. | `SIMULATOR_RULE_BYPASS` |
| BR-SIM-005 | Skenario deterministik MUST menghasilkan input dan outcome yang dapat diulang dari seed yang sama. | `SIMULATOR_NONDETERMINISTIC_SCENARIO` |
| BR-SIM-006 | Data demo MUST dapat dibedakan dari data produksi. | `DEMO_PRODUCTION_DATA_MIXED` |
| BR-SIM-007 | Tombol event duplikat MUST membuktikan tidak adanya movement ganda. | `SIMULATED_DUPLICATE_CREATED_EFFECT` |

## 29. Notifikasi

| ID | Aturan | Kode pelanggaran |
|---|---|---|
| BR-NTF-001 | Notifikasi hanya memberi tahu kondisi; notifikasi MUST NOT mengubah status atau stok. | `NOTIFICATION_CHANGED_DOMAIN_STATE` |
| BR-NTF-002 | Notifikasi MUST memiliki tipe, entitas, severity, waktu dibuat, dan status baca. | `NOTIFICATION_FIELDS_MISSING` |
| BR-NTF-003 | Notifikasi untuk kondisi dan entitas yang sama MUST dideduplicasi dalam jendela aturan yang sama. | `DUPLICATE_NOTIFICATION` |
| BR-NTF-004 | Menandai dibaca hanya mengubah status baca, bukan menyelesaikan issue sumber. | `READ_NOTIFICATION_RESOLVED_SOURCE` |
| BR-NTF-005 | Notifikasi kedaluwarsa dan klaim MUST mengarah ke detail batch/klaim terkait. | `NOTIFICATION_TARGET_MISSING` |
| BR-NTF-006 | Notifikasi eksternal seperti email berada di luar Must fase 1; pusat notifikasi in-app tetap wajib. | `IN_APP_NOTIFICATION_REQUIRED` |

## 30. Audit Trail

| ID | Aturan | Kode pelanggaran |
|---|---|---|
| BR-AUD-001 | Audit event MUST dibuat untuk login kritis, perubahan role, perubahan konfigurasi, posting, approval, reversal, reprocess, dan status exception. | `AUDIT_EVENT_MISSING` |
| BR-AUD-002 | Audit event MUST menyimpan actor/proses, aksi, entitas, ID entitas, waktu, dan correlation ID. | `AUDIT_FIELDS_MISSING` |
| BR-AUD-003 | Perubahan data konfigurasi/master MUST menyimpan nilai sebelum dan sesudah yang relevan. | `AUDIT_BEFORE_AFTER_MISSING` |
| BR-AUD-004 | Audit trail MUST append-only bagi pengguna aplikasi. | `AUDIT_MUTATION_FORBIDDEN` |
| BR-AUD-005 | Secret, token, password, atau payload sensitif MUST NOT ditulis ke audit/log. | `SENSITIVE_DATA_IN_AUDIT` |
| BR-AUD-006 | Tindakan otomatis MUST ditandai sebagai process/system actor. | `SYSTEM_ACTION_UNATTRIBUTED` |
| BR-AUD-007 | Audit event MUST dapat dicari berdasarkan actor, aksi, entitas, waktu, dan correlation ID. | `AUDIT_SEARCHABILITY_REQUIRED` |
| BR-AUD-008 | Kegagalan transaksi SHOULD menyimpan audit/error event tanpa mengklaim transaksi berhasil. | `FAILED_TRANSACTION_AUDIT_INCORRECT` |

## 31. Waktu, Kalender, dan Urutan Kejadian

| ID | Aturan | Kode pelanggaran |
|---|---|---|
| BR-TIM-001 | Waktu sistem MUST disimpan sebagai timestamp berzona atau UTC yang dapat dikonversi. | `TIMESTAMP_TIMEZONE_MISSING` |
| BR-TIM-002 | Tampilan operasional dan aturan kalender MUST menggunakan `Asia/Jakarta`. | `OPERATIONAL_TIMEZONE_MISMATCH` |
| BR-TIM-003 | `occurred_at` dan `recorded_at` MUST disimpan terpisah bila berbeda. | `BUSINESS_SYSTEM_TIME_NOT_SEPARATED` |
| BR-TIM-004 | Urutan histori menggunakan occurred time dengan recorded time dan ID sebagai tie-breaker deterministik. | `NONDETERMINISTIC_EVENT_ORDER` |
| BR-TIM-005 | Due date klaim dihitung dalam hari kalender, bukan jam kerja, kecuali keputusan bisnis berubah. | `CLAIM_CALENDAR_RULE_MISMATCH` |
| BR-TIM-006 | Perhitungan expired menggunakan tanggal lokal, bukan sekadar selisih jam UTC. | `EXPIRY_DATE_BOUNDARY_ERROR` |
| BR-TIM-007 | Backdated transaction hanya boleh dilakukan role berwenang, wajib alasan, dan MUST tetap mencatat recorded time aktual. | `UNAUTHORIZED_BACKDATED_TRANSACTION` |

## 32. State Machine Ringkas

### 32.1 Pesanan

```text
RECEIVED
  -> RESERVED -> READY -> PHYSICALLY_OUT
  -> STOCK_EXCEPTION
  -> EXCEPTION

RESERVED / READY
  -> CANCELLED_PRE_SHIPMENT

PHYSICALLY_OUT
  -> CANCELLED_POST_SHIPMENT
  -> RETURN_EXPECTED
  -> RETURN_IN_PROGRESS
  -> CLOSED
```

Transisi langsung dari `RECEIVED` ke `PHYSICALLY_OUT` hanya boleh jika normalisasi, reservasi, validasi stok, FEFO, movement, dan audit tetap dijalankan atomik. Implementasi sebaiknya tetap merekam tahapan antara agar jejak jelas.

### 32.2 Retur

```text
EXPECTED
  -> PARTIALLY_RECEIVED
  -> RECEIVED_PENDING_INSPECTION
  -> PARTIALLY_INSPECTED
  -> COMPLETED_SELLABLE | COMPLETED_DAMAGED | COMPLETED_MIXED
  -> CLOSED

EXPECTED -> LOST
any active state -> EXCEPTION
```

### 32.3 Klaim

```text
NOT_STARTED -> DUE_SOON -> SUBMITTED -> RESOLVED
NOT_STARTED / DUE_SOON -> EXPIRED
```

### 32.4 Opname

```text
DRAFT -> COUNTING -> REVIEW -> APPROVED -> POSTED
DRAFT / COUNTING / REVIEW -> CANCELLED
```

### 32.5 Issue Rekonsiliasi

```text
OPEN -> INVESTIGATING -> RESOLVED
OPEN / INVESTIGATING -> ACCEPTED_RISK | FALSE_POSITIVE
RESOLVED -> OPEN  (jika rule gagal kembali)
```

## 33. Matriks Keputusan Utama

### 33.1 Apakah Stok Berubah?

| Kejadian | Reserved berubah | On hand berubah | Movement fisik |
|---|:---:|:---:|:---:|
| Pesanan baru berhasil reservasi | Ya | Tidak | Tidak |
| Pesanan batal sebelum keluar | Ya, dilepas | Tidak | Tidak |
| Shopee `SHIPPED` | Ya, dikonsumsi | Ya, berkurang | Ya |
| TikTok `IN_TRANSIT` | Ya, dikonsumsi | Ya, berkurang | Ya |
| Batal setelah keluar | Tidak | Ya, bertambah sesuai quantity reversal | Exact reversal terhadap outbound shipment asli |
| Retur expected | Tidak | Tidak | Tidak |
| Retur tiba | Tidak | Tidak | Tidak; receipt operasional |
| Retur sellable setelah inspeksi | Tidak | Ya, bertambah | Inbound ke batch `RETURN` baru |
| Retur damaged setelah inspeksi | Tidak | Tidak | Tidak; audit kondisi |
| Retur lost | Tidak | Tidak | Tidak |
| Bonus/promo/sampel | Tidak | Ya, berkurang | Ya |
| Hitung fisik draft | Tidak | Tidak | Tidak |
| Adjustment opname posted | Tidak | Ya | Ya |

### 33.2 Alasan dan Kanal

| Skenario | Alasan | Kanal |
|---|---|---|
| Penjualan Shopee | `SALE` | `SHOPEE` |
| Penjualan TikTok | `SALE` | `TIKTOK_SHOP` |
| Penjualan offline | `OFFLINE_SALE` | `MANUAL` |
| Bonus | `BONUS` | `MANUAL` |
| Promo | `PROMO` | `MANUAL` |
| Sampel | `SAMPLE` | `MANUAL` |
| Retur layak jual | `RETURN_SELLABLE` | kanal pesanan asal atau `MANUAL` sesuai sumber |
| Retur rusak | `RETURN_DAMAGED` | kanal pesanan asal atau `MANUAL` sesuai sumber |
| Koreksi opname | `STOCKTAKE_ADJUSTMENT` | `STOCKTAKE` |

## 34. Kode Kesalahan Bisnis untuk UI dan API

Kode berikut adalah kontrak semantik; teks UI dapat dilokalkan.

| Kode | HTTP yang disarankan | Pesan operator yang disarankan |
|---|---:|---|
| `INSUFFICIENT_STOCK_AT_OUTBOUND` | 409 | Stok tersedia tidak cukup untuk memproses pengeluaran. |
| `DUPLICATE_EVENT` | 200/409 sesuai endpoint | Kejadian ini sudah pernah diproses dan tidak dibuat ulang. |
| `ILLEGAL_ORDER_TRANSITION` | 409 | Status pesanan tidak dapat dipindahkan dari kondisi saat ini. |
| `BATCH_NOT_ALLOCATABLE` | 422 | Batch tidak dapat digunakan karena diblokir, karantina, arsip, atau kedaluwarsa. |
| `EXPIRED_BATCH_ALLOCATED` | 409 | Batch kedaluwarsa tidak boleh dipakai untuk penjualan. |
| `RETURN_EXCEEDS_OUTBOUND` | 422 | Jumlah retur melebihi jumlah yang pernah dikirim. |
| `INSPECTION_WITHOUT_RECEIPT` | 409 | Barang belum diterima secara fisik sehingga belum dapat diinspeksi. |
| `POSTED_MOVEMENT_IMMUTABLE` | 409 | Transaksi yang sudah diposting tidak dapat diedit; gunakan reversal. |
| `STALE_STOCKTAKE_APPROVAL` | 409 | Data opname berubah dan harus ditinjau ulang sebelum disetujui. |
| `REVERSAL_CAUSES_NEGATIVE_STOCK` | 409 | Reversal ditolak karena akan membuat saldo negatif. |
| `UNAUTHORIZED` | 403 | Anda tidak memiliki hak untuk melakukan tindakan ini. |
| `VALIDATION_ERROR` | 422 | Periksa kembali data yang wajib atau tidak valid. |

Pesan error MUST menyebut entitas dan nilai relevan bila aman, misalnya SKU, kebutuhan, available, atau nomor baris impor. Stack trace dan detail database tidak boleh ditampilkan kepada operator.

## 35. Penegakan Aturan per Lapisan

| Lapisan | Tanggung jawab |
|---|---|
| UI | input terarah, preview, konfirmasi, pesan bisnis, pencegahan double-submit |
| Route Handler / server action | autentikasi, otorisasi, validasi request, pemanggilan domain service |
| Domain service / database function | state transition, FEFO, atomisitas, idempotensi, movement, audit |
| PostgreSQL constraint/index | keunikan, foreign key, not-null, integer/nonnegative, invariant lokal |
| PostgreSQL transaction/locking | proteksi concurrent allocation dan all-or-nothing |
| Supabase RLS/grants | pembatasan read/write per role dan defense in depth |
| Reconciliation job | invariant lintas tabel dan deteksi drift/projection mismatch |
| Automated test | bukti aturan tetap berlaku setelah perubahan |

Aturan kritis tidak boleh hanya berada di UI. Operasi stok sebaiknya dieksekusi melalui database function atau domain transaction terkontrol agar movement, saldo, status, dan audit tidak dapat terpisah. Untuk konflik concurrent allocation, implementasi dapat menggunakan row-level locking, isolation yang sesuai, atau mekanisme setara, selama acceptance test membuktikan tidak terjadi overallocation.

## 36. Skenario Uji Aturan Bisnis

| Test ID | Rule utama | Given / When / Then ringkas |
|---|---|---|
| BR-TST-001 | BR-INV-001 | Semua endpoint mutasi stok menghasilkan movement atau gagal. |
| BR-TST-002 | BR-RSV-002 | Pesanan 10 unit: on hand tetap, available turun 10. |
| BR-TST-003 | BR-OUT-005 | FEFO memilih expiry terdekat yang masih valid. |
| BR-TST-004 | BR-OUT-006 | Kebutuhan melebihi satu batch dibagi berurutan. |
| BR-TST-005 | BR-OUT-009 | Stok tidak cukup: tidak ada movement/status parsial. |
| BR-TST-006 | BR-OUT-010 | Dua outbound bersamaan: maksimal satu memakai unit terakhir. |
| BR-TST-007 | BR-EVT-002 | Event sama dua kali: efek domain hanya sekali. |
| BR-TST-008 | BR-ORD-010/015 | Batal parsial sebelum keluar hanya melepas quantity reservasi terkait tanpa ledger. |
| BR-TST-009 | BR-ORD-011/012/017/018 | Batal setelah keluar membuat exact linked reversal shipment asli, tidak menjalankan FEFO ulang, tidak membuat return otomatis, dan tidak overlap dengan expected return. |
| BR-TST-010 | BR-RET-004 | Retur tiba menambah received/pending inspection tanpa movement stok. |
| BR-TST-011 | BR-RET-007 | Inspeksi sellable membuat satu inbound ke batch `RETURN` baru dan retry identik tidak menggandakan efek. |
| BR-TST-012 | BR-RET-008/009 | Damaged dan lost tidak membuat movement stok kedua. |
| BR-TST-013 | BR-BND-006 | Perubahan resep tidak mengubah pesanan lama. |
| BR-TST-014 | BR-STK-011 | Selisih opname membuat adjustment dan tidak mengedit ledger lama. |
| BR-TST-015 | BR-REV-003 | Reversal mempertahankan movement asal. |
| BR-TST-016 | BR-REC-006 | Pesanan physically out tanpa movement membuat issue critical. |
| BR-TST-017 | BR-EXP-003 | Batch expired tidak dapat dialokasikan. |
| BR-TST-018 | BR-IMP-003 | Preview CSV tidak mengubah data. |
| BR-TST-019 | BR-ACL-004 | Operator tidak dapat approve opname atau reversal. |
| BR-TST-020 | BR-LED-004 | Projection dapat dihapus dan dibangun ulang sama dari ledger. |

## 37. Traceability ke Product Requirements

| Area business rules | Requirement utama |
|---|---|
| Invariant, balance, ledger | LED-001 sampai LED-009, NFR-001 sampai NFR-003 |
| Otorisasi | AUTH-001 sampai AUTH-004, NFR-004 sampai NFR-006 |
| Produk dan batch | PRD-001 sampai BAT-004 |
| Cutover | CUT-001 sampai CUT-004 |
| Penerimaan | RCV-001 sampai RCV-005 |
| Bundle | BND-001 sampai BND-004 |
| Event/idempotensi | EVT-001 sampai EVT-005 |
| Pesanan/reservasi | ORD-001 sampai ORD-006, Bagian 17 PRD |
| FEFO/outbound | OUT-001 sampai OUT-006 |
| Outbound manual | MAN-001 sampai MAN-007 |
| Retur/klaim | RET-001 sampai CLM-004, Bagian 21 PRD |
| Kedaluwarsa | EXP-001 sampai EXP-005 |
| Opname | STK-001 sampai STK-010 |
| Rekonsiliasi | REC-001 sampai REC-008 |
| Simulator | SIM-001 sampai SIM-004 |
| Impor | IMP-001 sampai IMP-007 |
| Audit/UX/NFR | AUD-001 sampai AUD-005, UX, NFR |

## 38. Keputusan yang Masih Terbuka

Keputusan retur berikut sudah final berdasarkan Phase 2:

- deadline klaim TikTok dihitung 40 hari kalender dari `operations.returns.created_at`;
- receipt fisik stock-neutral;
- sellable membuat inbound ke batch baru bertanda `RETURN`;
- damaged dan lost tidak membuat movement stok kedua;
- batch outbound asal adalah provenance, bukan batch tujuan.

Aturan berikut masih terbuka:

| ID | Keputusan terbuka | Aturan aman sementara |
|---|---|---|
| OQ-03 | Batas adjustment yang perlu dua approver | minimal satu Admin; workflow dua approver dibuat configurable |
| OQ-05 | Format CSV nyata Shopee/TikTok | gunakan adapter mapping per versi template |
| OQ-06 | Apakah operasi berhenti saat opname | sesi wajib memilih `FROZEN_OPERATIONS` atau `CONTINUOUS_OPERATIONS` |
| OQ-07 | Batas ukuran file impor | konfigurasi environment; tolak sebelum parsing bila melewati batas |
| OQ-08 | Hak operator untuk reprocess event | default: Admin saja |
| OQ-09 | Kebutuhan rak/bin | tidak menjadi dimensi saldo fase 1 |
| OQ-10 | Toleransi selisih kritis per produk | severity default berdasarkan invariant; threshold produk dibuat configurable kemudian |

## 39. Change Control

Perubahan rule MUST mengikuti langkah berikut:

1. buat usulan dengan rule ID terdampak;
2. jelaskan alasan bisnis dan contoh kasus;
3. identifikasi dampak pada saldo historis, migration, API, UI, dan test;
4. dapatkan persetujuan Product/klien untuk perubahan bisnis;
5. naikkan versi dokumen;
6. perbarui PRD, schema/architecture, dan test terkait;
7. jika berlaku retrospektif, sediakan migration atau reconciliation plan;
8. catat tanggal efektif agar transaksi lama tidak ditafsirkan ulang tanpa dasar.

Perubahan trigger outbound, rumus saldo, FEFO, hasil retur, atau status machine dianggap **breaking business change** dan wajib mendapat review khusus.

## 40. Release Gate Business Rules

Fase 1 tidak boleh dirilis apabila:

- ada mutasi stok yang tidak membuat ledger;
- movement posted masih dapat diedit/dihapus;
- event duplikat dapat membuat efek ganda;
- concurrent allocation dapat menghasilkan saldo negatif atau overallocation;
- FEFO dapat memakai batch expired atau blocked;
- pembatalan pra-pengiriman membuat movement fisik;
- pembatalan pasca-pengiriman melakukan generic restock, FEFO ulang, batch substitution, atau movement yang tidak tertaut ke shipment asli;
- retur dapat masuk sellable tanpa penerimaan dan inspeksi;
- stocktake adjustment dapat diposting tanpa approval;
- reversal menghapus histori;
- simulator atau impor melewati pipeline domain;
- RLS/otorisasi server belum diuji;
- ledger dan balance projection tidak dapat direkonsiliasi;
- BR-TST-001 sampai BR-TST-020 belum lulus.

## 41. Rujukan Implementasi Resmi

Rujukan teknis berikut mendukung cara penegakan rule, bukan menggantikan keputusan bisnis klien:

1. PostgreSQL Documentation, *Transaction Isolation*.
2. PostgreSQL Documentation, *Explicit Locking*.
3. PostgreSQL Documentation, *Constraints* dan *Concurrency Control*.
4. Supabase Documentation, *Row Level Security*.
5. Supabase Documentation, *Database Functions* dan *Securing Your API*.
6. Next.js Documentation, *Route Handlers*.

## 42. Sumber Proyek

- `stok-management-system.pdf` sebagai brief klien utama.
- `01-project-brief.md` sebagai ringkasan arah dan batas proyek.
- `02-product-requirements.md` sebagai katalog requirement fase 1.

---

**Dokumen berikutnya yang disarankan:** `04-domain-model.md`, untuk menerjemahkan aturan ini menjadi entitas, aggregate, value object, event, relasi, dan lifecycle domain tanpa mengunci detail schema terlalu dini.

---

## Aturan Implementasi Marketplace Listing Versioned

Aturan berikut telah diterapkan dan menjadi penjelas authoritative bagi contoh lama:

1. Bundle bukan stock keeping entity. Bundle tidak mempunyai stok, batch, reservation, allocation, transaction, ledger entry, atau projection.
2. Listing dinormalisasi sebelum reservasi. Input adapter adalah external listing identity dan listing quantity, bukan internal product UUID.
3. Mapping dipilih berdasarkan organisasi, channel, external listing code, dan waktu event dengan effective range `[effective_from, effective_to)`.
4. Activated atau used version immutable. Perubahan komponen dilakukan melalui draft version baru.
5. Order menyimpan source listing, mapping version, mapping fingerprint, recipe/component identity, dan expanded product snapshot yang digunakan saat ingestion.
6. Quantity komponen dihitung dengan integer arithmetic: `listing_quantity × component_quantity`.
7. Seluruh komponen satu event diproses atomic. Satu mapping, komponen, atau stok yang invalid menggagalkan seluruh event.
8. FEFO, partial cancellation, exact post-shipment reversal, expected return, dan partial return beroperasi per canonical product component.
9. Replay identik tidak menggandakan effect; identity sama dengan payload berbeda adalah conflict.
10. Lifecycle create, save, preview, activate, retire, dan archive listing bersifat stock-neutral.
