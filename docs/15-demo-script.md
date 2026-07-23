<!--
File: 15-demo-script.md
Project: Sistem Rekonsiliasi Stok
Status: Phase 2 synced live-demo contract
Version: 1.1.0
Last updated: 2026-07-23
Language: id-ID
Timezone: Asia/Jakarta
Application role model: ADMIN only
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
  - 10-fefo-batch-allocation.md
  - 11-stock-opname-flow.md
  - 12-notification-rules.md
  - 13-security-and-rls.md
  - 14-testing-scenarios.md
-->

# Demo Script: Sistem Rekonsiliasi Stok

```text
Hanya ada satu user role aplikasi: ADMIN.
```

## 1. Tujuan Dokumen

Dokumen ini adalah runbook resmi untuk mendemonstrasikan Sistem Rekonsiliasi Stok fase 1 secara live.

Demo harus membuktikan bahwa sistem memahami akar masalah klien:

```text
catatan stok hampir tidak pernah sama dengan barang fisik
dan tidak ada cerita yang menjelaskan selisihnya
```

Karena itu, demo tidak boleh berhenti pada:

- login;
- dashboard;
- CRUD produk;
- tabel stok;
- tampilan yang terlihat rapi;
- tombol simulator yang langsung mengubah saldo;
- narasi “sistem sudah terintegrasi” tanpa bukti.

Demo harus memperlihatkan perjalanan barang dan data secara utuh:

```text
barang masuk
-> tersedia
-> direservasi
-> keluar secara fisik
-> dialokasikan ke batch
-> dapat batal
-> dapat diretur
-> dapat rusak atau hilang
-> dihitung saat opname
-> direkonsiliasi
-> dijelaskan melalui ledger
```

> **Janji demo:** setiap angka stok yang berubah dapat dibuka sampai terlihat sumber, batch, alasan, kanal, waktu, dan actor yang membentuknya.

Submission harus berupa aplikasi live yang dapat langsung dicoba. Dokumen ini tidak menggantikan aplikasi live, video, test suite, atau dokumentasi teknis. Dokumen ini memastikan demo hidup tidak berubah menjadi improvisasi panik yang mengandalkan keberuntungan Wi-Fi.

---

## 2. Prioritas yang Harus Dibuktikan

Urutan penilaian source project:

1. logika stok benar dan selisih dapat ditelusuri;
2. fitur sesuai cakupan;
3. mudah digunakan Admin gudang;
4. kualitas teknis dan deployment stabil.

Urutan demo mengikuti penilaian tersebut.

### 2.1 Alokasi Waktu

| Area | Proporsi |
|---|---:|
| Logika stok dan traceability | 55% |
| Kelengkapan fitur | 20% |
| Kemudahan penggunaan | 15% |
| Kualitas teknis | 10% |

### 2.2 Hal yang Tidak Perlu Mendominasi

- animasi;
- landing page;
- pergantian tema;
- penjelasan folder proyek;
- daftar library;
- pembacaan seluruh dashboard;
- diagram arsitektur sebelum masalah bisnis terbukti.

Teknologi dijelaskan saat mendukung bukti, bukan sebagai parade nama paket.

---

## 3. Sasaran Demo

| ID | Sasaran |
|---|---|
| `DEM-GOAL-001` | Menjelaskan masalah stok dalam waktu kurang dari 60 detik. |
| `DEM-GOAL-002` | Menunjukkan bahwa saldo berasal dari ledger. |
| `DEM-GOAL-003` | Menunjukkan perbedaan reservation dan physical outbound. |
| `DEM-GOAL-004` | Membuktikan trigger Shopee `SHIPPED`. |
| `DEM-GOAL-005` | Membuktikan trigger TikTok `IN_TRANSIT`. |
| `DEM-GOAL-006` | Membuktikan FEFO otomatis tanpa pemilihan batch oleh Admin. |
| `DEM-GOAL-007` | Membuktikan pembatalan sebelum dan sesudah outbound berbeda. |
| `DEM-GOAL-008` | Membuktikan alasan dan kanal disimpan terpisah. |
| `DEM-GOAL-009` | Membuktikan bundle dipecah menjadi produk satuan. |
| `DEM-GOAL-010` | Membuktikan retur expected tidak otomatis menambah stok. |
| `DEM-GOAL-011` | Membuktikan receipt retur hanya menambah pending inspection dan tetap stock-neutral. |
| `DEM-GOAL-012` | Membuktikan sellable membuat inbound ke batch `RETURN` baru, sedangkan damaged hanya dicatat untuk audit/klaim. |
| `DEM-GOAL-013` | Membuktikan lost return dan claim tidak mengubah stok. |
| `DEM-GOAL-014` | Membuktikan duplicate event tidak menggandakan movement. |
| `DEM-GOAL-015` | Membuktikan stok opname memakai snapshot dan adjustment ledger. |
| `DEM-GOAL-016` | Membuktikan rekonsiliasi menjelaskan sumber selisih. |
| `DEM-GOAL-017` | Menunjukkan notifikasi expiry dan claim deadline. |
| `DEM-GOAL-018` | Menunjukkan mobile usability minimal satu flow. |
| `DEM-GOAL-019` | Menunjukkan aplikasi live, build production, dan data demo terisolasi. |
| `DEM-GOAL-020` | Menutup demo dengan saldo akhir yang dapat dihitung ulang. |

---

## 4. Prinsip Demo

### 4.1 Show the Effect

Setiap tindakan yang mengubah stok harus diikuti bukti:

1. perubahan posisi stok;
2. transaction;
3. ledger entry;
4. source;
5. audit atau drill-down.

### 4.2 Jelaskan Sebelum Klik

Presenter menyebut:

- yang diharapkan;
- yang tidak boleh terjadi.

Baru setelah itu Admin menjalankan tindakan.

Contoh:

```text
“Pesanan baru ini hanya membuat reservasi.
Jumlah fisik sellable tidak boleh berkurang
dan belum boleh ada ledger outbound.”
```

Lalu hasil diperiksa.

### 4.3 Gunakan Angka Kecil dan Dapat Dihitung

Angka demo harus:

- cukup kecil untuk dihitung penonton;
- cukup beragam untuk membuktikan split batch;
- tidak berubah tanpa alasan;
- tidak bergantung random tanpa seed.

### 4.4 Jangan Menyembunyikan Error

Scenario yang sengaja ditolak harus ditampilkan sebagai keberhasilan aturan.

Contoh:

```text
duplicate event -> DUPLICATE
return quantity berlebih -> REJECTED
```

Error yang benar lebih meyakinkan daripada aplikasi yang menerima semua hal seperti petugas gerbang yang sudah menyerah pada hidup.

### 4.5 Jangan Mengedit Database Saat Demo

Dilarang:

- membuka SQL editor untuk memperbaiki saldo;
- update projection manual;
- delete ledger;
- mengubah status secara langsung;
- membuat batch langsung di database;
- membersihkan issue dengan query;
- mengubah clock production.

Semua tindakan memakai UI atau prosedur resmi.

### 4.6 Data Demo Harus Jelas

Banner:

```text
DEMO MODE
```

Data memiliki:

```text
is_demo_data = true
simulation_run_id
organization demo terpisah
```

### 4.7 Satu Akun Tidak Berarti Akun Bersama

Aplikasi hanya memiliki role:

```text
ADMIN
```

Tetapi presenter memakai akun Admin individual.

---

## 5. Format Demo yang Direkomendasikan

### 5.1 Demo Utama

```text
Durasi: 18 menit
Q&A: 7–12 menit
```

### 5.2 Demo Ringkas

```text
Durasi: 8 menit
```

Dipakai bila waktu dipotong.

### 5.3 Technical Deep Dive

```text
Durasi tambahan: 10–20 menit
```

Hanya bila reviewer meminta.

### 5.4 Urutan Utama

```text
Problem
-> Baseline
-> Inbound
-> Reservation
-> FEFO Outbound
-> Cancellation
-> Manual Movement
-> Bundle
-> Return
-> Lost Claim
-> Idempotency
-> Stocktake
-> Reconciliation
-> Notifications
-> Closing Proof
```

---

# PART A — PERAN, LINGKUNGAN, DAN PERSIAPAN

## 6. Peran Tim Demo

