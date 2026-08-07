import type {
  ReactNode,
} from "react";

import { cx } from "@/components/ui/class-names";

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
    controlProps: FieldControlProps,
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
  const descriptionId = description
    ? `${id}-description`
    : null;
  const errorId = error
    ? `${id}-error`
    : null;

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
      data-field="shared"
    >
      <label
        className="text-sm font-semibold text-ui-text"
        htmlFor={id}
      >
        {label}
      </label>

      {description ? (
        <p
          className="text-xs leading-5 text-ui-text-muted"
          id={descriptionId ?? undefined}
        >
          {description}
        </p>
      ) : null}

      {children({
        id,
        "aria-describedby": describedBy,
        "aria-invalid": error
          ? true
          : undefined,
      })}

      {error ? (
        <p
          className="text-xs font-medium leading-5 text-ui-danger"
          id={errorId ?? undefined}
          role="alert"
        >
          {error}
        </p>
      ) : null}
    </div>
  );
}