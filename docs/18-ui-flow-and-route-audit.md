# UI Flow & Route Simplification Audit

**Project:** Stok Management System / Stok Reconciliation System
**Status:** Final
**Tanggal:** 13 Agustus 2026
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
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡
ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Pekerjaan Hari Ini
ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Masalah yang perlu tindakan
ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Batch perlu perhatian
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬ÂÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Aktivitas terbaru
     ↓
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
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡
ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Daftar Stok
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡   ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬ÂÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Produk
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡       ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬ÂÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Batch
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡
ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Catat Perubahan
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡   ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Barang Masuk
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡   ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Barang Keluar
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡   ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬ÂÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Barang Rusak / Kedaluwarsa
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡
ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Hitung Stok
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬ÂÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Masalah Stok
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
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡
ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Daftar Pesanan
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡   ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬ÂÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Detail Pesanan
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡       ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ lifecycle marketplace
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡       ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬ÂÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ pembatalan
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬ÂÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Retur & Klaim
    ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬ÂÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Detail Retur
```

Pembatalan marketplace tidak perlu menjadi workspace terpisah.

Flow yang diinginkan:

```text
Pesanan
→ Detail Pesanan
→ tindakan yang tersedia sesuai state
→ pembatalan bila memang relevan
```

Retur dan klaim tetap menjadi sub-flow Pesanan karena keduanya lahir dari lifecycle marketplace.

---

### 4.4 Pengaturan

```text
PENGATURAN
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡
ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Profil/Admin
ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Setup Stok Awal
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬ÂÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Konfigurasi administratif/teknis yang memang perlu dikelola Admin
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
| `/stocktakes/[stocktakeId]` | COMPLETE | Cancel end-to-end lengkap, auditable, idempotent, stock-neutral |
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
COMPATIBILITY / Redirect ke /
```

---

### 7.2 `/notifications`

Notification Center tidak perlu menjadi tempat kerja utama.

Arah yang benar:

```text
Beranda
→ pekerjaan yang perlu dilakukan
→ deep-link ke tindakan
```

Bukan:

```text
Notifikasi
→ baca notifikasi
→ cari halaman kerja
```

Keputusan:

```text
COMPATIBILITY / Redirect ke /; notification state tetap contextual di /notifications/operations#notification-state
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
→ Detail Transaksi
→ Ada kesalahan?
→ Batalkan Transaksi
→ Preview dampak
→ Konfirmasi
→ Reversal baru tercatat
```

Bukan:

```text
Sidebar
→ Koreksi Entri
→ cari transaksi lagi
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
→ Barang Masuk
→ Isi form
→ Simpan
→ Berhasil
→ Kembali ke Stok / Lihat Transaksi / Catat Lagi
```

History tetap melalui Riwayat Stok.

### Barang Keluar

Flow:

```text
Stok
→ Barang Keluar
→ Isi Data
→ Periksa
→ Simpan
→ Berhasil
→ Kembali ke Stok / Lihat Transaksi / Catat Lagi
```

Batch tetap dipilih otomatis oleh FEFO.

### Barang Rusak / Kedaluwarsa

Flow:

```text
Stok
→ Barang Rusak / Kedaluwarsa
→ Isi Data
→ Periksa
→ Simpan
→ Berhasil
→ Kembali ke Stok / Lihat Transaksi / Catat Lagi
```

Rusak dan kedaluwarsa tetap berbeda secara reason/business meaning bila kontrak domain mengharuskannya.

---

## 12. Produk dan Batch

Produk dan Batch tidak menjadi menu utama.

Flow:

```text
Stok
→ pilih Produk
→ Detail Produk
→ pilih Batch
→ Detail Batch
```

Detail teknis boleh kompleks, tetapi user tidak perlu memahami route internal.

Halaman Detail Produk dan Detail Batch harus berfungsi sebagai drill-down dari konteks Stok.

---

## 13. Hitung Stok

Flow utama:

```text
Stok
→ Hitung Stok
→ Mulai Hitung Stok
→ Counting
→ Review
→ Approval
→ Posting Adjustment
→ Selesai
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
DRAFT      → boleh dibatalkan
READY      → boleh dibatalkan
COUNTING   → boleh dibatalkan, attempt tetap tersimpan
REVIEW     → perlu keputusan domain yang eksplisit
APPROVED   → jangan pakai cancel biasa
POSTING    → jangan pakai cancel biasa
POSTED     → tidak boleh dibatalkan; gunakan mekanisme koreksi/reversal yang sesuai
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

