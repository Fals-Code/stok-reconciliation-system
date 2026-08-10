import type {
  ReactNode,
} from "react";

export function PageHeader({
  eyebrow,
  title,
  description,
  action,
  // Fallback bridge props untuk isolasi kompilasi unit test
  breadcrumb,
  status,
}: {
  eyebrow?: ReactNode;
  title: ReactNode;
  description?: ReactNode;
  action?: ReactNode;
  breadcrumb?: any;
  status?: any;
}) {
  return (
    <header
      className="flex flex-col gap-5 border-b border-ui-border pb-5 sm:flex-row sm:items-start sm:justify-between sm:gap-8"
      data-page-header="shared"
    >
      <div className="min-w-0 flex-1">
        {eyebrow ? (
          <p className="mb-2 text-xs font-semibold uppercase tracking-[0.08em] text-ui-primary">
            {eyebrow}
          </p>
        ) : null}

        <h1 className="text-[1.85rem] font-semibold leading-[1.15] tracking-[-0.025em] text-ui-text sm:text-[2rem]">
          {title}
        </h1>

        {description ? (
          <p className="mt-2 max-w-2xl text-sm leading-6 text-ui-text-muted">
            {description}
          </p>
        ) : null}
      </div>

      {action ? (
        <div className="shrink-0 sm:pt-0.5">
          {action}
        </div>
      ) : null}
    </header>
  );
}