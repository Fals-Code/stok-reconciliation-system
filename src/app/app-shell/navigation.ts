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

/*
 * shortLabel dipertahankan sebagai compatibility bridge untuk shell lama.
 * Redesign shell berikutnya akan menggantinya dengan ikon aksesibel.
 */
export const APP_NAV_SECTIONS = [
  {
    label: "Utama",
    items: [
      {
        href: "/today",
        label: "Pusat Kendali",
        shortLabel: "PK",
        description: "Pekerjaan yang perlu ditangani hari ini",
      },
      {
        href: "/",
        label: "Ringkasan Stok",
        shortLabel: "RS",
        description: "Posisi stok dan aktivitas terbaru",
      },
    ],
  },
  {
    label: "Pekerjaan Gudang",
    items: [
      {
        href: "/manual-outbounds",
        label: "Barang Keluar",
        shortLabel: "BK",
        description: "Preview FEFO sebelum stok dikeluarkan",
      },
      {
        href: "/returns",
        label: "Retur",
        shortLabel: "RT",
        description: "Penerimaan, inspeksi, dan klaim retur",
      },
      {
        href: "/stock-disposals",
        label: "Rusak & Kedaluwarsa",
        shortLabel: "RD",
        description: "Catat pengeluaran stok yang tidak layak",
      },
      {
        href: "/marketplace",
        label: "Pesanan Marketplace",
        shortLabel: "PM",
        description: "Listing, reservasi, dan pengiriman",
      },
      {
        href: "/marketplace/import",
        label: "Impor Marketplace",
        shortLabel: "IM",
        description: "Periksa dan proses data CSV",
      },
    ],
  },
  {
    label: "Kontrol Stok",
    items: [
      {
        href: "/stocktakes",
        label: "Stok Opname",
        shortLabel: "SO",
        description: "Hitung fisik dan penyesuaian opname",
      },
      {
        href: "/reconciliation",
        label: "Rekonsiliasi",
        shortLabel: "RE",
        description: "Periksa integritas dan selisih stok",
      },
      {
        href: "/entry-corrections",
        label: "Koreksi Entri",
        shortLabel: "KE",
        description: "Preview dan reversal transaksi salah",
      },
      {
        href: "/opening-balances",
        label: "Saldo Awal",
        shortLabel: "SA",
        description: "Cutover dan verifikasi stok awal",
      },
      {
        href: "/ledger",
        label: "Riwayat Stok",
        shortLabel: "RS",
        description: "Telusuri pergerakan dan asal saldo",
      },
    ],
  },
  {
    label: "Data & Sistem",
    items: [
      {
        href: "/products",
        label: "Produk & Batch",
        shortLabel: "PB",
        description: "Kelola identitas produk dan batch",
      },
      {
        href: "/notifications",
        label: "Notifikasi",
        shortLabel: "NT",
        description: "Peringatan dan tindak lanjut aktif",
      },
      {
        href: "/notifications/operations",
        label: "Pemrosesan Notifikasi",
        shortLabel: "PN",
        description: "Periksa evaluasi dan antrean notifikasi",
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
