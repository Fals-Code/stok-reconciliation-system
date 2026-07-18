---
title: "Product Requirements Document - Sistem Rekonsiliasi Stok"
document_id: "02-product-requirements"
version: "1.1.0"
status: "Phase 2 Synced - ADMIN Only"
last_updated: "2026-07-18"
language: "id-ID"
timezone: "Asia/Jakarta"
product_phase: "Phase 1 / MVP"
depends_on:
  - "stok-management-system.pdf"
  - "01-project-brief.md"
  - "06-user-roles-and-flows.md"
source_of_truth_order:
  - "VibeDev Phase 2 Sync Update v2, 13 Juni 2026"
  - "Keputusan bisnis eksplisit pada stok-management-system.pdf"
  - "Klarifikasi dan guardrail pada 01-project-brief.md"
  - "Keputusan produk terdokumentasi setelah PRD ini"
  - "06-user-roles-and-flows.md untuk keputusan role, approval, dan hak akses"
---

# Product Requirements Document: Sistem Rekonsiliasi Stok

> [!IMPORTANT]
> **Pemberitahuan perubahan model role**
>
> Keputusan produk terbaru menetapkan bahwa Fase 1 memiliki tepat satu role aplikasi, yaitu `ADMIN`.
> Seluruh definisi role, approval, dan hak akses pada dokumen ini tunduk pada
> [`06-user-roles-and-flows.md`](./06-user-roles-and-flows.md).
>
> Referensi lama terhadap `OPERATOR`, `VIEWER`, `WAREHOUSE_OPERATOR`,
> `OWNER_VIEWER`, atau pemisahan kemampuan berdasarkan role tidak lagi menjadi
> requirement aktif Fase 1. Beberapa akun Admin individual tetap diperbolehkan
> dan seluruh tindakan harus tetap dikaitkan dengan actor serta organisasi yang
> terautentikasi.

## 1. Tujuan Dokumen

Dokumen ini menerjemahkan `01-project-brief.md` dan brief klien menjadi persyaratan produk yang dapat:

1. Dipakai untuk menyusun backlog pengembangan.
2. Menjadi kontrak perilaku antara produk, desain, engineering, dan pengujian.
3. Menentukan apa yang wajib tersedia pada aplikasi fase 1.
4. Menjelaskan aturan bisnis yang tidak boleh berubah diam-diam selama implementasi.
5. Menjadi dasar acceptance test sebelum aplikasi dinyatakan siap didemonstrasikan atau digunakan.

Dokumen ini membahas **apa yang harus dilakukan produk dan bagaimana keberhasilannya dinilai**. Detail struktur database, komponen, deployment, dan keputusan implementasi mendalam akan dibahas pada dokumen arsitektur terpisah.

## 2. Ringkasan Produk

Produk adalah aplikasi web mandiri untuk mencatat dan merekonsiliasi stok sebuah brand skincare Indonesia dengan sekitar 70 produk hasil maklon, penjualan melalui Shopee dan TikTok Shop, ratusan paket keluar per hari, serta volume retur yang signifikan.

Masalah utama saat ini adalah stok pada spreadsheet hampir tidak pernah sama dengan stok fisik. Ketika stok opname menemukan selisih, organisasi hanya mengetahui angkanya, bukan rangkaian kejadian yang membentuknya. Kebocoran terutama muncul dari:

- Pesanan batal yang sudah terlanjur dianggap keluar.
- Retur yang kembali layak jual, rusak, atau hilang.
- Bonus, promo, dan sampel yang tidak terhubung dengan transaksi jelas.
- Saldo awal yang masih berupa perkiraan.

Produk harus menjadikan buku besar pergerakan stok sebagai pusat sistem. Semua perubahan fisik harus dapat ditelusuri ke aktor, waktu, produk, batch, alasan, kanal, dan referensi sumber.

> **Janji produk:** tidak ada angka stok yang berubah tanpa jejak.

## 3. Outcome Produk

### 3.1 Outcome Utama

Pengguna dapat menjelaskan posisi stok saat ini dengan menelusuri seluruh pergerakan yang membentuknya, bukan sekadar melihat angka saldo akhir.

### 3.2 Outcome Operasional

Pada fase 1, produk harus memungkinkan tim gudang untuk:

- Mengetahui stok tersedia per produk dan batch.
- Mencatat barang masuk dari maklon.
- Mereservasi barang untuk pesanan tanpa mengurangi stok fisik.
- Mengurangi stok hanya ketika barang benar-benar meninggalkan gudang.
- Mengalokasikan batch secara otomatis dengan FEFO.
- Menangani pembatalan dan retur tanpa menambah atau mengurangi stok secara semu.
- Mencatat bonus, promo, sampel, dan pengeluaran manual lain secara eksplisit.
- Melakukan stok opname dan memposting koreksi yang diaudit.
- Menemukan kejanggalan pencatatan melalui rekonsiliasi harian.

### 3.3 Indikator Keberhasilan Fase 1

| ID | Indikator | Target penerimaan |
|---|---|---|
| KPI-01 | Perubahan stok tanpa ledger | 0 kejadian pada seluruh skenario uji |
| KPI-02 | Skenario emas yang lulus | 100% dari skenario pada Bagian 37 |
| KPI-03 | Duplikasi event eksternal | 0 movement ganda untuk idempotency key yang sama |
| KPI-04 | Alokasi batch salah | 0 pada pengujian FEFO, split batch, kedaluwarsa, dan stok tidak cukup |
| KPI-05 | Saldo negatif | 0 saldo negatif yang dapat diposting melalui jalur resmi |
| KPI-06 | Drill-down transaksi | Seluruh saldo uji dapat ditelusuri sampai movement dan dokumen sumber |
| KPI-07 | Alur Admin | Penerimaan, outbound, retur, dan opname dapat diselesaikan tanpa akses database |
| KPI-08 | Deployment | Aplikasi live, seed demo tersedia, dan alur inti dapat dicoba langsung |

Target ini mengukur kebenaran sistem, bukan metrik kosmetik seperti jumlah tombol. Inventaris yang salah tetap salah meskipun tombolnya memiliki animasi yang sangat halus.

## 4. Prinsip Produk

### P-01. Ledger sebagai sumber kebenaran

Saldo harus diturunkan dari buku besar pergerakan atau proyeksi yang dapat direkonstruksi darinya. Tidak tersedia fitur untuk mengetik saldo akhir secara langsung.

### P-02. Append-only untuk transaksi yang diposting

Movement yang sudah diposting tidak boleh diedit atau dihapus. Kesalahan diperbaiki melalui reversal dan transaksi pengganti.

### P-03. Stok fisik dan reservasi dipisahkan

Reservasi mengurangi ketersediaan untuk dijual, tetapi tidak mengurangi stok fisik sampai barang meninggalkan gudang.

### P-04. Alasan dan kanal dipisahkan

Alasan menjelaskan **mengapa** barang bergerak. Kanal menjelaskan **dari mana** kejadian berasal.

### P-05. Kondisi retur ditentukan gudang

Marketplace dapat memberi informasi bahwa retur terjadi, tetapi kondisi fisik hanya ditetapkan setelah inspeksi gudang.

### P-06. Semua jalur masuk memakai logika domain yang sama

Simulator, impor CSV, dan API marketplace masa depan harus menghasilkan event kanonis dan diproses melalui aturan stok yang sama.

### P-07. Kebenaran lebih penting daripada kemudahan memaksa transaksi

Ketika invariant tidak terpenuhi, sistem harus menolak transaksi secara utuh dan menjelaskan penyebabnya.

### P-08. Antarmuka ditujukan untuk Admin operasional stok

Bahasa, urutan langkah, dan pesan kesalahan harus menggunakan istilah bisnis yang dapat dipahami tanpa pengetahuan teknis.

## 5. Definisi Istilah

| Istilah | Definisi |
|---|---|
| Produk | Barang dasar yang memiliki SKU dan dihitung dalam satuan unit |
| Batch | Kelompok stok produk dengan kode dan tanggal kedaluwarsa tertentu |
| Movement | Entri buku besar yang mencatat perubahan kuantitas fisik atau perpindahan bucket |
| Ledger | Kumpulan movement append-only yang menjadi dasar rekonstruksi saldo |
| On hand | Seluruh barang yang secara fisik masih berada di gudang |
| Sellable | Barang fisik yang layak dijual |
| Reserved | Komitmen sellable untuk pesanan yang belum keluar gudang |
| Available | Sellable dikurangi reserved aktif |
| Quarantine | Barang yang belum boleh dijual karena menunggu inspeksi atau identifikasi |
| Damaged | Barang rusak yang secara fisik masih berada di gudang |
| FEFO | First Expired, First Out; batch dengan kedaluwarsa terdekat digunakan lebih dahulu |
| Event kanonis | Bentuk standar kejadian marketplace setelah sumber asli dinormalisasi |
| Idempotency key | Identitas unik untuk mencegah kejadian yang sama diproses dua kali |
| Stok opname | Sesi perbandingan saldo sistem dengan hasil hitung fisik |
| Rekonsiliasi | Pemeriksaan konsistensi internal dan penelusuran penyebab selisih |
| Posting | Tindakan final yang menghasilkan movement dan tidak dapat diedit langsung |

## 6. Pengguna dan Hak Utama

### 6.1 Admin Operasional Stok

Fase 1 memiliki tepat satu role aplikasi:

```text
ADMIN
```

Sistem dapat memiliki beberapa akun Admin individual agar setiap mutation,
approval, posting, dan tindakan audit dapat dikaitkan dengan actor yang benar.

Admin dapat:

