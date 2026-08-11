import Link from "next/link";

import { AppShell } from "@/app/app-shell/app-shell";
import { PageHeader } from "@/app/app-shell/page-header";
import { requireAdminSession } from "@/lib/auth";

export default async function LedgerTransactionNotFound() {
  const session = await requireAdminSession();
  return <AppShell profile={session.profile}><div className="mx-auto w-full max-w-[840px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8"><PageHeader title="Transaksi Tidak Ditemukan" /><section className="mt-6 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-6 shadow-[var(--ui-shadow-sm)]"><p className="text-sm leading-6 text-ui-text-muted">Transaksi tidak ditemukan atau tidak dapat diakses.</p><Link className="mt-5 inline-flex min-h-[var(--ui-control-height)] items-center rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary hover:bg-ui-primary-hover" href="/ledger">Kembali ke Riwayat Stok</Link></section></div></AppShell>;
}
