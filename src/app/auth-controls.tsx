import { logoutAction } from "@/app/auth-actions";
import { getAdminSession } from "@/lib/auth";

export default async function AuthControls() {
  const session = await getAdminSession();

  if (!session) {
    return null;
  }

  return (
    <details className="group fixed bottom-4 right-4 z-50 max-w-[calc(100vw-2rem)] text-sm">
      <summary className="cursor-pointer list-none rounded-full border border-white/10 bg-slate-950/90 px-4 py-2 font-medium text-slate-200 shadow-2xl shadow-black/30 backdrop-blur transition hover:border-emerald-400/30 hover:text-white">
        Akun Admin
      </summary>

      <div className="absolute bottom-full right-0 mb-2 flex min-w-64 items-center justify-between gap-4 rounded-2xl border border-white/10 bg-slate-950/95 px-4 py-3 shadow-2xl shadow-black/30 backdrop-blur">
        <div>
          <p className="font-medium text-white">{session.profile.display_name}</p>
          <p className="mt-0.5 text-xs text-slate-500">
            {session.profile.organization_name}{" \u00b7 "}ADMIN
          </p>
        </div>

        <form action={logoutAction}>
          <button
            className="rounded-xl border border-white/10 px-3 py-2 text-xs font-medium text-slate-300 transition hover:border-rose-400/30 hover:bg-rose-400/10 hover:text-rose-200"
            type="submit"
          >
            Logout
          </button>
        </form>
      </div>
    </details>
  );
}