- melihat dashboard, posisi stok, batch, ledger, dan audit trail;
- mengelola produk, batch, bundle, kanal, alasan, dan mapping marketplace;
- mencatat receipt dan outbound manual;
- menjalankan simulator marketplace;
- menerima dan menginspeksi retur;
- menjalankan stocktake, review, approval, dan posting adjustment;
- menjalankan rekonsiliasi;
- membuat reversal sesuai invariant domain;
- meninjau dan mengelola notifikasi;
- mengelola akun Admin lain sesuai guardrail keamanan.

Hak Admin tidak mengizinkan:

- mengedit saldo secara langsung;
- mengubah atau menghapus ledger entry yang telah diposting;
- melewati FEFO pada outbound normal;
- memposting hasil `SELLABLE` ketika provenance batch asal belum terverifikasi;
- memakai `service_role` dari browser;
- melewati tenant isolation, RLS, idempotency, atau validasi domain.

### 6.2 Status bagian multi-role sebelumnya

Model multi-role pada versi awal PRD
telah **superseded**. Perbedaan tugas operasional tetap dapat dijalankan oleh
akun Admin yang berbeda, tetapi bukan melalui role aplikasi yang berbeda.

## 7. Prioritas Requirement

Setiap requirement menggunakan skala berikut:

- **Must:** wajib untuk fase 1 dan menjadi release gate.
- **Should:** penting dan diupayakan selesai pada fase 1, tetapi dapat ditunda hanya dengan keputusan produk terdokumentasi.
- **Could:** nilai tambah setelah semua Must stabil.
- **Won't:** sengaja tidak dikerjakan pada fase 1.

## 8. Matriks Hak Akses Ringkas

Matriks multi-role pada versi awal PRD telah **superseded**.

| Kemampuan | ADMIN |
|---|:---:|
| Melihat dashboard, stok, batch, ledger, dan audit trail | Ya |
| Mengelola produk, batch, bundle, kanal, dan alasan | Ya |
| Posting penerimaan | Ya |
| Posting outbound manual | Ya |
| Memproses event marketplace | Ya |
| Menerima dan menginspeksi retur | Ya |
| Membuat dan menjalankan stocktake | Ya |
| Review, approval, dan posting adjustment | Ya |
| Membuat reversal yang memenuhi invariant | Ya |
| Menjalankan simulator, import, dan rekonsiliasi | Ya |
| Mengelola akun Admin | Ya |

Seluruh kemampuan tetap dibatasi oleh autentikasi, status akun aktif,
organization scope, RLS, validation, idempotency, dan business rules. Satu role
bukan berarti satu akun dan bukan pula izin untuk melewati domain contract.

## 9. Cakupan Fase 1

### 9.1 Termasuk

- Autentikasi dan peran pengguna.
- Master produk dan batch.
- Saldo awal/cutover yang diaudit.
- Penerimaan barang dari maklon.
- Pesanan Shopee dan TikTok Shop melalui simulator dan CSV.
- Reservasi pesanan.
- Pengeluaran fisik sesuai status sumber.
- FEFO otomatis.
- Bundle sebagai resep produk satuan.
- Pembatalan sebelum dan setelah barang keluar.
- Barang keluar manual.
- Retur expected, penerimaan stock-neutral, pending inspection operasional, layak jual, rusak, dan hilang.
- Pengingat klaim TikTok sebelum tenggat tetap 40 hari sejak `operations.returns.created_at`.
- Notifikasi kedaluwarsa per batch.
- Stok opname, review, persetujuan, dan koreksi.
- Rekonsiliasi harian dan issue tracking.
- Ledger dan audit trail yang dapat di-drill.
- Deployment live dan seed demo.

### 9.2 Tidak Termasuk

- API langsung Shopee atau TikTok Shop.
- Harga, nilai persediaan, diskon nominal, margin, atau akuntansi.
- Purchase order lengkap.
- Forecasting permintaan.
- Perencanaan produksi maklon.
- Multi-warehouse kompleks.
- Stok bundle sebagai entitas.
- Aplikasi mobile native.
- Otomatisasi pengajuan klaim marketplace.
- Pengiriman, kurir, dan optimasi rute.

## 10. Requirement Autentikasi dan Pengguna

### AUTH-001 - Login pengguna

**Prioritas:** Must

Sistem harus menyediakan login untuk pengguna terdaftar.

**Acceptance criteria:**

- Pengguna dengan kredensial valid dapat masuk.
- Pengguna dengan kredensial tidak valid menerima pesan generik tanpa membocorkan keberadaan akun.
- Seluruh halaman operasional mengharuskan sesi autentikasi.
- Setelah logout, pengguna tidak dapat membuka kembali halaman terlindungi melalui tombol Back tanpa autentikasi ulang.

### AUTH-002 - Role pengguna

**Prioritas:** Must

Setiap profil pengguna aktif harus memiliki role aplikasi konstan `ADMIN`.

**Acceptance criteria:**

- UI tidak menyediakan pilihan role.
- Role aplikasi tidak dapat diubah menjadi role lain pada Fase 1.
- Akses tetap memerlukan autentikasi, profil aktif, dan organization scope yang valid.
- Seluruh mutation tetap tunduk pada RLS, authorization server-side, idempotency, dan business rules.
- Role infrastruktur seperti `anon`, `authenticated`, dan `service_role` bukan role aplikasi.
### AUTH-003 - Status akun

**Prioritas:** Must

Admin dapat mengaktifkan atau menonaktifkan akun tanpa menghapus histori pengguna.

**Acceptance criteria:**

- Akun nonaktif tidak dapat membuat sesi baru.
- Histori transaksi tetap menampilkan identitas akun yang telah nonaktif.
- Menonaktifkan akun menghasilkan audit event.

### AUTH-004 - Pengelolaan profil minimum

**Prioritas:** Should

Admin dapat mengatur nama tampilan dan status akun. Role aplikasi selalu
`ADMIN` dan tidak tersedia sebagai field yang dapat diedit.

Pengguna dapat melihat identitas, organisasi, status akun, dan role dirinya.
## 11. Requirement Master Produk dan Batch

### PRD-001 - Membuat produk

**Prioritas:** Must

Admin dapat membuat produk dengan minimal:

- SKU unik.
- Nama produk.
- Satuan dasar `unit`.
- Status aktif.
- Catatan opsional.

**Acceptance criteria:**

- SKU kosong atau duplikat ditolak.
- Produk baru tidak memiliki saldo sampai ada movement.
- Pembuatan produk tercatat pada audit trail.

### PRD-002 - Mengubah produk

**Prioritas:** Must

Admin dapat mengubah atribut non-historis produk.

**Acceptance criteria:**

- Perubahan SKU setelah produk memiliki transaksi memerlukan konfirmasi khusus atau dilarang sesuai keputusan implementasi.
- Perubahan nama tidak mengubah histori movement.
- Nilai sebelum dan sesudah tersimpan pada audit event.

### PRD-003 - Mengarsipkan produk

**Prioritas:** Must

Produk yang pernah memiliki transaksi tidak boleh dihapus permanen melalui UI.

**Acceptance criteria:**

- Produk diarsipkan menjadi tidak aktif.
- Produk tidak aktif tidak dapat digunakan pada transaksi baru.
- Histori tetap dapat dibuka.

### BAT-001 - Membuat batch

**Prioritas:** Must

Admin dapat membuat batch dengan:

- Produk.
- Kode batch.
- Tanggal kedaluwarsa.
- Tanggal penerimaan pertama bila tersedia.
- Status batch.

**Acceptance criteria:**

- Kombinasi produk dan kode batch harus unik.
- Tanggal kedaluwarsa wajib untuk produk yang dikelola pada fase 1.
- Pembuatan batch tidak menambah stok tanpa posting penerimaan atau saldo awal.

### BAT-002 - Status batch

**Prioritas:** Must

Batch harus mendukung sedikitnya status:

- `ACTIVE`.
- `BLOCKED`.
- `QUARANTINED`.
- `EXPIRED` sebagai status turunan atau efektif berdasarkan tanggal.
- `ARCHIVED`.

**Acceptance criteria:**

- Batch blocked, quarantined, expired, atau archived tidak dapat dialokasikan untuk penjualan.
- Perubahan status tercatat dengan actor, waktu, dan alasan.

### BAT-003 - Detail batch

**Prioritas:** Must

Halaman detail batch harus menampilkan:

- Produk dan kode batch.
- Tanggal kedaluwarsa.
- Saldo per bucket.
- Reserved aktif.
- Available.
- Riwayat movement.
- Referensi transaksi terkait.

### BAT-004 - Penelusuran batch

**Prioritas:** Must

Pengguna dapat mencari batch berdasarkan SKU, nama produk, kode batch, dan rentang kedaluwarsa.

## 12. Requirement Saldo Awal dan Cutover

### CUT-001 - Membuat sesi cutover

**Prioritas:** Must

Admin dapat membuat satu sesi saldo awal dengan tanggal dan waktu cutover.

**Acceptance criteria:**

- Sesi memiliki status `DRAFT`, `REVIEW`, dan `POSTED`.
- Satu environment produksi hanya boleh memiliki satu cutover aktif yang telah diposting, kecuali dilakukan reversal terkontrol.
- Tanggal cutover terlihat pada laporan.

### CUT-002 - Input saldo awal per batch dan kondisi

**Prioritas:** Must

Saldo awal harus dimasukkan per produk, batch, dan bucket fisik.

**Acceptance criteria:**

- Kuantitas harus bilangan bulat nol atau positif.
- Batch yang tidak diketahui tidak boleh dipalsukan; barang ditempatkan pada quarantine dengan referensi yang jelas.
- Preview menampilkan total per produk sebelum posting.

### CUT-003 - Posting saldo awal

**Prioritas:** Must

