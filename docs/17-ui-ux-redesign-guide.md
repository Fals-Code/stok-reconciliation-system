# UI/UX Redesign Guide

## Identitas Produk

Nama user-facing resmi adalah **Sistem Rekonsiliasi Stok**.

Nama ini harus konsisten pada:

- login;
- sidebar/app shell;
- browser title/metadata;
- empty state dan error state;
- dokumen bantuan user-facing.

Jangan mencampur `Stok Management`, `GlowLab Inventory`, `Stock Reconciliation`, atau nama teknis lain pada UI utama. Nama repository atau istilah engineering boleh tetap berbeda di belakang layar.

## Tujuan

Frontend dibangun sebagai workspace Admin gudang yang:

- sederhana dan cepat dipahami tanpa pelatihan istilah teknis;
- membuat pengguna baru langsung mengetahui apa yang harus dilakukan;
- cepat dipindai untuk pekerjaan operasional harian;
- aman untuk operasi yang mengubah stok;
- tetap dapat menjelaskan asal setiap perubahan angka;
- menyembunyikan kompleksitas sistem sampai detail teknis benar-benar dibutuhkan;
- tidak membuat kondisi gagal terlihat seperti kondisi aman;
- selalu memberi langkah berikutnya ketika pekerjaan belum selesai.

Pengguna tidak boleh dipaksa memahami cara backend dibangun untuk dapat memakai aplikasi.

Setiap layar utama harus membantu pengguna menjawab:

1. Saya sedang melihat apa?
2. Apakah ada masalah?
3. Jika ada, masalahnya apa?
4. Apa yang harus saya lakukan sekarang?
5. Apa yang terjadi jika saya menekan tombol ini?
6. Apakah stok berubah atau tidak?
7. Jika saya salah, bagaimana memperbaikinya?
8. Apakah tindakan tadi benar-benar berhasil?

Kebenaran stok dan keterlacakan tetap lebih penting daripada kosmetik, tetapi kompleksitas teknis tidak boleh dibebankan ke pengguna utama.

## Sembilan Hukum UX

1. **Kalau sistem sudah tahu, jangan tanyakan user.**
2. **Kalau user sudah berada di konteks yang benar, jangan suruh mencari fiturnya lagi.**
3. **Kalau sistem menolak tindakan, jelaskan alasan dan jalan keluarnya.**
4. **Jangan membuat kondisi gagal terlihat seperti kondisi aman atau kosong.**
5. **Setelah tindakan, jelaskan apa yang berubah dan apa yang tidak berubah.**
6. **Setiap status yang belum selesai harus menunjukkan langkah berikutnya.**
7. **Jangan tampilkan state internal; tampilkan arti operasionalnya bagi user.**
8. **Keputusan berisiko tidak boleh menjadi default.**
9. **Keadaan sementara yang belum selesai harus menjadi pekerjaan yang terlihat.**

Aturan tambahan:

- UI mengikuti pekerjaan manusia, bukan tabel, route, engine, atau lifecycle backend.
- Jika suatu kemampuan lebih mudah ditemukan dari objek yang sedang dikerjakan, jangan buat menu terpisah.
- Informasi yang sudah diketahui dari halaman sebelumnya harus dibawa ke langkah berikutnya.
- Jangan meminta user membuat ID/kode internal yang dapat dibuat sistem.
- Jangan menjadikan checkbox “Saya memahami...” sebagai pengganti penjelasan akibat tindakan yang jelas.

## Information Architecture

### Primary navigation

Primary navigation hanya memiliki tiga tempat kerja:

1. **Beranda**
2. **Stok**
3. **Pesanan**

**Pengaturan** ditempatkan terpisah di bagian bawah karena bukan pekerjaan harian.

```text
Sistem Rekonsiliasi Stok

● Beranda
  Stok
  Pesanan

────────────────
⚙ Pengaturan
```

Route lama/teknis boleh tetap dipertahankan untuk kontrak, deep-link, test, dan migrasi bertahap. Tidak semua route perlu tampil pada sidebar.

### Beranda — judul halaman `Hari Ini`

Beranda menjadi titik awal setelah login. Judul halaman dapat memakai **Hari Ini** karena isinya menjawab:

> Apa yang perlu saya perhatikan sekarang?

Isi utama:

- ringkasan stok singkat;
- pekerjaan yang benar-benar perlu tindakan;
- masalah mendesak;
- risiko batch;
- pekerjaan yang belum selesai;
- aktivitas/notifikasi terbaru sebagai informasi sekunder.

Contoh:

```text
Hari Ini

Perlu Tindakan  3

Batas klaim TikTok hari ini
Retur RTN-281
[ Ajukan Klaim ]

Ada selisih stok
Serum A · kurang 4 unit
[ Periksa Selisih ]

Retur belum diperiksa
RTN-294
[ Periksa Retur ]
```

Jika tidak ada masalah, jangan tampilkan halaman kosong:

```text
✓ Semua aman

Tidak ada pekerjaan mendesak saat ini.
Masalah stok                 Tidak ada
Retur menunggu pemeriksaan   Tidak ada
Klaim jatuh tempo            Tidak ada
```

Notifikasi bukan workspace utama. `Unread` tidak sama dengan `actionable`.

### Lanjutkan Pekerjaan

Beranda dapat menampilkan pekerjaan nyata yang belum selesai, bukan sekadar halaman terakhir yang dikunjungi.

Contoh:

```text
Lanjutkan Pekerjaan

Hitung Stok Gudang A
18 dari 42 barang sudah dihitung
[ Lanjutkan ]

Impor Pesanan
4 baris perlu diperbaiki
[ Periksa ]
```

### Onboarding ringan

Pada pengalaman pertama, Beranda boleh memberi orientasi singkat tanpa product tour panjang:

```text
Selamat datang di Sistem Rekonsiliasi Stok

Lihat atau cari stok
[ Lihat Stok ]

Proses pesanan, retur, dan klaim
[ Lihat Pesanan ]

Pekerjaan penting akan muncul di Beranda.
```

Setelah pengguna familiar, orientasi ini tidak perlu terus ditampilkan.

### Stok

Stok menjadi rumah untuk:

- posisi stok;
- produk dan batch;
- riwayat stok;
- barang masuk;
- barang keluar;
- barang rusak/kedaluwarsa;
- hitung stok;
- masalah/selisih stok.

Detail produk:

```text
Ringkasan | Batch | Riwayat
```

Aksi utama:

```text
[ Catat Perubahan ▾ ]   [ Mulai Hitung Stok ]
```

Isi `Catat Perubahan`:

```text
+ Barang Masuk
→ Barang Keluar
× Barang Rusak / Kedaluwarsa
```

Tidak perlu menu utama terpisah untuk Receipt, Manual Outbound, Disposal, Ledger, Stocktake, Reconciliation, Entry Correction, atau FEFO.

### Pesanan sebagai workspace

Pesanan menjadi rumah untuk lifecycle marketplace:

```text
Pesanan | Retur & Klaim
```

Tindakan kontekstual:

- Impor Pesanan dari halaman Pesanan;
- pembatalan dari detail pesanan;
- retur dari pesanan terkait;
- klaim dari retur terkait.

Jangan jadikan `Simulator`, `Reservation`, `Allocation`, `Event`, `Normalization`, atau `Partial Cancellation` sebagai mental model user.

### Pengaturan

Gunakan untuk kebutuhan jarang/khusus:

- Setup Stok Awal;
- konfigurasi yang benar-benar perlu dikelola Admin;
- Status Sistem;
- Diagnostik.

Notification Operations, evaluator, outbox retry, raw processing state, dan metadata teknis masuk Diagnostik.

## Orientation dan Context

### Satu layar, satu keputusan utama

Setiap layar memiliki:

- satu judul yang menjelaskan tujuan;
- satu tindakan utama yang paling jelas;
- informasi terpenting lebih dahulu;
- tindakan tambahan secara kontekstual;
- langkah berikutnya bila pekerjaan belum selesai.

### Contextual prefill

Jika user masuk dari konteks tertentu, jangan meminta memilih ulang data yang sudah diketahui.

Contoh:

- `Stok > Serum A > Barang Keluar` → Serum A sudah terpilih;
- `Pesanan TK-281 > Buat Retur` → pesanan sudah terpilih;
- `Retur RTN-291 > Ajukan Klaim` → retur dan item eligible sudah diketahui;
- `Riwayat > Transaksi > Batalkan` → transaksi sudah terpilih.

### Pertahankan konteks daftar

Kembali dari detail harus mempertahankan:

- search;
- filter;
- sort;
- pagination/cursor;
- posisi konteks bila memungkinkan.

Gunakan label tujuan yang eksplisit:

- **Kembali ke Stok**
- **Kembali ke Pesanan**
- **Kembali ke Retur**

bukan hanya `Kembali`.

### Session recovery

Jika session habis di tengah workflow, setelah login sukses user sebaiknya kembali ke safe internal route terakhir yang masih valid. Jangan selalu melempar user ke Beranda bila konteks aman dapat dipulihkan.

### Session Recovery tanpa Auto-Replay

Session recovery mempertahankan pekerjaan, tetapi tidak boleh mengulang mutation secara otomatis.

#### Jika sesi habis sebelum submit diterima server

```text
Sesi telah berakhir.

Isian belum dikirim.
Masuk kembali untuk melanjutkan.

[ Masuk Kembali ]
```

Setelah login:

- pulihkan draft/context bila aman;
- lakukan authoritative preview ulang;
- user menekan final action lagi secara eksplisit.

#### Jika outcome submit tidak diketahui

Contoh timeout/session failure setelah request sempat dikirim:

```text
Belum dapat memastikan hasil transaksi.

Jangan kirim ulang otomatis. Periksa bukti transaksi yang sudah tersimpan terlebih dahulu.
```

Gunakan bukti durable/idempotency bila capability tersebut tersedia. Jika belum tersedia, arahkan Admin ke Riwayat Stok atau transaksi terkait sebelum menawarkan retry.

Jika ternyata sudah tersimpan:

```text
Transaksi ini sudah berhasil disimpan sebelumnya.
Tidak ada transaksi tambahan yang dibuat.

[ Lihat Transaksi ]
```

Jika belum:

```text
Transaksi belum tersimpan.

Input tetap tersedia.
[ Periksa Lagi ]
```

#### Login tidak pernah auto-submit form lama

Kembali ke safe return route boleh dilakukan.

Mengirim ulang POST/mutation tanpa tindakan baru user tidak boleh dilakukan.

#### Browser refresh/back mengikuti prinsip yang sama

Setelah success gunakan redirect/read evidence sehingga refresh tidak memunculkan resubmit transaksi.

Jika draft belum diposting, refresh hanya memulihkan state yang memang durable.

#### Preview setelah re-login dianggap stale sampai dibuktikan lagi

Stock state dapat berubah selama session terputus.

Jangan memakai preview lama sebagai dasar final commit setelah login ulang.


## Bahasa Antarmuka

### Bahasa pekerjaan, bukan implementasi

| Istilah sistem | Bahasa UI utama |
| --- | --- |
| Today Control Center | **Beranda**, judul **Hari Ini** |
| Dashboard | masuk ke **Beranda / Stok** |
| Notification Center | aktivitas/notifikasi di **Beranda** |
| Product Inventory | **Stok** |
| Stock Ledger | **Riwayat Stok** |
| Stocktake | **Hitung Stok** |
| Reconciliation | **Masalah Stok / Selisih Stok** |
| Entry Correction | **Batalkan Transaksi** |
| Manual Outbound | **Barang Keluar** |
| Receipt | **Barang Masuk** |
| Disposal | **Barang Rusak / Kedaluwarsa** |
| Authoritative Preview | **Periksa Sebelum Simpan** |
| Reversal | **Pembatalan Transaksi** |
| Projection | **Jumlah stok saat ini** bila konteks memungkinkan |
| Quantity | **Jumlah** |
| Bucket | **Kondisi Stok** |
| Actor / process | **Dilakukan oleh** |
| Occurred at | **Waktu kejadian** |
| Recorded at | **Waktu dicatat** |
| Severity | **Prioritas** |
| Lifecycle | jangan tampilkan sebagai istilah utama |

