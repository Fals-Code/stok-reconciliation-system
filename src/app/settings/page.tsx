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

export default async function SettingsPage() {
  const session =
    await requireAdminSession();

  const {
    profile,
  } = session;

  return (
    <AppShell profile={profile}>
      <div className="mx-auto w-full max-w-[960px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        <PageHeader
          description="Informasi akun dan organisasi yang sedang digunakan."
          eyebrow="Pengaturan"
          title="Pengaturan"
        />

        <section className="mt-6 overflow-hidden rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface shadow-[var(--ui-shadow-sm)]">
          <div className="border-b border-ui-border px-5 py-4">
            <h2 className="text-base font-semibold text-ui-text">
              Akun Admin
            </h2>
          </div>

          <dl>
            <div className="grid gap-1 border-b border-ui-border px-5 py-4 sm:grid-cols-[180px_minmax(0,1fr)]">
              <dt className="text-sm text-ui-text-muted">
                Nama
              </dt>

              <dd className="text-sm font-medium text-ui-text">
                {
                  profile.display_name
                }
              </dd>
            </div>

            <div className="grid gap-1 border-b border-ui-border px-5 py-4 sm:grid-cols-[180px_minmax(0,1fr)]">
              <dt className="text-sm text-ui-text-muted">
                Akses
              </dt>

              <dd>
                <StatusBadge tone="selected">
                  Admin
                </StatusBadge>
              </dd>
            </div>

            <div className="grid gap-1 border-b border-ui-border px-5 py-4 sm:grid-cols-[180px_minmax(0,1fr)]">
              <dt className="text-sm text-ui-text-muted">
                Kode pegawai
              </dt>

              <dd className="text-sm text-ui-text">
                {profile.employee_code ??
                  "Tidak tersedia"}
              </dd>
            </div>

            <div className="grid gap-1 border-b border-ui-border px-5 py-4 sm:grid-cols-[180px_minmax(0,1fr)]">
              <dt className="text-sm text-ui-text-muted">
                Organisasi
              </dt>

              <dd>
                <p className="text-sm font-medium text-ui-text">
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

            <div className="grid gap-1 px-5 py-4 sm:grid-cols-[180px_minmax(0,1fr)]">
              <dt className="text-sm text-ui-text-muted">
                Zona waktu
              </dt>

              <dd className="text-sm text-ui-text">
                {profile.timezone}
              </dd>
            </div>
          </dl>
        </section>

        <section
          aria-labelledby="administrative-settings-heading"
          className="mt-6 overflow-hidden rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface shadow-[var(--ui-shadow-sm)]"
        >
          <div className="border-b border-ui-border px-5 py-4">
            <h2
              className="text-base font-semibold text-ui-text"
              id="administrative-settings-heading"
            >
              Kebutuhan Administratif
            </h2>
            <p className="mt-1 text-sm leading-6 text-ui-text-muted">
              Setup dan pengelolaan khusus Admin yang tidak termasuk pekerjaan gudang harian.
            </p>
          </div>

          <div className="divide-y divide-ui-border">
            <div className="px-5 py-4">
              <p className="text-xs font-semibold uppercase tracking-wide text-ui-text-muted">
                Stok awal
              </p>
              <Link
                className="mt-3 flex min-h-[var(--ui-control-height)] items-center justify-between gap-4 rounded-[var(--ui-radius-md)] p-3 hover:bg-ui-surface-subtle"
                href="/opening-balances"
              >
                <span>
                  <span className="block text-sm font-semibold text-ui-text">
                    Setup Stok Awal
                  </span>
                  <span className="mt-1 block text-sm leading-6 text-ui-text-muted">
                    Siapkan basis stok pertama sebelum kegiatan gudang berjalan.
                  </span>
                </span>
                <span aria-hidden="true" className="text-ui-primary">→</span>
              </Link>
            </div>

            <div className="px-5 py-4">
              <p className="text-xs font-semibold uppercase tracking-wide text-ui-text-muted">
                Marketplace
              </p>
              <div className="mt-3 grid gap-2">
                <Link
                  className="flex min-h-[var(--ui-control-height)] items-center justify-between gap-4 rounded-[var(--ui-radius-md)] p-3 hover:bg-ui-surface-subtle"
                  href="/marketplace/listings"
                >
                  <span>
                    <span className="block text-sm font-semibold text-ui-text">
                      Mapping Produk Marketplace
                    </span>
                    <span className="mt-1 block text-sm leading-6 text-ui-text-muted">
                      Hubungkan produk marketplace dengan produk dan isi paket yang benar.
                    </span>
                  </span>
                  <span aria-hidden="true" className="text-ui-primary">→</span>
                </Link>

                <Link
                  className="flex min-h-[var(--ui-control-height)] items-center justify-between gap-4 rounded-[var(--ui-radius-md)] p-3 hover:bg-ui-surface-subtle"
                  href="/marketplace/import"
                >
                  <span>
                    <span className="block text-sm font-semibold text-ui-text">
                      Import Pesanan
                    </span>
                    <span className="mt-1 block text-sm leading-6 text-ui-text-muted">
                      Masukkan file pesanan marketplace melalui preview dan validasi.
                    </span>
                  </span>
                  <span aria-hidden="true" className="text-ui-primary">→</span>
                </Link>

                <Link
                  className="flex min-h-[var(--ui-control-height)] items-center justify-between gap-4 rounded-[var(--ui-radius-md)] p-3 hover:bg-ui-surface-subtle"
                  href="/marketplace/simulator"
                >
                  <span>
                    <span className="block text-sm font-semibold text-ui-text">
                      Simulator Pesanan
                    </span>
                    <span className="mt-1 block text-sm leading-6 text-ui-text-muted">
                      Uji normalized event, reservasi, dan shipment untuk demo atau verifikasi Admin.
                    </span>
                  </span>
                  <span aria-hidden="true" className="text-ui-primary">→</span>
                </Link>
              </div>
            </div>

            <div className="px-5 py-4">
              <p className="text-xs font-semibold uppercase tracking-wide text-ui-text-muted">
                Status sistem
              </p>
              <Link
                className="mt-3 flex min-h-[var(--ui-control-height)] items-center justify-between gap-4 rounded-[var(--ui-radius-md)] p-3 hover:bg-ui-surface-subtle"
                href="/notifications/operations"
              >
                <span>
                  <span className="block text-sm font-semibold text-ui-text">
                    Status &amp; Diagnostik Sistem
                  </span>
                  <span className="mt-1 block text-sm leading-6 text-ui-text-muted">
                    Periksa pengiriman notifikasi dan tangani kegagalan yang memerlukan Admin.
                  </span>
                </span>
                <span aria-hidden="true" className="text-ui-primary">→</span>
              </Link>
            </div>
          </div>
        </section>

        <section className="mt-6 rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-5 shadow-[var(--ui-shadow-sm)]">
          <h2 className="text-base font-semibold text-ui-text">
            Sesi
          </h2>

          <p className="mt-1 text-sm leading-6 text-ui-text-muted">
            Keluar dari perangkat ini
            setelah pekerjaan selesai.
          </p>

          <form
            action={logoutAction}
            className="mt-4"
          >
            <Button
              type="submit"
              variant="secondary"
            >
              Keluar dari aplikasi
            </Button>
          </form>
        </section>
      </div>
    </AppShell>
  );
}