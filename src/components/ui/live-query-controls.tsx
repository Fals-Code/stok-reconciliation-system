"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useState,
  useTransition,
} from "react";
import {
  usePathname,
  useRouter,
  useSearchParams,
} from "next/navigation";

import {
  Input,
  Select,
} from "@/components/ui/controls";
import {
  cx,
} from "@/components/ui/cx";

export type LiveQueryOption = {
  value: string;
  label: string;
};

type LiveQueryBaseField = {
  name: string;
  label?: string;
  ariaLabel: string;
  className?: string;
};

export type LiveQuerySearchField = LiveQueryBaseField & {
  kind: "search";
  placeholder: string;
};

export type LiveQueryTextField = LiveQueryBaseField & {
  kind: "text";
  placeholder?: string;
};

export type LiveQueryDateTimeField = LiveQueryBaseField & {
  kind: "datetime-local";
};

export type LiveQuerySelectField = LiveQueryBaseField & {
  kind: "select";
  options: readonly LiveQueryOption[];
};

export type LiveQueryFieldConfig =
  | LiveQuerySearchField
  | LiveQueryTextField
  | LiveQueryDateTimeField
  | LiveQuerySelectField;

export type LiveQueryControlsProps = {
  fields: readonly LiveQueryFieldConfig[];
  advancedFields?: readonly LiveQueryFieldConfig[];
  contextKeys?: readonly string[];
  resetKeys?: readonly string[];
  debounceMs?: number;
  clearLabel?: string;
  advancedLabel?: string;
  className?: string;
  bare?: boolean;
  compact?: boolean;
  hideIdleStatus?: boolean;
  hideInactiveClear?: boolean;
};

function normalize(value: string) {
  return value.trim();
}

function isDebouncedField(field: LiveQueryFieldConfig) {
  return field.kind === "search" || field.kind === "text";
}

function fieldNames(
  fields: readonly LiveQueryFieldConfig[],
  advancedFields: readonly LiveQueryFieldConfig[],
) {
  return [...fields, ...advancedFields].map((field) => field.name);
}