### Produk vs Barang

Gunakan konsisten:

- **Produk** = jenis/master item;
- **Barang** = unit fisik yang bergerak.

Contoh:

- Tambah Produk;
- Barang Masuk;
- Barang Keluar;
- Barang Rusak.

### Istilah stok

| Kode/domain | Bahasa UI |
| --- | --- |
| SELLABLE | **Layak Dijual** |
| RESERVED | **Sudah Dipesan** |
| AVAILABLE | **Tersedia** |
| QUARANTINE | **Ditahan** |
| DAMAGED | **Rusak** |
| ON HAND | **Stok Fisik** |

Jangan menggabungkan angka yang memiliki makna berbeda.

Jika user bertanya secara alami “kenapa stok fisik ada tetapi tersedia nol?”, UI harus mampu menjelaskan breakdown:

```text
Stok fisik       30
Rusak            -5
Ditahan         -10
Sudah dipesan   -15
──────────────────
Tersedia           0
```

### Batch

`Batch` boleh dipakai karena merupakan konsep gudang yang penting. Gunakan **Kode Batch**, bukan `Batch ID`.

Status batch harus menjelaskan arti operasional:

| Internal | UI |
| --- | --- |
| ACTIVE | **Aktif** |
| BLOCKED | **Ditahan** |
| UNBLOCK | **Lepaskan Penahanan** |
| ARCHIVE | **Nonaktifkan Batch** |
| ARCHIVED | **Tidak Aktif** |
| REACTIVATE | **Aktifkan Kembali** |
| EXPIRED | **Kedaluwarsa** |

Jangan menampilkan `FEFO Eligible`, `Effective expiry`, atau raw lifecycle sebagai status utama.

Lebih baik:

```text
Dapat digunakan
Tidak

Alasan
Batch sedang ditahan.
```

### Produk aktif/nonaktif

Gunakan **Aktif / Tidak Aktif** dan aksi **Nonaktifkan Produk / Aktifkan Kembali**. Hindari menjadikan `Archive` sebagai bahasa utama.

### Prioritas

Maksimal empat tingkat:

- **Kritis**
- **Mendesak**
- **Perlu Diperiksa**
- **Informasi**

Warna mendukung label, bukan menggantikan label.

`Belum dibaca` tidak boleh otomatis diberi warna danger jika isi notifikasinya tidak kritis.

### Status Hitung Stok

| Internal | UI |
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

Setiap status non-terminal harus disertai next action.

### Alasan selisih

Gunakan bahasa manusia seperti:

- Barang keluar belum dicatat;
- Barang masuk belum dicatat;
- Data retur tidak sesuai;
- Salah hitung batch;
- Barang rusak belum dicatat;
- Barang kedaluwarsa belum dicatat;
- Ada perubahan stok saat penghitungan;
- Perubahan stok tercatat dua kali;
- Data dari sumber gagal diproses;
- Saldo sistem tidak sesuai riwayat;
- Barang fisik hilang;
- Stok fisik lebih banyak;
- Data produk/batch salah;
- Belum diketahui.

Kode internal tetap tersedia pada Detail Teknis.

## Form dan Input

### Jangan minta ID internal

Identifier internal seperti intent ID, idempotency key, source line ref, UUID, atau nomor internal yang dapat dibuat sistem tidak boleh diminta kepada user.

Jika sistem membutuhkan nomor internal, sistem yang menghasilkan.

Jika user memang perlu memasukkan nomor eksternal, label harus spesifik:

- Nomor Surat Jalan;
- Nomor Pesanan;
- Nomor Klaim;
- Bukti / Berita Acara;
- Referensi Kegiatan.

### Field wajib dan opsional

Jangan meminta alasan/catatan untuk semua hal sampai user akhirnya menulis `ok`, `-`, atau `done`.

Alasan wajib bila memiliki nilai audit nyata, misalnya:

- pemusnahan;
- pembatalan transaksi;
- menerima selisih;
- pembatalan klaim;
- menahan/nonaktifkan batch;
- perubahan master sensitif.

Tandai field opsional secara jelas.

### Alasan, kanal, dan referensi tidak dicampur

**Alasan** menjawab mengapa barang bergerak. **Kanal/Sumber** menjawab dari mana kejadian berasal.

Jangan membuat satu pilihan campuran seperti:

```text
Shopee Promo
TikTok Sampel
Manual Rusak
```

Lebih jelas:

```text
Alasan
Sampel

Kanal / Sumber
Pengeluaran Manual
```

Untuk Barang Keluar manual dengan alasan **Bonus**, **Promo**, atau **Sampel**, current server contract membutuhkan referensi bisnis.

UI harus langsung menampilkan field wajib yang relevan:

```text
Referensi Kegiatan *
[ Campaign Agustus ]
```

Jangan menunggu submit gagal baru menjelaskan bahwa referensi diperlukan. Identifier teknis/source-line tetap dibuat sistem.

### Default waktu

Untuk operasi yang terjadi sekarang, default-kan waktu ke saat ini dan tampilkan:

```text
Waktu
Sekarang · 8 Agu 2026, 10:42 WIB
[ Ubah ]
```

Minta user mengubah hanya bila mencatat kejadian lampau.

Semua waktu operasional harus konsisten menggunakan **Asia/Jakarta / WIB**.

### Format dan satuan

Jelaskan format sebelum error terjadi:

```text
Kode Batch
[ SER-2612-B ]

Jumlah
[ 12 ] unit
```

Tampilkan satuan di angka stok kecuali header tabel sudah menjelaskan satuan.

### Inline validation

Jika data lokal saat ini cukup untuk memberi peringatan, tampilkan dekat field:

```text
Jumlah
[ 50 ]
⚠ Maksimal 22 unit tersedia saat ini.
```

Tetap lakukan authoritative validation di server. Jangan menjanjikan `stok pasti cukup` dari browser; gunakan `22 unit tersedia saat ini`.

### Form state preservation

Jika server menolak, data yang sudah diisi user tidak boleh hilang.

Contoh:

```text
Stok berubah sejak data diperiksa.
Input kamu tetap disimpan.
[ Periksa Lagi ]
```

Jika user mencoba meninggalkan form yang benar-benar sudah berubah dan belum tersimpan, boleh tampilkan peringatan kehilangan data. Jangan munculkan dialog bila form belum berubah.

## Mutation dan Confirmation

### Pola utama

1. **Isi Data**
2. **Periksa Sebelum Simpan**
3. **Konfirmasi**
4. **Bukti Berhasil**

Preview authoritative tetap berasal dari server/domain source of truth.

### Tombol menjelaskan akibat

Hindari `Submit`, `Post`, `Execute`, `Process`, atau `Confirm` jika dapat dibuat lebih jelas.

Gunakan:

- **Simpan Barang Masuk**
- **Periksa Barang Keluar**
- **Keluarkan 12 Unit**
- **Mulai Hitung Stok**
- **Simpan Hasil Hitung**
- **Batalkan Transaksi**
- **Catat Pemusnahan**
- **Catat Barang Diterima**
- **Simpan Hasil Pemeriksaan**
- **Ajukan Klaim**
- **Impor 24 Pesanan**

### Confirmation berbasis risiko

Jangan gunakan checkbox konfirmasi sebagai ritual di setiap mutation.

Gunakan confirmation kuat untuk aksi yang benar-benar berisiko:

- pengeluaran stok;
- pemusnahan;
- pembatalan transaksi;
- posting hasil hitung;
- setup saldo awal;
- nonaktifkan master penting.

Confirmation harus menjelaskan akibat dalam bahasa manusia.

### Pending dan anti double-submit

Saat submit:

```text
[ Menyimpan... ]
```

Tombol tidak boleh dapat ditekan ulang sampai hasil request diketahui.

### Preview menjadi tidak berlaku saat input berubah

Authoritative preview hanya berlaku untuk input dan basis data yang diperiksa saat preview dibuat.

Jika user mengubah field yang dapat memengaruhi request, eligibility, allocation, atau dampak stok setelah preview tampil, preview lama langsung dianggap tidak berlaku.

Contoh:

```text
Periksa Sebelum Simpan
✓ Sudah diperiksa

Jumlah diubah
10 → 12 unit

⚠ Perlu diperiksa ulang
Dampak sebelumnya sudah tidak berlaku.

[ Periksa Lagi ]
```

Sampai preview baru berhasil:

- final mutation tidak tersedia;
- preview lama tidak boleh tetap terlihat sebagai evidence yang masih sah;
- input user tetap dipertahankan;
- frontend tidak menghitung ulang FEFO, eligibility, atau stock effect sebagai pengganti authoritative server preview.

Perubahan alasan, waktu kejadian, reference, quantity, item, atau field lain yang masuk kontrak preview mengikuti prinsip yang sama.

### Retry vs Batalkan

- **Coba Lagi** = operasi sebelumnya belum berhasil.
- **Batalkan Transaksi** = operasi sebelumnya sudah berhasil dan dikoreksi melalui reversal.

Jangan mencampur keduanya.

### Setelah sukses

Success state harus memberi bukti dan next action:

```text
✓ 12 unit berhasil dikeluarkan.
Barang Keluar BK-0182
Serum A · 12 unit

[ Lihat Transaksi ]
```

Jika relevan, tawarkan tindakan berikutnya seperti `Lihat Stok`, `Catat Lagi`, `Lihat Selisih`, atau `Kembali ke Retur`.

## Jelaskan Dampak Stok

Setelah preview/success, tampilkan **apa yang berubah dan apa yang tidak berubah**.

Contoh retur:

```text
Apa yang berubah
✓ Retur RTN-281 tercatat

Stok
— Belum berubah

Stok baru berubah setelah barang diterima dan dinyatakan layak dijual.
```

Reservasi:

```text
Sudah dipesan   +4
Stok fisik       tetap
Tersedia         -4
```

Pemusnahan:

```text
Stok fisik       30 → 27
Rusak             3 → 0
```

## Workflow Khusus

### Barang Keluar dan FEFO

User memilih produk dan jumlah, bukan batch.

Penjelasan cukup:

> Sistem memilih batch dengan tanggal kedaluwarsa terdekat secara otomatis.

Preview menampilkan:

- jumlah keluar;
- batch yang dipilih sistem;
- tanggal kedaluwarsa;
- stok sebelum;
- stok setelah.

### Barang Rusak / Kedaluwarsa

#### Mendekati kedaluwarsa bukan kedaluwarsa

Batch yang **mendekati** tanggal kedaluwarsa hanya mendapat warning/risk state. Jangan menawarkan atau mengizinkan alasan **Kedaluwarsa** seolah tanggal kedaluwarsa sudah lewat.

```text
Mendekati kedaluwarsa
12 hari lagi

Batch belum dapat dicatat sebagai Kedaluwarsa.
```

Eligibility tetap berasal dari source/server dengan boundary tanggal operasional yang sah.

Jika barang memang rusak, proses melalui kondisi/alasan rusak yang sah; jangan mengubah near-expiry menjadi expired agar pemusnahan dapat diposting.

User memang memilih batch fisik exact, tetapi UI tidak perlu memakai istilah `bucket`.

