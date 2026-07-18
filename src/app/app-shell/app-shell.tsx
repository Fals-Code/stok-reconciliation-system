"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  useEffect,
  useRef,
  useState,
  type ReactNode,
  type RefObject,
} from "react";

import { logoutAction } from "@/app/auth-actions";
import {
  APP_NAV_SECTIONS,
  findActiveNavItem,
  isNavItemActive,
} from "@/app/app-shell/navigation";

type AppShellProfile = {
  displayName: string;
  email: string | null;
  organizationCode: string;
  organizationName: string;
  roleCode: "ADMIN";
};

type AppShellProps = {
  children: ReactNode;
  profile: AppShellProfile;
  appMode: string;
  unreadCount: number;
};

function formatUnreadCount(unreadCount: number) {
  return unreadCount > 99 ? "99+" : unreadCount.toLocaleString("id-ID");
}

function Brand({
  onNavigate,
}: {
  onNavigate?: () => void;
}) {
  return (
    <Link
      className="block border-b border-white/10 px-5 py-5 transition hover:bg-white/[0.025]"
      href="/"
      onClick={onNavigate}
    >
      <p className="font-mono text-xs uppercase tracking-[0.2em] text-emerald-300">
        GlowLab Inventory
      </p>
      <p className="mt-1 text-sm text-slate-400">
        Ledger-first stock control
      </p>
    </Link>
  );
}

function Navigation({
  pathname,
  onNavigate,
  unreadCount,
}: {
  pathname: string;
  onNavigate?: () => void;
  unreadCount: number;
}) {
  return (
    <nav aria-label="Navigasi utama" className="space-y-7 px-3 py-5">
      {APP_NAV_SECTIONS.map((section) => (
        <section key={section.label}>
          <p className="px-3 font-mono text-[0.65rem] uppercase tracking-[0.18em] text-slate-600">
            {section.label}
          </p>

          <div className="mt-2 space-y-1">
            {section.items.map((item) => {
              const active = isNavItemActive(pathname, item.href);

              return (
                <Link
                  key={item.href}
                  aria-current={active ? "page" : undefined}
                  className={[
                    "group flex items-center gap-3 rounded-xl border px-3 py-2.5 transition",
                    active
                      ? "border-emerald-400/20 bg-emerald-400/10 text-white"
                      : "border-transparent text-slate-400 hover:border-white/10 hover:bg-white/[0.035] hover:text-white",
                  ].join(" ")}
                  href={item.href}
                  onClick={onNavigate}
                >
                  <span
                    aria-hidden="true"
                    className={[
                      "flex h-8 w-8 shrink-0 items-center justify-center rounded-lg border font-mono text-[0.65rem] font-semibold",
                      active
                        ? "border-emerald-400/25 bg-emerald-400/15 text-emerald-200"
                        : "border-white/10 bg-white/[0.025] text-slate-500 group-hover:text-slate-300",
                    ].join(" ")}
                  >
                    {item.shortLabel}
                  </span>

                  <span className="min-w-0 flex-1">
                    <span className="flex items-center gap-2 text-sm font-medium">
                      <span>{item.label}</span>
                      {item.href === "/notifications" && unreadCount > 0 ? (
                        <span className="inline-flex min-w-6 items-center justify-center rounded-full bg-rose-400/15 px-1.5 py-0.5 font-mono text-[0.65rem] text-rose-200">
                          {formatUnreadCount(unreadCount)}
                        </span>
                      ) : null}
                    </span>
                    <span className="mt-0.5 block truncate text-xs text-slate-600 group-hover:text-slate-500">
                      {item.description}
                    </span>
                  </span>
                </Link>
              );
            })}
          </div>
        </section>
      ))}
    </nav>
  );
}

