import {
  Suspense,
} from "react";
import Link from "next/link";

import {
  AppShell,
} from "@/app/app-shell/app-shell";
import {
  PageHeader,
} from "@/app/app-shell/page-header";
import { LedgerFilterControls } from "@/app/ledger/ledger-filter-controls";

import {
  Alert,
  EmptyState,
  StatusBadge,
} from "@/components/ui";
import {
  requireAdminSession,
} from "@/lib/auth";
import {
  getLedgerExplorerPage,
  type LedgerExplorerFilters,
  type LedgerExplorerPage,
  type LedgerExplorerRow,
} from "@/lib/supabase-rest";

export const dynamic = "force-dynamic";

type SearchParams = Record<string, string | string[] | undefined>;

const numberFormatter = new Intl.NumberFormat("id-ID");
const dateFormatter = new Intl.DateTimeFormat("id-ID", {
  timeZone: "Asia/Jakarta",
  dateStyle: "medium",
  timeStyle: "short",
});

function first(value: SearchParams[string]) {
  return Array.isArray(value) ? value[0] : value;
}

function text(params: SearchParams, name: string) {
  return first(params[name])?.trim() ?? "";
}

function isLedgerCursor(value: string) {
  return /^\d+$/.test(value) && BigInt(value) > BigInt(0);
}

function paginationContext(params: SearchParams) {
  const value = text(params, "page");
  const parsedPage = /^[1-9]\d*$/.test(value) ? Number(value) : 1;
  const page = Number.isSafeInteger(parsedPage) ? parsedPage : 1;
  const cursor = text(params, "cursor");

  if (page === 1 || !isLedgerCursor(cursor)) {
    return { cursor: undefined, direction: "next" as const, page: 1 };
  }

  return {
    cursor,
    direction: text(params, "direction") === "previous" ? "previous" as const : "next" as const,
    page,
  };
}

function ledgerFilters(params: SearchParams): LedgerExplorerFilters {
  const pagination = paginationContext(params);
  const quantityDirection = text(params, "quantityDirection");
  const reversalState = text(params, "reversalState");

  return {
    occurredFrom: text(params, "occurredFrom") || undefined,
    occurredTo: text(params, "occurredTo") || undefined,
    recordedFrom: text(params, "recordedFrom") || undefined,
    recordedTo: text(params, "recordedTo") || undefined,
    productId: text(params, "productId") || undefined,
    productSku: text(params, "productSku") || undefined,
    batchId: text(params, "batchId") || undefined,
    batchCode: text(params, "batchCode") || undefined,
    transactionType: text(params, "transactionType") || undefined,
    reason: text(params, "reason") || undefined,
    channel: text(params, "channel") || undefined,
    sourceType: text(params, "sourceType") || undefined,
    sourceRef: text(params, "sourceRef") || undefined,
    actorProcess: text(params, "actorProcess") || undefined,
    bucket: text(params, "bucket") || undefined,
    quantityDirection:
      quantityDirection === "IN" || quantityDirection === "OUT"
        ? quantityDirection
        : undefined,
    reversalState:
      reversalState === "NOT_REVERSED" ||
      reversalState === "PARTIALLY_REVERSED" ||
      reversalState === "FULLY_REVERSED" ||
      reversalState === "REVERSAL"
        ? reversalState
        : undefined,
    cursor: pagination.cursor,
    direction: pagination.direction,
    pageSize: 20,
  };
}

function formatDate(value: string | null) {
  if (!value) return "-";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "-" : dateFormatter.format(date);
}

function signedQuantity(value: number) {
  return `${value > 0 ? "+" : ""}${numberFormatter.format(value)} unit`;
}

