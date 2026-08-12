import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const root = process.cwd();
const files = {
  landing: "src/app/stocktakes/page.tsx",
  create: "src/app/stocktakes/new/page.tsx",
  createForm: "src/app/stocktakes/create-form.tsx",
  detail: "src/app/stocktakes/[stocktakeId]/page.tsx",
  feedback: "src/app/stocktakes/presentation-feedback.tsx",
  counting: "src/app/stocktakes/components/counting-panel.tsx",
  review: "src/app/stocktakes/components/review-panel.tsx",
  approval: "src/app/stocktakes/components/approval-panel.tsx",
  posting: "src/app/stocktakes/components/posting-panel.tsx",
};
const pgtapFiles = [
  "supabase/tests/023_stocktake_session_commands.test.sql",
  "supabase/tests/024_stocktake_counting_commands.test.sql",
  "supabase/tests/025_stocktake_review_approval.test.sql",
  "supabase/tests/026_stocktake_adjustment_posting.test.sql",
  "supabase/tests/027_stocktake_review_view_contract.test.sql",
  "supabase/tests/028_stocktake_list_blind_confidentiality.test.sql",
];
const reviewReasons = [
  "UNRECORDED_MANUAL_OUTBOUND",
  "UNRECORDED_INBOUND",
  "RETURN_MISMATCH",
  "WRONG_BATCH_COUNT",
  "WRONG_BUCKET_COUNT",
  "DAMAGE_NOT_RECORDED",
  "EXPIRY_NOT_RECORDED",
  "INITIAL_BALANCE_UNCERTAIN",
  "COUNT_TIMING_DIFFERENCE",
  "DUPLICATE_MOVEMENT",
  "SOURCE_EVENT_FAILURE",
  "PROJECTION_DRIFT",
  "PHYSICAL_LOSS",
  "PHYSICAL_SURPLUS",
  "MASTER_DATA_ERROR",
  "UNKNOWN",
  "OTHER",
];

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function readSources() {
  const entries = await Promise.all(
    Object.entries(files).map(async ([name, filePath]) => [
      name,
      await readFile(path.resolve(root, filePath), "utf8"),
    ]),
  );
  return Object.fromEntries(entries);
}

function assertFormContract(source, action, fields) {
  const form = new RegExp(`<form[^>]*action=\\{${action}\\}[\\s\\S]*?<\\/form>`).exec(source)?.[0];
  assert(form, `Form ${action} tidak ditemukan.`);

  for (const field of fields) {
    assert(new RegExp(`name="${field}"`).test(form), `${action} harus membawa ${field}.`);
  }
}

function assertNoPrimaryTechnicalCopy(source) {
  const forbidden = [
    "Mode CONTINUOUS",
    "Versi sesi",
    "Ledger #",
    "Reconciliation ",
    "Snapshot persetujuan versi",
    "transaction_id}",
    "reconciliation_run_id}",
  ];

  for (const value of forbidden) {
    assert(!source.includes(value), `UI operator masih memuat informasi teknis: ${value}`);
  }
}

function runPgtap(filePath) {
  const isWindows = process.platform === "win32";
  const command = isWindows ? process.env.ComSpec || "cmd.exe" : "npx";
  const args = isWindows
    ? ["/d", "/s", "/c", `npx supabase test db --local ${filePath}`]
    : ["supabase", "test", "db", "--local", filePath];
  const result = spawnSync(command, args, {
    cwd: root,
    encoding: "utf8",
    shell: false,
    windowsHide: true,
  });

  if (result.status !== 0) {
    throw new Error(`pgTAP gagal: ${filePath}\n${result.error?.message ?? ""}\n${result.stdout ?? ""}\n${result.stderr ?? ""}`);
  }
}

