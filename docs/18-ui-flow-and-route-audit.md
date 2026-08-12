# UI Flow & Route Simplification Audit

**Project:** Stok Management System / Stok Reconciliation System
**Status:** Audit route/flow aktif - diperbarui untuk reachability Pengaturan
**Tanggal:** 12 Agustus 2026
**Berlaku untuk:** frontend redesign / operator-first usability refinement

---

## 1. Tujuan Dokumen

Dokumen ini menetapkan arah penyederhanaan arsitektur halaman dan alur navigasi aplikasi agar pengguna utama tidak perlu memahami struktur teknis sistem untuk menyelesaikan pekerjaan gudang.

Prinsip utamanya:

> **Jumlah route internal tidak menentukan jumlah menu yang harus dipahami pengguna.**

Route detail, audit, mutation, recovery, dan administrative workflow boleh tetap ada selama hanya muncul dari konteks pekerjaan yang relevan.

Sebelum membuat halaman baru, wajib dibuktikan bahwa halaman tersebut menutup flow yang benar-benar putus. Jika capability dapat diselesaikan lebih jelas melalui halaman existing, contextual action, tab, deep-link, atau detail page, jangan membuat workspace baru.

Dokumen ini tidak menggantikan business rules, database contract, atau VibeDev Phase 2 Sync Update v2. Jika terjadi konflik, aturan bisnis dan source yang lebih tinggi prioritasnya tetap berlaku.

---

## 2. Dasar Keputusan

Arah UI mengikuti prinsip berikut:

1. Kebenaran stok dan keterlacakan tetap lebih penting daripada kosmetik.
2. User utama adalah Admin/operator gudang, bukan developer.
3. Backend boleh kompleks, tetapi kompleksitas teknis tidak boleh dibebankan ke user.
4. Setiap pekerjaan harus menjawab:
   - Apa yang terjadi?
   - Apa yang perlu saya lakukan?
   - Dari transaksi mana masalah ini berasal?
5. Menu utama hanya berisi area kerja yang memang perlu dikenal user.
6. Route teknis tidak otomatis menjadi menu.
7. History/audit tidak boleh digandakan menjadi banyak halaman history per domain jika ledger sudah menjadi sumber bukti terpadu.
8. Status yang belum selesai harus menunjukkan langkah berikutnya.
9. Mutation berisiko tetap memakai preview/confirmation sesuai kontrak bisnis.
10. Tidak boleh ada placeholder, TODO, tombol mati, atau flow setengah jadi.

---

## 3. Mental Model Utama

User cukup memahami empat area utama:

```text
Beranda
Stok
Pesanan
Pengaturan
```

Sidebar tidak perlu memuat seluruh modul internal.

Struktur navigasi utama yang direkomendasikan:

```text
Beranda
Stok
Pesanan

Pengaturan
```

Semua halaman lain dibuka secara kontekstual dari empat area tersebut.

---

## 4. Peta Aplikasi Final yang Direkomendasikan

### 4.1 Beranda

```text
BERANDA
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡
ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Pekerjaan Hari Ini
ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Masalah yang perlu tindakan
ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Batch perlu perhatian
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬ÂÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Aktivitas terbaru
     ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬Å“
     deep-link ke pekerjaan sebenarnya
```

Peran Beranda:

- menjadi pusat orientasi user;
- menunjukkan pekerjaan aktif;
- menunjukkan kondisi penting;
- mengarahkan user langsung ke tindakan yang benar;
- bukan sekadar dashboard statistik.

`/today` tidak perlu menjadi route terpisah apabila fungsi Hari Ini sudah menjadi isi `/`.

Notification tidak perlu menjadi workspace utama terpisah. Notifikasi operasional sebaiknya muncul sebagai pekerjaan pada Beranda dan membawa user ke halaman tindakan yang tepat.

---

### 4.2 Stok

```text
STOK
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡
ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Daftar Stok
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡   ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬ÂÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Produk
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡       ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬ÂÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Batch
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡
ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Catat Perubahan
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡   ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Barang Masuk
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡   ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Barang Keluar
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡   ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬ÂÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Barang Rusak / Kedaluwarsa
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡
ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Hitung Stok
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬ÂÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Masalah Stok
```

Halaman utama Stok adalah workspace, bukan sekadar daftar produk.

Dari Stok, user harus dapat:

