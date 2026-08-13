"use client";

import {
  LiveQueryControls,
  type LiveQueryFieldConfig,
} from "@/components/ui/live-query-controls";

export type ProductStatusFilter =
  | "ALL"
  | "ACTIVE"
  | "ARCHIVED";

const fields: readonly LiveQueryFieldConfig[] = [
  {
    kind: "search",
    name: "q",
    ariaLabel: "Cari produk",
    placeholder: "Cari nama atau SKU",
  },
  {
    kind: "select",
    name: "status",
    ariaLabel: "Filter status produk",
    className: "lg:max-w-56",
    options: [
      {
        value: "",
        label: "Semua status",
      },
      {
        value: "ACTIVE",
        label: "Aktif",
      },
      {
        value: "ARCHIVED",
        label: "Tidak Aktif",
      },
    ],
  },
];

export function StockWorkspaceControls() {
  return (
    <LiveQueryControls
      className="shadow-none"
      bare
      compact
      hideIdleStatus
      hideInactiveClear
      fields={fields}
    />
  );
}