# UI/UX Redesign Guide

## Tujuan

Frontend dibangun sebagai workspace Admin gudang yang:

- sederhana dan cepat dipahami tanpa pelatihan istilah teknis;
- membantu pengguna mengetahui apa yang perlu dilakukan berikutnya;
- cepat dipindai untuk pekerjaan operasional harian;
- aman untuk operasi yang mengubah stok;
- tetap dapat menjelaskan asal setiap perubahan angka;
- menyembunyikan kompleksitas sistem sampai detail teknis benar-benar dibutuhkan.

Pengguna tidak boleh dipaksa memahami cara backend dibangun untuk dapat memakai aplikasi.

Setiap layar utama harus membantu pengguna menjawab:

1. Apa yang perlu saya perhatikan sekarang?
2. Stok saya bagaimana?
3. Apa yang ingin saya kerjakan?
4. Apa dampaknya sebelum saya menyimpan?
5. Jika ada masalah, dari mana asalnya?

Kebenaran stok dan keterlacakan tetap lebih penting daripada kosmetik, tetapi kompleksitas teknis tidak boleh dibebankan ke pengguna utama.

## Prinsip utama

### UI mengikuti pekerjaan manusia, bukan struktur backend

Menu utama tidak dibuat satu per route, tabel, engine, atau lifecycle internal.

Hal seperti ledger, FEFO allocation, reconciliation run, notification evaluator, reversal, reservation, projection, event normalization, dan idempotency tetap penting sebagai kontrak sistem, tetapi bukan berarti semuanya harus menjadi menu atau istilah utama di UI.

Gunakan progressive disclosure:

- tampilkan pekerjaan dan hasil terlebih dahulu;
- tampilkan penjelasan bila dibutuhkan;
- tampilkan detail teknis hanya pada audit atau troubleshooting.

### Tempat kerja sedikit, kemampuan tetap lengkap

Primary navigation ditargetkan hanya memiliki tiga tempat kerja:

1. **Beranda**
2. **Stok**
3. **Pesanan**

**Pengaturan** ditempatkan terpisah di bagian bawah navigasi karena bukan pekerjaan harian.

Struktur target:

```text
Stock Reconciliation

● Beranda
  Stok
  Pesanan

────────────────
⚙ Pengaturan
```

Alasan memakai **Beranda** sebagai label navigasi:

- lebih universal daripada `Hari Ini`;
- langsung dipahami sebagai titik awal aplikasi;
- tidak memberi kesan bahwa pekerjaan dengan tenggat besok/lusa tidak boleh muncul;
- tetap memungkinkan judul halaman **Hari Ini** untuk menekankan pekerjaan yang perlu diperhatikan sekarang.

Route teknis dan route lama boleh tetap dipertahankan untuk menjaga kontrak, deep-link, test, dan implementasi bertahap. Route tidak wajib tampil sebagai primary navigation.

### Satu layar, satu keputusan utama

Setiap layar memiliki:

- satu judul yang jelas;
- deskripsi singkat bila benar-benar membantu;
- maksimal satu tindakan utama yang dominan;
- informasi terpenting tampil lebih dahulu;
- tindakan tambahan muncul secara kontekstual.

Jangan membuat menu terpisah jika sebuah kemampuan lebih mudah ditemukan dari objek yang sedang dikerjakan.

Contoh:

- koreksi transaksi dibuka dari detail transaksi;
- pembatalan pesanan dibuka dari detail pesanan;
- klaim dibuka dari retur terkait;
- FEFO berjalan saat pengguna melakukan Barang Keluar;
- rekonsiliasi muncul ketika sistem menemukan masalah;
- import merupakan tindakan dari halaman Pesanan, bukan menu utama.

## Information architecture

### 1. Beranda — halaman `Hari Ini`

**Beranda** menjadi halaman awal setelah login dan menggantikan kebutuhan pengguna untuk memilih antara dashboard, Pusat Kendali, Ringkasan Stok, dan Notifikasi.

Judul halaman dapat menggunakan **Hari Ini**.

Pertanyaan yang dijawab:

> Apa yang perlu saya perhatikan sekarang?

Isi utama:

- ringkasan stok singkat;
- jumlah masalah yang perlu diperiksa;
- pekerjaan mendesak;
- risiko batch;
- antrean tindakan berdasarkan prioritas;
- aktivitas atau notifikasi terbaru sebagai informasi sekunder.

Contoh bahasa:

- **Ada selisih stok**
- **Retur belum diperiksa**
- **Batas klaim TikTok mendekat**
- **Batch hampir kedaluwarsa**