export function LiveQueryControls({
  fields,
  advancedFields = [],
  contextKeys = [],
  resetKeys = ["cursor", "direction", "page"],
  debounceMs = 300,
  clearLabel = "Hapus filter",
  advancedLabel = "Filter lanjutan",
  className,
  bare = false,
  compact = false,
  hideIdleStatus = false,
  hideInactiveClear = false,
}: LiveQueryControlsProps) {
  const pathname = usePathname();
  const router = useRouter();
  const searchParams = useSearchParams();

  const controlledNamesSignature = fieldNames(
    fields,
    advancedFields,
  ).join("\u001f");

  const controlledNames = useMemo(
    () =>
      controlledNamesSignature
        ? controlledNamesSignature.split("\u001f")
        : [],
    [controlledNamesSignature],
  );

  const debouncedNamesSignature = [
    ...fields,
    ...advancedFields,
  ]
    .filter(isDebouncedField)
    .map((field) => field.name)
    .join("\u001f");

  const debouncedNames = useMemo(
    () =>
      debouncedNamesSignature
        ? debouncedNamesSignature.split("\u001f")
        : [],
    [debouncedNamesSignature],
  );

  const immediateNamesSignature = [
    ...fields,
    ...advancedFields,
  ]
    .filter((field) => !isDebouncedField(field))
    .map((field) => field.name)
    .join("\u001f");

  const immediateNames = useMemo(
    () =>
      immediateNamesSignature
        ? immediateNamesSignature.split("\u001f")
        : [],
    [immediateNamesSignature],
  );

  const resetKeysSignature = resetKeys.join("\u001f");

  const stableResetKeys = useMemo(
    () =>
      resetKeysSignature
        ? resetKeysSignature.split("\u001f")
        : [],
    [resetKeysSignature],
  );

  const canonicalValues = useMemo(() => {
    const values: Record<string, string> = {};

    for (const name of controlledNames) {
      values[name] = searchParams.get(name) ?? "";
    }

    return values;
  }, [controlledNames, searchParams]);

  const canonicalSignature = useMemo(
    () =>
      controlledNames
        .map((name) => `${name}=${normalize(canonicalValues[name] ?? "")}`)
        .join("&"),
    [canonicalValues, controlledNames],
  );

  const [values, setValues] =
    useState<Record<string, string>>(canonicalValues);
  const [isPending, startTransition] =
    useTransition();

  const [prevSignature, setPrevSignature] = useState(canonicalSignature);

  if (canonicalSignature !== prevSignature) {
    setValues(canonicalValues);
    setPrevSignature(canonicalSignature);
  }

  const replaceUrl = useCallback(
    (nextValues: Record<string, string>) => {
      const params =
        new URLSearchParams(searchParams.toString());

      for (const name of controlledNames) {
        params.delete(name);
      }

      for (const name of controlledNames) {
        const value = normalize(nextValues[name] ?? "");

        if (value) {
          params.set(name, value);
        }
      }

      for (const name of stableResetKeys) {
        params.delete(name);
      }

      const nextQuery = params.toString();
      const nextHref = nextQuery
        ? `${pathname}?${nextQuery}`
        : pathname;

      const currentQuery = searchParams.toString();
      const currentHref = currentQuery
        ? `${pathname}?${currentQuery}`
        : pathname;

      if (nextHref === currentHref) {
        return;
      }

      startTransition(() => {
        router.replace(nextHref, {
          scroll: false,
        });
      });
    },
    [
      controlledNames,
      pathname,
      stableResetKeys,
      router,
      searchParams,
    ],
  );

  useEffect(() => {
    const hasUnsyncedDebouncedValue =
      debouncedNames.some(
        (name) =>
          normalize(values[name] ?? "") !==
          normalize(canonicalValues[name] ?? ""),
      );

    if (!hasUnsyncedDebouncedValue) {
      return;
    }

    const timeout = window.setTimeout(() => {
      replaceUrl(values);
    }, debounceMs);

    return () => {
      window.clearTimeout(timeout);
    };
  }, [
    canonicalValues,
    debounceMs,
    debouncedNames,
    replaceUrl,
    values,
  ]);

  function updateValue(name: string, value: string) {
    const nextValues = {
      ...values,
      [name]: value,
    };

    setValues(nextValues);

    if (immediateNames.includes(name)) {
      replaceUrl(nextValues);
    }
  }

  function clearField(name: string) {
    const nextValues = {
      ...values,
      [name]: "",
    };

    setValues(nextValues);
    replaceUrl(nextValues);
  }

  function clearAll() {
    const nextValues: Record<string, string> = {};

    for (const name of controlledNames) {
      nextValues[name] = "";
    }

    setValues(nextValues);
    replaceUrl(nextValues);
  }

  const hasActiveValue = controlledNames.some((name) =>
    Boolean(normalize(values[name] ?? "")),
  );
  const hasUnsyncedValues =
    controlledNames.some(
      (name) =>
        normalize(values[name] ?? "") !==
        normalize(canonicalValues[name] ?? ""),
    );
  const isUpdating =
    isPending || hasUnsyncedValues;

  const hasAdvancedValue =
    advancedFields.some((field) =>
      Boolean(normalize(values[field.name] ?? "")),
    );
  const [advancedOpen, setAdvancedOpen] =
    useState(hasAdvancedValue);
  const [prevHasAdvanced, setPrevHasAdvanced] =
    useState(hasAdvancedValue);

  if (hasAdvancedValue && !prevHasAdvanced) {
    setAdvancedOpen(true);
    setPrevHasAdvanced(true);
  } else if (!hasAdvancedValue && prevHasAdvanced) {
    setPrevHasAdvanced(false);
  }

  function renderField(field: LiveQueryFieldConfig) {
    const value = values[field.name] ?? "";

    if (field.kind === "select") {
      const select = (
        <Select
          aria-label={field.ariaLabel}
          className={field.className}
          name={field.name}
          onChange={(event) => {
            updateValue(field.name, event.target.value);
          }}
          value={value}
        >
          {field.options.map((option) => (
            <option
              key={`${field.name}:${option.value}`}
              value={option.value}
            >
              {option.label}
            </option>
          ))}
        </Select>
      );

      if (!field.label) {
        return (
          <div className="min-w-0" key={field.name}>
            {select}
          </div>
        );
      }

      return (
        <label
          className="grid min-w-0 gap-2 text-sm font-semibold text-ui-text"
          key={field.name}
        >
          {field.label}
          {select}
        </label>
      );
    }

    const input = (
      <div className="relative min-w-0">
        {field.kind === "search" ? (
          <span
            aria-hidden="true"
            className="pointer-events-none absolute inset-y-0 left-3 flex items-center text-ui-text-muted"
          >
            <svg
              className="h-[18px] w-[18px]"
              fill="none"
              viewBox="0 0 24 24"
            >
              <path
                d="m21 21-4.35-4.35m2.35-5.15a7.5 7.5 0 1 1-15 0 7.5 7.5 0 0 1 15 0Z"
                stroke="currentColor"
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth="1.75"
              />
            </svg>
          </span>
        ) : null}

        <Input
          aria-label={field.ariaLabel}
          className={cx(
            field.kind === "search" && "pl-10",
            Boolean(value) && field.kind !== "datetime-local" && "pr-20",
            field.className,
          )}
          name={field.name}
          onChange={(event) => {
            updateValue(field.name, event.target.value);
          }}
          placeholder={
            field.kind === "search" || field.kind === "text"
              ? field.placeholder
              : undefined
          }
          type={field.kind}
          value={value}
        />

        {value && field.kind !== "datetime-local" ? (
          <button
            aria-label={`Hapus ${field.ariaLabel.toLowerCase()}`}
            className="absolute inset-y-0 right-2 my-auto h-8 rounded-[var(--ui-radius-sm)] px-2 text-xs font-semibold text-ui-text-muted hover:bg-ui-surface-subtle hover:text-ui-text"
            onClick={() => {
              clearField(field.name);
            }}
            type="button"
          >
            Hapus
          </button>
        ) : null}
      </div>
    );

    if (!field.label) {
      return (
        <div className="min-w-0" key={field.name}>
          {input}
        </div>
      );
    }

    return (
      <label
        className="grid min-w-0 gap-2 text-sm font-semibold text-ui-text"
        key={field.name}
      >
        {field.label}
        {input}
      </label>
    );
  }

  return (
    <div
      aria-busy={isUpdating}
      className={cx(
        bare
          ? "bg-transparent p-0"
          : compact
            ? "rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface px-3 py-2.5"
            : "rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface p-4 shadow-[var(--ui-shadow-sm)]",
        className,
      )}
      data-ui-live-query-controls
    >
      {contextKeys.map((name) => {
        const value =
          searchParams.get(name)?.trim() ?? "";

        return value ? (
          <input
            key={name}
            name={name}
            type="hidden"
            value={value}
          />
        ) : null;
      })}

      <div className={bare ? (fields.length === 3 ? "grid gap-2 sm:grid-cols-[minmax(16rem,1fr)_11rem_11rem]" : "grid gap-2 sm:grid-cols-[minmax(16rem,1fr)_14rem]") : compact ? "grid gap-2 sm:grid-cols-2 lg:grid-cols-4" : "grid gap-3 sm:grid-cols-2 lg:grid-cols-4"}>
        {fields.map(renderField)}
      </div>

      {advancedFields.length > 0 ? (
        <details
          className="mt-4 border-t border-ui-border pt-4"
          onToggle={(event) => {
            setAdvancedOpen(event.currentTarget.open);
          }}
          open={advancedOpen}
        >
          <summary className="cursor-pointer text-sm font-semibold text-ui-text">
            {advancedLabel}
          </summary>

          <div className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            {advancedFields.map(renderField)}
          </div>
        </details>
      ) : null}

      {(!hideIdleStatus || isUpdating || hasActiveValue) ? (
        <div className={compact ? "mt-1.5 flex min-h-6 items-center justify-between gap-3" : "mt-3 flex min-h-8 items-center justify-between gap-3"}>
          <p
            aria-live="polite"
            className="text-xs text-ui-text-muted"
            role="status"
          >
            {isUpdating
              ? "Memperbarui hasil..."
              : hideIdleStatus
                ? ""
                : "Hasil diperbarui otomatis"}
          </p>

          {!hideInactiveClear || hasActiveValue ? (
            <button
              className="shrink-0 rounded-[var(--ui-radius-sm)] px-2.5 py-2 text-sm font-semibold text-ui-text-muted hover:bg-ui-surface-subtle hover:text-ui-text"
              onClick={clearAll}
              type="button"
            >
              {clearLabel}
            </button>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}
