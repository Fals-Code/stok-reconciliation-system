import {
  redirect,
} from "next/navigation";

type SearchParams = Record<
  string,
  string | string[] | undefined
>;

export default async function ReconciliationCompatibilityPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const query = await searchParams;
  const params = new URLSearchParams();

  for (const [key, value] of Object.entries(query)) {
    if (Array.isArray(value)) {
      for (const item of value) {
        params.append(key, item);
      }
    } else if (value !== undefined) {
      params.set(key, value);
    }
  }

  const encoded = params.toString();
  redirect(`/stock-issues${encoded ? `?${encoded}` : ""}`);
}