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

## Tujuh Hukum UX

1. **Kalau sistem sudah tahu, jangan tanyakan user.**
2. **Kalau user sudah berada di konteks yang benar, jangan suruh mencari fiturnya lagi.**
3. **Kalau sistem menolak tindakan, jelaskan alasan dan jalan keluarnya.**
4. **Jangan membuat kondisi gagal terlihat seperti kondisi aman atau kosong.**
5. **Setelah tindakan, jelaskan apa yang berubah dan apa yang tidak berubah.**
6. **Setiap status yang belum selesai harus menunjukkan langkah berikutnya.**
7. **Jangan tampilkan state internal; tampilkan arti operasionalnya bagi user.**

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

### Pesanan

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

### Pesanan

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
[ Menipis × ] [ Serum × ]
Menampilkan 4 dari 128 produk
[ Hapus Semua Filter ]
```

Jangan membuat user lupa bahwa dia sedang melihat subset.

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

## Error, Empty, Blocked, dan Recovery

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

## Freshness, Koneksi, dan Refresh

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

## Audit Trail

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

## Permission dan Security

Scope saat ini tetap **satu role ADMIN**.

Redesign tidak membuat Supervisor/Manager palsu.

Komponen dibuat future-ready terhadap permission untuk aksi seperti:

- pemusnahan;
- pembatalan transaksi;
- posting hasil hitung;
- saldo awal;
- diagnostik.

Jika RBAC ditambahkan kemudian, keamanan harus ditegakkan oleh server/RLS/domain guard, bukan hanya menyembunyikan tombol.

## Visual dan Accessibility

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

## Operator-First UX Contract Hardening

To ensure risky operations never become defaults:
- All non-terminal work states must display explicit next-action buttons.
- Empty, partial, or error data states must be explicitly distinguished from zero inventory.
- Proof-based reconciliation must link directly to verified ledger entries.