Peran presentasi bukan role aplikasi.

| Peran | Tanggung Jawab |
|---|---|
| Presenter | Menjelaskan masalah, aturan, dan hasil. |
| Demo Operator | Menjalankan UI memakai akun Admin individual. |
| Technical Observer | Mengawasi health, waktu, dan fallback tanpa mengubah data diam-diam. |
| Timekeeper | Memberi sinyal waktu secara privat. |

Satu orang boleh menjalankan beberapa peran.

### 6.1 Aturan Komunikasi

- Presenter tidak berbicara saat operator sedang mencari menu tanpa tujuan.
- Operator tidak melakukan tindakan sebelum presenter menyebut expected effect.
- Technical observer tidak memotong kecuali ada risiko demo rusak.
- Timekeeper memberi sinyal pada menit 5, 10, 15, dan 17.

---

## 7. Environment Demo

Recommended:

```text
Environment: DEMO atau PREVIEW
Organization: ORG_DEMO
Database: terpisah dari production
Simulator: enabled untuk ORG_DEMO
Data: synthetic
Timezone: Asia/Jakarta
Build: production build
```

### 7.1 Environment Variables

```text
APP_ENV=demo
NEXT_PUBLIC_APP_MODE=DEMO
MARKETPLACE_SIMULATOR_ENABLED=true
MARKETPLACE_SIMULATOR_ALLOW_COMMIT=true
MARKETPLACE_SIMULATOR_DEMO_ORG_ID=<ORG_DEMO_UUID>
MARKETPLACE_SIMULATOR_MAX_EVENTS_PER_RUN=50
```

Tidak boleh ada:

```text
production service key pada browser
production customer data
production reset endpoint
```

### 7.2 Banner

Banner wajib terlihat pada seluruh halaman utama:

```text
DEMO MODE · Data sintetis · Organisasi demo terisolasi
```

---

## 8. Demo Clock

Untuk hasil deterministik, environment demo dapat memakai clock fixture pada rule/scenario:

```text
DEMO_NOW = 2026-07-15T10:00:00+07:00
```

Clock fixture:

- hanya aktif pada demo/test;
- tidak mengubah clock server production;
- disimpan pada simulator run;
- terlihat sebagai data demo;
- dipakai untuk threshold expiry dan claim.

Jika clock fixture tidak tersedia, seed menggunakan tanggal relatif terhadap waktu demo.

---

## 9. Golden Demo Data

### 9.1 Organisasi dan User

```text
Organization: GlowLab Demo
Admin: demo.admin@glowlab.invalid
Display name: Demo Admin
```

Alamat `.invalid` dipakai agar tidak menyerupai akun pelanggan nyata.

### 9.2 Produk

| SKU | Nama | Peran Demo |
|---|---|---|
| `SER-NIA-30` | Serum Niacinamide 30 ml | FEFO, retur, claim, opname |
| `CLN-GEN-100` | Gentle Cleanser 100 ml | Bundle |
| `TNR-HYD-100` | Hydrating Toner 100 ml | Produk pembanding |
| `BND-GLOW-01` | Glow Starter Bundle | Listing bundle, bukan stok |

### 9.3 Batch Awal

Demo date:

```text
2026-07-15
```

| Produk | Batch | Expiry | Bucket | Qty |
|---|---|---:|---|---:|
| Serum | `SER-2608-A` | 2026-08-01 | SELLABLE | 5 |
| Serum | `SER-2612-B` | 2026-12-31 | SELLABLE | 20 |
| Cleanser | `CLN-2611-A` | 2026-11-30 | SELLABLE | 15 |
| Toner | `TNR-2610-A` | 2026-10-31 | SELLABLE | 12 |

Total awal:

```text
Serum sellable = 25
Cleanser sellable = 15
Toner sellable = 12
```

### 9.4 Batch Receipt Demo

```text
SER-2701-C
expiry = 2027-01-31
receipt qty = 10
```

Setelah receipt:

```text
Serum sellable = 35
```

### 9.5 Bundle Recipe Snapshot

```text
BND-GLOW-01
=
2 x SER-NIA-30
1 x CLN-GEN-100
```

Tidak ada stock balance untuk `BND-GLOW-01`.

### 9.6 Marketplace Listing

| Channel | Listing SKU | Mapping |
|---|---|---|
| Shopee | `SHP-SER-NIA-30` | 1 Serum |
| TikTok | `TTS-SER-NIA-30` | 1 Serum |
| Shopee | `SHP-BND-GLOW-01` | Bundle recipe |
| TikTok | `TTS-BND-GLOW-01` | Bundle recipe |

---

## 10. Expected Quantity Ledger Demo

Urutan utama menghasilkan angka berikut.

| Step | Serum Sellable | Serum Reserved | Serum Available | Pending Inspection | Damaged Return Classification | Cleanser Sellable |
|---:|---:|---:|---:|---:|---:|---:|
| Baseline | 25 | 0 | 25 | 0 | 0 | 15 |
| Maklon +10 | 35 | 0 | 35 | 0 | 0 | 15 |
| Shopee order reserve 8 | 35 | 8 | 27 | 0 | 0 | 15 |
| Shopee shipped 8 | 27 | 0 | 27 | 0 | 0 | 15 |
| TikTok reserve 1 | 27 | 1 | 26 | 0 | 0 | 15 |
| TikTok in transit 1 | 26 | 0 | 26 | 0 | 0 | 15 |
| Manual bonus 2 | 24 | 0 | 24 | 0 | 0 | 15 |
| Bundle shipped | 22 | 0 | 22 | 0 | 0 | 14 |
| Return received 3 | 22 | 0 | 22 | 3 | 0 | 14 |
| Inspect 2 sellable + 1 damaged | 24 | 0 | 24 | 0 | 1 | 14 |
| Return lost/claim | 24 | 0 | 24 | 0 | 1 | 14 |
| Stocktake variance -1 | 23 | 0 | 23 | 0 | 1 | 14 |

### 10.1 FEFO Breakdown

Shopee order 8:

```text
SER-2608-A -> 5
SER-2612-B -> 3
```

TikTok order 1:

```text
SER-2612-B -> 1
```

Manual bonus 2:

```text
SER-2612-B -> 2
```

Bundle:

```text
SER-2612-B -> 2
CLN-2611-A -> 1
```

Return inspection sellable:

```text
RET-{receipt-line-id} sellable = +2
batch_kind_code = RETURN
source batch SER-2612-B = provenance only
```

Before stocktake:

```text
SER-2608-A sellable = 0
SER-2612-B sellable = 12
SER-2701-C sellable = 10
RET-{receipt-line-id} sellable = 2
Total = 24
```

Stocktake count on `SER-2612-B`:

```text
expected = 12
physical = 11
variance = -1
```

After adjustment:

```text
SER-2612-B = 11
Serum total sellable = 23
```

---

## 11. Preset Scenario Codes

Recommended simulator presets:

```text
DEMO_SHOPEE_RESERVATION_TO_SHIPPED
DEMO_TIKTOK_RESERVATION_TO_IN_TRANSIT
DEMO_CANCEL_PRE_SHIPMENT
DEMO_CANCEL_POST_SHIPMENT
DEMO_BUNDLE_SHIPMENT
DEMO_RETURN_MIXED_INSPECTION
DEMO_RETURN_LOST_AND_CLAIM
DEMO_DUPLICATE_EVENT
DEMO_REJECT_RETURN_OVER_OUTBOUND
DEMO_DAILY_RECONCILIATION
```

Preset definitions versioned in source control.

---

## 12. Pre-Demo Checklist: T-24 Jam

### Product

- [ ] Flow dan narasi tidak berubah sejak rehearsal terakhir.
- [ ] Semua open decision yang memengaruhi demo diselesaikan.
- [ ] Demo duration sesuai agenda.
- [ ] Golden quantities masih sesuai implementation.
- [ ] Tidak ada harga/nilai uang pada UI.

### Build

- [ ] Commit release candidate dipilih.
- [ ] Tag/release candidate dicatat.
- [ ] Production build berhasil.
- [ ] Deployment URL final tersedia.
- [ ] SSL valid.
- [ ] Custom domain/DNS stabil bila digunakan.

### Database

