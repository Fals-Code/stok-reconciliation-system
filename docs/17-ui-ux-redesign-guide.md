# UI/UX Redesign Guide

## Tujuan

Frontend dibangun sebagai workspace Admin gudang yang:

- sederhana;
- jelas;
- cepat dipindai;
- mudah dipelajari;
- aman untuk operasi stok;
- dapat menjelaskan asal perubahan angka.

Setiap halaman harus membantu pengguna menjawab:

1. Apa yang terjadi?
2. Apa yang perlu dilakukan?
3. Apa dampaknya terhadap stok?
4. Dari transaksi mana angka atau masalah berasal?

Kebenaran stok dan keterlacakan tetap lebih penting daripada kosmetik.

## Prinsip utama

### Satu halaman, satu pekerjaan utama

Setiap halaman memiliki:

- satu judul yang jelas;
- satu deskripsi singkat;
- maksimal satu tindakan utama;
- informasi terpenting tampil lebih dahulu.

### Tampilkan informasi seperlunya

Tampilan utama memprioritaskan:

- nama produk atau proses;
- quantity;
- status;
- masalah;
- tindakan berikutnya.

UUID, hash, payload, event code, dan identifier internal ditempatkan pada detail audit.

### Pola halaman konsisten

Halaman daftar menggunakan urutan:

1. Breadcrumb.
2. Judul dan tindakan utama.
3. Ringkasan.
4. Search dan filter.
5. Daftar atau tabel.
6. Pagination.

Alur perubahan permanen menggunakan urutan:

1. Input.
2. Preview authoritative.
3. Konfirmasi.
4. Bukti keberhasilan.

Preview tidak boleh diganti dengan perhitungan kosmetik di browser.

## Bahasa antarmuka

Gunakan bahasa kerja gudang, seperti:

- Pusat Kendali;
- Barang Keluar;
- Stok Tersedia;
- Riwayat Stok;
- Perlu Diperiksa;
- Menunggu Inspeksi;
- Koreksi Entri;
- Stok Opname;
- Rekonsiliasi.

Istilah teknis seperti ledger sequence, request hash, RPC, event code, dan projection hanya tampil pada detail audit.

Hindari singkatan navigasi seperti DB, BK, RK, atau LG sebagai penanda utama.

## Hierarki tindakan

- Primary: tindakan utama halaman.
- Secondary: tindakan pendukung.
- Ghost atau link: navigasi dan detail.
- Danger: tindakan berisiko.

Jangan menampilkan beberapa tombol dengan bobot visual yang sama.

Form bertahap menggunakan pola:

Batal | Lanjutkan

Tahap akhir menggunakan pola:

Kembali | Konfirmasi dan proses

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
- warna status selalu disertai label;
- shadow digunakan sedikit;
- border tipis menjadi pemisah utama;
- tidak semua bagian dijadikan kartu;
- quantity memakai tabular numerals dan rata kanan;
- radius utama 8 sampai 12 px.

## Responsive

### Mobile

- sidebar menjadi drawer;
- tabel padat berubah menjadi task card;
- target sentuh minimal 44 x 44 px;
- drawer mengunci scroll belakang;
- fokus kembali ke tombol pembuka setelah drawer ditutup.

### Tablet

- navigasi lebih ringkas;
- tabel hanya mempertahankan kolom prioritas;
- detail dapat memakai sheet atau split view.

### Desktop

- sidebar persistent;
- tabel menggunakan lebar yang tersedia;
- detail dapat dibuka melalui drawer;
- halaman data tidak dipaksa masuk kartu sempit.

## Pola bisnis

### Pusat Kendali

Menampilkan antrean kerja berdasarkan prioritas. Setiap item membuka sumber atau tindakan yang benar tanpa membuat mutation baru.

### Barang Keluar FEFO

Admin memasukkan produk dan quantity. Sistem menampilkan alokasi FEFO sebagai preview read-only. Admin tidak memilih batch.

### Retur

Pisahkan:

- tahap proses;
- kondisi fisik;
- dampak stok.

Expected return dan penerimaan fisik tidak otomatis mengubah stok. Hanya inspeksi SELLABLE yang membuat inbound ke batch RETURN baru.

### Rekonsiliasi

Pisahkan pemeriksaan integritas internal dari perbandingan hasil hitung fisik.

Tampilkan:

- nilai seharusnya;
- nilai tercatat;
- delta;
- kemungkinan sumber;
- tautan bukti.

## Domain guardrails

UI tidak boleh mengubah aturan berikut:

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
12. Koreksi Entri menggunakan reversal.
13. Penyesuaian Opname merupakan proses terpisah.
14. Preview wajib dipertahankan untuk stock-out dan koreksi manual.

## State wajib

Halaman dan komponen harus menyediakan state nyata:

- loading;
- empty;
- error;
- blocked;
- success;
- stale preview;
- replay atau idempotent success bila relevan.

Tidak boleh ada placeholder, tombol mati, link palsu, atau form palsu.

## Urutan migrasi

1. Panduan dan design tokens.
2. App shell, navigasi, breadcrumb, dan page header.
3. Komponen dasar.
4. Pusat Kendali sebagai pilot.
5. Worklist read-only.
6. Alur perubahan stok.
7. Retur dan rekonsiliasi.
8. Responsive, accessibility, dan cleanup legacy UI.

Setiap kelompok harus dapat direview dan divalidasi secara terpisah.
