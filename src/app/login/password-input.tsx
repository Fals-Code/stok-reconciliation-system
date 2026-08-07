"use client";

import { useState } from "react";

import {
  IconButton,
  Input,
} from "@/components/ui";

export type PasswordInputProps = {
  id: string;
  name: string;
  autoComplete?: string;
  placeholder?: string;
  required?: boolean;
  "aria-describedby"?: string;
  "aria-invalid"?: boolean;
};

export function PasswordInput({
  id,
  name,
  autoComplete,
  placeholder,
  required,
  "aria-describedby": ariaDescribedBy,
  "aria-invalid": ariaInvalid,
}: PasswordInputProps) {
  const [visible, setVisible] =
    useState(false);

  return (
    <div className="relative">
      <Input
        aria-describedby={ariaDescribedBy}
        aria-invalid={ariaInvalid}
        autoComplete={autoComplete}
        className="pr-14"
        id={id}
        name={name}
        placeholder={placeholder}
        required={required}
        type={
          visible
            ? "text"
            : "password"
        }
      />

      <IconButton
        aria-pressed={visible}
        className="absolute inset-y-0 right-0 my-auto"
        label={
          visible
            ? "Sembunyikan password"
            : "Tampilkan password"
        }
        onClick={() =>
          setVisible(
            (current) => !current,
          )
        }
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
      </IconButton>
    </div>
  );
}