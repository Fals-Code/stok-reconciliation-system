import { getAdminSession } from "@/lib/auth";

const TEMPLATE = [
  "schema_version,channel_code,external_event_ref,external_order_ref,source_status,occurred_at,received_at,source_line_ref,external_listing_code,listing_quantity,event_type,source_title,source_sku,note",
  "MARKETPLACE_RESERVATION_V1,SHOPEE,ORDER-EXAMPLE-001,ORDER-EXAMPLE-001,CREATED,2026-07-26T09:00:00Z,2026-07-26T09:05:00Z,LINE-1,LISTING-EXAMPLE-001,1,ORDER,Contoh listing,,Contoh reservation",
].join("\r\n") + "\r\n";

export async function GET() {
  const session = await getAdminSession();
  if (!session) return new Response("Not found", { status: 404 });
  return new Response(TEMPLATE, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": 'attachment; filename="marketplace-reservation-v1-template.csv"',
      "Cache-Control": "no-store",
    },
  });
}
