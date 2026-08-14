# Release Readiness — Slice B

Slice B menambahkan kontrak scheduler produksi berbasis Supabase Cron (`pg_cron`). Implementasi ini belum melakukan provisioning atau verifikasi cron pada proyek Supabase production; itu tetap pekerjaan Slice C/runbook.

## Provider dan boundary

`pg_cron` menjalankan fungsi database lokal pada database yang sama. Tidak ada endpoint HTTP cron, Vercel Cron, GitHub schedule, Edge Function, atau secret service-role pada aplikasi/browser.

Empat job katalog tetap:

| Operasi Admin | Job code | Jadwal pg_cron UTC | Waktu operasional WIB |
| --- | --- | --- | --- |
| Pemrosesan Notifikasi | `NOTIFICATION_OUTBOX` | setiap menit | setiap menit |
| Pengingat Klaim | `CLAIM_DEADLINE` | menit ke-7 setiap jam | tiap jam |
| Pemeriksaan Kedaluwarsa | `EXPIRY_DAILY` | `10 17 * * *` | 00:10 WIB |
| Rekonsiliasi Harian | `RECONCILIATION_DAILY` | `25 17 * * *` | 00:25 WIB, setelah expiry |

`pg_cron` lokal menggunakan UTC. Slot harian dihitung di database dari `Asia/Jakarta`; timezone server tidak diubah.

## Keamanan dan integritas

- `scheduler.job_runs` adalah ledger operasional privat untuk empat job tetap, dengan unique invariant `job + scope + slot`.
- Repeated atau concurrent trigger slot sama mengembalikan hasil run yang sama, tanpa delegasi domain kedua.
- Scheduler hanya menjalankan evaluator/outbox yang sudah authoritative dan `api.run_reconciliation` yang ada. Ia tidak menulis transaction, ledger, projection, reservation, FEFO, stocktake, return inspection, maupun lifecycle marketplace.
- Rekonsiliasi scheduled memakai core yang sama dengan manual; run yang dihasilkan diprovenance-kan sebagai `DAILY` / `SYSTEM`. Manual tetap `MANUAL` / `MANUAL`.
- Rekonsiliasi sukses mengantrekan event evaluator notifikasi yang sudah ada dengan identity deterministik; outbox minute worker yang akan mendelegasikannya.
- Semua fungsi `scheduler` privat: tidak ada EXECUTE untuk `PUBLIC`, `anon`, `authenticated`, atau `service_role`. Read contract `api.scheduler_operations_summary()` hanya untuk Admin authenticated dan menyaring organisasi dari session trusted.
- Kegagalan delegate dicatat sebagai `FAILED` dengan kode/ringkasan tersanitasi. `cron.job_run_details` menandakan kesehatan invokasi provider; `scheduler.job_runs` menandakan hasil domain job.

## Observabilitas Admin

`/notifications/operations` menampilkan bagian **Operasi Sistem Terjadwal** dalam halaman diagnostik yang telah ada. Tampilan memakai status Sehat, Gagal, Terlambat, atau Belum Pernah Berjalan serta waktu selesai/failure tersanitasi. Tidak menampilkan nama fungsi SQL, cron expression, payload, atau secret.

## Validasi lokal Slice B

Jalankan sesudah Supabase lokal hidup dan migration diterapkan:

```powershell
npx supabase migration up --local
npx supabase test db supabase/tests/073_production_scheduler_contract.test.sql
npm run test:scheduler-parallel
npm run test:notification-admin-operations
```

Setelah focused gate lulus, jalankan lint, typecheck, build, dan full pgTAP. Browser Admin tetap release gate lokal terpisah.

## Yang belum dilakukan

- provisioning dan inspeksi cron pada Supabase production;
- verifikasi observability provider production;
- production environment/backup/migration promotion, golden smoke, rollback, dan release evidence;
- scheduler untuk stocktake, keputusan retur, marketplace mutation, CSV lifecycle, email, atau WhatsApp.