"use client";

import Link from "next/link";
import {
  usePathname,
} from "next/navigation";

import {
  isNavItemActive,
  type AppNavigationItem,
} from "@/app/app-shell/navigation";
import {
  cx,
} from "@/components/ui/cx";

function NavigationIcon({
  icon,
}: {
  icon: AppNavigationItem["icon"];
}) {
  if (icon === "home") {
    return (
      <svg
        aria-hidden="true"
        className="h-[19px] w-[19px]"
        fill="none"
        viewBox="0 0 24 24"
      >
        <path
          d="M3.5 10.5 12 3l8.5 7.5V21H14v-6h-4v6H3.5V10.5Z"
          stroke="currentColor"
          strokeLinejoin="round"
          strokeWidth="1.7"
        />
      </svg>
    );
  }

  if (icon === "stock") {
    return (
      <svg
        aria-hidden="true"
        className="h-[19px] w-[19px]"
        fill="none"
        viewBox="0 0 24 24"
      >
        <path
          d="m4 7 8-4 8 4-8 4-8-4Z"
          stroke="currentColor"
          strokeLinejoin="round"
          strokeWidth="1.7"
        />
        <path
          d="M4 7v10l8 4 8-4V7M12 11v10"
          stroke="currentColor"
          strokeLinejoin="round"
          strokeWidth="1.7"
        />
      </svg>
    );
  }

  if (icon === "orders") {
    return (
      <svg
        aria-hidden="true"
        className="h-[19px] w-[19px]"
        fill="none"
        viewBox="0 0 24 24"
      >
        <path
          d="M6 7h12l1 14H5L6 7Z"
          stroke="currentColor"
          strokeLinejoin="round"
          strokeWidth="1.7"
        />
        <path
          d="M9 9V6a3 3 0 0 1 6 0v3"
          stroke="currentColor"
          strokeLinecap="round"
          strokeWidth="1.7"
        />
      </svg>
    );
  }

  return (
    <svg
      aria-hidden="true"
      className="h-[19px] w-[19px]"
      fill="none"
      viewBox="0 0 24 24"
    >
      <circle
        cx="12"
        cy="12"
        r="3"
        stroke="currentColor"
        strokeWidth="1.7"
      />
      <path
        d="M19.4 13a7.7 7.7 0 0 0 0-2l2-1.55-2-3.46-2.48 1a7.7 7.7 0 0 0-1.72-1L14.85 3h-4l-.35 2.99a7.7 7.7 0 0 0-1.72 1l-2.48-1-2 3.46L6.3 11a7.7 7.7 0 0 0 0 2l-2 1.55 2 3.46 2.48-1a7.7 7.7 0 0 0 1.72 1l.35 2.99h4l.35-2.99a7.7 7.7 0 0 0 1.72-1l2.48 1 2-3.46L19.4 13Z"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.7"
      />
    </svg>
  );
}

export function NavigationLink({
  item,
  compact = false,
}: {
  item: AppNavigationItem;
  compact?: boolean;
}) {
  const pathname = usePathname();
  const active = isNavItemActive(item.href, pathname);

  return (
    <Link
      aria-current={active ? "page" : undefined}
      className={cx(
        "group relative flex items-center rounded-[var(--ui-radius-md)] text-sm transition-colors motion-reduce:transition-none",
        compact
          ? "min-h-[3.5rem] flex-col justify-center gap-1 px-1 text-[0.68rem] font-medium"
          : "min-h-11 gap-2.5 px-2.5 font-medium",
        compact
          ? active
            ? "text-ui-primary"
            : "text-ui-text-muted hover:text-ui-text"
          : active
            ? "bg-ui-surface-selected font-semibold text-ui-primary"
            : "text-ui-text-muted hover:bg-ui-surface hover:text-ui-text",
      )}
      href={item.href}
    >
      {!compact && active ? (
        <span
          aria-hidden="true"
          className="absolute left-0 top-1/2 h-5 w-0.5 -translate-y-1/2 rounded-full bg-ui-primary"
        />
      ) : null}

      <span
        className={cx(
          "flex shrink-0 items-center justify-center transition-colors motion-reduce:transition-none",
          compact
            ? "h-7 min-w-9 rounded-full px-2"
            : "h-8 w-8 rounded-[var(--ui-radius-sm)]",
          active
            ? compact
              ? "bg-ui-primary-subtle text-ui-primary"
              : "text-ui-primary"
            : "text-ui-text-muted group-hover:text-ui-text",
        )}
      >
        <NavigationIcon icon={item.icon} />
      </span>

      <span className={compact ? "leading-none" : "truncate"}>
        {item.label}
      </span>
    </Link>
  );
}