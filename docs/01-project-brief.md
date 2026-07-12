---
title: "Project Brief - Sistem Rekonsiliasi Stok"
document_id: "01-project-brief"
version: "1.0.0"
status: "Draft for Phase 1 Planning"
last_updated: "2026-07-12"
language: "id-ID"
timezone: "Asia/Jakarta"
source_of_truth: "stok-management-system.pdf"
---

# Project Brief: Sistem Rekonsiliasi Stok

## 1. Ringkasan Proyek

Proyek ini membangun aplikasi web mandiri untuk pencatatan dan rekonsiliasi stok sebuah brand skincare Indonesia yang memiliki sekitar 70 produk hasil maklon, berjualan melalui Shopee dan TikTok Shop, serta memproses ratusan paket keluar setiap hari.

Masalah utama bukan sekadar adanya selisih antara stok pada spreadsheet dan barang fisik di gudang. Masalah yang lebih mendasar adalah tidak tersedianya jejak yang dapat menjelaskan **kapan, mengapa, melalui kanal apa, dan akibat kejadian apa stok berubah**. Selisih baru terlihat ketika stok opname dilakukan setiap 1-3 bulan, sementara penyebabnya sudah tersebar di pembatalan pesanan, retur, bonus, promo, sampel, barang rusak, barang kedaluwarsa, dan stok awal yang belum akurat.

Aplikasi fase pertama harus membuktikan bahwa setiap perubahan stok dapat dicatat, diaudit, dan ditelusuri sampai ke kejadian pembentuknya. Sistem bukan aplikasi akuntansi dan tidak mencatat harga atau nilai uang.

> **Prinsip produk:** tidak ada angka stok yang berubah tanpa jejak.

## 2. Pernyataan Masalah

Pencatatan stok saat ini dilakukan secara manual menggunakan spreadsheet. Cara ini menimbulkan beberapa kegagalan operasional:

1. Pesanan dapat tercatat keluar meskipun kemudian dibatalkan, tetapi stok tidak dikembalikan secara benar.
2. Retur memiliki hasil berbeda, yaitu layak jual, rusak, atau hilang di ekspedisi, tetapi status fisik dan dampaknya terhadap stok tidak tercatat konsisten.
3. Bonus, promo, dan sampel keluar dari gudang tanpa referensi transaksi yang jelas dan menjadi sumber selisih terbesar.
4. Stok awal masih berupa perkiraan sehingga selisih dapat sudah ada sebelum transaksi baru diproses.
5. Stok opname hanya menemukan besarnya selisih, bukan rangkaian kejadian yang menyebabkannya.

Akibatnya, tim tidak dapat menjawab pertanyaan dasar seperti:

- Mengapa stok produk tertentu berkurang?
- Pesanan, retur, atau aktivitas manual mana yang membentuk selisih?
- Batch mana yang seharusnya masih tersedia?
- Apakah selisih berasal dari kesalahan pencatatan, proses gudang, atau kehilangan barang?
- Apakah suatu retur benar-benar sudah kembali secara fisik dan telah diperiksa?

## 3. Visi Produk

Menjadi sumber kebenaran tunggal untuk seluruh pergerakan kuantitas barang, sehingga posisi stok saat ini dapat dijelaskan melalui rangkaian kejadian yang lengkap, konsisten, dan dapat diaudit.

## 4. Tujuan Fase 1

Fase pertama bertujuan untuk:

1. Mencatat seluruh pergerakan stok masuk, keluar, reservasi, retur, dan koreksi melalui mekanisme yang konsisten.
2. Menyediakan buku besar stok sebagai sumber utama perhitungan saldo.
3. Mengalokasikan barang keluar ke batch secara otomatis menggunakan FEFO.
4. Memisahkan alasan pergerakan dari kanal pencatatannya.
5. Menangani siklus pesanan marketplace tanpa integrasi API langsung melalui simulasi dan impor file.
6. Menangani retur berdasarkan hasil inspeksi gudang.
7. Membandingkan stok sistem dengan hasil hitung fisik melalui stok opname.
8. Menjelaskan selisih melalui drill-down dari saldo hingga transaksi dan pergerakan pembentuknya.
9. Menyediakan aplikasi live yang mudah digunakan operator gudang.

## 5. Indikator Keberhasilan

Fase 1 dinyatakan berhasil apabila:

- 100% perubahan kuantitas menghasilkan entri buku besar yang memiliki waktu, produk, batch, kuantitas, jenis pergerakan, alasan, kanal, referensi sumber, dan pelaku.
- Tidak ada fitur yang dapat mengubah saldo stok secara langsung tanpa menulis ke buku besar.
- Seluruh skenario uji utama pada Bagian 18 dapat diselesaikan tanpa menghasilkan saldo yang salah.
- Pengiriman mengalokasikan batch FEFO dengan benar dan tidak dapat membuat stok tersedia menjadi negatif.
- Kejadian yang sama tidak menghasilkan pergerakan ganda ketika disimulasikan atau diimpor ulang.
- Selisih hasil opname dapat ditelusuri ke saldo sebelum hitung fisik, hasil hitung, koreksi, dan pihak yang menyetujui.
- Operator dapat menemukan riwayat perubahan sebuah produk atau batch tanpa membaca database atau log teknis.
- Aplikasi dapat diakses melalui deployment live dan alur utama dapat didemonstrasikan menggunakan data dummy.

## 6. Pengguna dan Peran

### 6.1 Admin

Bertanggung jawab atas konfigurasi sistem dan kontrol data utama.

Hak utama:

- Mengelola pengguna dan peran.
- Mengelola produk, batch, resep bundle, alasan pergerakan, kanal, dan ambang notifikasi.
- Menyetujui koreksi stok opname.
- Menjalankan simulasi, impor, rekonsiliasi, dan melihat seluruh audit trail.

### 6.2 Operator Gudang

Bertanggung jawab atas aktivitas fisik barang sehari-hari.

Hak utama:

- Mencatat barang masuk.
- Mencatat barang keluar manual.
- Memproses pengiriman pesanan.
- Menerima dan memeriksa retur.
- Mengisi hasil hitung fisik pada stok opname.
- Melihat stok, batch, notifikasi, dan riwayat yang relevan.

Operator tidak memilih batch saat barang keluar. Sistem melakukan alokasi FEFO.

### 6.3 Owner atau Viewer

Bertanggung jawab memantau kondisi stok dan kejanggalan tanpa mengubah transaksi operasional.

Hak utama:

- Melihat dashboard, posisi stok, rekonsiliasi, notifikasi, dan audit trail.
- Mengekspor laporan yang tersedia.

## 7. Prinsip Domain yang Tidak Boleh Dilanggar

### 7.1 Buku Besar Bersifat Append-Only

Entri pergerakan yang sudah diposting tidak diedit atau dihapus. Kesalahan diperbaiki melalui transaksi pembalik dan transaksi pengganti yang saling mereferensikan.

### 7.2 Saldo Merupakan Hasil Perhitungan

Saldo stok bukan angka bebas yang dapat diedit. Saldo dihitung dari buku besar atau dari proyeksi/materialized balance yang selalu dapat direkonstruksi dari buku besar.

### 7.3 Setiap Pergerakan Memiliki Identitas

Setiap entri minimal menyimpan:

- Produk.
- Batch.
- Kuantitas bertanda positif atau negatif.
- Bucket atau kondisi stok.
- Jenis pergerakan.
- Alasan bisnis.
- Kanal asal.
- Referensi sumber.
- Waktu kejadian bisnis.
- Waktu pencatatan sistem.
- Pengguna atau proses yang membuatnya.
- Idempotency key untuk kejadian eksternal atau impor.

### 7.4 Alasan dan Kanal Dipisahkan

`alasan` menjelaskan mengapa barang bergerak, sedangkan `kanal` menjelaskan dari jalur mana kejadian masuk.

Contoh:

- Alasan: `SALE`; kanal: `SHOPEE`.
- Alasan: `BONUS`; kanal: `MANUAL`.
- Alasan: `SAMPLE`; kanal: `MANUAL`.
- Alasan: `RETURN_SELLABLE`; kanal: `TIKTOK_SHOP`.

### 7.5 Tidak Ada Stok Negatif

Sistem menolak transaksi keluar apabila stok layak jual yang tersedia tidak mencukupi. Kegagalan harus tampil sebagai pesan yang dapat dipahami operator, bukan sekadar error database yang tampak seperti kutukan mesin kuno.

### 7.6 Proses Majemuk Harus Atomik

Perubahan status pesanan, pelepasan reservasi, alokasi FEFO, dan penulisan buku besar harus berhasil seluruhnya atau gagal seluruhnya.

## 8. Model Stok Konseptual

Sistem membedakan bucket fisik dan komitmen pesanan.

### 8.1 Bucket Fisik