Posting cutover menghasilkan movement `INITIAL_BALANCE` untuk setiap baris bernilai lebih dari nol.

**Acceptance criteria:**

- Movement memiliki referensi sesi cutover.
- Posting atomik: seluruh baris berhasil atau seluruhnya gagal.
- Setelah posting, data tidak dapat diedit langsung.

### CUT-004 - Rekonsiliasi spreadsheet lama

**Prioritas:** Should

Sistem dapat menyimpan angka spreadsheet lama sebagai pembanding tanpa menjadikannya sumber saldo.

**Acceptance criteria:**

- Laporan menampilkan angka lama, hitung fisik, dan selisih.
- Selisih awal tidak disembunyikan melalui edit saldo.

## 13. Requirement Penerimaan Barang

### RCV-001 - Membuat draft penerimaan

**Prioritas:** Must

Admin dapat membuat penerimaan dari maklon dengan:

- Nomor referensi dokumen.
- Tanggal dan waktu diterima.
- Pemasok atau nama maklon opsional.
- Satu atau lebih item produk, batch, kedaluwarsa, kuantitas, dan bucket tujuan.
- Catatan.

### RCV-002 - Validasi penerimaan

**Prioritas:** Must

**Acceptance criteria:**

- Kuantitas setiap baris harus bilangan bulat lebih dari nol.
- Produk dan batch harus valid.
- Nomor referensi atau idempotency key yang sama tidak boleh diposting dua kali untuk sumber yang sama.
- Tanggal kedaluwarsa yang telah lewat memunculkan blokir atau konfirmasi admin; barang tidak boleh masuk sellable.

### RCV-003 - Preview sebelum posting

**Prioritas:** Must

Sistem menampilkan ringkasan perubahan saldo sebelum pengguna memposting.

**Acceptance criteria:**

- Preview menampilkan produk, batch, bucket, saldo sebelum, perubahan, dan saldo setelah.
- Preview tidak mengubah data.

### RCV-004 - Posting penerimaan

**Prioritas:** Must

Posting menambah bucket tujuan melalui movement inbound.

**Acceptance criteria:**

- Posting atomik untuk seluruh dokumen.
- Setiap movement memiliki actor, waktu bisnis, waktu sistem, alasan, kanal, dan referensi dokumen.
- Setelah posting, dokumen bersifat read-only.
- Sistem menampilkan nomor transaksi dan tautan ke ledger.

### RCV-005 - Reversal penerimaan

**Prioritas:** Should

Admin dapat membalik penerimaan yang salah selama stok terkait masih memungkinkan koreksi.

**Acceptance criteria:**

- Reversal menghasilkan movement lawan, bukan menghapus movement awal.
- Jika stok batch sudah digunakan sehingga reversal membuat saldo negatif, reversal ditolak dan pengguna diarahkan ke proses adjustment yang sesuai.

## 14. Requirement Bundle

### BND-001 - Membuat resep bundle

**Prioritas:** Must

Admin dapat mendefinisikan listing bundle per kanal dengan:

- Kode listing eksternal.
- Nama bundle.
- Kanal.
- Daftar produk komponen.
- Kuantitas unit per komponen.
- Versi dan tanggal berlaku.

### BND-002 - Validasi resep

**Prioritas:** Must

**Acceptance criteria:**

- Bundle minimal memiliki satu komponen.
- Kuantitas komponen harus bilangan bulat lebih dari nol.
- Produk komponen harus aktif saat resep dibuat.
- Kode listing unik dalam kanal dan periode berlaku.

### BND-003 - Ekspansi bundle

**Prioritas:** Must

Saat item pesanan bundle diterima, sistem mengekspansi bundle menjadi kebutuhan produk satuan.

**Acceptance criteria:**

- Tidak dibuat saldo bundle.
- Total kebutuhan sama dengan kuantitas bundle dikali resep.
- Ekspansi mendukung beberapa komponen.
- Hasil ekspansi terlihat pada detail pesanan.

### BND-004 - Snapshot resep

**Prioritas:** Must

Pesanan menyimpan versi atau snapshot resep yang dipakai.

**Acceptance criteria:**

- Perubahan resep setelah pesanan masuk tidak mengubah kebutuhan pesanan lama.
- Detail pesanan menunjukkan resep historis yang digunakan.

## 15. Requirement Ingestion Marketplace

### EVT-001 - Event kanonis

**Prioritas:** Must

Simulator dan impor harus menghasilkan event dengan atribut minimum:

- `source`.
- `external_event_id`.
- `event_type`.
- `occurred_at`.
- `external_order_id`.
- Payload sumber asli.
- Waktu diterima sistem.

### EVT-002 - Idempotensi event

**Prioritas:** Must

Kombinasi sumber dan external event ID harus unik.

**Acceptance criteria:**

- Event yang sama dapat dikirim ulang tanpa menghasilkan movement, reservasi, atau transisi ganda.
- Respons menunjukkan bahwa event telah diproses sebelumnya.
- Payload duplikat yang berbeda untuk ID sama ditandai sebagai konflik, bukan diam-diam ditimpa.

### EVT-003 - Penyimpanan payload asli

**Prioritas:** Must

Payload sumber asli disimpan untuk audit dan debugging, dengan pembatasan data sensitif sesuai kebutuhan.

### EVT-004 - Status pemrosesan event

**Prioritas:** Must

Event memiliki status sedikitnya:

- `RECEIVED`.
- `VALIDATED`.
- `PROCESSED`.
- `REJECTED`.
- `DUPLICATE`.
- `CONFLICT`.

**Acceptance criteria:**

- Event gagal menyimpan alasan yang dapat ditindaklanjuti.
- Event dapat dicari berdasarkan order, ID eksternal, tipe, status, dan waktu.

### EVT-005 - Pemrosesan ulang terkontrol

**Prioritas:** Should

Admin dapat memproses ulang event `REJECTED` setelah masalah data diperbaiki, tanpa melewati idempotensi.

## 16. Requirement Pesanan dan Reservasi

### ORD-001 - Membuat atau menerima pesanan

**Prioritas:** Must

Pesanan dapat masuk dari Shopee atau TikTok Shop melalui event simulator atau CSV.

Data minimum:

- Sumber marketplace.
- External order ID.
- Waktu pesanan.
- Status sumber.
- Daftar item asli.
- Produk satuan hasil mapping atau ekspansi bundle.

### ORD-002 - Keunikan pesanan

**Prioritas:** Must

External order ID harus unik dalam sumber marketplace.

### ORD-003 - Reservasi pada pesanan aktif

**Prioritas:** Must

Pesanan baru yang valid membuat reservasi untuk produk satuan, bukan movement outbound.

**Acceptance criteria:**

- On hand tidak berubah.
- Reserved bertambah.
- Available berkurang.
- Detail pesanan menunjukkan kuantitas reserved.
- Ledger fisik tidak memiliki outbound final.

### ORD-004 - Stok tidak cukup saat reservasi

**Prioritas:** Must

Jika available tidak mencukupi, sistem tidak membuat reservasi parsial secara diam-diam.

**Acceptance criteria:**

- Pesanan ditandai `STOCK_EXCEPTION` atau status ekuivalen.
- Kekurangan per produk ditampilkan.
- Tidak ada reserved negatif atau melebihi sellable.
- Admin/Admin dapat memproses setelah stok tersedia.

### ORD-005 - Timeline pesanan

**Prioritas:** Must

Detail pesanan menampilkan timeline event, status kanonis, status sumber, reservasi, alokasi batch, movement, retur, dan issue rekonsiliasi terkait.

### ORD-006 - Transisi status valid

**Prioritas:** Must

Sistem menolak transisi yang melompati atau bertentangan dengan state machine.

**Acceptance criteria:**

- Event out-of-order yang masih dapat direkonsiliasi disimpan dan ditangani deterministik.
- Transisi ilegal menghasilkan issue atau rejection dengan alasan.
- Histori status tidak ditimpa.

## 17. State Machine Pesanan

### 17.1 Status Kanonis

| Status | Makna |
|---|---|
| `RECEIVED` | Data pesanan diterima tetapi belum selesai divalidasi |
| `RESERVED` | Kebutuhan produk telah direservasi |
| `STOCK_EXCEPTION` | Reservasi gagal karena stok atau mapping tidak cukup |
| `READY` | Pesanan valid dan menunggu status keluar fisik |
| `PHYSICALLY_OUT` | Barang telah meninggalkan gudang dan outbound diposting |
| `CANCELLED_PRE_SHIPMENT` | Dibatalkan sebelum keluar; reservasi dilepas |
| `CANCELLED_POST_SHIPMENT` | Dibatalkan setelah keluar; stok belum kembali |
| `RETURN_EXPECTED` | Pengembalian diharapkan |
| `RETURN_IN_PROGRESS` | Retur sedang berjalan atau telah diterima sebagian |
| `CLOSED` | Siklus pesanan dan retur selesai |
| `EXCEPTION` | Memerlukan penanganan manual |

### 17.2 Trigger Keluar Fisik

| Sumber | Status sumber yang memicu outbound |
|---|---|
| Shopee | `SHIPPED` |
| TikTok Shop | `IN_TRANSIT` |

Status sumber asli tetap disimpan. Mapping dapat dikonfigurasi melalui kode, tetapi perubahan mapping adalah perubahan bisnis yang harus diuji dan didokumentasikan.

### 17.3 Aturan Pembatalan

- Pembatalan sebelum `PHYSICALLY_OUT` hanya melepaskan reservasi.
- Pembatalan setelah `PHYSICALLY_OUT` tidak membuat inbound.
- Pembatalan setelah keluar membuat proses `RETURN_EXPECTED` atau exception sesuai event sumber.

## 18. Requirement Pengeluaran Fisik dan FEFO

