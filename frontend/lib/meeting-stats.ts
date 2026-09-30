import type { Meeting } from "@/lib/api";

/** Monday 00:00 local time of the week containing `date`. */
export function startOfWeek(date: Date): Date {
  const d = new Date(date);
  d.setHours(0, 0, 0, 0);
  const day = (d.getDay() + 6) % 7; // Monday = 0
  d.setDate(d.getDate() - day);
  return d;
}

export type WeekStats = {
  meetings: number;
  hours: number;
  avgAttendees: number;
};

function statsFor(meetings: Meeting[], from: Date, to: Date): WeekStats {
  const inWeek = meetings.filter((m) => {
    const start = new Date(m.starts_at);
    return start >= from && start < to;
  });
  const minutes = inWeek.reduce(
    (sum, m) =>
      sum +
      (new Date(m.ends_at).getTime() - new Date(m.starts_at).getTime()) /
        60_000,
    0,
  );
  const attendees = inWeek.reduce((sum, m) => sum + m.attendee_count, 0);
  return {
    meetings: inWeek.length,
    hours: Math.round((minutes / 60) * 10) / 10,
    avgAttendees:
      inWeek.length === 0
        ? 0
        : Math.round((attendees / inWeek.length) * 10) / 10,
  };
}

/** This week against last week, both Monday-to-Monday in local time. */
export function weekOverWeek(meetings: Meeting[], now: Date = new Date()) {
  const thisWeek = startOfWeek(now);
  const nextWeek = new Date(thisWeek);
  nextWeek.setDate(nextWeek.getDate() + 7);
  const lastWeek = new Date(thisWeek);
  lastWeek.setDate(lastWeek.getDate() - 7);
  return {
    current: statsFor(meetings, thisWeek, nextWeek),
    previous: statsFor(meetings, lastWeek, thisWeek),
  };
}

/** Percentage change, or null when there is nothing to compare against. */
export function percentChange(
  current: number,
  previous: number,
): number | null {
  if (previous === 0) return null;
  return Math.round(((current - previous) / previous) * 100);
}
