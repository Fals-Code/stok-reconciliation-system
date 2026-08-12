import { readFile } from "node:fs/promises";

const paths = {
  page: "src/app/stocktakes/[stocktakeId]/page.tsx",
  panel: "src/app/stocktakes/components/cancel-stocktake-panel.tsx",
  actions: "src/app/stocktakes/actions.ts",
  queries: "src/lib/stocktakes/queries.ts",
  types: "src/lib/stocktakes/types.ts",
  errors: "src/lib/stocktakes/errors.ts",
};

function ok(value, message) {
  if (!value) throw new Error(message);
}

const source = Object.fromEntries(
  await Promise.all(
    Object.entries(paths).map(async ([name, path]) => [
      name,
      await readFile(path, "utf8"),
    ]),
  ),
);

ok(
  /CancelStocktakePanel/.test(source.page) &&
    /\["DRAFT", "READY", "COUNTING", "REVIEW"\]\.includes\([\s\S]*details\.status_code/.test(source.page),
  "Panel cancel harus hanya tampil pada DRAFT/READY/COUNTING/REVIEW.",
);
ok(
  /details\.status_code === "CANCELLED"/.test(source.page) &&
    /tidak memiliki tindakan lanjutan/.test(source.page) &&
    /stok tidak berubah/.test(source.page) &&
    /cancellation\.reason/.test(source.page),
  "CANCELLED harus terminal, stock-neutral, dan menampilkan alasan.",
);
ok(
  /cancelStocktakeAction/.test(source.panel) &&
    /name="stocktakeId"/.test(source.panel) &&
    /name="reason"/.test(source.panel) &&
    /name="confirmation"/.test(source.panel) &&
    /variant="danger"/.test(source.panel) &&
    /tetap tersimpan untuk audit/.test(source.panel),
  "Form cancel harus meminta identity/reason/confirmation dan menjelaskan audit.",
);
ok(
  /export async function cancelStocktakeAction/.test(source.actions) &&
    /"cancel_stocktake"/.test(source.actions) &&
    /stocktake:" \+ stocktakeId \+ ":cancel:v1"/.test(source.actions) &&
    /p_confirmation: checkbox\(formData, "confirmation"\)/.test(source.actions) &&
    /dibatalkan tanpa mengubah stok/.test(source.actions),
  "Server Action cancel harus trusted, deterministic, confirmed, dan stock-neutral.",
);
ok(
  /getStocktakeCancellation/.test(source.queries) &&
    /organization_id=eq\./.test(source.queries) &&
    /stocktake_id=eq\./.test(source.queries),
  "Read cancellation harus organization dan stocktake scoped.",
);
ok(
  /status_before_code: "DRAFT" \| "READY" \| "COUNTING" \| "REVIEW"/.test(source.types) &&
    /status_after_code: "CANCELLED"/.test(source.types),
  "Type cancellation harus mengunci transition contract.",
);
ok(
  /STOCKTAKE_CANCEL_INVALID_STATE/.test(source.errors) &&
    /STOCKTAKE_CANCEL_REASON_REQUIRED/.test(source.errors) &&
    /STOCKTAKE_CANCEL_CONFIRMATION_REQUIRED/.test(source.errors),
  "Error mapping cancellation belum lengkap.",
);

console.log("PASS - stocktake cancellation UI contract");