- [ ] Migration diterapkan.
- [ ] Seed demo deterministik berhasil.
- [ ] RLS test lulus.
- [ ] Ledger/projection reconciliation lulus.
- [ ] Tidak ada unexpected critical issue.
- [ ] Demo organization terpisah.

### Simulator

- [ ] Enabled pada demo organization.
- [ ] Disabled pada production organization.
- [ ] Semua preset dapat preview.
- [ ] Semua event diberi label demo.
- [ ] Reset procedure berhasil.

### Security

- [ ] Service-role tidak terdapat pada browser bundle.
- [ ] Akun Admin aktif.
- [ ] MFA/re-auth flow siap bila diaktifkan.
- [ ] Tidak ada data pelanggan nyata.
- [ ] Evidence demo sintetis.

---

## 13. Pre-Demo Checklist: T-60 Menit

Jalankan automated verification:

```bash
pnpm install --frozen-lockfile
pnpm typecheck
pnpm lint
pnpm test --run
supabase db reset
supabase test db
pnpm build
pnpm playwright test --grep @demo
```

Perintah final disesuaikan `package.json`.

Catat:

```text
commit SHA
deployment URL
database migration version
seed version
Playwright report URL/artifact
last reconciliation run
```

### 13.1 Environment Health

- [ ] Login berhasil.
- [ ] Dashboard load.
- [ ] Realtime atau polling berfungsi.
- [ ] Cron tidak backlog.
- [ ] Notification outbox sehat.
- [ ] Browser console bebas error kritis.
- [ ] API health normal.
- [ ] Database connection normal.

---

## 14. Pre-Demo Checklist: T-15 Menit

1. reset/recreate demo organization;
2. seed golden fixture;
3. login dengan Admin demo;
4. buka tab:
   - Dashboard;
   - Simulator;
   - Ledger;
   - Stock Opname;
   - Reconciliation;
   - Notifications;
5. tutup tab pribadi/tidak relevan;
6. zoom browser 100%;
7. nonaktifkan browser extension yang mengganggu;
8. sembunyikan bookmark/personal account bila perlu;
9. set notifikasi OS ke do-not-disturb;
10. siapkan charger dan koneksi cadangan;
11. jalankan smoke read-only;
12. jangan menjalankan skenario utama sebelum demo dimulai.

---

## 15. Pre-Demo Checklist: T-5 Menit

- [ ] Screen sharing menunjukkan monitor/tab yang benar.
- [ ] Password manager tidak menampilkan data sensitif.
- [ ] Banner `DEMO MODE` terlihat.
- [ ] Stopwatch aktif.
- [ ] Presenter memiliki printed/secondary-device runbook.
- [ ] Technical observer membuka health page.
- [ ] No unexpected critical notification.
- [ ] Initial serum = 25.
- [ ] Initial cleanser = 15.
- [ ] Batch `SER-2608-A` = 5.
- [ ] Notification expiry `D30` aktif untuk batch tersebut.

---

## 16. Opening State Verification

Sebelum berbicara:

```text
Dashboard:
Serum sellable = 25
Serum reserved = 0
Serum available = 25
Cleanser sellable = 15
```

Ledger baseline:

```text
initial balance entries exist
no demo run from previous session
```

Jika angka tidak cocok:

```text
STOP
reset demo organization
do not improvise adjustment
```

---

# PART B — DEMO UTAMA 18 MENIT

## 17. Timeline Ringkas

| Waktu | Segmen |
|---|---|
| 00:00–00:50 | Masalah dan janji sistem |
| 00:50–01:40 | Dashboard dan ledger baseline |
| 01:40–02:50 | Barang masuk maklon |
| 02:50–04:10 | Shopee: reservation |
| 04:10–05:50 | Shopee: shipped dan FEFO split |
| 05:50–07:10 | Pembatalan sebelum vs sesudah shipment |
| 07:10–08:10 | Manual bonus: alasan vs kanal |
| 08:10–09:15 | Bundle menjadi produk satuan |
| 09:15–11:15 | Retur: expected, receipt, inspection |
| 11:15–12:15 | Lost return dan claim |
| 12:15–13:00 | Duplicate event |
| 13:00–15:15 | Stok opname |
| 15:15–16:40 | Rekonsiliasi dan drill-down |
| 16:40–17:20 | Notifikasi |
| 17:20–18:00 | Penutup dan bukti akhir |

---

## 18. Segmen 1 — Masalah dan Janji Sistem

### Durasi

```text
00:00–00:50
```

### Layar

Dashboard overview.

### Narasi Presenter

> “Brand ini memiliki sekitar 70 produk skincare, ratusan paket keluar per hari, dan retur yang signifikan. Masalahnya bukan cuma angka spreadsheet berbeda dengan gudang. Masalah yang lebih besar adalah tidak ada yang bisa menjawab selisih itu terbentuk dari pesanan batal, retur, bonus, promo, sampel, atau saldo awal.”

> “Sistem ini dibangun dengan satu aturan: tidak ada angka stok yang berubah tanpa jejak. Saya akan mulai dari saldo awal, lalu menjalankan alur barang masuk, pesanan Shopee dan TikTok, FEFO, pembatalan, bonus, bundle, retur, klaim, opname, sampai rekonsiliasi.”

### Poin yang Harus Terlihat

- Dashboard tidak hanya menampilkan `stok total`.
- Ada:
  - sellable;
  - reserved;
  - available;
  - quarantine;
  - damaged;
  - expiry warning;
  - reconciliation status.

### Jangan Katakan

```text
“Ini sudah terintegrasi langsung ke Shopee dan TikTok.”
```

Fase 1 memakai simulator dan impor.

Gunakan:

> “Pada fase 1, simulator menghasilkan event kanonis yang sama dengan adapter API masa depan.”

---

## 19. Segmen 2 — Baseline dan Ledger

### Durasi

```text
00:50–01:40
```

### Action Operator

1. buka produk `SER-NIA-30`;
2. tampilkan batch;
3. buka ledger awal.

### Narasi Presenter

> “Serum ini memiliki dua batch sellable. Batch pertama tinggal 5 unit dan kedaluwarsa lebih dekat. Batch kedua 20 unit dengan expiry lebih panjang.”

> “Saldo 25 ini bukan field yang kami edit. Ini hasil agregasi ledger per batch dan bucket.”

### Expected

```text
SER-2608-A = 5
SER-2612-B = 20
Total sellable = 25
```

### Bukti

- batch code;
- expiry;
- bucket;
- initial balance source;
- ledger sequence;
- actor/process.

### Highlight

Notification expiry aktif:

```text
SER-2608-A within 30 days
quantity = 5
```

Presenter:

> “Notifikasi ini nanti akan hilang ketika batch berisiko tadi benar-benar habis melalui FEFO, bukan ketika seseorang sekadar menekan tombol read.”

---

## 20. Segmen 3 — Penerimaan dari Maklon

### Durasi

```text
01:40–02:50
```

### Action Operator

1. buka `Barang Masuk`;
2. create receipt:
   - product `SER-NIA-30`;
   - batch `SER-2701-C`;
   - expiry `2027-01-31`;
   - quantity `10`;
3. preview;
4. post;
5. buka transaction.

### Narasi Sebelum Posting

> “Penerimaan ini harus menambah sellable 10 unit pada batch baru. Sistem akan membuat satu transaction dan satu ledger entry. Jika saya mengirim command yang sama lagi, idempotency harus mencegah entry kedua.”

### Expected

```text
SER-2701-C SELLABLE +10
Serum sellable 25 -> 35
available 25 -> 35
```

### Bukti

- source receipt;
- batch;
- expiry;
- ledger `+10`;
- transaction type;
- Admin actor;
- timestamp.

### Narasi Setelah Posting

> “Saldo berubah karena receipt posted. Draft atau preview tidak pernah mengubah stok.”

---

## 21. Segmen 4 — Shopee Pesanan Baru: Reservasi

### Durasi

```text
02:50–04:10
```

### Action Operator

1. buka Simulator;
2. pilih `Shopee Order Created`;
3. item `SHP-SER-NIA-30`;
4. quantity `8`;
5. preview;
6. jalankan;
7. buka order.

### Narasi Sebelum Run

> “Keputusan klien menyatakan barang baru dihitung keluar saat fisik meninggalkan gudang. Jadi event pesanan baru hanya membuat reservasi.”

