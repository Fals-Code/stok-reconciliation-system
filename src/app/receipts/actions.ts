"use server";

import {
  revalidatePath,
} from "next/cache";
import {
  redirect,
} from "next/navigation";

import {
  requireAdminSession,
} from "@/lib/auth";
import {
  callRpc,
} from "@/lib/supabase-rest";

type ReceiptLineInput = {
  productId: string;
  batchId?: string;
  batchCode?: string;
  expiryDate?: string;
  manufacturedDate?: string | null;
  quantity: number;
};

function required(
  formData: FormData,
  key: string,
) {
  const value =
    formData.get(key);

  if (
    typeof value !== "string" ||
    value.trim() === ""
  ) {
    throw new Error(
      `${key} wajib diisi.`,
    );
  }

  return value.trim();
}

function jakartaTimestamp(
  raw: string,
) {
  if (
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(
      raw,
    )
  ) {
    throw new Error(
      "Waktu penerimaan tidak valid.",
    );
  }

  return `${raw}:00+07:00`;
}

function parseLines(
  raw: string,
): ReceiptLineInput[] {
  let value: unknown;

  try {
    value = JSON.parse(raw);
  } catch {
    throw new Error(
      "Daftar barang penerimaan tidak valid.",
    );
  }

  if (
    !Array.isArray(value) ||
    value.length === 0
  ) {
    throw new Error(
      "Tambahkan minimal satu barang yang diterima.",
    );
  }

  const seen =
    new Set<string>();

  return value.map(
    (item, index) => {
      if (
        !item ||
        typeof item !== "object"
      ) {
        throw new Error(
          `Barang ke-${index + 1} tidak valid.`,
        );
      }

      const row =
        item as Record<
          string,
          unknown
        >;

      const productId =
        typeof row.productId ===
        "string"
          ? row.productId.trim()
          : "";

      const batchId =
        typeof row.batchId ===
          "string" &&
        row.batchId.trim()
          ? row.batchId.trim()
          : undefined;

      const batchCode =
        typeof row.batchCode ===
          "string" &&
        row.batchCode.trim()
          ? row.batchCode.trim()
          : undefined;

      const expiryDate =
        typeof row.expiryDate ===
          "string" &&
        row.expiryDate.trim()
          ? row.expiryDate.trim()
          : undefined;

      const manufacturedDate =
        typeof row.manufacturedDate ===
          "string" &&
        row.manufacturedDate.trim()
          ? row.manufacturedDate.trim()
          : null;

      const quantity =
        Number(row.quantity);

      if (!productId) {
        throw new Error(
          `Produk barang ke-${index + 1} belum dipilih.`,
        );
      }

      if (
        !batchId &&
        (!batchCode || !expiryDate)
      ) {
        throw new Error(
          `Batch barang ke-${index + 1} belum lengkap. Pilih batch yang ada atau isi kode batch dan tanggal kedaluwarsa.`,
        );
      }

      if (
        manufacturedDate &&
        expiryDate &&
        manufacturedDate > expiryDate
      ) {
        throw new Error(
          `Tanggal produksi tidak boleh setelah kedaluwarsa pada barang ke-${index + 1}.`,
        );
      }

      if (
        !Number.isSafeInteger(
          quantity,
        ) ||
        quantity <= 0
      ) {
        throw new Error(
          `Jumlah barang ke-${index + 1} harus bilangan bulat positif.`,
        );
      }

      const identity = batchId
        ? `${productId}:id:${batchId}`
        : `${productId}:code:${batchCode!.toUpperCase()}`;

      if (
        seen.has(identity)
      ) {
        throw new Error(
          "Batch yang sama tidak boleh ditambahkan dua kali dalam satu penerimaan.",
        );
      }

      seen.add(identity);

      return {
        productId,
        ...(batchId
          ? { batchId }
          : {
              batchCode,
              expiryDate,
              manufacturedDate,
            }),
        quantity,
      };
    },
  );
}