function OrganizationSummary({
  profile,
}: {
  profile: AppShellProfile;
}) {
  return (
    <div className="border-t border-white/10 p-4">
      <div className="rounded-xl border border-white/10 bg-white/[0.025] p-3">
        <p className="truncate text-sm font-medium text-slate-200">
          {profile.organizationName}
        </p>
        <p className="mt-1 font-mono text-[0.65rem] uppercase tracking-[0.14em] text-slate-600">
          {profile.organizationCode} · {profile.roleCode}
        </p>
      </div>
    </div>
  );
}

function AccountMenu({
  profile,
  detailsRef,
}: {
  profile: AppShellProfile;
  detailsRef: RefObject<HTMLDetailsElement | null>;
}) {
  return (
    <details ref={detailsRef} className="group relative">
      <summary className="flex cursor-pointer list-none items-center gap-3 rounded-xl border border-white/10 bg-white/[0.025] px-3 py-2 transition hover:border-white/20 hover:bg-white/[0.045]">
        <span
          aria-hidden="true"
          className="flex h-8 w-8 items-center justify-center rounded-full bg-emerald-400/10 text-sm font-semibold text-emerald-200"
        >
          {profile.displayName.slice(0, 1).toUpperCase()}
        </span>

        <span className="hidden min-w-0 text-left md:block">
          <span className="block max-w-40 truncate text-sm font-medium text-slate-200">
            {profile.displayName}
          </span>
          <span className="block max-w-40 truncate text-xs text-slate-500">
            {profile.email ?? profile.roleCode}
          </span>
        </span>

        <span aria-hidden="true" className="text-xs text-slate-500">
          ▾
        </span>
      </summary>

      <div className="absolute right-0 top-full z-50 mt-2 w-72 rounded-2xl border border-white/10 bg-slate-950/98 p-3 shadow-2xl shadow-black/40 backdrop-blur">
        <div className="rounded-xl bg-white/[0.025] p-3">
          <p className="font-medium text-white">{profile.displayName}</p>
          <p className="mt-1 truncate text-xs text-slate-500">
            {profile.email ?? "Email tidak tersedia"}
          </p>
          <p className="mt-2 text-xs text-slate-500">
            {profile.organizationName} · {profile.roleCode}
          </p>
        </div>

        <form action={logoutAction} className="mt-2">
          <button
            className="flex w-full items-center justify-center rounded-xl border border-rose-400/20 bg-rose-400/[0.055] px-3 py-2.5 text-sm font-medium text-rose-200 transition hover:bg-rose-400/10"
            type="submit"
          >
            Keluar dari akun
          </button>
        </form>
      </div>
    </details>
  );
}

