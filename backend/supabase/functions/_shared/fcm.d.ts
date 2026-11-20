export const corsHeaders: Record<string, string>;

export function jsonResponse(data: unknown, status?: number): Response;

export interface FirebaseCredentials {
  projectId: string;
  clientEmail: string;
  privateKey: string;
}

export function resolveFirebaseCredentials(
  getEnv: (name: string) => string | undefined
): FirebaseCredentials | null;

export function normalizePemPrivateKey(privateKey: string): string;

export function createServiceAccountJwt(params: {
  clientEmail: string;
  privateKey: string;
  scope?: string;
  nowSeconds?: number;
  subtle?: SubtleCrypto;
}): Promise<string>;

export function clearAccessTokenCache(): void;

export function getGoogleAccessToken(params: {
  clientEmail: string;
  privateKey: string;
  fetchImpl?: typeof fetch;
  nowSeconds?: (() => number) | number;
  subtle?: SubtleCrypto;
  useCache?: boolean;
}): Promise<string>;

export function stringifyDataMap(input: Record<string, unknown> | null | undefined): Record<string, string>;

export function buildChildCommandFcmMessage(
  token: string,
  payload: Record<string, unknown>,
  nowMs?: number
): Record<string, unknown>;

export function buildParentAlertFcmMessage(
  token: string,
  params: { title: string; body: string; data?: Record<string, unknown> }
): Record<string, unknown>;

export function sendFcmV1Message(params: {
  projectId: string;
  accessToken: string;
  message: Record<string, unknown>;
  fetchImpl?: typeof fetch;
}): Promise<{ ok: boolean; status: number; result: Record<string, unknown> }>;

export function isStaleFcmTokenError(status: number, errorBody: unknown): boolean;