### OUT-001 - Posting outbound marketplace

**Prioritas:** Must

Saat status sumber mencapai trigger keluar fisik, sistem secara atomik:

1. Memvalidasi transisi.
2. Memastikan kebutuhan produk satuan.
3. Memvalidasi reservasi.
4. Mengalokasikan batch FEFO.
5. Melepaskan reservasi.
6. Membuat movement outbound per batch.
7. Menyimpan relasi item pesanan ke alokasi batch.
8. Mengubah status pesanan menjadi `PHYSICALLY_OUT`.

### OUT-002 - Urutan FEFO

**Prioritas:** Must

Urutan alokasi:

1. Tanggal kedaluwarsa paling dekat.
2. Tanggal penerimaan lebih awal.
3. ID batch sebagai tie-breaker deterministik.

Batch expired, blocked, quarantined, archived, atau tanpa available harus dilewati.

### OUT-003 - Split batch

**Prioritas:** Must

Jika satu batch tidak cukup, sistem membagi alokasi ke batch berikutnya.

**Acceptance criteria:**

- Total alokasi sama persis dengan kebutuhan.
- Setiap bagian menghasilkan movement per batch.
- Urutan FEFO dapat dilihat di detail transaksi.

### OUT-004 - Kegagalan atomik

**Prioritas:** Must

Jika total available tidak cukup atau terjadi konflik konkuren, seluruh posting gagal.

**Acceptance criteria:**

- Tidak ada movement parsial.
- Reservasi tidak hilang secara parsial.
- Status pesanan tidak berubah menjadi keluar.
- Pesan menyebut produk dan kekurangan kuantitas.

### OUT-005 - Proteksi proses konkuren

**Prioritas:** Must

Dua transaksi bersamaan tidak boleh mengalokasikan unit fisik yang sama.

**Acceptance criteria:**

- Pengujian konkuren tidak menghasilkan saldo negatif atau overselling.
- Konflik menghasilkan retry aman atau kegagalan yang dapat dipahami.

### OUT-006 - Traceability alokasi

**Prioritas:** Must

Dari item pesanan, pengguna dapat melihat batch mana yang digunakan. Dari batch, pengguna dapat melihat pesanan mana yang menggunakannya.

## 19. Requirement Barang Keluar Manual

### MAN-001 - Jenis pengeluaran manual

**Prioritas:** Must

Form pengeluaran manual mendukung sedikitnya:

- Penjualan offline.
- Bonus.
- Promo.
- Sampel.
- Barang rusak yang dikeluarkan/dimusnahkan.
- Barang kedaluwarsa yang dikeluarkan/dimusnahkan.

### MAN-002 - Alasan dan kanal wajib terpisah

**Prioritas:** Must

**Acceptance criteria:**

- Alasan tidak dapat diturunkan hanya dari kanal.
- Kanal default dapat `MANUAL`, tetapi alasan tetap wajib.
- Ledger menyimpan keduanya pada field terpisah.

### MAN-003 - Form transaksi

**Prioritas:** Must

Data minimum:

- Waktu kejadian.
- Alasan.
- Kanal.
- Produk dan kuantitas.
- Catatan.
- Referensi opsional atau wajib sesuai alasan.

### MAN-004 - FEFO untuk outbound umum

**Prioritas:** Must

Penjualan offline, bonus, promo, dan sampel menggunakan FEFO otomatis.

### MAN-005 - Pengeluaran batch tertentu

**Prioritas:** Must

Untuk pemusnahan rusak atau kedaluwarsa, pengguna memilih batch dan bucket sumber yang memang akan keluar fisik.

**Acceptance criteria:**

- Sistem hanya menawarkan batch dengan kuantitas pada bucket terkait.
- Kuantitas melebihi saldo ditolak.
- Tindakan tercatat sebagai outbound, bukan sekadar perubahan label.

### MAN-006 - Preview dan konfirmasi

**Prioritas:** Must

Sebelum posting, pengguna melihat alokasi batch dan dampak saldo.

### MAN-007 - Reversal outbound manual

**Prioritas:** Should

Admin dapat membalik transaksi salah melalui movement lawan yang mereferensikan transaksi awal.

## 20. Requirement Retur dan Klaim

### RET-001 - Membuat retur yang diharapkan

**Prioritas:** Must

Event marketplace atau input resmi dapat membuat retur yang mereferensikan pesanan dan item asal.

**Acceptance criteria:**

- Membuat retur tidak langsung menambah stok.
- Sistem menunjukkan kuantitas maksimal yang dapat diretur berdasarkan outbound asal.
- Retur duplikat tidak menghasilkan proses kedua untuk item yang sama tanpa alasan eksplisit.

### RET-002 - Menerima fisik retur

**Prioritas:** Must

Admin dapat menandai item retur telah tiba.

**Acceptance criteria:**

- Kuantitas diterima tidak boleh melebihi kuantitas yang diharapkan.
- Penerimaan hanya menambah `received_qty` dan `pending_inspection_qty` secara operasional.
- Penerimaan tidak membuat stock transaction, ledger entry, atau projection delta.
- Penerimaan menyimpan actor, waktu fisik, bukti opsional, dan provenance outbound bila tersedia.
- Retry identik tidak membuat penerimaan kedua; payload konflik ditolak.

### RET-003 - Inspeksi retur

**Prioritas:** Must

Admin memilih hasil per item:

- `SELLABLE`.
- `DAMAGED`.
- `LOST` hanya untuk item yang tidak pernah tiba.

**Acceptance criteria:**

- `SELLABLE` membuat tepat satu `RETURN_SELLABLE_INBOUND` ke batch baru dengan `batch_kind_code = RETURN`.
- Batch `RETURN` baru bukan batch outbound asal dan menyimpan provenance retur, produk, item order, serta hasil inspeksi.
- `DAMAGED` mencatat kondisi fisik untuk audit/klaim tanpa stock transaction, ledger entry, atau projection delta kedua.
- `LOST` tetap terpisah dari `DAMAGED` dan tidak menambah stok fisik.
- Mixed inspection hanya menambah stok sebesar kuantitas `SELLABLE`.
- Hasil inspeksi menyimpan actor, waktu, catatan, bukti opsional, dan idempotency contract.

### RET-004 - Batch retur dan provenance

**Prioritas:** Must

Batch outbound asal dipertahankan sebagai provenance, bukan tujuan inbound retur.

**Acceptance criteria:**

- Hasil `SELLABLE` hanya boleh diposting bila provenance batch asal terverifikasi.
- Provenance unknown tidak boleh direkayasa menjadi placeholder atau batch produksi.
- Hasil `DAMAGED` tetap dapat dicatat tanpa movement stok ketika provenance belum diketahui.
- Batch `RETURN` baru dibuat server-side dan diaudit.

### RET-005 - Retur parsial

**Prioritas:** Must

Sistem mendukung retur sebagian dari kuantitas yang dikirim.

**Acceptance criteria:**

- Total received, inspected, lost, dan pending tidak melebihi kuantitas retur.
- Status retur mencerminkan progres parsial.

### RET-006 - Retur hilang

**Prioritas:** Must

Item yang hilang dalam ekspedisi tidak menghasilkan inbound.

**Acceptance criteria:**

- Kasus kehilangan memiliki referensi pesanan, item, kuantitas, dan tanggal dasar klaim.
- Kasus dapat memicu pengingat klaim.

### CLM-001 - Tenggat klaim TikTok

**Prioritas:** Must

Sistem menghitung tenggat klaim TikTok tepat 40 hari kalender sejak `operations.returns.created_at`.

**Acceptance criteria:**

- Basis waktu selalu `operations.returns.created_at`, bukan receipt, inspection, lost, atau tanggal input manual.
- Tanggal dasar dan tanggal jatuh tempo terlihat.
- Perhitungan kalender dan tampilan menggunakan zona waktu `Asia/Jakarta`.
- Status klaim tidak membuat movement stok.

### CLM-002 - Status klaim

**Prioritas:** Must

Klaim memiliki status minimal:

- `NOT_STARTED`.
- `DUE_SOON`.
- `SUBMITTED`.
- `RESOLVED`.
- `EXPIRED`.

### CLM-003 - Notifikasi klaim

**Prioritas:** Must

Sistem menampilkan klaim yang mendekati tenggat berdasarkan ambang configurable.

### CLM-004 - Tanpa nilai uang

**Prioritas:** Must

Modul klaim tidak menyimpan atau menghitung nilai kompensasi pada fase 1.

## 21. State Machine Retur

| Status | Makna |
|---|---|
| `EXPECTED` | Retur dicatat tetapi barang belum tiba |
| `PARTIALLY_RECEIVED` | Sebagian barang telah tiba |
| `RECEIVED_PENDING_INSPECTION` | Barang tiba, tercatat operasional, dan belum memberi dampak stok |
| `PARTIALLY_INSPECTED` | Sebagian hasil inspeksi telah ditetapkan |
| `COMPLETED_SELLABLE` | Seluruh hasil layak jual |
| `COMPLETED_DAMAGED` | Seluruh hasil rusak |
| `COMPLETED_MIXED` | Hasil campuran |
| `LOST` | Barang tidak tiba dan ditetapkan hilang |
| `CLOSED` | Proses operasional selesai |
| `EXCEPTION` | Membutuhkan tindakan Admin |

Transisi dari `EXPECTED` langsung ke kondisi sellable tanpa penerimaan dan inspeksi harus ditolak.

## 22. Requirement Kedaluwarsa dan Notifikasi Batch

### EXP-001 - Perhitungan umur batch

**Prioritas:** Must

Sistem menghitung sisa hari kedaluwarsa berdasarkan tanggal operasional lokal.

### EXP-002 - Ambang notifikasi

