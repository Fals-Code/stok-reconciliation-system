import Link from "next/link";
import { notFound } from "next/navigation";

import { AppShell } from "@/app/app-shell/app-shell";
import { PageHeader } from "@/app/app-shell/page-header";
import { Alert, StatusBadge } from "@/components/ui";
import { requireAdminSession } from "@/lib/auth";
import {
  getLedgerTransactionDetail,
  previewStockTransactionReversal,
  type LedgerExplorerRow,
  type LedgerReversalLink,
} from "@/lib/supabase-rest";

export const dynamic = "force-dynamic";

type SearchParams = Record<string, string | string[] | undefined>;

const formatter = new Intl.NumberFormat("id-ID");
const dateFormatter = new Intl.DateTimeFormat("id-ID", {
  timeZone: "Asia/Jakarta",
  dateStyle: "medium",
  timeStyle: "short",
});

function first(value: SearchParams[string]) {
  return Array.isArray(value) ? value[0] : value;
}

function formatDate(value: string | null) {
  const date = value ? new Date(value) : null;
  return date && !Number.isNaN(date.getTime()) ? dateFormatter.format(date) : "-";
}

function signed(value: number) {
  return `${value > 0 ? "+" : ""}${formatter.format(value)} unit`;
}

function typeLabel(code: string) {
  if (code === "INITIAL_BALANCE") return "Saldo Awal";
  if (code === "RECEIPT") return "Barang Masuk";
  if (["MARKETPLACE_OUTBOUND", "OUTBOUND_MARKETPLACE", "MANUAL_OUTBOUND", "OUTBOUND_MANUAL"].includes(code)) return "Barang Keluar";
  if (code.startsWith("RETURN")) return "Retur";
  if (code === "DISPOSAL_DAMAGED") return "Barang Rusak";
  if (code === "DISPOSAL_EXPIRED") return "Barang Kedaluwarsa";
  if (code.startsWith("DISPOSAL")) return "Barang Rusak / Kedaluwarsa";
  if (code === "STOCKTAKE_ADJUSTMENT") return "Penyesuaian Hasil Hitung";
  if (code === "REVERSAL") return "Pembatalan Transaksi";
  return "Perubahan Stok";
}

function bucketLabel(code: LedgerExplorerRow["bucket_code"]) {
  if (code === "SELLABLE") return "Layak Dijual";
  if (code === "QUARANTINE") return "Ditahan";
  return "Rusak";
}

function reversalLabel(state: LedgerExplorerRow["reversal_state"]) {
  if (state === "REVERSAL") return "Transaksi pembatalan";
  if (state === "FULLY_REVERSED") return "Sudah dibatalkan";
  if (state === "PARTIALLY_REVERSED") return "Sebagian dibatalkan";
  return "Belum dibatalkan";
}

function codeLabel(value: string) {
  return value.toLowerCase().split("_").filter(Boolean).map((part) => part.charAt(0).toUpperCase() + part.slice(1)).join(" ");
}

