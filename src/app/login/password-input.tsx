"use client";

import { useState } from "react";

export type PasswordInputProps = {
  id: string;
  name: string;
  autoComplete?: string;
  placeholder?: string;
  required?: boolean;
};

export function PasswordInput({
  id,
  name,
  autoComplete,
  placeholder,
  required,
}: PasswordInputProps) {
  const [visible, setVisible] = useState(false);

  return (
    <div className="relative">
      <input
        autoComplete={autoComplete}
        className="min-h-12 w-full rounded-[0.75rem] border border-[#c7d4cf] bg-[#f6f8f7] px-4 pr-12 text-sm text-[#172522] outline-none placeholder:text-[#788681] hover:border-[#8fa09a] focus-visible:border-[#1f6f64] focus-visible:ring-2 focus-visible:ring-[#2f8075] focus-visible:ring-offset-1"
        id={id}
        name={name}
        placeholder={placeholder}
        required={required}
        type={visible ? "text" : "password"}
      />

      <button
        aria-label={visible ? "Sembunyikan password" : "Tampilkan password"}
        aria-pressed={visible}
        className="absolute inset-y-0 right-1.5 my-auto grid h-9 w-9 place-items-center rounded-[0.625rem] text-[#6b7873] transition hover:bg-[#e7efec] hover:text-[#123f3a] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#2f8075]"
        onClick={() => setVisible((current) => !current)}
        type="button"
      >
        {visible ? (
          <svg
            aria-hidden="true"
            fill="none"
            height="18"
            viewBox="0 0 18 18"
            width="18"
          >
            <path
              d="M3 3L15 15"
              stroke="currentColor"
              strokeLinecap="round"
              strokeWidth="1.6"
            />
            <path
              d="M7.2 5.2A6.5 6.5 0 0 1 9 5C13.2 5 16 9 16 9a11.8 11.8 0 0 1-2.1 2.4M10.9 12.8A6.8 6.8 0 0 1 9 13C4.8 13 2 9 2 9a12.3 12.3 0 0 1 2.2-2.5"
              stroke="currentColor"
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth="1.6"
            />
          </svg>
        ) : (
          <svg
            aria-hidden="true"
            fill="none"
            height="18"
            viewBox="0 0 18 18"
            width="18"
          >
            <path
              d="M2 9S4.8 5 9 5s7 4 7 4-2.8 4-7 4-7-4-7-4Z"
              stroke="currentColor"
              strokeLinejoin="round"
              strokeWidth="1.6"
            />
            <circle
              cx="9"
              cy="9"
              r="2"
              stroke="currentColor"
              strokeWidth="1.6"
            />
          </svg>
        )}
      </button>
    </div>
  );
}