**Prioritas:** Must

Default ambang adalah 90, 60, dan 30 hari, serta status telah kedaluwarsa.

**Acceptance criteria:**

- Admin dapat mengubah ambang untuk notifikasi berikutnya.
- Notifikasi tidak dibuat berulang setiap kali halaman dibuka.
- Batch tanpa saldo tidak perlu menghasilkan notifikasi aktif.

### EXP-003 - Batch kedaluwarsa tidak dapat dijual

**Prioritas:** Must

Batch yang tanggal kedaluwarsanya telah lewat tidak boleh masuk kandidat FEFO.

### EXP-004 - Daftar risiko kedaluwarsa

**Prioritas:** Must

Pengguna dapat memfilter batch berdasarkan rentang kedaluwarsa, produk, status, dan saldo.

### EXP-005 - Penanganan stok kedaluwarsa

**Prioritas:** Must

Stok kedaluwarsa yang masih fisik tetap terlihat sampai diposting sebagai pengeluaran/pemusnahan.

## 23. Requirement Ledger dan Posisi Stok

### LED-001 - Ledger append-only

**Prioritas:** Must

Movement yang telah diposting tidak dapat diedit atau dihapus melalui aplikasi.

### LED-002 - Atribut movement minimum

**Prioritas:** Must

Setiap movement menyimpan:

- ID unik.
- Produk.
- Batch.
- Bucket asal dan tujuan bila transfer.
- Kuantitas.
- Arah atau tipe movement.
- Alasan.
- Kanal.
- Referensi sumber dan ID sumber.
- Waktu kejadian bisnis.
- Waktu pencatatan sistem.
- Actor atau proses.
- ID reversal bila ada.

### LED-003 - Jenis movement minimum

**Prioritas:** Must

Sistem mendukung sedikitnya:

- `INITIAL_BALANCE`.
- `RECEIPT`.
- `OUTBOUND_MARKETPLACE`.
- `OUTBOUND_MANUAL`.
- `RETURN_SELLABLE_INBOUND`.
- `STOCKTAKE_ADJUSTMENT`.
- `REVERSAL`.
- `DISPOSAL_DAMAGED`.
- `DISPOSAL_EXPIRED`.

Nama teknis dapat berbeda selama makna dan auditabilitas tetap setara.

### LED-004 - Tampilan saldo

**Prioritas:** Must

Untuk setiap produk dan batch, sistem menampilkan:

- Sellable.
- Quarantine.
- Damaged.
- On hand.
- Reserved.
- Available.

### LED-005 - Rumus saldo

**Prioritas:** Must

- `on_hand = sellable + quarantine + damaged`.
- `available = sellable - reserved`.
- Nilai tidak boleh negatif melalui proses resmi.

### LED-006 - Filter ledger

**Prioritas:** Must

Ledger dapat difilter berdasarkan:

- Rentang waktu.
- SKU atau produk.
- Batch.
- Tipe movement.
- Alasan.
- Kanal.
- Referensi.
- Actor.

### LED-007 - Drill-down dua arah

**Prioritas:** Must

- Dari saldo ke movement pembentuk.
- Dari movement ke dokumen/pesanan/retur/opname sumber.
- Dari dokumen sumber kembali ke movement.

### LED-008 - Reversal

**Prioritas:** Must

Admin dapat membuat reversal melalui alur terkontrol.

**Acceptance criteria:**

- Movement awal tetap ada.
- Movement reversal mereferensikan movement awal.
- Reversal ganda untuk movement yang sama ditolak.
- Reversal yang melanggar saldo atau invariant ditolak.

### LED-009 - Export ledger

**Prioritas:** Should

Pengguna dapat mengekspor hasil filter ledger ke CSV tanpa mengubah data.

## 24. Requirement Stok Opname

### STK-001 - Membuat sesi opname

**Prioritas:** Must

Admin dapat membuat sesi opname dengan scope produk atau seluruh gudang.

### STK-002 - Status opname

**Prioritas:** Must

Status minimal:

- `DRAFT`.
- `COUNTING`.
- `REVIEW`.
- `APPROVED`.
- `POSTED`.
- `CANCELLED`.

### STK-003 - Snapshot saldo

**Prioritas:** Must

Ketika sesi dimulai, sistem menyimpan snapshot saldo per produk, batch, dan bucket pada timestamp yang jelas.

**Acceptance criteria:**

- Snapshot tidak berubah ketika transaksi operasional berikutnya terjadi.
- Laporan membedakan snapshot, movement setelah snapshot, dan hitung fisik bila transaksi tetap berjalan selama opname.

### STK-004 - Input hitung fisik

**Prioritas:** Must

Admin dapat mengisi kuantitas fisik per produk, batch, dan kondisi.

**Acceptance criteria:**

- Kuantitas bilangan bulat nol atau positif.
- Baris dapat disimpan sebagai draft.
- Produk atau batch tak dikenal dicatat sebagai exception, bukan otomatis membuat master tanpa kontrol.

### STK-005 - Impor hasil hitung

**Prioritas:** Should

Hasil hitung dapat diimpor melalui template CSV dengan preview dan validasi.

### STK-006 - Perhitungan selisih

**Prioritas:** Must

Sistem menghitung selisih antara expected balance pada titik perbandingan dan hitung fisik.

**Acceptance criteria:**

- Selisih ditampilkan per produk, batch, dan bucket.
- Sistem membedakan selisih positif dan negatif.
- Total ringkasan sama dengan detail.

### STK-007 - Review dan alasan koreksi

**Prioritas:** Must

Setiap selisih yang akan diposting wajib memiliki alasan atau catatan review.

### STK-008 - Persetujuan koreksi

**Prioritas:** Must

Koreksi hanya dapat disetujui Admin.

**Acceptance criteria:**

- Actor persetujuan dan waktu tersimpan.
- Sistem mencegah approval setelah data berubah tanpa review ulang.
- Kebijakan pemisahan pembuat dan penyetuju dapat diaktifkan.

### STK-009 - Posting koreksi

**Prioritas:** Must

Posting membuat movement adjustment per baris selisih.

**Acceptance criteria:**

- Posting atomik.
- Ledger sebelum posting tidak diubah.
- Sesi menjadi read-only setelah posted.
- Seluruh movement mereferensikan sesi opname.

### STK-010 - Laporan opname

**Prioritas:** Must

Laporan menampilkan:

- Snapshot sistem.
- Hitung fisik.
- Selisih.
- Adjustment.
- Alasan.
- Penghitung.
- Reviewer dan approver.
- Waktu setiap tahapan.

## 25. Requirement Rekonsiliasi Harian

### REC-001 - Menjalankan pemeriksaan

**Prioritas:** Must

Rekonsiliasi dapat dijalankan manual oleh Admin dan terjadwal setidaknya sekali per hari.

### REC-002 - Pemeriksaan minimum

**Prioritas:** Must

Sistem memeriksa sedikitnya:

1. Saldo proyeksi sama dengan penjumlahan ledger.
2. Tidak ada saldo negatif.
3. Tidak ada event eksternal diproses lebih dari sekali.
4. Total komponen bundle sesuai snapshot resep.
5. Total alokasi batch sama dengan kuantitas outbound.
6. Pesanan keluar fisik memiliki movement outbound.
7. Pesanan sebelum keluar tidak memiliki outbound final.
8. Receipt retur tetap stock-neutral; hanya hasil SELLABLE terinspeksi yang menambah stok melalui RETURN_SELLABLE_INBOUND ke batch RETURN baru.
9. Movement memiliki alasan, kanal, actor/proses, dan referensi valid.
10. Transisi status mengikuti state machine.
11. Reserved tidak melebihi sellable.
12. Reversal memiliki pasangan yang valid dan tidak ganda.

### REC-003 - Membuat issue rekonsiliasi

**Prioritas:** Must

Kegagalan pemeriksaan membuat issue dengan:

- Tipe rule.
- Severity.
- Deskripsi.
- Entitas terkait.
- Bukti atau nilai yang berbeda.
- Waktu terdeteksi.
- Status.

### REC-004 - Severity

**Prioritas:** Must

Severity minimal:

- `INFO`.
- `WARNING`.
- `HIGH`.
- `CRITICAL`.

Issue saldo negatif, movement ganda, atau outbound tanpa ledger harus `CRITICAL` atau `HIGH` sesuai dampak.

### REC-005 - Status issue

**Prioritas:** Must

Status minimal:

- `OPEN`.
- `INVESTIGATING`.
- `RESOLVED`.
- `ACCEPTED_RISK`.
- `FALSE_POSITIVE`.

### REC-006 - Penyelesaian issue

**Prioritas:** Must

Menutup issue wajib menyimpan actor, waktu, catatan, dan referensi tindakan koreksi bila ada.

### REC-007 - Drill-down issue

**Prioritas:** Must

Pengguna dapat membuka pesanan, retur, movement, batch, atau opname yang menyebabkan issue dari halaman issue.

### REC-008 - Issue berulang

**Prioritas:** Should

Rule yang masih gagal pada run berikutnya memperbarui kemunculan issue yang sama atau menghubungkan issue baru, tanpa memenuhi daftar dengan duplikat tak bermakna.

## 26. Requirement Simulator Marketplace

### SIM-001 - Skenario simulasi

**Prioritas:** Must

Simulator menyediakan tombol atau aksi untuk:

- Pesanan baru.
- Pesanan dikonfirmasi/siap.
- Shopee `SHIPPED`.
- TikTok `IN_TRANSIT`.
- Pembatalan sebelum keluar.
- Pembatalan setelah keluar.
- Retur dimulai.
- Retur diterima.
- Retur dinilai layak jual.
- Retur dinilai rusak.
- Retur hilang.
- Pengiriman event duplikat.

