"use client";

import { useEffect } from "react";

export function StocktakePresentationFeedback({ shouldSanitize }: { shouldSanitize: boolean }) {
  useEffect(() => {
    if (!shouldSanitize) return;

    const url = new URL(window.location.href);
    const params = url.searchParams;
    params.delete("success");
    params.delete("error");
    params.delete("idempotencyKey");
    params.delete("notice");
    const search = params.toString();
    window.history.replaceState(window.history.state, "", `${url.pathname}${search ? `?${search}` : ""}${url.hash}`);
  }, [shouldSanitize]);

  return null;
}
