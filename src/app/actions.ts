"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireAdminSession } from "@/lib/auth";
import { callRpc } from "@/lib/supabase-rest";

const RECONCILIATION_CHECK_CODES = [
  "LEDGER_BATCH_PROJECTION",
  "BATCH_PRODUCT_PROJECTION",
  "RESERVATION_CONSISTENCY",
  "MARKETPLACE_ALLOCATION_CONSISTENCY",
  "RETURN_RECEIPT_CONSISTENCY",
  "RETURN_INSPECTION_CONSISTENCY",
  "DUPLICATE_SOURCE_EFFECT",
  "IMPOSSIBLE_PROJECTION_STATE",
] as const;

function required(formData: FormData, key: string) {
  const value = formData.get(key);

  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`${key} wajib diisi.`);
  }

  return value.trim();
}

function errorMessage(error: unknown) {
  return error instanceof Error
    ? error.message
    : "Terjadi kesalahan yang tidak diketahui.";
}

function reconciliationErrorMessage(error: unknown) {
  const raw = errorMessage(error);
  const messages: Record<string, string> = {
    RECONCILIATION_CHECKS_REQUIRED:
      "Pilih minimal satu pemeriksaan rekonsiliasi.",
    RECONCILIATION_CHECK_CODE_DUPLICATE:
      "Daftar pemeriksaan mengandung kode duplikat.",
    RECONCILIATION_CHECK_NOT_SUPPORTED:
      "Terdapat pemeriksaan yang belum didukung.",
    RECONCILIATION_SCOPE_NOT_SUPPORTED:
      "Scope rekonsiliasi selain seluruh organisasi belum didukung.",
    IDEMPOTENCY_KEY_REUSED:
      "Permintaan rekonsiliasi memakai referensi yang sudah digunakan.",
    IDEMPOTENCY_COMMAND_IN_PROGRESS:
      "Permintaan rekonsiliasi yang sama masih diproses.",
    ORGANIZATION_ACCESS_DENIED:
      "Rekonsiliasi tidak dapat dijalankan untuk organisasi lain.",
    AUTHENTICATION_REQUIRED:
      "Sesi Admin sudah berakhir. Silakan login kembali.",
    AUTH_SESSION_REQUIRED:
      "Sesi Admin sudah berakhir. Silakan login kembali.",
  };

  const matched = Object.entries(messages).find(([code]) =>
    raw.includes(code),
  );

  return matched ? matched[1] : raw;
}

function reconciliationCheckCodes(formData: FormData) {
  const values = formData
    .getAll("checkCodes")
    .filter((value): value is string => typeof value === "string")
    .map((value) => value.trim().toUpperCase())
    .filter(Boolean);

  if (values.length === 0) {
    throw new Error("RECONCILIATION_CHECKS_REQUIRED");
  }

  if (new Set(values).size !== values.length) {
    throw new Error("RECONCILIATION_CHECK_CODE_DUPLICATE");
  }

  const supported = new Set<string>(RECONCILIATION_CHECK_CODES);

  if (values.some((value) => !supported.has(value))) {
    throw new Error("RECONCILIATION_CHECK_NOT_SUPPORTED");
  }

  return values;
}

export async function runReconciliationAction(formData: FormData) {
  const session = await requireAdminSession();
  let message: string;
  let kind: "success" | "error" = "success";

  try {
    const checkCodes = reconciliationCheckCodes(formData);
    const idempotencyKey = required(formData, "idempotencyKey");

    const result = await callRpc<{
      status: string;
      integrityStatus: string;
      runId: string;
      runNo: string;
      ruleSetVersion: string;
      ledgerSeqFrom: number;
      ledgerSeqTo: number;
      checkCount: number;
      issueCount: number;
    }>("run_reconciliation", {
      p_organization_id: session.profile.organization_id,
      p_idempotency_key: idempotencyKey,
      p_check_codes: checkCodes,
      p_scope: {},
      p_metadata: {
        source: "reconciliation-admin-ui",
        version: 1,
        actorUserId: session.user.id,
      },
    });

    message =
      `${result.runNo} selesai dengan status ${result.integrityStatus}. ` +
      `Boundary ledger ${result.ledgerSeqFrom}-${result.ledgerSeqTo}, ` +
      `${result.issueCount} issue dari ${result.checkCount} check.`;

    revalidatePath("/stock-issues");
    revalidatePath("/reconciliation");
  } catch (error) {
    kind = "error";
    message = reconciliationErrorMessage(error);
  }

  const params = new URLSearchParams({ [kind]: message });
  redirect(`/stock-issues?${params.toString()}`);
}
