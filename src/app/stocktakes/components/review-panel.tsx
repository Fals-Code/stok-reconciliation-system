"use client";

import { useState } from "react";

import { requestStocktakeReviewRecountAction, reviewStocktakeLineAction } from "@/app/stocktakes/actions";
import { Alert, Input, Select, StatusBadge, Textarea } from "@/components/ui";
import type { StocktakeCountAttempt, StocktakeReviewDecision, StocktakeReviewLine, StocktakeVarianceReason } from "@/lib/stocktakes/types";

const numberFormatter = new Intl.NumberFormat("id-ID");
const reasonOptions: Array<[StocktakeVarianceReason, string]> = [["UNRECORDED_MANUAL_OUTBOUND", "Barang keluar manual belum tercatat"], ["UNRECORDED_INBOUND", "Barang masuk belum tercatat"], ["RETURN_MISMATCH", "Ketidaksesuaian retur"], ["WRONG_BATCH_COUNT", "Salah hitung Kode Batch"], ["WRONG_BUCKET_COUNT", "Salah hitung kondisi stok"], ["DAMAGE_NOT_RECORDED", "Kerusakan belum tercatat"], ["EXPIRY_NOT_RECORDED", "Kedaluwarsa belum tercatat"], ["INITIAL_BALANCE_UNCERTAIN", "Saldo awal belum pasti"], ["COUNT_TIMING_DIFFERENCE", "Perbedaan waktu penghitungan"], ["DUPLICATE_MOVEMENT", "Perubahan stok tercatat dua kali"], ["SOURCE_EVENT_FAILURE", "Peristiwa sumber gagal tercatat"], ["PROJECTION_DRIFT", "Catatan stok tidak selaras"], ["PHYSICAL_LOSS", "Kehilangan fisik"], ["PHYSICAL_SURPLUS", "Kelebihan fisik"], ["MASTER_DATA_ERROR", "Data produk atau batch keliru"], ["UNKNOWN", "Belum diketahui"], ["OTHER", "Lainnya"]];
function bucketLabel(bucket: string) { return bucket === "SELLABLE" ? "Layak Dijual" : bucket === "QUARANTINE" ? "Ditahan" : "Rusak"; }
function formatCountedAt(value: string) { const date = new Date(value); return Number.isNaN(date.getTime()) ? "Waktu tidak tersedia" : new Intl.DateTimeFormat("id-ID", { timeZone: "Asia/Jakarta", day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", hour12: false }).format(date); }

function ReviewLineForm({ line, returnTo, stocktakeId }: { line: StocktakeReviewLine; returnTo: string; stocktakeId: string }) {
  const hasVariance = line.variance_qty !== 0;
  const initialDecision: Exclude<StocktakeReviewDecision, "RECOUNT_REQUIRED"> = hasVariance ? line.review_decision_code === "EXCEPTION" ? "EXCEPTION" : "VARIANCE_ACCEPTED" : "MATCHED";
  const [decision, setDecision] = useState<Exclude<StocktakeReviewDecision, "RECOUNT_REQUIRED">>(initialDecision);
  const [reason, setReason] = useState(line.reason_code ?? "");

  const isComplete =
    line.count_status_code === "COUNTED" &&
    line.final_physical_qty !== null &&
    line.expected_qty_at_count !== null &&
    line.variance_qty !== null;

  if (!isComplete) {
    return (
      <Alert
        className="mt-4"
        title="Bukti hitungan belum lengkap"
        tone="warning"
      >
        Baris ini belum memiliki jumlah fisik, catatan saat dihitung,
        dan selisih yang lengkap. Jangan menyetujui hasil sebelum
        data tersebut tersedia.
      </Alert>
    );
  }

  const requiresNote = decision === "VARIANCE_ACCEPTED" && (reason === "UNKNOWN" || reason === "OTHER");
  const changeDecision = (value: Exclude<StocktakeReviewDecision, "RECOUNT_REQUIRED">) => { setDecision(value); if (value !== "VARIANCE_ACCEPTED") setReason(""); };
  return <><form action={reviewStocktakeLineAction} className="mt-4 grid gap-3 border-t border-ui-border pt-4 sm:grid-cols-2"><input name="returnTo" type="hidden" value={returnTo} /><input name="stocktakeId" type="hidden" value={stocktakeId} /><input name="stocktakeLineId" type="hidden" value={line.stocktake_line_id} /><input name="lineVersion" type="hidden" value={line.version_no} /><label className="grid gap-2 text-sm font-semibold text-ui-text">Keputusan<Select name="decisionCode" onChange={(event) => changeDecision(event.target.value as Exclude<StocktakeReviewDecision, "RECOUNT_REQUIRED">)} value={decision}>{hasVariance ? <><option value="VARIANCE_ACCEPTED">Terima selisih</option><option value="EXCEPTION">Tandai bermasalah</option></> : <option value="MATCHED">Sesuai catatan</option>}</Select></label>{decision === "VARIANCE_ACCEPTED" ? <label className="grid gap-2 text-sm font-semibold text-ui-text">Alasan selisih<Select name="reasonCode" onChange={(event) => setReason(event.target.value as StocktakeVarianceReason | "")} required={decision === "VARIANCE_ACCEPTED"} value={reason}><option value="">Pilih alasan</option>{reasonOptions.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</Select></label> : <input name="reasonCode" type="hidden" value="" />}{decision === "EXCEPTION" ? <label className="grid gap-2 text-sm font-semibold text-ui-text">Keterangan masalah<Input defaultValue={line.exception_code ?? ""} name="exceptionCode" required={decision === "EXCEPTION"} /></label> : <input name="exceptionCode" type="hidden" value="" />}<label className="grid gap-2 text-sm font-semibold text-ui-text">Catatan pemeriksaan<Textarea defaultValue={line.review_note ?? ""} name="reviewNote" required={requiresNote} /></label><div><button className="min-h-[var(--ui-control-height)] rounded-[var(--ui-radius-md)] border border-ui-primary bg-ui-primary px-4 text-sm font-semibold text-ui-text-on-primary" type="submit">Simpan Pemeriksaan</button></div></form><form action={requestStocktakeReviewRecountAction} className="mt-3 flex flex-col gap-3 border-t border-ui-border pt-3 sm:flex-row sm:items-end"><input name="returnTo" type="hidden" value={returnTo} /><input name="stocktakeId" type="hidden" value={stocktakeId} /><input name="stocktakeLineId" type="hidden" value={line.stocktake_line_id} /><input name="lineVersion" type="hidden" value={line.version_no} /><label className="grid flex-1 gap-2 text-sm font-semibold text-ui-text">Alasan hitung ulang<Input name="reason" required /></label><button className="min-h-[var(--ui-control-height)] rounded-[var(--ui-radius-md)] border border-ui-border px-4 text-sm font-semibold text-ui-text" type="submit">Kembalikan untuk Hitung Ulang</button></form></>;
}

export function ReviewPanel({ attempts, lines, returnTo, stocktakeId }: { attempts: StocktakeCountAttempt[]; lines: StocktakeReviewLine[]; returnTo: string; stocktakeId: string }) {
  const attemptsByLine = new Map<string, StocktakeCountAttempt[]>(); for (const attempt of attempts) attemptsByLine.set(attempt.stocktake_line_id, [...(attemptsByLine.get(attempt.stocktake_line_id) ?? []), attempt]);
  return <section className="mt-6 grid gap-3">{lines.map((line) => { const lineAttempts = attemptsByLine.get(line.stocktake_line_id) ?? []; return <article className="rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface p-4" key={line.stocktake_line_id}><div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between"><div><h2 className="font-semibold text-ui-text">{line.product_name_snapshot}</h2><p className="mt-1 text-sm text-ui-text-muted">{line.product_sku_snapshot} · Kode Batch {line.batch_code_snapshot} · {bucketLabel(line.bucket_code)}</p></div><StatusBadge tone={line.review_status_code === "REVIEWED" ? "selected" : "warning"}>{line.review_status_code === "REVIEWED" ? "Sudah diperiksa" : "Menunggu pemeriksaan"}</StatusBadge></div><div className="mt-4 grid gap-3 text-sm sm:grid-cols-2 lg:grid-cols-4"><p><span className="text-ui-text-muted">Snapshot awal</span><br /><span className="ui-number font-semibold text-ui-text">{numberFormatter.format(line.system_qty_at_snapshot)} unit</span></p><p><span className="text-ui-text-muted">Catatan saat dihitung</span><br /><span className="ui-number font-semibold text-ui-text">{line.expected_qty_at_count === null ? "Belum tersedia" : `${numberFormatter.format(line.expected_qty_at_count)} unit`}</span></p><p><span className="text-ui-text-muted">Jumlah fisik</span><br /><span className="ui-number font-semibold text-ui-text">{line.final_physical_qty === null ? "Belum dihitung" : `${numberFormatter.format(line.final_physical_qty)} unit`}</span></p><p><span className="text-ui-text-muted">Selisih</span><br /><span className="ui-number font-semibold text-ui-text">{line.variance_qty === null ? "Belum tersedia" : `${numberFormatter.format(line.variance_qty)} unit`}</span></p></div>{lineAttempts.length ? <div className="mt-4 grid gap-2 border-t border-ui-border pt-4">{lineAttempts.map((attempt) => <div className="rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface-subtle p-3 text-sm" key={attempt.count_attempt_id}><p className="font-semibold text-ui-text">Penghitungan ke-{attempt.attempt_no}</p><p className="mt-1 text-ui-text-muted">Jumlah fisik {numberFormatter.format(attempt.physical_qty)} unit · {formatCountedAt(attempt.counted_at)}</p><p className="mt-1 text-ui-text-muted">Catatan saat itu {numberFormatter.format(attempt.expected_qty_at_count)} unit · Selisih {numberFormatter.format(attempt.variance_qty)} unit</p>{attempt.count_cutoff_ledger_seq !== null ? <p className="mt-1 text-ui-text-muted">Dicatat saat penghitungan ini disimpan</p> : null}{attempt.note ? <p className="mt-1 text-ui-text-muted">Catatan: {attempt.note}</p> : null}</div>)}</div> : null}<ReviewLineForm line={line} returnTo={returnTo} stocktakeId={stocktakeId} /></article>; })}</section>;
}
