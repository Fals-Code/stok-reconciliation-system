import { redirect } from "next/navigation";
import { loginAction } from "@/app/auth-actions";
import { getAdminSession } from "@/lib/auth";

export const dynamic = "force-dynamic";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string; message?: string }>;
}) {
  const session = await getAdminSession();

  if (session) {
    redirect("/");
  }

  const feedback = await searchParams;

  return (
    <main className="flex min-h-screen items-center justify-center bg-slate-950 px-5 py-12 text-slate-100">
      <section className="w-full max-w-md rounded-3xl border border-white/10 bg-white/[0.035] p-7 shadow-2xl shadow-black/30 sm:p-9">
        <div className="mb-8">
          <p className="font-mono text-xs uppercase tracking-[0.22em] text-emerald-300">
            GlowLab Inventory
          </p>
          <h1 className="mt-3 text-3xl font-semibold tracking-tight text-white">
            Masuk sebagai Admin.
          </h1>
          <p className="mt-3 text-sm leading-6 text-slate-400">
            Gunakan akun Admin yang terhubung ke organisasi aktif untuk mengakses dashboard stok.
          </p>
        </div>

        {feedback.error ? (
          <div className="mb-5 rounded-2xl border border-rose-400/20 bg-rose-400/10 px-4 py-3 text-sm text-rose-200">
            {feedback.error}
          </div>
        ) : null}

        {feedback.message ? (
          <div className="mb-5 rounded-2xl border border-emerald-400/20 bg-emerald-400/10 px-4 py-3 text-sm text-emerald-200">
            {feedback.message}
          </div>
        ) : null}

        <form action={loginAction} className="space-y-5">
          <label className="field-label">
            Email
            <input
              autoComplete="email"
              name="email"
              type="email"
              required
              placeholder="demo.admin@glowlab.invalid"
            />
          </label>

          <label className="field-label">
            Password
            <input
              autoComplete="current-password"
              name="password"
              type="password"
              required
              placeholder="Masukkan password Admin"
            />
          </label>

          <button className="primary-button w-full justify-center" type="submit">
            Masuk ke dashboard
          </button>
        </form>

        <p className="mt-6 text-xs leading-5 text-slate-500">
          Session disimpan pada cookie server-only. Kredensial tidak dikirim ke komponen browser setelah login.
        </p>
      </section>
    </main>
  );
}
