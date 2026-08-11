import { readFile } from "node:fs/promises";

const files = {
  page: "src/app/products/page.tsx",
  workspace: "src/app/products/stock-workspace.tsx",
  controls: "src/app/products/stock-workspace-controls.tsx",
};

function expect(name, condition) {
  if (!condition) {
    throw new Error(name);
  }

  console.log(`[PASS] ${name}`);
}

async function source(path) {
  return readFile(path, "utf8");
}

async function main() {
  const [page, workspace, controls] = await Promise.all([
    source(files.page),
    source(files.workspace),
    source(files.controls),
  ]);
  const rendered = `${page}\n${workspace}\n${controls}`;

  expect(
    "Landing memakai getProductMasterData dan ProductMasterRow authoritative",
    workspace.includes("getProductMasterData") &&
      workspace.includes("ProductMasterRow") &&
      [
        "available_qty",
        "reserved_qty",
        "is_active",
        "sellable_qty",
        "batch_count",
      ].every((field) => workspace.includes(field)),
  );
  expect(
    "Header Stok memakai copy yang disetujui",
    page.includes('title="Stok"') &&
      page.includes('description="Pantau posisi stok dan catat perubahan bila diperlukan."'),
  );
  expect(
    "Filter live mempertahankan q dan status pada URL",
    controls.includes("LiveQueryControls") &&
      controls.includes('name: "q"') &&
      controls.includes('name: "status"') &&
      controls.includes('value: ""') &&
      controls.includes('value: "ACTIVE"') &&
      controls.includes('value: "ARCHIVED"') &&
      controls.includes('label: "Semua status"'),
  );
  expect(
    "Label status menggunakan Tidak Aktif",
    rendered.includes("Tidak Aktif") && !rendered.includes("Diarsipkan"),
  );
  expect(
    "State jujur tersedia tanpa fallback nol",
    workspace.includes("Memuat posisi stok") &&
      workspace.includes("Belum ada produk") &&
      workspace.includes("Tidak ada produk yang cocok") &&
      workspace.includes("Hapus Filter") &&
      workspace.includes("Stok belum dapat dimuat") &&
      workspace.includes("Kegagalan tidak mengubah stok") &&
       !workspace.includes("data?.products ?? []"),
  );
  expect(
    "Kegagalan baca menyediakan pemulihan yang mempertahankan filter",
    workspace.includes('href={retryHref}') &&
      workspace.includes("Muat Ulang"),
  );
  expect(
    "State error hanya menangkap kegagalan fetch, bukan render",
    !workspace.includes("try {"),
  );
  expect(
    "Kartu mobile menggantikan tabel desktop",
    workspace.includes("md:hidden") &&
      workspace.includes("hidden md:block") &&
      ["product.name", "product.sku", "Tersedia", "Layak Dijual", "Sudah Dipesan", "Batch"].every(
        (value) => workspace.includes(value),
      ),
  );
  const productCards = workspace.slice(
    workspace.indexOf("function ProductCards"),
    workspace.indexOf("function ProductTable"),
  );
  expect(
    "Kartu mobile hanya memuat posisi stok ringkas",
    !productCards.includes("ProductStatus"),
  );
  expect(
    "Tabel desktop hanya menampilkan kolom posisi stok yang didukung",
    ["Produk", "Status", "Layak Dijual", "Sudah Dipesan", "Tersedia", "Batch"].every(
      (value) => workspace.includes(value),
    ) &&
      !workspace.includes("overflow-x-auto"),
  );
  expect(
    "Landing mengekspos aksi stok yang sudah siap",
    [
      "Catat Perubahan",
      "Barang Keluar",
      "Barang Rusak / Kedaluwarsa",
      "Hitung Stok",
      "Riwayat Stok",
      'href="/manual-outbounds"',
      'href="/stock-disposals"',
      'href="/stocktakes/new"',
      'href="/ledger"',
    ].every((value) => workspace.includes(value)),
  );
  expect(
    "Workspace menyediakan Tambah Produk dan Barang Masuk sebagai aksi kontekstual",
    rendered.includes("Tambah Produk") &&
      rendered.includes("Barang Masuk") &&
      rendered.includes('href="/receipts/new"'),
  );


  expect(
    "Landing tetap tidak mengekspos capability yang belum disetujui",
    ![

      "Stok Fisik",
      "Connected",
      "low stock",
      "href={`/products/${product.product_id}`}",
    ].some((value) => rendered.includes(value)),
  );

  expect(
    "Landing tidak membuat badge Aman palsu",
    !rendered.includes(">Aman<"),
  );

  expect(
    "Landing membaca kelanjutan Hitung Stok dari source authoritative",
    workspace.includes("getStocktakeList") &&
      workspace.includes("NON_TERMINAL_STOCKTAKE_STATUSES") &&
      workspace.includes(".find((stocktake)") &&
      workspace.includes("stocktake.status_code"),
  );

  expect(
    "Landing hanya menautkan kelanjutan ke sesi Hitung Stok yang tepat",
    workspace.includes(
      'href={`/stocktakes/${encodeURIComponent(stocktake.stocktake_id)}`}',
    ),
  );

  expect(
    "Kegagalan membaca kelanjutan Hitung Stok tidak mengubah posisi stok menjadi gagal",
    workspace.includes("Promise.allSettled") &&
      workspace.includes('stocktakeResult.status === "rejected"') &&
      workspace.includes('productResult.status === "rejected"'),
  );

  console.log("Stock workspace UI contract PASS");
}

main().catch((error) => {
  console.error(
    "Stock workspace UI contract FAIL",
    error instanceof Error ? error.message : String(error),
  );
  process.exitCode = 1;
});