| Bucket | Makna | Dapat dijual |
|---|---|---:|
| `SELLABLE` | Barang fisik layak jual | Ya |
| `QUARANTINE` | Barang menunggu inspeksi atau identifikasi | Tidak |
| `DAMAGED` | Barang rusak yang masih berada secara fisik di gudang | Tidak |

### 8.2 Reservasi

`RESERVED` bukan pergerakan barang fisik. Reservasi adalah komitmen kuantitas `SELLABLE` untuk pesanan yang belum mencapai status keluar gudang. Karena itu, membuat atau melepaskan reservasi tidak menulis movement outbound final.

Definisi posisi stok:

- **On hand fisik:** `SELLABLE + QUARANTINE + DAMAGED`.
- **Reserved:** total reservasi aktif yang belum dilepas atau dikonversi menjadi outbound.
- **Tersedia untuk dijual:** `SELLABLE - RESERVED`.
- **Keluar fisik:** kuantitas yang telah diposting sebagai movement outbound dan tidak lagi termasuk on hand.

Implementasi tabel dapat berbeda selama makna bisnis tersebut tetap terjaga, reservasi tidak dihitung ganda, dan saldo fisik dapat direkonstruksi dari buku besar.

## 9. Aturan Bisnis Utama

### 9.1 Produk dan Batch

- Setiap produk memiliki SKU unik, nama, status aktif, dan satuan dasar `unit`.
- Batch memiliki kode unik dalam konteks produk, tanggal masuk, tanggal kedaluwarsa, dan status.
- Pergerakan stok fisik harus mereferensikan batch.
- Batch kedaluwarsa tidak boleh dialokasikan untuk pengiriman.
- Batch yang diblokir atau berada dalam karantina tidak boleh digunakan untuk penjualan.

### 9.2 Saldo Awal dan Cutover

- Implementasi dimulai dengan sesi saldo awal yang memiliki tanggal cutover yang jelas.
- Pilihan utama adalah melakukan hitung fisik per produk, batch, dan kondisi sebelum operasional dimulai.
- Setiap saldo awal diposting sebagai movement `INITIAL_BALANCE`, sehingga titik awal sistem tetap memiliki jejak.
- Data spreadsheet lama dapat digunakan sebagai pembanding atau bahan impor, tetapi tidak otomatis dianggap benar.
- Selisih antara spreadsheet lama dan hitung fisik dicatat dalam laporan cutover, bukan disembunyikan melalui pengeditan saldo.
- Barang yang batch-nya belum dapat dipastikan masuk ke `QUARANTINE` sampai diverifikasi.
- Setelah cutover diposting, perubahan saldo awal hanya dilakukan melalui reversal atau adjustment yang diaudit.

### 9.3 Barang Masuk dari Maklon

- Penerimaan mencatat dokumen sumber, tanggal terima, produk, batch, tanggal kedaluwarsa, dan kuantitas.
- Posting penerimaan menambah bucket `SELLABLE`, kecuali admin memilih `QUARANTINE` karena pemeriksaan belum selesai.
- Pengulangan input dengan referensi atau idempotency key yang sama harus ditolak atau dikenali sebagai kejadian yang sudah diproses.

### 9.4 Reservasi Pesanan

- Pesanan baru atau terkonfirmasi membuat reservasi, bukan pengeluaran fisik.
- Reservasi tidak menulis outbound final ke buku besar.
- Reservasi mengurangi kuantitas yang tersedia untuk pesanan lain.
- Pembatalan sebelum barang keluar hanya melepaskan reservasi.

### 9.5 Barang Keluar Marketplace

- Shopee dianggap keluar fisik pada status `SHIPPED`.
- TikTok Shop dianggap keluar fisik pada status `IN_TRANSIT`.
- Pada saat keluar fisik, sistem secara atomik:
  1. Memvalidasi transisi status.
  2. Memecah bundle menjadi produk satuan.
  3. Mengalokasikan batch FEFO.
  4. Melepaskan reservasi terkait.
  5. Menulis pergerakan outbound per batch.
  6. Menyimpan relasi antara item pesanan dan alokasi batch.

### 9.6 FEFO

- Batch dengan tanggal kedaluwarsa paling dekat dialokasikan terlebih dahulu.
- Batch kedaluwarsa, diblokir, karantina, atau tidak memiliki stok tersedia harus dilewati.
- Jika satu batch tidak mencukupi, kuantitas dibagi ke beberapa batch secara berurutan.
- Jika total stok tidak mencukupi, seluruh transaksi gagal dan tidak boleh meninggalkan alokasi parsial.
- Untuk tanggal kedaluwarsa yang sama, urutan kedua adalah tanggal penerimaan lebih awal, lalu ID batch sebagai tie-breaker deterministik.

