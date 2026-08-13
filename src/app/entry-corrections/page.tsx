import { randomUUID } from "node:crypto";
import Link from "next/link";

import { AppShell } from "@/app/app-shell/app-shell";
import { PageHeader } from "@/app/app-shell/page-header";
import { reverseStockTransactionAction } from "@/app/entry-corrections/actions";
import { Alert, EmptyState, Textarea } from "@/components/ui";
import { requireAdminSession } from "@/lib/auth";
import {
  getLedgerTransactionDetail,
  previewStockTransactionReversal,
  type LedgerReversalLink,
} from "@/lib/supabase-rest";

export const dynamic = "force-dynamic";

type SearchParams = Record<string, string | string[] | undefined>;

const formatter = new Intl.NumberFormat("id-ID");

function signed(value: number) {
  return `${value > 0 ? "+" : ""}${formatter.format(value)} unit`;
}

function bucketLabel(code: string) {
  if (code === "SELLABLE") return "Layak Dijual";
  if (code === "QUARANTINE") return "Ditahan";
  if (code === "DAMAGED") return "Rusak";
  return "Kondisi stok";
}

function blockerMessage(code: string, message: string) {
  const known: Record<string, string> = {
    REVERSAL_TRANSACTION_TYPE_NOT_SUPPORTED:
      "Jenis transaksi ini memiliki alur koreksi tersendiri.",
    REVERSAL_ORIGINAL_ENTRIES_REQUIRED:
      "Transaksi ini tidak memiliki perubahan stok yang dapat dibatalkan.",
    ORIGINAL_TRANSACTION_ALREADY_REVERSED:
      "Transaksi ini sudah dibatalkan sebelumnya.",
    REVERSAL_NEGATIVE_BUCKET:
      "Pembatalan akan membuat jumlah pada batch tidak cukup.",
    REVERSAL_RESERVED_CONFLICT:
      "Pembatalan akan membuat barang yang sudah dipesan melebihi jumlah layak dijual.",
    REVERSAL_PROJECTION_DRIFT:
      "Data stok perlu diperiksa sebelum transaksi ini dapat dibatalkan.",
  };

  return known[code] ?? message;
}

function amountTransition(before: number | null, after: number | null) {
  if (before === null || after === null) return "Tidak tersedia";
  return `${formatter.format(before)} unit -> ${formatter.format(after)} unit`;
}

function firstText(params: SearchParams, name: string) {
  const value = params[name];
  return (Array.isArray(value) ? value[0] : value)?.trim() ?? "";
}

function normalizeLedgerReturnTo(value: string) {
  if (!value.startsWith("/") || value.startsWith("//")) return "/ledger";

  try {
    const destination = new URL(value, "http://entry-correction.local");
    if (
      destination.origin !== "http://entry-correction.local" ||
      destination.pathname !== "/ledger" ||
      destination.hash
    ) {
      return "/ledger";
    }
    return `${destination.pathname}${destination.search}`;
  } catch {
    return "/ledger";
  }
}

function ledgerDetailHref(transactionId: string, ledgerReturnTo: string) {
  const context = new URL(ledgerReturnTo, "http://entry-correction.local");
  return `/ledger/${transactionId}${context.search}`;
}

function errorHint(value: string) {
  if (value.includes("Alasan koreksi wajib diisi")) {
    return "Catatan pembatalan wajib diisi sebelum mengirim.";
  }
  if (value.includes("Konfirmasi final wajib dicentang")) {
    return "Konfirmasi pembatalan wajib dicentang sebelum mengirim.";
  }
  if (value.includes("Posisi stok berubah setelah preview dibuat")) {
    return "Dampak stok sudah berubah. Periksa kembali sebelum mengirim.";
  }
  return "Lengkapi catatan dan konfirmasi, lalu periksa dampak transaksi sebelum mengirim kembali.";
}

function uniqueRelationships(
  links: LedgerReversalLink[],
  transactionId: string,
) {
  const relatedIds = new Set<string>();

  return links.filter((link) => {
    const relatedId = link.original_transaction_id === transactionId
      ? link.reversal_transaction_id
      : link.original_transaction_id;

    if (relatedIds.has(relatedId)) return false;
    relatedIds.add(relatedId);
    return true;
  });
}