Notifikasi bukan primary navigation. Notifikasi yang membutuhkan tindakan masuk ke antrean **Perlu Tindakan**. Notifikasi informasional dapat dilihat sebagai aktivitas terbaru atau melalui shortcut lonceng di topbar.

### 2. Stok

**Stok** menjadi rumah untuk semua pekerjaan yang berhubungan langsung dengan produk, batch, posisi stok, perubahan stok, hitung fisik, masalah stok, dan riwayat.

Pertanyaan yang dijawab:

> Berapa stok saya, dari mana angkanya, dan apa yang ingin saya lakukan terhadap stok?

Tampilan default:

- pencarian produk, SKU, atau batch;
- posisi stok per produk;
- status stok yang mudah dipahami;
- akses ke detail produk;
- tindakan kontekstual.

Detail produk menggunakan pola:

```text
Ringkasan | Batch | Riwayat
```

Kemampuan yang tidak perlu menjadi menu utama:

- **Barang Masuk** → `Stok > Catat Perubahan > Barang Masuk`
- **Barang Keluar** → `Stok > Catat Perubahan > Barang Keluar`
- **Barang Rusak / Kedaluwarsa** → `Stok > Catat Perubahan > Barang Rusak / Kedaluwarsa`
- **Stocktake** → tombol `Mulai Hitung Stok`
- **Ledger** → `Stok > Riwayat`
- **Reconciliation** → muncul sebagai `Masalah Stok` ketika ada masalah
- **Entry Correction** → `Riwayat > Detail Transaksi > Batalkan Transaksi`
- **FEFO** → otomatis di dalam alur Barang Keluar

Tombol utama dapat berbentuk:

```text
[ Catat Perubahan ▾ ]   [ Mulai Hitung Stok ]
```

Isi `Catat Perubahan`:

```text
+ Barang Masuk
→ Barang Keluar
× Barang Rusak / Kedaluwarsa
```

### 3. Pesanan

**Pesanan** menjadi rumah untuk alur marketplace dari pesanan sampai retur dan klaim.

Pertanyaan yang dijawab:

> Pesanan mana yang perlu diproses dan bagaimana statusnya sampai selesai?

Struktur sederhana:

```text
Pesanan | Retur & Klaim
```

Tindakan:

- `Impor Pesanan` sebagai tombol dari halaman Pesanan;
- pembatalan dari detail pesanan;
- retur dari pesanan terkait;
- klaim dari retur terkait.

Jangan menjadikan istilah berikut sebagai primary navigation:

- Marketplace Simulator;
- Import Marketplace;
- Reservation;
- Allocation;
- Event;
- Normalization;
- Partial Cancellation;
- Claim workflow terpisah.

Jika implementasi masih menggunakan simulator atau adapter lokal, cukup tampilkan indikator kecil seperti **Mode Demo** bila konteks tersebut memang perlu diketahui. Jangan menjadikan simulator sebagai mental model pengguna.

### 4. Pengaturan

**Pengaturan** bukan workspace harian dan ditempatkan di bagian bawah navigasi.

Gunakan untuk kebutuhan jarang atau teknis seperti:

- Setup Awal / Saldo Awal;
- konfigurasi yang benar-benar perlu dikelola Admin;
- Status Sistem;
- Diagnostik.

Notification Operations, outbox retry, evaluator, status processing, dan detail teknis sejenis masuk ke **Diagnostik**, bukan sejajar dengan pekerjaan gudang sehari-hari.

## Safeguard operasional

Penyederhanaan UI tidak boleh mengurangi keamanan operasional.

### Jejak audit tetap kuat

Setiap perubahan permanen harus tetap dapat menjawab:

- siapa atau proses apa yang melakukan perubahan;
- kapan kejadian berlangsung;
- kapan sistem mencatatnya;
- apa alasan perubahan;
- referensi/bukti apa yang digunakan;
- nilai sebelum dan sesudah bila relevan;
- transaksi sumber dan transaksi pembatalan bila terjadi reversal.

Pada UI utama, tampilkan bahasa manusia seperti:

- **Dilakukan oleh**
- **Waktu kejadian**
- **Waktu dicatat**
- **Alasan**
- **Referensi / Bukti**

Metadata seperti correlation ID, idempotency command ID, ledger sequence, raw source type, dan linkage teknis ditempatkan dalam **Detail teknis**.

Audit trail tidak boleh dapat dihapus atau dimodifikasi hanya demi menyederhanakan UI.

### Permission-aware, tetapi jangan membuat RBAC palsu

Scope produk saat ini tetap **satu role ADMIN**. Redesign ini tidak otomatis menambah Supervisor, Manager, atau role baru karena hal tersebut memerlukan kontrak auth/RLS/server action/test tersendiri.