### 9.7 Bundle

- Bundle tidak memiliki stok sendiri.
- Admin mendefinisikan resep bundle sebagai daftar produk komponen dan jumlah unit.
- Saat data pesanan masuk, listing bundle diekspansi menjadi kebutuhan produk satuan.
- Versi resep yang digunakan harus tersimpan pada pesanan agar perubahan resep berikutnya tidak mengubah histori.

### 9.8 Pembatalan Setelah Barang Keluar

- Pembatalan setelah status keluar fisik tidak otomatis menambah stok.
- Sistem membuat status menunggu pengembalian atau penyelesaian.
- Stok baru bertambah setelah barang benar-benar diterima dan diperiksa di gudang.

### 9.9 Barang Keluar Manual

Barang keluar manual mendukung sedikitnya alasan:

- Penjualan offline.
- Bonus.
- Promo.
- Sampel.
- Barang rusak.
- Barang kedaluwarsa.
- Koreksi yang telah disetujui.

Setiap transaksi wajib memiliki alasan, kanal, catatan, dan pengguna. Pengeluaran manual juga menggunakan FEFO, kecuali pergerakan secara eksplisit berasal dari batch tertentu, seperti pemusnahan batch rusak atau kedaluwarsa.

### 9.10 Retur

Retur diproses dalam dua tahap:

1. **Retur diharapkan:** marketplace atau operator mencatat bahwa barang sedang dikembalikan.
2. **Retur diterima dan diinspeksi:** operator mengonfirmasi barang telah tiba dan memilih kondisi fisiknya.

Hasil inspeksi:

- `SELLABLE`: menambah stok layak jual.
- `DAMAGED`: menambah bucket barang rusak, bukan stok layak jual.
- `LOST`: tidak menambah stok fisik dan membuat kasus kehilangan atau klaim.

Retur yang masih menunggu inspeksi masuk ke `QUARANTINE`. Apabila batch asli dapat ditelusuri dari alokasi outbound, retur dikembalikan ke batch tersebut. Jika batch fisik tidak dapat dipastikan, barang tetap dikarantina sampai admin menetapkan batch atau melakukan koreksi terkontrol.

### 9.11 Pengingat Klaim TikTok

- Sistem menyimpan tanggal dasar klaim, tenggat, status klaim, dan catatan.
- Tenggat fase 1 menggunakan 40 hari kalender dan dibuat configurable.
- Notifikasi tampil sebelum tenggat berdasarkan ambang yang dapat dikonfigurasi.
- Sistem hanya melacak status dan tenggat klaim, bukan nilai kompensasi.

### 9.12 Kedaluwarsa

- Sistem memberi notifikasi per batch yang mendekati kedaluwarsa.
- Default ambang fase 1: 90, 60, dan 30 hari sebelum kedaluwarsa.
- Batch yang sudah kedaluwarsa otomatis tidak tersedia untuk FEFO.
- Pengeluaran atau pemusnahan barang kedaluwarsa tetap harus dicatat sebagai movement dengan alasan yang sesuai.

### 9.13 Stok Opname

- Stok opname memiliki status `DRAFT`, `COUNTING`, `REVIEW`, dan `POSTED`.
- Sistem menyimpan snapshot saldo pada waktu opname dimulai.
- Operator memasukkan hasil hitung fisik per produk, batch, dan kondisi.
- Sistem menghitung selisih antara snapshot dan hasil fisik.
- Koreksi hanya diposting setelah ditinjau atau disetujui admin.
- Koreksi menghasilkan entri buku besar baru dan tidak mengubah histori sebelumnya.
- Setelah posting, laporan opname tidak dapat diedit; perubahan dilakukan melalui siklus koreksi baru.

### 9.14 Rekonsiliasi Harian

Rekonsiliasi harian memeriksa sedikitnya:

- Saldo proyeksi sama dengan hasil penjumlahan buku besar.
- Tidak ada saldo negatif.
- Tidak ada event eksternal yang diproses lebih dari sekali.
- Total komponen bundle sesuai resep yang tersimpan.
- Total alokasi batch sesuai kuantitas barang keluar.
- Pesanan pada status keluar fisik memiliki movement outbound.
- Pesanan yang belum keluar fisik tidak memiliki movement outbound final.
- Retur layak jual hanya menambah stok setelah diterima dan diinspeksi.
- Movement memiliki referensi dan alasan yang valid.
- Transisi status mengikuti state machine yang ditetapkan.