> “Yang harus terjadi: sellable tetap 35, reserved menjadi 8, available menjadi 27, dan belum ada ledger outbound.”

### Expected

```text
sellable = 35
reserved = 8
available = 27
outbound ledger = none
order = RESERVED
```

### Bukti

- canonical event;
- reservation;
- stock position;
- absence of allocation;
- absence of outbound ledger.

### Kalimat Kunci

> “Reservasi melindungi stok dari transaksi lain, tetapi tidak berpura-pura bahwa barang sudah keluar.”

---

## 22. Segmen 5 — Shopee `SHIPPED`: FEFO Split

### Durasi

```text
04:10–05:50
```

### Action Operator

1. dari order, jalankan event `SHIPPED`;
2. lihat allocation result;
3. buka ledger entries;
4. kembali ke batch position.

### Narasi Sebelum Run

> “Sekarang barang benar-benar meninggalkan gudang. Admin tidak memilih batch. Sistem menjalankan FEFO di dalam transaksi.”

> “Kebutuhannya 8 unit. Batch terdekat hanya memiliki 5, jadi hasil yang benar adalah split 5 unit dari batch A dan 3 unit dari batch B.”

### Expected Allocation

```text
SER-2608-A -> 5, FEFO rank 1
SER-2612-B -> 3, FEFO rank 2
```

### Expected Position

```text
sellable 35 -> 27
reserved 8 -> 0
available = 27
```

### Expected Ledger

```text
SER-2608-A SELLABLE -5
SER-2612-B SELLABLE -3
```

### Bukti

- algorithm code/version;
- operational date;
- expiry snapshot;
- safety buffer snapshot;
- allocation group;
- source order;
- ledger.

### Narasi

> “Batch A sekarang nol. Notifikasi expiry akan di-resolve saat evaluation berikutnya karena quantity berisiko sudah habis.”

### Jangan Lakukan

- jangan memilih batch manual;
- jangan menjelaskan FEFO sebagai FIFO;
- jangan hanya menunjukkan total `-8`.

---

## 23. Segmen 6 — Pembatalan Sebelum vs Sesudah Shipment

### Durasi

```text
05:50–07:10
```

### 23.1 Cancel Before Shipment

#### Action

1. simulator create Shopee order cleanser quantity `2`;
2. tunjukkan reserved;
3. cancel sebelum shipped.

#### Narasi

> “Pembatalan sebelum barang keluar hanya melepaskan reservation. Tidak ada pengembalian stok karena stok fisik memang belum pernah berkurang.”

#### Expected

```text
Cleanser sellable = 15
reserved 0 -> 2 -> 0
outbound ledger = none
```

### 23.2 Cancel After Shipment

#### Action

1. create TikTok serum quantity `1`;
2. show reservation;
3. process `IN_TRANSIT`;
4. cancel setelah physical outbound.

#### Narasi

> “Untuk TikTok, trigger fisiknya adalah `IN_TRANSIT`. Setelah itu, cancel tidak boleh otomatis menambah stok.”

#### Expected

```text
TikTok order:
reserve 1
IN_TRANSIT -> outbound -1
cancel after shipment -> no inbound
exact linked reversal created
```

Serum:

```text
27 -> 26
```

### Kalimat Kunci

> “Inilah salah satu kebocoran spreadsheet lama. Sistem baru tidak mengembalikan barang yang belum benar-benar kembali ke gudang.”

---

## 24. Segmen 7 — Pengeluaran Manual: Bonus

### Durasi

```text
07:10–08:10
```

### Action Operator

1. buka Manual Outbound;
2. channel `MANUAL`;
3. reason `BONUS`;
4. Serum quantity `2`;
5. preview FEFO;
6. post.

### Narasi

> “Bonus dan penjualan offline sama-sama dimasukkan manual, tetapi artinya berbeda. Kanal menjelaskan dari mana input berasal. Alasan menjelaskan mengapa barang keluar.”

### Expected

```text
channel = MANUAL
reason = BONUS
SER-2612-B -2
Serum sellable 26 -> 24
```

### Bukti

- reason;
- channel;
- batch allocation;
- ledger;
- source document.

### Kalimat Kunci

> “Barang gratis tidak boleh hilang di kategori ‘manual’ tanpa makna.”

---

## 25. Segmen 8 — Bundle Dihitung Satuan

### Durasi

```text
08:10–09:15
```

### Action Operator

1. buka recipe bundle;
2. tampilkan:
   - 2 Serum;
   - 1 Cleanser;
3. simulator create and ship one `SHP-BND-GLOW-01`;
4. buka normalized order lines;
5. buka allocation.

### Narasi

> “Bundle tidak memiliki stok sendiri. Listing paket dipecah menggunakan recipe snapshot saat order masuk.”

### Expected

```text
Bundle qty 1
-> Serum qty 2
-> Cleanser qty 1
```

Physical:

```text
Serum 24 -> 22
Cleanser 15 -> 14
```

### Bukti

- listing source;
- recipe version/snapshot;
- normalized component lines;
- reservations;
- FEFO allocation;
- no stock balance for bundle SKU.

### Kalimat Kunci

> “Jika recipe berubah besok, order ini tetap memakai recipe yang berlaku ketika data masuk.”

---

## 26. Segmen 9 — Retur: Expected, Receipt, dan Inspection

### Durasi

```text
09:15–11:15
```

### 26.1 Expected Return

#### Action

Buat return dari Shopee order pertama:

```text
expected qty = 3
```

#### Narasi

> “Status retur dari marketplace hanya membuat barang diharapkan kembali. Stok belum bertambah.”

#### Expected

```text
stock effect = none
return status = EXPECTED
```

### 26.2 Physical Receipt

#### Action

Konfirmasi barang tiba:

```text
received qty = 3
source batch provenance = SER-2612-B
```

#### Narasi

> “Barang sudah tiba, tetapi receipt hanya mencatat pending inspection. Stok fisik sistem belum berubah.”

#### Expected

```text
api.confirm_return_receipt
received qty = 3
pending inspection 0 -> 3
stock transaction = none
ledger entry = none
projection delta = 0
stock effect = NONE
sellable remains 22
```

### 26.3 Inspection

#### Action

Inspect:

```text
SELLABLE 2
DAMAGED 1
```

#### Expected

```text
api.inspect_return
RETURN_SELLABLE_INBOUND +2
destination = new batch `RETURN`
source batch SER-2612-B = provenance only
DAMAGED 1 = audit classification
damaged stock movement = none
```

Final:

```text
Serum sellable 22 -> 24
pending inspection 3 -> 0
damaged return classification 0 -> 1
damaged stock bucket remains 0
```

### Bukti

- source return;
- receipt dengan `stockEffectCode = NONE`;
- inspection record;
- stock transaction `RETURN_SELLABLE_INBOUND`;
- batch tujuan dengan `batch_kind_code = RETURN`;
- provenance batch asal;
- damaged allocation tanpa ledger destination;
- actor/time/note.

### Kalimat Kunci

> “Marketplace memberi informasi. Gudang menentukan kondisi fisik.”

---

## 27. Segmen 10 — Retur Hilang dan Klaim TikTok

### Durasi

```text
11:15–12:15
```

### Action Operator

1. buka TikTok post-shipment cancellation lalu drill-down ke original shipment allocation dan exact linked reversal;
2. mark pending quantity `1` sebagai lost;
3. create claim;
4. buka deadline dan notification.

### Narasi

> “Barang ini tidak pernah tiba. Menandai lost tidak membuat inbound. Klaim juga tidak menambah stok.”

### Expected

```text
lost qty = 1
ledger effect = none
claim created
claim window = 40 calendar days
deadline basis = operations.returns.created_at
```

Untuk golden clock:

```text
deadline remaining = 3 days
notification stage = D3
severity = HIGH
```

### Bukti

- return status/outcome;
- claim basis;
- deadline;
- no ledger;
- notification deep link.

### Kalimat Kunci

> “Klaim adalah kewajiban operasional, bukan movement barang dan bukan pencatatan uang.”

---

## 28. Segmen 11 — Duplicate Event dan Idempotency

### Durasi

```text
12:15–13:00
```

### Action Operator

1. pilih event shipment Shopee yang sudah diproses;
2. kirim duplicate dengan external event ID dan payload sama;
3. buka result.

