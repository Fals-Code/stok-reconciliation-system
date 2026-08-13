import type {
  ButtonHTMLAttributes,
} from "react";

import { cx } from "@/components/ui/cx";

export type ButtonVariant =
  | "primary"
  | "secondary"
  | "danger"
  | "ghost";

export type ButtonProps =
  ButtonHTMLAttributes<HTMLButtonElement> & {
    variant?: ButtonVariant;
    loading?: boolean;
    loadingLabel?: string;
  };

const variantClasses: Record<
  ButtonVariant,
  string
> = {
  primary:
    "border-ui-primary bg-ui-primary text-ui-text-on-primary hover:border-ui-primary-hover hover:bg-ui-primary-hover",
  secondary:
    "border-ui-border bg-ui-surface text-ui-text hover:border-ui-border-strong hover:bg-ui-surface-subtle",
  danger:
    "border-ui-danger bg-ui-danger text-ui-text-on-primary hover:opacity-90",
  ghost:
    "border-transparent bg-transparent text-ui-text-muted hover:bg-ui-surface-subtle hover:text-ui-text",
};

export function Button({
  variant = "primary",
  loading = false,
  loadingLabel = "Memproses...",
  disabled,
  className,
  children,
  type = "button",
  ...props
}: ButtonProps) {
  const isDisabled =
    disabled || loading;

  return (
    <button
      {...props}
      aria-busy={
        loading || undefined
      }
      className={cx(
        "relative inline-flex min-h-[var(--ui-control-height)] items-center justify-center rounded-[var(--ui-radius-md)] border px-4 text-sm font-semibold transition-colors motion-reduce:transition-none",
        "focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ui-focus",
        "disabled:cursor-not-allowed disabled:opacity-50",
        variantClasses[variant],
        className,
      )}
      disabled={isDisabled}
      type={type}
    >
      <span
        aria-hidden={
          loading || undefined
        }
        className={
          loading
            ? "invisible"
            : undefined
        }
      >
        {children}
      </span>

      {loading ? (
        <span className="absolute inset-0 flex items-center justify-center">
          {loadingLabel}
        </span>
      ) : null}
    </button>
  );
}