Kejanggalan menghasilkan issue rekonsiliasi dengan severity, deskripsi, referensi terkait, status penyelesaian, dan catatan penanganan.

## 10. Cakupan Fungsional Fase 1

### 10.1 Dashboard

Menampilkan:

- Total SKU aktif.
- Total stok tersedia.
- Jumlah batch mendekati kedaluwarsa.
- Pesanan menunggu proses.
- Retur menunggu penerimaan atau inspeksi.
- Klaim mendekati tenggat.
- Issue rekonsiliasi terbuka.
- Ringkasan pergerakan stok terbaru.

### 10.2 Master Produk dan Batch

- CRUD produk dengan pengarsipan, bukan hard delete untuk data yang sudah dipakai.
- Pembuatan dan pencarian batch.
- Riwayat saldo serta movement per batch.
- Penandaan batch aktif, diblokir, kedaluwarsa, atau dikarantina.

### 10.3 Penerimaan Barang

- Form penerimaan dari maklon.
- Dukungan beberapa item dan batch dalam satu dokumen.
- Preview sebelum posting.
- Bukti referensi atau nomor dokumen.

### 10.4 Pesanan Marketplace

- Daftar pesanan Shopee dan TikTok Shop.
- Detail item asli, hasil ekspansi bundle, reservasi, status, dan alokasi batch.
- Pemrosesan event baru, dikirim, dibatalkan, retur, dan kehilangan.
- Timeline seluruh perubahan status.

### 10.5 Barang Keluar Manual

- Form cepat untuk penjualan offline, bonus, promo, sampel, rusak, dan kedaluwarsa.
- Alasan dan kanal wajib dipilih secara terpisah.
- Preview alokasi FEFO sebelum posting.

### 10.6 Retur dan Klaim

- Daftar retur yang diharapkan, diterima, menunggu inspeksi, selesai, atau hilang.
- Form inspeksi kondisi barang.
- Riwayat per item dan batch.
- Daftar klaim TikTok beserta countdown tenggat.

### 10.7 Stok Opname

- Membuat sesi opname.
- Memasukkan atau mengimpor hasil hitung.
- Membandingkan saldo sistem dan fisik.
- Meninjau selisih.
- Menyetujui dan memposting koreksi.

### 10.8 Rekonsiliasi dan Audit Trail

- Menjalankan pemeriksaan harian secara manual dan terjadwal.
- Menampilkan issue berdasarkan severity dan status.
- Drill-down dari saldo produk ke batch, movement, dokumen, pesanan, retur, atau opname.
- Timeline audit yang memuat siapa melakukan apa dan kapan.

### 10.9 Simulasi Marketplace

Tersedia tombol untuk menyuntikkan data dummy yang mewakili:

- Pesanan baru.
- Pesanan dikonfirmasi.
- Pesanan mencapai status keluar fisik.
- Pembatalan sebelum pengiriman.
- Pembatalan setelah pengiriman.
- Retur dimulai.
- Retur diterima.
- Retur rusak.
- Retur hilang.

Simulator wajib menggunakan jalur pemrosesan domain yang sama dengan impor dan integrasi API masa depan. Simulator tidak boleh menulis langsung ke tabel saldo atau buku besar.

### 10.10 Impor File

- Mendukung impor data melalui CSV pada fase 1.
- Menyediakan template file.
- Menampilkan preview dan hasil validasi sebelum commit.
- Menolak baris tidak valid tanpa diam-diam mengubah data.
- Menyediakan laporan baris gagal.
- Menggunakan external event ID atau idempotency key untuk mencegah duplikasi.

### 10.11 Notifikasi

Notifikasi fase 1 mencakup:

- Batch mendekati kedaluwarsa.
- Batch sudah kedaluwarsa tetapi masih memiliki stok.
- Retur menunggu inspeksi.
- Klaim TikTok mendekati tenggat.
- Issue rekonsiliasi baru atau kritis.

## 11. Halaman Minimum

1. Login.
2. Dashboard.
3. Produk.
4. Detail produk dan batch.
5. Penerimaan barang.
6. Pesanan marketplace.
7. Detail pesanan.
8. Barang keluar manual.
9. Retur dan klaim.
10. Stok opname.
11. Rekonsiliasi.
12. Buku besar stok.
13. Simulator dan impor.
14. Notifikasi.
15. Pengaturan dan pengguna.

## 12. Di Luar Cakupan Fase 1

Fase pertama tidak mencakup:

