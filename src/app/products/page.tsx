import { randomUUID } from "node:crypto";
import Link from "next/link";

import { createProductAction } from "@/app/products/actions";
import { getProductMasterData } from "@/lib/supabase-rest";

export const dynamic = "force-dynamic";

type SearchParams = { success?: string; error?: string; q?: string; status?: string };
const formatter = new Intl.NumberFormat("id-ID");

function quantity(value: number) { return formatter.format(Number(value)); }
function formatDate(value: string) {
  return new Intl.DateTimeFormat("id-ID", { timeZone: "Asia/Jakarta", dateStyle: "medium", timeStyle: "short", hour12: false }).format(new Date(value));
}
function feedback(params: SearchParams) {
  const message = params.success ?? params.error;
  if (!message) return null;
  const tone = params.error ? "border-rose-400/30 bg-rose-400/10 text-rose-100" : "border-emerald-400/30 bg-emerald-400/10 text-emerald-100";
  return <p role="status" className={`rounded-xl border px-4 py-3 text-sm ${tone}`}>{message}</p>;
}

export default async function ProductsPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const params = await searchParams;
  let data;
  try { data = await getProductMasterData(); } catch (error) {
    return <main className="min-h-screen px-5 py-12 text-slate-100"><section className="panel-card mx-auto max-w-3xl"><p className="section-kicker text-amber-300">Master Data / Produk</p><h1 className="section-title">Data Produk gagal dimuat.</h1><p className="mt-3 text-slate-300">{error instanceof Error && error.message.includes("AUTH_SESSION_REQUIRED") ? "Sesi Admin diperlukan untuk melihat Produk." : "Coba muat ulang halaman. Jika berulang, periksa koneksi aplikasi."}</p></section></main>;
  }
  const query = params.q?.trim().toLowerCase() ?? "";
  const status = params.status?.toUpperCase() === "ARCHIVED" ? "ARCHIVED" : params.status?.toUpperCase() === "ACTIVE" ? "ACTIVE" : "ALL";
  const products = data.products.filter((product) => {
    const matches = !query || `${product.sku} ${product.name}`.toLowerCase().includes(query);
    return matches && (status === "ALL" || (status === "ACTIVE" ? product.is_active : !product.is_active));
  });
  const active = data.products.filter((product) => product.is_active).length;
  const archived = data.products.length - active;
  return <main className="mx-auto w-full max-w-7xl px-5 py-8 text-slate-100"><header className="mb-7 flex flex-wrap items-end justify-between gap-4"><div><p className="section-kicker">Master Data / Produk</p><h1 className="mt-2 text-3xl font-semibold tracking-tight">Kelola Produk tanpa mengubah stok</h1><p className="mt-2 max-w-2xl text-sm leading-6 text-slate-400">SKU, nama, dan status Produk diaudit. Saldo fisik tetap hanya berasal dari ledger.</p></div><div className="flex gap-3"><div className="metric-card min-w-28"><p className="text-xs text-slate-400">Aktif</p><p className="mt-1 text-2xl font-semibold text-emerald-300">{active}</p></div><div className="metric-card min-w-28"><p className="text-xs text-slate-400">Diarsipkan</p><p className="mt-1 text-2xl font-semibold text-amber-200">{archived}</p></div></div></header>
  {feedback(params)}
  <section id="product-form" className="panel-card mt-6"><p className="section-kicker">Tambah Produk</p><h2 className="section-title">Catat identitas Produk baru</h2><form action={createProductAction} className="form-grid mt-5"><input type="hidden" name="intentId" value={randomUUID()} /><label className="field-label">SKU<input required name="sku" placeholder="Contoh: GLW SERUM 30ML" /></label><label className="field-label">Nama Produk<input required name="name" placeholder="Nama yang dibaca gudang" /></label><label className="field-label">Satuan<input value="UNIT" readOnly aria-readonly="true" /></label><label className="field-label">Deskripsi<textarea name="description" rows={2} placeholder="Opsional" /></label><label className="field-label sm:col-span-2">Catatan audit<textarea name="note" rows={2} placeholder="Opsional; alasan atau konteks pembuatan" /></label><div className="sm:col-span-2"><button className="primary-button" type="submit">Simpan Produk</button></div></form></section>
  <section className="panel-card mt-6"><div className="flex flex-wrap items-end justify-between gap-4"><div><p className="section-kicker">Daftar Produk</p><h2 className="section-title">Posisi dan status master terkini</h2></div><form className="flex flex-wrap gap-2" method="get"><input className="rounded-xl border border-white/10 bg-slate-950 px-3 py-2 text-sm" name="q" defaultValue={params.q ?? ""} placeholder="Cari SKU atau nama" /><select className="rounded-xl border border-white/10 bg-slate-950 px-3 py-2 text-sm" name="status" defaultValue={status}><option value="ALL">Semua status</option><option value="ACTIVE">Aktif</option><option value="ARCHIVED">Diarsipkan</option></select><button className="primary-button" type="submit">Terapkan</button></form></div>
  {products.length === 0 ? <div className="mt-6 rounded-2xl border border-dashed border-white/15 p-8 text-sm text-slate-400">{data.products.length === 0 ? "Belum ada Produk. Gunakan formulir di atas untuk menambahkan Produk pertama." : "Tidak ada Produk yang cocok dengan pencarian atau filter."}</div> : <div className="mt-6 overflow-x-auto"><table><thead><tr><th>Produk</th><th>Status</th><th>Sellable</th><th>Quarantine</th><th>Damaged</th><th>Reserved</th><th>Available</th><th>Histori</th><th>Batch</th><th>Diperbarui</th></tr></thead><tbody>{products.map((product) => <tr key={product.product_id}><td><Link className="font-semibold text-emerald-300 hover:text-emerald-200" href={`/products/${product.product_id}`}>{product.sku}</Link><p className="mt-1 text-xs text-slate-400">{product.name}</p></td><td><span className={product.is_active ? "status-pill status-success" : "status-pill status-warning"}>{product.is_active ? "AKTIF" : "DIARSIPKAN"}</span></td><td>{quantity(product.sellable_qty)}</td><td>{quantity(product.quarantine_qty)}</td><td>{quantity(product.damaged_qty)}</td><td>{quantity(product.reserved_qty)}</td><td>{quantity(product.available_qty)}</td><td>{product.has_authoritative_history ? "Ada" : "Belum"}</td><td>{quantity(product.batch_count)}</td><td>{formatDate(product.updated_at)}</td></tr>)}</tbody></table></div>}</section></main>;
}