Namun komponen tindakan berisiko harus didesain agar future-ready terhadap permission, misalnya:

- pemusnahan stok;
- pembatalan transaksi;
- posting hasil hitung;
- perubahan saldo awal;
- tindakan diagnostik sistem.

Aturan:

- keamanan tidak boleh hanya bergantung pada tombol yang disembunyikan; permission tetap harus ditegakkan server-side bila RBAC benar-benar ditambahkan;
- aksi yang secara permanen tidak dimiliki suatu role dapat disembunyikan;
- aksi yang hanya sementara tidak tersedia sebaiknya disabled dengan alasan yang jelas;
- jangan menampilkan opsi role/permission yang backend-nya belum ada.

Penambahan RBAC adalah scope terpisah, bukan bagian kosmetik redesign.

### Status koneksi dan penyimpanan harus jujur

Jangan menampilkan label **Tersinkronisasi** jika aplikasi belum memiliki mekanisme offline queue/sync yang nyata.

Untuk implementasi sekarang:

- saat request berlangsung → **Menyimpan...**;
- setelah server mengonfirmasi → **Tersimpan**;
- bila request gagal → jelaskan bahwa perubahan **belum tersimpan**;
- bila browser terdeteksi offline → tampilkan banner **Koneksi terputus** dan cegah kesan bahwa mutation sudah aman;
- tombol mutation harus mencegah double-submit saat request sedang berjalan.

Jika di masa depan dibuat offline queue, baru gunakan state seperti:

- **Belum dikirim**
- **Menunggu sinkronisasi**
- **Sedang menyinkronkan**
- **Tersinkronisasi**
- **Perlu diperiksa** bila terjadi konflik.

Offline-first dan conflict resolution merupakan capability tersendiri dan tidak boleh dipalsukan melalui indikator visual saja.

## Bahasa antarmuka

### Gunakan bahasa pekerjaan, bukan bahasa implementasi

Bahasa UI utama menggunakan istilah yang dapat dipahami pengguna tanpa mengetahui arsitektur sistem.

| Istilah sistem | Bahasa UI utama |
| --- | --- |
| Today Control Center / Pusat Kendali | **Beranda**, judul halaman **Hari Ini** |
| Dashboard / Ringkasan Stok | masuk ke **Beranda** dan **Stok** |
| Notification Center | **Aktivitas / Notifikasi terbaru** di Beranda |
| Product Inventory | **Stok** |
| Stock Ledger | **Riwayat Stok** |
| Stocktake / Stok Opname | **Hitung Stok** |
| Reconciliation | **Masalah Stok** atau **Selisih Stok** |
| Entry Correction | **Batalkan Transaksi** dari detail transaksi |
| Manual Outbound | **Barang Keluar** |
| Receipt / Post Receipt | **Barang Masuk / Simpan Barang Masuk** |
| Stock Disposal | **Barang Rusak / Kedaluwarsa** atau **Catat Pemusnahan** |
| Return Inspection Pending | **Retur Belum Diperiksa** |
| TikTok Claim Deadline | **Batas Klaim TikTok Mendekat** |
| Authoritative Preview | **Periksa Sebelum Simpan** |
| Reversal | **Pembatalan Transaksi** |
| Projection | **Jumlah stok saat ini** bila konteks memungkinkan |
| Work Item | langsung gunakan nama masalah/tugas |
| Severity | **Prioritas** |
| Source Reference | gunakan label kontekstual, bukan hanya `Referensi` |
| Resolution Status | **Status** |
| Quantity | **Jumlah** |
| Bucket | **Kondisi Stok** |
| Actor / process | **Dilakukan oleh** |
| Occurred at | **Waktu kejadian** |
| Recorded at | **Waktu dicatat** |

Istilah teknis tetap boleh muncul pada `Detail teknis`, audit, troubleshooting, atau dokumentasi developer.

### Istilah stok

Gunakan label yang menjelaskan kondisi stok:

| Kode/domain | Bahasa UI |
| --- | --- |
| SELLABLE | **Layak Dijual** |
| RESERVED | **Sudah Dipesan** |
| AVAILABLE | **Tersedia** |
| QUARANTINE | **Ditahan** |
| DAMAGED | **Rusak** |
| ON HAND | **Stok Fisik** |

Jika dua angka berbeda secara bisnis, jangan menyederhanakan sampai maknanya hilang. Misalnya **Layak Dijual** dan **Tersedia** tetap dipisahkan bila sebagian stok sudah dipesan.

Untuk kode status batch:

| Kode | Bahasa UI |
| --- | --- |
| ACTIVE | **Aktif** |
| BLOCKED | **Diblokir** + alasan |
| EXPIRED | **Kedaluwarsa** |
| ARCHIVED | **Diarsipkan** |

`Batch` tetap dapat digunakan karena merupakan konsep gudang penting, tetapi tampilkan sebagai **Kode Batch** pada field dan berikan penjelasan singkat pada pengalaman pertama bila diperlukan.

### Istilah prioritas

Gunakan maksimal empat tingkat dan hindari campuran bahasa:

| Kode | Bahasa UI |
| --- | --- |
| CRITICAL | **Kritis** |
| HIGH | **Mendesak** |
| WARNING / MEDIUM | **Perlu Diperiksa** |
| INFO / LOW | **Informasi** |

Gunakan warna sebagai pendukung, bukan satu-satunya pembeda.

### Status Hitung Stok

Status internal stocktake perlu diterjemahkan menjadi progres yang mudah dipahami:

| Status internal | Bahasa UI |
| --- | --- |
| DRAFT | **Belum Dimulai** |
| READY | **Siap Dihitung** |
| COUNTING | **Sedang Dihitung** |
| REVIEW | **Perlu Diperiksa** |
| APPROVED | **Siap Disimpan** |
| POSTING | **Menyimpan Perubahan** |
| POSTED | **Selesai** |
| CANCELLED | **Dibatalkan** |
| EXCEPTION | **Bermasalah** |

Status baris:

- PENDING → **Belum Dihitung**
- COUNTED → **Sudah Dihitung**
- RECOUNT_REQUESTED → **Hitung Ulang**

Keputusan pemeriksaan:

- MATCHED → **Sesuai**
- VARIANCE_ACCEPTED → **Selisih Diterima**
- RECOUNT_REQUIRED → **Hitung Ulang**
- EXCEPTION → **Perlu Penanganan**

### Alasan selisih stok

Hindari istilah internal seperti `projection drift`, `source event failure`, atau `duplicate movement` pada pilihan utama.

Gunakan bahasa seperti:

- **Barang keluar belum dicatat**
- **Barang masuk belum dicatat**
- **Data retur tidak sesuai**
- **Salah hitung batch**
- **Salah hitung kondisi stok**
- **Barang rusak belum dicatat**
- **Barang kedaluwarsa belum dicatat**
- **Saldo awal belum pasti**
- **Ada perubahan stok saat penghitungan**
- **Perubahan stok tercatat dua kali**
- **Data dari sumber gagal diproses**
- **Saldo sistem tidak sesuai riwayat**
- **Barang fisik hilang**
- **Stok fisik lebih banyak**
- **Data produk/batch salah**
- **Belum diketahui**
- **Lainnya**

## Audit field dan form

### Field umum

Gunakan label kontekstual.

Kurang jelas:

- Referensi
- Source Ref
- Quantity
- Channel
- Bucket
- Actor / Process

Lebih jelas:

- **Nomor / Referensi Barang Keluar**
- **Nomor / Referensi Barang Masuk**
- **Nomor Catatan Pemusnahan**
- **Bukti / Berita Acara**
- **Jumlah**
- **Sumber Pesanan** atau **Marketplace**
- **Kondisi Stok**
- **Dilakukan oleh**

`SKU` boleh dipertahankan tetapi label yang lebih ramah adalah **SKU / Kode Produk**.

### Barang Keluar

Jangan tampilkan copy seperti:

- `Database menentukan batch secara FEFO...`
- `Preview authoritative`
- `reserved stock`
- `ledger/projection/idempotency`
- `Referensi baris UI-1`

Gunakan:

> Sistem memilih batch yang tanggal kedaluwarsanya paling dekat secara otomatis.

Info sebelum simpan:

> Memeriksa data belum mengubah stok. Setelah disimpan, transaksi tidak dapat diedit. Jika ada kesalahan, transaksi dapat dibatalkan dari Riwayat Stok.

CTA:

- `Tinjau alokasi FEFO` → **Periksa Barang Keluar**
- final → **Keluarkan N Unit** atau **Simpan Barang Keluar**

### Barang Rusak / Kedaluwarsa

User memang perlu memilih batch exact karena barang fisik tertentu akan dimusnahkan, tetapi tidak perlu memahami istilah `bucket`.

Gunakan:

- `Bucket sumber` → **Kondisi Stok**
- `Quantity` → **Jumlah Dimusnahkan**
- `Exact batch & bucket` → hapus dari UI utama
- `Pilih batch dan bucket fisik...` → **Pilih batch dan jumlah barang yang benar-benar dimusnahkan.**

