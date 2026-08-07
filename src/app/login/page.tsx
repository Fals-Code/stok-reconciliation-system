import { redirect } from "next/navigation";

import { loginAction } from "@/app/auth-actions";
import { PasswordInput } from "@/app/login/password-input";
import {
  Alert,
  Button,
  Field,
  Input,
} from "@/components/ui";
import { getAdminSession } from "@/lib/auth";

export const dynamic = "force-dynamic";

function BrandMark() {
  return (
    <span
      aria-hidden="true"
      className="grid h-10 w-10 place-items-center rounded-[0.8rem] bg-[#123f3a] text-white shadow-[0_10px_24px_rgba(18,63,58,0.18)]"
    >
      <svg
        fill="none"
        height="21"
        viewBox="0 0 21 21"
        width="21"
      >
        <path
          d="M4 5.5H17M4 10.5H17M4 15.5H12.5"
          stroke="currentColor"
          strokeLinecap="round"
          strokeWidth="1.7"
        />
        <circle
          cx="15.5"
          cy="15.5"
          fill="#d9a928"
          r="1.5"
        />
      </svg>
    </span>
  );
}

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{
    error?: string;
    message?: string;
  }>;
}) {
  const session = await getAdminSession();

  if (session) {
    redirect("/");
  }

  const feedback = await searchParams;
  const errorMessage =
    feedback.error ===
    "Sesi Admin diperlukan."
      ? null
      : feedback.error;

  return (
    <main
      className="flex min-h-screen items-center justify-center bg-[#edf3f0] px-4 py-8 text-[#172522] sm:px-6"
      data-login-layout="simple-admin-login"
    >
      <section
        aria-labelledby="login-title"
        className="w-full max-w-[27rem] overflow-hidden rounded-[1rem] border border-[rgba(18,63,58,0.14)] bg-[#fffdf8] shadow-[0_24px_70px_rgba(18,63,58,0.14)]"
        data-login-card="admin-auth"
      >
        <div className="h-1 bg-[#1d6a61]" />

        <div className="px-6 py-7 sm:px-8 sm:py-8">
          <div className="flex items-center gap-3">
            <BrandMark />

            <div>
              <p className="text-sm font-semibold text-[#123f3a]">
                Stok Management
              </p>
              <p className="mt-0.5 text-xs text-[#74807c]">
                Sistem Rekonsiliasi Stok
              </p>
            </div>
          </div>

          <div className="mt-8">
            <h1
              className="text-3xl font-semibold tracking-tight text-[#172522]"
              id="login-title"
            >
              Masuk
            </h1>

            <p className="mt-2 text-sm leading-6 text-[#66736f]">
              Gunakan akun Admin gudang.
            </p>
          </div>

          {errorMessage ? (
            <Alert
              className="mt-5"
              title={errorMessage}
              tone="danger"
            />
          ) : null}

          {feedback.message ? (
            <Alert
              className="mt-5"
              title={feedback.message}
              tone="success"
            />
          ) : null}

          <form
            action={loginAction}
            aria-label="Masuk ke Stok Management"
            className="mt-6 grid gap-5"
          >
            <Field
              id="login-email"
              label="Email"
            >
              {(fieldProps) => (
                <Input
                  {...fieldProps}
                  autoComplete="email"
                  autoFocus
                  inputMode="email"
                  name="email"
                  placeholder="admin@perusahaan.com"
                  required
                  type="email"
                />
              )}
            </Field>

            <Field
              id="login-password"
              label="Password"
            >
              {(fieldProps) => (
                <PasswordInput
                  {...fieldProps}
                  autoComplete="current-password"
                  name="password"
                  placeholder="Masukkan password"
                  required
                />
              )}
            </Field>

            <Button
              className="mt-1 w-full"
              type="submit"
            >
              Masuk
            </Button>
          </form>

          <div className="mt-5 flex items-center gap-2 border-t border-[#d9e2de] pt-4 text-xs text-[#74807c]">
            <span
              aria-hidden="true"
              className="h-2 w-2 rounded-full bg-[#1d6a61]"
            />
            <span>
              Akses terbatas untuk Admin aktif.
            </span>
          </div>
        </div>
      </section>
    </main>
  );
}