Gunakan:

- **Kondisi Stok**
- **Jumlah Dimusnahkan**
- **Bukti / Berita Acara**
- **Catatan Pemusnahan**

### Hitung Stok

Alur mental user:

```text
1 Pilih Barang
2 Hitung
3 Periksa Hasil
4 Selesai
```

Form awal cukup menanyakan:

1. Apa yang ingin dihitung? Semua stok / Produk tertentu / Batch tertentu.
2. Kapan dihitung?
3. Tampilkan jumlah sistem saat menghitung? Jangan tampilkan / Tampilkan.
4. Catatan opsional.

Istilah seperti `Full inventory`, `Cycle count`, `Ad hoc`, `CONTINUOUS`, `Mode scope`, `Visibility`, `Buckets`, `Inclusion rules`, `snapshot ledger`, `rule version`, `tolerance`, dan `idempotencyKey` tidak tampil pada alur utama.

Jika backend tetap membutuhkan `Prepare → Start`, sistem boleh menjalankan tahap tersebut tanpa menjadikannya dua pekerjaan yang harus dipahami user.

Jika sesi belum siap:

```text
Belum bisa dimulai.
2 batch yang dipilih sudah tidak aktif.
[ Lihat 2 Batch ]
```

Progress:

```text
18 dari 42 barang sudah dihitung
43%
24 barang tersisa
[ Lanjut Menghitung ]
```

### Masalah Stok

Rekonsiliasi muncul ketika ada masalah, bukan sebagai pekerjaan yang harus dicari user setiap saat.

```text
Ada selisih pada Serum A

Stok tercatat       26
Stok seharusnya     22
Selisih             -4

Kemungkinan penyebab
Barang keluar ORD-281 belum tercatat lengkap.

[ Lihat Riwayat Terkait ]
```

### Pembatalan Transaksi

Entry point berada pada detail transaksi.

Jelaskan:

> Transaksi asli tidak dihapus. Sistem membuat transaksi pembatalan agar riwayat tetap dapat dilacak.

Alasan pembatalan wajib.

#### Tidak semua transaksi dapat memakai pembatalan generik

Ketersediaan **Batalkan Transaksi** mengikuti authoritative preview dan domain support, bukan sekadar karena transaksi terlihat di Riwayat.

Jika pembatalan diblokir, jelaskan alasan manusia dan arah berikutnya.

Contoh penerimaan yang barangnya sudah dipakai:

```text
Transaksi ini belum dapat dibatalkan.

Sebagian barang dari penerimaan ini sudah digunakan
pada transaksi lain.

[ Lihat Pergerakan Terkait ]
```

Blocker lain dapat mencakup:

- transaksi sudah dibatalkan;
- stok yang perlu dipulihkan/tarik kembali sudah tidak cukup;
- pembatalan akan membuat posisi stok tidak valid terhadap reservasi;
- preview sudah tidak berlaku;
- tipe transaksi memiliki workflow koreksi domain tersendiri.

Jangan menampilkan tombol generik aktif lalu membiarkan raw database error menjadi penjelasan pertama.

### Status dan langkah berikutnya Pesanan

Status harus menjawab posisi dan langkah berikutnya.

Contoh:

- **Perlu Diproses** — Siapkan barang untuk pesanan ini.
- **Dalam Pengiriman** — Tidak ada tindakan yang diperlukan sekarang.
- **Retur Belum Diperiksa** — Periksa kondisi barang yang sudah kembali.

### Retur dan Klaim

Pisahkan visual:

1. proses;
2. kondisi fisik;
3. dampak stok.

Bahasa:

- Akan Diretur;
- Belum Tiba;
- Sudah Diterima;
- Belum Diperiksa;
- Layak Dijual;
- Rusak;
- Hilang;
- Klaim Perlu Diajukan;
- Menunggu Hasil Klaim;
- Klaim Selesai.

Claim page tidak perlu menonjolkan `stage`, `eligible snapshot`, `stock effect code`, `policy`, `provenance`, atau `immutable timeline` sebagai informasi utama.

### Impor Pesanan

User mental model:

```text
1 Unggah File
2 Periksa Data
3 Impor
```

Jangan menjadikan `job`, `commit`, `canonical`, `row`, `event`, `atomic`, `rollback`, atau `idempotency` sebagai bahasa utama.

Jika 124 baris berisi 120 benar dan 4 salah:

```text
4 baris perlu diperbaiki.
Belum ada pesanan yang diimpor sampai semua kesalahan diperbaiki.
[ Lihat 4 Kesalahan ]
```

### Setup Stok Awal

Letakkan di `Pengaturan > Setup Stok Awal` dan jelaskan bahwa fitur ini khusus untuk memulai basis stok.

User flow:

```text
1 Tambahkan Stok
2 Periksa
3 Simpan
```

Jangan tampilkan `cutover`, `basis hash`, `request hash`, `atomic posting`, `projection`, atau `exact reversal` sebagai bahasa utama.

Setelah setup selesai, UI lebih menekankan bahwa setup sudah selesai daripada mengundang user membuat setup baru.

## Search, Filter, dan Daftar

### Global search

Topbar idealnya memiliki pencarian global:

```text
Cari produk, SKU, batch, pesanan, retur, atau transaksi...
```

Hasil dikelompokkan berdasarkan objek:

- Produk;
- Batch;
- Pesanan;
- Retur;
- Transaksi.

Search sebaiknya toleran terhadap variasi manusia seperti kapitalisasi atau tanda pemisah jika backend mendukungnya.

### Filter aktif harus terlihat

Contoh:

```text
[ Ditahan × ] [ Serum × ]
Menampilkan 4 dari 128 produk
[ Hapus Semua Filter ]
```

Jangan membuat user lupa bahwa dia sedang melihat subset.

### State daftar penting tersimpan di URL

Untuk list/worklist penting, state yang menentukan **subset dan urutan data** harus tersimpan di URL bila route mendukungnya:

- pencarian;
- filter;
- sort;
- pagination/cursor.

Tujuannya agar refresh, bookmark, tombol Back, dan kembali dari detail membawa user ke konteks yang sama.

Contoh state URL:

```text
?q=serum&status=ditahan
```

Jangan menyimpan ke URL:

- password;
- catatan draft yang belum disimpan;
- raw payload;
- token/secret;
- data sensitif lain.

Parameter URL yang tidak valid tidak boleh diam-diam menampilkan subset berbeda seolah benar. Gunakan fallback aman dan jelaskan filter yang benar-benar aktif.

### Riwayat Stok

Filter default:

- Tanggal;
- Produk / SKU;
- Batch;
- Jenis Perubahan;
- Nomor Referensi.

Filter teknis seperti actor/process, source type, raw bucket, recorded timestamp, reversal state, dan identifier internal masuk **Filter Lanjutan**.

### Tabel

Desktop memakai tabel data-dense. Mobile boleh menggunakan compact cards.

- quantity rata kanan;
- tabular numerals;
- sticky header bila perlu;
- status normal tenang;
- exception lebih menonjol;
- jangan menjadikan semua status sebagai badge warna-warni.

## Notification dan Pekerjaan

Bell menandakan informasi baru, bukan jumlah pekerjaan aktif.

Beranda menampilkan jumlah pekerjaan yang benar-benar perlu tindakan.

Notification preview sebaiknya memberi CTA ke pekerjaan terkait dan link akhir **Lihat semua di Beranda**, bukan membangun mental model inbox terpisah.

Jangan tampilkan tiga badge sekaligus untuk severity + lifecycle + read state jika satu status operasional dan CTA sudah cukup.

### Notification Handling Semantics

Notifikasi memberi tahu kondisi. Mengelola notifikasi tidak sama dengan menyelesaikan kondisi sumber.

#### Read state bersifat pribadi

```text
Belum dibaca
Sudah dibaca
Diarsipkan
```

hanya mengatur tampilan untuk akun Admin tersebut.

Perubahan ini tidak:

- mengubah stok;
- mengubah status retur;
- mengubah status klaim;
- menyelesaikan issue rekonsiliasi;
- mengubah status untuk Admin lain.

#### Acknowledge diterjemahkan sebagai “Sedang Ditangani”

Jika capability acknowledgment tetap tersedia:

```text
[ Tandai Sedang Ditangani ]
```

Helper:

```text
Ini tidak menyelesaikan masalah sumber.
Status selesai akan muncul setelah kondisi sumber benar-benar beres.
```

Jangan gunakan label `Acknowledged`.

#### Penanganan Kritis membutuhkan catatan audit

Untuk notification dengan severity source `CRITICAL` yang ditampilkan sebagai **Kritis**, tindakan:

```text
[ Tandai Sedang Ditangani ]
```

harus meminta catatan penanganan yang bermakna:

```text
Catatan penanganan *
[ Sedang dicek terhadap transaksi dan stok fisik. ]
```

Severity di bawahnya boleh mengikuti kontrak server yang mengizinkan catatan opsional.

Catatan penanganan:

- menjadi evidence koordinasi manusia;
- tidak mengubah stok;
- tidak menyelesaikan kondisi sumber;
- tidak menggantikan tindakan domain yang sebenarnya.

#### Resolved berasal dari source condition

Jangan menyediakan tombol generik:

```text
[ Tandai Selesai ]
```

pada notification jika tidak ada domain action yang benar-benar menyelesaikan kondisi sumber.

Contoh:

```text
Retur belum diperiksa
[ Periksa Retur ]
```

Setelah retur benar-benar diperiksa, notification dapat menjadi resolved melalui evaluator/source lifecycle.

#### Archive tidak boleh menghilangkan pekerjaan aktif dari Beranda

Jika notification diarsipkan oleh satu Admin tetapi source condition masih actionable:

```text
Beranda > Perlu Tindakan
```

tetap dapat menampilkan pekerjaan tersebut.

#### Unread tidak memakai danger sebagai makna risiko

Unread cukup ditandai dengan:

- dot;
- font lebih tebal;
- highlight ringan.

Severity risiko berasal dari source condition.

#### Notification empty tidak menyimpulkan seluruh operasi aman

Filtered empty:

```text
Tidak ada notifikasi yang cocok dengan filter ini.
```

Jangan:

```text
Kondisi operasional mungkin aman.
```

karena notification list bukan bukti lengkap kesehatan sistem.

#### Beberapa Admin dapat melihat status penanganan tanpa mengubah role model

Jika actor acknowledgment tersedia:

```text
Sedang ditangani
oleh Ayuni · 10:42 WIB
```

Semua akun tetap role `ADMIN`; ini hanya konteks koordinasi manusia.


## Error, Empty, Blocked, Partial Data, dan Recovery

### Error tidak boleh menjadi empty

Jika fetch gagal, jangan fallback ke `0`, `[]`, atau `Tidak ada masalah` seolah kondisi aman.

Gunakan:

```text
Informasi terbaru belum dapat dimuat.
Data mungkin belum lengkap.
[ Coba Lagi ]
```

### Pola error

Error harus menjawab:

1. Apa yang gagal?
2. Apakah ada perubahan stok/data?
3. Mengapa bila diketahui?
4. Apa tindakan aman berikutnya?

Contoh:

```text
Barang keluar belum disimpan.
Stok tidak berubah.
Koneksi ke server terputus.
[ Coba Lagi ]
```

### Disabled action

Setiap tombol disabled harus mempunyai alasan yang terlihat.

```text
[ Simpan Hasil Hitung ] disabled
2 barang masih perlu dihitung ulang.
```

### Stale data

Jika data berubah sejak halaman dibuka:

```text
Stok sudah berubah.
Saat halaman dibuka: 20 unit
Sekarang: 15 unit
[ Gunakan Data Terbaru ]
```

Jangan menampilkan `row version mismatch`, `stale preview`, atau raw concurrency error sebagai pesan utama.

### Konflik perubahan dari Admin lain

Satu role `ADMIN` dapat dipakai oleh beberapa akun manusia. Edit lama tidak boleh menimpa perubahan yang lebih baru secara diam-diam.

Jika master atau data editable berubah setelah user mulai mengedit:

```text
Produk ini berubah sejak kamu mulai mengedit.

Data terbaru tersedia.
Perubahan kamu belum disimpan dan tidak ditimpa.

[ Lihat Data Terbaru ]
```

Setelah data terbaru dibuka:

- pertahankan input user yang masih aman untuk dibandingkan;
- jelaskan field yang sudah berubah bila datanya tersedia;
- minta user meninjau ulang sebelum menyimpan;
- jangan melakukan blind retry dengan versi lama;
- jangan mengklaim siapa yang mengubah data bila actor tidak tersedia dari source authoritative.

`row_version`, optimistic lock token, dan kode conflict tetap detail teknis, bukan bahasa utama.

### Empty state

Empty state menjawab tindakan berikutnya.

Contoh:

```text
Tidak ada klaim yang perlu ditangani.
Semua klaim pada filter ini sudah selesai atau belum memenuhi syarat.
[ Hapus Filter ]
```

### 404/dead end

Jangan berhenti pada `Batch tidak ditemukan`.

```text
Batch tidak ditemukan.
Batch mungkin sudah tidak tersedia atau tautan sudah tidak berlaku.
[ Kembali ke Stok ] [ Cari Batch ]
```

### Draft, Prasyarat, dan Return-to-Task

#### Draft hanya berarti tersimpan jika durable

Sebelum server mengonfirmasi:

```text
Perubahan belum disimpan
```

Setelah server menyimpan:

```text
Draft tersimpan
10:42 WIB
```

Jangan menampilkan `Tersimpan otomatis` jika browser state belum durable.

#### Unsaved changes hanya muncul saat form benar-benar dirty

```text
Perubahan belum disimpan.

Jika keluar sekarang, isian akan hilang.

[ Tetap di Sini ] [ Keluar Tanpa Menyimpan ]
```

#### Blocker menawarkan prerequisite yang aman

Contoh Barang Masuk:

```text
Batch untuk produk ini belum terdaftar.

[ Tambah Batch Baru ]
```

Setelah batch dibuat, kembali ke Barang Masuk dengan produk + batch baru tetap terpilih.

Contoh import:

```text
Listing belum terhubung ke produk.

[ Atur Produk Marketplace ]
```

setelah selesai:

```text
[ Kembali Periksa Import ]
```

#### Shortcut prerequisite tidak bypass invariant

Contextual shortcut tidak boleh otomatis:

- mengaktifkan produk;
- membuat batch RETURN manual;
- menebak mapping listing;
- melepas penahanan tanpa alasan;
- mem-posting stok.

#### Return-to-task mempertahankan input yang masih valid

Saat kembali dari prerequisite:

- identity konteks tetap ada;
- quantity/catatan tetap ada bila masih valid;
- stale data diperiksa ulang sebelum final mutation.

#### Tidak semua blocker perlu CTA

Jika tidak ada tindakan user yang aman:

```text
Belum dapat dilanjutkan.
Data sedang diproses oleh sistem.
Tidak ada tindakan yang perlu dilakukan sekarang.
```

Jangan membuat tombol palsu.


### Empty State Taxonomy dan Partial Data

Tidak semua layar kosong memiliki arti yang sama.

#### First-use empty

Belum ada data karena capability belum pernah digunakan:

```text
Belum ada Produk

Tambahkan Produk pertama untuk mulai menyiapkan stok.

[ Tambah Produk ]
```

#### Filtered empty

Data ada, tetapi filter/search tidak menemukan hasil:

```text
Tidak ada Produk yang cocok.

Filter aktif
Ditahan · Serum

[ Hapus Filter ]
```

Jangan menyimpulkan bahwa kondisi operasional seluruh sistem aman.

#### True operational zero

Data berhasil dimuat dan nilai memang nol:

```text
Retur belum diperiksa
0

Tidak ada retur yang menunggu pemeriksaan.
```

Ini hanya berlaku pada scope metric tersebut.

#### Partial data

Sebagian halaman berhasil dimuat, bagian lain gagal:

```text
Sebagian informasi belum dapat dimuat

Posisi stok tersedia.
Riwayat terbaru belum dapat dimuat.

[ Coba Muat Riwayat Lagi ]
```

Header/ringkasan yang bergantung pada bagian gagal harus diberi status `Belum lengkap`.

Jangan menghitung bagian yang gagal sebagai nol.

#### No-history empty

Objek ada tetapi belum memiliki transaksi:

```text
Belum ada pergerakan stok

Produk sudah terdaftar, tetapi belum ada
Saldo Awal, Barang Masuk, atau transaksi fisik lain.
```

#### Not-found berbeda dari unauthorized

Jangan mengungkap keberadaan objek lintas organisasi.

Pesan user-facing tetap aman:

```text
Data tidak ditemukan atau tidak dapat diakses.
```

jika backend sengaja menyamakan kedua kondisi untuk keamanan.

#### Empty state tidak memakai humor yang dapat menyamarkan makna

Gunakan copy langsung dan operasional.

Jangan menulis kalimat yang membuat user menebak apakah kosong berarti aman, filter terlalu sempit, atau fetch gagal.


### Error Aman, System Health, dan Monitoring

#### Read error tidak menampilkan raw provider/server error

Primary UI tidak menampilkan:

- SQL;
- RPC;
- nama table/schema;
- environment variable;
- stack trace;
- token/secret;
- URL internal.

Gunakan fallback:

```text
Data belum dapat dimuat.

Coba muat ulang halaman.
Jika masalah tetap terjadi, lihat Status Sistem.

[ Muat Ulang ]
```

Raw detail hanya pada log/Diagnostik yang aman.

#### Jangan menampilkan instruksi developer kepada operator

Hindari:

```text
npx supabase status
Isi SUPABASE_SECRET_KEY
npm run dev
```

pada UI gudang.

#### Pekerjaan gudang dan status sistem dipisahkan

Beranda utama:

```text
Perlu Tindakan
3
```

System health:

```text
⚠ Status Sistem
Pemeriksaan otomatis mengalami masalah.

[ Lihat Status Sistem ]
```

Jangan menjumlahkan keduanya menjadi satu count.

#### System recovery tidak menyelesaikan domain work

Evaluator kembali sehat tidak otomatis menyelesaikan:

- retur belum diperiksa;
- klaim belum diajukan;
- selisih stok;
- batch kedaluwarsa bersaldo.

#### Periksa ulang bukan stock mutation

Action health/reconciliation check tidak boleh secara implisit:

- menyesuaikan stok;
- mem-posting ledger;
- menerima selisih;
- menyelesaikan retur.


## Status, Freshness, Koneksi, dan Derived State

Jangan mengklaim **Tersinkronisasi** tanpa offline/sync capability nyata.

Untuk implementasi sekarang:

- **Menyimpan...** saat request;
- **Tersimpan** setelah server mengonfirmasi;
- **Belum tersimpan** bila gagal;
- **Koneksi terputus** bila browser offline.

Tampilkan waktu freshness pada data penting:

```text
Diperbarui 10:42 WIB
```

Jika ada data baru saat user membaca tabel, hindari auto-refresh agresif yang memindahkan baris. Lebih baik:

```text
3 perubahan baru tersedia
[ Perbarui ]
```

### Kejujuran Status, Freshness, dan Derived State

#### Jangan membuat low-stock rule dari angka arbitrer

Phase ini belum menetapkan reorder point/low-stock threshold.

Jangan hard-code:

```text
<= 10 unit → Menipis
> 10 unit  → Aman
```

tanpa business rule yang disepakati.

Tampilkan fakta:

```text
Tersedia
8 unit
```

Jika benar-benar nol:

```text
Habis
0 unit tersedia
```

`Menipis` membutuhkan threshold domain yang eksplisit.

#### “Tidak ada masalah” berbeda dari “belum diperiksa”

Bedakan:

```text
✓ Tidak ada masalah ditemukan
```

```text
○ Pemeriksaan belum pernah dijalankan
```

```text
⚠ Pemeriksaan otomatis terlambat atau gagal
```

Jangan mengubah dua kondisi terakhir menjadi angka `0`.

#### Healthy state membutuhkan pemeriksaan yang fresh

```text
✓ Semua aman
Terakhir diperiksa 10:40 WIB
```

hanya jika pemeriksaan yang mendasarinya benar-benar berhasil dan masih fresh menurut rule backend.

#### “Semua aman” juga membutuhkan coverage yang lengkap

Fresh belum tentu lengkap.

Global healthy state hanya boleh digunakan bila seluruh sumber pemeriksaan yang diwajibkan untuk summary tersebut berhasil berpartisipasi dan coverage-nya dapat dibuktikan.

Jika pemeriksaan yang tersedia berhasil tetapi sebagian sumber belum tercakup:

```text
Tidak ada pekerjaan ditemukan
dari pemeriksaan yang tersedia.
```

Jika coverage yang diwajibkan gagal, terlambat, atau belum tersedia:

```text
⚠ Pemeriksaan belum lengkap

Beberapa sumber pekerjaan belum dapat diperiksa.
[ Lihat Status Sistem ]
```

Jangan mengubah partial coverage menjadi `Semua aman`, sekalipun pemeriksaan yang sempat berjalan masih fresh.

#### Bedakan waktu dimuat dan waktu data berubah

Jika yang diketahui hanya waktu fetch:

```text
Dimuat pukul 10:42 WIB
```

Jika backend memiliki timestamp perubahan:

```text
Data terakhir berubah
10:39 WIB
```

Jika evaluator memiliki timestamp:

```text
Terakhir diperiksa
10:40 WIB
```

Jangan menyebut waktu render sebagai `Update terakhir`.

#### Derived status berasal dari source resmi

Frontend tidak membuat rule paralel untuk:

- severity expiry;
- deadline stage klaim;
- eligibility action;
- reconciliation severity;
- verification state;
- FEFO eligibility.

Frontend boleh memetakan `HIGH → Mendesak`, tetapi `HIGH` harus berasal dari domain/evaluator.

#### Due date memakai makna bisnis yang tepat

Untuk klaim:

```text
Batas Klaim
10 Agu 2026 · 09:14 WIB
```

Untuk expiry:

```text
Kedaluwarsa
12 Des 2026
```

Jangan menerjemahkan setiap `due_at` sebagai `Tenggat`.

#### Deadline dan eligibility tidak sama

`Terlambat` menjelaskan waktu. Action eligibility tetap mengikuti server.

Frontend tidak boleh men-disable action hanya karena perhitungan tanggal lokal jika backend masih mengizinkannya.


## Audit Trail dan Explainability

Setiap perubahan permanen tetap dapat menjawab:

- siapa/proses yang melakukan;
- kapan kejadian berlangsung;
- kapan sistem mencatat;
- alasan;
- referensi/bukti;
- nilai sebelum dan sesudah;
- hubungan transaksi asal dan pembatalan.

UI utama menampilkan:

- Dilakukan oleh;
- Waktu;
- Alasan;
- Referensi/Bukti;
- Dampak stok.

Detail teknis menyimpan:

- UUID;
- ledger sequence;
- correlation ID;
- idempotency command;
- raw source type;
- request/basis hash;
- raw payload;
- event/evaluator/outbox metadata.

