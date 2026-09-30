import { describe, expect, it } from "vitest";

import type { Meeting } from "@/lib/api";
import { percentChange, startOfWeek, weekOverWeek } from "@/lib/meeting-stats";

function m(start: Date, minutes: number, attendees: number): Meeting {
  return {
    id: crypto.randomUUID(),
    title: "x",
    starts_at: start.toISOString(),
    ends_at: new Date(start.getTime() + minutes * 60_000).toISOString(),
    attendee_count: attendees,
    created_at: start.toISOString(),
  };
}

describe("meeting stats", () => {
  const now = new Date(2026, 8, 30, 12, 0); // Wednesday 30 Sep 2026, local

  it("weeks start on Monday", () => {
    expect(startOfWeek(now)).toEqual(new Date(2026, 8, 28, 0, 0));
  });

  it("compares this week with last week", () => {
    const meetings = [
      m(new Date(2026, 8, 28, 10), 60, 4), // this week
      m(new Date(2026, 8, 30, 9), 30, 2), // this week
      m(new Date(2026, 8, 22, 10), 60, 6), // last week
      m(new Date(2026, 9, 6, 10), 60, 6), // next week: ignored
    ];
    const { current, previous } = weekOverWeek(meetings, now);
    expect(current).toEqual({ meetings: 2, hours: 1.5, avgAttendees: 3 });
    expect(previous).toEqual({ meetings: 1, hours: 1, avgAttendees: 6 });
  });

  it("reports no change against an empty week as null", () => {
    expect(percentChange(3, 0)).toBeNull();
    expect(percentChange(3, 2)).toBe(50);
  });
});
