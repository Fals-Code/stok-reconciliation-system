import Link from "next/link";

type PageContextBarProps = {
  eyebrow: string;
  title: string;
  backHref: string;
  backLabel: string;
  maxWidth?: "max-w-6xl" | "max-w-[1500px]";
};

export default function PageContextBar({
  eyebrow,
  title,
  backHref,
  backLabel,
  maxWidth = "max-w-6xl",
}: PageContextBarProps) {
  return (
    <div className="border-b border-ui-border bg-ui-surface">
      <div
        className={`mx-auto flex ${maxWidth} flex-col gap-3 px-5 py-4 sm:flex-row sm:items-center sm:justify-between lg:px-8`}
      >
        <div className="min-w-0">
          <p className="font-mono text-[0.65rem] uppercase tracking-[0.18em] text-emerald-300">
            {eyebrow}
          </p>
          <p className="mt-1 truncate text-sm text-ui-text-muted">{title}</p>
        </div>

        <Link
          className="inline-flex w-fit shrink-0 items-center rounded-[var(--ui-radius-md)] border border-ui-border px-3 py-2 text-sm text-ui-text-muted transition hover:border-ui-primary hover:bg-ui-surface-subtle hover:text-ui-text"
          href={backHref}
        >
          {backLabel}
        </Link>
      </div>
    </div>
  );
}