import { randomUUID } from "node:crypto";
import Link from "next/link";

import { AppShell } from "@/app/app-shell/app-shell";
import { PageHeader } from "@/app/app-shell/page-header";
import { requireAdminSession } from "@/lib/auth";
import { getPromoReferences, type PromoReferenceRow } from "@/lib/supabase-rest";
import {
  createPromoReferenceAction,
  updatePromoReferenceAction,
  archivePromoReferenceAction,
  reactivatePromoReferenceAction,
} from "./actions";
import { Alert } from "@/components/ui/alert";
import { EmptyState } from "@/components/ui/empty-state";
import { Button, Input, Textarea, StatusBadge } from "@/components/ui";

export const dynamic = "force-dynamic";

type SearchParams = {
  q?: string;
  status?: string;
  success?: string;
  error?: string;
};

type PromoStatusFilter = "ALL" | "ACTIVE" | "INACTIVE";

function statusFrom(value?: string): PromoStatusFilter {
  const normalized = value?.toUpperCase();
  if (normalized === "ACTIVE" || normalized === "INACTIVE") {
    return normalized;
  }
  return "ALL";
}

function matchesFilters(
  promo: PromoReferenceRow,
  query: string,
  status: PromoStatusFilter,
) {
  const matchesQuery =
    !query ||
    `${promo.name} ${promo.code}`
      .toLowerCase()
      .includes(query.toLowerCase());
  const matchesStatus =
    status === "ALL" ||
    (status === "ACTIVE" ? promo.is_active : !promo.is_active);

  return matchesQuery && matchesStatus;
}

function retryPath(query: string, status: PromoStatusFilter) {
  const parameters = new URLSearchParams();
  if (query) parameters.set("q", query);
  if (status !== "ALL") parameters.set("status", status);
  const search = parameters.toString();
  return search ? `/settings/promos?${search}` : "/settings/promos";
}

