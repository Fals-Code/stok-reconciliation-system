import type { NavigationIconName } from "@/app/app-shell/navigation-icon";

export type AppNavItem = {
  href: string;
  label: string;
  description: string;
  icon: NavigationIconName;
};

export type AppNavSection = {
  label: string;
  items: readonly AppNavItem[];
};

export const APP_NAV_SECTIONS = [
  {
    label: "Utama",
    items: [
      {
        href: "/today",
        label: "Pusat Kendali",
        description: "Pekerjaan yang perlu ditangani hari ini",
        icon: "task",
      },
      {
        href: "/",
        label: "Ringkasan Stok",
        description: "Posisi stok dan aktivitas terbaru",
        icon: "dashboard",
      },
    ],
  },
  {
    label: "Pekerjaan Gudang",
    items: [
      {
        href: "/manual-outbounds",
        label: "Barang Keluar",
        description: "Preview FEFO sebelum stok dikeluarkan",
        icon: "outbound",
      },
      {
        href: "/returns",
        label: "Retur",
        description: "Penerimaan, inspeksi, dan klaim retur",
        icon: "return",
      },
      {
        href: "/stock-disposals",
        label: "Rusak & Kedaluwarsa",
        description: "Catat pengeluaran stok yang tidak layak",
        icon: "disposal",
      },
      {
        href: "/marketplace",
        label: "Pesanan Marketplace",
        description: "Listing, reservasi, dan pengiriman",
        icon: "marketplace",
      },
      {
        href: "/marketplace/import",
        label: "Impor Marketplace",
        description: "Periksa dan proses data CSV",
        icon: "import",
      },
    ],
  },
  {
    label: "Kontrol Stok",
    items: [
      {
        href: "/stocktakes",
        label: "Stok Opname",
        description: "Hitung fisik dan penyesuaian opname",
        icon: "stocktake",
      },
      {
        href: "/reconciliation",
        label: "Rekonsiliasi",
        description: "Periksa integritas dan selisih stok",
        icon: "reconciliation",
      },
      {
        href: "/entry-corrections",
        label: "Koreksi Entri",
        description: "Preview dan reversal transaksi salah",
        icon: "correction",
      },
      {
        href: "/opening-balances",
        label: "Saldo Awal",
        description: "Cutover dan verifikasi stok awal",
        icon: "opening-balance",
      },
      {
        href: "/ledger",
        label: "Riwayat Stok",
        description: "Telusuri pergerakan dan asal saldo",
        icon: "history",
      },
    ],
  },
  {
    label: "Data & Sistem",
    items: [
      {
        href: "/products",
        label: "Produk & Batch",
        description: "Kelola identitas produk dan batch",
        icon: "product",
      },
      {
        href: "/notifications",
        label: "Notifikasi",
        description: "Peringatan dan tindak lanjut aktif",
        icon: "notification",
      },
      {
        href: "/notifications/operations",
        label: "Pemrosesan Notifikasi",
        description: "Periksa evaluasi dan antrean notifikasi",
        icon: "notification-process",
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

export function getActiveNavHref(pathname: string) {
  let activeHref: string | null = null;

  for (const section of APP_NAV_SECTIONS) {
    for (const item of section.items) {
      if (!isNavItemActive(pathname, item.href)) {
        continue;
      }

      if (activeHref === null || item.href.length > activeHref.length) {
        activeHref = item.href;
      }
    }
  }

  return activeHref;
}

export function findActiveNavItem(pathname: string) {
  const activeHref = getActiveNavHref(pathname);

  if (!activeHref) {
    return null;
  }

  for (const section of APP_NAV_SECTIONS) {
    const item = section.items.find(
      (candidate) => candidate.href === activeHref,
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
