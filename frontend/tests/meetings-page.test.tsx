import { screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { MeetingsPage } from "@/components/meetings-page";
import { api } from "@/lib/api";

import { renderWithQuery } from "./utils";

describe("MeetingsPage", () => {
  it("lists meetings from the API", async () => {
    vi.spyOn(api, "listMeetings").mockResolvedValue([
      {
        id: "1",
        title: "Design review",
        starts_at: "2026-10-01T07:00:00Z",
        ends_at: "2026-10-01T08:00:00Z",
        attendee_count: 6,
        created_at: "2026-09-30T00:00:00Z",
      },
    ]);
    renderWithQuery(<MeetingsPage />);
    expect(await screen.findByText("Design review")).toBeInTheDocument();
    expect(screen.getByText(/6 attendees/)).toBeInTheDocument();
    expect(screen.getByText("1 h")).toBeInTheDocument();
  });

  it("shows an empty state", async () => {
    vi.spyOn(api, "listMeetings").mockResolvedValue([]);
    renderWithQuery(<MeetingsPage />);
    expect(await screen.findByText("No meetings yet")).toBeInTheDocument();
  });

  it("shows an error with a retry button", async () => {
    vi.spyOn(api, "listMeetings").mockRejectedValue(new Error("boom"));
    renderWithQuery(<MeetingsPage />);
    expect(
      await screen.findByText("Could not load meetings"),
    ).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /retry/i })).toBeInTheDocument();
  });
});