### SIM-002 - Jalur pemrosesan identik

**Prioritas:** Must

Simulator harus membuat event kanonis dan memanggil pipeline yang sama dengan impor/API masa depan.

**Acceptance criteria:**

- Simulator tidak menulis langsung ke saldo, reservasi, atau ledger.
- Event hasil simulasi terlihat pada event log.
- Semua rule idempotensi dan state transition tetap berlaku.

### SIM-003 - Data demo aman

**Prioritas:** Must

Simulator hanya tersedia pada environment demo atau bagi Admin dengan konfirmasi yang jelas.

### SIM-004 - Skenario deterministik

**Prioritas:** Should

Tersedia skenario demo terpandu dengan data dan hasil yang dapat diulang untuk presentasi acceptance test.

## 27. Requirement Impor CSV

### IMP-001 - Template impor

**Prioritas:** Must

Sistem menyediakan template CSV untuk tipe impor yang didukung.

Tipe minimum fase 1:

- Pesanan/event marketplace.
- Penerimaan barang.
- Hasil hitung opname, bila fitur STK-005 disertakan.

### IMP-002 - Upload dan preview

**Prioritas:** Must

Sebelum commit, sistem menampilkan:

- Jumlah baris.
- Baris valid.
- Baris invalid.
- Duplikat.
- Konflik mapping.
- Contoh hasil normalisasi.

### IMP-003 - Validasi file

**Prioritas:** Must

**Acceptance criteria:**

- Ekstensi, ukuran, encoding, header, tipe data, dan jumlah kolom divalidasi.
- Field tidak dikenal ditolak atau diabaikan secara eksplisit, bukan diam-diam mengubah mapping.
- Formula spreadsheet dan konten berbahaya tidak dieksekusi.

### IMP-004 - Commit impor

**Prioritas:** Must

Commit hanya memproses baris yang telah lolos validasi sesuai mode yang dipilih.

**Acceptance criteria:**

- Mode default fase 1 adalah all-or-nothing per batch impor untuk transaksi yang saling terkait.
- Tidak ada baris gagal yang dianggap sukses.
- Hasil commit menyimpan jumlah sukses, gagal, duplikat, dan konflik.

### IMP-005 - Idempotensi impor

**Prioritas:** Must

Setiap baris transaksi eksternal memiliki external event ID atau idempotency key.

### IMP-006 - Laporan kesalahan

**Prioritas:** Must

Pengguna dapat mengunduh CSV hasil validasi dengan nomor baris, field, kode kesalahan, dan pesan perbaikan.

### IMP-007 - Histori impor

**Prioritas:** Must

Sistem menyimpan siapa mengimpor, nama file, hash atau identitas file, waktu, tipe, status, dan ringkasan hasil.

## 28. Requirement Dashboard

### DSH-001 - Ringkasan utama

**Prioritas:** Must

Dashboard menampilkan:

- Total SKU aktif.
- Total sellable.
- Total reserved.
- Total available.
- Batch mendekati kedaluwarsa.
- Retur menunggu penerimaan.
- Retur menunggu inspeksi.
- Klaim mendekati tenggat.
- Issue rekonsiliasi terbuka berdasarkan severity.

### DSH-002 - Aktivitas terbaru

**Prioritas:** Should

Dashboard menampilkan movement dan transaksi terbaru dengan tautan detail.

### DSH-003 - Filter waktu

**Prioritas:** Should

Ringkasan aktivitas memiliki filter waktu yang jelas dan tidak mengubah kartu saldo saat ini secara ambigu.

### DSH-004 - Empty dan error state

**Prioritas:** Must

Dashboard membedakan belum ada data, hasil filter kosong, dan kegagalan memuat data.

## 29. Requirement Notifikasi

### NTF-001 - Jenis notifikasi

**Prioritas:** Must

Notifikasi fase 1 mencakup:

- Batch mendekati kedaluwarsa.
- Batch expired dengan saldo.
- Retur menunggu inspeksi.
- Klaim mendekati tenggat.
- Issue rekonsiliasi baru `HIGH` atau `CRITICAL`.

### NTF-002 - Pusat notifikasi

**Prioritas:** Must

Pengguna dapat melihat daftar notifikasi, status terbaca, tanggal, severity, dan tautan ke objek terkait.

### NTF-003 - Deduplication

**Prioritas:** Must

Sistem tidak membuat notifikasi aktif identik berulang untuk objek dan kondisi yang sama.

### NTF-004 - Mark as read

**Prioritas:** Should

Pengguna dapat menandai satu atau semua notifikasi sebagai dibaca tanpa mengubah status bisnis objek.

### NTF-005 - Kanal eksternal

**Prioritas:** Won't

Email, WhatsApp, atau push notification tidak wajib pada fase 1.

## 30. Requirement Audit Trail

### AUD-001 - Aktivitas yang diaudit

**Prioritas:** Must

Audit trail mencakup sedikitnya:

- Login penting dan kegagalan autentikasi yang relevan.
- Pembuatan/perubahan master.
- Posting transaksi.
- Reversal.
- Perubahan role dan status akun.
- Perubahan konfigurasi.
- Persetujuan opname.
- Penyelesaian issue rekonsiliasi.
- Impor dan simulator.

### AUD-002 - Atribut audit event

**Prioritas:** Must

- Actor atau proses.
- Waktu.
- Jenis aksi.
- Entitas dan ID.
- Ringkasan perubahan.
- Nilai sebelum dan sesudah untuk perubahan konfigurasi/master yang relevan.
- Correlation ID atau request ID.

### AUD-003 - Integritas audit

**Prioritas:** Must

Audit event tidak dapat diedit atau dihapus oleh pengguna aplikasi biasa.

### AUD-004 - Perlindungan data sensitif

**Prioritas:** Must

Password, token, secret, cookie sesi, dan payload sensitif tidak boleh ditampilkan atau dicatat mentah dalam audit log.

### AUD-005 - Pencarian audit

**Prioritas:** Should

Audit trail dapat difilter berdasarkan waktu, actor, jenis aksi, dan entitas.

## 31. Requirement Pengaturan

### CFG-001 - Ambang kedaluwarsa

**Prioritas:** Must

Admin dapat mengatur daftar hari pengingat kedaluwarsa.

### CFG-002 - Batas klaim

**Prioritas:** Must

Admin dapat mengatur jumlah hari klaim TikTok dan definisi tanggal dasar yang dipakai.

### CFG-003 - Alasan movement

**Prioritas:** Must

Admin dapat mengaktifkan/nonaktifkan alasan yang digunakan pada transaksi baru tanpa mengubah histori.

### CFG-004 - Kanal

**Prioritas:** Must

Kanal minimum: `SHOPEE`, `TIKTOK_SHOP`, `OFFLINE`, `MANUAL`, `IMPORT`, dan `SIMULATOR`.

Kanal teknis dan kanal bisnis dapat dimodelkan terpisah bila diperlukan, tetapi ledger harus tetap dapat menjawab asal kejadian.

### CFG-005 - Zona waktu dan satuan

**Prioritas:** Must

Fase 1 menggunakan zona waktu `Asia/Jakarta` dan kuantitas bilangan bulat dalam satuan unit.

## 32. Requirement Pengalaman Pengguna

### UX-001 - Bahasa antarmuka

**Prioritas:** Must

Antarmuka utama menggunakan bahasa Indonesia yang ringkas dan konsisten. Nama status teknis dapat memiliki label bisnis yang lebih mudah dipahami.

### UX-002 - Tindakan berisiko

**Prioritas:** Must

Posting, reversal, persetujuan adjustment, dan simulator massal memerlukan konfirmasi yang menjelaskan dampak.

### UX-003 - Pesan kesalahan operasional

**Prioritas:** Must

Pesan harus menyebutkan:

- Apa yang gagal.
- Mengapa gagal sejauh dapat dijelaskan.
- Objek atau baris yang terdampak.
- Langkah yang dapat dilakukan pengguna.

### UX-004 - Status tidak bergantung pada warna

**Prioritas:** Must

Setiap status memiliki teks atau ikon bermakna; warna hanya menjadi penguat.

### UX-005 - Navigasi keyboard

**Prioritas:** Should

Form inti dapat digunakan dengan keyboard dan urutan fokus logis.

### UX-006 - Tabel operasional

**Prioritas:** Must

Tabel utama menyediakan pencarian, filter, sort yang aman, pagination, loading state, empty state, dan error state.

### UX-007 - Umpan balik transaksi

**Prioritas:** Must

Transaksi sukses menampilkan nomor referensi, ringkasan perubahan, dan tautan ke detail/ledger.

### UX-008 - Pencegahan double submit

**Prioritas:** Must

Tombol posting tidak dapat menghasilkan transaksi ganda akibat klik berulang atau retry jaringan.

### UX-009 - Responsif

**Prioritas:** Should

Aplikasi dapat digunakan pada desktop dan tablet gudang. Optimasi mobile kecil tidak menjadi prioritas utama fase 1.

### UX-010 - Aksesibilitas

**Prioritas:** Should

Komponen inti ditargetkan memenuhi WCAG 2.2 Level AA yang relevan, terutama label form, fokus terlihat, penggunaan warna, kontras, pesan error, dan target interaksi.

## 33. Persyaratan Nonfungsional

### NFR-001 - Integritas transaksi

**Prioritas:** Must

Proses yang mengubah stok harus atomik. Kegagalan salah satu langkah membatalkan seluruh proses.

### NFR-002 - Konsistensi konkuren

**Prioritas:** Must

Alokasi stok bersamaan harus memakai mekanisme transaksi dan locking/isolation yang mencegah overselling.

### NFR-003 - Constraint data

**Prioritas:** Must

