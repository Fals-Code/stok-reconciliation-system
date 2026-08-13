export type AppNavigationItem = {
  href: string;
  label: string;
  icon: "home" | "stock" | "orders" | "settings";
};

export const primaryNavigation: readonly AppNavigationItem[] = [
  {
    href: "/",
    label: "Beranda",
    icon: "home",
  },
  {
    href: "/products",
    label: "Stok",
    icon: "stock",
  },
  {
    href: "/marketplace",
    label: "Pesanan",
    icon: "orders",
  },
];

export const settingsNavigation: AppNavigationItem = {
  href: "/settings",
  label: "Pengaturan",
  icon: "settings",
};

export function getActiveNavHref(pathname: string): string | null {
  if (pathname === "/") {
    return "/";
  }

  if (
    pathname === "/products" ||
    pathname.startsWith("/products/") ||
    pathname === "/receipts" ||
    pathname.startsWith("/receipts/") ||
    pathname === "/manual-outbounds" ||
    pathname.startsWith("/manual-outbounds/") ||
    pathname === "/stock-disposals" ||
    pathname.startsWith("/stock-disposals/") ||
    pathname === "/stocktakes" ||
    pathname.startsWith("/stocktakes/") ||
    pathname === "/stock-issues" ||
    pathname.startsWith("/stock-issues/") ||
    pathname === "/reconciliation" ||
    pathname.startsWith("/reconciliation/") ||
    pathname === "/ledger" ||
    pathname.startsWith("/ledger/") ||
    pathname === "/entry-corrections" ||
    pathname.startsWith("/entry-corrections/")
  ) {
    return "/products";
  }

  if (
    pathname === "/marketplace/listings" ||
    pathname.startsWith("/marketplace/listings/") ||
    pathname === "/marketplace/import" ||
    pathname.startsWith("/marketplace/import/") ||
    pathname === "/marketplace/simulator" ||
    pathname.startsWith("/marketplace/simulator/") ||
    pathname === "/notifications/operations" ||
    pathname.startsWith("/notifications/operations/")
  ) {
    return "/settings";
  }

  if (
    pathname === "/marketplace" ||
    pathname.startsWith("/marketplace/") ||
    pathname === "/returns" ||
    pathname.startsWith("/returns/")
  ) {
    return "/marketplace";
  }

  if (
    pathname === "/settings" ||
    pathname.startsWith("/settings/") ||
    pathname === "/opening-balances" ||
    pathname.startsWith("/opening-balances/")
  ) {
    return "/settings";
  }

  return null;
}

export function isNavItemActive(itemHref: string, pathname: string): boolean {
  return getActiveNavHref(pathname) === itemHref;
}
