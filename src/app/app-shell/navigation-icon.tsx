export type NavigationIconName =
  | "dashboard"
  | "task"
  | "outbound"
  | "return"
  | "disposal"
  | "marketplace"
  | "import"
  | "stocktake"
  | "reconciliation"
  | "correction"
  | "opening-balance"
  | "history"
  | "product"
  | "notification"
  | "notification-process";

const ICON_PATHS: Record<
  NavigationIconName,
  readonly string[]
> = {
  dashboard: [
    "M4 4h6v6H4z",
    "M14 4h6v10h-6z",
    "M4 14h6v6H4z",
    "M14 18h6v2h-6z",
  ],
  task: [
    "M4 6h1",
    "M9 6h11",
    "M4 12h1",
    "M9 12h11",
    "M4 18h1",
    "M9 18h11",
  ],
  outbound: [
    "M5 19 19 5",
    "M10 5h9v9",
  ],
  return: [
    "M9 7H5V3",
    "M5 7a8 8 0 1 1-1 9",
  ],
  disposal: [
    "M4 7h16",
    "M9 7V4h6v3",
    "M7 7l1 13h8l1-13",
    "M10 11v5",
    "M14 11v5",
  ],
  marketplace: [
    "M5 8h14l-1 12H6z",
    "M9 8V6a3 3 0 0 1 6 0v2",
  ],
  import: [
    "M12 16V4",
    "M7 9l5-5 5 5",
    "M5 20h14",
  ],
  stocktake: [
    "M9 5V3h6v2",
    "M7 5H5v16h14V5h-2",
    "M8 13l3 3 5-6",
  ],
  reconciliation: [
    "M12 3v18",
    "M5 6h14",
    "M5 6l-3 6h6z",
    "M19 6l-3 6h6z",
    "M8 21h8",
  ],
  correction: [
    "M9 7H5V3",
    "M5 7c2-2 4-3 7-3a8 8 0 0 1 7 12",
    "M19 16l-2-1",
    "M5 7l4 4",
  ],
  "opening-balance": [
    "M12 3 3 8l9 5 9-5z",
    "M5 12l7 4 7-4",
    "M5 16l7 4 7-4",
  ],
  history: [
    "M3 12a9 9 0 1 0 3-6",
    "M3 4v5h5",
    "M12 7v5l3 2",
  ],
  product: [
    "M4 7l8-4 8 4-8 4z",
    "M4 7v10l8 4 8-4V7",
    "M12 11v10",
  ],
  notification: [
    "M6 9a6 6 0 0 1 12 0v5l2 3H4l2-3z",
    "M10 20h4",
  ],
  "notification-process": [
    "M4 6h16",
    "M8 4v4",
    "M4 12h16",
    "M15 10v4",
    "M4 18h16",
    "M10 16v4",
  ],
};

export function NavigationIcon({
  className,
  name,
}: {
  className?: string;
  name: NavigationIconName;
}) {
  return (
    <svg
      aria-hidden="true"
      className={className}
      fill="none"
      focusable="false"
      viewBox="0 0 24 24"
    >
      {ICON_PATHS[name].map((path) => (
        <path
          d={path}
          key={path}
          stroke="currentColor"
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth="1.75"
        />
      ))}
    </svg>
  );
}
