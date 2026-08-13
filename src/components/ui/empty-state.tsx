import type {
  HTMLAttributes,
  ReactNode,
} from "react";

import { cx } from "@/components/ui/cx";

export type EmptyStateProps =
  HTMLAttributes<HTMLDivElement> & {
    title: ReactNode;
    description?: ReactNode;
    action?: ReactNode;
  };

export function EmptyState({
  title,
  description,
  action,
  className,
  ...props
}: EmptyStateProps) {
  return (
    <div
      {...props}
      className={cx(
        "border-y border-dashed border-ui-border bg-ui-surface-subtle px-5 py-8 text-center",
        className,
      )}
      data-ui-empty-state
    >
      <div className="text-sm font-semibold text-ui-text">
        {title}
      </div>

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