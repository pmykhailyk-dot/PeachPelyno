import uuid
from datetime import date, datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field


class AgendaItemIn(BaseModel):
    topic: str = Field(min_length=1, max_length=500)
    owner: str | None = Field(default=None, max_length=200)
    minutes: int | None = Field(default=None, ge=1, le=480)


class ActionItemIn(BaseModel):
    task: str = Field(min_length=1, max_length=500)
    owner: str | None = Field(default=None, max_length=200)
    due: date | None = None


class AgendaSave(BaseModel):
    """What ``PUT /api/meetings/{id}/agenda`` accepts - the checked, possibly
    corrected form. Never written by the model: only a human pressing Save
    reaches this endpoint (Lab 6, Part 4, Step 4)."""

    items: list[AgendaItemIn] = Field(default_factory=list)
    action_items: list[ActionItemIn] = Field(default_factory=list)
    # Present only when this save followed a Paste an agenda parse - the raw
    # suggestion, kept next to the user's corrected version as the feedback
    # signal (Part 0: "every correction is feedback").
    ai_suggestion: dict[str, Any] | None = None
    ai_model: str | None = Field(default=None, max_length=100)
    ai_prompt_version: str | None = Field(default=None, max_length=50)


class AgendaRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    meeting_id: uuid.UUID
    items: list[AgendaItemIn]
    action_items: list[ActionItemIn]
    ai_suggestion: dict[str, Any] | None
    ai_model: str | None
    ai_prompt_version: str | None
    created_at: datetime
    updated_at: datetime