Riwayat manusia sebaiknya berbentuk cerita:

```text
8 Agu · 10:42
12 unit Serum A dikeluarkan untuk Sampel Promosi.
Dilakukan oleh Admin
Referensi: Campaign Agustus
[ Lihat Detail ]
```

### Explainability, Snapshot Historis, dan Idempotency

#### Angka stok harus dapat diceritakan

```text
Jejak Stok
Serum A

Saldo Awal
+25 unit

Barang Masuk
+10 unit

Pesanan TikTok dikirim
-4 unit

Barang Keluar
-3 unit

Retur layak dijual
+2 unit

Penyesuaian hasil hitung
-1 unit
────────────────────
Layak Dijual saat ini
29 unit
```

Raw ledger tetap tersedia pada Detail Teknis.

#### Running balance hanya jika boundary authoritative

Jika daftar hanya 10 perubahan terbaru, sebut:

```text
10 perubahan terbaru
```

Jangan menyebut `seluruh pembentuk saldo`.

#### Reversal tampil sebagai cerita koreksi

```text
Barang Keluar
-5 unit

Dibatalkan
+5 unit
Alasan: Salah jumlah
```

Transaksi awal tetap terlihat.

#### Current master dan historical snapshot dipisahkan

Jika nama produk berubah:

```text
Produk saat transaksi
Bright Serum 30 ml

Produk sekarang
Brightening Serum 30 ml
```

Order lama tetap menggunakan recipe/listing snapshot lama.

#### Duplicate identik berbeda dari conflict

Replay identik:

```text
Sudah diproses sebelumnya.
Tidak ada transaksi tambahan yang dibuat.
```

Conflict:

```text
⚠ Data berbeda dengan yang sudah tercatat.
Belum ada perubahan baru yang dibuat.

[ Periksa Data Sumber ]
```

Jangan memakai tone danger untuk duplicate aman.

#### Human actor dan system actor dibedakan

Aksi manusia:

```text
Dilakukan oleh
Ayuni
```

Aksi otomatis:

```text
Dilakukan oleh
Sistem
```

Import dapat menjelaskan:

```text
Dimulai oleh Ayuni
Diproses oleh Sistem
```

Jangan menampilkan UUID atau process name sebagai nama pelaku utama.


## Permission, Security, dan Akun Admin

Scope saat ini tetap **satu role ADMIN**.

Redesign tidak membuat Supervisor/Manager palsu.

Komponen dibuat future-ready terhadap permission untuk aksi seperti:

- pemusnahan;
- pembatalan transaksi;
- posting hasil hitung;
- saldo awal;
- diagnostik.

Jika RBAC ditambahkan kemudian, keamanan harus ditegakkan oleh server/RLS/domain guard, bukan hanya menyembunyikan tombol.

### Login dan logout aman

Login gagal karena kredensial tidak valid harus memakai pesan generik yang tidak membocorkan apakah email tertentu terdaftar.

Contoh:

```text
Email atau password tidak cocok.
Periksa kembali lalu coba lagi.
```

Jangan menampilkan raw provider error, endpoint Auth, environment variable, SQL, atau detail yang membedakan `email tidak ada` dari `password salah`.

Capability yang belum tersedia seperti signup atau reset password tidak boleh ditampilkan sebagai link palsu.

Setelah logout:

```text
Sesi telah diakhiri.
```

halaman operasional wajib tetap terlindungi. Menekan tombol **Back** tidak boleh membuka kembali data authenticated tanpa autentikasi ulang.

Ini berbeda dari session recovery: logout adalah tindakan eksplisit untuk mengakhiri akses, sehingga sistem tidak boleh memulihkan mutation/draft rahasia secara otomatis setelah logout.

### Akun Admin Individual dan Lifecycle

Satu role `ADMIN` bukan berarti satu akun bersama.

Setiap orang yang melakukan pekerjaan harus memakai akun individual agar audit dapat menjawab siapa yang melakukan tindakan.

#### Pengaturan memiliki rumah untuk Akun Admin

Ketika capability backend tersedia end-to-end:

```text
Pengaturan
→ Akun Admin
```

Daftar:

```text
Akun Admin

Ayuni
ayuni@example.com
Aktif

Falah
falah@example.com
Aktif
```

Jangan membuat menu `Role & Permission` pada fase satu role.

#### Role tidak menjadi input

Form akun tidak memiliki:

```text
Role
[ Admin / Supervisor / Operator ]
```

Semua akun aplikasi aktif adalah `ADMIN`.

Jika perlu ditampilkan:

```text
Akses
Admin
```

sebagai informasi read-only, bukan pilihan.

#### Status akun menggunakan bahasa manusia

```text
Diundang
Aktif
Tidak Aktif
Undangan Kedaluwarsa
```

Raw code `INVITED`, `ACTIVE`, `INACTIVE`, `EXPIRED` tetap detail teknis.

#### Undangan menjelaskan langkah berikutnya

```text
Ayuni
Diundang

Undangan dikirim ke
ayuni@example.com

[ Kirim Ulang Undangan ]
```

Hanya tampilkan action bila backend benar-benar mendukung invite/resend end-to-end.

Jangan membuat tombol undangan palsu yang tidak terhubung ke trusted server flow.

#### Nonaktifkan akun menjelaskan dampak

```text
Nonaktifkan akun Falah?

Akun tidak dapat masuk atau melakukan tindakan baru.
Riwayat tindakan sebelumnya tetap tersimpan.

[ Kembali ] [ Nonaktifkan Akun ]
```

Tidak ada penghapusan histori actor.

#### Jangan izinkan self-deactivation bila kontrak melarang

Jika user membuka akun sendiri:

```text
Akun ini sedang digunakan.

Untuk menonaktifkan akun sendiri,
gunakan akun Admin lain yang aktif.
```

Action nonaktif tidak tersedia.

#### Lindungi akun Admin aktif terakhir

Jika hanya tersisa satu akun aktif:

```text
Akun ini tidak dapat dinonaktifkan.

Minimal satu akun Admin aktif harus tetap tersedia
agar sistem dapat dikelola.
```

Jangan hanya menampilkan constraint/database error.

#### Akun yang dinonaktifkan saat masih memiliki sesi

Pada request berikutnya:

```text
Akun sudah tidak aktif.

Akses ke sistem dihentikan.
Hubungi pengelola jika akun perlu diaktifkan kembali.
```

Jangan menawarkan retry mutation yang sama terus-menerus.

#### Audit tetap memakai nama historis yang aman

Jika akun kemudian tidak aktif:

```text
Dilakukan oleh
Falah
```

tetap tersedia pada transaksi lama.

Jangan mengubah histori menjadi:

```text
Unknown User
```

hanya karena akun sudah nonaktif.

#### Account menu tetap sederhana

Menu akun personal:

```text
Nama
Email
Organisasi
Keluar dari akun
```

Link ke pengelolaan akun Admin boleh ditempatkan pada `Pengaturan`, bukan membuat account popover menjadi panel administrasi besar.

#### Jangan tampilkan capability sebelum backend siap

Jika invite/activate/deactivate belum memiliki server authorization, audit, dan persistence yang lengkap:

- jangan tampilkan tombol palsu;
- jangan membuat form demo;
- catat sebagai implementation gap;
- aktifkan UI hanya setelah flow end-to-end tersedia.


## Visual, Accessibility, dan House Style

### Tokens

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

### Aturan visual

- light-first;
- tenang, flat, data-dense;
- tidak card-heavy;
- border tipis sebagai separator utama;
- shadow sedikit;
- merah hanya untuk risiko/destructive nyata;
- status harus dipahami tanpa warna;
- normal state tenang, exceptional state yang berbicara;
- quantity memakai tabular numerals.

### Bantuan kontekstual

Jangan mengandalkan hover tooltip sebagai satu-satunya bantuan karena aplikasi juga dipakai pada touch device.

Gunakan helper inline atau disclosure yang dapat ditekan:

```text
Ditahan ⓘ
Stok ditahan tidak dapat digunakan sampai penahanan dilepas.
```

### Error form

Jika beberapa field salah, tampilkan ringkasan dan pindahkan fokus ke field pertama yang bermasalah. Jangan mengandalkan border merah saja.

### Accessibility Interaksi dan House Style

#### Navigation/action memakai elemen semantik

Jangan menjadikan `<tr onClick>` satu-satunya cara membuka detail.

Nama objek dapat menjadi link atau sediakan tombol:

```text
[ Buka ]
```

yang dapat menerima keyboard focus.

#### Hover bukan satu-satunya cara melihat informasi

Reason blocked, arti Tersedia, deadline, dan helper penting dapat diakses melalui:

- helper inline;
- button info;
- details;
- popover yang keyboard/touch friendly.

#### Dialog mengelola focus

Saat dialog ditutup, focus kembali ke trigger.

Danger action tidak perlu menjadi default focus.

#### Bahasa utama konsisten Indonesia

Gunakan:

```text
Sampel
Tindakan
Retur
Riwayat
Hitung Stok
Selisih
Ajukan Klaim
Simpan Hasil Klaim
```

Hindari campuran `Actions`, `Counting`, `Variance`, `Submit claim`, `Resolve claim`.

#### Sentence case dan kata kerja aktif

Gunakan:

```text
Periksa kondisi retur
Simpan barang masuk
Batalkan transaksi
```

bukan title case/uppercase berlebihan atau CTA generik.

#### First-use terminology

Gunakan:

```text
SKU / Kode Produk
```

pada first use bila membantu.

Batch tetap dipakai sebagai istilah gudang, dengan helper sederhana saat pertama dibutuhkan.

#### Reference bisnis dapat disalin

Sediakan copy action untuk:

- Nomor Pesanan;
- Nomor Retur;
- Nomor Transaksi;
- Kode Batch;
- Nomor Klaim.

Copy business reference, bukan UUID internal.


## Responsive dan Mobile Gudang

### Mobile

- sidebar menjadi drawer;
- tabel padat berubah menjadi compact card bila lebih efektif;
- target sentuh minimal 44×44 px;
- numeric input nyaman untuk jumlah;
- unit tetap terlihat;
- action final boleh sticky di bawah layar;
- status koneksi/error tidak menutupi CTA;
- jangan memaksa horizontal scroll panjang sebagai satu-satunya cara membaca tabel.

### Tablet

- navigasi ringkas;
- hanya kolom prioritas yang dipertahankan;
- detail dapat memakai sheet/split view.

### Desktop

- sidebar persistent;
- tabel memanfaatkan lebar;
- detail dapat drawer atau halaman;
- jangan memenuhi workspace dengan kartu besar.

Barcode scanner tidak ditambahkan hanya karena konteksnya gudang. Tambahkan hanya bila workflow nyata memang menggunakannya.

## Poin Plus yang Realistis

Prioritaskan kualitas kecil yang benar-benar membantu:

- global search yang baik;
- contextual prefill;
- copy nomor Pesanan/Retur/Transaksi/Batch satu klik;
- tanggal absolut + relatif (`10 Agu 2026 · 2 hari lagi`);
- `Diperbarui pukul ...` pada data penting;
- resume pekerjaan belum selesai;
- preserved filters/context;
- input tidak hilang setelah error;
- clear pending state;
- anti double-submit;
- clear stale-data recovery;
- healthy/empty state yang bermakna;
- next action pada setiap non-terminal status;
- sticky final action di mobile.

Jangan menambah dashboard customization, favorite widgets, pin module, bulk destructive action, command palette, atau barcode scanner sebelum ada kebutuhan nyata.

Bulk action hanya cocok untuk hal aman seperti `Tandai sudah dibaca` atau export bila memang dibutuhkan. Hindari bulk disposal, bulk reversal, atau bulk stock correction.

