"use client";

import {
  useState,
} from "react";

import {
  IconButton,
  Input,
  type InputProps,
} from "@/components/ui";

export type PasswordInputProps =
  Omit<
    InputProps,
    "type"
  >;

function EyeIcon({
  hidden,
}: {
  hidden: boolean;
}) {
  return (
    <svg
      aria-hidden="true"
      className="h-5 w-5"
      fill="none"
      focusable="false"
      viewBox="0 0 24 24"
    >
      {hidden ? (
        <>
          <path
            d="M3 3l18 18"
            stroke="currentColor"
            strokeLinecap="round"
            strokeWidth="1.7"
          />
          <path
            d="M10.6 10.7a2 2 0 0 0 2.7 2.7"
            stroke="currentColor"
            strokeLinecap="round"
            strokeWidth="1.7"
          />
          <path
            d="M9.9 5.2A10.7 10.7 0 0 1 12 5c5.4 0 9 7 9 7a15.8 15.8 0 0 1-2.5 3.4M6.6 6.7C4.3 8.2 3 12 3 12s3.6 7 9 7c1.1 0 2.2-.3 3.1-.7"
            stroke="currentColor"
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth="1.7"
          />
        </>
      ) : (
        <>
          <path
            d="M3 12s3.6-7 9-7 9 7 9 7-3.6 7-9 7-9-7-9-7Z"
            stroke="currentColor"
            strokeLinejoin="round"
            strokeWidth="1.7"
          />
          <circle
            cx="12"
            cy="12"
            r="2.5"
            stroke="currentColor"
            strokeWidth="1.7"
          />
        </>
      )}
    </svg>
  );
}

export function PasswordInput({
  className,
  ...props
}: PasswordInputProps) {
  const [visible, setVisible] =
    useState(false);

  return (
    <div className="relative">
      <Input
        {...props}
        className={[
          "pr-14",
          className,
        ]
          .filter(Boolean)
          .join(" ")}
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
        <EyeIcon hidden={visible} />
      </IconButton>
    </div>
  );
}