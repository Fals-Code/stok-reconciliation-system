# Release Readiness — Slice A

Slice A menambahkan pemeriksaan otomatis PR dan endpoint deployment tanpa mengubah aturan stok.

## CI

Workflow `.github/workflows/phase2-ci.yml` berjalan pada pull request dan push ke `main`.
Ia memasang dependency dari `package-lock.json`, menyalakan Supabase lokal yang terisolasi, membangun `.env.local` sementara dari `supabase status -o env`, lalu menjalankan lint, typecheck, build, smoke health/readiness, dan full pgTAP.

Workflow tidak memakai URL, database, atau kredensial production. Browser harness tidak dijalankan di CI karena harness saat ini meminta password Admin melalui `SecureString`; browser tetap menjadi release gate lokal sampai ada provisioning CI yang aman dan deterministik.

## Validasi lokal

- Reset Supabase lokal selesai berhasil.
- Full pgTAP setelah reset bersih: `Files=72, Tests=4007, Result=PASS`.
- Runtime smoke health/readiness: `PASS, 8 checks`.
- `npm run lint`: PASS dengan 5 warning lama di luar Slice A.
- `npm run typecheck`: PASS.
- `npm run build`: PASS.
- `git diff --check`: PASS.

PR #92 telah dibuat dari `agent/release-readiness` ke `main`. GitHub Actions `Phase 2 CI` run #1 (`31781466281`) benar-benar berjalan pada GitHub-hosted runner melalui trigger `pull_request` untuk head commit `769153a2314a0480f7dbf65af4e134f023297e27`, dengan status akhir `completed` dan conclusion `success`.

Seluruh step `Validate` berhasil: checkout, setup Node, `npm ci`, Supabase CLI, start isolated Supabase, konfigurasi environment local-only, lint, typecheck, build, smoke health/readiness yang stock-neutral, dan full pgTAP. Keberhasilan CI ini bukan deployment production; scheduler belum diimplementasikan pada Slice A dan Issue #91 belum selesai.

## Endpoint deployment

- `GET /api/health/live` mengembalikan `200 {"status":"ok"}` bila proses Next.js merespons. Endpoint ini tidak memeriksa dependency.
- `GET /api/health/ready` melakukan satu `GET` terbatas ke read-model `api.ledger_explorer` melalui credential server-only dan mengembalikan `200 {"status":"ready"}` bila Supabase Data API dapat diakses. Bila konfigurasi atau dependency tidak tersedia, responsnya `503 {"status":"unavailable"}`.

Kedua endpoint bersifat no-store, tidak menerima input, tidak memaparkan konfigurasi/exception, dan tidak menjalankan mutation ledger, projection, reservation, idempotency, maupun reconciliation.

Slice B akan mengaudit scheduler operasional; Slice A tidak menambahkan cron atau scheduled workflow.
