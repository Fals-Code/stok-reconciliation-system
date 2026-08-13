const INTERNAL_ROUTE_ORIGIN = "http://internal.local";

export type SafeInternalRouteOptions = {
  allowedPathnames?: readonly string[];
};

export function isSafeInternalRoute(
  value: string | null | undefined,
): value is string {
  if (!value) return false;

  const candidate = value.trim();

  if (!candidate.startsWith("/") || candidate.startsWith("//")) {
    return false;
  }

  if (
    candidate.includes("\\") ||
    /[\u0000-\u001F\u007F]/.test(candidate)
  ) {
    return false;
  }

  try {
    return new URL(candidate, INTERNAL_ROUTE_ORIGIN).origin === INTERNAL_ROUTE_ORIGIN;
  } catch {
    return false;
  }
}

export function safeInternalRoute(
  value: string | null | undefined,
  fallback: string,
  options: SafeInternalRouteOptions = {},
) {
  if (!isSafeInternalRoute(value)) return fallback;

  const parsed = new URL(value.trim(), INTERNAL_ROUTE_ORIGIN);

  if (
    options.allowedPathnames &&
    !options.allowedPathnames.includes(parsed.pathname)
  ) {
    return fallback;
  }

  return `${parsed.pathname}${parsed.search}${parsed.hash}`;
}
