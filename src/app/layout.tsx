import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "GlowLab Inventory | Sistem Rekonsiliasi Stok",
  description:
    "Dashboard operasional untuk penerimaan, outbound FEFO, posisi inventory, dan immutable stock ledger.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="id">
      <body>{children}</body>
    </html>
  );
}
