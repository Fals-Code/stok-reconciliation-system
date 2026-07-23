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
      },      {
        href: "/manual-outbounds",
        label: "Barang Keluar",
        shortLabel: "BK",
        description: "Preview FEFO dan posting",
      },
      {
        href: "/stock-disposals",
        label: "Rusak & Kedaluwarsa",
        shortLabel: "RX",
        description: "Pemusnahan batch dan bucket",
      },
      {
        href: "/marketplace",
        label: "Marketplace",
        shortLabel: "MP",
        description: "Listing, reservasi, dan shipment",
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
        href: "/opening-balances",
        label: "Saldo Awal",
        shortLabel: "SA",
        description: "Cutover, verifikasi, dan audit",
      },
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
    label: "Master Data",
    items: [
      {
        href: "/products",
        label: "Produk",
        shortLabel: "PR",
        description: "Identitas Produk, status, dan audit",
      },
    ],
  },  {
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