function ReversalEvidence({
  ledgerReturnTo,
  links,
  transactionId,
}: {
  ledgerReturnTo: string;
  links: LedgerReversalLink[];
  transactionId: string;
}) {
  const relationships = uniqueRelationships(links, transactionId);
  if (!relationships.length) return null;

  return (
    <div className="mt-4 grid gap-3 border-t border-ui-border pt-4">
      {relationships.map((link) => {
        const isOriginal = link.original_transaction_id === transactionId;
        const relatedId = isOriginal
          ? link.reversal_transaction_id
          : link.original_transaction_id;
        const relatedNo = isOriginal
          ? link.reversal_transaction_no
          : link.original_transaction_no;

        return (
          <div
            className="rounded-[var(--ui-radius-md)] border border-ui-border p-4 text-sm"
            key={link.reversal_application_id}
          >
            {isOriginal ? (
              <>
                <p className="font-semibold text-ui-text">
                  Transaksi ini telah dibatalkan.
                </p>
                <p className="mt-1 text-ui-text-muted">
                  Pembatalan: {" "}
                  <Link
                    className="font-semibold text-ui-primary hover:underline"
                     href={ledgerDetailHref(relatedId, ledgerReturnTo)}
                  >
                    {relatedNo}
                  </Link>
                </p>
              </>
            ) : (
              <p className="font-semibold text-ui-text">
                Pembatalan untuk transaksi {" "}
                <Link
                  className="text-ui-primary hover:underline"
                  href={ledgerDetailHref(relatedId, ledgerReturnTo)}
                >
                  {relatedNo}
                </Link>
              </p>
            )}
          </div>
        );
      })}
    </div>
  );
}

