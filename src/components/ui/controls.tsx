import type {
  InputHTMLAttributes,
  SelectHTMLAttributes,
  TextareaHTMLAttributes,
} from "react";

import { cx } from "@/components/ui/cx";

const controlClassName = [
  "min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)]",
  "border border-ui-border bg-ui-surface px-3.5 text-sm text-ui-text",
  "outline-none transition-colors motion-reduce:transition-none",
  "placeholder:text-ui-text-muted",
  "hover:border-ui-border-strong",

  "disabled:cursor-not-allowed disabled:bg-ui-surface-subtle disabled:text-ui-text-muted",
  "aria-[invalid=true]:border-ui-danger",
].join(" ");

export type InputProps =
  InputHTMLAttributes<HTMLInputElement>;

export function Input({
  className,
  ...props
}: InputProps) {
  return (
    <input
      {...props}
      className={cx(
        controlClassName,
        className,
      )}
      data-ui-control="input"
    />
  );
}

export type SelectProps =
  SelectHTMLAttributes<HTMLSelectElement>;

export function Select({
  className,
  ...props
}: SelectProps) {
  return (
    <select
      {...props}
      className={cx(
        controlClassName,
        "pr-9",
        className,
      )}
      data-ui-control="select"
    />
  );
}

export type TextareaProps =
  TextareaHTMLAttributes<HTMLTextAreaElement>;

export function Textarea({
  className,
  ...props
}: TextareaProps) {
  return (
    <textarea
      {...props}
      className={cx(
        controlClassName,
        "min-h-28 resize-y py-3",
        className,
      )}
      data-ui-control="textarea"
    />
  );
}