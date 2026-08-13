type PageSectionNavItem = {
  href: `#${string}`;
  label: string;
};

export default function PageSectionNav({
  items,
}: {
  items: readonly PageSectionNavItem[];
}) {
  return (
    <nav
      aria-label="Navigasi bagian halaman"
      className="sticky top-16 z-20 border-b border-ui-border bg-ui-surface backdrop-blur"
    >
      <div className="mx-auto flex max-w-[1500px] items-center gap-1 overflow-x-auto px-5 py-2 lg:px-8">
        {items.map((item) => (
          <a
            key={item.href}
            className="shrink-0 rounded-[var(--ui-radius-md)] px-3 py-2 text-sm text-ui-text-muted transition hover:bg-ui-surface-subtle hover:text-ui-text focus-visible:outline focus-visible:outline-2 focus-visible:outline-ui-primary"
            href={item.href}
          >
            {item.label}
          </a>
        ))}
      </div>
    </nav>
  );
}