function transactionLabel(code: string) {
  if (code === "INITIAL_BALANCE") return "Saldo Awal";
  if (code === "RECEIPT") return "Barang Masuk";
  if (code === "MARKETPLACE_OUTBOUND" || code === "OUTBOUND_MARKETPLACE") {
    return "Barang Keluar";
  }
  if (code === "MANUAL_OUTBOUND" || code === "OUTBOUND_MANUAL") {
    return "Barang Keluar";
  }
  if (code.startsWith("RETURN")) return "Retur";
  if (code === "DISPOSAL_DAMAGED") return "Barang Rusak";
  if (code === "DISPOSAL_EXPIRED") return "Barang Kedaluwarsa";
  if (code.startsWith("DISPOSAL")) return "Barang Rusak / Kedaluwarsa";
  if (code === "STOCKTAKE_ADJUSTMENT") return "Penyesuaian Hasil Hitung";
  if (code === "REVERSAL") return "Pembatalan Transaksi";
  return "Perubahan Stok";
}

function reversalLabel(state: LedgerExplorerRow["reversal_state"]) {
  if (state === "REVERSAL") return "Transaksi pembatalan";
  if (state === "FULLY_REVERSED") return "Sudah dibatalkan";
  if (state === "PARTIALLY_REVERSED") return "Sebagian dibatalkan";
  return "Belum dibatalkan";
}

