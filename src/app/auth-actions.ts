"use server";

import {
  redirect,
} from "next/navigation";

import {
  logoutSession,
  signInWithPassword,
} from "@/lib/auth";
import {
  safeInternalRoute,
} from "@/lib/safe-internal-route";

type LoginErrorCode =
  | "EMAIL_REQUIRED"
  | "EMAIL_FORMAT"
  | "PASSWORD_REQUIRED"
  | "CREDENTIALS_INVALID"
  | "ADMIN_INACTIVE"
  | "AUTH_UNAVAILABLE";

function fieldValue(
  formData: FormData,
  key: string,
) {
  const value =
    formData.get(key);

  if (typeof value !== "string") {
    return "";
  }

  return value.trim();
}

function isValidEmailShape(
  email: string,
) {
  if (
    email.length > 254 ||
    /\s/.test(email)
  ) {
    return false;
  }

  const at =
    email.indexOf("@");

  if (
    at <= 0 ||
    at !==
      email.lastIndexOf("@")
  ) {
    return false;
  }

  const domain =
    email.slice(at + 1);

  return (
    domain.length > 2 &&
    domain.includes(".") &&
    !domain.startsWith(".") &&
    !domain.endsWith(".")
  );
}

function loginFailure(
  code: LoginErrorCode,
  returnTo: string,
): never {
  const params = new URLSearchParams({ error: code });

  if (returnTo !== "/") {
    params.set("returnTo", returnTo);
  }

  redirect(`/login?${params.toString()}`);
}

export async function loginAction(
  formData: FormData,
) {
  const returnTo = safeInternalRoute(
    fieldValue(formData, "returnTo"),
    "/",
  );

  const email =
    fieldValue(
      formData,
      "email",
    ).toLowerCase();

  const passwordValue =
    formData.get("password");

  const password =
    typeof passwordValue ===
    "string"
      ? passwordValue
      : "";

  if (!email) {
    loginFailure(
      "EMAIL_REQUIRED",
      returnTo,
    );
  }

  if (
    !isValidEmailShape(email)
  ) {
    loginFailure(
      "EMAIL_FORMAT",
      returnTo,
    );
  }

  if (!password) {
    loginFailure(
      "PASSWORD_REQUIRED",
      returnTo,
    );
  }

  let failure:
    LoginErrorCode | null = null;

  try {
    await signInWithPassword(
      email,
      password,
    );
  } catch (error) {
    if (
      error instanceof Error &&
      error.message ===
        "Akun tidak memiliki akses Admin aktif."
    ) {
      failure =
        "ADMIN_INACTIVE";
    } else if (
      error instanceof TypeError ||
      (
        error instanceof Error &&
        error.message.includes(
          "belum dikonfigurasi",
        )
      )
    ) {
      failure =
        "AUTH_UNAVAILABLE";
    } else {
      /*
       * Sengaja generik.
       *
       * Jangan membedakan email tidak
       * terdaftar dan password salah.
       * Itu membuka account enumeration.
       */
      failure =
        "CREDENTIALS_INVALID";
    }
  }

  if (failure) {
    loginFailure(failure, returnTo);
  }

  redirect(returnTo);
}

export async function logoutAction() {
  await logoutSession();

  redirect(
    "/login?message=SIGNED_OUT",
  );
}
