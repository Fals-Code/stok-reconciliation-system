"use server";

import { redirect } from "next/navigation";
import { logoutSession, signInWithPassword } from "@/lib/auth";

function required(formData: FormData, key: string) {
  const value = formData.get(key);

  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`${key} wajib diisi.`);
  }

  return value.trim();
}

export async function loginAction(formData: FormData) {
  let errorMessage: string | null = null;

  try {
    const email = required(formData, "email");
    const password = required(formData, "password");
    await signInWithPassword(email, password);
  } catch (error) {
    errorMessage =
      error instanceof Error ? error.message : "Login gagal karena kesalahan yang tidak diketahui.";
  }

  if (errorMessage) {
    const params = new URLSearchParams({ error: errorMessage });
    redirect(`/login?${params.toString()}`);
  }

  redirect("/");
}

export async function logoutAction() {
  await logoutSession();
  redirect("/login?message=Sesi+Admin+telah+diakhiri.");
}
