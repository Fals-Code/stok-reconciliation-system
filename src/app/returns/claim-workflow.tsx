import Link from "next/link";

import {
  cancelTikTokReturnClaimAction,
  confirmLateReturnArrivalAction,
  createTikTokReturnClaimAction,
  resolveTikTokReturnClaimAction,
  submitTikTokReturnClaimAction,
} from "@/app/returns/actions";
import { CurrentDateTimeInput } from "@/app/returns/current-date-time-input";
import type {
  ReturnClaimData,
  ReturnClaimHeader,
  ReturnHeader,
  ReturnItem,
} from "@/lib/supabase-rest";

const stages = ["ALL", "DUE_SOON", "OVERDUE", "NOT_STARTED", "SUBMITTED", "RESOLVED", "EXCEPTION", "CANCELLED"] as const;
const resolutions = ["APPROVED", "REJECTED", "PARTIALLY_APPROVED", "NO_ACTION", "OTHER"] as const;
const statusFilters = new Set(["NOT_STARTED", "SUBMITTED", "RESOLVED", "EXCEPTION", "CANCELLED"]);

function label(value: string | null | undefined) {
  const labels: Record<string, string> = {
    NOT_STARTED: "Belum dimulai", DUE_SOON: "Segera jatuh tempo", OVERDUE: "Terlambat",
    SUBMITTED: "Sudah dikirim", RESOLVED: "Selesai", EXCEPTION: "Perlu penanganan", CANCELLED: "Dibatalkan",
    LOST_RETURN: "Retur hilang", PARTIAL_RETURN_MISSING: "Retur kurang sebagian", APPROVED: "Disetujui",
    REJECTED: "Ditolak", PARTIALLY_APPROVED: "Disetujui sebagian", NO_ACTION: "Tidak ada tindakan", OTHER: "Lainnya",
  };
  return value ? labels[value] ?? value : "—";
}

function fmt(value: string | null, time = false) {
  if (!value) return "—";
  return new Intl.DateTimeFormat("id-ID", { timeZone: "Asia/Jakarta", dateStyle: "medium", ...(time ? { timeStyle: "short" } : {}) }).format(new Date(value));
}

function tone(status: string) {
  if (["RESOLVED", "SUBMITTED"].includes(status)) return "border-emerald-400/20 bg-emerald-400/10 text-emerald-300";
  if (["OVERDUE", "EXCEPTION"].includes(status)) return "border-rose-400/20 bg-rose-400/10 text-rose-200";
  return "border-amber-400/20 bg-amber-400/10 text-amber-200";
}

function committedByItem(claims: ReturnClaimHeader[], claimItems: ReturnClaimData["claimItems"]) {
  const totals = new Map<string, number>();
  for (const item of claimItems) {
    const claim = claims.find((candidate) => candidate.id === item.claim_id);
    if (claim?.status_code !== "CANCELLED") totals.set(item.return_item_id, (totals.get(item.return_item_id) ?? 0) + Number(item.quantity));
  }
  return totals;
}

