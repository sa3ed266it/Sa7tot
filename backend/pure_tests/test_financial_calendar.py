from datetime import date

import pytest

from app.services.financial_calendar import financial_month_window, financial_week_window


def test_default_month_and_week_windows_are_monday_and_calendar_month() -> None:
    anchor = date(2026, 8, 11)

    month = financial_month_window(anchor, 1, "Europe/Rome")
    week = financial_week_window(anchor, 1, "Europe/Rome")

    assert (month.local_start, month.local_end) == (date(2026, 8, 1), date(2026, 9, 1))
    assert (week.local_start, week.local_end) == (date(2026, 8, 10), date(2026, 8, 17))


def test_custom_month_and_week_preferences_use_the_anchor_date() -> None:
    month = financial_month_window(date(2026, 8, 11), 15, "Europe/Rome")
    week = financial_week_window(date(2026, 8, 11), 3, "Europe/Rome")

    assert (month.local_start, month.local_end) == (date(2026, 7, 15), date(2026, 8, 15))
    assert (week.local_start, week.local_end) == (date(2026, 8, 5), date(2026, 8, 12))


@pytest.mark.parametrize(
    "anchor, configured_day, expected_start, expected_end",
    [
        (date(2027, 3, 15), 31, date(2027, 2, 28), date(2027, 3, 31)),
        (date(2028, 3, 15), 31, date(2028, 2, 29), date(2028, 3, 31)),
        (date(2026, 5, 20), 31, date(2026, 4, 30), date(2026, 5, 31)),
        (date(2026, 12, 31), 31, date(2026, 12, 31), date(2027, 1, 31)),
    ],
)
def test_month_boundaries_clamp_to_the_actual_month_length(
    anchor: date,
    configured_day: int,
    expected_start: date,
    expected_end: date,
) -> None:
    window = financial_month_window(anchor, configured_day, "Europe/Rome")
    assert (window.local_start, window.local_end) == (expected_start, expected_end)


@pytest.mark.parametrize("week_start_day", range(1, 8))
def test_week_start_is_iso_monday_through_sunday(week_start_day: int) -> None:
    anchor = date(2026, 8, 9)  # Sunday
    window = financial_week_window(anchor, week_start_day, "Europe/Rome")
    assert window.local_start.isoweekday() == week_start_day
    assert (window.local_end - window.local_start).days == 7


def test_boundaries_are_local_midnights_and_dst_safe() -> None:
    window = financial_week_window(date(2026, 3, 29), 1, "Europe/Rome")

    assert window.local_start == date(2026, 3, 23)
    assert window.utc_start.isoformat() == "2026-03-22T23:00:00+00:00"
    assert window.utc_end.isoformat() == "2026-03-29T22:00:00+00:00"
    assert window.utc_end > window.utc_start


def test_named_timezone_is_used_for_utc_conversion() -> None:
    window = financial_week_window(date(2026, 8, 11), 1, "America/New_York")

    assert window.utc_start.isoformat() == "2026-08-10T04:00:00+00:00"
    assert window.utc_end.isoformat() == "2026-08-17T04:00:00+00:00"


def test_invalid_preferences_are_rejected_instead_of_clamped() -> None:
    with pytest.raises(ValueError):
        financial_month_window(date(2026, 8, 11), 0, "Europe/Rome")
    with pytest.raises(ValueError):
        financial_week_window(date(2026, 8, 11), 8, "Europe/Rome")
