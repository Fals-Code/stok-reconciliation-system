import "server-only";

import { getAdminSession } from "@/lib/auth";
import type { StocktakeListItem } from "@/lib/stocktakes/types";

const DEFAULT_LOCAL_URL = "http://127.0.0.1:54321";

function getConfig() {
  const url = (process.env.NEXT_PUBLIC_SUPABASE_URL ?? DEFAULT_LOCAL_URL).replace(
    /\/$/,
    "",
  );
  const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

  if (!publishableKey || publishableKey.includes("REPLACE_ME")) {
    throw new Error(
      "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY belum dikonfigurasi di .env.local.",
    );
  }

  return { url, publishableKey };
}

async function responseError(response: Response) {
  const raw = await response.text();

  if (!raw) {
    return `${response.status} ${response.statusText}`;
  }

  try {
    const parsed = JSON.parse(raw) as {
      message?: string;
      details?: string;
      hint?: string;
      code?: string;
    };

    return [parsed.message, parsed.details, parsed.hint, parsed.code]
      .filter(Boolean)
      .join(" | ");
  } catch {
    return raw;
  }
}

export async function getStocktakeList(): Promise<StocktakeListItem[]> {
  const session = await getAdminSession();

  if (!session) {
    throw new Error("AUTH_SESSION_REQUIRED");
  }

  const { url, publishableKey } = getConfig();
  const params = new URLSearchParams({
    organization_id: `eq.${session.profile.organization_id}`,
    select: "*",
    order: "updated_at.desc,created_at.desc",
  });

  const response = await fetch(`${url}/rest/v1/stocktake_list?${params}`, {
    headers: {
      apikey: publishableKey,
      Authorization: `Bearer ${session.accessToken}`,
      "Accept-Profile": "api",
    },
    cache: "no-store",
  });

  if (!response.ok) {
    throw new Error(await responseError(response));
  }

  return (await response.json()) as StocktakeListItem[];
}