- melihat stok;
- membuka detail produk;
- membuka detail batch;
- mencatat barang masuk;
- mencatat barang keluar;
- mencatat barang rusak/kedaluwarsa;
- memulai Hitung Stok;
- membuka Masalah Stok;
- membuka Riwayat Stok bila membutuhkan bukti.

---

### 4.3 Pesanan

```text
PESANAN
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡
ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Daftar Pesanan
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡   ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬ÂÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Detail Pesanan
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡       ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ lifecycle marketplace
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡       ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬ÂÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ pembatalan
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬ÂÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Retur & Klaim
    ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬ÂÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Detail Retur
```

Pembatalan marketplace tidak perlu menjadi workspace terpisah.

Flow yang diinginkan:

```text
Pesanan
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Detail Pesanan
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ tindakan yang tersedia sesuai state
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ pembatalan bila memang relevan
```

Retur dan klaim tetap menjadi sub-flow Pesanan karena keduanya lahir dari lifecycle marketplace.

---

### 4.4 Pengaturan

```text
PENGATURAN
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡
ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Profil/Admin
ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Setup Stok Awal
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬ÂÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Konfigurasi administratif/teknis yang memang perlu dikelola Admin
```

Opening balance bukan pekerjaan harian gudang.

Karena itu:

```text
Setup Stok Awal
```

harus berada di Pengaturan, bukan menjadi menu reguler Stok.

---

## 5. Contextual Utilities

Halaman berikut tetap diperlukan, tetapi tidak perlu menjadi menu utama:

```text
Riwayat Stok
Detail Transaksi
Batalkan Transaksi / Koreksi Entri
Detail Produk
Detail Batch
Detail Hitung Stok
Detail Retur
```

Prinsipnya:

> User membuka utility karena sedang menyelesaikan pekerjaan tertentu, bukan karena harus mengingat nama modul teknisnya.

---

## 6. Klasifikasi Route Saat Ini

| Route | Keputusan | Catatan |
|---|---|---|
| `/` | KEEP utama | Beranda / Hari Ini |
| `/products` | KEEP utama | Workspace Stok |
| `/marketplace` | KEEP utama | Workspace Pesanan |
| `/settings` | DONE / KEEP utama | Pengaturan menjadi pintu capability administratif |
| `/login` | KEEP system route | Authentication |
| `/products/[productId]` | KEEP contextual | Detail produk |
| `/products/[productId]/batches/[batchId]` | KEEP contextual | Detail batch |
| `/receipts/new` | KEEP action | Barang Masuk |
| `/manual-outbounds` | KEEP action | Barang Keluar |
| `/stock-disposals` | KEEP action | Barang Rusak / Kedaluwarsa |
| `/stocktakes` | KEEP sub-flow | Daftar/pekerjaan Hitung Stok |
| `/stocktakes/new` | KEEP contextual | Mulai Hitung Stok |
| `/stocktakes/[stocktakeId]` | COMPLETE | Cancel end-to-end belum ada; status `CANCELLED` ada tetapi command/RPC/action cancel belum ditemukan |
| `/stock-issues` | KEEP sub-flow | Masalah Stok |
| `/reconciliation` | COMPATIBILITY DONE | Redirect ke `/stock-issues`; bukan konsep user-facing terpisah |
| `/ledger` | KEEP contextual | Riwayat Stok |
| `/ledger/[transactionId]` | KEEP contextual | Detail transaksi |
| `/entry-corrections` | KEEP contextual-only | Dibuka dari transaksi yang salah |
| `/opening-balances` | KEEP contextual / ADMIN-REACHABLE | Setup Stok Awal tersedia dari `/settings` |
| `/marketplace/[orderId]` | KEEP contextual | Detail pesanan |
| `/returns` | KEEP sub-flow | Retur & Klaim |
| `/returns/[returnId]` | KEEP contextual | Detail retur |

---

## 7. Route / Halaman yang Sudah Tepat Dikurangi

### 7.1 `/today`

Jika `/` sudah menjadi Hari Ini, route `/today` redundant.

Keputusan:

```text
REMOVE / MERGE INTO /
```

---

### 7.2 `/notifications`

Notification Center tidak perlu menjadi tempat kerja utama.

Arah yang benar:

```text
Beranda
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ pekerjaan yang perlu dilakukan
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ deep-link ke tindakan
```

Bukan:

```text
Notifikasi
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ baca notifikasi
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ cari halaman kerja
```

Keputusan:

```text
HIDE / MERGE ke Pekerjaan Hari Ini
```

Operational notification engine tetap boleh ada di backend.

---

### 7.3 `/marketplace/cancellations`

Pembatalan harus menjadi bagian dari detail pesanan.

Keputusan:

```text
REMOVE workspace terpisah
KEEP capability pada detail pesanan
```

---

## 8. Riwayat Stok sebagai Satu Pintu Bukti

`/ledger` tetap penting, tetapi tidak boleh menjadi menu utama.

User sebaiknya sampai ke Riwayat Stok dari:

- Aktivitas Beranda;
- Detail Produk;
- Detail Batch;
- transaksi berhasil;
- Masalah Stok;
- hasil Hitung Stok;
- detail transaksi lain.

Prinsip:

```text
Riwayat Stok = bukti / drill-down
bukan tempat user memulai pekerjaan
```

Jangan membuat halaman history terpisah untuk:

```text
Riwayat Barang Masuk
Riwayat Barang Keluar
Riwayat Pemusnahan
Riwayat Penyesuaian Hitung Stok
```

Jika data tersebut sudah dapat ditelusuri dengan benar melalui ledger, membuat history terpisah hanya menggandakan konsep dan membingungkan user.

---

## 9. Koreksi Entri sebagai Flow Kontekstual

Koreksi Entri berbeda dari Penyesuaian Hasil Hitung Stok.

Flow yang direkomendasikan:

```text
Riwayat Stok
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Detail Transaksi
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Ada kesalahan?
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Batalkan Transaksi
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Preview dampak
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Konfirmasi
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Reversal baru tercatat
```

Bukan:

```text
Sidebar
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Koreksi Entri
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ cari transaksi lagi
```

Route `/entry-corrections` boleh tetap ada untuk implementasi, tetapi tidak perlu dikenal sebagai area utama.

---

## 10. Rekonsiliasi dan Masalah Stok

Aplikasi memiliki dua ritme pemeriksaan:

1. rekonsiliasi harian untuk konsistensi internal;
2. stocktake untuk perbandingan sistem dengan hitung fisik.

User tidak perlu memilih antara istilah teknis:

```text
Rekonsiliasi
vs
Masalah Stok
```

Untuk pekerjaan harian, gunakan satu konsep user-facing:

```text
Masalah Stok
```

Reconciliation engine/read model tetap berjalan di balik halaman tersebut.

Route compatibility `/reconciliation` boleh sementara redirect ke `/stock-issues`, tetapi setelah audit deep-link selesai route tersebut dapat dihapus.

---

## 11. Barang Masuk, Barang Keluar, dan Pemusnahan sebagai Task Page

### Barang Masuk

Tidak perlu halaman history receipt tersendiri.

Flow:

```text
Stok
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Barang Masuk
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Isi form
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Simpan
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Berhasil
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Kembali ke Stok / Lihat Transaksi / Catat Lagi
```

History tetap melalui Riwayat Stok.

### Barang Keluar

Flow:

```text
Stok
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Barang Keluar
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Isi Data
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Periksa
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Simpan
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Berhasil
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Kembali ke Stok / Lihat Transaksi / Catat Lagi
```

Batch tetap dipilih otomatis oleh FEFO.

### Barang Rusak / Kedaluwarsa

Flow:

```text
Stok
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Barang Rusak / Kedaluwarsa
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Isi Data
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Periksa
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Simpan
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Berhasil
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Kembali ke Stok / Lihat Transaksi / Catat Lagi
```

Rusak dan kedaluwarsa tetap berbeda secara reason/business meaning bila kontrak domain mengharuskannya.

---

## 12. Produk dan Batch

Produk dan Batch tidak menjadi menu utama.

Flow:

```text
Stok
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ pilih Produk
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Detail Produk
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ pilih Batch
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Detail Batch
```

Detail teknis boleh kompleks, tetapi user tidak perlu memahami route internal.

Halaman Detail Produk dan Detail Batch harus berfungsi sebagai drill-down dari konteks Stok.

---

## 13. Hitung Stok

Flow utama:

```text
Stok
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Hitung Stok
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Mulai Hitung Stok
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Counting
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Review
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Approval
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Posting Adjustment
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Selesai
```

Hitung Stok tidak boleh mengubah stok selama:

- create;
- prepare;
- start;
- counting;
- recount;
- review;
- approval.

Perubahan stok baru terjadi saat posting adjustment sesuai kontrak ledger.

### Gap yang sudah ditemukan: cancel Hitung Stok

State `CANCELLED` sudah dikenal, tetapi flow pembatalan belum lengkap.

Target behavior yang perlu diaudit dan dibangun:

```text
DRAFT      ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ boleh dibatalkan
READY      ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ boleh dibatalkan
COUNTING   ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ boleh dibatalkan, attempt tetap tersimpan
REVIEW     ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ perlu keputusan domain yang eksplisit
APPROVED   ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ jangan pakai cancel biasa
POSTING    ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ jangan pakai cancel biasa
POSTED     ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ tidak boleh dibatalkan; gunakan mekanisme koreksi/reversal yang sesuai
```

Pembatalan:

- tidak mengubah stok;
- wajib auditable;
- membutuhkan alasan;
- tidak menghapus count attempt;
- idempotent;
- tidak boleh menjadi jalan pintas untuk membatalkan movement yang sudah diposting.

---

## 14. Marketplace Listing Administration

Route `/marketplace/listings` masih ada dan capability UI/backend tersedia. Pada baseline `ea1b940`, capability ini orphan dari IA operator. Pada tahap reachability Pengaturan, link `Mapping Produk Marketplace` dari `/settings` sudah tersedia dan diuji pada desktop/mobile.

Capability listing tetap penting karena marketplace listing harus dapat dipetakan ke canonical product/bundle dan recipe version yang benar.

Audit yang mendasari keputusan penempatan:

1. route dan capability existing dipertahankan;
2. flow Admin mapping tetap memakai kontrak yang sama;
3. link dari Pengaturan menutup status orphan tanpa menambah primary navigation;
4. bundle recipe versioning tetap dapat dikelola tanpa workspace utama baru.

Penempatan administratif yang diterapkan:

```text
Pengaturan
|-- Marketplace
    `-- Mapping Produk Marketplace
```

Keputusan tahap ini menempatkan mapping sebagai capability administratif di Pengaturan tanpa menambah primary navigation atau mengubah domain contract.

---

## 15. CSV Import / Simulator Marketplace

Phase 2 mewajibkan import/simulator diperlakukan sebagai adapter di belakang normalized event contract yang sama dengan future API/webhook.

Route `/marketplace/import` dan `/marketplace/import/[jobId]` masih ada. Capability import/simulator tetap diperlukan sebagai adapter. Gap baseline `ea1b940` sudah ditutup melalui link `Import / Simulator Pesanan` dari `/settings`; flow import ke detail job dan kembali tetap dipertahankan.

Audit harus memastikan:

- simulator/import tetap dapat digunakan untuk testing/demo;
- event yang dihasilkan memakai normalized contract yang sama;
- ledger, FEFO, dan order state machine tidak bergantung pada tombol simulator;
- penggantian adapter dengan API/webhook tidak mengubah core logic;
- import tidak harus menjadi menu harian operator.

Penempatan administratif yang diterapkan:

```text
Pengaturan
`-- Import / Simulator Pesanan
```

Capability ini tetap adapter administratif dan tidak menjadi pekerjaan gudang harian.

---

## 16. Prinsip Create vs Merge

Sebelum membuat halaman baru, jawab pertanyaan berikut:

1. Apakah capability belum memiliki UI?
2. Apakah flow benar-benar putus tanpa halaman baru?
3. Apakah user perlu kembali ke halaman tersebut secara rutin?
4. Apakah halaman baru punya mental model berbeda dari halaman existing?
5. Apakah fungsi ini cukup menjadi contextual action, tab, drawer, atau detail section?
6. Apakah membuat halaman baru justru menggandakan history/audit yang sudah ada?

Jika jawabannya tidak kuat, pilih:

```text
MERGE
HIDE
CONTEXTUAL ACTION
DEEP-LINK
```

bukan membuat workspace baru.

---

## 17. Kategori Audit

Setiap route/flow baru harus diklasifikasikan sebagai:

### KEEP

Route diperlukan dan sudah berada pada tempat yang tepat.

### COMPLETE

Route/capability penting tetapi flow masih putus atau kurang.

### CREATE

Capability wajib belum memiliki UI yang dapat digunakan end-to-end.