## Keputusan Aman dan Pekerjaan Belum Selesai

### Jangan preselect keputusan berisiko

Sistem boleh memberi default untuk hasil yang deterministik dan aman, tetapi tidak untuk keputusan yang menerima ketidaksesuaian atau menghasilkan dampak permanen.

Contoh review Hitung Stok:

```text
Catatan sistem       26 unit
Hasil hitung fisik   22 unit
Selisih              -4 unit

Apa yang ingin dilakukan?

○ Hitung Ulang
○ Terima Selisih
○ Perlu Penanganan
```

Untuk selisih non-zero tidak ada pilihan yang dipilih otomatis.

Jika benar-benar sama:

```text
✓ Sesuai
```

boleh ditentukan sistem.

### Mutation tidak memilih record pertama secara implisit

Form yang dapat mengubah data tidak boleh otomatis memilih:

- retur pertama;
- klaim pertama;
- pesanan pertama;
- candidate pembatalan pertama;
- produk pertama;
- batch pertama.

Default aman adalah belum ada pilihan, kecuali identity datang dari contextual action/deep-link yang eksplisit.

### Selection mengikuti filter aktif

Jika filter berubah dan record terpilih tidak lagi termasuk hasil:

- clear selection; atau
- jelaskan bahwa record berada di luar filter.

Jangan membiarkan mutation aktif pada selection tersembunyi.

### Keadaan sementara menjadi pekerjaan terlihat

Contoh:

```text
Batch asal belum diketahui
→ Verifikasi Batch Asal

Selisih belum diputuskan
→ Periksa Selisih

Retur belum seluruhnya diklasifikasikan
→ Periksa Retur

Import memiliki 4 baris salah
→ Perbaiki 4 Baris
```

State belum selesai tidak boleh hanya tersimpan di database.

### Hitung Stok menggunakan mode kerja berurutan

Untuk puluhan item, mode utama:

```text
Hitung Stok

18 dari 42 selesai

Barang 19 dari 42

Serum A
SKU SRM-001
Batch SER-2612-B

Jumlah fisik
[     ] unit

Catatan
[ Opsional ]

[ Simpan & Berikutnya ]
```

Sediakan pencarian SKU/batch dan overview seluruh item untuk lompat bila urutan fisik gudang berbeda.

### Konfirmasi nol hanya ketika nilai nol dimasukkan

```text
Jumlah fisik
[ 0 ]

⚠ Nilai stok 0 dimasukkan.

☐ Ya, barang fisik benar-benar tidak ada.
```

Nilai kosong tidak pernah dianggap nol.

### Conservation check untuk pembagian quantity

Pada inspeksi retur:

```text
Barang diterima       5 unit

Layak Dijual          3
Rusak                 1
────────────────────────
Sudah diperiksa       4
Belum ditentukan      1
```

Final action tetap disabled dengan alasan terlihat sampai seluruh quantity diklasifikasikan.

## Visibilitas Fisik dan Scope Quantity

### Tidak aktif tidak berarti tidak ada

Produk/batch tidak aktif, ditahan, atau kedaluwarsa tetap dapat memiliki stok fisik dan histori.

```text
Serum A
Tidak Aktif

Stok fisik
12 unit

Tidak dapat dipakai untuk transaksi baru.
12 unit tetap tercatat dan dapat ditelusuri.
```

### Default Stok tidak menyembunyikan barang fisik

Tetap tampilkan:

- produk tidak aktif yang masih bersaldo;
- batch ditahan yang masih bersaldo;
- batch kedaluwarsa yang masih bersaldo;
- batch retur yang masih bersaldo;
- batch dengan provenance bermasalah yang perlu tindakan.

Master tidak aktif bersaldo nol boleh masuk filter histori, tetapi tetap searchable.

### Tidak Aktif membatasi transaksi baru, bukan investigasi dan hitung fisik

Produk atau batch tidak aktif yang masih memiliki saldo fisik tetap merupakan benda gudang yang harus dapat diverifikasi.

Karena itu, sesuai scope authoritative:

- saldo fisiknya tetap terlihat;
- record tetap dapat dicari dan dibuka;
- riwayat dan audit tetap tersedia;
- record bersaldo tetap dapat masuk scope **Hitung Stok**;
- historical return atau exact correction yang memang masih sah tetap dapat menelusuri identity lama.

UI dapat menjelaskan:

```text
Tidak Aktif

Tidak dapat digunakan untuk transaksi baru.
Stok fisik dan riwayat tetap dapat diperiksa.

[ Lihat Riwayat ] [ Hitung Stok ]
```

`Hitung Stok` hanya ditampilkan bila record memang termasuk scope stocktake authoritative. Jangan mengaktifkan kembali master hanya agar stok fisiknya dapat dihitung.

### Kedaluwarsa tidak membuat movement otomatis

```text
Batch SER-2608-A
Kedaluwarsa

4 unit masih berada di gudang.

[ Catat Pemusnahan ]
```

Expiry sendiri tidak mengurangi ledger.

### Product-scoped dan batch-scoped quantity tidak dicampur

Reservasi sebelum shipment adalah level produk.

Detail produk:

```text
Layak Dijual       26
Sudah Dipesan       4
Tersedia           22
```

Detail batch menonjolkan quantity batch:

```text
Batch SER-2612-B

Layak Dijual       16
Ditahan              2
Rusak                1
```

Jika product reservation perlu ditampilkan pada halaman batch:

```text
Untuk seluruh Serum A
Sudah Dipesan 4 unit
Belum dialokasikan ke batch tertentu.
```

Jangan mengurangi reservasi produk yang sama pada setiap batch.

### Reason disposal dan source stock adalah dua konsep

Contoh:

```text
Alasan Pemusnahan
Kedaluwarsa

Diambil dari
Layak Dijual

Jumlah
4 unit
```

`Kedaluwarsa` bukan pseudo-bucket baru.

### Batch RETURN menjelaskan asalnya

```text
Jenis
Batch Retur

Dibuat dari
Retur RTN-281

[ Lihat Retur ]
```

Batch RETURN dibuat oleh workflow retur, bukan dipilih manual saat membuat batch normal.

## Marketplace, Bundle, Retur, dan Klaim

### Status marketplace tidak sama dengan penerimaan fisik gudang

Marketplace dapat menyatakan retur **diterima**, tetapi status sumber tersebut bukan bukti bahwa Admin gudang sudah melihat barang secara fisik.

Jika keduanya berbeda, tampilkan terpisah:

```text
Status Marketplace
Retur diterima

Status Gudang
Belum dikonfirmasi tiba

Dampak stok
Belum berubah
```

Jangan otomatis:

- mengubah status gudang menjadi Sudah Diterima;
- menjalankan inspeksi;
- membuat batch RETURN;
- menambah stok;

hanya karena source marketplace menyebut `received`.

Penerimaan fisik tetap merupakan tindakan/command gudang tersendiri dan pada Phase 2 tetap stock-neutral sampai hasil inspeksi `SELLABLE` yang sah.

### Status pesanan dan dampak stok dipisahkan

Sebelum trigger physical outbound:

```text
Status
Siap Dikirim

Stok
4 unit sudah dipesan
Stok fisik belum berubah
```

Setelah trigger channel yang sah:

```text
Status
Dalam Pengiriman

Stok
4 unit sudah keluar dari gudang
```

Shopee mengurangi stok saat `SHIPPED`; TikTok Shop saat `IN_TRANSIT`.

User tidak memilih trigger tersebut.

### Pembatalan menjelaskan posisi barang

Sebelum shipment:

```text
Batalkan 2 unit

Dampak
2 unit tidak lagi dipesan.
Stok fisik tidak berubah.
```

Sesudah shipment:

```text
Batalkan Transaksi

Dampak
Sistem membuat pembatalan sesuai shipment asli.
Transaksi awal tetap tersimpan.
```

Jika barang sudah kembali secara fisik, arahkan ke Retur.

### Partial cancellation/return terlihat per item

Jangan hanya menampilkan status header `PARTIALLY_*`.

```text
Serum A

Dipesan             5
Belum dikirim       2
Sudah dikirim       3
Dibatalkan          1
Diretur              1
```

Action hanya tersedia untuk quantity yang masih eligible.

### Quantity pembatalan menjelaskan unit yang sudah terikat retur

Jumlah yang sudah menjadi expected return tidak boleh terlihat seolah masih bebas dibatalkan setelah shipment.

Contoh:

```text
Serum A

Sudah dikirim                5
Akan diretur                 2
Sudah dibatalkan             1
Masih dapat dibatalkan       2
```

Jika user memasukkan 3 unit:

```text
Maksimal 2 unit dapat dibatalkan.

2 unit lainnya sudah tercatat akan diretur.
```

Jangan hanya menampilkan `quantity exceeds eligible amount`.

Nilai `Masih dapat dibatalkan` tetap berasal dari source authoritative. Frontend tidak menghitung sendiri batas pembatalan dari angka yang kebetulan terlihat pada layar.

### Bundle ditampilkan sebagai produk pelanggan dan komponen stok

```text
Glow Set x1

Isi paket saat pesanan dibuat
Serum A       1
Cleanser B    1
Toner C       2
```

Movement tetap terjadi pada produk satuan.

### Versi resep baru tidak mengubah order lama

```text
Perubahan berlaku untuk pesanan baru mulai
10 Agu 2026 · 00:00 WIB.

Pesanan lama tetap memakai isi paket
yang tersimpan saat pesanan dibuat.
```

### Produk Marketplace adalah secondary management di Pesanan

Capability listing mapping/versioned recipe tetap harus dapat ditemukan, tetapi bukan menu sidebar baru.

Gunakan label:

```text
Produk Marketplace
Isi Paket
Versi
Berlaku Mulai
Riwayat Versi
```

bukan `Listing Mapping Registry`, `Recipe`, atau `Normalization`.

### Retur Rusak/Hilang tidak membuat movement kedua

```text
Kondisi Retur
Rusak · 2 unit

Dampak stok
Tidak ada perubahan stok baru
```

```text
Kondisi Retur
Hilang · 1 unit

Dampak stok
Tidak ada perubahan stok baru
```

Hanya outcome Layak Dijual membuat inbound ke batch RETURN baru.

### Provenance retur Belum Diverifikasi membatasi tindakan secara jelas

Jika asal barang belum dapat dibuktikan, UI harus menjelaskan bahwa blocker berasal dari provenance, bukan dari kondisi fisik semata.

```text
Asal barang belum terverifikasi

Barang belum dapat dimasukkan kembali
sebagai Layak Dijual.

[ Verifikasi Asal Barang ]
```

CTA hanya ditampilkan bila verifikasi provenance memang tersedia end-to-end.

Jika kondisi fisik `Rusak` masih boleh dicatat sebagai audit-only menurut kontrak server:

```text
Rusak · 1 unit

Dampak stok
Tidak ada perubahan stok baru.

Asal barang masih belum terverifikasi.
```

Jangan membuat outcome audit-only terlihat seperti penambahan stok `DAMAGED`, dan jangan menawarkan `Layak Dijual` sampai server menyatakan provenance yang diperlukan sudah valid.

### Claim process, result, dan stock effect dipisahkan

```text
Status
Menunggu Hasil TikTok

Hasil
Belum ada

Dampak stok
Tidak ada perubahan
```

Setelah selesai:

```text
Status
Selesai

Hasil
Disetujui
```

Klaim tidak mengubah stok.

### Deadline klaim menjelaskan basisnya

```text
Retur dibuat
1 Jul 2026 · 09:14 WIB

Batas Klaim
10 Agu 2026 · 09:14 WIB
2 hari lagi
```