export default async function EntryCorrectionsPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const [session, params] = await Promise.all([
    requireAdminSession(),
    searchParams,
  ]);
  const transactionId = firstText(params, "transactionId");
  const ledgerReturnTo = normalizeLedgerReturnTo(
    firstText(params, "ledgerReturnTo"),
  );
  const detail = transactionId
    ? await getLedgerTransactionDetail(transactionId).catch(() => null)
    : null;
  const preview = detail
    ? await previewStockTransactionReversal(detail.transactionId).catch(() => null)
    : null;
  const returnTo = detail
    ? `/entry-corrections?transactionId=${encodeURIComponent(detail.transactionId)}&ledgerReturnTo=${encodeURIComponent(ledgerReturnTo)}#detail`
    : "/entry-corrections#detail";
  const originalId = firstText(params, "originalId");
  const reversalId = firstText(params, "reversalId");
  const reversal = detail && detail.transactionId === originalId && reversalId
    ? await getLedgerTransactionDetail(reversalId).catch(() => null)
    : null;
  const hasVerifiedReversalEvidence = Boolean(
    detail &&
      reversal &&
      detail.transactionId === originalId &&
      detail.reversalLinks.some(
        (link) =>
          link.original_transaction_id === originalId &&
          link.reversal_transaction_id === reversalId,
      ),
  );

  return (
    <AppShell profile={session.profile}>
      <div className="mx-auto w-full max-w-[1040px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        <PageHeader
          description="Transaksi asli tidak dihapus. Pembatalan membuat transaksi baru agar riwayat tetap dapat ditelusuri."
          title="Batalkan Transaksi"
        />
        <p className="mt-4 text-sm text-ui-text-muted">
          Pembatalan transaksi berbeda dari Penyesuaian Hasil Hitung Stok.
          Tidak ada saldo yang dapat diedit langsung.
        </p>

        {hasVerifiedReversalEvidence ? (
          <Alert className="mt-6" title="Pembatalan transaksi tercatat" tone="info">
            <p>Relasi transaksi asal dan pembatalannya tercatat di riwayat.</p>
            <div className="mt-3 flex flex-wrap gap-3">
              <Link className="font-semibold text-ui-primary hover:underline" href={ledgerDetailHref(originalId, ledgerReturnTo)}>Lihat transaksi asal</Link>
              <Link className="font-semibold text-ui-primary hover:underline" href={ledgerDetailHref(reversalId, ledgerReturnTo)}>Lihat transaksi pembatalan</Link>
            </div>
          </Alert>
        ) : null}

        {firstText(params, "error") ? (
          <Alert className="mt-6" title="Periksa kembali pembatalan ini" tone="warning">
            <p>{errorHint(firstText(params, "error"))}</p>
          </Alert>
        ) : null}

        {!transactionId ? (
          <EmptyState
            className="mt-6"
            description="Buka detail transaksi dari Riwayat Stok untuk memeriksa pembatalan."
            title="Pilih transaksi yang akan diperiksa"
          />
        ) : !detail ? (
          <EmptyState
            action={<Link className="inline-flex min-h-[var(--ui-control-height)] items-center rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary" href={ledgerReturnTo}>Kembali ke Riwayat Stok</Link>}
            className="mt-6"
            description="Transaksi tidak ditemukan atau tidak dapat diakses."
            title="Transaksi tidak tersedia"
          />
        ) : (
          <section className="mt-6" id="detail">
            <div className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5 shadow-[var(--ui-shadow-sm)]">
              <p className="text-sm font-semibold text-ui-text">
                {detail.rows[0].transaction_no}
              </p>
              <p className="mt-1 text-sm text-ui-text-muted">
                Periksa semua dampak berikut sebelum membuat pembatalan.
              </p>
              <Link
                className="mt-3 inline-flex min-h-[var(--ui-control-height)] items-center text-sm font-semibold text-ui-primary hover:underline"
                href={ledgerDetailHref(detail.transactionId, ledgerReturnTo)}
              >
                Lihat detail transaksi
              </Link>
              <ReversalEvidence
                ledgerReturnTo={ledgerReturnTo}
                links={detail.reversalLinks}
                transactionId={detail.transactionId}
              />
            </div>

            {preview ? (
              <>
                <section className="mt-6 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface shadow-[var(--ui-shadow-sm)]">
                  <div className="border-b border-ui-border px-5 py-4">
                    <h2 className="font-semibold text-ui-text">Periksa Sebelum Membatalkan</h2>
                    <p className="mt-1 text-sm text-ui-text-muted">
                      Dampak ini diperiksa dari data stok saat ini. Jangan gunakan sebagai pengganti hitung stok.
                    </p>
                  </div>
                  <div className="divide-y divide-ui-border">
                    {preview.lines.map((line) => (
                      <div className="grid gap-3 px-5 py-4 sm:grid-cols-[minmax(0,1fr)_auto]" key={line.originalEntryId}>
                        <div>
                          <p className="font-semibold text-ui-text">{line.productSku}</p>
                          <p className="mt-1 text-sm text-ui-text-muted">
                            Kode Batch {line.batchCode} · {bucketLabel(line.bucketCode)}
                          </p>
                          <p className="mt-2 text-xs text-ui-text-muted">
                            Jumlah batch: {amountTransition(line.currentBatchBucketQty, line.resultingBatchBucketQty)}
                          </p>
                          {line.currentProductSellableQty !== null && line.resultingProductSellableQty !== null ? (
                            <p className="mt-1 text-xs text-ui-text-muted">
                              Layak Dijual produk: {amountTransition(line.currentProductSellableQty, line.resultingProductSellableQty)}
                            </p>
                          ) : null}
                        </div>
                        <div className="text-right">
                          <p className="text-xs text-ui-text-muted">Dampak pembatalan</p>
                          <p className={line.reversalDelta >= 0 ? "ui-number mt-1 font-semibold text-ui-primary" : "ui-number mt-1 font-semibold text-ui-danger"}>
                            {signed(line.reversalDelta)}
                          </p>
                        </div>
                      </div>
                    ))}
                  </div>
                </section>

                {preview.eligible ? (
                  <form action={reverseStockTransactionAction} className="mt-6 rounded-[var(--ui-radius-lg)] border border-ui-danger bg-ui-danger-subtle p-5">
                    <input name="originalTransactionId" type="hidden" value={detail.transactionId} />
                    <input name="previewBasisHash" type="hidden" value={preview.basisHash} />
                    <input name="idempotencyKey" type="hidden" value={`entry-correction:${detail.transactionId}:${randomUUID()}`} />
                    <input name="returnTo" type="hidden" value={returnTo} />
                    <h2 className="font-semibold text-ui-text">Periksa Sebelum Membatalkan</h2>
                    <p className="mt-1 text-sm leading-6 text-ui-text-muted">
                      Transaksi asli tetap ada. Sistem akan mencatat pembatalan baru dengan dampak yang diperiksa di atas.
                    </p>
                    <label className="mt-5 grid gap-2 text-sm font-semibold text-ui-text" htmlFor="reversal-note">
                      Catatan pembatalan
                      <Textarea id="reversal-note" maxLength={2000} minLength={1} name="note" placeholder="Jelaskan kesalahan yang perlu dibatalkan." required rows={4} />
                    </label>
                    <label className="mt-4 flex items-start gap-3 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface p-4 text-sm text-ui-text">
                      <input className="mt-1 size-4" name="confirmation" required type="checkbox" />
                      <span>
                        <span className="font-semibold">Saya sudah meninjau dampak pembatalan ini.</span>
                        <span className="mt-1 block text-ui-text-muted">Transaksi asli tidak akan dihapus atau diedit.</span>
                      </span>
                    </label>
                    <button className="mt-5 inline-flex min-h-[var(--ui-control-height)] items-center rounded-[var(--ui-radius-md)] border border-ui-danger bg-ui-danger px-4 text-sm font-semibold text-ui-text-on-primary hover:opacity-90" type="submit">
                      Batalkan Transaksi
                    </button>
                  </form>
                ) : (
                  <Alert className="mt-6" title="Tidak dapat dibatalkan" tone="warning">
                    <p>{preview.blockers.map((blocker) => blockerMessage(blocker.code, blocker.message)).join(" ") || "Transaksi ini belum memenuhi syarat untuk dibatalkan."}</p>
                  </Alert>
                )}
              </>
            ) : (
              <Alert
                className="mt-6"
                title="Pemeriksaan pembatalan belum dapat dimuat"
                tone="warning"
              >
                <p>
                  Data untuk memeriksa pembatalan belum dapat dimuat.
                  Tidak ada perubahan stok yang dilakukan.
                </p>
              </Alert>
            )}
          </section>
        )}
      </div>
    </AppShell>
  );
}