### Narasi Sebelum Run

> “Marketplace dan jaringan dapat mengirim event yang sama lebih dari sekali. Yang benar bukan berharap duplicate tidak terjadi, tetapi memastikan efeknya maksimal satu kali.”

### Expected

```text
processing status = DUPLICATE
new stock transaction = none
new ledger entry = none
stock remains unchanged
```

### Optional Conflict

Jika waktu cukup, kirim same ID/different payload.

Expected:

```text
REJECTED
IDEMPOTENCY_PAYLOAD_MISMATCH
```

### Bukti

- existing event reference;
- duplicate status;
- unchanged ledger count.

---

## 29. Segmen 12 — Stok Opname

### Durasi

```text
13:00–15:15
```

### Setup

Scope:

```text
SER-NIA-30
Batch SER-2612-B
Bucket SELLABLE
Mode FROZEN
Visibility BLIND
```

Expected system quantity:

```text
12
```

Physical count input:

```text
11
```

### 29.1 Start

#### Action

1. create stocktake;
2. start frozen;
3. show hold/status.

#### Narasi

> “Stok opname tidak mengedit saldo. Sistem mengambil snapshot ledger dan menahan movement pada scope ini.”

### 29.2 Blind Count

#### Action

1. buka count task;
2. tunjukkan bahwa expected tidak terlihat;
3. input `11`;
4. submit.

#### Narasi

> “Attempt pertama blind. Admin menghitung barang fisik, bukan menyalin angka sistem.”

### 29.3 Review

#### Expected

```text
expected = 12
physical = 11
variance = -1
```

#### Action

1. open movement breakdown;
2. pilih reason `PHYSICAL_LOSS` atau reason demo yang disetujui;
3. approve.

### 29.4 Post

#### Action

Post adjustment.

#### Expected

```text
STOCKTAKE_ADJUSTMENT
SER-2612-B SELLABLE -1
SER-2612-B 12 -> 11
Serum sellable 24 -> 23
```

### Bukti

- snapshot sequence;
- count attempt;
- actor;
- expected formula;
- variance;
- approval version;
- ledger adjustment;
- reconciliation run.

### Kalimat Kunci

> “Selisih tidak dihapus. Selisih diterima dengan bukti, alasan, dan adjustment ledger.”

---

## 30. Segmen 13 — Rekonsiliasi dan Drill-Down

### Durasi

```text
15:15–16:40
```

### Action Operator

1. buka reconciliation run sesudah stocktake;
2. tampilkan:
   - ledger vs batch projection;
   - batch vs product projection;
   - allocation vs outbound;
   - `RETURN_RECEIPT_CONSISTENCY`;
   - `RETURN_INSPECTION_CONSISTENCY`;
   - stocktake adjustment;
3. buka movement breakdown Serum.

### Narasi

> “Ada dua ritme rekonsiliasi. Harian memeriksa konsistensi sistem sendiri. Saat opname, catatan dibandingkan dengan hitung fisik.”

> “Setelah adjustment, ledger dan projection harus kembali konsisten. Tetapi histori selisih dan alasan adjustment tetap ada.”

### Expected Movement Story

```text
Initial balance       +25
Maklon receipt        +10
Shopee shipped         -8
TikTok in transit      -1
Manual bonus           -2
Bundle component       -2
Return sellable        +2
Stocktake adjustment   -1
--------------------------------
Final sellable         23
```

### Bukti

- drill-down dari total ke transaction;
- source order/manual/return/stocktake;
- actor;
- batch;
- ledger sequence.

### Kalimat Kunci

> “Sistem tidak hanya mengatakan ada selisih satu unit. Sistem menunjukkan kapan saldo terbentuk dan transaksi apa yang menyusun angka akhirnya.”

---

## 31. Segmen 14 — Notifikasi

### Durasi

```text
16:40–17:20
```

### Action Operator

1. buka Notification Center;
2. tunjukkan:
   - expiry episode batch A resolved;
   - claim D3 active;
   - stocktake/reconciliation notification bila ada;
3. mark claim notification read;
4. buka claim.

### Narasi

> “Notifikasi adalah projection kondisi. Mark as read tidak menyelesaikan klaim dan tidak mengubah stok.”

### Expected

```text
expiry notification:
resolved because relevant balance = 0

claim:
active D3
read state changes for current Admin only
claim status unchanged
stock unchanged
```

---

## 32. Segmen 15 — Penutup

### Durasi

```text
17:20–18:00
```

### Layar

Final product position + ledger summary.

### Narasi Presenter

> “Kita mulai dengan 25 unit serum. Masuk 10 dari maklon, lalu keluar melalui Shopee, TikTok, bonus, dan bundle. Dua unit retur kembali layak jual melalui batch RETURN baru, satu unit diklasifikasikan rusak tanpa movement stok, dan satu hilang menjadi klaim. Opname menemukan selisih fisik satu unit dan membuat adjustment yang dapat diaudit.”

> “Saldo akhir sellable adalah 23. Damaged stock bucket tetap nol, sementara satu damaged return tercatat sebagai kondisi operasional. Setiap perubahan stok memiliki transaction dan ledger; setiap receipt, kondisi, dan klaim stock-neutral tetap memiliki audit trail.”

### Final Proof

```text
Serum sellable = 23
Damaged stock bucket = 0
Damaged return classification = 1
Pending inspection = 0
Active reserved = 0
```

### Closing Sentence

> “Nilai utama sistem ini bukan sekadar mengetahui stok sekarang. Nilainya adalah kemampuan menjawab mengapa angka itu menjadi demikian.”

Stop.

Jangan menambahkan tur menu acak setelah closing.

---

# PART C — CHECKPOINT SETELAH SETIAP SEGMEN

## 33. Checkpoint Matrix

| Segmen | Checkpoint | Jika Tidak Cocok |
|---|---|---|
| Baseline | Serum 25 | Reset demo |
| Maklon | Serum 35 | Stop; verify receipt |
| Reservation | Sellable 35, reserved 8 | Stop; inspect event |
| Shopee shipped | Serum 27 | Check allocation/ledger |
| TikTok out | Serum 26 | Check status mapping |
| Bonus | Serum 24 | Check reason/FEFO |
| Bundle | Serum 22, cleanser 14 | Check recipe snapshot |
| Return receipt | Pending inspection 3; stock tetap 22 | Check receipt result |
| Inspection | Sellable 24 pada batch RETURN baru; damaged classification 1; damaged stock 0 | Check transaction/audit |
| Lost/claim | No stock effect | Stop if ledger exists |
| Duplicate | No stock effect | Stop; idempotency defect |
| Stocktake | Sellable 23 | Check adjustment |
| Reconciliation | Critical unexpected = 0 | Do not hide issue |

---

## 34. Stop Conditions

Demo utama harus dihentikan dan di-reset bila:

- initial quantity salah;
- duplicate event membuat movement baru;
- stock menjadi negatif;
- FEFO memilih expired/blocked batch;
- return expected menambah stock;
- return receipt membuat stock transaction, ledger entry, atau projection delta;
- claim membuat ledger;
- stocktake posting parsial;
- cross-organization data terlihat;
- service error membuat hasil posting tidak pasti.

Jangan melanjutkan sambil mengatakan:

```text
“Ini cuma data demo.”
```

Jika invariant gagal pada data demo, ia tidak tiba-tiba menjadi benar pada data produksi.

---

# PART D — DEMO RINGKAS 8 MENIT

## 35. Tujuan Versi Ringkas

Versi ringkas harus tetap membuktikan:

- reservation vs outbound;
- FEFO;
- receipt stock-neutral dan inspection dengan dampak stok terpisah;
- stocktake/reconciliation;
- traceability.

### Timeline

| Waktu | Segmen |
|---|---|
| 00:00–00:40 | Masalah |
| 00:40–01:20 | Baseline + ledger |
| 01:20–02:00 | Maklon receipt |
| 02:00–03:20 | Shopee reserve -> shipped -> FEFO |
| 03:20?04:20 | Partial post-shipment cancellation + exact linked reversal |
| 04:20–05:20 | Return receipt + mixed inspection |
| 05:20–06:40 | Stocktake variance |
| 06:40–07:30 | Reconciliation drill-down |
| 07:30–08:00 | Closing |

