"use client";

import { useMemo, useState } from "react";

export type ReturnSourceOption = {
  id: string;
  label: string;
  channelCode: string;
  orderRef: string;
  productId: string;
  sourceLineRef: string;
};

export type ReturnReceiptSourceOption = {
  id: string;
  label: string;
  returnItemId: string;
  marketplaceShipAllocationId: string | null;
};

export function ReturnSourceSelect({
  options,
}: {
  options: ReturnSourceOption[];
}) {
  const [selectedId, setSelectedId] = useState("");
  const selected = useMemo(
    () => options.find((option) => option.id === selectedId),
    [options, selectedId],
  );

  return (
    <>
      <select
        value={selectedId}
        onChange={(event) => setSelectedId(event.target.value)}
        required
        disabled={options.length === 0}
      >
        <option value="" disabled>
          {options.length === 0
            ? "Belum ada shipment yang dapat diretur"
            : "Pilih item shipment"}
        </option>
        {options.map((option) => (
          <option key={option.id} value={option.id}>
            {option.label}
          </option>
        ))}
      </select>
      <input type="hidden" name="channelCode" value={selected?.channelCode ?? ""} />
      <input type="hidden" name="orderRef" value={selected?.orderRef ?? ""} />
      <input type="hidden" name="productId" value={selected?.productId ?? ""} />
      <input type="hidden" name="sourceLineRef" value={selected?.sourceLineRef ?? ""} />
    </>
  );
}

export function ReturnReceiptSourceSelect({
  options,
}: {
  options: ReturnReceiptSourceOption[];
}) {
  const [selectedId, setSelectedId] = useState("");
  const selected = useMemo(
    () => options.find((option) => option.id === selectedId),
    [options, selectedId],
  );

  return (
    <>
      <select
        value={selectedId}
        onChange={(event) => setSelectedId(event.target.value)}
        required
        disabled={options.length === 0}
      >
        <option value="" disabled>
          {options.length === 0
            ? "Tidak ada quantity yang menunggu penerimaan"
            : "Pilih item dan sumber batch"}
        </option>
        {options.map((option) => (
          <option key={option.id} value={option.id}>
            {option.label}
          </option>
        ))}
      </select>
      <input type="hidden" name="returnItemId" value={selected?.returnItemId ?? ""} />
      <input
        type="hidden"
        name="marketplaceShipAllocationId"
        value={selected?.marketplaceShipAllocationId ?? ""}
      />
    </>
  );
}