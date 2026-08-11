import Link from "next/link";

export function OrderWorkspaceTabs({
  active,
}: {
  active: "orders" | "returns";
}) {
  return (
    <nav
      aria-label="Bagian Pesanan"
      className="mt-5 inline-flex items-center gap-1 rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface-subtle p-1"
    >
      <Link
        aria-current={active === "orders" ? "page" : undefined}
        className={`rounded-[calc(var(--ui-radius-md)-2px)] px-3.5 py-2 text-sm font-semibold transition-colors motion-reduce:transition-none ${
          active === "orders"
            ? "bg-ui-primary text-white shadow-[var(--ui-shadow-sm)]"
            : "text-ui-text hover:bg-ui-surface hover:text-ui-primary"
        }`}
        href="/marketplace"
      >
        Pesanan
      </Link>

      <Link
        aria-current={active === "returns" ? "page" : undefined}
        className={`rounded-[calc(var(--ui-radius-md)-2px)] px-3.5 py-2 text-sm font-semibold transition-colors motion-reduce:transition-none ${
          active === "returns"
            ? "bg-ui-primary text-white shadow-[var(--ui-shadow-sm)]"
            : "text-ui-text hover:bg-ui-surface hover:text-ui-primary"
        }`}
        href="/returns"
      >
        Retur & Klaim
      </Link>
    </nav>
  );
}