### Yang Dipotong

- TikTok happy path dijelaskan dari existing result;
- cancel pre-shipment menjadi screenshot/detail singkat;
- manual bonus dilihat pada ledger;
- bundle ditunjukkan melalui normalized line;
- duplicate event melalui result card;
- notification melalui bell.

Tidak boleh memotong FEFO, bukti receipt stock-neutral/inspection, atau rekonsiliasi.

---

# PART E — TECHNICAL DEEP DIVE

## 36. Kapan Digunakan

Buka bagian teknis hanya bila reviewer bertanya:

- bagaimana angka dihitung;
- bagaimana concurrency aman;
- bagaimana RLS bekerja;
- bagaimana simulator bisa diganti API;
- bagaimana test dilakukan;
- bagaimana data demo diisolasi.

---

## 37. Arsitektur Singkat

Narasi maksimal 45 detik:

> “Next.js menjadi boundary UI dan server action. Supabase Auth mengidentifikasi Admin. PostgreSQL menyimpan ledger, projection, order, retur, dan opname. Client tidak menulis ledger langsung. Mutation kritis masuk database function atomik. RLS membatasi organisasi. Simulator dan impor menghasilkan event kanonis yang diproses domain pipeline yang sama.”

Diagram:

```text
Admin
-> Next.js
-> authenticated server boundary
-> canonical command/event
-> database function
-> ledger + projection + audit
-> reconciliation
```

---

## 38. Pertanyaan: Mengapa Ledger dan Projection?

Jawaban:

> “Ledger adalah histori append-only dan source of truth. Projection mempercepat pembacaan saldo. Rekonsiliasi memastikan projection selalu dapat dibangun ulang dari ledger. Jika berbeda, yang diperbaiki projection, bukan ledger.”

Bukti:

- ledger entry;
- rebuild function/test;
- reconciliation check.

---

## 39. Pertanyaan: Bagaimana Mencegah Stok Negatif?

Jawaban:

> “Validation awal hanya untuk UX. Saat commit, function mengunci posisi produk dan kandidat batch, menghitung ulang availability, lalu mem-posting allocation dan ledger dalam satu transaksi. Dua request bersamaan tidak dapat memakai unit yang sama.”

Bukti:

- concurrency test `TST-FEFO-011`;
- test report;
- no negative invariant.

---

## 40. Pertanyaan: Mengapa Batch Tidak Dipilih Admin?

Jawaban:

> “FEFO adalah aturan sistem. Admin memilih produk dan quantity, bukan batch. Batch final ditentukan saat physical outbound berdasarkan expiry dan eligibility saat itu. Ini mengurangi human error dan membuat keputusan dapat diuji.”

---

## 41. Pertanyaan: Kenapa Tidak Kurangi Stok Saat Order Masuk?

Jawaban:

> “Order belum berarti barang meninggalkan gudang. Sistem hanya membuat reservation. Ini mencegah cancel sebelum shipment diperlakukan seperti barang yang harus dikembalikan.”

---

## 42. Pertanyaan: Mengapa Receipt Retur Tidak Langsung Mengubah Stok?

Jawaban:

> “Status marketplace dan kedatangan fisik belum membuktikan barang layak jual. Receipt hanya mencatat pending inspection. Setelah gudang menginspeksi, kuantitas sellable masuk ke batch RETURN baru, sedangkan damaged dicatat untuk audit tanpa movement stok kedua.”

---

## 43. Pertanyaan: Bagaimana Simulator Diganti API?

Jawaban:

> “Simulator berhenti setelah menghasilkan event kanonis. CSV import dan API masa depan memetakan input ke event yang sama. Reservation, state machine, FEFO, ledger, retur, dan reconciliation tidak perlu ditulis ulang.”

Bukti:

- canonical event preview;
- `source = SIMULATOR`;
- event processor reference;
- no direct simulator ledger write.

---

## 44. Pertanyaan: Bagaimana Security Bekerja Jika Hanya Ada Satu Role?

Jawaban:

> “Role aplikasi memang hanya Admin, tetapi hak teknis tetap dipisahkan. Browser tidak memiliki service-role, direct ledger write ditolak, RLS membatasi organisasi, file evidence private, dan function memverifikasi user, organisasi, state, serta MFA untuk tindakan sensitif.”

---

## 45. Pertanyaan: Bagaimana Test Dilakukan?

Jawaban ringkas:

> “Vitest untuk logic, pgTAP untuk schema/function/RLS, Playwright untuk flow live, harness paralel untuk concurrency, dan k6 untuk threshold performa. Release berhenti bila ada negative stock, duplicate movement, cross-org access, FEFO salah, atau receipt retur mengubah stok atau sellable diposting tanpa inspeksi/provenance.”

Buka test report bila diminta, bukan membacakan 278 scenario.

---

# PART F — Q&A CHEAT SHEET

## 46. “Apakah Ini Terintegrasi API Shopee/TikTok?”

Jawaban:

> “Belum pada fase 1, sesuai batasan brief. Simulator dan impor menggantikan API. Keduanya masuk ke canonical event pipeline yang dirancang agar adapter API bisa menggantikan tombol tanpa mengubah logika inti.”

---

## 47. “Mengapa Tidak Menyimpan Harga?”

Jawaban:

> “Scope fase 1 sengaja unit-only. Seluruh schema, klaim, laporan, dan test tidak memakai harga atau nilai uang.”

---

## 48. “Bagaimana Jika Barang Return Datang Setelah Ditandai Hilang?”

Jawaban:

> “Sistem membuka late-arrival exception, mencatat receipt secara stock-neutral, mempertahankan histori lost dan claim, lalu menginspeksi barang melalui alur normal. Histori lama tidak dihapus.”

---

## 49. “Bagaimana Jika Expiry Sama?”

Jawaban:

> “Tie-breaker FEFO adalah waktu penerimaan, lalu batch code, lalu batch ID. Hasil deterministik.”

---

## 50. “Bagaimana Jika Batch Terdekat Sedang Dikunci?”

Jawaban:

> “Normal FEFO menunggu atau retry. Kami tidak memakai `SKIP LOCKED` untuk keputusan FEFO karena itu dapat melompati batch expiry terdekat.”

---

## 51. “Mengapa Notifikasi Tidak Mengubah Status?”

Jawaban:

> “Notifikasi hanya projection kondisi. Mark as read tidak menyelesaikan claim, retur, issue, atau batch expiry. Tindakan domain selalu eksplisit.”

---

## 52. “Bagaimana Menjelaskan Selisih?”

Jawaban:

> “Dari variance opname, Admin dapat membuka expected quantity, physical count, movement breakdown, ledger entry, source document, batch, actor, dan adjustment yang dilakukan.”

---

## 53. “Bisa Dipakai Lewat Ponsel?”

Jawaban:

> “Flow penerimaan, simulator, retur, count task, dan notifikasi dirancang satu kolom pada viewport kecil. Posting tetap online dan selalu memakai validation server.”

Lakukan satu mobile viewport spot-check bila diminta.

---

## 54. “Bisa Banyak User?”

Jawaban:

> “Bisa beberapa akun individual, semuanya role Admin sesuai keputusan terbaru. Status baca notifikasi dan audit actor tetap per akun. Akun bersama tidak digunakan.”

---

## 55. “Bagaimana Reset Demo?”

Jawaban:

> “Demo menggunakan organisasi terisolasi. Reset dilakukan dengan recreate/restore tenant demo pada environment non-production, bukan menghapus ledger production atau mencari row berdasarkan kata ‘demo’.”

---

# PART G — FAILURE RECOVERY

## 56. Prinsip Fallback

Fallback tidak boleh:

- memalsukan hasil;
- menulis database manual;
- menghapus error;
- mengganti live app dengan video tanpa menjelaskan;
- memakai production.

Fallback yang diperbolehkan:

- reload;
- query idempotency result;
- pindah ke browser cadangan;
- pindah koneksi;
- restore demo tenant;
- buka trace/test evidence;
- gunakan completed scenario result dari rehearsal pada organisasi demo jika live event processor sementara bermasalah dan jelaskan secara jujur.

---

## 57. Login Gagal

### Langkah