function blockerMessage(
  code: string,
  message: string,
) {
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

const ledgerSearchParamNames = [
  "occurredFrom", "occurredTo", "recordedFrom", "recordedTo", "productId",
  "productSku", "batchId", "batchCode", "transactionType", "reason", "channel",
  "sourceType", "sourceRef", "actorProcess", "bucket", "quantityDirection",
  "reversalState",
] as const;

function isLedgerCursor(value: string) {
  return /^\d+$/.test(value) && BigInt(value) > BigInt(0);
}

function ledgerReturnTo(params: SearchParams) {
  const query = new URLSearchParams();
  const requestedPage = first(params.page)?.trim() ?? "";
  const parsedPage = /^[1-9]\d*$/.test(requestedPage) ? Number(requestedPage) : 1;
  const page = Number.isSafeInteger(parsedPage) ? parsedPage : 1;
  const cursor = first(params.cursor)?.trim() ?? "";
  const hasKeysetContext = page > 1 && isLedgerCursor(cursor);

  for (const key of ledgerSearchParamNames) {
    const resolved = first(params[key]);
    if (resolved?.trim()) query.set(key, resolved);
  }
  if (requestedPage) query.set("page", String(hasKeysetContext ? page : 1));
  if (hasKeysetContext) {
    query.set("cursor", cursor);
    query.set("direction", first(params.direction)?.trim() === "previous" ? "previous" : "next");
  }
  const encoded = query.toString();
  return encoded ? `/ledger?${encoded}` : "/ledger";
}

function ledgerDetailHref(transactionId: string, returnTo: string) {
  const context = new URL(returnTo, "http://ledger.local");
  return `/ledger/${transactionId}${context.search}`;
}

function entryCorrectionHref(transactionId: string, returnTo: string) {
  const query = new URLSearchParams({
    transactionId,
    ledgerReturnTo: returnTo,
  });
  return `/entry-corrections?${query.toString()}`;
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

function Linkage({ links, transactionId, ledgerReturnTo }: { links: LedgerReversalLink[]; transactionId: string; ledgerReturnTo: string }) {
  const relationships = uniqueRelationships(links, transactionId);
  if (!relationships.length) return <p className="text-sm text-ui-text-muted">Belum ada pembatalan yang tertaut pada transaksi ini.</p>;

  return (
    <div className="grid gap-3">
      {relationships.map((link) => {
        const isOriginal = link.original_transaction_id === transactionId;
        const relatedId = isOriginal ? link.reversal_transaction_id : link.original_transaction_id;
        const relatedNo = isOriginal ? link.reversal_transaction_no : link.original_transaction_no;

        return (
          <div className="rounded-[var(--ui-radius-md)] border border-ui-border p-4" key={link.reversal_application_id}>
            {isOriginal ? (
              <>
                <p className="font-semibold text-ui-text">Transaksi ini telah dibatalkan.</p>
                <p className="mt-1 text-sm text-ui-text-muted">
                  Pembatalan: <Link className="font-semibold text-ui-primary hover:underline" href={ledgerDetailHref(relatedId, ledgerReturnTo)}>{relatedNo}</Link>
                </p>
              </>
            ) : (
              <p className="font-semibold text-ui-text">
                  Pembatalan untuk transaksi <Link className="text-ui-primary hover:underline" href={ledgerDetailHref(relatedId, ledgerReturnTo)}>{relatedNo}</Link>
              </p>
            )}
          </div>
        );
      })}
    </div>
  );
}

function DetailReadFailure({
  profile,
  backTo,
}: {
  profile: Awaited<ReturnType<typeof requireAdminSession>>["profile"];
  backTo: string;
}) {
  return (
    <AppShell profile={profile}>
      <div className="mx-auto w-full max-w-[840px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        <PageHeader title="Detail transaksi belum dapat dimuat" />
        <Alert className="mt-6" title="Detail transaksi belum dapat dimuat" tone="danger">
          <p>Detail transaksi tidak dapat dimuat. Coba buka riwayat transaksi lagi.</p>
          <Link className="mt-3 inline-flex min-h-[var(--ui-control-height)] items-center rounded-[var(--ui-radius-md)] border border-ui-danger px-4 font-semibold" href={backTo}>Kembali ke Riwayat Stok</Link>
        </Alert>
      </div>
    </AppShell>
  );
}

export default async function LedgerTransactionPage({
  params,
  searchParams,
}: {
  params: Promise<{ transactionId: string }>;
  searchParams: Promise<SearchParams>;
}) {
  const [session, resolvedParams, query] = await Promise.all([
    requireAdminSession(),
    params,
    searchParams,
  ]);
  let detail;

  try {
    detail = await getLedgerTransactionDetail(resolvedParams.transactionId);
  } catch {
    return <DetailReadFailure backTo={ledgerReturnTo(query)} profile={session.profile} />;
  }

  if (!detail) notFound();

  const firstRow = detail.rows[0];
  const preview = await previewStockTransactionReversal(detail.transactionId).catch(() => null);
  const returnTo = ledgerReturnTo(query);

  return (
    <AppShell profile={session.profile}>
      <div className="mx-auto w-full max-w-[1120px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        <Link className="inline-flex min-h-[var(--ui-control-height)] items-center text-sm font-semibold text-ui-primary hover:underline" href={returnTo}>
          Kembali ke Riwayat Stok
        </Link>
        <div className="mt-4">
          <PageHeader
            action={preview?.eligible ? <Link className="inline-flex min-h-[var(--ui-control-height)] items-center rounded-[var(--ui-radius-md)] border border-ui-danger bg-ui-danger px-4 text-sm font-semibold text-ui-text-on-primary hover:opacity-90" href={entryCorrectionHref(detail.transactionId, returnTo)}>Batalkan Transaksi</Link> : undefined}
            description={typeLabel(firstRow.transaction_type_code)}
            title="Detail Transaksi"
          />
        </div>

        <section className="mt-6 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5 shadow-[var(--ui-shadow-sm)]">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <p className="text-lg font-semibold text-ui-text">{firstRow.transaction_no}</p>
              <p className="mt-1 text-sm text-ui-text-muted">{firstRow.note || "Tidak ada catatan tambahan pada transaksi ini."}</p>
            </div>
            <StatusBadge tone={firstRow.reversal_state === "NOT_REVERSED" ? "neutral" : "warning"}>{reversalLabel(firstRow.reversal_state)}</StatusBadge>
          </div>
          <dl className="mt-5 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <div><dt className="text-xs font-semibold text-ui-text-muted">Waktu kejadian</dt><dd className="mt-1 text-sm text-ui-text">{formatDate(firstRow.occurred_at)}</dd></div>
            <div><dt className="text-xs font-semibold text-ui-text-muted">Waktu dicatat</dt><dd className="mt-1 text-sm text-ui-text">{formatDate(firstRow.recorded_at)}</dd></div>
            <div><dt className="text-xs font-semibold text-ui-text-muted">Alasan</dt><dd className="mt-1 text-sm text-ui-text">{codeLabel(firstRow.reason_code_snapshot)}</dd></div>
            <div><dt className="text-xs font-semibold text-ui-text-muted">Kanal / Sumber</dt><dd className="mt-1 text-sm text-ui-text">{codeLabel(firstRow.channel_code_snapshot)}</dd></div>
            <div><dt className="text-xs font-semibold text-ui-text-muted">Referensi sumber</dt><dd className="mt-1 text-sm text-ui-text">{firstRow.source_ref_snapshot}</dd></div>
            <div><dt className="text-xs font-semibold text-ui-text-muted">Dilakukan oleh</dt><dd className="mt-1 text-sm text-ui-text">{firstRow.process_name ? "Proses otomatis" : "Akun Admin"}</dd></div>
          </dl>
        </section>

        <section className="mt-6 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface shadow-[var(--ui-shadow-sm)]">
          <div className="border-b border-ui-border px-5 py-4"><h2 className="font-semibold text-ui-text">Dampak stok</h2><p className="mt-1 text-sm text-ui-text-muted">Jumlah per produk, batch, dan kondisi stok pada transaksi ini.</p></div>
          <div className="divide-y divide-ui-border" data-testid="ledger-detail-entries">
            {detail.rows.map((row) => (
              <div className="grid gap-3 px-5 py-4 sm:grid-cols-[minmax(0,1fr)_auto_auto]" key={row.ledger_entry_id}>
                <div><p className="font-semibold text-ui-text">{row.product_sku_snapshot}</p><p className="mt-1 text-sm text-ui-text-muted">Kode Batch {row.batch_code_snapshot} · {bucketLabel(row.bucket_code)}</p></div>
                <p className={row.quantity_delta >= 0 ? "ui-number font-semibold text-ui-primary" : "ui-number font-semibold text-ui-danger"}>{signed(row.quantity_delta)}</p>
                <StatusBadge tone={row.reversal_state === "NOT_REVERSED" ? "neutral" : "warning"}>{reversalLabel(row.reversal_state)}</StatusBadge>
              </div>
            ))}
          </div>
        </section>

        <section className="mt-6 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5 shadow-[var(--ui-shadow-sm)]">
          <h2 className="font-semibold text-ui-text">Status pembatalan</h2>
          <div className="mt-4"><Linkage ledgerReturnTo={returnTo} links={detail.reversalLinks} transactionId={detail.transactionId} /></div>
          {!preview ? (
            <Alert
              className="mt-4"
              title="Status pembatalan belum dapat diperiksa"
              tone="warning"
            >
              <p>
                Data untuk memeriksa pembatalan belum dapat dimuat.
                Tidak ada perubahan stok yang dilakukan.
              </p>
            </Alert>
          ) : !preview.eligible ? (
            <Alert
              className="mt-4"
              title="Tidak dapat dibatalkan"
              tone="warning"
            >
              <p>
                {preview.blockers
                  .map((blocker) =>
                    blockerMessage(
                      blocker.code,
                      blocker.message,
                    ),
                  )
                  .filter(Boolean)
                  .join(" ") ||
                  "Transaksi ini belum memenuhi syarat untuk dibatalkan."}
              </p>
            </Alert>
          ) : null}
        </section>

        <details className="mt-6 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5">
          <summary className="cursor-pointer font-semibold text-ui-text">Detail Teknis</summary>
          <dl className="mt-4 grid gap-3 text-sm sm:grid-cols-2">
            <div><dt className="text-ui-text-muted">ID transaksi</dt><dd className="ui-code mt-1 break-all text-ui-text">{detail.transactionId}</dd></div>
            <div><dt className="text-ui-text-muted">ID korelasi</dt><dd className="ui-code mt-1 break-all text-ui-text">{firstRow.correlation_id}</dd></div>
            <div><dt className="text-ui-text-muted">Kode jenis</dt><dd className="ui-code mt-1 text-ui-text">{firstRow.transaction_type_code}</dd></div>
            <div><dt className="text-ui-text-muted">ID pelaku / proses</dt><dd className="ui-code mt-1 break-all text-ui-text">{firstRow.actor_user_id ?? firstRow.process_name ?? "-"}</dd></div>
          </dl>
        </details>
      </div>
    </AppShell>
  );
}
