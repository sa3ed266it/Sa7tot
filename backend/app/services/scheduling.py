from __future__ import annotations

import calendar
from datetime import date, timedelta

from app.core.errors import DomainError


def _month_date(year: int, month: int, day: int) -> date:
    return date(year, month, min(day, calendar.monthrange(year, month)[1]))


def _add_months(value: date, months: int, anchor_day: int) -> date:
    index = value.year * 12 + value.month - 1 + months
    year, month_index = divmod(index, 12)
    return _month_date(year, month_index + 1, anchor_day)


def occurrence_at_index(anchor: date, cadence: str, interval: int, index: int) -> date:
    if interval < 1 or index < 0:
        raise DomainError(422, "cadence interval must be at least 1", "invalid_cadence_interval")
    if cadence == "daily":
        return anchor + timedelta(days=index * interval)
    if cadence == "weekly":
        return anchor + timedelta(weeks=index * interval)
    if cadence == "monthly":
        return _add_months(anchor, index * interval, anchor.day)
    if cadence == "yearly":
        return _month_date(anchor.year + index * interval, anchor.month, anchor.day)
    raise DomainError(422, "unsupported cadence", "invalid_cadence")


def first_occurrence_on_or_after(start: date, anchor: date, cadence: str, interval: int) -> date:
    if start <= anchor:
        return anchor

    if cadence == "daily":
        estimate = max(0, (start - anchor).days // interval)
    elif cadence == "weekly":
        estimate = max(0, (start - anchor).days // (7 * interval))
    elif cadence == "monthly":
        estimate = max(0, ((start.year - anchor.year) * 12 + start.month - anchor.month) // interval)
    elif cadence == "yearly":
        estimate = max(0, (start.year - anchor.year) // interval)
    else:
        raise DomainError(422, "unsupported cadence", "invalid_cadence")

    candidate = occurrence_at_index(anchor, cadence, interval, estimate)
    while candidate < start:
        estimate += 1
        candidate = occurrence_at_index(anchor, cadence, interval, estimate)
    while estimate > 0:
        previous = occurrence_at_index(anchor, cadence, interval, estimate - 1)
        if previous < start:
            break
        estimate -= 1
        candidate = previous
    return candidate


def next_occurrence_after(value: date, anchor: date, cadence: str, interval: int) -> date:
    candidate = first_occurrence_on_or_after(value, anchor, cadence, interval)
    if candidate > value:
        return candidate
    index = 0
    while occurrence_at_index(anchor, cadence, interval, index) <= value:
        index += 1
    return occurrence_at_index(anchor, cadence, interval, index)


def occurrences_through(start: date, end: date, anchor: date, cadence: str, interval: int) -> list[date]:
    if start > end:
        return []
    current = first_occurrence_on_or_after(start, anchor, cadence, interval)
    result: list[date] = []
    while current <= end:
        result.append(current)
        current = next_occurrence_after(current, anchor, cadence, interval)
    return result