Tampilkan bukti/alasan secara eksplisit karena tindakan bersifat destruktif.

### Hitung Stok

Form pembuatan sesi saat ini terlalu banyak meminta keputusan teknis. UI target menyederhanakannya menjadi:

1. **Apa yang ingin dihitung?**
   - Semua stok
   - Produk tertentu
   - Batch tertentu
2. **Kapan dihitung?**
3. **Tampilkan jumlah sistem saat menghitung?**
   - Jangan tampilkan — disarankan
   - Tampilkan
4. **Catatan** — opsional

Field/istilah berikut tidak perlu tampil di alur utama bila dapat diinfer atau memiliki default tetap:

- `Full inventory / Cycle count / Ad hoc`
- `CONTINUOUS`
- `Mode scope`
- `Visibility`
- `Buckets`
- `Inclusion rules`
- `idempotencyKey`

Jika kategori kondisi stok memang perlu dipilih, tampilkan sebagai bagian **Pilihan Tambahan**:

```text
Kondisi stok yang dihitung
☑ Layak Dijual
☑ Ditahan
☑ Rusak
```

Pilihan seperti include zero balance, inactive master, blocked batch, dan expired batch masuk **Pilihan Lanjutan**, bukan layar utama.

### Pesanan

User utama tidak perlu melihat state `reservation`, `normalization`, `mapping version`, `component lifecycle`, atau `event` kecuali masuk detail teknis.

Status utama harus menjawab progres pekerjaan, misalnya:

- **Perlu Diproses**
- **Stok Disiapkan**
- **Dalam Pengiriman**
- **Dikirim**
- **Selesai**
- **Dibatalkan**
- **Selesai — sebagian dibatalkan**

### Retur dan Klaim

Gunakan bahasa:

- **Akan Diretur**
- **Belum Tiba**
- **Sudah Diterima**
- **Belum Diperiksa**
- **Layak Dijual**
- **Rusak**
- **Hilang**
- **Klaim Perlu Diajukan**
- **Menunggu Hasil Klaim**
- **Klaim Selesai**

Jangan menampilkan raw status code sebagai label utama.

## Audit filter dan pencarian

### Beranda

- `Severity` → **Prioritas**
- `Work Type` → **Jenis Masalah**
- `Terapkan` → **Tampilkan** atau **Terapkan Filter**
- `Reset` → **Hapus Filter**

### Riwayat Stok

Filter default cukup:

- Tanggal
- Produk / SKU
- Batch
- Jenis Perubahan
- Referensi

Filter lanjutan bila dibutuhkan:

- Waktu dicatat sistem
- Sumber data
- Dilakukan oleh
- Kondisi stok
- Arah stok: Masuk / Keluar
- Status pembatalan

Terjemahan:

- `transaction type` → **Jenis Perubahan**
- `reason` → **Alasan**
- `channel` → **Sumber Pesanan**
- `source reference` → **Nomor Referensi**
- `actor/process` → **Dilakukan oleh**
- `quantity direction` → **Arah Stok**
- `reversal state` → **Status Pembatalan**
- `recorded at` → **Waktu Dicatat Sistem**

Jangan menampilkan semua filter teknis secara default.

### Hitung Stok

Filter daftar sesi cukup:

- Status
- Yang Dihitung
- Tanggal

`Visibility` tidak perlu menjadi filter utama kecuali ada kebutuhan operasional nyata.

### Pesanan dan Retur

Utamakan filter berbasis pekerjaan:

- Perlu Diproses
- Perlu Dikirim
- Perlu Diperiksa
- Klaim Mendekati Batas Waktu
- Selesai

bukan raw lifecycle code.

## Tombol menjelaskan akibatnya

Hindari tombol generik:

- Submit
- Post
- Execute
- Process
- Confirm

Gunakan:

- **Simpan Barang Masuk**
- **Periksa Barang Keluar**
- **Keluarkan 12 Unit**
- **Mulai Hitung Stok**
- **Simpan Hasil Hitung**
- **Batalkan Transaksi**
- **Catat Pemusnahan**
- **Tandai sebagai Rusak**
- **Catat Barang Diterima**
- **Simpan Hasil Pemeriksaan**
- **Ajukan Klaim**
- **Impor 24 Pesanan**

Pengguna harus dapat memperkirakan akibat tombol sebelum menekannya.

## Error menjelaskan masalah dan langkah berikutnya

Jangan menampilkan kode internal sebagai pesan utama.

Kurang baik:

```text
INSUFFICIENT_SELLABLE_AFTER_RESERVATION
```

Lebih baik:

