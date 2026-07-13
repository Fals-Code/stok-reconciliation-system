"use client";

import { useEffect, useRef } from "react";

type CurrentDateTimeInputProps = {
  minimumEventAt?: string;
};

function toJakartaDateTimeLocal(value: Date) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Jakarta",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(value);

  const values = Object.fromEntries(
    parts.map((part) => [part.type, part.value]),
  );

  return `${values.year}-${values.month}-${values.day}T${values.hour}:${values.minute}`;
}

export function CurrentDateTimeInput({
  minimumEventAt,
}: CurrentDateTimeInputProps) {
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const input = inputRef.current;

    if (!input) {
      return;
    }

    const now = toJakartaDateTimeLocal(new Date());
    input.value = now;
    input.min =
      minimumEventAt && minimumEventAt <= now
        ? minimumEventAt
        : "";
  }, [minimumEventAt]);

  return (
    <>
      <input
        ref={inputRef}
        name="occurredAt"
        type="datetime-local"
        required
      />
      <span className="text-[0.68rem] font-normal text-slate-500">
        Default mengikuti waktu sekarang WIB
      </span>
    </>
  );
}