- Integrasi API langsung dengan Shopee atau TikTok Shop.
- Harga pokok, harga jual, diskon nominal, margin, atau nilai persediaan.
- Akuntansi, invoice, pembayaran, dan jurnal keuangan.
- Procurement atau purchase order lengkap.
- Perencanaan produksi maklon.
- Forecasting permintaan.
- Optimasi rute atau pengiriman.
- Stok bundle sebagai entitas terpisah.
- Multi-warehouse kompleks.
- Aplikasi mobile native.
- Otomatisasi klaim marketplace.

Struktur event ingestion harus tetap dirancang agar API marketplace dapat ditambahkan kemudian tanpa mengubah aturan inti stok.

## 13. Persyaratan Pengalaman Pengguna

- Antarmuka menggunakan bahasa Indonesia yang ringkas dan konsisten.
- Tindakan berisiko seperti posting opname atau koreksi memerlukan konfirmasi yang menjelaskan dampaknya.
- Operator melihat istilah bisnis, bukan istilah database.
- Form utama dapat digunakan dengan keyboard dan memiliki urutan fokus yang masuk akal.
- Status ditampilkan dengan label teks, tidak hanya warna.
- Tabel memiliki pencarian, filter, pagination, dan empty state yang informatif.
- Setiap transaksi sukses menampilkan nomor referensi dan tautan ke audit trail.
- Error harus menyebutkan apa yang gagal dan langkah yang perlu dilakukan.
- Riwayat tidak boleh disembunyikan demi tampilan yang tampak “bersih”. Sistem ini dibuat untuk menemukan cerita di balik angka, bukan menyapunya di bawah karpet UI.

## 14. Persyaratan Teknis dan Guardrail

### 14.1 Stack Wajib

- Next.js.
- TypeScript.
- Supabase.
- PostgreSQL.

### 14.2 Arah Implementasi

- Gunakan Next.js App Router.
- Gunakan Route Handlers sebagai boundary HTTP untuk impor, simulator, dan integrasi eksternal di masa depan.
- PostgreSQL menjadi source of truth untuk aturan stok.
- Operasi data-intensif dan mutasi stok atomik ditempatkan dalam database function/RPC, bukan dirangkai sebagai serangkaian write terpisah dari browser.
- Semua tabel pada exposed schema harus menggunakan Row Level Security.
- Hak eksekusi function dibatasi berdasarkan peran.
- Gunakan migration yang tersimpan di repository untuk seluruh perubahan schema.
- Larang direct insert/update/delete ke buku besar dari client umum.
- Gunakan constraint, foreign key, unique index, dan check constraint untuk menjaga invariant.
- Gunakan idempotency key unik untuk event marketplace dan baris impor.
- Proses konkuren yang mengalokasikan stok harus menggunakan locking atau tingkat isolasi transaksi yang memadai serta menangani retry ketika terjadi serialization failure.
- Rahasia server dan service-role key tidak boleh dikirim ke browser.

### 14.3 Pengujian Minimum

- Unit test untuk ekspansi bundle dan pemetaan status.
- Database test untuk constraint, function, RLS, FEFO, dan integritas ledger.
- Integration test untuk setiap skenario emas pada Bagian 18.
- End-to-end smoke test untuk login, penerimaan, pengiriman, retur, opname, dan rekonsiliasi.
- Seed data yang konsisten untuk demonstrasi live.

## 15. Persyaratan Nonfungsional

### 15.1 Integritas

Kebenaran saldo lebih penting daripada kenyamanan menyimpan transaksi. Sistem harus gagal secara aman apabila invariant tidak terpenuhi.

### 15.2 Auditabilitas

Semua mutasi penting menyimpan actor, timestamp, referensi, dan perubahan yang terjadi. Waktu kejadian bisnis dan waktu pencatatan sistem disimpan terpisah.

### 15.3 Keamanan

- Autentikasi wajib untuk seluruh halaman operasional.
- Otorisasi berbasis peran diterapkan di UI dan database.
- RLS aktif pada tabel yang diekspos.
- Input divalidasi di boundary aplikasi dan database.
- Aksi sensitif dicatat pada audit log.

### 15.4 Performa

Target awal pada data fase 1:

- Halaman daftar utama merespons dalam waktu yang wajar pada koneksi kantor standar.
- Pencarian ledger menggunakan pagination dan index yang sesuai.
- Mutasi stok tidak bergantung pada pemuatan seluruh riwayat ke browser.

