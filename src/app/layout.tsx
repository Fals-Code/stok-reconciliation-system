import type {
  Metadata,
  Viewport,
} from "next";

import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "Sistem Rekonsiliasi Stok",
    template: "%s | Sistem Rekonsiliasi Stok",
  },
  description:
    "Workspace Admin gudang untuk mengelola stok, pesanan, dan rekonsiliasi.",
};

export const viewport: Viewport = {
  colorScheme: "light",
  themeColor: "#f7f8f6",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="id" data-scroll-behavior="smooth">
      <body className="bg-ui-canvas text-ui-text antialiased">
        {children}
      </body>
    </html>
  );
}