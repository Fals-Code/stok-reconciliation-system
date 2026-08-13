import Link from "next/link";

import {
  AppShell,
} from "@/app/app-shell/app-shell";
import {
  PageHeader,
} from "@/app/app-shell/page-header";
import {
  logoutAction,
} from "@/app/auth-actions";
import {
  Button,
  StatusBadge,
} from "@/components/ui";
import {
  requireAdminSession,
} from "@/lib/auth";

export const dynamic =
  "force-dynamic";

function SettingsChevron() {
  return (
    <svg
      aria-hidden="true"
      className="h-4 w-4"
      fill="none"
      viewBox="0 0 20 20"
    >
      <path
        d="m7.5 5 5 5-5 5"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.6"
      />
    </svg>
  );
}

function SettingsLink({
  href,
  title,
  description,
}: {
  href: string;
  title: string;
  description: string;
}) {
  return (
    <Link
      className="group flex min-h-[4.75rem] items-center justify-between gap-5 px-5 py-4 transition-colors hover:bg-ui-surface-subtle focus-visible:bg-ui-surface-subtle motion-reduce:transition-none sm:px-6"
      href={href}
    >
      <span className="min-w-0">
        <span className="block text-sm font-semibold text-ui-text">
          {title}
        </span>

        <span className="mt-1 block max-w-[42rem] text-sm leading-6 text-ui-text-muted">
          {description}
        </span>
      </span>

      <span
        aria-hidden="true"
        className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-ui-primary transition-transform group-hover:translate-x-0.5 motion-reduce:transform-none motion-reduce:transition-none"
      >
        <SettingsChevron />
      </span>
    </Link>
  );
}

function SettingsGroupLabel({
  children,
}: {
  children: string;
}) {
  return (
    <p className="px-5 pb-1 pt-5 text-[0.7rem] font-semibold uppercase tracking-[0.09em] text-ui-text-muted sm:px-6">
      {children}
    </p>
  );
}

export default async function SettingsPage() {
  const session =
    await requireAdminSession();

  const {
    profile,
  } = session;

  return (
    <AppShell profile={profile}>
      <div className="mx-auto w-full max-w-[1040px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        <PageHeader
          description="Informasi akun dan organisasi yang sedang digunakan."
          eyebrow="Pengaturan"
          title="Pengaturan"
        />

        <section className="mt-6 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface shadow-[var(--ui-shadow-sm)]">
          <div className="px-5 pb-2 pt-5 sm:px-6 sm:pt-6">
            <h2 className="text-base font-semibold text-ui-text">
              Akun Admin
            </h2>

            <p className="mt-1 text-sm leading-6 text-ui-text-muted">
              Identitas akses yang digunakan pada sesi ini.
            </p>
          </div>

          <dl className="grid px-5 pb-5 sm:grid-cols-2 sm:gap-x-10 sm:px-6 sm:pb-6">
            <div className="border-t border-ui-border py-4">
              <dt className="text-xs font-medium text-ui-text-muted">
                Nama
              </dt>

              <dd className="mt-1.5 text-sm font-semibold text-ui-text">
                {
                  profile.display_name
                }
              </dd>
            </div>

            <div className="border-t border-ui-border py-4">
              <dt className="text-xs font-medium text-ui-text-muted">
                Akses
              </dt>

              <dd className="mt-1.5">
                <StatusBadge tone="selected">
                  Admin
                </StatusBadge>
              </dd>
            </div>

            <div className="border-t border-ui-border py-4">
              <dt className="text-xs font-medium text-ui-text-muted">
                Kode pegawai
              </dt>

              <dd className="mt-1.5 text-sm font-medium text-ui-text">
                {profile.employee_code ??
                  "Tidak tersedia"}
              </dd>
            </div>

            <div className="border-t border-ui-border py-4">
              <dt className="text-xs font-medium text-ui-text-muted">
                Zona waktu
              </dt>

              <dd className="mt-1.5 text-sm font-medium text-ui-text">
                {profile.timezone}
              </dd>
            </div>

            <div className="border-t border-ui-border py-4 sm:col-span-2">
              <dt className="text-xs font-medium text-ui-text-muted">
                Organisasi
              </dt>

              <dd className="mt-1.5">
                <p className="text-sm font-semibold text-ui-text">
                  {
                    profile.organization_name
                  }
                </p>

                <p className="ui-code mt-1 text-xs text-ui-text-muted">
                  {
                    profile.organization_code
                  }
                </p>
              </dd>
            </div>
          </dl>
        </section>

        <section
          aria-labelledby="administrative-settings-heading"
          className="mt-6 overflow-hidden rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface shadow-[var(--ui-shadow-sm)]"
        >
          <div className="px-5 pb-5 pt-5 sm:px-6 sm:pt-6">
            <h2
              className="text-base font-semibold text-ui-text"
              id="administrative-settings-heading"
            >
              Kebutuhan Administratif
            </h2>

            <p className="mt-1 max-w-[44rem] text-sm leading-6 text-ui-text-muted">
              Setup dan pengelolaan khusus Admin yang tidak termasuk pekerjaan gudang harian.
            </p>
          </div>

          <div className="border-t border-ui-border">
            <SettingsGroupLabel>
              Stok awal
            </SettingsGroupLabel>

            <SettingsLink
              description="Siapkan basis stok pertama sebelum kegiatan gudang berjalan."
              href="/opening-balances"
              title="Setup Stok Awal"
            />
          </div>

          <div className="border-t border-ui-border">
            <SettingsGroupLabel>
              Marketplace
            </SettingsGroupLabel>

            <div className="divide-y divide-ui-border">
              <SettingsLink
                description="Hubungkan produk marketplace dengan produk dan isi paket yang benar."
                href="/marketplace/listings"
                title="Mapping Produk Marketplace"
              />

              <SettingsLink
                description="Masukkan file pesanan marketplace melalui preview dan validasi."
                href="/marketplace/import"
                title="Import Pesanan"
              />

              <SettingsLink
                description="Uji normalized event, reservasi, dan shipment untuk demo atau verifikasi Admin."
                href="/marketplace/simulator"
                title="Simulator Pesanan"
              />
            </div>
          </div>

          <div className="border-t border-ui-border">
            <SettingsGroupLabel>
              Operasional
            </SettingsGroupLabel>

            <SettingsLink
              description="Kelola referensi Promo yang dapat dipilih saat mencatat barang keluar."
              href="/settings/promos"
              title="Referensi Promo"
            />
          </div>

          <div className="border-t border-ui-border">
            <SettingsGroupLabel>
              Status sistem
            </SettingsGroupLabel>

            <SettingsLink
              description="Periksa pengiriman notifikasi dan tangani kegagalan yang memerlukan Admin."
              href="/notifications/operations"
              title="Status & Diagnostik Sistem"
            />
          </div>
        </section>

        <section
          aria-labelledby="session-heading"
          className="mt-8 border-t border-ui-border pt-6"
        >
          <div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <h2
                className="text-base font-semibold text-ui-text"
                id="session-heading"
              >
                Sesi
              </h2>

              <p className="mt-1 text-sm leading-6 text-ui-text-muted">
                Keluar dari perangkat ini setelah pekerjaan selesai.
              </p>
            </div>

            <form action={logoutAction}>
              <Button
                type="submit"
                variant="secondary"
              >
                Keluar dari aplikasi
              </Button>
            </form>
          </div>
        </section>
      </div>
    </AppShell>
  );
}