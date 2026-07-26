"use server";

import { uploadAndValidateMarketplaceCsv } from "@/lib/csv-import/server";
import { commitMarketplaceCsvImportJob } from "@/lib/csv-import/server";
import { redirect } from "next/navigation";

export async function stageMarketplaceCsvAction(formData: FormData) {
  const file = formData.get("file");
  if (!(file instanceof File)) {
    throw new Error("CSV_FILE_REQUIRED");
  }
  let target = "/marketplace/import?error=CSV_IMPORT_FAILED";
  try {
    const result = await uploadAndValidateMarketplaceCsv(file);
    if (!result.jobId) {
      target = `/marketplace/import?error=${encodeURIComponent(result.parse.errors[0]?.code ?? result.status)}`;
    } else {
      target = `/marketplace/import/${result.jobId}?status=${encodeURIComponent(result.status)}`;
    }
  } catch (error) {
    target = `/marketplace/import?error=${encodeURIComponent(error instanceof Error ? error.message : "CSV_IMPORT_FAILED")}`;
  }
  redirect(target);
}

export async function commitMarketplaceCsvImportAction(formData: FormData) {
  const jobId = String(formData.get("jobId") ?? "");
  const key = String(formData.get("commitKey") ?? "");
  const confirmation = formData.get("confirmation") === "on";
  let target = `/marketplace/import/${jobId}?commitError=CSV_IMPORT_COMMIT_FAILED`;
  try {
    const result = await commitMarketplaceCsvImportJob(jobId, key, confirmation);
    target = `/marketplace/import/${jobId}?commit=${encodeURIComponent(result.status)}`;
  } catch (error) {
    target = `/marketplace/import/${jobId}?commitError=${encodeURIComponent(error instanceof Error ? error.message : "CSV_IMPORT_COMMIT_FAILED")}`;
  }
  redirect(target);
}
