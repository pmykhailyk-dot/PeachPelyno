import { afterEach, describe, expect, it, vi } from "vitest";

import { ApiError, api } from "@/lib/api";

function mockFetch(body: unknown, init: { status?: number } = {}) {
  const status = init.status ?? 200;
  return vi.spyOn(globalThis, "fetch").mockResolvedValue({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  } as Response);
}

const meeting = {
  id: "11111111-1111-1111-1111-111111111111",
  title: "Weekly sync",
  starts_at: "2026-10-01T07:00:00Z",
  ends_at: "2026-10-01T07:30:00Z",
  attendee_count: 5,
  created_at: "2026-09-30T12:00:00Z",
};

afterEach(() => vi.restoreAllMocks());

describe("api", () => {
  it("parses the meeting list", async () => {
    const spy = mockFetch([meeting]);
    await expect(api.listMeetings()).resolves.toEqual([meeting]);
    expect(spy.mock.calls[0][0]).toMatch(/\/api\/meetings$/);
  });

  it("posts a new meeting as JSON", async () => {
    const spy = mockFetch(meeting, { status: 201 });
    const payload = {
      title: meeting.title,
      starts_at: meeting.starts_at,
      ends_at: meeting.ends_at,
      attendee_count: meeting.attendee_count,
    };
    await expect(api.createMeeting(payload)).resolves.toEqual(meeting);
    const init = spy.mock.calls[0][1];
    expect(init?.method).toBe("POST");
    expect(JSON.parse(init?.body as string)).toEqual(payload);
  });

  it("raises ApiError carrying the detail from the backend", async () => {
    mockFetch({ detail: "database unavailable" }, { status: 503 });
    await expect(api.listMeetings()).rejects.toMatchObject({
      status: 503,
      message: "database unavailable",
    });
  });

  it("rejects a response that breaks the contract", async () => {
    mockFetch([{ ...meeting, attendee_count: "five" }]);
    await expect(api.listMeetings()).rejects.toThrow();
  });

  it("raises ApiError when the network is unreachable", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async () => {
      throw new TypeError("failed");
    });
    await expect(api.listMeetings()).rejects.toBeInstanceOf(ApiError);
  });
});
