import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Sistem Rekonsiliasi Stok",
  description:
    "Sistem pencatatan dan rekonsiliasi stok berbasis stock ledger, batch, dan FEFO.",
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
