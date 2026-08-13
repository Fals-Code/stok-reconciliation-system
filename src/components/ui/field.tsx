import type {
  ReactNode,
} from "react";

import { cx } from "@/components/ui/cx";

export type FieldControlProps = {
  id: string;
  "aria-describedby"?: string;
  "aria-invalid"?: true;
};

export type FieldProps = {
  id: string;
  label: ReactNode;
  description?: ReactNode;
  error?: ReactNode;
  children: (
    props: FieldControlProps,
  ) => ReactNode;
  className?: string;
};

export function Field({
  id,
  label,
  description,
  error,
  children,
  className,
}: FieldProps) {
  const descriptionId =
    description
      ? `${id}-description`
      : undefined;

  const errorId =
    error
      ? `${id}-error`
      : undefined;

  const describedBy = [
    descriptionId,
    errorId,
  ]
    .filter(Boolean)
    .join(" ") || undefined;

  return (
    <div
      className={cx(
        "grid gap-2",
        className,
      )}
      data-ui-field
    >
      <label
        className="text-sm font-semibold text-ui-text"
        htmlFor={id}
      >
        {label}
      </label>

      {description ? (
        <div
          className="text-xs leading-5 text-ui-text-muted"
          id={descriptionId}
        >
          {description}
        </div>
      ) : null}

      {children({
        id,
        "aria-describedby":
          describedBy,
        "aria-invalid":
          error
            ? true
            : undefined,
      })}

      {error ? (
        <div
          className="text-xs font-medium leading-5 text-ui-danger"
          id={errorId}
          role="alert"
        >
          {error}
        </div>
      ) : null}
    </div>
  );
}