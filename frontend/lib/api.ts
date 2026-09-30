import { z } from "zod";

/** Browser code must reach the API through the published port; server components
 *  resolve the Compose service name instead. */
export function apiBaseUrl(): string {
  if (typeof window === "undefined") {
    return process.env.INTERNAL_API_URL ?? "http://backend:8000";
  }
  return process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000";
}

export class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

async function request<T>(
  path: string,
  schema: z.ZodType<T>,
  init?: RequestInit,
): Promise<T> {
  let response: Response;
  try {
    response = await fetch(`${apiBaseUrl()}${path}`, {
      ...init,
      cache: "no-store",
      headers: {
        "Content-Type": "application/json",
        ...(init?.headers ?? {}),
      },
    });
  } catch {
    throw new ApiError(0, "Could not reach the API");
  }

  if (!response.ok) {
    const detail = await response
      .json()
      .then((body) => (typeof body?.detail === "string" ? body.detail : null))
      .catch(() => null);
    throw new ApiError(
      response.status,
      detail ?? `Request failed (${response.status})`,
    );
  }

  return schema.parse(await response.json());
}

/* --- schemas mirroring the API contract in PROJECT.md section 5 --- */

export const meetingSchema = z.object({
  id: z.string(),
  title: z.string(),
  starts_at: z.string(), // ISO 8601 with offset, e.g. 2026-10-01T07:00:00Z
  ends_at: z.string(),
  attendee_count: z.number().int(),
  created_at: z.string(),
});

export const meetingListSchema = z.array(meetingSchema);

export const healthSchema = z.object({
  status: z.string(),
  database: z.string(),
});

/** What POST /api/meetings accepts. Datetimes must carry an offset. */
export type MeetingCreate = {
  title: string;
  starts_at: string;
  ends_at: string;
  attendee_count: number;
};

export type Meeting = z.infer<typeof meetingSchema>;
export type Health = z.infer<typeof healthSchema>;

/* --- endpoints --- */

export const api = {
  readiness: () => request("/api/health/ready", healthSchema),

  listMeetings: () => request("/api/meetings", meetingListSchema),

  createMeeting: (payload: MeetingCreate) =>
    request("/api/meetings", meetingSchema, {
      method: "POST",
      body: JSON.stringify(payload),
    }),
};
