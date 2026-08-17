# Template Bukti Rilis Produksi

## Status Dokumen

Status: **TEMPLATE / BELUM DIISI**.

Dokumen ini adalah template reusable untuk mencatat bukti rilis produksi Sistem Rekonsiliasi Stok. Dokumen ini **bukan bukti bahwa deployment produksi telah terjadi**, bukan bukti bahwa migration telah diterapkan, dan bukan klaim bahwa check apa pun sudah `PASS`.

Gunakan placeholder yang jelas. Jangan mengganti placeholder dengan nilai production nyata sebelum bukti tersedia dan aman dicatat.

Format hasil yang valid:

```text
NOT_RUN
PASS
FAIL
BLOCKED
```

## Identitas Rilis

| Field | Nilai |
|---|---|
| Deployed commit SHA | `<COMMIT_SHA_BELUM_DIISI>` |
| Release tag/reference | `<RELEASE_TAG_ATAU_REF_BELUM_DIISI>` |
| Environment | `<PRODUCTION_ATAU_ENV_TARGET_BELUM_DIISI>` |
| Timestamp rilis Asia/Jakarta | `<YYYY-MM-DD HH:mm:ss Asia/Jakarta>` |
| Operator rilis | `<NAMA_OPERATOR_BELUM_DIISI>` |
| Reviewer rilis | `<NAMA_REVIEWER_BELUM_DIISI>` |
| Evidence location | `<URL_ATAU_PATH_BUKTI_BELUM_DIISI>` |
| Nomor change/request | `<CHANGE_ID_BELUM_DIISI>` |
| Catatan scope | `<RINGKASAN_SCOPE_RILIS_BELUM_DIISI>` |

## Validation Gates

Catat gate validasi tanpa mengarang hasil. Jika gate belum dijalankan, isi `Result` dengan `NOT_RUN`.

| Command / Gate | Result (`NOT_RUN` / `PASS` / `FAIL` / `BLOCKED`) | Timestamp Asia/Jakarta | Evidence Reference |
|---|---|---|---|
| `<pnpm typecheck atau gate setara>` | `NOT_RUN` | `<YYYY-MM-DD HH:mm:ss Asia/Jakarta>` | `<LINK_ATAU_ID_BUKTI>` |
| `<pnpm lint atau gate setara>` | `NOT_RUN` | `<YYYY-MM-DD HH:mm:ss Asia/Jakarta>` | `<LINK_ATAU_ID_BUKTI>` |
| `<pnpm test:run atau unit/component gate>` | `NOT_RUN` | `<YYYY-MM-DD HH:mm:ss Asia/Jakarta>` | `<LINK_ATAU_ID_BUKTI>` |
| `<supabase test db atau pgTAP gate>` | `NOT_RUN` | `<YYYY-MM-DD HH:mm:ss Asia/Jakarta>` | `<LINK_ATAU_ID_BUKTI>` |
| `<pnpm build atau production build gate>` | `NOT_RUN` | `<YYYY-MM-DD HH:mm:ss Asia/Jakarta>` | `<LINK_ATAU_ID_BUKTI>` |
| `<Playwright smoke / golden-smoke gate>` | `NOT_RUN` | `<YYYY-MM-DD HH:mm:ss Asia/Jakarta>` | `<LINK_ATAU_ID_BUKTI>` |
| `<secret scan / security gate>` | `NOT_RUN` | `<YYYY-MM-DD HH:mm:ss Asia/Jakarta>` | `<LINK_ATAU_ID_BUKTI>` |
| `<migration compatibility gate>` | `NOT_RUN` | `<YYYY-MM-DD HH:mm:ss Asia/Jakarta>` | `<LINK_ATAU_ID_BUKTI>` |

## Migration State

Status migration Supabase: `NOT_RUN` / `PASS` / `FAIL` / `BLOCKED` = `NOT_RUN`.

Isi hanya metadata aman. Jangan mencatat password database, `DATABASE_URL`, `DIRECT_URL`, `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD`, service-role key, atau secret lain.

| Field | Nilai |
|---|---|
| Supabase project reference aman | `<PROJECT_REF_TERREDAKSI_ATAU_ALIAS>` |
| Migration workflow/run ID | `<WORKFLOW_RUN_ID_BELUM_DIISI>` |
| Migration command/gate | `<NAMA_GATE_BELUM_DIISI>` |
| Migration list evidence | `<LINK_ATAU_ID_BUKTI_BELUM_DIISI>` |
| Latest applied migration version | `<MIGRATION_VERSION_BELUM_DIISI>` |
| Expected migration version dari commit | `<EXPECTED_MIGRATION_VERSION_BELUM_DIISI>` |
| Schema compatibility version | `<SCHEMA_COMPAT_VERSION_BELUM_DIISI>` |
| RLS/grants verification evidence | `<LINK_ATAU_ID_BUKTI_BELUM_DIISI>` |
| Direct ledger/projection mutation guard evidence | `<LINK_ATAU_ID_BUKTI_BELUM_DIISI>` |
| Catatan migration | `<CATATAN_BELUM_DIISI>` |

