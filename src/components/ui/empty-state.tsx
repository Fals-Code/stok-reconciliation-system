import type {
  ReactNode,
} from "react";

import { cx } from "@/components/ui/class-names";

export type EmptyStateProps = {
  title: ReactNode;
  description?: ReactNode;
  action?: ReactNode;
  className?: string;
};

export function EmptyState({
  title,
  description,
  action,
  className,
}: EmptyStateProps) {
  return (
    <div
      className={cx(
        "rounded-[var(--ui-radius-md)] border border-dashed border-ui-border bg-ui-surface-subtle px-6 py-8 text-center",
        className,
      )}
      data-empty-state="shared"
    >
      <p className="text-sm font-semibold text-ui-text">
        {title}
      </p>

      {description ? (
        <div className="mx-auto mt-2 max-w-xl text-sm leading-6 text-ui-text-muted">
          {description}
        </div>
      ) : null}

      {action ? (
        <div className="mt-4 flex justify-center">
          {action}
        </div>
      ) : null}
    </div>
  );
}