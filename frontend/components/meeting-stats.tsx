"use client";

import { ArrowDownRight, ArrowUpRight, Minus } from "lucide-react";

import type { Meeting } from "@/lib/api";
import { percentChange, weekOverWeek } from "@/lib/meeting-stats";
import { cn } from "@/lib/utils";

type TileProps = {
  label: string;
  value: number;
  previous: number;
  unit?: string;
};

function StatTile({ label, value, previous, unit }: TileProps) {
  const change = percentChange(value, previous);
  const Icon =
    change === null || change === 0
      ? Minus
      : change > 0
        ? ArrowUpRight
        : ArrowDownRight;
  return (
    <div className="rounded-xl border bg-card p-5 shadow-notion-xs">
      <p className="text-sm text-muted-foreground">{label}</p>
      <p className="mt-2 font-heading text-3xl font-semibold tabular-nums">
        {value}
        {unit && (
          <span className="ml-1 text-base font-medium text-muted-foreground">
            {unit}
          </span>
        )}
      </p>
      <p
        className={cn(
          "mt-2 inline-flex items-center gap-1 rounded-md px-1.5 py-0.5 text-xs font-medium",
          change === null || change === 0
            ? "bg-tint-gray text-muted-foreground"
            : change > 0
              ? "bg-tint-green text-tint-green-foreground"
              : "bg-tint-peach text-tint-peach-foreground",
        )}
      >
        <Icon aria-hidden className="size-3.5" />
        {change === null
          ? "no data last week"
          : `${change > 0 ? "+" : ""}${change}% vs last week`}
      </p>
    </div>
  );
}

export function MeetingStats({ meetings }: { meetings: Meeting[] }) {
  const { current, previous } = weekOverWeek(meetings);
  return (
    <section aria-label="This week" className="grid gap-3 sm:grid-cols-3">
      <StatTile
        label="Meetings this week"
        value={current.meetings}
        previous={previous.meetings}
      />
      <StatTile
        label="Time in meetings"
        value={current.hours}
        previous={previous.hours}
        unit="h"
      />
      <StatTile
        label="Avg. attendees"
        value={current.avgAttendees}
        previous={previous.avgAttendees}
      />
    </section>
  );
}