1. cek URL/environment;
2. refresh;
3. gunakan recovery code/MFA;
4. gunakan akun Admin demo cadangan individual;
5. jangan memakai service-role atau bypass RLS.

### Narasi

> “Akun demo utama gagal menyelesaikan autentikasi. Kami beralih ke akun Admin demo cadangan; keduanya tetap melewati Auth dan RLS yang sama.”

---

## 58. Simulator Dinonaktifkan

### Langkah

1. verifikasi banner/environment;
2. jangan ubah flag production;
3. pindah ke approved demo URL;
4. bila demo URL gagal, gunakan import canonical fixture jika tersedia.

### Narasi

> “Simulator sengaja tidak aktif pada environment ini. Kami pindah ke tenant demo yang memang diizinkan.”

---

## 59. Network Timeout Setelah Posting

### Langkah

1. jangan klik ulang dengan command baru;
2. buka transaction/result berdasarkan idempotency key;
3. refresh page;
4. verifikasi ledger;
5. lanjut hanya setelah status pasti.

### Narasi

> “Client tidak menerima response, tetapi command memakai idempotency. Kami memeriksa apakah transaction sudah committed sebelum melakukan retry.”

---

## 60. Duplicate Submit

Expected:

- tombol disabled;
- server mengembalikan existing result;
- no second ledger.

Jika movement kedua muncul:

```text
STOP DEMO
blocker defect
```

---

## 61. Lock Timeout

### Langkah

1. tampilkan error;
2. retry dengan idempotency key yang sama;
3. jangan mengubah quantity/batch;
4. bila terus gagal, buka concurrency evidence dan lanjut ke scenario result yang sudah ada.

### Narasi

> “Sistem lebih memilih meminta retry daripada melewati aturan batch atau membuat stok negatif.”

---

## 62. Data Baseline Tidak Cocok

### Langkah

1. stop;
2. reset demo tenant;
3. verify seed;
4. run baseline query/health page;
5. restart demo.

Dilarang membuat adjustment untuk menyesuaikan dengan naskah.

---

## 63. Notification Belum Muncul

### Langkah

1. jalankan rule evaluation manual dari Admin diagnostics yang resmi;
2. refresh/poll;
3. verifikasi source condition;
4. lihat rule run;
5. jangan insert notification langsung.

---

## 64. Reconciliation Job Lambat

### Langkah

1. tunjukkan run status;
2. gunakan safe refresh;
3. buka completed run terbaru yang memakai boundary yang relevan;
4. jelaskan job async;
5. simpan trace.

---

## 65. Browser Bermasalah

Cadangan:

- Chromium profile bersih;
- Firefox/WebKit bila perlu;
- mobile device optional;
- deployment URL bookmarked.

Jangan membuka incognito dengan session tak siap lalu menghabiskan tiga menit mencari kode MFA seperti ritual modern yang sangat bermartabat.

---

## 66. Koneksi Utama Putus

- hotspot cadangan;
- operator tetap pada tab terakhir;
- jangan menjalankan offline posting;
- aplikasi tidak boleh menampilkan draft sebagai posted;
- gunakan test evidence bila koneksi tidak pulih.

---

## 67. Fallback Evidence Pack

Simpan:

```text
latest Playwright demo trace
HTML test report
pgTAP report
reconciliation report
golden fixture summary
screenshots of completed scenario
commit SHA
migration version
```

Evidence pack:

- diagnostic;
- bukan pengganti submission live;
- tidak memuat secret atau PII.

Playwright trace membantu memeriksa DOM snapshot, network, console, dan langkah yang dijalankan.

---

# PART H — PRESENTATION QUALITY

## 68. Bahasa Presenter

Gunakan istilah bisnis:

```text
barang masuk
reservasi
barang keluar
batch
kedaluwarsa
retur
layak jual
rusak
hilang
stok opname
selisih
rekonsiliasi
```

Istilah teknis hanya saat perlu:

```text
ledger
FEFO
idempotency
RLS
canonical event
```

Jelaskan sekali.

---

## 69. Frasa yang Direkomendasikan

```text
“Yang harus terjadi adalah...”
“Yang tidak boleh terjadi adalah...”
“Sekarang kita buka sumber angkanya.”
“Ini adalah movement fisik, bukan perubahan status semata.”
“Event yang sama diproses satu kali.”
“Saldo ini dapat dihitung ulang dari ledger.”
```

---

## 70. Frasa yang Dihindari

```text
“Harusnya...”
“Kayaknya...”
“Biasanya jalan...”
“Ini sebenarnya bisa...”
“Kalau error tinggal update database.”
“Untuk demo kita bypass saja.”
“Role-nya banyak, tapi belum dibuat.”
“API marketplace sudah siap.”
```

---

## 71. Kecepatan

- 120–150 kata/menit;
- berhenti 1–2 detik setelah perubahan angka;
- jangan menggulir saat menjelaskan poin kritis;
- zoom pada ledger/allocation bila perlu;
- gunakan pointer secukupnya.

---

## 72. Screen Discipline

- satu tab aktif untuk flow;
- hindari berpindah editor;
- URL sensitif tidak terlihat;
- devtools hanya saat technical deep dive;
- no console spam;
- no personal notification;
- no unrelated bookmark.

---

## 73. Accessibility Saat Demo

- jangan mengandalkan warna saja;
- baca severity/status;
- gunakan zoom yang terbaca;
- jangan menggulir terlalu cepat;
- tunjukkan focus/label bila membahas usability;
- pastikan status success/error punya teks.

---

# PART I — ACCEPTANCE DAN SIGN-OFF

## 74. Demo Acceptance Criteria

### Problem and Value

- `DEM-AC-001`: Masalah dijelaskan kurang dari satu menit.
- `DEM-AC-002`: Janji “tidak ada perubahan tanpa jejak” dibuktikan.
- `DEM-AC-003`: Closing menghitung saldo akhir.

### Inventory

- `DEM-AC-004`: Receipt menambah stok dengan ledger.
- `DEM-AC-005`: Order baru hanya reservation.
- `DEM-AC-006`: Shopee outbound pada `SHIPPED`.
- `DEM-AC-007`: TikTok outbound pada `IN_TRANSIT`.
- `DEM-AC-008`: FEFO split terlihat.
- `DEM-AC-009`: Admin tidak memilih batch.
- `DEM-AC-010`: Cancel pre/post shipment berbeda.

### Manual and Bundle

- `DEM-AC-011`: Reason dan channel ditampilkan terpisah.
- `DEM-AC-012`: Bonus dapat ditelusuri.
- `DEM-AC-013`: Bundle dipecah.
- `DEM-AC-014`: Tidak ada stock bundle.

### Return and Claim

- `DEM-AC-015`: Expected return no stock effect.
- `DEM-AC-016`: Receipt menambah pending inspection tanpa transaction, ledger, atau projection delta.
- `DEM-AC-017`: Mixed inspection membuat sellable inbound ke batch `RETURN` baru dan damaged audit-only.
- `DEM-AC-018`: Lost no stock effect.
- `DEM-AC-019`: Claim deadline terlihat sebagai 40 hari sejak `operations.returns.created_at`.
- `DEM-AC-020`: Claim tidak mengubah stock.

### Integrity

- `DEM-AC-021`: Duplicate no second effect.
- `DEM-AC-022`: Stocktake blind count terlihat.
- `DEM-AC-023`: Adjustment linked ke variance.
- `DEM-AC-024`: Reconciliation pass setelah correction.
- `DEM-AC-025`: Movement breakdown dapat di-drill.

### Technical and Usability

- `DEM-AC-026`: Aplikasi menggunakan deployment live.
- `DEM-AC-027`: Demo data terisolasi.
- `DEM-AC-028`: Admin individual digunakan.
- `DEM-AC-029`: Mobile flow dapat ditunjukkan.
- `DEM-AC-030`: Tidak ada database manipulation manual.

---

## 75. Demo Release Gate

Demo tidak dinyatakan siap bila:

- golden quantity tidak cocok;
- P0 demo smoke gagal;
- unexpected critical reconciliation issue aktif;
- simulator menulis ledger langsung;
- production data digunakan;
- service-role terdeteksi client;
- duplicate menghasilkan movement kedua;
- FEFO memilih batch salah;
- return receipt mengubah stock atau sellable inspection tidak memakai batch RETURN baru/provenance;
- claim mengubah stock;
- stocktake posting parsial;
- deployment tidak stabil;
- reset demo belum diuji.

