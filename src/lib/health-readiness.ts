import "server-only";

const DEFAULT_LOCAL_URL = "http://127.0.0.1:54321";
const READINESS_TIMEOUT_MS = 1_000;

function readinessConfig() {
  const url = (process.env.NEXT_PUBLIC_SUPABASE_URL ?? DEFAULT_LOCAL_URL).replace(/\/$/, "");
  const secret = process.env.SUPABASE_SECRET_KEY;

  if (!secret || secret.includes("REPLACE_ME")) return null;
  return { url, secret };
}

export async function isSupabaseReady() {
  const config = readinessConfig();
  if (!config) return false;

  try {
    const response = await fetch(
      `${config.url}/rest/v1/ledger_explorer?select=ledger_seq&limit=1`,
      {
        headers: {
          apikey: config.secret,
          Authorization: `Bearer ${config.secret}`,
          "Accept-Profile": "api",
        },
        cache: "no-store",
        signal: AbortSignal.timeout(READINESS_TIMEOUT_MS),
      },
    );

    return response.ok;
  } catch {
    return false;
  }
}
