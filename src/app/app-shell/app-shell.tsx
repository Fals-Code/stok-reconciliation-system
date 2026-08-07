"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  useEffect,
  useRef,
  useState,
  useSyncExternalStore,
  type ReactNode,
  type RefObject,
} from "react";

import {
  APP_NAV_SECTIONS,
  findActiveNavItem,
  getActiveNavHref,
} from "@/app/app-shell/navigation";
import { NavigationIcon } from "@/app/app-shell/navigation-icon";
import { logoutAction } from "@/app/auth-actions";

type AppShellProfile = {
  displayName: string;
  email: string | null;
  organizationCode: string;
  organizationName: string;
  roleCode: "ADMIN";
};

export type NotificationPreviewItem = {
  notificationId: string;
  title: string;
  message: string;
  severityCode: string;
  lastSeenAt: string;
};

type AppShellProps = {
  children: ReactNode;
  profile: AppShellProfile;
  appMode: string;
  unreadCount: number;
  notificationPreview: readonly NotificationPreviewItem[];
};

const SIDEBAR_STORAGE_KEY =
  "stok-management-sidebar-collapsed";
const SIDEBAR_CHANGE_EVENT =
  "stok-management-sidebar-change";

const FOCUSABLE_SELECTOR = [
  "a[href]",
  "button:not([disabled])",
  "input:not([disabled])",
  "select:not([disabled])",
  "textarea:not([disabled])",
  '[tabindex]:not([tabindex="-1"])',
].join(",");

function subscribeSidebarPreference(
  onStoreChange: () => void,
) {
  window.addEventListener("storage", onStoreChange);
  window.addEventListener(
    SIDEBAR_CHANGE_EVENT,
    onStoreChange,
  );

  return () => {
    window.removeEventListener("storage", onStoreChange);
    window.removeEventListener(
      SIDEBAR_CHANGE_EVENT,
      onStoreChange,
    );
  };
}

function getSidebarPreferenceSnapshot() {
  return (
    window.localStorage.getItem(SIDEBAR_STORAGE_KEY) ===
    "true"
  );
}

function getSidebarPreferenceServerSnapshot() {
  return false;
}

function setSidebarPreference(collapsed: boolean) {
  window.localStorage.setItem(
    SIDEBAR_STORAGE_KEY,
    String(collapsed),
  );
  window.dispatchEvent(
    new Event(SIDEBAR_CHANGE_EVENT),
  );
}

function formatUnreadCount(unreadCount: number) {
  return unreadCount > 99
    ? "99+"
    : unreadCount.toLocaleString("id-ID");
}

function MenuIcon({
  className,
}: {
  className?: string;
}) {
  return (
    <svg
      aria-hidden="true"
      className={className}
      fill="none"
      focusable="false"
      viewBox="0 0 24 24"
    >
      <path
        d="M4 7h16M4 12h16M4 17h16"
        stroke="currentColor"
        strokeLinecap="round"
        strokeWidth="1.75"
      />
    </svg>
  );
}

function CloseIcon({
  className,
}: {
  className?: string;
}) {
  return (
    <svg
      aria-hidden="true"
      className={className}
      fill="none"
      focusable="false"
      viewBox="0 0 24 24"
    >
      <path
        d="m6 6 12 12M18 6 6 18"
        stroke="currentColor"
        strokeLinecap="round"
        strokeWidth="1.75"
      />
    </svg>
  );
}


