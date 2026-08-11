import { redirect } from "next/navigation";

/**
 * Compatibility redirect — /notifications merged into / (Beranda).
 * revalidatePath("/notifications") calls elsewhere are safe no-ops.
 * /notifications/operations is kept separately for admin troubleshooting.
 */
export default function NotificationsRedirect() {
  redirect("/");
}