### MERGE

Capability tetap dibutuhkan, tetapi tidak layak menjadi halaman/workspace sendiri.

### REMOVE / HIDE

Route tidak lagi diperlukan user sebagai entry point dan hanya menambah cognitive load.

---

## 18. Flow Audit Checklist

Untuk setiap area, audit harus memeriksa:

```text
Masuk dari mana?
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬Å“
User ingin menyelesaikan pekerjaan apa?
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬Å“
Apa informasi minimum yang dibutuhkan?
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬Å“
Apa primary action?
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬Å“
Apakah ada preview bila mutation berisiko?
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬Å“
Apa yang terjadi ketika berhasil?
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬Å“
Ke mana user pergi setelah berhasil?
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬Å“
Apa yang terjadi ketika gagal?
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬Å“
Apakah draft/context aman dipertahankan?
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬Å“
Apakah ada dead end?
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬Å“
Apakah ada halaman yang sebenarnya tidak perlu?
```

---

## 19. Urutan Audit Lanjutan

Audit lanjutan dilakukan per area, bukan berdasarkan nama folder.

### Tahap 1 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â Stok

```text
Stok
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Produk
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Batch
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Barang Masuk
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Barang Keluar
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Barang Rusak/Kedaluwarsa
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Hitung Stok
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Masalah Stok
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Riwayat/Koreksi
```

### Tahap 2 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â Pesanan

```text
Pesanan
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Detail Pesanan
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Reserve
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Shipment
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Cancellation
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Return
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Claim
```

### Tahap 3 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â Pengaturan

```text
Pengaturan
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Profil/Admin
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Setup Stok Awal
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Marketplace mapping
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Simulator/import bila diperlukan
```

### Tahap 4 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â Beranda

Pastikan setiap work item benar-benar memiliki deep-link ke tindakan yang benar dan tidak membuat user mencari halaman secara manual.

---

## 20. Definition of Done untuk Information Architecture

Information architecture dianggap selesai jika:

- sidebar hanya berisi area kerja yang benar-benar perlu dikenal user;
- user baru tahu harus mulai dari mana;
- tidak ada capability wajib yang orphan;
- tidak ada dua halaman berbeda untuk pekerjaan yang sama tanpa alasan kuat;
- tidak ada history duplikat yang menggandakan ledger;
- route teknis hanya dibuka secara kontekstual;
- setiap non-terminal state memiliki next action;
- setiap success state memiliki jalan kembali yang jelas;
- setiap error state memberi recovery yang aman;
- deep-link dari Beranda membawa user langsung ke pekerjaan yang relevan;
- seluruh domain wajib tetap end-to-end;
- penyederhanaan UI tidak menghapus auditability atau safety.

---

## 21. Target Mental Model Akhir

Backend boleh memiliki banyak route, action, RPC, read model, dan state machine.

User cukup memahami:

```text
Saya ingin melihat kondisi hari ini
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Beranda

Saya ingin bekerja dengan stok
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Stok

Saya ingin menangani pesanan atau retur
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Pesanan

Saya ingin mengatur hal administratif
ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Pengaturan
```

Jika user perlu memahami istilah internal seperti ledger sequence, reconciliation run, notification evaluator, adapter import, atau nama RPC hanya untuk menyelesaikan pekerjaan gudang harian, desain belum cukup sederhana.

---

## 22. Keputusan Saat Ini

Keputusan yang dianggap terkunci untuk audit berikutnya:

1. Sidebar utama tetap:
   - Beranda
   - Stok
   - Pesanan
   - Pengaturan

2. `/today` digabung ke `/`.

3. Notifikasi operasional tidak menjadi workspace utama.

4. `/ledger` tetap ada sebagai Riwayat Stok tetapi bersifat contextual.

5. `/entry-corrections` tetap contextual dan dibuka dari transaksi yang salah.

6. `/reconciliation` tidak menjadi konsep user-facing terpisah; gunakan Masalah Stok.

7. Opening Balance ditempatkan di Pengaturan.

8. Barang Masuk, Barang Keluar, dan Pemusnahan tidak memerlukan history page masing-masing.

9. Detail Produk, Detail Batch, Detail Transaksi, Detail Retur, dan Detail Hitung Stok tetap route contextual.

10. Flow cancel Hitung Stok adalah gap nyata yang harus ditutup setelah domain contract diaudit.