Helper:

```text
Batas klaim dihitung 40 hari sejak retur dibuat.
```

### Late arrival menjadi pekerjaan eksplisit

Jika barang yang sebelumnya dinyatakan hilang tiba:

```text
⚠ Barang yang sebelumnya dinyatakan hilang sudah tiba

Serum A · 2 unit

[ Catat Kedatangan ]
```

Status klaim dan dampak stok tetap terpisah.

## Worklist, Count, dan Navigasi Kontekstual

### Satu condition aktif memiliki satu identity pekerjaan

Kondisi yang sama boleh muncul di Beranda, Stok, dan bell, tetapi tidak menjadi tiga task berbeda.

`Perlu Tindakan 3` berarti tiga obligation unik, bukan tiga notification card.

### Unread count berbeda dari actionable count

```text
Bell
8 belum dibaca

Beranda
3 perlu tindakan
```

### Count page berbeda dari total antrean

Jika summary hanya menghitung page aktif:

```text
2 item pada halaman ini
```

Jangan menampilkan `2` sebagai total global.

### Worklist menggunakan order server yang stabil

Prioritas bisnis mengikuti backend/read model, misalnya:

1. urgency/severity;
2. deadline;
3. waktu;
4. stable tie-breaker.

Jangan client-sort hanya page aktif jika pagination server menentukan urutan.

### Item baru tidak memindahkan daftar secara agresif

```text
3 pekerjaan baru tersedia
[ Perbarui ]
```

lebih aman daripada auto-refresh yang menggeser row saat user membaca.

### Row list tidak mengeksekusi mutation berisiko langsung

Default action:

```text
[ Buka ]
[ Periksa ]
[ Lihat Detail ]
```

Pembatalan, pemusnahan, dan posting dilakukan dari detail/preview.

### Breadcrumb mengikuti mental model, bukan route lama

Contoh:

```text
/entry-corrections
→ Stok / Riwayat / Batalkan Transaksi

/returns
→ Pesanan / Retur & Klaim

/opening-balances
→ Pengaturan / Setup Stok Awal
```

Sidebar menandai workspace yang sesuai.

### Hanya ada satu Beranda user-facing

Selama `/today` menjadi pilot:

```text
Beranda → /today
```

Root legacy tidak menjadi workspace keempat.

Login/logo tanpa return route menuju canonical Beranda.

## Stocktake Berjalan dan FEFO Explainability

### Continuous stocktake tidak menjadi pilihan user

Jika fase ini memang memakai mode internal continuous, jangan tampilkan:

```text
Mode CONTINUOUS
```

sebagai konfigurasi user.

Pada review gunakan:

```text
Catatan sistem saat dihitung
26 unit

Hasil hitung fisik
22 unit
```

Backend memperhitungkan movement yang sah sampai boundary attempt.

### Pergerakan selama sesi tidak otomatis dianggap selisih

User tidak menghitung manual:

```text
snapshot + movement setelah snapshot
```

Expected quantity tetap dihitung server.

### Blind count tetap blind saat counting

Expected quantity baru terlihat saat review.

### Attempt history adalah evidence

Jika hitung ulang:

```text
Sebelumnya
20 unit

Hasil hitung ulang
22 unit
```

Metadata attempt/cutoff masuk Detail Teknis.

### FEFO menjelaskan eligibility

Copy utama:

```text
Sistem memilih batch dengan tanggal kedaluwarsa
terdekat dari batch yang masih dapat digunakan.
```

Jika batch dilewati:

```text
SER-2608-A
Tidak digunakan

Alasan
Terlalu dekat dengan tanggal kedaluwarsa.
```

### Safety buffer adalah rule, bukan field user

Jika tersedia:

```text
Batas penggunaan batch
Minimal 14 hari sebelum kedaluwarsa
```

User tidak mengubah safety buffer dari form Barang Keluar.

### Shortage menjelaskan sumber kekurangan

```text
Diminta
12 unit

Stok fisik layak dijual
20 unit

Dapat digunakan untuk pengeluaran ini
8 unit

Kurang
4 unit
```

Jangan memberi pilihan `Pilih Batch Lain`.

## First-Run dan Setup Stok Awal

### Belum setup

```text
Setup Stok Awal

Stok awal belum disiapkan.

[ Mulai Setup Stok Awal ]
```

### Ada draft aktif

```text
Setup Stok Awal
Belum Selesai

Draft terakhir
7 Agu 2026 · 16:20 WIB

[ Lanjutkan Setup ]
```

Jangan menonjolkan pembuatan draft baru jika draft aktif masih dapat dilanjutkan.

### Sudah posted

```text
✓ Setup Stok Awal selesai

Verifikasi
Belum seluruhnya diverifikasi

[ Lihat Detail ] [ Mulai Hitung Stok ]
```

Default menjadi summary read-only.

### Verifikasi stok awal adalah pekerjaan setelah setup

Status:

```text
Belum Diverifikasi
Sebagian Terverifikasi
Terverifikasi
```

Opening balance perkiraan tetap UNVERIFIED sampai opname pertama yang relevan.

### Koreksi setup adalah exceptional action

```text
•••
Koreksi Setup Stok Awal
```

bukan action harian.

Transaksi awal tidak dihapus; correction memakai reversal yang dapat ditelusuri.

### Bahasa user-facing

Gunakan:

- Setup Stok Awal;
- Draft Setup;
- Periksa Stok Awal;
- Simpan Stok Awal;
- Koreksi Setup;
- Saldo Awal Pengganti.

`Cutover`, hash, dan exact reversal tetap Detail Teknis.

### First-Run Readiness dan Guided Setup

Orang yang pertama kali membuka sistem tidak boleh diminta mengetahui sendiri urutan dependensi master dan stok.

#### Sistem kosong memiliki jalur setup yang eksplisit

Jika belum ada data operasional yang cukup:

```text
Setup dasar Sistem Rekonsiliasi Stok belum lengkap

Selesaikan setup dasar:

1. Tambahkan Produk
2. Tambahkan Batch
3. Masukkan dan simpan Stok Awal

Setelah stok awal disimpan, verifikasi melalui Hitung Stok menjadi pekerjaan lanjutan. Status stok awal tetap **Belum Diverifikasi** sampai hitung fisik pertama yang relevan selesai.
```

Tampilkan progress nyata, bukan wizard kosmetik.

Contoh:

```text
Setup Awal

✓ Produk            70 terdaftar
✓ Batch             126 terdaftar
○ Stok Awal         Belum selesai
○ Verifikasi        Belum dimulai

[ Lanjutkan Setup Stok Awal ]
```

#### Produk dibuat tanpa stok

Setelah Produk berhasil dibuat:

```text
✓ Produk berhasil ditambahkan

Serum A
SKU SRM-001

Stok
Belum ada

Langkah berikutnya
Tambahkan Batch untuk produk ini.

[ Tambah Batch ]
```

Jangan membuat user mengira `Simpan Produk` juga membuat saldo.

#### Batch dibuat tanpa stok

Setelah Batch berhasil dibuat:

```text
✓ Batch SER-2612-B berhasil dibuat

Stok
Belum berubah

Langkah berikutnya
Masukkan stok melalui Setup Stok Awal atau Barang Masuk,
sesuai konteks penggunaan.

[ Kembali ke Produk ]
```

Pada first-run/cutover, CTA utama dapat langsung menuju Setup Stok Awal.

#### Setup Stok Awal memeriksa prerequisite sebelum membuka form

Jika belum ada batch eligible:

```text
Setup Stok Awal belum dapat dimulai

Stok awal membutuhkan Produk dan Batch yang sudah terdaftar.

[ Tambah Produk ]   [ Tambah Batch ]
```

Jangan membuka draft kosong yang mustahil diselesaikan.

#### Setelah Stok Awal diposting, arahkan ke verifikasi

```text
✓ Stok awal berhasil disimpan

Status
Belum Diverifikasi

Langkah berikutnya
Hitung stok fisik untuk memverifikasi saldo awal.

[ Mulai Hitung Stok ]
```

#### Onboarding menghilang setelah sistem siap

Checklist setup tidak menjadi card permanen setelah seluruh prerequisite selesai.

Setelah ready, Beranda kembali fokus pada pekerjaan harian.

#### Readiness berasal dari data nyata

Frontend tidak menyimpan flag lokal `onboardingComplete`.

Status readiness berasal dari kondisi server/read model seperti:

- produk ada;
- batch yang relevan ada;
- opening balance aktif/posted bila diperlukan;
- verification status.

Jika data tidak cukup untuk menyimpulkan readiness, tampilkan keadaan tidak pasti, bukan `Setup selesai`.


## Penerimaan sebagai Dokumen Multi-Item

Penerimaan barang mengikuti mental model dokumen fisik seperti surat jalan, bukan satu transaksi terpisah untuk setiap produk.

### Pisahkan field dokumen dan field baris

Bagian dokumen:

```text
Barang Masuk

Nomor / Referensi Penerimaan
SJ-MAKLON-2026-001

Waktu diterima
8 Agu 2026 · 10:42 WIB

Catatan
Opsional
```

Bagian item:

```text
Barang diterima

1. Serum A
   Batch SER-2612-B
   10 unit

2. Toner B
   Batch TON-2608-A
   24 unit

[ Tambah Produk ]
```

Nomor dokumen, waktu, dan catatan tidak perlu diulang pada setiap baris.

### Satu dokumen dapat memiliki banyak produk dan batch

Preview:

```text
Periksa Barang Masuk

2 produk
2 batch
34 unit total

Serum A
SER-2612-B
+10 unit

Toner B
TON-2608-A
+24 unit
```

Posting tetap atomik sesuai kontrak server.

Jika satu baris invalid dan transaction scope bersifat atomic, jelaskan bahwa belum ada stok yang berubah.

### Produk yang sama boleh muncul pada batch berbeda

Contoh valid:

```text
Serum A · Batch SER-2612-A · 5 unit
Serum A · Batch SER-2612-B · 8 unit
```

Jangan memakai rule `satu produk hanya boleh sekali` pada penerimaan jika batch berbeda.

Untuk pasangan produk + batch yang sama dua kali dalam dokumen:

- gabungkan quantity bila aman; atau
- beri peringatan duplikat dan minta user memeriksa.

Jangan membuat dua line identik tanpa alasan.

### Batch yang belum ada dapat dibuat dari flow penerimaan

```text
Batch
[ Pilih batch... ]

Tidak menemukan batch?
[ Tambah Batch Baru ]
```

Quick-create hanya meminta field master minimum yang memang dibutuhkan.

Setelah batch berhasil dibuat:

- kembali ke draft penerimaan;
- produk tetap terpilih;
- batch baru otomatis menjadi pilihan aktif;
- quantity dan field dokumen tetap dipertahankan.

Membuat batch tidak menambah stok. Stok baru berubah ketika Penerimaan diposting.

### Batch quick-create tetap mengikuti jenis yang sah

Penerimaan normal hanya membuat/memakai batch `STANDARD`.

Jangan menawarkan pilihan:

```text
STANDARD
RETURN
UNIDENTIFIED_RETURN
```

kepada operator.

### Source-line identity dibuat sistem

User tidak memasukkan:

```text
UI-1
UI-2
sourceLineRef
```

Sistem membuat identity baris untuk idempotency/audit.

### Duplicate reference memberi jalur ke dokumen lama

Jika nomor penerimaan sudah pernah berhasil diproses:

```text
Penerimaan ini sudah tercatat sebelumnya.

SJ-MAKLON-2026-001

Tidak ada stok tambahan yang dibuat.

[ Lihat Penerimaan Sebelumnya ]
```