Import Pesanan tersedia di `/marketplace/import` (dan detail job `/marketplace/import/[jobId]`), sedangkan Simulator Pesanan tersedia di `/marketplace/simulator`. Keduanya terpisah di Pengaturan sebagai adapter administratif.

Audit harus memastikan:

- simulator/import tetap dapat digunakan untuk testing/demo;
- event yang dihasilkan memakai normalized contract yang sama;
- ledger, FEFO, dan order state machine tidak bergantung pada tombol simulator;
- penggantian adapter dengan API/webhook tidak mengubah core logic;
- import dan simulator tidak harus menjadi menu harian operator.

Penempatan administratif yang diterapkan:

```text
Pengaturan
├── Import Pesanan (/marketplace/import)
└── Simulator Pesanan (/marketplace/simulator)
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
↓
User ingin menyelesaikan pekerjaan apa?
↓
Apa informasi minimum yang dibutuhkan?
↓
Apa primary action?
↓
Apakah ada preview bila mutation berisiko?
↓
Apa yang terjadi ketika berhasil?
↓
Ke mana user pergi setelah berhasil?
↓
Apa yang terjadi ketika gagal?
↓
Apakah draft/context aman dipertahankan?
↓
Apakah ada dead end?
↓
Apakah ada halaman yang sebenarnya tidak perlu?
```

---

## 19. Urutan Audit Lanjutan

Audit lanjutan dilakukan per area, bukan berdasarkan nama folder.

### Tahap 1 — Stok

```text
Stok
→ Produk
→ Batch
→ Barang Masuk
→ Barang Keluar
→ Barang Rusak/Kedaluwarsa
→ Hitung Stok
→ Masalah Stok
→ Riwayat/Koreksi
```

### Tahap 2 — Pesanan

```text
Pesanan
→ Detail Pesanan
→ Reserve
→ Shipment
→ Cancellation
→ Return
→ Claim
```

### Tahap 3 — Pengaturan

```text
Pengaturan
→ Profil/Admin
→ Setup Stok Awal
→ Marketplace mapping
→ Simulator/import bila diperlukan
```

### Tahap 4 — Beranda

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
→ Beranda

Saya ingin bekerja dengan stok
→ Stok

Saya ingin menangani pesanan atau retur
→ Pesanan

Saya ingin mengatur hal administratif
→ Pengaturan
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

10. Cancel Hitung Stok selesai sebagai tindakan kontekstual pada detail sesi; tidak menambah menu atau route utama.

11. Marketplace listing administration dan CSV import/simulator tersedia dari Pengaturan sebagai capability administratif; keduanya tetap di luar primary navigation dan bukan menu harian operator.

12. Tidak membuat halaman baru hanya karena backend memiliki modul/domain tersendiri.

---

## 23. Sumber Prioritas

Gunakan urutan source proyek yang berlaku:

1. **VibeDev Phase 2 Sync Update v2 — 13 Juni 2026**
2. Brief Bounty Phase 1
3. Dokumen proyek yang lebih baru
4. README, business rules, migrations, tests, source, issue/PR
5. Dokumen UI/UX

Jika dokumen ini bertentangan dengan source prioritas lebih tinggi, source lebih tinggi yang berlaku.

---

## 24. Prinsip Penutup

Target akhir bukan:

> “Aplikasi memiliki semua halaman untuk setiap modul.”

Target akhirnya adalah:

> **“Admin dapat melihat apa yang terjadi, tahu apa yang perlu dilakukan, dan menelusuri bukti tanpa harus memahami struktur internal sistem.”**

Sederhanakan navigasi, bukan aturan stok.

Kurangi halaman yang harus dipahami user, bukan audit trail.

Gabungkan flow yang serupa, tetapi jangan menggabungkan konsep bisnis yang berbeda.

Dan sebelum menambah halaman baru, selalu tanyakan:

> **Apakah halaman ini benar-benar membantu user menyelesaikan pekerjaan, atau hanya memindahkan kompleksitas backend ke layar?**

---

## 25. Status Final Flow dan Route Frontend

Status ini berasal dari inventory aktual `src/app/**/page.tsx`, route handler aktual, consumer Server Action, focused tests, production build Next.js 16.3.0, browser smoke desktop/mobile, dan seluruh pgTAP. Audit tidak mengubah schema, migration, ledger/projection, FEFO, reservation, return effect, marketplace shipment, cancellation, atau stocktake posting.

### 25.1 Inventory route aktual

