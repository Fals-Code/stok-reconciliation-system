import type { Metadata } from "next";

import AppShell from "@/app/app-shell/app-shell";
import { getAdminSession } from "@/lib/auth";

import "./globals.css";

export const metadata: Metadata = {
  title: "GlowLab Inventory | Sistem Rekonsiliasi Stok",
  description:
    "Dashboard operasional untuk penerimaan, outbound FEFO, posisi inventory, dan immutable stock ledger.",
};

export default async function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const session = await getAdminSession();
  const appMode =
    process.env.NEXT_PUBLIC_APP_MODE?.trim().toUpperCase() || "LOCAL";

  return (
    <html lang="id" data-scroll-behavior="smooth">
      <body>
        {session ? (
          <AppShell
            appMode={appMode}
            profile={{
              displayName: session.profile.display_name,
              email: session.user.email ?? null,
              organizationCode: session.profile.organization_code,
              organizationName: session.profile.organization_name,
              roleCode: session.profile.role_code,
            }}
          >
            {children}
          </AppShell>
        ) : (
          children
        )}
      </body>
    </html>
  );
}