Invariant utama diperkuat dengan constraint database, foreign key, unique index, check constraint, atau fungsi transaksi, bukan hanya validasi client.

### NFR-004 - Row Level Security

**Prioritas:** Must

Seluruh tabel pada schema yang diekspos ke client menggunakan RLS dengan least privilege.

### NFR-005 - Secret management

**Prioritas:** Must

Service-role key dan secret server tidak boleh tersedia pada bundle browser, log client, atau repository.

### NFR-006 - Validasi input berlapis

**Prioritas:** Must

Input divalidasi pada UI untuk usability, pada boundary server untuk keamanan, dan pada database untuk integritas.

### NFR-007 - Performa halaman

**Prioritas:** Should

Pada dataset demo dan beban operasional fase 1:

- Halaman daftar utama ditargetkan menampilkan konten berguna dalam sekitar 2,5 detik pada koneksi kantor standar.
- Filter atau pagination tidak memuat seluruh ledger ke browser.
- Posting transaksi normal ditargetkan selesai dalam sekitar 3 detik, di luar gangguan jaringan.

Target merupakan sasaran produk, bukan izin untuk mengorbankan integritas transaksi demi angka benchmark.

### NFR-008 - Pagination dan indeks

**Prioritas:** Must

Ledger, pesanan, event, audit, dan notifikasi menggunakan pagination serta indeks sesuai pola pencarian.

### NFR-009 - Observability

**Prioritas:** Must

Error server memiliki correlation ID dan log teknis yang cukup untuk investigasi tanpa membocorkan secret.

### NFR-010 - Deployment reproducible

**Prioritas:** Must

Environment baru dapat dibangun dari source, migration, environment variable, dan seed terdokumentasi.

### NFR-011 - Backup dan pemulihan

**Prioritas:** Should

Sebelum penggunaan production, pemilik proyek harus mengaktifkan mekanisme backup yang sesuai paket Supabase dan mendokumentasikan prosedur restore serta uji pemulihan.

### NFR-012 - Data demo terpisah

**Prioritas:** Must

Reset seed demo tidak dapat dijalankan terhadap environment production tanpa proteksi eksplisit.

### NFR-013 - Kompatibilitas browser

**Prioritas:** Should

Aplikasi mendukung versi stabil terbaru Chrome dan Edge yang lazim digunakan pada perangkat kantor saat release.

### NFR-014 - Keamanan log

**Prioritas:** Must

Log keamanan dan audit harus terlindungi dari modifikasi pengguna biasa dan tidak menyimpan kredensial atau token mentah.

### NFR-015 - Pengujian database

**Prioritas:** Must

Constraint, database function, RLS, FEFO, idempotensi, reversal, dan saldo diuji otomatis.

### NFR-016 - Pengujian alur

**Prioritas:** Must

Tersedia integration/e2e test untuk penerimaan, reservasi, outbound, pembatalan, retur, opname, dan rekonsiliasi.

## 34. Model Data Produk yang Wajib Terwakili

Bagian ini bukan schema final, tetapi setiap konsep harus memiliki representasi yang jelas.

| Konsep | Tujuan |
|---|---|
| User/Profile/Role | Identitas dan otorisasi |
| Product | Master SKU |
| Batch | Identitas stok berkedaluwarsa |
| Stock Movement | Buku besar append-only |
| Stock Balance Projection | Pembacaan saldo cepat yang dapat direkonstruksi |
| Reservation | Komitmen pesanan sebelum keluar fisik |
| Receipt | Dokumen barang masuk |
| Marketplace Event | Event kanonis dan payload sumber |
| Order dan Order Item | Siklus pesanan dan produk asli |
| Expanded Order Item | Produk satuan hasil bundle/mapping |
| Bundle Recipe dan Version | Definisi paket dan histori |
| Batch Allocation | Relasi outbound dengan batch |
| Manual Outbound | Dokumen pengeluaran manual |
| Return dan Return Item | Siklus pengembalian |
| Inspection | Keputusan kondisi fisik retur |
| Claim Case | Tenggat dan status klaim |
| Stocktake Session dan Count | Snapshot, hitung, selisih, adjustment |
| Reconciliation Run dan Issue | Pemeriksaan dan kejanggalan |
| Import Job dan Import Row | Preview, validasi, hasil |
| Notification | Peringatan operasional |
| Audit Event | Jejak tindakan pengguna/proses |
| Configuration | Nilai bisnis yang dapat diubah |

## 35. Aturan Validasi Global

1. Kuantitas stok fase 1 selalu bilangan bulat.
2. Movement dengan kuantitas nol ditolak.
3. Produk dan batch pada movement harus valid.
4. Batch harus dimiliki produk yang sama dengan movement.
5. Tanggal dan waktu disimpan secara konsisten serta ditampilkan dalam `Asia/Jakarta`.
6. External ID dibatasi panjang dan formatnya; input berbahaya diperlakukan sebagai data, bukan dieksekusi.
7. Referensi transaksi yang wajib tidak dapat kosong.
8. Nilai enum tidak dikenal ditolak atau masuk jalur mapping exception.
9. Transaksi yang telah diposting tidak menerima update langsung.
10. Setiap request mutasi memiliki idempotency atau proteksi double submit yang sesuai.

## 36. State Machine Pendukung

### 36.1 Import Job

`UPLOADED -> VALIDATING -> READY -> COMMITTING -> COMPLETED`

Cabang kegagalan:

- `VALIDATION_FAILED`.
- `COMMIT_FAILED`.
- `CANCELLED` sebelum commit.

### 36.2 Reconciliation Issue

`OPEN -> INVESTIGATING -> RESOLVED`

Cabang keputusan:

- `ACCEPTED_RISK`.
- `FALSE_POSITIVE`.

Issue yang resolved tetapi rule kembali gagal dapat dibuka ulang atau dibuat issue baru yang tertaut.

### 36.3 Stocktake

`DRAFT -> COUNTING -> REVIEW -> APPROVED -> POSTED`

Cabang:

- `DRAFT/COUNTING/REVIEW -> CANCELLED`.
- Setelah `POSTED`, tidak ada transisi kembali.

## 37. Skenario Emas Acceptance Test

### AT-01 - Penerimaan barang

**Given** Produk A dan Batch A1 valid.
**When** Admin memposting penerimaan 100 unit ke sellable.
**Then** sellable dan on hand bertambah 100, ledger memiliki movement inbound, serta dokumen dapat ditelusuri dua arah.

### AT-02 - Pesanan baru hanya mereservasi

**Given** Produk A sellable 100 dan reserved 0.
**When** pesanan 10 unit diterima.
**Then** on hand tetap 100, reserved 10, available 90, dan belum ada outbound final.

### AT-03 - Pengiriman FEFO split batch

**Given** Batch A1 tersedia 5 dengan kedaluwarsa lebih dekat dan A2 tersedia 20.
**When** pesanan 10 unit mencapai trigger keluar.
**Then** sistem mengalokasikan 5 dari A1 dan 5 dari A2 serta membuat movement per batch.

### AT-04 - Pembatalan sebelum keluar

**Given** pesanan masih reserved.
**When** event pembatalan diterima.
**Then** reservasi dilepas dan tidak ada inbound maupun outbound fisik.

### AT-05 - Pembatalan setelah keluar

**Given** pesanan telah `PHYSICALLY_OUT`.
**When** event pembatalan diterima.
**Then** stok tidak langsung bertambah dan proses pengembalian dibuat.

### AT-06 - Retur layak jual

**Given** retur 2 unit diharapkan dan provenance outbound terverifikasi.
**When** barang diterima secara stock-neutral lalu diinspeksi sellable.
**Then** satu `RETURN_SELLABLE_INBOUND` menambah sellable 2 pada batch `RETURN` baru; batch outbound asal hanya menjadi provenance.

### AT-07 - Retur rusak

**Given** retur 1 unit telah diterima secara operasional.
**When** Admin menetapkan damaged.
**Then** kondisi damaged tercatat, sellable tidak bertambah, dan tidak ada stock transaction, ledger entry, atau projection delta kedua.

### AT-08 - Retur hilang

**Given** barang retur tidak pernah tiba.
**When** ditetapkan lost.
**Then** tidak ada inbound dan kasus klaim memiliki tenggat.

### AT-09 - Bonus manual

**Given** stok tersedia mencukupi.
**When** Admin mengeluarkan 3 unit dengan alasan bonus dan kanal manual.
**Then** outbound memakai FEFO dan ledger menyimpan alasan serta kanal terpisah.

### AT-10 - Bundle

**Given** satu bundle berisi 2 Produk A dan 1 Produk B.
**When** pesanan 3 bundle diterima.
**Then** kebutuhan menjadi 6 A dan 3 B tanpa membuat stok bundle.

### AT-11 - Duplikasi event

**Given** event pengiriman telah diproses.
**When** event dengan source dan external event ID sama dikirim lagi.
**Then** tidak terbentuk reservasi, alokasi, movement, atau status ganda.

### AT-12 - Stok tidak cukup

**Given** kebutuhan 10 dan available 8.
**When** posting outbound dijalankan.
**Then** seluruh proses gagal tanpa alokasi parsial atau perubahan saldo.

### AT-13 - Stok opname

**Given** expected balance 50 dan hitung fisik 47.
**When** koreksi disetujui dan diposting.
**Then** adjustment -3 dibuat, movement awal tetap ada, dan laporan menyimpan approver.

### AT-14 - Rekonsiliasi menemukan outbound tanpa movement

**Given** data uji mengandung pesanan keluar tanpa ledger.
**When** rekonsiliasi dijalankan.
**Then** issue severity tinggi dibuat dan dapat dibuka ke pesanan terkait.

### AT-15 - Dua pengiriman bersamaan