export default function AppShell({
  children,
  profile,
  appMode,
  unreadCount,
}: AppShellProps) {
  const pathname = usePathname();
  const [mobileOpen, setMobileOpen] = useState(false);
  const accountMenuRef = useRef<HTMLDetailsElement>(null);
  const activeNavigation = findActiveNavItem(pathname);

  useEffect(() => {
    if (!mobileOpen) {
      return;
    }

    const previousOverflow = document.body.style.overflow;

    function closeOnEscape(event: KeyboardEvent) {
      if (event.key === "Escape") {
        setMobileOpen(false);
      }
    }

    document.body.style.overflow = "hidden";
    window.addEventListener("keydown", closeOnEscape);

    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener("keydown", closeOnEscape);
    };
  }, [mobileOpen]);


  return (
    <div className="flex min-h-screen bg-slate-950 text-slate-100">
      <aside className="sticky top-0 hidden h-screen w-72 shrink-0 flex-col border-r border-white/10 bg-slate-950/92 backdrop-blur lg:flex">
        <Brand />

        <div className="min-h-0 flex-1 overflow-y-auto">
          <Navigation pathname={pathname} unreadCount={unreadCount} />
        </div>

        <OrganizationSummary profile={profile} />
      </aside>

      {mobileOpen ? (
        <>
          <button
            aria-label="Tutup navigasi"
            className="fixed inset-0 z-[55] bg-black/65 backdrop-blur-sm lg:hidden"
            onClick={() => setMobileOpen(false)}
            type="button"
          />

          <aside
            aria-label="Navigasi mobile"
            className="fixed inset-y-0 left-0 z-[60] flex w-[min(21rem,calc(100vw-2rem))] flex-col border-r border-white/10 bg-slate-950 shadow-2xl shadow-black/50 lg:hidden"
            id="mobile-navigation"
          >
            <div className="flex items-center justify-between border-b border-white/10">
              <div className="min-w-0 flex-1">
                <Brand onNavigate={() => setMobileOpen(false)} />
              </div>

              <button
                aria-label="Tutup menu"
                className="mr-3 flex h-10 w-10 items-center justify-center rounded-xl border border-white/10 text-xl text-slate-400 transition hover:bg-white/[0.05] hover:text-white"
                onClick={() => setMobileOpen(false)}
                type="button"
              >
                ×
              </button>
            </div>

            <div className="min-h-0 flex-1 overflow-y-auto">
              <Navigation
                pathname={pathname}
                onNavigate={() => setMobileOpen(false)}
                unreadCount={unreadCount}
              />
            </div>

            <OrganizationSummary profile={profile} />
          </aside>
        </>
      ) : null}

      <div className="min-w-0 flex-1">
        <header className="sticky top-0 z-30 border-b border-white/10 bg-slate-950/90 backdrop-blur">
          <div className="flex min-h-16 items-center gap-3 px-4 py-2 sm:px-5 lg:px-7">
            <button
              aria-controls="mobile-navigation"
              aria-expanded={mobileOpen}
              aria-label="Buka navigasi"
              className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border border-white/10 text-lg text-slate-300 transition hover:bg-white/[0.05] hover:text-white lg:hidden"
              onClick={() => {
                accountMenuRef.current?.removeAttribute("open");
                setMobileOpen(true);
              }}
              type="button"
            >
              ☰
            </button>

            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-semibold text-white">
                {activeNavigation?.item.label ?? "GlowLab Inventory"}
              </p>
              <p className="mt-0.5 truncate text-xs text-slate-500">
                {activeNavigation?.sectionLabel ?? profile.organizationName}
              </p>
            </div>

            <div className="hidden items-center gap-2 xl:flex">
              <Link
                className="rounded-xl border border-white/10 bg-white/[0.025] px-3 py-2 transition hover:border-emerald-400/20 hover:bg-emerald-400/[0.055]"
                href="/reconciliation"
              >
                <span className="block text-xs font-medium text-slate-300">
                  Status rekonsiliasi
                </span>
                <span className="mt-0.5 block text-[0.65rem] text-slate-600">
                  Buka modul
                </span>
              </Link>

              <Link
                aria-label={`Buka Notification Center, ${unreadCount} belum dibaca`}
                className="rounded-xl border border-white/10 bg-white/[0.025] px-3 py-2 transition hover:border-emerald-400/20 hover:bg-emerald-400/[0.055]"
                href="/notifications"
              >
                <span className="block text-xs font-medium text-slate-400">
                  Notifikasi
                </span>
                <span
                  className={[
                    "mt-0.5 block text-[0.65rem]",
                    unreadCount > 0 ? "text-rose-300" : "text-slate-600",
                  ].join(" ")}
                >
                  {unreadCount > 0
                    ? `${formatUnreadCount(unreadCount)} belum dibaca`
                    : "Tidak ada unread"}
                </span>
              </Link>
            </div>

            <span className="hidden rounded-lg border border-sky-400/15 bg-sky-400/[0.055] px-2.5 py-1.5 font-mono text-[0.65rem] uppercase tracking-[0.12em] text-sky-200 sm:inline-flex">
              {appMode}
            </span>

            <AccountMenu
              detailsRef={accountMenuRef}
              profile={profile}
            />
          </div>
        </header>

        <div className="min-w-0">{children}</div>
      </div>
    </div>
  );
}