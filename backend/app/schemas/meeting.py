import uuid
from datetime import datetime
from typing import Self

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, model_validator


class MeetingCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    # AwareDatetime rejects "2026-10-01T10:00:00" without an offset: the API
    # never guesses which timezone a client meant.
    starts_at: AwareDatetime
    ends_at: AwareDatetime
    attendee_count: int = Field(ge=0, le=10_000)

    @model_validator(mode="after")
    def _ends_after_start(self) -> Self:
        if self.ends_at <= self.starts_at:
            raise ValueError("ends_at must be later than starts_at")
        return self


class MeetingRead(MeetingCreate):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    created_at: datetime