| Route | Fungsi | Kelompok | Entry/context | Back | Success / failure | Refresh | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `/` | Pusat pekerjaan dan deep-link operasional | Beranda | Primary nav | — | Read/retry pada workspace | Query/object link stabil | KEEP MAIN |
| `/login` | Autentikasi Admin | Sistem | Proxy/session | `returnTo` internal tervalidasi | Success ke `returnTo`; failure tetap di login dan mempertahankan `returnTo` | Aman; POST tidak direplay | TECHNICAL-ONLY |
| `/today` | Bookmark pusat kendali lama | Beranda | Direct/bookmark lama | — | Redirect ke `/` | Stabil | COMPATIBILITY |
| `/products` | Workspace posisi stok dan master produk | Stok | Primary nav/Beranda | — | Mutation produk memberi feedback pada workspace/detail | Filter `q/status` di URL | KEEP MAIN |
| `/products/[productId]` | Detail produk, batch, dan riwayat | Stok | Kartu/tabel Stok | `returnTo` tepat ke `/products` beserta query | Mutation kembali ke detail dengan feedback | Tab dan `returnTo` di URL | KEEP CONTEXTUAL |
| `/products/[productId]/batches/[batchId]` | Detail dan administrasi batch | Stok | Tab batch produk | `returnTo` hanya ke detail produk yang sama | Mutation kembali ke detail batch dengan feedback | Konteks produk/tab di URL | KEEP CONTEXTUAL |
| `/receipts/new` | Barang Masuk | Stok | Aksi workspace Stok | `/products` | Success menampilkan hasil/link transaksi; failure memulihkan draft | Draft/error recovery tersedia | KEEP CONTEXTUAL |
| `/manual-outbounds` | Barang Keluar manual dengan preview FEFO | Stok | Aksi workspace Stok | `/products` | Preview lalu post; failure tetap dapat diperbaiki | Draft/preview aman | KEEP CONTEXTUAL |
| `/stock-disposals` | Pemusnahan stok dengan preview | Stok | Aksi workspace Stok | `/products` | Preview lalu post; failure tetap dapat diperbaiki | Draft/preview aman | KEEP CONTEXTUAL |
| `/stocktakes` | Daftar pekerjaan Hitung Stok | Stok | Workspace Stok | `/products` | Read/retry; membuka sesi existing | Filter `status/type` di URL | KEEP CONTEXTUAL |
| `/stocktakes/new` | Membuat sesi Hitung Stok | Stok | Daftar Hitung Stok | `/stocktakes` | Success ke detail; failure memulihkan isian | Notice aman, command identity baru | KEEP CONTEXTUAL |
| `/stocktakes/[stocktakeId]` | Counting, review, approval, posting, dan pembatalan sesi | Stok | Daftar Hitung Stok/deep-link | `returnTo` tepat ke `/stocktakes` beserta filter | Semua action kembali ke detail dengan feedback dan `returnTo` | Context tetap setelah refresh; CANCELLED terminal | KEEP CONTEXTUAL |
| `/stock-issues` | Masalah Stok dan rekonsiliasi harian | Stok | Workspace Stok/deep-link | `/products` | Evaluasi memberi feedback pada halaman | Query stabil | KEEP CONTEXTUAL |
| `/reconciliation` | Bookmark nama teknis lama | Stok | Direct/bookmark lama | — | Redirect ke `/stock-issues`, query dipertahankan | Stabil | COMPATIBILITY |
| `/ledger` | Riwayat Stok authoritative | Stok | Workspace Stok, produk, batch, hasil transaksi | `/products` | Read/retry; membuka detail transaksi | Filter/page di URL | KEEP CONTEXTUAL |
| `/ledger/[transactionId]` | Bukti transaksi dan linkage reversal | Stok | Riwayat/deep-link hasil mutation | Filter Riwayat Stok direkonstruksi | Link correction hanya bila eligible; read failure kembali ke riwayat | Context tetap setelah refresh | KEEP CONTEXTUAL |
| `/entry-corrections` | Preview dan reversal Koreksi Entri | Stok | Detail transaksi eligible | Riwayat/detail asal | Success ke bukti transaksi; failure tetap pada preview/recovery | Transaction context di URL | KEEP CONTEXTUAL |
| `/marketplace` | Daftar Pesanan marketplace | Pesanan | Primary nav/Beranda | — | Read/retry; membuka exact order | Filter `q/channel/status` di URL | KEEP MAIN |
| `/marketplace/[orderId]` | Detail order dan partial cancellation existing | Pesanan | Daftar Pesanan/deep-link | `returnTo` tepat ke `/marketplace` beserta filter | Cancellation success/failure kembali ke detail dan mempertahankan context | Aman setelah refresh | KEEP CONTEXTUAL |
| `/returns` | Daftar Retur dan Klaim | Pesanan | Pesanan/Beranda/deep-link legacy | `/marketplace` | Read/retry; membuka exact return/claim | Section dan object identity di URL | KEEP CONTEXTUAL |
| `/returns/[returnId]` | Kedatangan, inspeksi, lost, klaim, late arrival | Pesanan | Daftar Retur/Klaim/work item | `returnTo` tepat ke `/returns` atau tab Klaim | Semua action kembali ke exact return/claim dengan feedback | `returnId`, `claimId`, anchor, `returnTo` stabil | KEEP CONTEXTUAL |
| `/settings` | Hub capability administratif | Pengaturan | Primary nav | — | Link capability jelas; logout aktif | Stabil | KEEP MAIN |
| `/opening-balances` | Setup Stok Awal | Pengaturan | Hub Pengaturan | `/settings` | Draft/review/post/reversal memberi feedback dan recovery | State authoritative dibaca ulang | KEEP ADMIN |
| `/marketplace/listings` | Mapping Produk Marketplace | Pengaturan | Hub Pengaturan | `/settings` | Mutation memberi feedback; read failure kembali ke Pengaturan | Query/form state stabil | KEEP ADMIN |
| `/marketplace/import` | Upload/preview import adapter | Pengaturan | Hub Pengaturan | `/settings` | Success ke job detail; read/upload failure punya recovery aman | Job tersimpan authoritative | KEEP ADMIN |
| `/marketplace/import/[jobId]` | Preview dan commit atomic job import | Pengaturan | Riwayat job/deep-link | `/marketplace/import` | Commit success/failure tetap pada job; read failure kembali ke import | Job/filter row stabil | KEEP ADMIN |
| `/marketplace/simulator` | Simulator Pesanan | Pengaturan | Hub Pengaturan | `/settings` | Simulasi pesanan memberi feedback | State simulator stabil | KEEP ADMIN |
| `/notifications` | Bookmark Notification Center lama | Beranda | Direct/bookmark lama | — | Redirect ke `/` | Stabil | COMPATIBILITY |
| `/notifications/operations` | Diagnostics/evaluator/outbox Admin | Pengaturan | Hub Pengaturan | `/settings` | Evaluate/retry memberi feedback; read failure kembali ke Pengaturan | Query status stabil | TECHNICAL-ONLY |

