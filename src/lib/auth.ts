import "server-only";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";

const DEFAULT_LOCAL_URL = "http://127.0.0.1:54321";
const ACCESS_TOKEN_COOKIE = "glowlab_access_token";
const REFRESH_TOKEN_COOKIE = "glowlab_refresh_token";

export type AuthUser = {
  id: string;
  email?: string;
};

export type AdminProfile = {
  user_id: string;
  organization_id: string;
  display_name: string;
  employee_code: string | null;
  role_code: "ADMIN";
  organization_code: string;
  organization_name: string;
  timezone: string;
};

export type AdminSession = {
  accessToken: string;
  user: AuthUser;
  profile: AdminProfile;
};

type PasswordTokenResponse = {
  access_token: string;
  refresh_token: string;
  expires_in: number;
  user: AuthUser;
};

function getAuthConfig() {
  const url = (process.env.NEXT_PUBLIC_SUPABASE_URL ?? DEFAULT_LOCAL_URL).replace(/\/$/, "");
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
      msg?: string;
      message?: string;
      error_description?: string;
      error?: string;
    };

    return (
      parsed.msg ??
      parsed.message ??
      parsed.error_description ??
      parsed.error ??
      raw
    );
  } catch {
    return raw;
  }
}

async function authFetch(path: string, init: RequestInit = {}) {
  const { url, publishableKey } = getAuthConfig();
  const headers = new Headers(init.headers);

  headers.set("apikey", publishableKey);

  if (init.body) {
    headers.set("Content-Type", "application/json");
  }

  return fetch(`${url}${path}`, {
    ...init,
    headers,
    cache: "no-store",
  });
}

async function fetchAdminProfile(accessToken: string) {
  const { url, publishableKey } = getAuthConfig();
  const response = await fetch(
    `${url}/rest/v1/current_admin_profile?select=*`,
    {
      headers: {
        apikey: publishableKey,
        Authorization: `Bearer ${accessToken}`,
        "Accept-Profile": "api",
      },
      cache: "no-store",
    },
  );

  if (!response.ok) {
    throw new Error(await responseError(response));
  }

  const profiles = (await response.json()) as AdminProfile[];
  return profiles[0] ?? null;
}

async function setSessionCookies(tokens: PasswordTokenResponse) {
  const cookieStore = await cookies();
  const secure = process.env.NODE_ENV === "production";

  cookieStore.set(ACCESS_TOKEN_COOKIE, tokens.access_token, {
    httpOnly: true,
    sameSite: "lax",
    secure,
    path: "/",
    maxAge: Math.max(tokens.expires_in - 30, 60),
  });

  cookieStore.set(REFRESH_TOKEN_COOKIE, tokens.refresh_token, {
    httpOnly: true,
    sameSite: "lax",
    secure,
    path: "/",
    maxAge: 60 * 60 * 24 * 30,
  });
}

export async function signInWithPassword(email: string, password: string) {
  const normalizedEmail = email.trim().toLowerCase();

  if (!normalizedEmail || !password) {
    throw new Error("Email dan password wajib diisi.");
  }

  const response = await authFetch("/auth/v1/token?grant_type=password", {
    method: "POST",
    body: JSON.stringify({ email: normalizedEmail, password }),
  });

  if (!response.ok) {
    throw new Error(await responseError(response));
  }

  const tokens = (await response.json()) as PasswordTokenResponse;
  const profile = await fetchAdminProfile(tokens.access_token);

  if (!profile || profile.role_code !== "ADMIN") {
    throw new Error("Akun tidak memiliki akses Admin aktif.");
  }

  await setSessionCookies(tokens);

  return {
    accessToken: tokens.access_token,
    user: tokens.user,
    profile,
  } satisfies AdminSession;
}

export async function getAccessToken() {
  const cookieStore = await cookies();
  return cookieStore.get(ACCESS_TOKEN_COOKIE)?.value ?? null;
}

export async function getAdminSession(): Promise<AdminSession | null> {
  const accessToken = await getAccessToken();

  if (!accessToken) {
    return null;
  }

  const userResponse = await authFetch("/auth/v1/user", {
    headers: { Authorization: `Bearer ${accessToken}` },
  });

  if (!userResponse.ok) {
    return null;
  }

  const user = (await userResponse.json()) as AuthUser;
  const profile = await fetchAdminProfile(accessToken);

  if (!profile || profile.user_id !== user.id || profile.role_code !== "ADMIN") {
    return null;
  }

  return { accessToken, user, profile };
}

export async function requireAdminSession() {
  const session = await getAdminSession();

  if (!session) {
    redirect("/login?error=Sesi+Admin+diperlukan.");
  }

  return session;
}

export async function logoutSession() {
  const cookieStore = await cookies();
  const accessToken = cookieStore.get(ACCESS_TOKEN_COOKIE)?.value;

  if (accessToken) {
    await authFetch("/auth/v1/logout", {
      method: "POST",
      headers: { Authorization: `Bearer ${accessToken}` },
    }).catch(() => undefined);
  }

  cookieStore.delete(ACCESS_TOKEN_COOKIE);
  cookieStore.delete(REFRESH_TOKEN_COOKIE);
}