```text
Stok tidak cukup.
Kamu mencoba mengeluarkan 12 unit, tetapi hanya 8 unit yang tersedia karena 4 unit sudah dipesan.

Tersedia  8
Diminta   12
Kurang     4

[ Ubah Jumlah ]
```

Kode internal dapat tersedia di bagian `Detail teknis` yang collapsed.

Gunakan pola error:

1. apa yang gagal;
2. apakah ada data yang berubah;
3. mengapa bila dapat dijelaskan;
4. tindakan aman berikutnya.

Contoh:

> **Barang keluar belum tersimpan.** Koneksi ke server terputus sebelum proses selesai. Tidak ada bukti bahwa stok sudah berubah. Periksa koneksi lalu coba lagi.

## Progressive disclosure

Informasi dibagi menjadi tiga tingkat:

### Tingkat 1 — pekerjaan utama

Tampilkan langsung:

- nama produk/pesanan/retur;
- jumlah;
- status;
- masalah;
- tenggat;
- tindakan berikutnya.

### Tingkat 2 — penjelasan

Tampilkan ketika pengguna membuka detail:

- batch terkait;
- sebelum dan sesudah;
- alasan sistem memilih tindakan;
- riwayat yang relevan;
- kemungkinan penyebab masalah;
- siapa yang melakukan dan kapan.

### Tingkat 3 — detail teknis

Tampilkan hanya bila dibutuhkan:

- UUID;
- ledger sequence;
- correlation ID;
- request hash;
- RPC;
- event code;
- projection internals;
- idempotency key/command ID;
- raw payload;
- evaluator/outbox details;
- raw lifecycle code.

## Pola perubahan stok

Alur perubahan permanen menggunakan urutan:

1. **Isi Data**
2. **Periksa Sebelum Simpan**
3. **Konfirmasi**
4. **Bukti Berhasil**

Preview tetap authoritative dan dihitung oleh sumber data resmi. Penyederhanaan bahasa tidak boleh mengganti authoritative preview dengan perhitungan kosmetik di browser.

### Barang Keluar dan FEFO

Pengguna memilih produk dan jumlah, bukan batch.

Pada langkah **Periksa Sebelum Simpan**, tampilkan:

- jumlah yang akan keluar;
- batch yang dipilih otomatis;
- tanggal kedaluwarsa batch;
- stok sebelum;
- stok setelah.

Penjelasan cukup:

> Batch dipilih otomatis berdasarkan tanggal kedaluwarsa terdekat.

Istilah FEFO boleh tampil sebagai detail/penjelasan sekunder, bukan sebagai pekerjaan yang harus dipahami sebelum menggunakan fitur.

### Hitung Stok

Gunakan alur sederhana:

```text
1. Pilih Barang
2. Hitung
3. Periksa Hasil
4. Selesai
```

Jika cocok dengan aturan bisnis, physical count dapat dilakukan tanpa memperlihatkan expected quantity terlebih dahulu untuk mengurangi bias hitung.

Jangan menjadikan `approval immutable`, `ledger adjustment`, atau `audit reconciliation` sebagai bahasa utama. Sistem tetap menjalankan aturan tersebut di belakang layar.

### Masalah Stok

Rekonsiliasi bukan pekerjaan yang harus dicari pengguna setiap saat. Sistem menampilkan masalah ketika pemeriksaan menemukan sesuatu yang perlu ditindaklanjuti.

Contoh:

```text
Ada selisih pada Serum A

Stok tercatat        26
Stok seharusnya      22
Selisih              -4

Kemungkinan penyebab
Barang keluar ORD-281 tidak tercatat lengkap.

[ Lihat Riwayat Terkait ]
```

Kode seperti `LEDGER_BATCH_PROJECTION`, `RESERVATION_CONSISTENCY`, atau `DUPLICATE_SOURCE_EFFECT` diterjemahkan menjadi penjelasan manusia pada UI utama.

### Pembatalan transaksi

Pengguna tidak masuk ke menu Koreksi Entri. Pengguna menemukan transaksi dari Riwayat Stok, membuka detail, lalu memilih **Batalkan Transaksi** bila diizinkan.

Jelaskan bahwa transaksi asli tidak dihapus dan sistem akan membuat transaksi pembatalan agar riwayat tetap dapat dilacak.

Backend tetap menggunakan reversal sesuai aturan domain.

## Pola Pesanan, Retur, dan Klaim

Pesanan diperlakukan sebagai satu cerita yang dapat ditelusuri:

```text
Pesanan
  ↓
Pengiriman
  ↓
Retur bila ada
  ↓
Pemeriksaan retur
  ↓
Klaim bila diperlukan
```

