import { approveStocktakeAction } from "@/app/stocktakes/actions";
import { Textarea } from "@/components/ui";
import type { StocktakeReviewLine } from "@/lib/stocktakes/types";

export function ApprovalPanel({ lines, returnTo, stocktakeId, stocktakeVersion }: { lines: StocktakeReviewLine[]; returnTo: string; stocktakeId: string; stocktakeVersion: number }) {
  const unreviewed = lines.filter((line) => line.review_status_code !== "REVIEWED");
  const exceptions = lines.filter((line) => line.exception_code || line.review_decision_code === "EXCEPTION");
  const incomplete = lines.filter(
    (line) =>
      line.count_status_code !== "COUNTED" ||
      line.final_physical_qty === null ||
      line.expected_qty_at_count === null ||
      line.variance_qty === null,
  );
  if (unreviewed.length || exceptions.length || incomplete.length) return <section className="mt-6 rounded-[var(--ui-radius-md)] border border-ui-warning bg-ui-warning-subtle p-4 text-sm text-ui-warning"><h2 className="font-semibold">Hasil belum dapat disetujui</h2><p className="mt-1 leading-6">{unreviewed.length ? `${unreviewed.length} baris masih perlu diperiksa.` : ""} {exceptions.length ? `${exceptions.length} baris ditandai bermasalah dan perlu diselesaikan.` : ""} {incomplete.length ? `${incomplete.length} baris belum memiliki bukti hitungan lengkap.` : ""} Menyetujui hasil tidak mengubah stok.</p></section>;
  return <section className="mt-6 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface p-4"><h2 className="text-lg font-semibold text-ui-text">Setujui Hasil Hitung</h2><p className="mt-1 text-sm leading-6 text-ui-text-muted">Semua {lines.length} baris telah diperiksa. Persetujuan mengunci hasil pemeriksaan untuk tahap simpan perubahan dan belum mengubah stok.</p><form action={approveStocktakeAction} className="mt-4 grid gap-3"><input name="returnTo" type="hidden" value={returnTo} /><input name="stocktakeId" type="hidden" value={stocktakeId} /><input name="stocktakeVersion" type="hidden" value={stocktakeVersion} /><label className="grid gap-2 text-sm font-semibold text-ui-text">Catatan persetujuan<Textarea name="note" /></label><label className="flex items-start gap-2 text-sm text-ui-text"><input className="mt-1" name="confirmation" required type="checkbox" /> Saya sudah memeriksa hasil ini dan setuju untuk menyiapkannya sebelum disimpan.</label><button className="min-h-[var(--ui-control-height)] justify-self-start rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary" type="submit">Setujui Hasil Hitung</button></form></section>;
}
