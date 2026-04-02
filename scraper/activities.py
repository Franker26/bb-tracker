from dataclasses import dataclass
from datetime import datetime


@dataclass
class Activity:
    id: str
    title: str
    course_id: str
    course_name: str
    due_date: datetime | None
    status: str        # "pending" | "submitted" | "overdue"
    url: str
    score: str | None  # ej. "8.5 / 10" o None si no hay nota
    description: str | None
