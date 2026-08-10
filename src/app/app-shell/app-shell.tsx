import type {
  ReactNode,
} from "react";

import {
  NavigationLink,
} from "@/app/app-shell/navigation-link";
import {
  primaryNavigation,
  settingsNavigation,
} from "@/app/app-shell/navigation";
import type {
  AdminProfile,
} from "@/lib/auth";

function profileInitial(value: string) {
  return value.trim().slice(0, 1).toUpperCase() || "A";
}

export function AppShell({
  profile,
  children,
}: {
  profile: AdminProfile;
  children: ReactNode;
}) {
  return (
    <div className="min-h-screen bg-ui-canvas lg:grid lg:grid-cols-[240px_minmax(0,1fr)]">
      <a
        className="fixed left-4 top-0 z-[100] -translate-y-full rounded-b-[var(--ui-radius-md)] bg-ui-primary px-4 py-3 text-sm font-semibold text-ui-text-on-primary shadow-[var(--ui-shadow-md)] transition-transform focus:translate-y-0 motion-reduce:transition-none"
        href="#main-content"
      >
        Lewati ke konten utama
      </a>

      <aside className="hidden min-h-screen border-r border-ui-border bg-ui-surface-subtle lg:sticky lg:top-0 lg:flex lg:h-screen lg:flex-col">
        <div className="px-5 pb-6 pt-6">
          <p className="text-[0.95rem] font-semibold leading-5 tracking-[-0.015em] text-ui-text">
            Sistem Rekonsiliasi Stok
          </p>
          <p className="mt-1 text-xs leading-5 text-ui-text-muted">
            Operasional gudang
          </p>
        </div>

        <nav
          aria-label="Navigasi utama"
          className="flex min-h-0 flex-1 flex-col px-3 pb-4"
        >
          <div className="grid gap-1">
            {primaryNavigation.map((item) => (
              <NavigationLink
                item={item}
                key={item.href}
              />
            ))}
          </div>

          <div className="mt-auto border-t border-ui-border pt-3">
            <NavigationLink item={settingsNavigation} />
          </div>
        </nav>

        <div className="border-t border-ui-border px-5 py-4">
          <div className="flex min-w-0 items-center gap-3">
            <span
              aria-hidden="true"
              className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-ui-primary-subtle text-xs font-semibold text-ui-primary"
            >
              {profileInitial(profile.display_name)}
            </span>

            <div className="min-w-0">
              <p className="truncate text-sm font-semibold text-ui-text">
                {profile.display_name}
              </p>
              <p className="mt-0.5 truncate text-xs text-ui-text-muted">
                {profile.organization_name}
              </p>
            </div>
          </div>
        </div>
      </aside>

      <div className="min-w-0">
        <header className="sticky top-0 z-30 border-b border-ui-border bg-ui-surface/95 backdrop-blur lg:hidden">
          <div className="flex h-14 items-center px-4 sm:px-5">
            <div className="min-w-0">
              <p className="text-[0.65rem] font-semibold uppercase tracking-[0.11em] text-ui-text-muted">
                Gudang
              </p>
              <p className="mt-0.5 truncate text-sm font-semibold text-ui-text">
                Sistem Rekonsiliasi Stok
              </p>
            </div>
          </div>
        </header>

        <main
          className="min-h-screen pb-[5.25rem] lg:pb-0"
          id="main-content"
          tabIndex={-1}
        >
          {children}
        </main>

        <nav
          aria-label="Navigasi utama"
          className="fixed inset-x-0 bottom-0 z-40 grid grid-cols-4 border-t border-ui-border bg-ui-surface/97 px-2 pb-[max(0.4rem,env(safe-area-inset-bottom))] pt-1.5 shadow-[0_-6px_24px_rgb(24_32_30_/_0.05)] backdrop-blur lg:hidden"
        >
          {primaryNavigation.map((item) => (
            <NavigationLink
              compact
              item={item}
              key={item.href}
            />
          ))}

          <NavigationLink
            compact
            item={settingsNavigation}
          />
        </nav>
      </div>
    </div>
  );
}