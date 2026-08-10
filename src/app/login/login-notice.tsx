"use client";

import {
  useEffect,
  useState,
  type ReactNode,
} from "react";

import {
  Alert,
  type AlertTone,
} from "@/components/ui";

export function LoginNotice({
  title,
  children,
  tone,
  dismissAfterMs,
}: {
  title: ReactNode;
  children: ReactNode;
  tone: AlertTone;
  dismissAfterMs?: number;
}) {
  const [visible, setVisible] =
    useState(true);

  useEffect(() => {
    if (!dismissAfterMs) {
      return;
    }

    const timer =
      window.setTimeout(
        () => {
          setVisible(false);

          const url =
            new URL(
              window.location.href,
            );

          url.searchParams.delete(
            "error",
          );

          url.searchParams.delete(
            "message",
          );

          const nextUrl =
            `${url.pathname}` +
            `${
              url.search
                ? url.search
                : ""
            }`;

          window.history.replaceState(
            window.history.state,
            "",
            nextUrl,
          );
        },
        dismissAfterMs,
      );

    return () => {
      window.clearTimeout(
        timer,
      );
    };
  }, [dismissAfterMs]);

  if (!visible) {
    return null;
  }

  return (
    <Alert
      className="mt-5"
      title={title}
      tone={tone}
    >
      {children}
    </Alert>
  );
}