Route handler teknis yang tidak memiliki `page.tsx`:

- `/marketplace/import/template`: download template privat dari halaman Import;
- `/marketplace/import/[jobId]/errors`: download error report privat dari detail job.

### 25.2 Klasifikasi final

- MAIN: `/`, `/products`, `/marketplace`, `/settings`.
- CONTEXTUAL: detail produk/batch, Barang Masuk, Barang Keluar, Pemusnahan, Hitung Stok, Masalah Stok, Riwayat/detail transaksi, Koreksi Entri, detail order, Retur/detail retur.
- ADMIN: `/opening-balances`, `/marketplace/listings`, `/marketplace/import`, detail job import, dan `/marketplace/simulator`.
- COMPATIBILITY: `/today` ke `/`, `/notifications` ke `/`, `/reconciliation` ke `/stock-issues` dengan query.
- TECHNICAL: `/login`, `/notifications/operations`, template CSV, dan error report job.

Tidak ada route user/Admin penting yang orphan. Diagnostics dan import tetap reachable dari Pengaturan tanpa bocor menjadi primary navigation. Detail object memiliki entry list/deep-link dan back destination yang jelas.

### 25.3 Hasil audit navigation dan recovery

- Primary navigation tetap empat item. Route marketplace listing/import aktif sebagai Pengaturan; detail order dan Retur aktif sebagai Pesanan; semua route stok aktif sebagai Stok pada desktop dan mobile.
- Validator `safeInternalRoute` dipakai bersama untuk `returnTo`. Ia menolak URL eksternal, protocol-relative, `javascript:`, backslash, dan control character; contextual route juga memakai allowlist pathname parent yang tepat.
- Proxy menyimpan pathname dan query hanya untuk GET/HEAD unauthenticated. Login success/failure mempertahankan internal `returnTo`; POST mutation tidak direplay setelah login.
- Product, batch, marketplace order, return/claim, dan stocktake mempertahankan context list saat detail direfresh dan saat mutation success/failure kembali ke detail.
- Failure read pada listing, import list/detail, dan diagnostics tidak menjadi HTTP 5xx/dead end dan menyediakan link kembali yang benar.
- Compatibility route tetap ada untuk bookmark lama. Tidak ada caller user-facing aktif yang menuju `/notifications`; work item Retur/Klaim menuju exact object route.

