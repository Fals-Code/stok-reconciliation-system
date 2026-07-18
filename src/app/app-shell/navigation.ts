export type AppNavItem = {
  href: string;
  label: string;
  shortLabel: string;
  description: string;
};

export type AppNavSection = {
  label: string;
  items: readonly AppNavItem[];
};

export const APP_NAV_SECTIONS = [
  {
    label: "Operasional",
    items: [
      {
        href: "/",
        label: "Dashboard",
        shortLabel: "DB",
        description: "Ringkasan stok dan transaksi",
      },
      {
        href: "/marketplace",
        label: "Marketplace",
        shortLabel: "MP",
        description: "Reservasi dan shipment",
      },
      {
        href: "/returns",
        label: "Retur",
        shortLabel: "RT",
        description: "Penerimaan dan inspeksi",
      },
    ],
  },
  {
    label: "Kontrol stok",
    items: [
      {
        href: "/stocktakes",
        label: "Stok Opname",
        shortLabel: "SO",
        description: "Hitung fisik dan adjustment",
      },
      {
        href: "/entry-corrections",
        label: "Koreksi Entri",
        shortLabel: "KE",
        description: "Preview dan reversal transaksi",
      },
      {
        href: "/reconciliation",
        label: "Rekonsiliasi",
        shortLabel: "RK",
        description: "Pemeriksaan integritas stok",
      },
    ],
  },
  {
    label: "Monitoring",
    items: [
      {
        href: "/notifications/operations",
        label: "Notification Operations",
        shortLabel: "NO",
        description: "Evaluator dan outbox",
      },
      {
        href: "/notifications",
        label: "Notification Center",
        shortLabel: "NT",
        description: "Alert dan tindak lanjut",
      },
    ],
  },
] as const satisfies readonly AppNavSection[];

export function isNavItemActive(pathname: string, href: string) {
  if (href === "/") {
    return pathname === "/";
  }

  return pathname === href || pathname.startsWith(`${href}/`);
}

export function findActiveNavItem(pathname: string) {
  for (const section of APP_NAV_SECTIONS) {
    const item = section.items.find((candidate) =>
      isNavItemActive(pathname, candidate.href),
    );

    if (item) {
      return {
        sectionLabel: section.label,
        item,
      };
    }
  }

  return null;
}