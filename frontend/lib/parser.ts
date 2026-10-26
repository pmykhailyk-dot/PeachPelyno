import { z } from "zod";

import { actionItemSchema, agendaItemSchema } from "@/lib/api";

/** The agenda-parser Lambda's own URL (infra/ai.tf), separate from the main
 *  API - Paste an agenda never goes through the backend, only Save does. */
function parserUrl(): string {
  const url = process.env.NEXT_PUBLIC_PARSER_URL;
  if (!url) {
    throw new ParserError(
      0,
      "Paste an agenda is not set up yet (no parser URL)",
    );
  }
  return url;
}

export class ParserError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "ParserError";
  }
}

export const parsedAgendaSchema = z.object({
  title: z.string().nullable(),
  starts_at: z.string().nullable(),
  duration_minutes: z.number().int().nullable(),
  items: z.array(agendaItemSchema),
  action_items: z.array(actionItemSchema),
  language: z.string(),
});

const parseResponseSchema = z.object({
  agenda: parsedAgendaSchema,
  model: z.string(),
  prompt_version: z.string(),
});

export type ParsedAgenda = z.infer<typeof parsedAgendaSchema>;
export type ParseResponse = z.infer<typeof parseResponseSchema>;

const KNOWN_STATUSES = new Set([400, 401, 413, 422, 429]);

function messageForStatus(status: number): string {
  switch (status) {
    case 401:
      return "Your session expired - sign in again to use Paste an agenda";
    case 400:
      return "Paste some text first";
    case 413:
      return "That text is too long to parse (max 10,000 characters)";
    case 422:
      return "Could not find an agenda in that text";
    case 429:
      return "The model is busy right now - try again in a moment";
    default:
      return `Parsing failed (${status})`;
  }
}

/** The user's local "today" and IANA time zone, so the model resolves
 *  relative dates ("Monday", "by Friday") against the user's calendar, not
 *  the Lambda's UTC clock. */
function todayAndTz(): { today: string; tz: string } {
  const now = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  return {
    today: `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`,
    tz: Intl.DateTimeFormat().resolvedOptions().timeZone,
  };
}

export async function parseAgenda(
  text: string,
  idToken: string,
  signal?: AbortSignal,
): Promise<ParseResponse> {
  let response: Response;
  try {
    response = await fetch(parserUrl(), {
      method: "POST",
      signal,
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${idToken}`,
      },
      body: JSON.stringify({ text, ...todayAndTz() }),
    });
  } catch (err) {
    if (err instanceof DOMException && err.name === "AbortError") throw err;
    throw new ParserError(0, "Could not reach the parser");
  }

  if (!response.ok) {
    // Known statuses get the friendly message; the Lambda's own error text
    // ("no agenda returned (stop_reason=end_turn)") is for the logs.
    if (KNOWN_STATUSES.has(response.status)) {
      throw new ParserError(response.status, messageForStatus(response.status));
    }
    const detail = await response
      .json()
      .then((body) => (typeof body?.error === "string" ? body.error : null))
      .catch(() => null);
    throw new ParserError(
      response.status,
      detail ?? messageForStatus(response.status),
    );
  }

  return parseResponseSchema.parse(await response.json());
}