function codeLabel(value: string) {
  return value
    .toLowerCase()
    .split("_")
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function queryFor(
  params: SearchParams,
  cursor: string | null,
  direction: "next" | "previous",
  page: number,
) {
  const query = new URLSearchParams();
  const names = [
    "occurredFrom", "occurredTo", "recordedFrom", "recordedTo", "productId",
    "productSku", "batchId", "batchCode", "transactionType", "reason", "channel",
    "sourceType", "sourceRef", "actorProcess", "bucket", "quantityDirection",
    "reversalState",
  ];

  for (const name of names) {
    const value = text(params, name);
    if (value) query.set(name, value);
  }

  if (cursor) {
    query.set("cursor", cursor);
    query.set("direction", direction);
  }
  query.set("page", String(page));

  const encoded = query.toString();
  return encoded ? `/ledger?${encoded}` : "/ledger";
}

function detailHref(row: LedgerExplorerRow, params: SearchParams) {
  const pagination = paginationContext(params);
  const context = new URL(queryFor(params, pagination.cursor ?? null, pagination.direction, pagination.page), "http://ledger.local");
  return `/ledger/${row.transaction_id}${context.search}`;
}

function LedgerCards({ rows, params }: { rows: LedgerExplorerRow[]; params: SearchParams }) {
  return <div className="grid gap-3 md:hidden">{rows.map((row) => <article className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4" key={row.ledger_entry_id}><div className="flex items-start justify-between gap-3"><div><p className="text-sm font-semibold text-ui-text">{transactionLabel(row.transaction_type_code)}</p><p className="mt-1 text-xs text-ui-text-muted">{row.product_sku_snapshot} · {row.batch_code_snapshot}</p></div><p className={row.quantity_delta >= 0 ? "ui-number text-sm font-semibold text-ui-primary" : "ui-number text-sm font-semibold text-ui-danger"}>{signedQuantity(row.quantity_delta)}</p></div><div className="mt-3 flex flex-wrap items-center gap-2"><StatusBadge tone={row.reversal_state === "NOT_REVERSED" ? "neutral" : "warning"}>{reversalLabel(row.reversal_state)}</StatusBadge><span className="text-xs text-ui-text-muted">{formatDate(row.occurred_at)}</span></div><Link className="mt-4 inline-flex min-h-[var(--ui-control-height)] items-center text-sm font-semibold text-ui-primary hover:underline" href={detailHref(row, params)}>Lihat Detail</Link></article>)}</div>;
}

function LedgerTable({ rows, params }: { rows: LedgerExplorerRow[]; params: SearchParams }) {
  return <div className="hidden overflow-hidden md:block" data-testid="ledger-table"><table className="w-full text-left text-sm"><thead className="border-b border-ui-border bg-ui-surface-subtle text-xs font-semibold text-ui-text-muted"><tr><th className="px-4 py-3">Perubahan</th><th className="px-4 py-3">Produk / SKU</th><th className="px-4 py-3">Kode Batch</th><th className="px-4 py-3 text-right">Jumlah</th><th className="px-4 py-3">Waktu kejadian</th><th className="px-4 py-3">Waktu dicatat</th><th className="px-4 py-3">Status</th><th className="px-4 py-3"></th></tr></thead><tbody>{rows.map((row) => <tr className="border-b border-ui-border last:border-0" key={row.ledger_entry_id}><td className="px-4 py-4"><p className="font-semibold text-ui-text">{transactionLabel(row.transaction_type_code)}</p><p className="mt-1 text-xs text-ui-text-muted">{codeLabel(row.reason_code_snapshot)} · {codeLabel(row.channel_code_snapshot)}</p></td><td className="px-4 py-4 font-medium text-ui-text">{row.product_sku_snapshot}</td><td className="px-4 py-4 text-ui-text">{row.batch_code_snapshot}</td><td className={row.quantity_delta >= 0 ? "ui-number px-4 py-4 text-right font-semibold text-ui-primary" : "ui-number px-4 py-4 text-right font-semibold text-ui-danger"}>{signedQuantity(row.quantity_delta)}</td><td className="whitespace-nowrap px-4 py-4 text-ui-text-muted">{formatDate(row.occurred_at)}</td><td className="whitespace-nowrap px-4 py-4 text-ui-text-muted">{formatDate(row.recorded_at)}</td><td className="px-4 py-4"><StatusBadge tone={row.reversal_state === "NOT_REVERSED" ? "neutral" : "warning"}>{reversalLabel(row.reversal_state)}</StatusBadge></td><td className="px-4 py-4"><Link className="inline-flex min-h-[var(--ui-control-height)] items-center text-sm font-semibold text-ui-primary hover:underline" href={detailHref(row, params)}>Lihat Detail</Link></td></tr>)}</tbody></table></div>;
}

function Pagination({ result, params, page }: { result: LedgerExplorerPage; params: SearchParams; page: number }) {
  const previousPage = Math.max(1, page - 1);
  const nextPage = page + 1;
  const controlClass = "inline-flex size-11 shrink-0 items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-border text-sm font-semibold text-ui-text hover:bg-ui-surface-subtle";
  const activeClass = "inline-flex size-11 shrink-0 items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface-subtle text-sm font-semibold text-ui-text";
  const disabledClass = "inline-flex size-11 shrink-0 cursor-not-allowed items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-border text-sm font-semibold text-ui-text-muted opacity-50";
  const hasPrevious = result.hasPreviousPage && Boolean(result.previousCursor);
  const hasNext = result.hasNextPage && Boolean(result.nextCursor);
  const previousHref = hasPrevious
    ? previousPage === 1
      ? queryFor(params, null, "previous", previousPage)
      : queryFor(params, result.previousCursor, "previous", previousPage)
    : "";
  const nextHref = hasNext ? queryFor(params, result.nextCursor, "next", nextPage) : "";

  return <div className="flex flex-wrap items-center justify-between gap-3 border-t border-ui-border px-4 py-4"><p className="text-sm text-ui-text-muted">{result.pageSize} perubahan per halaman</p><nav aria-label="Navigasi halaman riwayat stok" className="flex shrink-0 items-center gap-1" data-testid="ledger-pagination">{hasPrevious ? <Link aria-label="Halaman sebelumnya" className={controlClass} href={previousHref}>‹</Link> : <span aria-disabled="true" aria-label="Halaman sebelumnya" className={disabledClass}>‹</span>}{hasPrevious ? <Link aria-label={`Halaman ${previousPage}`} className={controlClass} href={previousHref}>{previousPage}</Link> : null}<span aria-current="page" className={activeClass}>{page}</span>{hasNext ? <Link aria-label={`Halaman ${nextPage}`} className={controlClass} href={nextHref}>{nextPage}</Link> : null}{hasNext ? <Link aria-label="Halaman berikutnya" className={controlClass} href={nextHref}>›</Link> : <span aria-disabled="true" aria-label="Halaman berikutnya" className={disabledClass}>›</span>}</nav></div>;
}

const editableLedgerFilterNames = [
  "occurredFrom",
  "occurredTo",
  "recordedFrom",
  "recordedTo",
  "productSku",
  "batchCode",
  "transactionType",
  "reason",
  "channel",
  "sourceType",
  "sourceRef",
  "actorProcess",
  "bucket",
  "quantityDirection",
  "reversalState",
] as const;

function hasEditableLedgerFilter(
  params: SearchParams,
) {
  return editableLedgerFilterNames.some(
    (name) => Boolean(text(params, name)),
  );
}

function hasLedgerContext(
  params: SearchParams,
) {
  return Boolean(
    text(params, "productId") ||
      text(params, "batchId"),
  );
}

function ledgerContextHref(
  params: SearchParams,
) {
  const query = new URLSearchParams();

  for (
    const name of [
      "productId",
      "batchId",
    ] as const
  ) {
    const value = text(params, name);

    if (value) {
      query.set(name, value);
    }
  }

  const encoded = query.toString();

  return encoded
    ? `/ledger?${encoded}`
    : "/ledger";
}

async function LedgerResults({ params }: { params: SearchParams }) {
  const result = await getLedgerExplorerPage(ledgerFilters(params)).catch(() => null);
  const { page } = paginationContext(params);
  if (!result) return <Alert className="mt-6" title="Riwayat stok belum dapat dimuat" tone="danger"><p>Data riwayat stok tidak dapat dimuat. Coba muat ulang halaman ini.</p><Link className="mt-3 inline-flex min-h-[var(--ui-control-height)] items-center rounded-[var(--ui-radius-md)] border border-ui-danger px-4 font-semibold" href={queryFor(params, null, "next", page)}>Coba Lagi</Link></Alert>;
  if (result.rows.length === 0) {
    const hasEditableFilter =
      hasEditableLedgerFilter(params);
    const hasContext =
      hasLedgerContext(params);

    if (hasEditableFilter) {
      return (
        <EmptyState
          action={
            <Link
              className="inline-flex min-h-[var(--ui-control-height)] items-center rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary hover:bg-ui-primary-hover"
              href={ledgerContextHref(params)}
            >
              Hapus Filter
            </Link>
          }
          className="mt-6"
          description="Tidak ada perubahan stok yang cocok dengan filter saat ini."
          title="Tidak ada riwayat yang cocok"
        />
      );
    }

    if (hasContext) {
      return (
        <EmptyState
          action={
            <Link
              className="inline-flex min-h-[var(--ui-control-height)] items-center rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary hover:bg-ui-primary-hover"
              href="/ledger"
            >
              Lihat semua riwayat
            </Link>
          }
          className="mt-6"
          description="Belum ada perubahan stok yang cocok dengan produk atau batch yang sedang dibuka."
          title="Belum ada riwayat untuk konteks ini"
        />
      );
    }

    return (
      <EmptyState
        className="mt-6"
        description="Perubahan stok akan muncul di sini setelah transaksi pertama tercatat."
        title="Belum ada perubahan stok"
      />
    );
  }
  return <section className="mt-6 overflow-hidden rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface shadow-[var(--ui-shadow-sm)]"><LedgerCards params={params} rows={result.rows} /><LedgerTable params={params} rows={result.rows} /><Pagination page={page} params={params} result={result} /></section>;
}

function LedgerLoading() {
  return <section aria-live="polite" className="mt-6 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-6"><p className="text-sm text-ui-text-muted">Memuat riwayat stok</p><div className="mt-4 h-56 animate-pulse rounded-[var(--ui-radius-md)] bg-ui-surface-subtle motion-reduce:animate-none" /></section>;
}

export default async function LedgerPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const [session, params] = await Promise.all([requireAdminSession(), searchParams]);
  return <AppShell profile={session.profile}><div className="mx-auto w-full max-w-[1440px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8"><PageHeader description="Telusuri perubahan barang tanpa mengubah riwayat yang sudah tercatat." title="Riwayat Stok" /><p className="mt-4 text-sm text-ui-text-muted">Transaksi yang sudah dicatat tidak dapat diubah atau dihapus. Pembatalan transaksi berbeda dari Penyesuaian Hasil Hitung Stok.</p><LedgerFilterControls /><Suspense fallback={<LedgerLoading />}><LedgerResults params={params} /></Suspense></div></AppShell>;
}