export default async function PromoReferencesPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const [session, params] = await Promise.all([
    requireAdminSession(),
    searchParams,
  ]);

  const query = params.q?.trim() ?? "";
  const status = statusFrom(params.status);
  const retryHref = retryPath(query, status);

  let promos: PromoReferenceRow[] = [];
  let fetchError = false;

  try {
    promos = await getPromoReferences();
  } catch {
    fetchError = true;
  }

  const filteredPromos = promos.filter((promo) =>
    matchesFilters(promo, query, status),
  );

  const hasFilters = Boolean(query) || status !== "ALL";

  return (
    <AppShell profile={session.profile}>
      <div className="mx-auto w-full max-w-[1200px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        <div className="mb-6 flex items-center gap-2 text-xs font-semibold text-ui-text-muted">
          <Link className="hover:text-ui-primary" href="/settings">
            Pengaturan
          </Link>
          <span aria-hidden="true">{"\u203A"}</span>
          <span className="text-ui-text">Referensi Promo</span>
        </div>

        <PageHeader
          action={
            <div className="flex flex-wrap items-center gap-2">
              <details className="group relative" id="promo-create-form">
                <summary className="inline-flex min-h-[var(--ui-control-height)] cursor-pointer list-none items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary shadow-[var(--ui-shadow-sm)] hover:bg-ui-primary-hover [&::-webkit-details-marker]:hidden">
                  Tambah Referensi Promo
                </summary>
                <div className="mt-2 w-full rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4 shadow-[var(--ui-shadow-md)] sm:absolute sm:right-0 sm:z-20 sm:w-[28rem]">
                  <h2 className="text-base font-semibold text-ui-text">Tambah Referensi Promo</h2>
                  <p className="mt-1 text-sm leading-6 text-ui-text-muted">
                    Membuat referensi promo yang dapat dipilih saat mencatat pengeluaran stok.
                  </p>
                  <form action={createPromoReferenceAction} className="mt-4 grid gap-4">
                    <input name="intentId" type="hidden" value={randomUUID()} />
                    <label className="grid gap-2 text-sm font-semibold text-ui-text">
                      Kode Promo
                      <Input autoComplete="off" name="code" placeholder="Contoh: PROMO72A" required />
                    </label>
                    <label className="grid gap-2 text-sm font-semibold text-ui-text">
                      Nama Promo
                      <Input autoComplete="off" name="name" placeholder="Contoh: Promo Maklon Agustus" required />
                    </label>
                    <label className="grid gap-2 text-sm font-semibold text-ui-text">
                      Deskripsi
                      <Textarea name="description" placeholder="Opsional. Penjelasan mengenai promo ini." rows={2} />
                    </label>
                    <div className="flex justify-end gap-2">
                      <button
                        className="inline-flex min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary hover:bg-ui-primary-hover"
                        type="submit"
                      >
                        Tambah Promo
                      </button>
                    </div>
                  </form>
                </div>
              </details>
              <Link
                className="inline-flex min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-4 text-sm font-semibold text-ui-text hover:border-ui-border-strong hover:bg-ui-surface-subtle"
                href="/settings"
              >
                Kembali
              </Link>
            </div>
          }
          description="Kelola daftar master rujukan Promo untuk transaksi pengeluaran stok gudang."
          title="Referensi Promo"
        />

        {params.success ? (
          <Alert className="mt-6" title="Aksi berhasil" tone="success">
            <p>{params.success}</p>
          </Alert>
        ) : null}

        {params.error ? (
          <Alert className="mt-6" title="Aksi gagal" tone="danger">
            <p>{params.error}</p>
          </Alert>
        ) : null}

        {fetchError ? (
          <Alert className="mt-6" title="Referensi Promo belum dapat dimuat" tone="danger">
            <p>Koneksi database terganggu. Coba muat ulang halaman.</p>
            <Link
              className="mt-3 inline-flex min-h-[var(--ui-control-height)] items-center rounded-[var(--ui-radius-md)] border border-ui-danger px-4 text-sm font-semibold text-ui-danger hover:bg-ui-danger-subtle"
              href={retryHref}
            >
              Muat Ulang
            </Link>
          </Alert>
        ) : (
          <section className="mt-6">
            <div className="rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4">
              <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
                <form action="/settings/promos" className="flex flex-1 flex-wrap items-center gap-3" method="GET">
                  <div className="min-w-[15rem] flex-1">
                    <Input
                      autoComplete="off"
                      defaultValue={query}
                      name="q"
                      placeholder="Cari kode atau nama promo..."
                    />
                  </div>
                  <div className="w-full sm:w-44">
                    <select
                      className="flex min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3 text-sm font-semibold text-ui-text hover:border-ui-border-strong focus:outline-none"
                      defaultValue={status}
                      name="status"
                    >
                      <option value="ALL">Semua Status</option>
                      <option value="ACTIVE">Aktif</option>
                      <option value="INACTIVE">Tidak Aktif</option>
                    </select>
                  </div>
                  <Button type="submit">Saring</Button>
                  {hasFilters ? (
                    <Link
                      className="inline-flex min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-4 text-sm font-semibold text-ui-text hover:border-ui-border-strong hover:bg-ui-surface-subtle"
                      href="/settings/promos"
                    >
                      Reset
                    </Link>
                  ) : null}
                </form>
              </div>
            </div>

            <div className="mt-6 overflow-hidden rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface">
              {filteredPromos.length > 0 ? (
                <div>
                  <div className="grid grid-cols-[1fr_auto] items-center gap-6 border-b border-ui-border bg-ui-surface-subtle px-5 py-2.5">
                    <p className="text-xs font-semibold text-ui-text-muted">Referensi Promo</p>
                    <p className="text-xs font-semibold text-ui-text-muted">Status</p>
                  </div>
                  <div className="divide-y divide-ui-border">
                    {filteredPromos.map((promo) => (
                      <div
                        className="group grid grid-cols-[1fr_auto] items-center gap-6 px-5 py-4 hover:bg-ui-surface-subtle"
                        key={promo.id}
                      >
                        <div className="min-w-0">
                          <h3 className="text-sm font-semibold text-ui-text">
                            {promo.name}
                          </h3>
                          <p className="ui-code mt-1 text-xs text-ui-text-muted">
                            {promo.code}
                          </p>
                          {promo.description ? (
                            <p className="mt-1 text-sm text-ui-text-muted">
                              {promo.description}
                            </p>
                          ) : null}
                          <div className="mt-3 flex flex-wrap items-center gap-4">
                            <details className="group relative">
                              <summary className="inline-flex cursor-pointer text-xs font-semibold text-ui-primary hover:underline [&::-webkit-details-marker]:hidden">
                                Ubah Data
                              </summary>
                              <div className="mt-2 w-full rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4 shadow-[var(--ui-shadow-md)] sm:absolute sm:left-0 sm:z-20 sm:w-96">
                                <h4 className="text-sm font-semibold text-ui-text">Ubah Referensi Promo</h4>
                                <form action={updatePromoReferenceAction} className="mt-3 grid gap-3">
                                  <input name="intentId" type="hidden" value={randomUUID()} />
                                  <input name="promoId" type="hidden" value={promo.id} />
                                  <input name="rowVersion" type="hidden" value={promo.row_version} />
                                  <label className="grid gap-1.5 text-xs font-semibold text-ui-text">
                                    Kode Promo (Tidak dapat diubah)
                                    <Input defaultValue={promo.code} disabled />
                                  </label>
                                  <label className="grid gap-1.5 text-xs font-semibold text-ui-text">
                                    Nama Promo
                                    <Input autoComplete="off" defaultValue={promo.name} name="name" required />
                                  </label>
                                  <label className="grid gap-1.5 text-xs font-semibold text-ui-text">
                                    Deskripsi
                                    <Textarea defaultValue={promo.description ?? ""} name="description" rows={2} />
                                  </label>
                                  <div className="flex justify-end gap-2">
                                    <button
                                      className="inline-flex min-h-8 items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary px-3 text-xs font-semibold text-ui-text-on-primary hover:bg-ui-primary-hover"
                                      type="submit"
                                    >
                                      Simpan
                                    </button>
                                  </div>
                                </form>
                              </div>
                            </details>

                            {promo.is_active ? (
                              <details className="group relative">
                                <summary className="inline-flex cursor-pointer text-xs font-semibold text-ui-text-muted hover:text-ui-text hover:underline [&::-webkit-details-marker]:hidden">
                                  Nonaktifkan
                                </summary>
                                <div className="mt-2 w-full rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4 shadow-[var(--ui-shadow-md)] sm:absolute sm:left-0 sm:z-20 sm:w-96">
                                  <h4 className="text-sm font-semibold text-ui-text">Nonaktifkan Referensi Promo</h4>
                                  <p className="mt-1 text-xs text-ui-text-muted">
                                    Menonaktifkan promo tidak mengubah transaksi yang sudah tercatat. Promo tidak akan tersedia untuk pencatatan barang keluar baru.
                                  </p>
                                  <form action={archivePromoReferenceAction} className="mt-3 grid gap-3">
                                    <input name="intentId" type="hidden" value={randomUUID()} />
                                    <input name="promoId" type="hidden" value={promo.id} />
                                    <input name="rowVersion" type="hidden" value={promo.row_version} />
                                    <label className="grid gap-1.5 text-xs font-semibold text-ui-text">
                                      Alasan Penonaktifan
                                      <Input autoComplete="off" name="reason" placeholder="Contoh: Masa berlaku berakhir" />
                                    </label>
                                    <label className="flex items-center gap-2 text-xs font-semibold text-ui-text">
                                      <input className="rounded border-ui-border text-ui-primary focus:ring-ui-primary" name="confirmation" required type="checkbox" />
                                      Saya yakin ingin menonaktifkan promo ini.
                                    </label>
                                    <div className="flex justify-end gap-2">
                                      <button
                                        className="inline-flex min-h-8 items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary px-3 text-xs font-semibold text-ui-text-on-primary hover:bg-ui-primary-hover"
                                        type="submit"
                                      >
                                        Nonaktifkan
                                      </button>
                                    </div>
                                  </form>
                                </div>
                              </details>
                            ) : (
                              <details className="group relative">
                                <summary className="inline-flex cursor-pointer text-xs font-semibold text-ui-primary hover:underline [&::-webkit-details-marker]:hidden">
                                  Aktifkan Kembali
                                </summary>
                                <div className="mt-2 w-full rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4 shadow-[var(--ui-shadow-md)] sm:absolute sm:left-0 sm:z-20 sm:w-96">
                                  <h4 className="text-sm font-semibold text-ui-text">Aktifkan Kembali Referensi Promo</h4>
                                  <p className="mt-1 text-xs text-ui-text-muted">
                                    Mengaktifkan kembali promo akan membuatnya tersedia kembali untuk dipilih pada pencatatan barang keluar baru.
                                  </p>
                                  <form action={reactivatePromoReferenceAction} className="mt-3 grid gap-3">
                                    <input name="intentId" type="hidden" value={randomUUID()} />
                                    <input name="promoId" type="hidden" value={promo.id} />
                                    <input name="rowVersion" type="hidden" value={promo.row_version} />
                                    <label className="grid gap-1.5 text-xs font-semibold text-ui-text">
                                      Alasan Reaktivasi
                                      <Input autoComplete="off" name="reason" placeholder="Contoh: Diperpanjang oleh prinsipal" />
                                    </label>
                                    <label className="flex items-center gap-2 text-xs font-semibold text-ui-text">
                                      <input className="rounded border-ui-border text-ui-primary focus:ring-ui-primary" name="confirmation" required type="checkbox" />
                                      Saya yakin ingin mengaktifkan kembali promo ini.
                                    </label>
                                    <div className="flex justify-end gap-2">
                                      <button
                                        className="inline-flex min-h-8 items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary px-3 text-xs font-semibold text-ui-text-on-primary hover:bg-ui-primary-hover"
                                        type="submit"
                                      >
                                        Aktifkan Kembali
                                      </button>
                                    </div>
                                  </form>
                                </div>
                              </details>
                            )}
                          </div>
                        </div>

                        <div className="flex items-center gap-2.5">
                          {promo.is_active ? (
                            <StatusBadge tone="selected">Aktif</StatusBadge>
                          ) : (
                            <StatusBadge>Tidak Aktif</StatusBadge>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              ) : (
                <EmptyState
                  action={
                    hasFilters ? (
                      <Link
                        className="inline-flex min-h-[var(--ui-control-height)] items-center rounded-[var(--ui-radius-md)] border border-ui-border px-4 text-sm font-semibold text-ui-text hover:border-ui-border-strong"
                        href="/settings/promos"
                      >
                        Hapus Filter
                      </Link>
                    ) : undefined
                  }
                  description={
                    hasFilters
                      ? "Ubah kata pencarian atau filter status."
                      : "Belum ada referensi promo yang tercatat untuk organisasi ini."
                  }
                  title={
                    hasFilters
                      ? "Tidak ada promo yang cocok"
                      : "Belum ada promo"
                  }
                />
              )}
            </div>
          </section>
        )}
      </div>
    </AppShell>
  );
}
