import {
  redirect,
} from "next/navigation";

import {
  loginAction,
} from "@/app/auth-actions";
import {
  LoginNotice,
} from "@/app/login/login-notice";
import {
  PasswordInput,
} from "@/app/login/password-input";
import {
  Button,
  Field,
  Input,
} from "@/components/ui";
import {
  getAdminSession,
} from "@/lib/auth";
import {
  safeInternalRoute,
} from "@/lib/safe-internal-route";

export const dynamic =
  "force-dynamic";

type LoginSearchParams = {
  error?:
    | string
    | string[];
  message?:
    | string
    | string[];
  returnTo?:
    | string
    | string[];
};

function firstValue(
  value:
    | string
    | string[]
    | undefined,
) {
  return Array.isArray(value)
    ? value[0]
    : value;
}

export default async function LoginPage({
  searchParams,
}: {
  searchParams:
    Promise<LoginSearchParams>;
}) {
  const params =
    await searchParams;

  const returnTo = safeInternalRoute(
    firstValue(params.returnTo),
    "/",
  );

  const session =
    await getAdminSession();

  if (session) {
    redirect(returnTo);
  }

  const errorCode =
    firstValue(
      params.error,
    );

  const messageCode =
    firstValue(
      params.message,
    );

  const emailError =
    errorCode ===
    "EMAIL_REQUIRED"
      ? "Email wajib diisi."
      : errorCode ===
          "EMAIL_FORMAT"
        ? "Format email belum benar."
        : undefined;

  const passwordError =
    errorCode ===
    "PASSWORD_REQUIRED"
      ? "Password wajib diisi."
      : undefined;

  const credentialError =
    errorCode ===
    "CREDENTIALS_INVALID";

  const adminInactive =
    errorCode ===
    "ADMIN_INACTIVE";

  const authUnavailable =
    errorCode ===
    "AUTH_UNAVAILABLE";

  const sessionRequired =
    errorCode ===
      "SESSION_REQUIRED" ||
    errorCode ===
      "Sesi Admin diperlukan.";

  const signedOut =
    messageCode ===
      "SIGNED_OUT" ||
    messageCode ===
      "Sesi Admin telah diakhiri.";

  return (
    <main
      className="relative flex min-h-screen items-center justify-center overflow-hidden bg-ui-canvas px-4 py-8 sm:px-6"
      data-login-layout="operator-login"
    >
      <div
        aria-hidden="true"
        className="pointer-events-none absolute inset-x-0 top-0 h-48 bg-gradient-to-b from-ui-primary-subtle/60 to-transparent"
      />

      <section
        aria-labelledby="login-title"
        className="relative w-full max-w-[430px]"
        data-login-card="admin-auth"
      >
        <div className="rounded-[16px] border border-ui-border bg-ui-surface px-6 py-7 shadow-[var(--ui-shadow-md)] sm:px-8 sm:py-8">
          <header>
            <div className="flex items-center gap-3">
              <div
                aria-hidden="true"
                className="flex h-11 w-11 shrink-0 items-center justify-center rounded-[12px] bg-ui-primary text-ui-text-on-primary shadow-[var(--ui-shadow-sm)]"
              >
                <svg
                  className="h-5 w-5"
                  fill="none"
                  focusable="false"
                  viewBox="0 0 24 24"
                >
                  <path
                    d="m4 7 8-4 8 4-8 4-8-4Z"
                    stroke="currentColor"
                    strokeLinejoin="round"
                    strokeWidth="1.8"
                  />

                  <path
                    d="M4 7v10l8 4 8-4V7M12 11v10"
                    stroke="currentColor"
                    strokeLinejoin="round"
                    strokeWidth="1.8"
                  />
                </svg>
              </div>

              <div>
                <p className="text-sm font-semibold leading-5 text-ui-text">
                  Sistem Rekonsiliasi Stok
                </p>

                <p className="mt-0.5 text-xs text-ui-text-muted">
                  Workspace Admin Gudang
                </p>
              </div>
            </div>

            <div className="mt-7">
              <h1
                className="text-[1.75rem] font-semibold tracking-[-0.025em] text-ui-text"
                id="login-title"
              >
                Masuk
              </h1>

              <p className="mt-2 text-sm leading-6 text-ui-text-muted">
                Masuk untuk melanjutkan
                pekerjaan gudang.
              </p>
            </div>
          </header>

          {sessionRequired ? (
            <LoginNotice
              dismissAfterMs={3500}
              title="Silakan masuk"
              tone="info"
            >
              Sesi diperlukan untuk
              membuka aplikasi.
            </LoginNotice>
          ) : null}

          {signedOut ? (
            <LoginNotice
              dismissAfterMs={3500}
              title="Sesi telah berakhir"
              tone="success"
            >
              Anda sudah keluar dari
              aplikasi.
            </LoginNotice>
          ) : null}

          {credentialError ? (
            <LoginNotice
              title="Login belum berhasil"
              tone="danger"
            >
              Email atau password tidak
              cocok. Periksa kembali lalu
              coba lagi.
            </LoginNotice>
          ) : null}

          {adminInactive ? (
            <LoginNotice
              title="Akses Admin tidak aktif"
              tone="danger"
            >
              Akun berhasil dikenali,
              tetapi tidak memiliki akses
              Admin aktif. Hubungi
              pengelola akses.
            </LoginNotice>
          ) : null}

          {authUnavailable ? (
            <LoginNotice
              title="Login belum dapat diproses"
              tone="danger"
            >
              Layanan autentikasi sedang
              tidak tersedia. Coba
              beberapa saat lagi.
            </LoginNotice>
          ) : null}

          <form
            action={loginAction}
            aria-label="Masuk ke Sistem Rekonsiliasi Stok"
            className="mt-6 grid gap-[18px]"
          >
            {returnTo !== "/" ? (
              <input name="returnTo" type="hidden" value={returnTo} />
            ) : null}

            <Field
              error={emailError}
              id="login-email"
              label="Email"
            >
              {(fieldProps) => (
                <Input
                  {...fieldProps}
                  autoComplete="email"
                  autoFocus
                  className="h-12"
                  inputMode="email"
                  name="email"
                  placeholder="nama@perusahaan.com"
                  required
                  type="email"
                />
              )}
            </Field>

            <Field
              error={passwordError}
              id="login-password"
              label="Password"
            >
              {(fieldProps) => (
                <PasswordInput
                  {...fieldProps}
                  autoComplete="current-password"
                  className="h-12"
                  name="password"
                  placeholder="Masukkan password"
                  required
                />
              )}
            </Field>

            <Button
              className="mt-1 h-12 w-full text-[15px]"
              type="submit"
            >
              Masuk
            </Button>
          </form>

          <div className="mt-6 border-t border-ui-border pt-5">
            <p className="text-center text-xs leading-5 text-ui-text-muted">
              Akses hanya untuk akun
              Admin aktif.
            </p>
          </div>
        </div>
      </section>
    </main>
  );
}
