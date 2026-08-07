import Link from "next/link";

import type { AppBreadcrumbItem } from "@/app/app-shell/navigation";

export type BreadcrumbProps = {
  items: readonly AppBreadcrumbItem[];
};

export function Breadcrumb({
  items,
}: BreadcrumbProps) {
  if (items.length === 0) {
    return null;
  }

  return (
    <nav
      aria-label="Breadcrumb"
      className="min-w-0"
      data-breadcrumb="shared"
    >
      <ol className="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1 text-sm">
        {items.map((item, index) => {
          const isCurrent =
            index === items.length - 1;

          return (
            <li
              className="flex min-w-0 items-center gap-2"
              key={`${index}:${item.label}`}
            >
              {index > 0 ? (
                <span
                  aria-hidden="true"
                  className="select-none opacity-40"
                >
                  /
                </span>
              ) : null}

              {item.href && !isCurrent ? (
                <Link
                  className="truncate opacity-70 transition-opacity hover:opacity-100 hover:underline"
                  href={item.href}
                >
                  {item.label}
                </Link>
              ) : (
                <span
                  aria-current={
                    isCurrent
                      ? "page"
                      : undefined
                  }
                  className={
                    isCurrent
                      ? "truncate font-medium"
                      : "truncate opacity-60"
                  }
                >
                  {item.label}
                </span>
              )}
            </li>
          );
        })}
      </ol>
    </nav>
  );
}