Jika reference sama tetapi isi berbeda, tampilkan conflict dan jangan menganggapnya replay aman.

### Success membuka evidence dokumen

Setelah berhasil:

```text
✓ Barang masuk berhasil disimpan

Penerimaan
RCV-281

2 produk
34 unit

Dampak stok
+34 unit

[ Lihat Detail Penerimaan ]
[ Catat Penerimaan Lain ]
```

Refresh harus tetap dapat membaca receipt yang sama dari server.

Jangan hanya kembali ke dashboard dengan toast yang hilang.

## Investigasi dan Penyelesaian Masalah Rekonsiliasi

Masalah rekonsiliasi tidak boleh ditutup seperti notifikasi biasa.

### Detail masalah menjawab lima hal

```text
Masalah Stok
Serum A

Apa yang ditemukan?
Catatan stok berbeda 4 unit.

Seharusnya
22 unit

Tercatat
26 unit

Bukti
[ Lihat transaksi terkait ]

Kemungkinan penyebab
Barang keluar belum tercatat.

Langkah berikutnya
[ Periksa Riwayat Stok ]
```

### “Selesai” membutuhkan evidence penyelesaian

Flow:

```text
Masalah ditemukan
→ lihat evidence
→ lakukan tindakan domain yang sah
→ tulis catatan penyelesaian
→ jalankan ulang check
→ check lulus
→ Selesai
```

Jangan menyediakan tombol:

```text
[ Tandai Selesai ]
```

yang dapat menutup issue tanpa verifikasi.

### Tindakan domain tetap dilakukan di tempat yang benar

Contoh issue projection drift:

```text
[ Periksa Detail ]
```

dapat mengarah ke workflow yang sah seperti:

- rebuild projection dari ledger;
- koreksi transaksi melalui reversal;
- verifikasi retur;
- perbaiki mapping;
- tindakan domain lain yang memang didukung.

Rekonsiliasi sendiri tidak mengedit saldo.

### Setelah remediasi, kembali ke issue asal

Jika user berangkat dari:

```text
Masalah Stok
→ Transaksi TRX-281
→ Batalkan Transaksi
```

setelah reversal berhasil:

```text
✓ Transaksi berhasil dibatalkan

Masalah asal
Serum A · selisih 4 unit

[ Kembali Periksa Masalah ]
```

User tidak perlu mencari issue yang sama dari awal.

### Rerun menjelaskan hasil

Jika lulus:

```text
✓ Masalah sudah tidak ditemukan

Diperiksa ulang
8 Agu 2026 · 11:04 WIB

Diselesaikan oleh
Ayuni

Catatan
Transaksi barang keluar yang salah sudah dibatalkan.
```

Jika masih gagal:

```text
Masalah masih ditemukan.

Selisih sekarang
2 unit

[ Lanjutkan Pemeriksaan ]
```

Jangan menampilkan success hanya karena command koreksi berhasil; yang menentukan issue selesai adalah hasil check.

### Selisih yang diterima harus eksplisit

Jika aturan domain memang mengizinkan selisih diterima tanpa mengubah fakta agar terlihat “cocok”:

```text
Terima sebagai pengecualian?

Masalah tetap tercatat sebagai exception
dengan alasan dan bukti.

Alasan
[____________________________]

[ Kembali ] [ Terima Pengecualian ]
```

Ini bukan sama dengan `Aman`.

Status dapat menggunakan:

```text
Pengecualian Diterima
```

dan histori tetap menunjukkan nilai yang berbeda.

### Resolution history tidak hilang

Issue yang selesai tetap dapat dibuka:

```text
Status
Selesai

Pertama ditemukan
7 Agu 2026 · 09:12 WIB

Selesai
8 Agu 2026 · 11:04 WIB

Diselesaikan oleh
Ayuni

Catatan
...
```

Run lama dan evidence lama tetap tersedia.

### Satu role tidak menghapus actor resolution

Walaupun semua user ber-role Admin, tetap tampilkan actor individual pada resolution note dan rerun evidence.

### Fakta, Evidence, dan Kemungkinan Penyebab

Sistem tidak boleh menyajikan dugaan akar masalah sebagai fakta.

#### Pisahkan fakta dari hipotesis

Contoh:

```text
Fakta
Catatan stok berbeda 4 unit.

Evidence
Transaksi TRX-281
Batch SER-2612-B
Ledger #1842

Kemungkinan penyebab
Barang keluar belum tercatat.
```

Jangan:

```text
Penyebab
Admin lupa mencatat barang keluar.
```

jika sistem belum memiliki bukti langsung.

#### Gunakan label “Kemungkinan penyebab”

Root-cause hint menggunakan bahasa seperti:

```text
Kemungkinan penyebab
Periksa apakah penerimaan ini tercatat dua kali.
```

atau:

```text
Hal yang perlu diperiksa
Mapping listing marketplace mungkin belum sesuai.
```

#### Jangan menuduh actor atau channel tanpa evidence

Hindari:

```text
Kesalahan Admin
Kesalahan Shopee
Kesalahan kurir
```

kecuali data sumber memang membuktikan kejadian tersebut.

Sistem dapat mengatakan:

```text
Event sumber dengan referensi sama tercatat dua kali.
```

jika duplicate effect benar-benar ditemukan.

#### Evidence dapat dibuka

Setiap fakta utama sebaiknya memiliki jalur drill-down:

```text
[ Lihat Transaksi ]
[ Lihat Batch ]
[ Lihat Pesanan ]
[ Lihat Retur ]
[ Lihat Detail Teknis ]
```

sesuai object yang tersedia.

#### Unknown tetap boleh unknown

Jika tidak ada root-cause hint yang cukup:

```text
Penyebab belum diketahui.

Periksa transaksi dan aktivitas terkait sebelum melakukan koreksi.
```

lebih aman daripada menebak.

#### Perbaikan tidak mengikuti hint secara otomatis

Hint hanya membantu investigasi.

Sistem tidak otomatis:

- membalik transaksi;
- menghapus duplicate;
- mengubah projection;
- menerima exception;

hanya karena satu kemungkinan penyebab dianggap paling mungkin.

#### Setelah evidence baru muncul, hint boleh berubah

Histori issue tetap mempertahankan evidence sebelumnya.

UI terbaru dapat menampilkan:

```text
Kemungkinan penyebab terbaru
...
```

tanpa menulis ulang fakta historis run lama.


## Domain Guardrails

Penyederhanaan UI tidak boleh mengubah:

1. Ledger append-only sebagai source of truth.
2. Projection hanya untuk pembacaan cepat.
3. Duplicate command/event maksimal satu domain effect.
4. Reservasi tidak mengubah stok fisik.
5. Shopee mengurangi stok saat SHIPPED.
6. TikTok mengurangi stok saat IN_TRANSIT.
7. FEFO otomatis dan Admin tidak memilih batch.
8. Expected return tidak mengubah stok.
9. Retur SELLABLE membuat inbound ke batch RETURN baru.
10. Retur DAMAGED/LOST tidak membuat movement kedua.
11. LOST tetap terpisah dari DAMAGED.
12. Koreksi transaksi menggunakan reversal.
13. Penyesuaian hasil hitung merupakan proses terpisah.
14. Preview authoritative dipertahankan untuk stock-out dan koreksi manual.
15. Navigasi baru tidak menghilangkan route contract, deep-link, audit evidence, atau safe internal route validation.
16. Scope tetap satu role ADMIN sampai kontrak security baru dibuat.
17. UI tidak mengklaim offline sync tanpa capability nyata.
18. Client-side simplification tidak boleh mengganti authoritative server validation.

19. Alasan dan kanal tetap merupakan dimensi terpisah.
20. Barang Keluar manual untuk Bonus/Promo/Sampel tetap memerlukan referensi bisnis sesuai kontrak server.
21. Status retur dari marketplace tidak menjadi bukti penerimaan fisik gudang.

## State Wajib

Setiap flow menyediakan state nyata:

- loading;
- empty;
- error;
- blocked;
- success;
- stale data/preview;
- saving/pending;
- replay/idempotent success bila relevan;
- connection failure;
- data baru tersedia bila refresh diperlukan.

Tidak boleh ada placeholder, tombol mati tanpa alasan, link palsu, form palsu, atau indikator sync palsu.

## Usability Audit Gate

Sebelum page group dianggap selesai, pengguna baru yang tidak memahami backend harus dapat:

1. Masuk dan mengetahui titik awal aplikasi.
2. Mengetahui apa yang perlu diperiksa sekarang.
3. Mencari produk/SKU/batch/pesanan/retur/transaksi.
4. Memahami Stok Fisik, Layak Dijual, Sudah Dipesan, Tersedia, Ditahan, dan Rusak.
5. Mengetahui kenapa stok ada tetapi tidak bisa digunakan.
6. Mencatat barang masuk.
7. Mengeluarkan barang tanpa memilih FEFO batch.
8. Mencatat pemusnahan dengan alasan/bukti.
9. Memulai dan melanjutkan hitung stok tanpa memahami scope/bucket/visibility/snapshot.
10. Mengetahui progres hitung dan pekerjaan tersisa.
11. Memahami penyebab selisih dan membuka bukti terkait.
12. Menemukan transaksi salah dari riwayat dan membatalkannya tanpa memahami reversal.
13. Memproses pesanan-retur-klaim sebagai satu cerita.
14. Mengimpor pesanan tanpa memahami job/commit/canonical/event.
15. Mengetahui apakah mutation benar-benar tersimpan.
16. Memulihkan workflow setelah error, stale data, atau session habis.
17. Membaca siapa/kapan/mengapa suatu perubahan terjadi.
18. Mengetahui langkah berikutnya dari setiap status non-terminal.
19. Menemukan jalan keluar dari empty/404/blocked state.
20. Menyelesaikan workflow utama pada mobile/tablet tanpa bergantung pada hover.

Pertanyaan evaluasi tiap layar:

- Saya sedang melihat apa?
- Ada masalah atau tidak?
- Apa tindakan utama saya?
- Mengapa tindakan tertentu tidak tersedia?
- Apa akibat tombol utama?
- Apa yang berubah pada stok?
- Apakah tindakan berhasil?
- Jika gagal, apa yang harus saya lakukan?
- Jika status belum selesai, apa langkah berikutnya?
- Apakah ada istilah yang hanya dipahami pembuat sistem?

Jika user masih perlu bertanya kepada pembuat sistem untuk pekerjaan umum, desain belum selesai.

## Urutan Migrasi

1. Kunci guide ini sebagai kontrak UX.
2. Konsistenkan nama user-facing menjadi **Sistem Rekonsiliasi Stok**.
3. Pertahankan route/business contract sambil menyederhanakan navigation menjadi Beranda, Stok, Pesanan, Pengaturan.
4. Migrasikan Beranda/Hari Ini sebagai pilot operator-first.
5. Satukan pengalaman Stok: posisi, produk/batch, riwayat, perubahan stok, hitung stok, masalah stok.
6. Satukan pengalaman Pesanan: pesanan, import sebagai action, retur/klaim, contextual actions.
7. Pindahkan setup dan diagnostik ke Pengaturan.
8. Terapkan dictionary bahasa UI, status + next action, form defaults, error/recovery, dan contextual prefill.
9. Terapkan freshness/connection state, audit manusia, mobile ergonomics, dan accessibility.
10. Jalankan usability scenarios sebelum cleanup legacy UI dinyatakan selesai.

Setiap kelompok harus dapat direview dan divalidasi secara terpisah. Penyederhanaan presentasi tidak boleh mengubah kontrak domain yang sudah lolos test.
