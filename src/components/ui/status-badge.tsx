import type {
  HTMLAttributes,
  ReactNode,
} from "react";

import { cx } from "@/components/ui/class-names";

export type StatusBadgeTone =
  | "neutral"
  | "selected"
  | "warning"
  | "danger";

export type StatusBadgeProps =
  HTMLAttributes<HTMLSpanElement> & {
    tone?: StatusBadgeTone;
    children: ReactNode;
  };

const toneClasses: Record<
  StatusBadgeTone,
  string
> = {
  neutral:
    "border-ui-border bg-ui-surface-subtle text-ui-text-muted",
  selected:
    "border-ui-border-strong bg-ui-primary-subtle text-ui-primary",
  warning:
    "border-ui-warning bg-ui-warning-subtle text-ui-warning",
  danger:
    "border-ui-danger bg-ui-danger-subtle text-ui-danger",
};

export function StatusBadge({
  tone = "neutral",
  className,
  children,
  ...props
}: StatusBadgeProps) {
  return (
    <span
      {...props}
      className={cx(
        "inline-flex min-h-6 items-center rounded-full border px-2.5 py-1 text-xs font-semibold leading-none",
        toneClasses[tone],
        className,
      )}
      data-status-badge="shared"
      data-tone={tone}
    >
      {children}
    </span>
  );
}