export function ReturnClaimWorkflow({
  returns,
  items,
  data,
  selectedReturn,
  claimId,
  claimStatus,
  claimStage,
}: {
  returns: ReturnHeader[];
  items: ReturnItem[];
  data: ReturnClaimData;
  selectedReturn: ReturnHeader | null;
  claimId?: string;
  claimStatus?: string;
  claimStage?: string;
}) {
  const committed = committedByItem(data.claims, data.claimItems);
  const claimedByClaim = new Map<string, number>();
  for (const item of data.claimItems) claimedByClaim.set(item.claim_id, (claimedByClaim.get(item.claim_id) ?? 0) + Number(item.quantity));
  const returnById = new Map(returns.map((item) => [item.return_id, item]));
  const filtered = data.claims.filter((claim) => {
    if (claimStatus && claim.status_code !== claimStatus) return false;
    if (claimStage === "DUE_SOON" && !["D14", "D7", "D3", "D1", "DUE_TODAY"].includes(claim.derived_deadline_stage)) return false;
    if (claimStage && !["DUE_SOON"].includes(claimStage) && claim.derived_deadline_stage !== claimStage) return false;
    return true;
  });
  const selectedClaim = claimId ? data.claims.find((claim) => claim.id === claimId) ?? null : filtered[0] ?? null;
  const claimReturn = selectedClaim ? returnById.get(selectedClaim.return_id) ?? null : null;
  const claimItems = selectedClaim ? data.claimItems.filter((item) => item.claim_id === selectedClaim.id) : [];
  const selectedReturnItems = selectedReturn ? items.filter((item) => item.return_id === selectedReturn.return_id) : [];
  const eligibleItems = selectedReturn?.channel_code === "TIKTOK_SHOP"
    ? selectedReturnItems.map((item) => ({ ...item, remaining: Math.max(0, Number(item.net_lost_qty ?? item.lost_qty) - (committed.get(item.return_item_id) ?? 0)) })).filter((item) => item.remaining > 0)
    : [];
  const lateItems = selectedReturnItems.filter((item) => Number(item.lost_qty) - Number(item.late_arrival_qty ?? 0) > 0);
  const notifications = selectedClaim ? data.notifications.filter((note) => note.entity_id === selectedClaim.id || note.action_route?.includes(selectedClaim.id)) : [];
  const links = selectedClaim ? data.lateArrivalClaimLinks.filter((link) => link.claim_id === selectedClaim.id) : [];
  const audit = selectedClaim ? data.claimEvents.filter((event) => event.claim_id === selectedClaim.id) : [];
  const noResult = claimId && !selectedClaim;

  return (
    <section id="claims" className="mt-10 scroll-mt-24">
      <div className="mb-5 flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <p className="section-kicker">TikTok claim desk</p>
          <h2 className="section-title">Klaim dan kedatangan terlambat dalam satu jejak audit.</h2>
          <p className="mt-2 max-w-3xl text-sm text-slate-400">Status klaim tidak mengubah stok. Quantity yang dapat diklaim selalu mengikuti net lost dan tetap divalidasi ulang oleh RPC.</p>
        </div>
        <div className="flex flex-wrap gap-2 text-xs">
          {stages.map((stage) => { const isStatus = statusFilters.has(stage); const active = isStatus ? claimStatus === stage : claimStage === stage || (!claimStage && !claimStatus && stage === "ALL"); const query = stage === "ALL" ? "" : isStatus ? `claimStatus=${stage}` : `claimStage=${stage}`; return <Link key={stage} href={`/returns?${query}#claims`} className={`rounded-full border px-3 py-1.5 ${active ? "border-emerald-400/30 bg-emerald-400/10 text-emerald-300" : "border-white/10 text-slate-400"}`}>{label(stage)}</Link>; })}
        </div>
      </div>

      <div className="grid gap-5 xl:grid-cols-[0.85fr_1.55fr]">
        <div className="panel-card p-0">
          {filtered.length === 0 ? <div className="p-7 text-sm text-slate-400">Tidak ada klaim yang cocok dengan filter ini.</div> : <div className="divide-y divide-white/10">{filtered.map((claim) => { const source = returnById.get(claim.return_id); return <Link key={claim.id} href={`/returns?returnId=${claim.return_id}&claimId=${claim.id}#claim-detail`} className={`block p-5 transition hover:bg-white/[0.03] ${selectedClaim?.id === claim.id ? "bg-emerald-400/[0.05]" : ""}`}><div className="flex items-start justify-between gap-3"><div><p className="font-mono text-sm text-white">{source?.external_return_ref ?? "Retur tidak ditemukan"}</p><p className="mt-1 text-xs text-slate-500">{source?.marketplace_order_ref ?? "—"} / {label(claim.claim_type_code)}</p></div><span className={`rounded-full border px-2.5 py-1 text-xs ${tone(claim.derived_deadline_stage === "OVERDUE" ? "OVERDUE" : claim.status_code)}`}>{label(claim.status_code)}</span></div><div className="mt-4 flex flex-wrap gap-3 text-xs text-slate-400"><span>stage {label(claim.derived_deadline_stage)}</span><span>batas {fmt(claim.deadline_at)}</span><span>claimed {claimedByClaim.get(claim.id) ?? 0}</span><span>{claim.stock_effect_code}</span></div></Link>; })}</div>}
        </div>

        <article id="claim-detail" className="panel-card scroll-mt-24">
          {noResult ? <div className="rounded-2xl border border-amber-400/20 bg-amber-400/[0.06] p-6 text-sm text-amber-100">Klaim tidak ditemukan dalam organisasi aktif. Tidak ada tindakan yang tersedia.</div> : !selectedClaim || !claimReturn ? <div className="py-10 text-center text-sm text-slate-400">Pilih klaim dari worklist untuk melihat detail dan tindakan.</div> : <>
            <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between"><div><p className="section-kicker">Detail klaim</p><h3 className="mt-2 text-2xl font-semibold">{claimReturn.external_return_ref}</h3><p className="mt-2 text-sm text-slate-400">{claimReturn.marketplace_order_ref} / {label(selectedClaim.claim_type_code)}</p></div><span className={`rounded-full border px-3 py-1.5 text-xs ${tone(selectedClaim.derived_deadline_stage === "OVERDUE" ? "OVERDUE" : selectedClaim.status_code)}`}>{label(selectedClaim.status_code)} · {label(selectedClaim.derived_deadline_stage)}</span></div>
            <div className="mt-6 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">{[["Dasar", selectedClaim.claim_basis_code], ["Batas", fmt(selectedClaim.deadline_at, true)], ["Jendela", `${selectedClaim.window_days_snapshot} hari`], ["Dampak stok", selectedClaim.stock_effect_code], ["Resolution", label(selectedClaim.resolution_code)], ["External ref", selectedClaim.external_claim_ref ?? "Belum ada"], ["Policy", selectedClaim.policy_version_snapshot], ["Zona waktu", selectedClaim.timezone_snapshot]].map(([key, value]) => <div key={key} className="rounded-2xl border border-white/10 bg-slate-950/50 p-4"><p className="text-xs text-slate-500">{key}</p><p className="mt-2 text-sm text-white">{value}</p></div>)}</div>
            <div className="mt-7 overflow-x-auto"><table className="min-w-full text-left text-sm"><thead className="text-xs uppercase tracking-wide text-slate-500"><tr><th className="px-3 py-3">SKU</th><th className="px-3 py-3">Claim</th><th className="px-3 py-3">Eligible snapshot</th><th className="px-3 py-3">Source line</th></tr></thead><tbody className="divide-y divide-white/10">{claimItems.map((item) => <tr key={item.id}><td className="px-3 py-3 text-white">{item.product_sku_snapshot}</td><td className="px-3 py-3">{item.quantity}</td><td className="px-3 py-3">{item.eligible_lost_qty_snapshot}</td><td className="px-3 py-3 font-mono text-xs text-slate-400">{item.source_line_ref_snapshot}<details className="mt-2"><summary className="cursor-pointer">Provenance historis</summary><pre className="mt-2 max-w-md whitespace-pre-wrap text-[11px] text-slate-500">{JSON.stringify(item.canonical_components_snapshot, null, 2)}</pre></details></td></tr>)}</tbody></table></div>
            <div className="mt-7 grid gap-5 lg:grid-cols-2"><div><h4 className="text-lg font-semibold">Tindakan lifecycle</h4><div className="mt-4 space-y-3">{["NOT_STARTED", "DUE_SOON", "EXPIRED"].includes(selectedClaim.status_code) ? <form action={submitTikTokReturnClaimAction} className="rounded-2xl border border-white/10 p-4"><input type="hidden" name="claimId" value={selectedClaim.id}/><input type="hidden" name="returnId" value={selectedClaim.return_id}/><label className="field-label">External claim reference<input name="externalClaimRef" required placeholder="TIKTOK-CLAIM-1001"/></label><label className="field-label mt-3">Waktu submit<CurrentDateTimeInput/></label><label className="mt-3 flex items-start gap-2 text-sm text-slate-300"><input type="checkbox" name="confirmation" required/> Saya mengonfirmasi pengiriman klaim.</label><button className="primary-button mt-4" type="submit">Submit claim</button></form> : null}{["SUBMITTED", "EXPIRED"].includes(selectedClaim.status_code) ? <form action={resolveTikTokReturnClaimAction} className="rounded-2xl border border-white/10 p-4"><input type="hidden" name="claimId" value={selectedClaim.id}/><input type="hidden" name="returnId" value={selectedClaim.return_id}/><label className="field-label">Resolution<select name="resolutionCode" defaultValue="" required><option value="" disabled>Pilih hasil</option>{resolutions.map((value) => <option key={value} value={value}>{label(value)}</option>)}</select></label><label className="field-label mt-3">Waktu resolve<CurrentDateTimeInput/></label><label className="mt-3 flex items-start gap-2 text-sm text-slate-300"><input type="checkbox" name="confirmation" required/> Saya mengonfirmasi penyelesaian klaim ini.</label><button className="primary-button mt-4" type="submit">Resolve claim</button></form> : null}{["NOT_STARTED", "DUE_SOON", "EXCEPTION"].includes(selectedClaim.status_code) ? <form action={cancelTikTokReturnClaimAction} className="rounded-2xl border border-white/10 p-4"><input type="hidden" name="claimId" value={selectedClaim.id}/><input type="hidden" name="returnId" value={selectedClaim.return_id}/><label className="field-label">Alasan pembatalan<textarea name="reason" required rows={2}/></label><label className="field-label mt-3">Waktu batal<CurrentDateTimeInput/></label><label className="mt-3 flex items-start gap-2 text-sm text-slate-300"><input type="checkbox" name="confirmation" required/> Saya mengonfirmasi pembatalan klaim ini.</label><button className="secondary-button mt-4" type="submit">Cancel claim</button></form> : null}</div></div><div><h4 className="text-lg font-semibold">Timeline immutable</h4><div className="mt-4 space-y-3">{audit.map((event) => <div key={event.id} className="rounded-2xl border border-white/10 p-4"><div className="flex justify-between gap-3"><span className="text-sm text-white">{label(event.event_type_code)}</span><time className="text-xs text-slate-500">{fmt(event.occurred_at, true)}</time></div>{event.note ? <p className="mt-2 text-xs text-slate-400">{event.note}</p> : null}<details className="mt-2 text-xs text-slate-500"><summary className="cursor-pointer">Detail audit</summary><pre className="mt-2 whitespace-pre-wrap">{JSON.stringify(event.snapshot, null, 2)}</pre></details></div>)}</div></div></div>
            {notifications.length ? <div className="mt-7 rounded-2xl border border-amber-400/20 bg-amber-400/[0.05] p-4 text-sm text-amber-100">{notifications.map((note) => <Link key={note.notification_id} className="block underline" href={`/notifications?notificationId=${note.notification_id}#detail`}>{note.title} · {label(note.lifecycle_status_code)}</Link>)}</div> : <p className="mt-7 text-sm text-slate-500">Belum ada notifikasi aktif untuk klaim ini.</p>}
            {links.length ? <div className="mt-4 rounded-2xl border border-rose-400/20 bg-rose-400/[0.05] p-4 text-sm text-rose-100">Kedatangan terlambat terhubung ke klaim ini. History klaim tetap dipertahankan.{links.some((link) => link.warning_required) ? " Perlu review karena klaim sudah dikirim atau selesai." : ""}</div> : null}\n            {links.length ? <div className="mt-4 space-y-2">{links.map((link) => { const late = data.lateArrivals.find((item) => item.late_arrival_id === link.late_arrival_id); return <div key={link.late_arrival_claim_link_id} className="rounded-2xl border border-white/10 p-4 text-sm text-slate-300">Late arrival {late?.late_arrival_reference ?? link.late_arrival_id} / receipt {late?.receipt_ref ?? "—"} / snapshot status {label(link.claim_status_snapshot)} / {late?.stock_effect_code ?? "NONE"}</div>; })}</div> : null}
            <details className="mt-6"><summary className="cursor-pointer text-xs text-slate-500">Detail audit teknis</summary><pre className="mt-3 overflow-x-auto rounded-2xl bg-slate-950 p-4 text-[11px] text-slate-500">{JSON.stringify({ claimId: selectedClaim.id, requestHash: selectedClaim.request_hash, idempotencyCommandId: selectedClaim.idempotency_command_id, schemaVersion: selectedClaim.schema_version }, null, 2)}</pre></details>
          </>}
        </article>
      </div>

      {selectedReturn ? <div className="mt-5 grid gap-5 lg:grid-cols-2"><form action={createTikTokReturnClaimAction} className="panel-card"><h3 className="text-lg font-semibold">Buat klaim TikTok</h3>{selectedReturn.channel_code !== "TIKTOK_SHOP" ? <p className="mt-3 text-sm text-slate-400">Form hanya tersedia untuk retur TikTok Shop.</p> : eligibleItems.length === 0 ? <p className="mt-3 text-sm text-amber-200">Tidak ada net lost quantity yang masih dapat diklaim.</p> : <><input type="hidden" name="returnId" value={selectedReturn.return_id}/><input type="hidden" name="claimTypeCode" value="LOST_RETURN"/><label className="field-label mt-4">Referensi proses/idempotency<input name="idempotencyKey" required placeholder="CLAIM-RET-1001"/></label><fieldset className="mt-4"><legend className="text-sm font-medium text-slate-200">Pilih item dan quantity</legend><div className="mt-3 space-y-3">{eligibleItems.map((item) => <label key={item.return_item_id} className="flex items-center gap-3 rounded-2xl border border-white/10 p-3 text-sm"><input type="checkbox" name="claimItemId" value={item.return_item_id}/><span className="min-w-0 flex-1"><span className="block text-white">{item.product_sku_snapshot}</span><span className="text-xs text-slate-500">sisa dapat diklaim {item.remaining}</span></span><input className="w-24" name={`quantity_${item.return_item_id}`} type="number" min="1" max={item.remaining} step="1" defaultValue="1" aria-label={`Quantity ${item.product_sku_snapshot}`}/></label>)}</div></fieldset><label className="field-label mt-4">Waktu dibuat<CurrentDateTimeInput/></label><label className="mt-4 flex items-start gap-2 text-sm text-slate-300"><input type="checkbox" name="confirmation" required/> Saya mengonfirmasi quantity klaim ini tidak mengubah stok.</label><button className="primary-button mt-4" type="submit">Buat claim</button></>}</form>
        <form action={confirmLateReturnArrivalAction} className="panel-card"><h3 className="text-lg font-semibold">Konfirmasi kedatangan terlambat</h3>{lateItems.length === 0 ? <p className="mt-3 text-sm text-slate-400">Tidak ada quantity lost yang menunggu koreksi.</p> : <><input type="hidden" name="returnId" value={selectedReturn.return_id}/><input type="hidden" name="returnRef" value={selectedReturn.external_return_ref}/><label className="field-label mt-4">Referensi kedatangan<input name="lateArrivalReference" required placeholder="LATE-RET-1001"/></label><label className="field-label mt-3">Referensi receipt<input name="receiptRef" required placeholder="RECEIPT-RET-1001"/></label><fieldset className="mt-4"><legend className="text-sm font-medium text-slate-200">Item lost yang datang</legend><div className="mt-3 space-y-3">{lateItems.map((item) => <label key={item.return_item_id} className="flex items-center gap-3 rounded-2xl border border-white/10 p-3 text-sm"><input type="checkbox" name="lateReturnItemId" value={item.return_item_id}/><span className="min-w-0 flex-1"><span className="block text-white">{item.product_sku_snapshot}</span><span className="text-xs text-slate-500">sisa koreksi {Number(item.lost_qty) - Number(item.late_arrival_qty ?? 0)}</span></span><input className="w-24" name={`lateQuantity_${item.return_item_id}`} type="number" min="1" max={Number(item.lost_qty) - Number(item.late_arrival_qty ?? 0)} step="1" defaultValue="1" aria-label={`Quantity kedatangan ${item.product_sku_snapshot}`}/></label>)}</div></fieldset><label className="field-label mt-3">Source line reference<input name="sourceLineRef" required placeholder="LATE-LINE-1"/></label><label className="field-label mt-3">Waktu datang<CurrentDateTimeInput/></label><label className="field-label mt-3">Catatan<textarea name="note" rows={2}/></label><label className="mt-4 flex items-start gap-2 text-sm text-slate-300"><input type="checkbox" name="confirmation" required/> Saya mengonfirmasi receipt ini stock-neutral.</label><button className="primary-button mt-4" type="submit">Catat kedatangan</button></>}</form></div> : null}
    </section>
  );
}