Invariant yang harus dipertahankan:

- Tidak ada direct manual edit ke ledger.
- Tidak ada direct manual edit ke projection.
- Tidak ada penonaktifan RLS sebagai bagian dari release evidence, rollback, recovery, atau workaround.
- Saldo awal production harus melalui alur cutover dan ledger, bukan update projection langsung.

## Health dan Readiness

Catat liveness dan readiness secara terpisah. Jangan menyimpulkan deployment sehat hanya dari salah satu endpoint.

| Endpoint | Tujuan | Result (`NOT_RUN` / `PASS` / `FAIL` / `BLOCKED`) | Timestamp Asia/Jakarta | Evidence Reference | Catatan Aman |
|---|---|---|---|---|---|
| `GET /api/health/live` | Liveness: proses aplikasi merespons | `NOT_RUN` | `<YYYY-MM-DD HH:mm:ss Asia/Jakarta>` | `<LINK_ATAU_ID_BUKTI>` | `<STATUS_CODE_BODY_TERREDAKSI>` |
| `GET /api/health/ready` | Readiness: environment valid, Supabase reachable, safe read/RPC, migration compatibility | `NOT_RUN` | `<YYYY-MM-DD HH:mm:ss Asia/Jakarta>` | `<LINK_ATAU_ID_BUKTI>` | `<STATUS_CODE_BODY_TERREDAKSI>` |

Readiness tidak boleh melakukan mutation stok, reconciliation berat, dump data, atau penggunaan service-role untuk membocorkan data.

## Scheduler / Job Health

Status scheduler produksi: `NOT_RUN` / `PASS` / `FAIL` / `BLOCKED` = `NOT_RUN`.

Tabel ini mengikuti kontrak scheduler produksi Phase 2 saat ini. Jangan menambah row untuk stocktake, return-inspection, marketplace, generic job-health, atau job spekulatif lain.

| Job Code | Cron Name | Configured State | Last Success/Failure | Result (`NOT_RUN` / `PASS` / `FAIL` / `BLOCKED`) | Evidence Reference |
|---|---|---|---|---|---|
| `NOTIFICATION_OUTBOX` | `phase2-notification-outbox` | `<ENABLED_DISABLED_UNKNOWN>` | `<LAST_SUCCESS_FAILURE_BELUM_DIISI>` | `NOT_RUN` | `<LINK_ATAU_ID_BUKTI>` |
| `CLAIM_DEADLINE` | `phase2-claim-deadline` | `<ENABLED_DISABLED_UNKNOWN>` | `<LAST_SUCCESS_FAILURE_BELUM_DIISI>` | `NOT_RUN` | `<LINK_ATAU_ID_BUKTI>` |
| `EXPIRY_DAILY` | `phase2-expiry-daily` | `<ENABLED_DISABLED_UNKNOWN>` | `<LAST_SUCCESS_FAILURE_BELUM_DIISI>` | `NOT_RUN` | `<LINK_ATAU_ID_BUKTI>` |
| `RECONCILIATION_DAILY` | `phase2-reconciliation-daily` | `<ENABLED_DISABLED_UNKNOWN>` | `<LAST_SUCCESS_FAILURE_BELUM_DIISI>` | `NOT_RUN` | `<LINK_ATAU_ID_BUKTI>` |

Bukti scheduler harus membedakan job belum pernah berjalan, sukses terakhir, gagal terakhir, dan blocked karena akses atau environment.

## Backup / PITR

Status backup/PITR: `NOT_RUN` / `PASS` / `FAIL` / `BLOCKED` = `NOT_RUN`.

| Field | Nilai |
|---|---|
| Backup prerequisite tersedia | `<YA_TIDAK_BLOCKED_BELUM_DIISI>` |
| PITR tersedia untuk project production | `<YA_TIDAK_BLOCKED_BELUM_DIISI>` |
| Retention window | `<RETENTION_WINDOW_BELUM_DIISI>` |
| Restore point / timestamp sebelum rilis | `<YYYY-MM-DD HH:mm:ss Asia/Jakarta>` |
| Backup verification method | `<METODE_VERIFIKASI_BELUM_DIISI>` |
| Backup verification result | `NOT_RUN` |
| Evidence reference | `<LINK_ATAU_ID_BUKTI>` |
| Catatan batasan restore | `<CATATAN_BELUM_DIISI>` |

Jangan mencatat credential backup, URL database lengkap, token provider, atau payload data pelanggan.

## Production Smoke

Status production smoke/golden-smoke: `NOT_RUN` / `PASS` / `FAIL` / `BLOCKED` = `NOT_RUN`.