function SidebarToggleIcon({
  className,
  collapsed,
}: {
  className?: string;
  collapsed: boolean;
}) {
  return (
    <svg
      aria-hidden="true"
      className={className}
      fill="none"
      focusable="false"
      viewBox="0 0 24 24"
    >
      <rect
        height="16"
        rx="2"
        stroke="currentColor"
        strokeWidth="1.75"
        width="18"
        x="3"
        y="4"
      />
      <path
        d="M9 4v16"
        stroke="currentColor"
        strokeWidth="1.75"
      />
      <path
        d={
          collapsed
            ? "m13 9 3 3-3 3"
            : "m16 9-3 3 3 3"
        }
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.75"
      />
    </svg>
  );
}
function BellIcon({
  className,
}: {
  className?: string;
}) {
  return (
    <svg
      aria-hidden="true"
      className={className}
      fill="none"
      focusable="false"
      viewBox="0 0 24 24"
    >
      <path
        d="M6 9a6 6 0 0 1 12 0v5l2 3H4l2-3zM10 20h4"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.75"
      />
    </svg>
  );
}

function Brand({
  compact = false,
  onNavigate,
}: {
  compact?: boolean;
  onNavigate?: () => void;
}) {
  return (
    <Link
      aria-label={
        compact
          ? "Stok Management — Ringkasan Stok"
          : undefined
      }
      className={[
        "flex min-h-16 items-center border-b border-ui-border",
        "transition hover:bg-ui-surface-subtle",
        compact
          ? "justify-center px-2"
          : "gap-3 px-4",
      ].join(" ")}
      href="/"
      onClick={onNavigate}
      title={compact ? "Stok Management" : undefined}
    >
      <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-[var(--ui-radius-md)] bg-ui-primary text-ui-text-on-primary">
        <NavigationIcon
          className="h-5 w-5"
          name="product"
        />
      </span>

      {!compact ? (
        <span className="min-w-0">
          <span className="block truncate text-sm font-semibold text-ui-text">
            Stok Management
          </span>
          <span className="mt-0.5 block truncate text-xs text-ui-text-muted">
            Kontrol stok gudang
          </span>
        </span>
      ) : null}
    </Link>
  );
}

function Navigation({
  collapsed = false,
  pathname,
  onNavigate,
  unreadCount,
}: {
  collapsed?: boolean;
  pathname: string;
  onNavigate?: () => void;
  unreadCount: number;
}) {
  const activeHref = getActiveNavHref(pathname);

  return (
    <nav
      aria-label="Navigasi utama"
      className={[
        "py-4",
        collapsed ? "px-2" : "px-3",
      ].join(" ")}
    >
      <div className="space-y-6">
        {APP_NAV_SECTIONS.map((section) => (
          <section key={section.label}>
            <p
              className={
                collapsed
                  ? "sr-only"
                  : "px-3 text-[0.68rem] font-semibold uppercase tracking-[0.12em] text-ui-text-muted"
              }
            >
              {section.label}
            </p>

            {collapsed ? (
              <div
                aria-hidden="true"
                className="mx-auto mb-2 h-px w-7 bg-ui-border"
              />
            ) : null}

            <div
              className={[
                "space-y-1",
                collapsed ? "" : "mt-2",
              ].join(" ")}
            >
              {section.items.map((item) => {
                const active = activeHref === item.href;
                const notificationItem =
                  item.href === "/notifications";
                const showUnread =
                  notificationItem && unreadCount > 0;

                return (
                  <Link
                    key={item.href}
                    aria-current={
                      active ? "page" : undefined
                    }
                    aria-label={
                      collapsed ? item.label : undefined
                    }
                    className={[
                      "group relative flex min-h-[var(--ui-control-height)] items-center rounded-[var(--ui-radius-md)] border transition",
                      collapsed
                        ? "justify-center px-2"
                        : "gap-3 px-3",
                      active
                        ? "border-ui-border-strong bg-ui-primary-subtle font-semibold text-ui-primary"
                        : "border-transparent text-ui-text-muted hover:border-ui-border hover:bg-ui-surface-subtle hover:text-ui-text",
                    ].join(" ")}
                    href={item.href}
                    onClick={onNavigate}
                    title={
                      collapsed
                        ? `${item.label} — ${item.description}`
                        : undefined
                    }
                  >
                    <span
                      aria-hidden="true"
                      className={[
                        "flex h-8 w-8 shrink-0 items-center justify-center rounded-[var(--ui-radius-sm)]",
                        active
                          ? "bg-ui-surface text-ui-primary shadow-[var(--ui-shadow-sm)]"
                          : "text-ui-text-muted group-hover:text-ui-text",
                      ].join(" ")}
                    >
                      <NavigationIcon
                        className="h-[1.15rem] w-[1.15rem]"
                        name={item.icon}
                      />
                    </span>

                    {!collapsed ? (
                      <span className="flex min-w-0 flex-1 items-center gap-2 text-sm">
                        <span className="truncate">
                          {item.label}
                        </span>

                        {showUnread ? (
                          <span className="inline-flex min-w-6 shrink-0 items-center justify-center rounded-full bg-ui-danger-subtle px-1.5 py-0.5 text-[0.65rem] font-semibold text-ui-danger">
                            {formatUnreadCount(
                              unreadCount,
                            )}
                          </span>
                        ) : null}
                      </span>
                    ) : null}

                    {collapsed && showUnread ? (
                      <span
                        aria-label={`${formatUnreadCount(unreadCount)} notifikasi belum dibaca`}
                        className="absolute right-1 top-1 flex h-4 min-w-4 items-center justify-center rounded-full bg-ui-danger px-1 text-[0.58rem] font-semibold text-white"
                      >
                        {formatUnreadCount(unreadCount)}
                      </span>
                    ) : null}

                    {collapsed ? (
                      <span
                        role="tooltip"
                        className="pointer-events-none absolute left-full z-50 ml-3 w-max max-w-64 rounded-[var(--ui-radius-sm)] bg-ui-text px-3 py-2 text-left text-xs font-normal text-white opacity-0 shadow-[var(--ui-shadow-md)] transition group-focus-within:opacity-100 group-hover:opacity-100"
                      >
                        <span className="block font-semibold">
                          {item.label}
                        </span>
                        <span className="mt-1 block text-white/75">
                          {item.description}
                        </span>
                      </span>
                    ) : null}
                  </Link>
                );
              })}
            </div>
          </section>
        ))}
      </div>
    </nav>
  );
}

