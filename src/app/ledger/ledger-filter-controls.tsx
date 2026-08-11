"use client";

import {
  LiveQueryControls,
  type LiveQueryFieldConfig,
} from "@/components/ui/live-query-controls";

const fields: readonly LiveQueryFieldConfig[] = [
  {
    kind: "search",
    name: "productSku",
    label: "Produk / SKU",
    ariaLabel: "Cari produk atau SKU",
    placeholder: "Cari SKU",
  },
  {
    kind: "search",
    name: "batchCode",
    label: "Kode Batch",
    ariaLabel: "Cari kode batch",
    placeholder: "Cari batch",
  },
  {
    kind: "select",
    name: "transactionType",
    label: "Jenis Perubahan",
    ariaLabel: "Filter jenis perubahan",
    options: [
      { value: "", label: "Semua perubahan" },
      { value: "INITIAL_BALANCE", label: "Saldo Awal" },
      { value: "RECEIPT", label: "Barang Masuk" },
      { value: "MARKETPLACE_OUTBOUND", label: "Barang Keluar Marketplace" },
      { value: "MANUAL_OUTBOUND", label: "Barang Keluar Manual" },
      { value: "RETURN_SELLABLE_INBOUND", label: "Retur Layak Dijual" },
      { value: "DISPOSAL", label: "Barang Rusak / Kedaluwarsa" },
      { value: "STOCKTAKE_ADJUSTMENT", label: "Penyesuaian Hasil Hitung" },
      { value: "REVERSAL", label: "Pembatalan Transaksi" },
    ],
  },
  {
    kind: "search",
    name: "sourceRef",
    label: "Nomor Referensi",
    ariaLabel: "Cari nomor referensi",
    placeholder: "Cari referensi",
  },
  {
    kind: "datetime-local",
    name: "occurredFrom",
    label: "Waktu kejadian dari",
    ariaLabel: "Waktu kejadian dari",
  },
  {
    kind: "datetime-local",
    name: "occurredTo",
    label: "Waktu kejadian sampai",
    ariaLabel: "Waktu kejadian sampai",
  },
];

const advancedFields: readonly LiveQueryFieldConfig[] = [
  {
    kind: "text",
    name: "reason",
    label: "Alasan",
    ariaLabel: "Filter alasan",
  },
  {
    kind: "text",
    name: "channel",
    label: "Kanal / Sumber",
    ariaLabel: "Filter kanal atau sumber",
  },
  {
    kind: "select",
    name: "sourceType",
    label: "Sumber transaksi",
    ariaLabel: "Filter sumber transaksi",
    options: [
      { value: "", label: "Semua sumber" },
      { value: "OPENING_BALANCE_CUTOVER", label: "Saldo Awal" },
      { value: "RECEIPT", label: "Barang Masuk" },
      { value: "MANUAL_OUTBOUND", label: "Barang Keluar Manual" },
      { value: "MARKETPLACE_SHIPMENT", label: "Pengiriman Marketplace" },
      { value: "RETURN_RECEIPT", label: "Penerimaan Retur" },
      { value: "RETURN_INSPECTION", label: "Pemeriksaan Retur" },
      { value: "STOCKTAKE", label: "Hitung Stok" },
      { value: "STOCK_TRANSACTION_REVERSAL", label: "Pembatalan Transaksi" },
    ],
  },
  {
    kind: "text",
    name: "actorProcess",
    label: "Dilakukan oleh",
    ariaLabel: "Filter pelaksana atau proses",
  },
  {
    kind: "datetime-local",
    name: "recordedFrom",
    label: "Waktu dicatat dari",
    ariaLabel: "Waktu dicatat dari",
  },
  {
    kind: "datetime-local",
    name: "recordedTo",
    label: "Waktu dicatat sampai",
    ariaLabel: "Waktu dicatat sampai",
  },
  {
    kind: "select",
    name: "bucket",
    label: "Kondisi Stok",
    ariaLabel: "Filter kondisi stok",
    options: [
      { value: "", label: "Semua kondisi" },
      { value: "SELLABLE", label: "Layak Dijual" },
      { value: "QUARANTINE", label: "Ditahan" },
      { value: "DAMAGED", label: "Rusak" },
    ],
  },
  {
    kind: "select",
    name: "quantityDirection",
    label: "Arah Jumlah",
    ariaLabel: "Filter arah jumlah",
    options: [
      { value: "", label: "Semua arah" },
      { value: "IN", label: "Bertambah" },
      { value: "OUT", label: "Berkurang" },
    ],
  },
  {
    kind: "select",
    name: "reversalState",
    label: "Status Pembatalan",
    ariaLabel: "Filter status pembatalan",
    options: [
      { value: "", label: "Semua status" },
      { value: "NOT_REVERSED", label: "Belum dibatalkan" },
      { value: "PARTIALLY_REVERSED", label: "Sebagian dibatalkan" },
      { value: "FULLY_REVERSED", label: "Sudah dibatalkan" },
      { value: "REVERSAL", label: "Transaksi pembatalan" },
    ],
  },
];

export function LedgerFilterControls() {
  return (
    <LiveQueryControls
      advancedFields={advancedFields}
      className="mt-6"
      contextKeys={["productId", "batchId"]}
      fields={fields}
    />
  );
}