import type {
  ButtonHTMLAttributes,
} from "react";

import { cx } from "@/components/ui/cx";

export type IconButtonVariant =
  | "ghost"
  | "secondary"
  | "danger";

export type IconButtonProps = Omit<
  ButtonHTMLAttributes<HTMLButtonElement>,
  "aria-label"
> & {
  label: string;
  variant?: IconButtonVariant;
};

const variantClasses: Record<
  IconButtonVariant,
  string
> = {
  ghost:
    "border-transparent bg-transparent text-ui-text-muted hover:bg-ui-surface-subtle hover:text-ui-text",
  secondary:
    "border-ui-border bg-ui-surface text-ui-text hover:border-ui-border-strong hover:bg-ui-surface-subtle",
  danger:
    "border-ui-danger bg-ui-danger-subtle text-ui-danger hover:bg-ui-danger hover:text-ui-text-on-primary",
};

export function IconButton({
  label,
  variant = "ghost",
  className,
  children,
  type = "button",
  ...props
}: IconButtonProps) {
  return (
    <button
      {...props}
      aria-label={label}
      className={cx(
        "inline-flex h-[var(--ui-control-height)] w-[var(--ui-control-height)] shrink-0 items-center justify-center rounded-[var(--ui-radius-md)] border transition-colors motion-reduce:transition-none",
        "focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ui-focus",
        "disabled:cursor-not-allowed disabled:opacity-50",
        variantClasses[variant],
        className,
      )}
      type={type}
    >
      {children}
    </button>
  );
}