async function main() {
  const source = await readSources();
  const combined = Object.values(source).join("\n");

  assert(/requireAdminSession/.test(source.landing) && /requireAdminSession/.test(source.create) && /requireAdminSession/.test(source.detail), "Semua route Hitung Stok harus menjaga akses Admin.");
  assert(source.createForm.startsWith('"use client"'), "Form buat harus interaktif di browser.");
  assert(source.counting.startsWith('"use client"'), "Panel counting harus menampilkan konfirmasi nol secara kondisional.");
  assert(source.review.startsWith('"use client"'), "Panel review harus memvalidasi kebutuhan keputusan secara kondisional.");
  assert(/scopeMode/.test(source.createForm) && /selectedScope/.test(source.createForm), "Cakupan buat belum dikendalikan secara kondisional.");
  assert(/selectedScope === "PRODUCTS"/.test(source.createForm), "Pilihan produk harus hanya tampil untuk cakupan produk.");
  assert(/selectedScope === "BATCHES"/.test(source.createForm), "Pilihan batch harus hanya tampil untuk cakupan batch.");
  assert(/<details/.test(source.createForm), "Pilihan tambahan harus berada di disclosure sekunder.");
  assert(!/name="modeCode"/.test(source.createForm), "Form tidak boleh mengirim mode yang tidak dipakai action.");
  assert(/redirect\("\/stocktakes\/new\?notice=retry"\)/.test(source.create), "Halaman buat harus redirect server-side dari parameter mentah ke notice retry.");
  assert(/notice === "retry"/.test(source.create) && /StocktakePresentationFeedback/.test(source.create), "Halaman buat harus merender feedback hanya dari notice dan membersihkannya setelah hidrasi.");
  assert(/idempotencyKey=\{randomUUID\(\)\}/.test(source.create) && !/idempotencyKey=\{params\.idempotencyKey/.test(source.create), "Form buat harus selalu memakai command identity baru dari server.");
  assert(/Isian sebelumnya dipulihkan\. Periksa lalu coba buat sesi lagi\./.test(source.create) && !/\{params\.error\}/.test(source.create), "Halaman buat tidak boleh merefleksikan error URL mentah.");
  assert(/physicalQty/.test(source.counting) && /physicalQty === "0"/.test(source.counting), "Konfirmasi nol harus bergantung pada jumlah fisik nol.");
  assert(/visibility === "NON_BLIND"/.test(source.counting) && /isNonBlindLine/.test(source.counting), "Counting NON_BLIND harus memakai data yang tersedia secara aman.");
  assert(/expected_qty_at_count/.test(source.counting) && /variance_qty/.test(source.counting), "Counting NON_BLIND harus menampilkan catatan sistem dan selisih bila tersedia.");
  assert(/visibility === "BLIND"/.test(source.counting) && /visibility === "NON_BLIND" && isNonBlindLine/.test(source.counting), "Counting BLIND harus memagari akses nilai sistem, selisih, dan riwayat.");
  assert(/Kode Batch/.test(source.counting), "Panel counting harus memakai istilah Kode Batch.");
  assert(/line\.count_status_code !== "COUNTED"/.test(source.counting), "Baris yang sudah dihitung tidak boleh langsung menampilkan form hitung baru.");
  assert(/recountOpenByLine/.test(source.counting) && /Hitung ulang/.test(source.counting), "Permintaan hitung ulang harus menjadi aksi sekunder yang dibuka secara eksplisit.");
  assert(/disabled=\{!allCounted\}/.test(source.counting), "Penghitungan tidak boleh diselesaikan dari UI sebelum seluruh lokasi selesai.");
  assert(/Jumlah sistem dan selisih disembunyikan selama menghitung\./.test(source.counting), "Mode BLIND harus menjelaskan bahwa angka sistem dan selisih disembunyikan.");
  assert(/Fisik terakhir/.test(source.counting) && /Selisih terakhir/.test(source.counting), "Baris selesai NON_BLIND harus menampilkan ringkasan hasil secara ringkas.");
  assert(/role="progressbar"/.test(source.detail) && /lokasi\s+selesai/.test(source.detail), "Detail Hitung Stok harus menampilkan progres lokasi sebagai anchor utama.");
  assert(!/Ãƒâ€šÃ‚Â·|ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢/.test(source.detail + source.counting), "Detail/counting tidak boleh memuat mojibake.");
  assert(/history\.replaceState/.test(source.feedback) && /params\.delete\("notice"\)/.test(source.feedback), "Feedback harus membersihkan notice setelah hidrasi.");
  assert(
    /safeInternalRoute\(/.test(source.detail) &&
      /allowedPathnames:\s*\["\/stocktakes"\]/.test(source.detail) &&
      /params\.set\("returnTo", returnTo\)/.test(source.detail) &&
      source.detail.includes("`/stocktakes/${encodeURIComponent(stocktakeId)}?${params}`"),
    "Halaman detail harus redirect server-side ke notice aman sambil mempertahankan returnTo internal yang tervalidasi.",
  );
  assert(/notice === "updated"/.test(source.detail) && /notice === "retry"/.test(source.detail) && /StocktakePresentationFeedback/.test(source.detail), "Halaman detail harus memakai notice sekali pakai untuk feedback aman.");
  assert(/Perubahan belum dapat disimpan\. Muat ulang halaman lalu coba lagi\./.test(source.detail) && !/>\{error\}<\/Alert>/.test(source.detail), "Halaman detail tidak boleh merefleksikan error URL mentah.");
  assert(/required=\{decision === "VARIANCE_ACCEPTED"\}/.test(source.review), "Alasan harus diwajibkan saat menerima selisih.");
  assert(/required=\{decision === "EXCEPTION"\}/.test(source.review), "Kode masalah harus diwajibkan saat menandai masalah.");
  assert(/requiresNote/.test(source.review), "Catatan harus diwajibkan untuk alasan UNKNOWN atau OTHER.");
  assert(/hasVariance/.test(source.review) && /hasVariance \?/.test(source.review), "Pilihan review harus berbeda untuk selisih nol dan tidak nol.");
  assert(/defaultValue=\{line\.review_note/.test(source.review) && /defaultValue=\{line\.exception_code/.test(source.review), "Catatan review dan masalah sebelumnya harus dipertahankan.");
  assert(/Penghitungan ke-/.test(source.review) && /physical_qty/.test(source.review) && /counted_at/.test(source.review) && /count_cutoff_ledger_seq/.test(source.review) && /Dicatat saat penghitungan ini disimpan/.test(source.review) && /attempt\.note/.test(source.review) && !/Batas catatan #/.test(source.review) && !/\{attempt\.count_cutoff_ledger_seq\}/.test(source.review), "Riwayat review harus menampilkan cutoff tanpa angka teknis.");
  for (const reason of reviewReasons) assert(source.review.includes(reason), `Alasan review ${reason} belum tersedia.`);
  assert(/unreviewed/.test(source.approval) && /exceptions/.test(source.approval), "Persetujuan harus diblokir untuk baris belum diperiksa atau bermasalah.");
  assert(/getStocktakeReviewLines/.test(source.detail) && /reviewLines/.test(source.posting), "Preview posting harus memakai identitas operator dari review lines.");
  assert(/status === "POSTING"/.test(source.posting), "Posting harus menjelaskan status pemrosesan tanpa mengulangi perintah.");
  assert(/status === "APPROVED"/.test(source.posting) && /postStocktakeAdjustmentAction/.test(source.posting), "Posting hanya boleh tersedia setelah hasil disetujui.");
  assert(/details.status_code === "EXCEPTION"/.test(source.detail) && /details.status_code === "CANCELLED"/.test(source.detail) && /tidak memiliki tindakan\s+lanjutan/.test(source.detail), "State bermasalah dan dibatalkan harus terminal tanpa action.");
  assert(/activeStocktakes/.test(source.landing) && /historyStocktakes/.test(source.landing), "Landing harus memisahkan pekerjaan aktif dan riwayat terminal.");
  assert(!/<table/.test(combined), "Hitung Stok tidak boleh memakai tabel horizontal sebagai UI utama mobile.");
  assertNoPrimaryTechnicalCopy(combined);
  assertFormContract(source.detail, "prepareStocktakeAction", ["returnTo", "stocktakeId"]);
  assertFormContract(source.detail, "startStocktakeAction", ["returnTo", "stocktakeId", "confirmStart"]);
  assertFormContract(source.counting, "submitStocktakeCountAction", ["returnTo", "stocktakeId", "stocktakeLineId", "attemptNo", "physicalQty"]);
  assertFormContract(source.counting, "requestStocktakeRecountAction", ["returnTo", "stocktakeId", "stocktakeLineId", "attemptNo", "reason"]);
  assertFormContract(source.review, "reviewStocktakeLineAction", ["returnTo", "stocktakeId", "stocktakeLineId", "lineVersion", "decisionCode", "reasonCode", "reviewNote", "exceptionCode"]);
  assertFormContract(source.review, "requestStocktakeReviewRecountAction", ["returnTo", "stocktakeId", "stocktakeLineId", "lineVersion", "reason"]);
  assertFormContract(source.approval, "approveStocktakeAction", ["returnTo", "stocktakeId", "stocktakeVersion", "confirmation"]);
  assertFormContract(source.posting, "postStocktakeAdjustmentAction", ["returnTo", "stocktakeId", "approvalVersion", "confirmation"]);

  console.log("[PASS] kontrak presentasi Hitung Stok");
  for (const filePath of pgtapFiles) {
    runPgtap(filePath);
    console.log(`[PASS] lifecycle domain: ${filePath}`);
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