Retur tetap membedakan tiga konsep secara visual:

1. proses;
2. kondisi barang;
3. dampak ke stok.

Gunakan bahasa sederhana seperti:

- Akan Diretur
- Belum Tiba
- Belum Diperiksa
- Layak Dijual
- Rusak
- Hilang

Jangan mencampur status proses dengan kondisi fisik atau dampak stok.

## Data table dan pencarian

Untuk data dalam jumlah besar:

- tabel menjadi komponen utama pada desktop;
- header tabel sticky bila daftar panjang;
- quantity rata kanan dan memakai tabular numerals;
- kolom utama lebih menonjol daripada metadata;
- action column tetap mudah ditemukan;
- filter penting disimpan di URL;
- keyset pagination tetap digunakan bila kontrak data memerlukannya;
- mobile dapat menggunakan compact cards bila tabel tidak lagi efektif.

Global search, bila tersedia, menggunakan placeholder yang menjelaskan cakupan:

```text
Cari produk, batch, pesanan, atau retur...
```

## Hierarki tindakan

- Primary: satu tindakan utama layar.
- Secondary: tindakan pendukung.
- Ghost/link: navigasi dan detail.
- Danger: tindakan destruktif/permanen.

Danger hanya digunakan pada tindakan final yang memang berisiko, bukan mewarnai seluruh halaman.

Confirmation kuat digunakan untuk tindakan seperti:

- pengeluaran stok permanen;
- disposal/pemusnahan;
- pembatalan/reversal;
- posting hasil hitung;
- saldo awal.

Search, filter, membuka detail, preview, dan navigasi tidak memerlukan confirmation.

## Fondasi visual

### Warna

- Canvas: #F7F8F6
- Surface: #FFFFFF
- Surface subtle: #FCFDFC
- Teks utama: #18201E
- Teks sekunder: #6B7471
- Border: #D9DFDC
- Primary: #1F6F64
- Primary hover: #185A52
- Primary subtle: #E7F0ED
- Warning: #B45309
- Warning subtle: #FFF4E5
- Danger: #B42318
- Danger subtle: #FDECEA
- Focus: #2F8075

Aturan visual:

- light theme menjadi arah utama;
- tampilan tenang, flat, data-dense, dan tidak card-heavy;
- warna status selalu disertai label/ikon;
- shadow digunakan sedikit;
- border tipis menjadi pemisah utama;
- tabel tidak dipaksa masuk kartu sempit;
- quantity memakai tabular numerals dan rata kanan;
- radius utama 8 sampai 12 px;
- warna merah dipakai hemat untuk risiko/tindakan destruktif nyata.

## Responsive

### Mobile

- sidebar menjadi drawer;
- primary navigation tetap hanya Beranda, Stok, Pesanan;
- tabel padat berubah menjadi compact card bila perlu;
- action penting tetap mudah dijangkau;
- target sentuh minimal 44 x 44 px;
- drawer mengunci scroll belakang;
- fokus kembali ke tombol pembuka setelah drawer ditutup;
- status koneksi/error tidak menutupi tindakan utama.

### Tablet

- navigasi lebih ringkas;
- tabel hanya mempertahankan kolom prioritas;
- detail dapat memakai sheet atau split view.

### Desktop

- sidebar persistent;
- tabel menggunakan lebar yang tersedia;
- detail dapat memakai drawer atau halaman detail;
- workspace tidak dipenuhi kartu besar yang mengurangi density.

## Domain guardrails

Penyederhanaan UI tidak boleh mengubah aturan berikut:

1. Ledger append-only tetap menjadi source of truth.
2. Projection hanya untuk pembacaan cepat.
3. Duplicate command atau event maksimal satu domain effect.
4. Reservasi tidak mengubah stok fisik.
5. Shopee mengurangi stok saat SHIPPED.
6. TikTok mengurangi stok saat IN_TRANSIT.
7. FEFO otomatis dan Admin tidak memilih batch.
8. Expected return tidak mengubah stok.
9. Retur SELLABLE membuat inbound ke batch RETURN baru.
10. Retur DAMAGED atau LOST tidak membuat movement kedua.
11. LOST tetap terpisah dari DAMAGED.
12. Koreksi transaksi menggunakan reversal.
13. Penyesuaian hasil hitung merupakan proses terpisah.
14. Preview authoritative wajib dipertahankan untuk stock-out dan koreksi manual.
15. Penyederhanaan navigasi tidak boleh menghilangkan route contract, deep-link, audit evidence, atau safe internal route validation.
16. Current scope tetap satu role ADMIN; RBAC baru memerlukan scope dan security contract terpisah.
17. UI tidak boleh mengklaim offline sync/tersinkronisasi tanpa capability server/client yang benar-benar mendukungnya.

