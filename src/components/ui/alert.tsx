import type {
  HTMLAttributes,
  ReactNode,
} from "react";

import { cx } from "@/components/ui/class-names";

export type AlertTone =
  | "info"
  | "success"
  | "warning"
  | "danger";

export type AlertProps = Omit<
  HTMLAttributes<HTMLDivElement>,
  "title"
> & {
  tone?: AlertTone;
  title?: ReactNode;
  children?: ReactNode;
};

const toneClasses: Record<
  AlertTone,
  string
> = {
  info:
    "border-ui-border-strong bg-ui-primary-subtle text-ui-primary",
  success:
    "border-ui-border-strong bg-ui-primary-subtle text-ui-primary",
  warning:
    "border-ui-warning bg-ui-warning-subtle text-ui-warning",
  danger:
    "border-ui-danger bg-ui-danger-subtle text-ui-danger",
};

export function Alert({
  tone = "info",
  title,
  children,
  className,
  role,
  ...props
}: AlertProps) {
  const resolvedRole =
    role ?? (tone === "danger"
      ? "alert"
      : "status");

  return (
    <div
      {...props}
      className={cx(
        "rounded-[var(--ui-radius-md)] border px-4 py-3 text-sm",
        toneClasses[tone],
        className,
      )}
      data-alert="shared"
      data-tone={tone}
      role={resolvedRole}
    >
      {title ? (
        <p className="font-semibold">
          {title}
        </p>
      ) : null}

      {children ? (
        <div
          className={cx(
            "leading-6",
            Boolean(title) && "mt-1",
          )}
        >
          {children}
        </div>
      ) : null}
    </div>
  );
}