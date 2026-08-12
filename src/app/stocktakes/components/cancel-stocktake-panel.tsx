import { cancelStocktakeAction } from "@/app/stocktakes/actions";
import { Alert, Button, Textarea } from "@/components/ui";

export function CancelStocktakePanel({
  stocktakeId,
}: {
  stocktakeId: string;
}) {
  return (
    <section className="mt-6 rounded-[var(--ui-radius-md)] border border-ui-danger/40 bg-ui-surface p-4">
      <h2 className="text-lg font-semibold text-ui-text">
        Batal Hitung Stok
      </h2>
      <Alert className="mt-3" title="Pembatalan bersifat final" tone="warning">
        Proses Hitung Stok akan dihentikan. Hasil hitung yang sudah dicatat
        tetap tersimpan untuk audit. Stok tidak berubah karena sesi belum
        diposting, dan sesi yang dibatalkan tidak dapat dilanjutkan.
      </Alert>

      <form action={cancelStocktakeAction} className="mt-4 space-y-4">
        <input name="stocktakeId" type="hidden" value={stocktakeId} />

        <label className="block">
          <span className="text-sm font-semibold text-ui-text">
            Alasan pembatalan
          </span>
          <Textarea
            className="mt-2"
            maxLength={2000}
            name="reason"
            placeholder="Contoh: area gudang belum siap dihitung."
            required
          />
        </label>

        <label className="flex items-start gap-3 text-sm text-ui-text">
          <input
            className="mt-1 size-4"
            name="confirmation"
            required
            type="checkbox"
          />
          <span>
            Saya memahami sesi dihentikan tanpa mengubah stok dan tidak dapat
            dilanjutkan.
          </span>
        </label>

        <Button type="submit" variant="danger">
          Batal Hitung Stok
        </Button>
      </form>
    </section>
  );
}