## State wajib

Halaman dan komponen harus menyediakan state nyata:

- loading;
- empty;
- error;
- blocked;
- success;
- stale preview;
- saving/pending untuk mutation;
- replay atau idempotent success bila relevan;
- connection failure bila request tidak dapat mencapai server.

Semua state menggunakan bahasa yang menjelaskan apa yang terjadi dan apa yang dapat dilakukan pengguna selanjutnya.

Tidak boleh ada placeholder, tombol mati, link palsu, form palsu, atau indikator sync palsu.

## Usability audit gate

Sebelum suatu page group dianggap selesai, lakukan tes dengan perspektif pengguna baru.

Pengguna harus dapat menyelesaikan skenario berikut tanpa mengetahui istilah backend:

1. Membuka aplikasi dan mengetahui apa yang perlu diperiksa.
2. Mencari stok Serum tertentu.
3. Mengetahui perbedaan Stok Fisik, Layak Dijual, Sudah Dipesan, dan Tersedia.
4. Mencatat barang masuk.
5. Mengeluarkan barang tanpa memilih batch FEFO sendiri.
6. Mencatat barang rusak/kedaluwarsa dengan bukti yang benar.
7. Memulai penghitungan fisik tanpa memahami `scope`, `bucket`, `visibility`, atau `cycle count`.
8. Mengetahui penyebab selisih stok dan membuka bukti terkait.
9. Menemukan transaksi salah dari riwayat dan membatalkannya tanpa memahami reversal.
10. Memproses pesanan, retur, dan klaim sebagai satu cerita.
11. Memahami apakah suatu perubahan sudah tersimpan atau belum ketika koneksi bermasalah.
12. Membaca siapa/kapan/mengapa suatu perubahan terjadi dari detail audit.

Pertanyaan evaluasi untuk setiap layar:

- Apakah judulnya langsung menjelaskan tujuan layar?
- Apakah ada istilah yang hanya dipahami pembuat sistem?
- Apakah user harus memilih sesuatu yang sebenarnya dapat ditentukan sistem?
- Apakah tombol menjelaskan akibatnya?
- Apakah error memberi langkah berikutnya?
- Apakah informasi teknis bisa dipindah ke detail lanjutan?
- Apakah tindakan destruktif memiliki bukti dan preview yang cukup?
- Apakah status koneksi/penyimpanan jujur?

## Target pengalaman pengguna

Pengguna baru harus dapat menjawab tanpa bantuan pembuat sistem:

- Untuk melihat pekerjaan penting → **Beranda**.
- Untuk mencari produk, batch, jumlah, atau riwayat → **Stok**.
- Untuk memproses marketplace, retur, atau klaim → **Pesanan**.
- Untuk mencatat perubahan stok → **Stok > Catat Perubahan**.
- Untuk menghitung fisik → **Stok > Mulai Hitung Stok**.
- Untuk memperbaiki transaksi salah → buka transaksi dari **Riwayat**, lalu **Batalkan Transaksi**.
- Untuk masalah teknis/setup → **Pengaturan**.

Jika pengguna masih harus bertanya kepada pembuat sistem “fitur ini ada di menu mana?”, “istilah ini artinya apa?”, atau “tombol ini akan melakukan apa?” untuk pekerjaan umum, desain belum selesai.

## Urutan migrasi

1. Kunci information architecture, bahasa UI, dan safeguard operasional pada guide ini.
2. Pertahankan route/business contract, tetapi sederhanakan primary navigation menjadi Beranda, Stok, Pesanan, dan Pengaturan sekunder.
3. Migrasikan **Beranda / Hari Ini** sebagai pilot: ringkasan + antrean tindakan + aktivitas/notifikasi.
4. Satukan pengalaman **Stok**: posisi stok, produk/batch, riwayat, perubahan stok, hitung stok, dan entry point masalah.
5. Satukan pengalaman **Pesanan**: pesanan, import sebagai action, retur & klaim, serta tindakan contextual.
6. Pindahkan setup dan diagnostik ke **Pengaturan**.
7. Hapus jargon teknis dari primary UI dan pindahkan ke detail teknis/audit.
8. Terapkan copy dictionary untuk status, field, filter, CTA, error, dan confirmation.
9. Lakukan responsive, accessibility, connection-state, usability scenario, dan cleanup legacy UI.

Setiap kelompok harus dapat direview dan divalidasi secara terpisah. Penyederhanaan presentasi tidak boleh mengubah kontrak domain yang sudah lolos test.
