import { randomUUID } from "node:crypto";
import Link from "next/link";
import { redirect } from "next/navigation";

import { AppShell } from "@/app/app-shell/app-shell";
import { PageHeader } from "@/app/app-shell/page-header";
import { StocktakeCreateForm } from "@/app/stocktakes/create-form";
import { StocktakePresentationFeedback } from "@/app/stocktakes/presentation-feedback";
import { Alert } from "@/components/ui";
import { requireAdminSession } from "@/lib/auth";
import { getStocktakeCreateOptions } from "@/lib/stocktakes/queries";

export const dynamic = "force-dynamic";

export default async function NewStocktakePage({
  searchParams,
}: {
  searchParams: Promise<{
    error?: string;
    idempotencyKey?: string;
    notice?: string;
  }>;
}) {
  const [session, params] = await Promise.all([
    requireAdminSession(),
    searchParams,
  ]);

  if (params.error || params.idempotencyKey) {
    redirect("/stocktakes/new?notice=retry");
  }

  let options;

  try {
    options = await getStocktakeCreateOptions();
  } catch {
    return (
      <AppShell profile={session.profile}>
        <div className="mx-auto w-full max-w-[960px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
          <PageHeader
            description="Pilihan untuk memulai hitung stok belum dapat dimuat. Kondisi gagal tidak mengubah stok."
            title="Mulai Hitung Stok"
          />
          <Alert
            className="mt-6"
            title="Data belum dapat dimuat"
            tone="warning"
          >
            Muat ulang halaman sebelum membuat Hitung Stok.
          </Alert>
        </div>
      </AppShell>
    );
  }

  const notice = params.notice;
  const shouldRestoreDraft = notice === "retry";

  return (
    <AppShell profile={session.profile}>
      <StocktakePresentationFeedback
        shouldSanitize={shouldRestoreDraft}
      />

      <div className="mx-auto w-full max-w-[960px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        <Link
          className="mb-4 inline-flex min-h-[var(--ui-control-height)] items-center text-sm font-semibold text-ui-primary hover:underline"
          href="/stocktakes"
        >
          &larr; Kembali ke Hitung Stok
        </Link>

        <PageHeader
          description="Tentukan apa yang akan dihitung. Membuat sesi belum mengubah stok."
          eyebrow="Stok"
          title="Mulai Hitung Stok"
        />

        {shouldRestoreDraft ? (
          <Alert
            className="mt-6"
            title="Hitung stok belum dibuat"
            tone="warning"
          >
            Isian sebelumnya dipulihkan. Periksa lalu coba buat sesi lagi.
          </Alert>
        ) : null}

        <StocktakeCreateForm
          idempotencyKey={randomUUID()}
          options={options}
          shouldRestoreDraft={shouldRestoreDraft}
        />
      </div>
    </AppShell>
  );
}