**Given** available hanya cukup untuk satu dari dua transaksi bersamaan.
**When** kedua transaksi diposting secara konkuren.
**Then** maksimal satu berhasil dan saldo tidak negatif.

### AT-16 - Batch kedaluwarsa dilewati

**Given** batch terdekat telah expired dan batch berikutnya masih valid.
**When** FEFO dijalankan.
**Then** batch expired tidak digunakan.

### AT-17 - Reversal tidak menghapus histori

**Given** satu movement inbound valid.
**When** Admin membalik transaksi.
**Then** movement awal dan reversal keduanya tetap terlihat serta saldo bersih sesuai.

### AT-18 - Impor campuran valid dan invalid

**Given** file memiliki baris valid, invalid, dan duplikat.
**When** validasi dijalankan.
**Then** hasil per baris jelas dan tidak ada data berubah sebelum commit.

## 38. Release Gates Fase 1

Release tidak boleh dinyatakan selesai apabila salah satu kondisi berikut masih ada:

1. Ada jalur resmi yang dapat mengubah saldo tanpa ledger.
2. Skenario AT-01 sampai AT-18 belum lulus.
3. RLS belum aktif atau belum diuji pada tabel exposed.
4. Event duplikat masih dapat menghasilkan movement ganda.
5. Proses konkuren dapat menghasilkan saldo negatif.
6. Movement posted masih dapat diedit atau dihapus melalui aplikasi.
7. Simulator menulis langsung ke saldo atau memakai logika terpisah.
8. Database tidak dapat dibangun ulang dari migration.
9. Seed demo tidak dapat menjalankan alur utama.
10. Aplikasi belum tersedia pada deployment live.
11. Admin tidak dapat melihat alasan kegagalan transaksi.
12. Drill-down dari saldo ke dokumen sumber belum berfungsi.

## 39. Urutan Implementasi yang Disarankan

Urutan ini mengurangi risiko membangun banyak layar di atas logika stok yang belum benar:

1. Autentikasi, role, migration, dan test harness.
2. Produk, batch, ledger, saldo projection, dan audit.
3. Penerimaan dan saldo awal.
4. Reservasi, pesanan, bundle, dan event kanonis.
5. FEFO dan outbound atomik.
6. Pembatalan dan reversal.
7. Retur, quarantine, damaged, lost, dan klaim.
8. Outbound manual.
9. Stok opname.
10. Rekonsiliasi harian.
11. CSV import dan simulator.
12. Dashboard, notifikasi, hardening UX, dan deployment demo.

CRUD produk memang lebih mudah dipamerkan pada hari pertama, tetapi engine stok adalah bagian yang menentukan apakah proyek ini aplikasi inventaris atau spreadsheet yang memakai kostum Next.js.

## 40. Traceability ke Brief Sumber

| Arah sumber | Requirement terkait |
|---|---|
| Produk dan batch dengan kedaluwarsa | PRD-001 sampai BAT-004, EXP-001 sampai EXP-005 |
| Ledger sebagai pusat | LED-001 sampai LED-009 |
| Barang masuk maklon | RCV-001 sampai RCV-005 |
| Keluar manual | MAN-001 sampai MAN-007 |
| Pesanan, pembatalan, retur marketplace | EVT, ORD, OUT, RET, CLM |
| Pengingat klaim 40 hari | CLM-001 sampai CLM-004 |
| Stok opname | STK-001 sampai STK-010 |
| Rekonsiliasi dan drill-down | REC-001 sampai REC-008, LED-007 |
| Tanpa API langsung, gunakan simulasi dan impor | SIM-001 sampai SIM-004, IMP-001 sampai IMP-007 |
| Tanpa harga | Bagian 9.2 dan CLM-004 |
| Keluar saat Shopee SHIPPED / TikTok IN_TRANSIT | Bagian 17.2, OUT-001 |
| Alasan dan kanal terpisah | P-04, MAN-002, LED-002 |
| FEFO otomatis | OUT-002 sampai OUT-006 |
| Bundle dihitung satuan | BND-001 sampai BND-004 |
| Dua ritme rekonsiliasi | REC dan STK |
| Kondisi retur diputuskan gudang | P-05, RET-002 sampai RET-004 |
| Stack Next.js + TypeScript + Supabase | NFR dan rujukan teknis |
| Produk live dan mudah dipakai Admin | KPI-07, KPI-08, UX, Release Gates |

## 41. Asumsi Fase 1

1. Satu gudang fisik.
2. Seluruh kuantitas berbentuk unit integer.
3. Tidak ada pencatatan harga.
4. Zona waktu operasional `Asia/Jakarta`.
5. Stok negatif dilarang.
6. Pengeluaran normal menggunakan FEFO otomatis.
7. Koreksi opname memerlukan Admin.
8. Provenance batch asal yang belum terverifikasi memblokir hasil SELLABLE; DAMAGED tetap audit-only tanpa movement stok.
9. CSV adalah format impor awal.
10. Default ambang kedaluwarsa 90, 60, dan 30 hari.
11. Tenggat klaim TikTok adalah 40 hari kalender sejak operations.returns.created_at.
12. Master yang sudah dipakai diarsipkan, bukan dihapus.
13. Status marketplace pada brief diperlakukan sebagai keputusan bisnis klien, bukan hasil inferensi API.

## 42. Pertanyaan Terbuka

| ID | Pertanyaan | Dampak jika belum diputuskan | Pemilik keputusan |
|---|---|---|---|
| OQ-02 | Apakah barcode atau kode batch selalu terbaca pada retur? | Verifikasi provenance dan kelayakan hasil `SELLABLE` | Operasional Gudang |
| OQ-03 | Apakah adjustment di atas ambang tertentu perlu dua approver? | Hak akses dan workflow | Klien/Product |
| OQ-04 | Apakah stok rusak tetap disimpan sampai pemusnahan? | Bucket dan outbound rusak | Operasional Gudang |
| OQ-05 | Format ekspor Shopee dan TikTok yang benar-benar tersedia? | Mapping CSV | Klien/Engineering |
| OQ-06 | Apakah transaksi operasional dihentikan saat opname? | Rumus expected balance | Operasional Gudang |
| OQ-07 | Berapa batas ukuran file impor fase 1? | UX, validasi, dan performa | Engineering/Product |
| OQ-08 | Apakah Admin boleh memproses ulang event gagal? | Permission dan audit | Product |
| OQ-09 | Apakah lokasi rak/bin diperlukan pada fase 1? | Model batch dan counting | Klien/Product |
| OQ-10 | Toleransi selisih apa yang dianggap kritis per produk? | Severity rekonsiliasi | Klien/Product |

Pertanyaan terbuka tidak boleh dijawab sepihak di kode lalu ditemukan tiga minggu kemudian saat demo, sebuah pola pengembangan yang entah mengapa masih populer.

## 43. Definition of Done Produk

Fase 1 dinyatakan selesai ketika:

- Semua requirement `Must` telah diimplementasikan atau memiliki waiver tertulis.
- Seluruh release gate terpenuhi.
- AT-01 sampai AT-18 lulus pada environment yang setara deployment.
- Database dapat dibangun dari migration dan seed.
- RLS dan hak role memiliki automated test.
- Simulator, CSV, dan event processor menggunakan pipeline yang sama.
- README menjelaskan setup, environment variable, migration, seed, testing, dan deployment.
- Data demo mencakup normal flow dan kasus selisih.
- Admin dapat menyelesaikan penerimaan, pengiriman, retur, dan opname tanpa bantuan developer.
- Admin dapat menjelaskan saldo uji melalui drill-down tanpa akses teknis.
- Tidak ada secret atau service-role key di client bundle atau repository.

## 44. Rujukan Teknis Resmi

Rujukan berikut mendukung requirement teknis dan nonfungsional. Rujukan ini tidak menggantikan keputusan bisnis pada brief klien.

1. Next.js, **Route Handlers**
   https://nextjs.org/docs/app/getting-started/route-handlers

2. Next.js, **App Router**
   https://nextjs.org/docs/app

3. Supabase, **Use Supabase Auth with Next.js**
   https://supabase.com/docs/guides/auth/quickstarts/nextjs

4. Supabase, **Row Level Security**
   https://supabase.com/docs/guides/database/postgres/row-level-security

5. Supabase, **Securing Your API**
   https://supabase.com/docs/guides/api/securing-your-api

6. Supabase, **Database Functions**
   https://supabase.com/docs/guides/database/functions

7. Supabase, **Testing Overview**
   https://supabase.com/docs/guides/local-development/testing/overview

8. PostgreSQL, **Transaction Isolation**
   https://www.postgresql.org/docs/current/transaction-iso.html

9. PostgreSQL, **Explicit Locking**
   https://www.postgresql.org/docs/current/explicit-locking.html

10. W3C WAI, **WCAG 2.2 Quick Reference**
    https://www.w3.org/WAI/WCAG22/quickref/

11. OWASP, **Input Validation Cheat Sheet**
    https://cheatsheetseries.owasp.org/cheatsheets/Input_Validation_Cheat_Sheet.html

12. OWASP, **Logging Cheat Sheet**
    https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html

## 45. Sumber Proyek

Dokumen ini disusun dari:

- `stok-management-system.pdf`, terutama masalah stok, cakupan fitur, batasan fase 1, keputusan FEFO, status keluar marketplace, bundle, retur, rekonsiliasi, stack, dan urutan penilaian.
- `01-project-brief.md`, terutama prinsip domain, model stok, asumsi, acceptance scenario, risiko, dan guardrail implementasi.

Apabila terjadi konflik, keputusan bisnis eksplisit pada brief sumber memiliki prioritas tertinggi sampai klien menyetujui perubahan tertulis.
