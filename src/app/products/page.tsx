import {
  Suspense,
} from "react";

import {
  AppShell,
} from "@/app/app-shell/app-shell";
import {
  PageHeader,
} from "@/app/app-shell/page-header";
import {
  StockWorkspace,
  StockWorkspaceLoading,
  WorkspaceActions,
} from "@/app/products/stock-workspace";
import {
  requireAdminSession,
} from "@/lib/auth";

export const dynamic = "force-dynamic";

type SearchParams = {
  q?: string;
  status?: string;
};

export default async function ProductsPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const [session, params] = await Promise.all([
    requireAdminSession(),
    searchParams,
  ]);

  return (
    <AppShell profile={session.profile}>
      <div className="mx-auto w-full max-w-[1200px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        <PageHeader
          action={<WorkspaceActions />}
          description="Pantau posisi stok dan catat perubahan bila diperlukan."
          title="Stok"
        />

        <Suspense fallback={<StockWorkspaceLoading />}>
          <StockWorkspace
            query={params.q}
            status={params.status}
          />
        </Suspense>
      </div>
    </AppShell>
  );
}