Tidak diperlukan optimasi skala absurd untuk jutaan gudang. Satu gudang yang menghitung stok dengan benar sudah merupakan pencapaian mulia bagi peradaban.

### 15.5 Keandalan

- Deployment harus stabil dan dapat direproduksi.
- Migration dapat dijalankan pada environment baru.
- Seed demo tidak merusak data produksi.
- Error server tercatat tanpa membocorkan rahasia kepada pengguna.

## 16. Model Integrasi Masa Depan

Semua sumber kejadian menggunakan kontrak event kanonis. Contoh atribut:

```ts
type MarketplaceEvent = {
  source: "SHOPEE" | "TIKTOK_SHOP";
  externalEventId: string;
  eventType:
    | "ORDER_CREATED"
    | "ORDER_CONFIRMED"
    | "ORDER_SHIPPED"
    | "ORDER_IN_TRANSIT"
    | "ORDER_CANCELLED"
    | "RETURN_REQUESTED"
    | "RETURN_RECEIVED"
    | "RETURN_LOST";
  occurredAt: string;
  orderId: string;
  payload: unknown;
};
```

Simulator, CSV import, dan API sungguhan kelak harus menghasilkan event kanonis yang sama. Setelah itu, event diproses oleh domain service atau database function yang sama. Dengan demikian, mengganti tombol simulasi dengan API tidak mengubah logika stok.

## 17. Asumsi Fase 1

Asumsi berikut berlaku sampai ada keputusan klien yang berbeda:

- Hanya ada satu gudang fisik.
- Semua kuantitas menggunakan bilangan bulat positif dalam satuan unit.
- Zona waktu operasional adalah `Asia/Jakarta`.
- Stok negatif dilarang.
- Koreksi opname memerlukan persetujuan Admin.
- Ambang notifikasi kedaluwarsa adalah 90, 60, dan 30 hari.
- Batas klaim TikTok adalah 40 hari kalender dan titik awalnya dapat dikonfigurasi.
- Retur tanpa batch yang dapat diverifikasi masuk karantina.
- Penghapusan master yang telah memiliki transaksi dilakukan melalui arsip/nonaktif.
- CSV menjadi format impor awal.

## 18. Skenario Emas untuk Acceptance Test

### Skenario 1: Penerimaan Barang

Menerima 100 unit Produk A Batch A1 harus menghasilkan saldo `SELLABLE` 100 dan satu rangkaian audit yang lengkap.

### Skenario 2: Pesanan Baru Hanya Mereservasi

Pesanan 10 unit Produk A belum mencapai status keluar fisik. On hand tetap 100, reserved menjadi 10, dan available menjadi 90. Belum ada outbound final.

### Skenario 3: Pengiriman dengan FEFO

Tersedia Batch A1 sebanyak 5 unit kedaluwarsa lebih dekat dan Batch A2 sebanyak 20 unit. Pengiriman 10 unit harus mengambil 5 dari A1 dan 5 dari A2.

### Skenario 4: Pembatalan Sebelum Pengiriman

Pesanan yang masih reservasi dibatalkan. Reserved kembali nol dan tidak ada inbound atau outbound fisik.

### Skenario 5: Pembatalan Setelah Pengiriman

Pesanan sudah keluar fisik kemudian dibatalkan. Sistem tidak langsung menambah stok dan membuat proses pengembalian yang dapat ditindaklanjuti.

### Skenario 6: Retur Layak Jual

Barang dikembalikan, diterima, dan dinilai layak jual. Sistem menambah `SELLABLE` pada batch asal serta menutup retur.

### Skenario 7: Retur Rusak

Barang dikembalikan dan dinilai rusak. Sistem menambah `DAMAGED`, tidak menambah stok tersedia, dan tetap menyimpan jejak batch.

### Skenario 8: Retur Hilang

Barang ditandai hilang di ekspedisi. Tidak ada stok masuk. Kasus klaim dan tenggat dibuat.

### Skenario 9: Bonus Manual

Operator mengeluarkan 3 unit sebagai bonus melalui kanal manual. Movement harus memiliki alasan `BONUS`, kanal `MANUAL`, dan alokasi FEFO.

### Skenario 10: Bundle

Satu bundle berisi 2 Produk A dan 1 Produk B. Pesanan 3 bundle harus menghasilkan kebutuhan 6 Produk A dan 3 Produk B tanpa membuat stok bundle.

### Skenario 11: Duplikasi Event

Event pengiriman dengan external event ID yang sama dikirim dua kali. Hanya satu rangkaian outbound yang boleh terbentuk.

### Skenario 12: Stok Tidak Cukup