11. Marketplace listing administration dan CSV import/simulator tersedia dari Pengaturan sebagai capability administratif; keduanya tetap di luar primary navigation dan bukan menu harian operator.

12. Tidak membuat halaman baru hanya karena backend memiliki modul/domain tersendiri.

---

## 23. Sumber Prioritas

Gunakan urutan source proyek yang berlaku:

1. **VibeDev Phase 2 Sync Update v2 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â 13 Juni 2026**
2. Brief Bounty Phase 1
3. Dokumen proyek yang lebih baru
4. README, business rules, migrations, tests, source, issue/PR
5. Dokumen UI/UX

Jika dokumen ini bertentangan dengan source prioritas lebih tinggi, source lebih tinggi yang berlaku.

---

## 24. Prinsip Penutup

Target akhir bukan:

> ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œAplikasi memiliki semua halaman untuk setiap modul.ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â

Target akhirnya adalah:

> **ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œAdmin dapat melihat apa yang terjadi, tahu apa yang perlu dilakukan, dan menelusuri bukti tanpa harus memahami struktur internal sistem.ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â**

Sederhanakan navigasi, bukan aturan stok.

Kurangi halaman yang harus dipahami user, bukan audit trail.

Gabungkan flow yang serupa, tetapi jangan menggabungkan konsep bisnis yang berbeda.

Dan sebelum menambah halaman baru, selalu tanyakan:

> **Apakah halaman ini benar-benar membantu user menyelesaikan pekerjaan, atau hanya memindahkan kompleksitas backend ke layar?**

---

## 25. Status Aktual Setelah Reachability Pengaturan

Audit source lokal setelah rebuild operator-first mengunci kondisi berikut:

| Area / Route | Status aktual | Tindak lanjut |
| --- | --- | --- |
| `/` | DONE / KEEP utama | Beranda menjadi pusat pekerjaan dan deep-link operasional |
| `/today` | COMPATIBILITY DONE | Redirect ke `/` |
| `/products` | DONE / KEEP utama | Workspace Stok |
| `/stock-issues` | DONE / KEEP sub-flow | Masalah Stok |
| `/reconciliation` | COMPATIBILITY DONE | Redirect ke `/stock-issues` |
| `/ledger` dan detail transaksi | DONE / KEEP contextual | Riwayat dan bukti stok |
| `/entry-corrections` | DONE / KEEP contextual-only | Dibuka dari transaksi yang salah |
| `/stocktakes/*` | COMPLETE WITH GAP | Flow utama tersedia; cancel session end-to-end belum ada |
| `/marketplace` dan detail pesanan | DONE / KEEP utama-contextual | Partial cancellation tersedia; reserve/ship tetap event/adapter-driven |
| `/returns` dan detail retur | KEEP sub-flow/contextual | Retur & Klaim tetap di bawah Pesanan |
| `/notifications` | COMPATIBILITY DONE | Bookmark lama redirect ke Beranda; work item Retur/Klaim memakai direct object route yang mempertahankan returnId/claimId; diagnostics tetap terpisah |
| `/notifications/operations` | KEEP admin-contextual / TECHNICAL-ONLY | Admin troubleshooting tersedia dari Pengaturan; bukan menu utama |
| `/settings` | DONE / KEEP utama | Pintu Setup Stok Awal, Marketplace, import/simulator, dan diagnostics administratif |
| `/opening-balances` | KEEP contextual / ADMIN-REACHABLE | Setup Stok Awal tersedia dari Pengaturan |
| `/marketplace/listings` | KEEP contextual / ADMIN-REACHABLE | Mapping Produk Marketplace tersedia dari Pengaturan |
| `/marketplace/import` | KEEP admin-contextual / ADAPTER | Import / Simulator Pesanan tersedia dari Pengaturan; bukan pekerjaan harian operator |

### Gap tersisa sebelum Information Architecture dianggap selesai

1. Tutup flow cancel Hitung Stok secara end-to-end, auditable, idempotent, dan tanpa perubahan stok sebelum posting.

2. Audit final seluruh back/returnTo, success recovery, failure recovery, dead action, dan route orphan.
3. Pertahankan reserve/shipment sebagai event/adapter-driven flow kecuali source prioritas lebih tinggi secara eksplisit meminta mutation manual dari UI.