| Field | Nilai |
|---|---|
| Smoke runner / checklist | `<NAMA_RUNNER_ATAU_CHECKLIST_BELUM_DIISI>` |
| Target URL aman | `<HTTPS_PRODUCTION_DOMAIN_PLACEHOLDER>` |
| Test account type | `<ADMIN_TEST_ATAU_OPERATOR_TEROTORISASI_BELUM_DIISI>` |
| Dataset | `<SYNTHETIC_ATAU_APPROVED_PRODUCTION_SAFE_SCOPE>` |
| Golden-smoke evidence | `<LINK_ATAU_ID_BUKTI_BELUM_DIISI>` |
| Result | `NOT_RUN` |
| Timestamp Asia/Jakarta | `<YYYY-MM-DD HH:mm:ss Asia/Jakarta>` |
| Catatan | `<CATATAN_BELUM_DIISI>` |

Production smoke tidak boleh menggunakan data private customer sebagai bukti mentah. Semua screenshot, log, dan response body harus direduksi bila mengandung data sensitif.

## Rollback / Recovery

| Field | Nilai |
|---|---|
| Keputusan rollback/recovery | `<NO_ROLLBACK_ROLLBACK_APP_FORWARD_FIX_DB_BLOCKED_BELUM_DIISI>` |
| Trigger keputusan | `<TRIGGER_BELUM_DIISI>` |
| Target application version/commit | `<TARGET_VERSION_OR_COMMIT_BELUM_DIISI>` |
| Target Vercel deployment/reference | `<DEPLOYMENT_REF_BELUM_DIISI>` |
| Database action default | `forward-fix, bukan destructive rollback` |
| Forward-fix database note | `<CATATAN_FORWARD_FIX_DB_BELUM_DIISI>` |
| Business stock correction note | `gunakan reversal/corrective transaction, bukan edit/hapus ledger` |
| Approval owner | `<NAMA_APPROVER_BELUM_DIISI>` |
| Evidence reference | `<LINK_ATAU_ID_BUKTI_BELUM_DIISI>` |

Recovery tidak boleh menghapus ledger, mengedit projection secara manual, men-disable RLS, atau memakai service-role di browser untuk melewati authorization.

## Final Sign-off

Dokumen ini baru menjadi bukti rilis setelah seluruh placeholder relevan diisi dengan evidence aman dan status eksplisit.

| Field | Nilai |
|---|---|
| Release owner sign-off | `<NAMA_TANGGAL_STATUS_BELUM_DIISI>` |
| Reviewer sign-off | `<NAMA_TANGGAL_STATUS_BELUM_DIISI>` |
| Security/release gate sign-off | `<NAMA_TANGGAL_STATUS_BELUM_DIISI>` |
| Remaining blockers | `<BLOCKER_BELUM_DIISI_ATAU_NONE_SETELAH_DIVERIFIKASI>` |
| Known limitations | `<LIMITASI_BELUM_DIISI_ATAU_NONE_SETELAH_DIVERIFIKASI>` |
| Final release decision | `<GO_NO_GO_BLOCKED_BELUM_DIISI>` |
| Final evidence bundle | `<LINK_ATAU_ID_BUKTI_BELUM_DIISI>` |

Jangan menulis `PASS`, `GO`, atau `no blocker` tanpa evidence aktual.

## Aturan Keamanan Bukti

- Jangan pernah mencatat password.
- Jangan pernah mencatat service-role key, secret key, bearer token, cookie, session token, refresh token, Vercel token, Supabase access token, atau database password.
- Jangan mencatat raw sensitive payload.
- Jangan mencatat private customer data.
- Redact nilai sensitif dengan placeholder seperti `<REDACTED>` atau `<SECRET_NOT_RECORDED>`.
- Bedakan `NOT_RUN`, `PASS`, `FAIL`, dan `BLOCKED` secara eksplisit.
- `BLOCKED` bukan `PASS`.
- `NOT_RUN` bukan `PASS`.
- Screenshot dan log harus direview untuk secret, cookie, bearer token, email private, nomor telepon, alamat, dan data pelanggan sebelum disimpan sebagai evidence.
- Evidence storage harus private dan access-controlled.
- Jangan memakai production service-role sebagai default client request.
- Jangan menaruh secret pada field browser-safe atau output diagnostik public.
- Jangan melakukan direct manual ledger edit sebagai bagian dari evidence, recovery, atau perbaikan data.
- Jangan melakukan direct manual projection edit sebagai bagian dari evidence, recovery, atau perbaikan data.
- Jangan men-disable RLS sebagai bagian dari release evidence, smoke, rollback, recovery, atau workaround.
- Perubahan quantity harus tetap dapat ditelusuri ke ledger/source dan dikoreksi melalui reversal atau corrective transaction yang diaudit.
