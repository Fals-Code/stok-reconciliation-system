type WizardProgressProps = {
  ariaLabel: string;
  current: 1 | 2 | 3;
};

const steps = ["Isi Data", "Periksa", "Selesai"] as const;

export function WizardProgress({
  ariaLabel,
  current,
}: WizardProgressProps) {
  return (
    <ol
      aria-label={ariaLabel}
      className="flex w-full items-center"
    >
      {steps.map((label, index) => {
        const step = (index + 1) as 1 | 2 | 3;
        const active = step === current;

        return (
          <li
            className="flex min-w-0 flex-1 items-center last:flex-none"
            key={label}
          >
            <div
              aria-current={active ? "step" : undefined}
              className={[
                "inline-flex min-w-0 items-center gap-2 text-sm font-semibold",
                active
                  ? "text-ui-primary"
                  : "text-ui-text-muted",
              ].join(" ")}
            >
              <span
                aria-hidden="true"
                className={[
                  "inline-flex size-7 shrink-0 items-center justify-center rounded-full border text-xs font-bold",
                  active
                    ? "border-ui-primary bg-ui-primary text-ui-text-on-primary"
                    : "border-ui-border bg-ui-surface text-ui-text-muted",
                ].join(" ")}
              >
                {step}
              </span>
              <span className="truncate">{label}</span>
            </div>

            {step < 3 ? (
              <span
                aria-hidden="true"
                className="mx-3 h-px min-w-4 flex-1 bg-ui-border"
              />
            ) : null}
          </li>
        );
      })}
    </ol>
  );
}