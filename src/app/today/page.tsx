import { redirect } from "next/navigation";

/**
 * Compatibility redirect — /today merged into / (Beranda).
 * Preserves bookmarks and test links from the former Pusat Kendali route.
 */
export default function TodayRedirect() {
  redirect("/");
}