### 25.4 Dead legacy yang dihapus dan komponen yang dipertahankan

- `src/app/notifications/actions.ts` tetap ada dipertahankan untuk integritas notification state dan system diagnostics. Notification evaluator, read model, database contract, dan operations diagnostics tetap aktif dan seluruh pgTAP notification PASS.
- `scripts/test-notification-write-actions.mjs` dan script package terkait tetap ada dipertahankan untuk pengujian fungsional penulisan notifikasi.
- Tujuh root Server Action legacy pada `src/app/actions.ts` dihapus karena tidak memiliki consumer; replacement route-scoped untuk receipt, marketplace, dan return tetap aktif. `runReconciliationAction` tetap dipakai oleh `/stock-issues`.
- Scan UI tidak menemukan `href="#"`, href kosong, TODO/FIXME, button `console.log`, atau disabled permanen palsu. Form tanpa Server Action yang tersisa adalah filter GET yang disengaja.

### 25.5 `playwright.config.ts`

Perubahan pada commit `b113912` dipertahankan. `PLAYWRIGHT_EXTERNAL_SERVER=true` hanya mencegah Playwright menyalakan server kedua ketika runner TikTok Return sudah memiliki server sendiri. Perubahan tidak mengubah timeout, retry, worker, project desktop/mobile, coverage test, console/page error checks, HTTP failure checks, credential, atau semantics CI default.

### 25.6 Bukti validasi audit final

- Focused: navigation contract, login UI, stock workspace, UI primitives, stocktake presentation + pgTAP 023–028, CSV parser, dan CSV error boundary PASS.
- Browser: 29 passed, 13 skipped, 0 failed pada desktop/mobile; tidak ada unexpected page error, HTTP 5xx, atau root horizontal overflow. Route utama/admin, compatibility redirect, active nav, login returnTo, refresh, dan back flow existing terverifikasi. Exact claim-notification smoke tidak dijalankan karena fixture aktif tidak tersedia dan audit tidak membuat mutation hanya untuk smoke.
- `npm run lint`: PASS dengan 0 error; empat warning unused-variable sudah ada pada source baseline.
- `npm run typecheck`: PASS.
- `npm run build`: PASS; build menginventarisasi seluruh page dan handler di atas.
- `npx supabase test db`: PASS, 69 files / 3,803 tests PASS.
- `git diff --check`: PASS.

### 25.7 Cancel Hitung Stok — COMPLETE

- Pembatalan hanya tersedia secara kontekstual pada `/stocktakes/[stocktakeId]`: `DRAFT`, `READY`, `COUNTING`, dan `REVIEW` dapat dibatalkan. `APPROVED`, `POSTING`, `POSTED`, `CANCELLED`, dan `EXCEPTION` terminal/non-cancellable.
- RPC atomik menulis audit append-only `operations.stocktake_cancellations` bersama idempotency command, actor, alasan, metadata, dan timestamp; count attempt yang telah tersimpan tidak dihapus.
- Pembatalan stock-neutral: tidak menulis transaksi/ledger stok, batch/product projection, reservation, atau marketplace allocation. `CANCELLED` tidak dapat dilanjutkan atau kemudian diposting.
- pgTAP 069 (38 assertion) membuktikan transition, isolasi organisasi, audit, idempotency, notification evaluator, count preservation, dan invariants stock-neutral.
- Playwright focused PASS pada desktop dan mobile: Admin membuat DRAFT, alasan kosong ditolak, pembatalan memberi feedback/status `Dibatalkan`, refresh dan back navigation aman, serta tidak ada HTTP 5xx/page error/root overflow.
- Harness dua sesi PASS: replay identik menghasilkan satu effect; changed payload mengembalikan `IDEMPOTENCY_KEY_REUSED`; command identity berbeda menghasilkan satu winner; cancel-vs-count serializable; APPROVED/POSTED menolak cancel. Durable rerun tidak menambah effect.

### 25.8 Gap besar tersisa

Tidak ada gap besar frontend/domain lain yang ditemukan oleh source dan test aktual dalam scope audit ini. Reserve/shipment tetap event/adapter-driven.
