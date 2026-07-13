import { logoutAction } from "@/app/auth-actions";
import { getAdminSession } from "@/lib/auth";

export default async function AuthControls() {
  const session = await getAdminSession();

  if (!session) {
    return null;
  }

  return (
    <aside className="fixed bottom-5 right-5 z-50 flex items-center gap-3 rounded-2xl border border-white/10 bg-slate-950/90 px-4 py-3 text-sm shadow-2xl shadow-black/30 backdrop-blur">
      <div className="hidden sm:block">
        <p className="font-medium text-white">{session.profile.display_name}</p>
        <p className="mt-0.5 text-xs text-slate-500">
          {session.profile.organization_name} · ADMIN
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
    </aside>
  );
}