function NotificationMenu({
  detailsRef,
  notifications,
  onOpen,
  unreadCount,
}: {
  detailsRef: RefObject<HTMLDetailsElement | null>;
  notifications: readonly NotificationPreviewItem[];
  onOpen: () => void;
  unreadCount: number;
}) {
  return (
    <details
      ref={detailsRef}
      className="group relative"
      data-exclusive-popover="notification"
      data-hover-menu
      onBlur={(event) => {
        const nextTarget = event.relatedTarget;

        if (
          !(nextTarget instanceof Node) ||
          !event.currentTarget.contains(nextTarget)
        ) {
          event.currentTarget.open = false;
        }
      }}
      onFocus={() => {
        onOpen();
      }}
      onPointerEnter={(event) => {
        if (event.pointerType !== "mouse") {
          return;
        }

        onOpen();
        event.currentTarget.open = true;
      }}
      onPointerLeave={(event) => {
        if (event.pointerType !== "mouse") {
          return;
        }

        if (
          !event.currentTarget.contains(
            document.activeElement,
          )
        ) {
          event.currentTarget.open = false;
        }
      }}
    >
      <summary
        aria-label={`Buka Notifikasi, ${unreadCount} belum dibaca`}
        className="relative flex h-11 w-11 cursor-pointer list-none items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface text-ui-text-muted transition hover:border-ui-border-strong hover:bg-ui-surface-subtle hover:text-ui-text"
        title="Notifikasi"
      >
        <BellIcon className="h-5 w-5" />

        {unreadCount > 0 ? (
          <span className="absolute -right-1 -top-1 flex h-5 min-w-5 items-center justify-center rounded-full bg-ui-danger px-1 text-[0.62rem] font-semibold text-white">
            {formatUnreadCount(unreadCount)}
          </span>
        ) : null}
      </summary>

      <span
        aria-hidden="true"
        className="w-[min(24rem,calc(100vw-2rem))]"
        data-popover-hover-bridge="notification"
      />

      <div
        className="fixed inset-x-4 top-[calc(var(--ui-header-height)+0.75rem)] z-50 hidden overflow-hidden rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface shadow-[var(--ui-shadow-md)] sm:absolute sm:inset-x-auto sm:right-0 sm:top-full sm:mt-3 sm:w-[min(24rem,calc(100vw-2rem))]"
        data-notification-preview
        data-notification-preview-mode="latest"
        data-popover
        data-popover-clip="rounded"
        data-popover-offset="spacious"
      >
        <div className="flex items-center justify-between gap-4 border-b border-ui-border px-5 py-4">
          <p className="font-semibold text-ui-text">
            Notifikasi
          </p>
          <span className="text-xs text-ui-text-muted">
            {unreadCount > 0
              ? `${formatUnreadCount(unreadCount)} belum dibaca`
              : "Tidak ada yang baru"}
          </span>
        </div>

        {notifications.length > 0 ? (
          <div className="max-h-96 divide-y divide-ui-border overflow-y-auto">
            {notifications.map((notification) => (
              <Link
                className="flex gap-3 px-5 py-4 transition hover:bg-ui-surface-subtle"
                href={`/notifications?notificationId=${encodeURIComponent(
                  notification.notificationId,
                )}#detail`}
                key={notification.notificationId}
              >
                <span
                  aria-hidden="true"
                  className={[
                    "mt-1.5 h-2.5 w-2.5 shrink-0 rounded-full",
                    notification.severityCode === "CRITICAL"
                      ? "bg-ui-danger"
                      : notification.severityCode === "HIGH" ||
                          notification.severityCode === "WARNING"
                        ? "bg-ui-warning"
                        : "bg-ui-primary",
                  ].join(" ")}
                />

                <span className="min-w-0 flex-1">
                  <span className="block truncate text-sm font-medium text-ui-text">
                    {notification.title}
                  </span>
                  <span className="mt-1 block max-h-10 overflow-hidden text-xs leading-5 text-ui-text-muted">
                    {notification.message}
                  </span>
                  <span className="mt-1.5 block text-[0.68rem] text-ui-text-muted">
                    {new Intl.DateTimeFormat("id-ID", {
                      dateStyle: "medium",
                      timeStyle: "short",
                      timeZone: "Asia/Jakarta",
                    }).format(
                      new Date(notification.lastSeenAt),
                    )} WIB
                  </span>
                </span>
              </Link>
            ))}
          </div>
        ) : (
          <p className="px-5 py-7 text-center text-sm text-ui-text-muted">
            Belum ada notifikasi.
          </p>
        )}

        <Link
          className="flex min-h-12 items-center justify-center border-t border-ui-border px-5 text-sm font-semibold text-ui-primary transition-colors hover:bg-ui-surface-subtle active:bg-ui-primary-subtle"
          href="/notifications"
        >
          Lihat semua notifikasi
        </Link>
      </div>
    </details>
  );
}
function AccountMenu({
  profile,
  detailsRef,
  onOpen,
}: {
  profile: AppShellProfile;
  detailsRef: RefObject<HTMLDetailsElement | null>;
  onOpen: () => void;
}) {
  return (
    <details
      ref={detailsRef}
      className="group relative"
      data-exclusive-popover="account"
      data-hover-menu
      onBlur={(event) => {
        const nextTarget = event.relatedTarget;

        if (
          !(nextTarget instanceof Node) ||
          !event.currentTarget.contains(nextTarget)
        ) {
          event.currentTarget.open = false;
        }
      }}
      onFocus={() => {
        onOpen();
      }}
      onPointerEnter={(event) => {
        if (event.pointerType !== "mouse") {
          return;
        }

        onOpen();
        event.currentTarget.open = true;
      }}
      onPointerLeave={(event) => {
        if (event.pointerType !== "mouse") {
          return;
        }

        if (
          !event.currentTarget.contains(
            document.activeElement,
          )
        ) {
          event.currentTarget.open = false;
        }
      }}
    >
      <summary
        aria-label={`Buka menu akun ${profile.displayName}`}
        className="flex h-11 w-11 cursor-pointer list-none items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface transition hover:border-ui-border-strong hover:bg-ui-surface-subtle"
        title={`Akun ${profile.displayName}`}
      >
        <span
          aria-hidden="true"
          className="flex h-8 w-8 items-center justify-center rounded-full bg-ui-primary-subtle text-sm font-semibold text-ui-primary"
        >
          {profile.displayName
            .slice(0, 1)
            .toUpperCase()}
        </span>
      </summary>

      <span
        aria-hidden="true"
        className="w-[min(20rem,calc(100vw-2rem))]"
        data-popover-hover-bridge="account"
      />

      <div
        className="fixed inset-x-4 top-[calc(var(--ui-header-height)+0.75rem)] z-50 hidden w-[min(20rem,calc(100vw-2rem))] rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4 shadow-[var(--ui-shadow-md)] sm:absolute sm:inset-x-auto sm:right-0 sm:top-full sm:mt-3"
        data-account-popover
        data-popover
        data-popover-offset="spacious"
      >
        <div className="rounded-[var(--ui-radius-md)] bg-ui-surface-subtle p-4">
          <p className="text-[0.68rem] font-semibold uppercase tracking-[0.1em] text-ui-text-muted">
            Profil
          </p>
          <p className="mt-2 font-medium text-ui-text">
            {profile.displayName}
          </p>
          <p className="mt-1 truncate text-xs text-ui-text-muted">
            {profile.email ?? "Email tidak tersedia"}
          </p>
          <p className="mt-2 text-xs text-ui-text-muted">
            {profile.organizationName} · Admin
          </p>
        </div>

        <form action={logoutAction} className="mt-3">
          <button
            className="flex min-h-[var(--ui-control-height)] w-full items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-danger-subtle px-3 text-sm font-medium text-ui-danger transition hover:border-ui-border-strong"
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
  notificationPreview,
}: AppShellProps) {
  const pathname = usePathname();
  const [mobileOpen, setMobileOpen] =
    useState(false);

  const sidebarCollapsed = useSyncExternalStore(
    subscribeSidebarPreference,
    getSidebarPreferenceSnapshot,
    getSidebarPreferenceServerSnapshot,
  );

  const accountMenuRef =
    useRef<HTMLDetailsElement>(null);
  const notificationMenuRef =
    useRef<HTMLDetailsElement>(null);
  const mobileTriggerRef =
    useRef<HTMLButtonElement>(null);
  const mobileCloseRef =
    useRef<HTMLButtonElement>(null);
  const mobileDialogRef =
    useRef<HTMLElement>(null);
  const mobileWasOpenRef = useRef(false);

  const activeNavigation =
    findActiveNavItem(pathname);

  useEffect(() => {
    function closeTopbarMenusOnEscape(
      event: KeyboardEvent,
    ) {
      if (event.key !== "Escape") {
        return;
      }

      notificationMenuRef.current?.removeAttribute(
        "open",
      );
      accountMenuRef.current?.removeAttribute(
        "open",
      );
    }

    window.addEventListener(
      "keydown",
      closeTopbarMenusOnEscape,
    );

    return () => {
      window.removeEventListener(
        "keydown",
        closeTopbarMenusOnEscape,
      );
    };
  }, []);

  useEffect(() => {
    if (!mobileOpen) {
      return;
    }

    mobileWasOpenRef.current = true;

    const previousOverflow =
      document.body.style.overflow;
    const dialog = mobileDialogRef.current;
    const focusRequest = window.requestAnimationFrame(
      () => {
        mobileCloseRef.current?.focus();
      },
    );

    function closeOnEscape(event: KeyboardEvent) {
      if (event.key === "Escape") {
        setMobileOpen(false);
        return;
      }

      if (
        event.key !== "Tab" ||
        dialog === null
      ) {
        return;
      }

      const focusable = Array.from(
        dialog.querySelectorAll<HTMLElement>(
          FOCUSABLE_SELECTOR,
        ),
      ).filter(
        (element) =>
          !element.hasAttribute("disabled") &&
          element.tabIndex !== -1,
      );

      const first = focusable.at(0);
      const last = focusable.at(-1);

      if (!first || !last) {
        event.preventDefault();
        dialog.focus();
        return;
      }

      if (
        event.shiftKey &&
        document.activeElement === first
      ) {
        event.preventDefault();
        last.focus();
      } else if (
        !event.shiftKey &&
        document.activeElement === last
      ) {
        event.preventDefault();
        first.focus();
      }
    }

    document.body.style.overflow = "hidden";
    window.addEventListener(
      "keydown",
      closeOnEscape,
    );

    return () => {
      window.cancelAnimationFrame(focusRequest);
      document.body.style.overflow =
        previousOverflow;
      window.removeEventListener(
        "keydown",
        closeOnEscape,
      );
    };
  }, [mobileOpen]);

  useEffect(() => {
    if (
      mobileOpen ||
      !mobileWasOpenRef.current
    ) {
      return;
    }

    mobileWasOpenRef.current = false;
    mobileTriggerRef.current?.focus();
  }, [mobileOpen]);

  function openMobileNavigation() {
    notificationMenuRef.current?.removeAttribute(
      "open",
    );
    accountMenuRef.current?.removeAttribute(
      "open",
    );
    setMobileOpen(true);
  }

  function closeMobileNavigation() {
    setMobileOpen(false);
  }

  return (
    <div
      className="app-shell flex min-h-screen bg-ui-canvas text-ui-text"
      data-app-shell="light-admin-shell"
    >
      <a
        className="fixed left-4 top-0 z-[100] -translate-y-full rounded-b-[var(--ui-radius-md)] bg-ui-primary px-4 py-3 text-sm font-semibold text-ui-text-on-primary shadow-[var(--ui-shadow-md)] transition focus:translate-y-0"
        href="#main-content"
      >
        Lewati ke konten utama
      </a>

      <aside
        aria-label="Navigasi desktop"
        className={[
          "sticky top-0 hidden h-screen shrink-0 flex-col border-r border-ui-border bg-ui-surface transition-[width] duration-200 lg:flex",
          sidebarCollapsed
            ? "w-[var(--ui-sidebar-collapsed)]"
            : "w-[var(--ui-sidebar-expanded)]",
        ].join(" ")}
        data-sidebar-state={
          sidebarCollapsed
            ? "collapsed"
            : "expanded"
        }
      >
        <Brand compact={sidebarCollapsed} />

        <div className="min-h-0 flex-1 overflow-y-auto overflow-x-hidden">
          <Navigation
            collapsed={sidebarCollapsed}
            pathname={pathname}
            unreadCount={unreadCount}
          />
        </div>



      </aside>

      {mobileOpen ? (
        <>
          <button
            aria-label="Tutup navigasi"
            className="fixed inset-0 z-[55] bg-[var(--ui-overlay)] lg:hidden"
            onClick={closeMobileNavigation}
            type="button"
          />

          <aside
            ref={mobileDialogRef}
            aria-label="Navigasi mobile"
            aria-modal="true"
            className="fixed inset-y-0 left-0 z-[60] flex w-[min(21rem,calc(100vw-2rem))] flex-col border-r border-ui-border bg-ui-surface shadow-[var(--ui-shadow-md)] lg:hidden"
            data-mobile-navigation
            id="mobile-navigation"
            role="dialog"
            tabIndex={-1}
          >
            <div className="flex items-center border-b border-ui-border">
              <div className="min-w-0 flex-1">
                <Brand
                  onNavigate={
                    closeMobileNavigation
                  }
                />
              </div>

              <button
                ref={mobileCloseRef}
                aria-label="Tutup menu"
                className="mr-3 flex h-11 w-11 shrink-0 items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-border text-ui-text-muted transition hover:border-ui-border-strong hover:bg-ui-surface-subtle hover:text-ui-text"
                onClick={closeMobileNavigation}
                type="button"
              >
                <CloseIcon className="h-5 w-5" />
              </button>
            </div>

            <div className="min-h-0 flex-1 overflow-y-auto">
              <Navigation
                pathname={pathname}
                onNavigate={
                  closeMobileNavigation
                }
                unreadCount={unreadCount}
              />
            </div>


          </aside>
        </>
      ) : null}

      <div className="min-w-0 flex-1">
        <header
          className="sticky top-0 z-30 border-b border-ui-border bg-ui-surface shadow-[var(--ui-shadow-sm)]"
          data-app-topbar="admin"
        >
          <div className="flex min-h-[var(--ui-header-height)] items-center gap-2 px-3 sm:px-4 lg:px-5">
            <button
              ref={mobileTriggerRef}
              aria-controls="mobile-navigation"
              aria-expanded={mobileOpen}
              aria-label="Buka navigasi"
              className="flex h-11 w-11 shrink-0 items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface text-ui-text-muted transition hover:border-ui-border-strong hover:bg-ui-surface-subtle hover:text-ui-text lg:hidden"
              onClick={openMobileNavigation}
              type="button"
            >
              <MenuIcon className="h-5 w-5" />
            </button>

            <button
              aria-label={
                sidebarCollapsed
                  ? "Perluas navigasi"
                  : "Ciutkan navigasi"
              }
              aria-pressed={sidebarCollapsed}
              className="hidden h-11 w-11 shrink-0 items-center justify-center rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface text-ui-text-muted transition hover:border-ui-border-strong hover:bg-ui-surface-subtle hover:text-ui-text lg:flex"
              data-sidebar-toggle
              onClick={() =>
                setSidebarPreference(
                  !sidebarCollapsed,
                )
              }
              title={
                sidebarCollapsed
                  ? "Perluas navigasi"
                  : "Ciutkan navigasi"
              }
              type="button"
            >
              <SidebarToggleIcon
                className="h-5 w-5"
                collapsed={sidebarCollapsed}
              />
            </button>

            <span
              aria-hidden="true"
              className="mx-1 hidden h-7 w-px bg-ui-border lg:block"
            />

            <div className="min-w-0 flex-1">
              <p className="truncate text-base font-semibold text-ui-text">
                {activeNavigation?.item.label ??
                  "Stok Management"}
              </p>
            </div>

            <div className="flex shrink-0 items-center gap-3">
              {appMode !== "LOCAL" ? (
                <span
                  className="hidden rounded-[var(--ui-radius-sm)] border border-ui-border bg-ui-surface-subtle px-2.5 py-1.5 text-[0.68rem] font-semibold uppercase tracking-[0.08em] text-ui-text-muted md:inline-flex"
                  title="Mode aplikasi"
                >
                  {appMode}
                </span>
              ) : null}

              <NotificationMenu
                detailsRef={notificationMenuRef}
                notifications={notificationPreview}
                onOpen={() => {
                  accountMenuRef.current?.removeAttribute(
                    "open",
                  );
                }}
                unreadCount={unreadCount}
              />

              <AccountMenu
                detailsRef={accountMenuRef}
                onOpen={() => {
                  notificationMenuRef.current?.removeAttribute(
                    "open",
                  );
                }}
                profile={profile}
              />
            </div>
          </div>
        </header>

        <div
          className="min-w-0 focus:outline-none"
          id="main-content"
          tabIndex={-1}
        >
          {children}
        </div>
      </div>
    </div>
  );
}
