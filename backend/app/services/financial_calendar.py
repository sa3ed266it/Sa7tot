from __future__ import annotations

from calendar import monthrange
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


FALLBACK_TIMEZONE = "Europe/Rome"


@dataclass(frozen=True, slots=True)
class FinancialPeriodWindow:
    local_start: date
    local_end: date
    utc_start: datetime
    utc_end: datetime


def _zone(timezone_name: str | None) -> ZoneInfo:
    try:
        return ZoneInfo(timezone_name or FALLBACK_TIMEZONE)
    except ZoneInfoNotFoundError:
        return ZoneInfo(FALLBACK_TIMEZONE)


def _window(start: date, end: date, timezone_name: str | None) -> FinancialPeriodWindow:
    zone = _zone(timezone_name)
    return FinancialPeriodWindow(
        local_start=start,
        local_end=end,
        utc_start=datetime.combine(start, time.min, tzinfo=zone).astimezone(UTC),
        utc_end=datetime.combine(end, time.min, tzinfo=zone).astimezone(UTC),
    )


def _validate_month_start_day(day: int) -> None:
    if not 1 <= day <= 31:
        raise ValueError("month_start_day must be between 1 and 31")


def _validate_week_start_day(day: int) -> None:
    if not 1 <= day <= 7:
        raise ValueError("week_start_day must be between 1 and 7")


def _clamped_day(year: int, month: int, configured_day: int) -> int:
    return min(configured_day, monthrange(year, month)[1])


def _shift_month(year: int, month: int, delta: int) -> tuple[int, int]:
    absolute = year * 12 + month - 1 + delta
    return absolute // 12, absolute % 12 + 1


def financial_month_window(
    anchor_date: date,
    month_start_day: int,
    timezone_name: str | None,
) -> FinancialPeriodWindow:
    _validate_month_start_day(month_start_day)
    current_boundary = date(
        anchor_date.year,
        anchor_date.month,
        _clamped_day(anchor_date.year, anchor_date.month, month_start_day),
    )
    if anchor_date >= current_boundary:
        start = current_boundary
        next_year, next_month = _shift_month(anchor_date.year, anchor_date.month, 1)
        end = date(next_year, next_month, _clamped_day(next_year, next_month, month_start_day))
    else:
        end = current_boundary
        previous_year, previous_month = _shift_month(anchor_date.year, anchor_date.month, -1)
        start = date(
            previous_year,
            previous_month,
            _clamped_day(previous_year, previous_month, month_start_day),
        )
    return _window(start, end, timezone_name)


def financial_week_window(
    anchor_date: date,
    week_start_day: int,
    timezone_name: str | None,
) -> FinancialPeriodWindow:
    _validate_week_start_day(week_start_day)
    start = anchor_date - timedelta(days=(anchor_date.isoweekday() - week_start_day) % 7)
    return _window(start, start + timedelta(days=7), timezone_name)
