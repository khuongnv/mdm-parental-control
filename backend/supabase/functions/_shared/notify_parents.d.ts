export const VALID_EVENT_TYPES: readonly string[];

export function resolveEventTable(eventType: string): "time_requests" | "device_messages" | null;

export function deduplicateParentUserIds(
  memberRows: Array<{ user_id?: string | null }> | null | undefined,
  familyRow: { created_by?: string | null } | null | undefined
): string[];

export function buildParentNotificationCopy(params: {
  eventType: string;
  deviceName?: string | null;
  title?: string | null;
  body?: string | null;
  data?: Record<string, unknown> | null;
  claimedRecord?: Record<string, unknown> | null;
}): { title: string; body: string };

export function handleNotifyFamilyParents(params: {
  payload: Record<string, unknown>;
  env: Record<string, string | undefined> | ((key: string) => string | undefined);
  fetchImpl?: typeof fetch;
  nowMs?: number;
  accessTokenProvider?: ((creds: { projectId: string; clientEmail: string; privateKey: string }) => Promise<string>) | null;
}): Promise<{ status: number; body: Record<string, unknown> }>;
