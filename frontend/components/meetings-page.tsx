"use client";

import { useQuery } from "@tanstack/react-query";
import { CalendarDays, Clock, Plus, RotateCw, Users } from "lucide-react";
import { useState } from "react";

import { MeetingFormDialog } from "@/components/meeting-form-dialog";
import { MeetingStats } from "@/components/meeting-stats";
import { PageHeader } from "@/components/page-header";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { api, type Meeting } from "@/lib/api";

const dayFormat = new Intl.DateTimeFormat("en-GB", {
  weekday: "long",
  day: "numeric",
  month: "long",
});
const timeFormat = new Intl.DateTimeFormat("en-GB", {
  hour: "2-digit",
  minute: "2-digit",
});

function dayKey(iso: string): string {
  const d = new Date(iso);
  return `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
}

function groupByDay(meetings: Meeting[]): [string, Meeting[]][] {
  const groups = new Map<string, Meeting[]>();
  for (const m of meetings) {
    const key = dayKey(m.starts_at);
    groups.set(key, [...(groups.get(key) ?? []), m]);
  }
  return [...groups.values()].map((list) => [
    dayFormat.format(new Date(list[0].starts_at)),
    list,
  ]);
}

function durationLabel(m: Meeting): string {
  const minutes = Math.round(
    (new Date(m.ends_at).getTime() - new Date(m.starts_at).getTime()) / 60_000,
  );
  if (minutes < 60) return `${minutes} min`;
  const h = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return rest ? `${h} h ${rest} min` : `${h} h`;
}

function MeetingCard({ meeting }: { meeting: Meeting }) {
  return (
    <li className="flex items-center gap-4 rounded-xl border bg-card p-4 shadow-notion-xs transition hover:shadow-notion-sm">
      <div className="grid w-16 shrink-0 text-center">
        <span className="font-heading text-lg font-semibold tabular-nums">
          {timeFormat.format(new Date(meeting.starts_at))}
        </span>
        <span className="text-xs text-muted-foreground tabular-nums">
          {timeFormat.format(new Date(meeting.ends_at))}
        </span>
      </div>
      <div className="min-w-0 flex-1 border-l pl-4">
        <p className="truncate font-medium">{meeting.title}</p>
        <p className="mt-1 flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-muted-foreground">
          <span className="inline-flex items-center gap-1">
            <Clock aria-hidden className="size-3.5" />
            {durationLabel(meeting)}
          </span>
          <span className="inline-flex items-center gap-1">
            <Users aria-hidden className="size-3.5" />
            {meeting.attendee_count}{" "}
            {meeting.attendee_count === 1 ? "attendee" : "attendees"}
          </span>
        </p>
      </div>
    </li>
  );
}

export function MeetingsPage() {
  const [dialogOpen, setDialogOpen] = useState(false);
  const query = useQuery({ queryKey: ["meetings"], queryFn: api.listMeetings });

  return (
    <main className="mx-auto grid w-full max-w-5xl gap-8 px-6 py-10 sm:px-8">
      <PageHeader
        icon="📅"
        title="Meetings"
        description="Everything on the team calendar, and how this week compares to last week."
        action={
          <Button size="lg" onClick={() => setDialogOpen(true)}>
            <Plus data-icon="inline-start" className="size-4" />
            New meeting
          </Button>
        }
      />

      {query.isPending && (
        <div className="grid gap-3">
          <div className="grid gap-3 sm:grid-cols-3">
            {[0, 1, 2].map((i) => (
              <Skeleton key={i} className="h-32 rounded-xl" />
            ))}
          </div>
          {[0, 1, 2].map((i) => (
            <Skeleton key={i} className="h-20 rounded-xl" />
          ))}
        </div>
      )}

      {query.isError && (
        <Alert variant="destructive">
          <AlertTitle>Could not load meetings</AlertTitle>
          <AlertDescription className="flex flex-wrap items-center gap-3">
            {query.error.message}
            <Button size="sm" variant="outline" onClick={() => query.refetch()}>
              <RotateCw data-icon="inline-start" className="size-3.5" />
              Retry
            </Button>
          </AlertDescription>
        </Alert>
      )}

      {query.isSuccess && (
        <>
          <MeetingStats meetings={query.data} />

          {query.data.length === 0 ? (
            <div className="grid place-items-center gap-3 rounded-xl border border-dashed p-12 text-center">
              <CalendarDays
                aria-hidden
                className="size-8 text-muted-foreground"
              />
              <p className="font-medium">No meetings yet</p>
              <Button onClick={() => setDialogOpen(true)}>
                <Plus data-icon="inline-start" className="size-4" />
                Add the first one
              </Button>
            </div>
          ) : (
            <section aria-label="Meetings" className="grid gap-6">
              {groupByDay(query.data).map(([day, meetings]) => (
                <div key={day} className="grid gap-2">
                  <h2 className="text-sm font-semibold text-muted-foreground">
                    {day}
                  </h2>
                  <ul className="grid gap-2">
                    {meetings.map((m) => (
                      <MeetingCard key={m.id} meeting={m} />
                    ))}
                  </ul>
                </div>
              ))}
            </section>
          )}
        </>
      )}

      <MeetingFormDialog open={dialogOpen} onOpenChange={setDialogOpen} />
    </main>
  );
}
