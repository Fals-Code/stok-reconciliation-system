import { getMarketplaceCsvImportErrorReport } from "@/lib/csv-import/server";

export async function GET(_request: Request, context: { params: Promise<{ jobId: string }> }) {
  const { jobId } = await context.params;
  const report = await getMarketplaceCsvImportErrorReport(jobId);
  if (report === null) return new Response("Not found", { status: 404 });
  return new Response(report, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="csv-import-${jobId}-errors.csv"`,
      "Cache-Control": "no-store",
    },
  });
}