Pengiriman memerlukan 10 unit tetapi hanya tersedia 8. Seluruh transaksi gagal tanpa alokasi parsial atau perubahan saldo.

### Skenario 13: Stok Opname

Saldo sistem 50 unit, hitung fisik 47 unit. Setelah persetujuan admin, adjustment -3 dibuat sebagai entri ledger baru dengan referensi sesi opname.

### Skenario 14: Rekonsiliasi Menemukan Kejanggalan

Data uji sengaja memiliki pengiriman tanpa movement. Rekonsiliasi harus membuat issue yang dapat di-drill ke pesanan terkait.

## 19. Definition of Done Fase 1

Fase 1 selesai ketika:

- Seluruh fitur dalam scope tersedia pada deployment live.
- Seluruh skenario emas lulus.
- Database dapat dibangun ulang dari migration dan seed.
- Tidak ada jalur UI umum yang dapat mengubah saldo secara langsung.
- RLS dan role permission telah diuji.
- Simulator menggunakan pipeline yang sama dengan impor dan calon API.
- README menjelaskan setup lokal, environment variable, migration, seed, test, dan deployment.
- Data demo menunjukkan alur normal serta kasus selisih yang dapat direkonsiliasi.
- Operator dapat menyelesaikan alur penerimaan, pengiriman, retur, dan opname tanpa bantuan developer.

## 20. Risiko Utama dan Mitigasi

| Risiko | Dampak | Mitigasi |
|---|---|---|
| Mutasi stok dilakukan dari banyak jalur berbeda | Saldo tidak konsisten | Satu posting service/RPC untuk seluruh movement |
| Event marketplace dikirim ulang | Stok keluar ganda | Unique idempotency key dan event log |
| Dua operator mengalokasikan batch bersamaan | Overselling atau saldo negatif | Transaksi atomik, locking/isolation, dan retry |
| Resep bundle berubah | Histori pesanan ikut berubah | Simpan snapshot/version resep pada pesanan |
| Retur dianggap masuk sebelum fisik tiba | Stok semu | Pisahkan expected return, received, dan inspected |
| Koreksi menghapus histori | Selisih tidak dapat dijelaskan | Append-only reversal dan adjustment |
| RLS salah konfigurasi | Data bocor atau mutasi ilegal | Database test untuk policy dan least privilege |
| Simulator memiliki logika sendiri | Demo lulus tetapi integrasi nyata gagal | Semua sumber masuk ke event pipeline yang sama |
| Operator kesulitan memakai UI | Proses kembali ke spreadsheet | Form ringkas, istilah bisnis, validasi, dan usability test |

## 21. Pertanyaan Terbuka untuk Keputusan Berikutnya

Pertanyaan ini tidak menghalangi penyusunan fase awal, tetapi harus diputuskan sebelum production rollout:

1. Tanggal apa yang menjadi titik awal resmi batas klaim TikTok 40 hari?
2. Apakah produk retur selalu memiliki kode batch yang dapat dibaca?
3. Apakah diperlukan dua tingkat persetujuan untuk adjustment besar?
4. Apakah ada lokasi rak atau bin yang perlu dilacak pada fase berikutnya?
5. Format ekspor marketplace apa yang tersedia dari Shopee dan TikTok Shop?
6. Apakah stok rusak tetap disimpan sampai pemusnahan atau langsung dianggap keluar fisik?
7. Berapa toleransi selisih yang dianggap kritis untuk setiap produk?
8. Apakah nomor dokumen maklon memiliki format unik yang dapat dijadikan idempotency key?

## 22. Rujukan Teknis

Rujukan ini mendukung guardrail implementasi, bukan menggantikan keputusan bisnis pada brief klien.

- [Next.js Documentation - Route Handlers](https://nextjs.org/docs/app/getting-started/route-handlers)
- [Supabase Documentation - Database Functions](https://supabase.com/docs/guides/database/functions)
- [Supabase Documentation - Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase Documentation - Testing Overview](https://supabase.com/docs/guides/local-development/testing/overview)
- [PostgreSQL Documentation - Transaction Isolation](https://www.postgresql.org/docs/current/transaction-iso.html)

## 23. Sumber Proyek

Dokumen ini disusun berdasarkan `stok-management-system.pdf`, terutama ketentuan mengenai masalah selisih stok, buku besar pergerakan, batch dan kedaluwarsa, FEFO, bundle, retur, stok opname, rekonsiliasi, simulasi marketplace, stack wajib, serta urutan penilaian aplikasi.
