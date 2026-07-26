"use server";

import { uploadAndValidateMarketplaceCsv } from "@/lib/csv-import/server";

export async function stageMarketplaceCsvAction(formData: FormData) {
  const file = formData.get("file");
  if (!(file instanceof File)) {
    throw new Error("CSV_FILE_REQUIRED");
  }
  return uploadAndValidateMarketplaceCsv(file);
}
