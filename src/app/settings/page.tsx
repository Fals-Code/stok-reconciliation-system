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