function receiptErrorMessage(
  error: unknown,
) {
  const raw =
    error instanceof Error
      ? error.message
      : "Penerimaan gagal diproses.";

  const messages:
    Record<string, string> = {
      RECEIPT_LINE_MASTER_NOT_FOUND:
        "Produk atau batch penerimaan tidak ditemukan pada organisasi aktif.",
      RECEIPT_PRODUCT_INACTIVE:
        "Produk sudah diarsipkan dan tidak dapat menerima transaksi baru.",
      RECEIPT_BATCH_NOT_ACTIVE:
        "Batch tidak aktif dan tidak dapat menerima transaksi baru.",
      RECEIPT_BATCH_EXPIRED:
        "Batch sudah kedaluwarsa dan tidak dapat menerima transaksi baru.",
      RECEIPT_BATCH_KIND_INVALID:
        "Penerimaan normal hanya dapat memakai Batch Standar.",
      INVALID_BATCH_DATE_RANGE:
        "Tanggal produksi tidak boleh setelah tanggal kedaluwarsa.",
      EXPIRY_DATE_REQUIRED:
        "Tanggal kedaluwarsa batch wajib diisi.",
      BATCH_CODE_REQUIRED:
        "Kode batch wajib diisi.",
      IDEMPOTENCY_KEY_REUSED:
        "Referensi penerimaan sudah digunakan untuk data yang berbeda.",
      AUTH_SESSION_REQUIRED:
        "Sesi Admin sudah berakhir. Silakan login kembali.",
    };

  const matched =
    Object.entries(
      messages,
    ).find(([code]) =>
      raw.includes(code),
    );

  return matched
    ? matched[1]
    : raw;
}

function destination(
  kind: "success" | "error",
  message: string,
  transactionId?: string,
) {
  const query =
    new URLSearchParams({
      [kind]: message,
    });

  if (transactionId) {
    query.set("transactionId", transactionId);
  }

  return `/receipts/new?${query.toString()}`;
}

export async function postMultiLineReceiptAction(
  formData: FormData,
) {
  const session =
    await requireAdminSession();

  let kind:
    | "success"
    | "error" = "success";
  let message: string;
  let resultTransactionId: string | undefined;

  try {
    const sourceRef =
      required(
        formData,
        "sourceRef",
      );

    const occurredAt =
      jakartaTimestamp(
        required(
          formData,
          "occurredAt",
        ),
      );

    const noteValue =
      formData.get("note");

    const note =
      typeof noteValue ===
        "string" &&
      noteValue.trim()
        ? noteValue.trim()
        : null;

    const lines =
      parseLines(
        required(
          formData,
          "receiptLines",
        ),
      );

    const result =
      await callRpc<{
        receiptNo: string;
        transactionId: string;
        totalQuantity: number;
      }>(
        "post_receipt",
        {
          p_organization_id:
            session.profile
              .organization_id,
          p_idempotency_key:
            `receipt:${sourceRef}`,
          p_source_ref:
            sourceRef,
          p_occurred_at:
            occurredAt,
          p_lines:
            lines.map(
              (
                line,
                index,
              ) => ({
                ...line,
                sourceLineRef:
                  `UI-${index + 1}`,
              }),
            ),
          p_note: note,
          p_metadata: {
            source:
              "stock-receipt-ui",
            version: 2,
            actorUserId:
              session.user.id,
          },
        },
      );

    resultTransactionId = result.transactionId;

    message =
      `${result.receiptNo} berhasil menambah ${result.totalQuantity} unit.`;

    revalidatePath("/");
    revalidatePath(
      "/products",
    );
    revalidatePath(
      "/ledger",
    );
  } catch (error) {
    kind = "error";
    message =
      receiptErrorMessage(
        error,
      );
  }

  redirect(
    destination(
      kind,
      message,
      kind === "success" ? resultTransactionId : undefined,
    ),
  );
}