---

## 76. Rehearsal Plan

### Rehearsal 1

Tujuan:

- validasi flow dan angka.

Boleh berhenti untuk diskusi.

### Rehearsal 2

Tujuan:

- waktu;
- perpindahan halaman;
- wording;
- fallback.

Tidak boleh mengubah requirement di tengah run.

### Rehearsal 3

Tujuan:

- simulasi kondisi live;
- screen sharing;
- Q&A;
- koneksi cadangan.

### Final Rehearsal

- commit sama dengan release candidate;
- deployment sama;
- seed sama;
- tanpa bantuan SQL;
- direkam internal untuk review.

---

## 77. Rehearsal Scorecard

| Area | Score 1–5 |
|---|---:|
| Masalah jelas |  |
| Angka mudah diikuti |  |
| FEFO terbukti |  |
| Reservation terbukti |  |
| Retur jelas |  |
| Opname jelas |  |
| Rekonsiliasi kuat |  |
| UI mudah diikuti |  |
| Waktu sesuai |  |
| Fallback siap |  |

Minimum sebelum final:

```text
semua area >= 4
```

---

## 78. Demo Sign-Off

| Item | Owner | Status |
|---|---|---|
| Product flow |  |  |
| Golden data |  |  |
| Database migration |  |  |
| Test suite |  |  |
| Security/RLS |  |  |
| Deployment |  |  |
| Simulator |  |  |
| Reconciliation |  |  |
| Presenter rehearsal |  |  |
| Fallback evidence |  |  |

Final sign-off records:

```text
commit SHA
deployment URL
release timestamp
migration version
seed version
demo Admin
test report
approver
```

---

## 79. Traceability ke Source Project

| Source requirement | Demo proof |
|---|---|
| Sekitar 70 produk dan batch expiry | Product/batch page |
| Ledger pusat | Every movement drill-down |
| Maklon receipt | Segment 3 |
| Manual offline/bonus/promo/sample | Bonus segment + menu |
| Shopee/TikTok event | Simulator segments |
| Retur berbagai kondisi | Return segment |
| Claim TikTok 40 hari | Claim segment |
| Expiry notification | Baseline/notification |
| Stocktake | Segment 12 |
| Reconciliation | Segment 13 |
| Shopee SHIPPED | Segment 5 |
| TikTok IN_TRANSIT | Segment 6 |
| Reservation before physical out | Segment 4 |
| FEFO automatic | Segment 5 |
| Bundle unit components | Segment 8 |
| Return condition by warehouse | Segment 9 |
| No marketplace API phase 1 | Simulator explanation |
| Import remains available | Technical/Q&A |
| No price | Entire demo |
| Live deployment | Environment |
| Easy for warehouse user | Screen flow and mobile |
| One Admin role | Individual Admin account |

---

## 80. Amendment terhadap Dokumen Sebelumnya

### `07-marketplace-simulator.md`

Tambahkan preset `DEMO_*` dan expected quantities pada dokumen ini.

### `12-notification-rules.md`

Pastikan expiry episode resolved ketika balance batch A nol.

### `14-testing-scenarios.md`

Tag seluruh demo-critical test:

```text
@demo
```

Dan sediakan Playwright project:

```text
demo-smoke
```

---

## 81. Keputusan Terbuka

1. Durasi final demo.
2. Apakah presenter dan operator orang yang sama.
3. Apakah demo memakai fixed clock.
4. Apakah MFA ditampilkan atau session disiapkan sebelum demo.
5. Apakah mobile flow masuk 18 menit atau Q&A.
6. Apakah duplicate conflict ditampilkan selain duplicate identik.
7. Apakah import ditampilkan live.
8. Apakah technical architecture slide digunakan.
9. Apakah claim stage D3 atau D1.
10. Apakah stocktake memakai frozen atau continuous pada demo utama.
11. Apakah browser matrix perlu ditunjukkan.
12. Siapa pemegang koneksi cadangan.
13. Siapa yang berhak melakukan reset demo.
14. Apakah fallback trace dapat dibuka tanpa autentikasi eksternal.
15. Apakah final Q&A memiliki batas waktu.

Default dokumen:

```text
18-minute demo
single presenter/operator allowed
fixed demo clock
frozen blind stocktake
D3 claim
mobile in Q&A
```

---

## 82. Referensi Teknis Resmi

### Next.js

Production Checklist:

`https://nextjs.org/docs/app/guides/production-checklist`

Checklist tersebut mencakup kesiapan production, keamanan, performa, dan pengalaman pengguna. Demo harus dijalankan pada production build, bukan dev server yang kebetulan sedang kooperatif.

### Supabase

Local Development:

`https://supabase.com/docs/guides/local-development`

Testing Overview:

`https://supabase.com/docs/guides/local-development/testing/overview`

Database Testing:

`https://supabase.com/docs/guides/database/testing`

Environment demo harus dapat dibangun ulang melalui migration dan seed, lalu diverifikasi melalui database tests.

### Playwright

Test Projects:

`https://playwright.dev/docs/test-projects`

Trace Viewer:

`https://playwright.dev/docs/trace-viewer`

Best Practices:

`https://playwright.dev/docs/best-practices`

Playwright trace disimpan sebagai evidence fallback dan alat diagnosis, bukan sebagai pengganti aplikasi live.

### OWASP

Environment Isolation:

`https://owasp.org/www-project-non-human-identities-top-10/2025/8-environment-isolation/`

Web Security Testing Guide:

`https://owasp.org/www-project-web-security-testing-guide/`

Demo, preview, testing, dan production harus menggunakan identitas, secret, serta data yang terisolasi.

---

## 83. Ringkasan Final

Demo yang benar bukan tur fitur.

Demo harus membuktikan cerita stok:

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

Sementara itu:

```text
1 damaged return classification
damaged stock bucket 0
1 return lost
claim active
pending inspection 0
reserved 0
```

Setiap perubahan stok memiliki:

```text
source
reason
channel
product
batch
bucket
actor
timestamp
ledger transaction
```

Setiap perubahan operasional stock-neutral memiliki receipt/inspection/claim event, actor, timestamp, provenance, dan `stockEffectCode = NONE`.

Simulator hanya membuat event. FEFO memilih batch. Receipt retur tetap stock-neutral. Gudang menginspeksi kondisi; sellable masuk batch RETURN baru dan damaged tetap audit-only. Klaim tidak mengubah stok. Opname membuat adjustment. Rekonsiliasi memastikan seluruh angka dapat dijelaskan.

Jika penonton hanya mengingat satu hal, biarkan itu menjadi ini:

> **Sistem tidak sekadar menunjukkan berapa stok yang tersisa. Sistem menunjukkan bagaimana angka tersebut terbentuk dan di mana selisih harus dicari.**

Itulah inti proyek. Sisanya adalah tombol, form, dan usaha manusia memberi nama resmi pada hal-hal yang seharusnya sejak awal dicatat dengan benar.

---

## Demo Marketplace Listing Versioned

Urutan demo yang telah tersedia:

1. Buka `/marketplace/listings`.
2. Buat listing bundle untuk channel marketplace dan isi external listing code.
3. Buat draft version dengan dua produk satuan dan positive integer quantity.
4. Jalankan preview untuk membuktikan expansion stock-neutral dan lihat basis hash.
5. Aktifkan version dengan effective time eksplisit.
6. Buka `/marketplace`, pilih external listing code tersebut, lalu reserve listing quantity.
7. Tunjukkan source listing line, mapping version, fingerprint, dan immutable canonical component snapshots.
8. Buat dan aktifkan version kedua pada boundary baru.
9. Buktikan order lama tetap memakai version pertama dan order baru memakai version kedua.
10. Jalankan shipment untuk memperlihatkan FEFO per component.
11. Jalankan partial cancellation untuk memperlihatkan reservation release dan exact post-shipment reversal.
12. Archive listing dan tunjukkan histori order/version tetap tersedia.

Jangan mendemokan bundle sebagai stok tersendiri dan jangan memasukkan internal product UUID pada simulator. Seluruh cleanup harus melalui normalized cancellation/reversal command, bukan update SQL manual.
