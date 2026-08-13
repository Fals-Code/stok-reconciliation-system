import Link from "next/link";

import {
  acknowledgeNotificationAction,
  revokeNotificationAcknowledgmentAction,
  setNotificationReadStateAction,
} from "@/app/notifications/actions";
import {
  Alert,
  Button,
  EmptyState,
  StatusBadge,
} from "@/components/ui";
import {
  isSafeInternalRoute,
} from "@/lib/safe-internal-route";
import {
  getNotificationList,
  type NotificationListItem,
} from "@/lib/supabase-rest";

const RETURN_TO =
  "/notifications/operations#notification-state";

function formatDate(value: string | null) {
  if (!value) return "Waktu belum tersedia";

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return "Waktu belum tersedia";
  }

  return new Intl.DateTimeFormat("id-ID", {
    timeZone: "Asia/Jakarta",
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(date);
}

function severityLabel(value: string) {
  const labels: Record<string, string> = {
    CRITICAL: "Kritis",
    HIGH: "Mendesak",
    WARNING: "Perlu Diperiksa",
    INFO: "Informasi",
  };

  return labels[value] ?? "Informasi";
}

function severityTone(
  value: string,
): "danger" | "warning" | "neutral" {
  if (value === "CRITICAL") return "danger";
  if (value === "HIGH" || value === "WARNING") {
    return "warning";
  }

  return "neutral";
}

function lifecycleLabel(value: string) {
  if (value === "ACKNOWLEDGED") {
    return "Sedang Ditangani";
  }

  if (value === "RESOLVED") {
    return "Selesai";
  }

  return "Belum Ditangani";
}

function lifecycleTone(
  value: string,
): "selected" | "warning" | "neutral" {
  if (value === "ACKNOWLEDGED") {
    return "selected";
  }

  if (value === "OPEN") {
    return "warning";
  }

  return "neutral";
}

function readAction(notification: NotificationListItem) {
  if (notification.read_state_code === "UNREAD") {
    return {
      code: "READ",
      label: "Tandai sudah dibaca",
    } as const;
  }

  if (
    notification.read_state_code ===
    "ARCHIVED_FOR_USER"
  ) {
    return {
      code: "READ",
      label: "Tandai sudah dibaca",
    } as const;
  }

  return {
    code: "UNREAD",
    label: "Tandai belum dibaca",
  } as const;
}

function NotificationRow({
  notification,
}: {
  notification: NotificationListItem;
}) {
  const nextReadState = readAction(notification);
  const actionRoute =
    isSafeInternalRoute(notification.action_route)
      ? notification.action_route
      : null;

  return (
    <article className="border-b border-ui-border px-4 py-4 last:border-b-0 sm:px-5">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <StatusBadge
              tone={severityTone(
                notification.severity_code,
              )}
            >
              {severityLabel(
                notification.severity_code,
              )}
            </StatusBadge>

            <StatusBadge
              tone={lifecycleTone(
                notification.lifecycle_status_code,
              )}
            >
              {lifecycleLabel(
                notification.lifecycle_status_code,
              )}
            </StatusBadge>

            <span className="text-xs font-medium text-ui-text-muted">
              {notification.read_state_code ===
              "UNREAD"
                ? "Belum dibaca"
                : notification.read_state_code ===
                    "ARCHIVED_FOR_USER"
                  ? "Diarsipkan"
                  : "Sudah dibaca"}
            </span>
          </div>

          <h3 className="mt-2 text-sm font-semibold text-ui-text">
            {notification.title}
          </h3>

          <p className="mt-1 max-w-3xl text-sm leading-6 text-ui-text-muted">
            {notification.message}
          </p>

          <p className="mt-2 text-xs text-ui-text-muted">
            Terakhir diperbarui{" "}
            {formatDate(
              notification.last_seen_at,
            )}{" "}
            WIB
          </p>

          {actionRoute ? (
            <Link
              className="mt-3 inline-flex min-h-9 items-center text-sm font-semibold text-ui-primary hover:underline"
              href={actionRoute}
            >
              Buka pekerjaan
              <span
                aria-hidden="true"
                className="ml-1"
              >
                →
              </span>
            </Link>
          ) : null}
        </div>

        <div className="grid shrink-0 gap-2 sm:min-w-[250px]">
          <div className="flex flex-wrap gap-2">
            <form
              action={
                setNotificationReadStateAction
              }
            >
              <input
                name="notificationId"
                type="hidden"
                value={
                  notification.notification_id
                }
              />
              <input
                name="returnTo"
                type="hidden"
                value={RETURN_TO}
              />
              <input
                name="readStateCode"
                type="hidden"
                value={nextReadState.code}
              />

              <Button
                type="submit"
                variant="secondary"
              >
                {nextReadState.label}
              </Button>
            </form>

            {notification.read_state_code !==
            "ARCHIVED_FOR_USER" ? (
              <form
                action={
                  setNotificationReadStateAction
                }
              >
                <input
                  name="notificationId"
                  type="hidden"
                  value={
                    notification.notification_id
                  }
                />
                <input
                  name="returnTo"
                  type="hidden"
                  value={RETURN_TO}
                />
                <input
                  name="readStateCode"
                  type="hidden"
                  value="ARCHIVED_FOR_USER"
                />

                <Button
                  type="submit"
                  variant="secondary"
                >
                  Arsipkan
                </Button>
              </form>
            ) : null}
          </div>

          {notification.lifecycle_status_code ===
          "OPEN" ? (
            <form
              action={
                acknowledgeNotificationAction
              }
              className="grid gap-2"
            >
              <input
                name="notificationId"
                type="hidden"
                value={
                  notification.notification_id
                }
              />
              <input
                name="returnTo"
                type="hidden"
                value={RETURN_TO}
              />

              <label className="text-xs font-medium text-ui-text-muted">
                Catatan tindak lanjut
                <input
                  className="mt-1 min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3 text-sm text-ui-text outline-none focus:border-ui-primary"
                  maxLength={2000}
                  name="note"
                  placeholder={
                    notification.severity_code ===
                    "CRITICAL"
                      ? "Wajib untuk prioritas Kritis"
                      : "Opsional"
                  }
                  required={
                    notification.severity_code ===
                    "CRITICAL"
                  }
                />
              </label>

              <Button type="submit">
                Tandai sedang ditangani
              </Button>
            </form>
          ) : notification.lifecycle_status_code ===
            "ACKNOWLEDGED" ? (
            <form
              action={
                revokeNotificationAcknowledgmentAction
              }
              className="grid gap-2"
            >
              <input
                name="notificationId"
                type="hidden"
                value={
                  notification.notification_id
                }
              />
              <input
                name="returnTo"
                type="hidden"
                value={RETURN_TO}
              />

              <input
                className="min-h-[var(--ui-control-height)] w-full rounded-[var(--ui-radius-md)] border border-ui-border bg-ui-surface px-3 text-sm text-ui-text outline-none focus:border-ui-primary"
                maxLength={2000}
                name="note"
                placeholder="Alasan bila perlu"
              />

              <Button
                type="submit"
                variant="secondary"
              >
                Batalkan penandaan
              </Button>
            </form>
          ) : null}
        </div>
      </div>
    </article>
  );
}

export default async function NotificationStatePanel() {
  let notifications: NotificationListItem[];

  try {
    notifications = await getNotificationList({
      lifecycleStatusCode: null,
      severityCode: null,
      categoryCode: null,
      readStateCode: null,
      includeArchived: true,
      limit: 50,
      beforeLastSeenAt: null,
      beforeId: null,
    });
  } catch {
    return (
      <section
        className="mt-8 scroll-mt-24"
        id="notification-state"
      >
        <Alert
          title="Status notifikasi belum dapat dimuat"
          tone="danger"
        >
          Data notifikasi tidak dianggap aman atau
          kosong ketika pembacaan gagal. Muat ulang
          halaman untuk mencoba lagi.
        </Alert>
      </section>
    );
  }

  const rows = [...notifications].sort(
    (left, right) => {
      const order: Record<string, number> = {
        OPEN: 0,
        ACKNOWLEDGED: 1,
        RESOLVED: 2,
      };

      return (
        (order[left.lifecycle_status_code] ?? 9) -
        (order[right.lifecycle_status_code] ?? 9)
      );
    },
  );

  return (
    <section
      className="mt-8 scroll-mt-24"
      id="notification-state"
    >
      <div>
        <p className="text-xs font-semibold uppercase tracking-wide text-ui-text-muted">
          Notifikasi
        </p>

        <h2 className="mt-1 text-lg font-semibold text-ui-text">
          Status baca dan penanganan
        </h2>

        <p className="mt-1 max-w-3xl text-sm leading-6 text-ui-text-muted">
          Kelola status pribadi dan tandai notifikasi
          yang sedang ditangani. Tindakan di bagian
          ini tidak mengubah stok.
        </p>
      </div>

      {rows.length === 0 ? (
        <EmptyState
          className="mt-4"
          description="Belum ada notifikasi yang dapat dikelola."
          title="Tidak ada notifikasi"
        />
      ) : (
        <div className="mt-4 overflow-hidden rounded-[var(--ui-radius-lg)] border border-ui-border bg-ui-surface">
          {rows.map((notification) => (
            <NotificationRow
              key={notification.notification_id}
              notification={notification}
            />
          ))}
        </div>
      )}
    </section>
  );
}