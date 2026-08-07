import type { ReactNode } from "react";

import {
  Breadcrumb,
  type BreadcrumbProps,
} from "@/app/app-shell/breadcrumb";

export type PageHeaderProps = {
  title: ReactNode;
  description?: ReactNode;
  breadcrumb?: BreadcrumbProps["items"];
  status?: ReactNode;
  primaryAction?: ReactNode;
  secondaryAction?: ReactNode;
};

export function PageHeader({
  title,
  description,
  breadcrumb,
  status,
  primaryAction,
  secondaryAction,
}: PageHeaderProps) {
  const hasTrailingContent = Boolean(
    status ||
      primaryAction ||
      secondaryAction,
  );

  return (
    <header
      className="flex flex-col gap-4"
      data-page-header="shared"
    >
      {breadcrumb &&
      breadcrumb.length > 0 ? (
        <Breadcrumb items={breadcrumb} />
      ) : null}

      <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
        <div className="min-w-0">
          <h1 className="text-3xl font-semibold tracking-tight sm:text-4xl">
            {title}
          </h1>

          {description ? (
            <div className="mt-3 max-w-3xl text-sm leading-6 opacity-70">
              {description}
            </div>
          ) : null}
        </div>

        {hasTrailingContent ? (
          <div className="flex shrink-0 flex-wrap items-center gap-3">
            {status}
            {secondaryAction}
            {primaryAction}
          </div>
        ) : null}
      </div>
    </header>
  );
}