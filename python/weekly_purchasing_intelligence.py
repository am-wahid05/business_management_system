"""Offline statistics for a company-scoped weekly purchasing snapshot.

Input contains only weekly aggregate weights keyed by product ID. Missing
product entries and explicit null values mean zero for that week.
"""

from __future__ import annotations

import json
import math
import statistics
import sys
from datetime import date
from typing import Any

MAX_INPUT_BYTES = 256 * 1024
MAX_WEEKS = 260
MAX_PRODUCTS = 100
MIN_HISTORY_WEEKS = 4
UNUSUAL_STANDARD_DEVIATIONS = 2


def analyze_json(payload: str | bytes) -> dict[str, Any]:
    """Validate a JSON snapshot and return advisory weekly statistics.

    Invalid input returns a small error object; caller input is never echoed.
    """
    try:
        if isinstance(payload, bytes):
            if len(payload) > MAX_INPUT_BYTES:
                raise ValueError("Input exceeds the maximum allowed size.")
            text = payload.decode("utf-8")
        elif isinstance(payload, str):
            if len(payload.encode("utf-8")) > MAX_INPUT_BYTES:
                raise ValueError("Input exceeds the maximum allowed size.")
            text = payload
        else:
            raise ValueError("Input must be JSON text.")

        snapshot = json.loads(text)
        return analyze_snapshot(snapshot)
    except (UnicodeDecodeError, json.JSONDecodeError):
        return {"error": "Input is not valid UTF-8 JSON."}
    except ValueError as error:
        return {"error": str(error)}


def analyze_snapshot(snapshot: Any) -> dict[str, Any]:
    """Calculate latest-week insights from a validated structured snapshot."""
    if not isinstance(snapshot, dict) or snapshot.get("schema_version") != 1:
        raise ValueError("Unsupported snapshot format.")

    weeks = snapshot.get("weeks")
    if not isinstance(weeks, list) or not weeks:
        raise ValueError("Snapshot must contain at least one week.")
    if len(weeks) > MAX_WEEKS:
        raise ValueError("Snapshot contains too many weeks.")

    parsed_weeks: list[tuple[str, dict[str, float]]] = []
    all_products: set[str] = set()
    previous_day: date | None = None
    for entry in weeks:
        if not isinstance(entry, dict):
            raise ValueError("Each week must be an object.")
        week_start = entry.get("week_start")
        if not isinstance(week_start, str):
            raise ValueError("Each week needs a valid week_start date.")
        try:
            parsed_day = date.fromisoformat(week_start)
        except ValueError:
            raise ValueError("Each week needs a valid week_start date.") from None
        if parsed_day.isoformat() != week_start or parsed_day.weekday() != 0:
            raise ValueError("week_start must be an ISO Monday date.")
        if previous_day is not None and parsed_day <= previous_day:
            raise ValueError("Weeks must be in strictly increasing order.")
        previous_day = parsed_day

        products = entry.get("products", {})
        if not isinstance(products, dict):
            raise ValueError("Weekly products must be an object.")
        if len(products) > MAX_PRODUCTS:
            raise ValueError("Snapshot contains too many products in one week.")
        normalized: dict[str, float] = {}
        for product_id, value in products.items():
            if (
                not isinstance(product_id, str)
                or not product_id.strip()
                or len(product_id) > 80
            ):
                raise ValueError("Product IDs must be non-empty strings of at most 80 characters.")
            if value is None:
                normalized[product_id] = 0.0
            elif (
                isinstance(value, bool)
                or not isinstance(value, (int, float))
                or not math.isfinite(value)
                or value < 0
            ):
                raise ValueError("Product weights must be finite non-negative numbers or null.")
            else:
                normalized[product_id] = float(value)
            all_products.add(product_id)
        parsed_weeks.append((week_start, normalized))

    if len(all_products) > MAX_PRODUCTS:
        raise ValueError("Snapshot contains too many products.")

    product_ids = sorted(all_products)
    totals = [
        sum(products.get(product_id, 0.0) for product_id in product_ids)
        for _, products in parsed_weeks
    ]
    latest_total = totals[-1]
    previous_total = totals[-2] if len(totals) > 1 else None
    history = totals[:-1]
    latest = {
        "week_start": parsed_weeks[-1][0],
        "total_weight": latest_total,
        "week_over_week_percent": _percent_change(previous_total, latest_total),
        "historical_mean": _rounded(statistics.mean(history)) if history else None,
        "historical_median": _rounded(statistics.median(history)) if history else None,
        "history_weeks": len(history),
    }
    latest["unusual_volume"] = _unusual(latest_total, history)
    latest["unusual_volume_explanation"] = _unusual_explanation(
        latest_total, history
    )

    product_insights = []
    for product_id in product_ids:
        product_totals = [
            products.get(product_id, 0.0) for _, products in parsed_weeks
        ]
        current = product_totals[-1]
        prior = product_totals[-2] if len(product_totals) > 1 else None
        product_history = product_totals[:-1]
        product_insights.append(
            {
                "product_id": product_id,
                "total_weight": current,
                "week_over_week_percent": _percent_change(prior, current),
                "historical_mean": (
                    _rounded(statistics.mean(product_history))
                    if product_history
                    else None
                ),
                "historical_median": (
                    _rounded(statistics.median(product_history))
                    if product_history
                    else None
                ),
                "history_weeks": len(product_history),
                "unusual_volume": _unusual(current, product_history),
                "unusual_volume_explanation": _unusual_explanation(
                    current, product_history
                ),
            }
        )

    return {
        "schema_version": 1,
        "method": (
            "Advisory only: unusual means current weekly weight is above the "
            "historical mean by more than two population standard deviations; "
            f"at least {MIN_HISTORY_WEEKS} prior weeks are required."
        ),
        "weekly_totals": [
            {"week_start": week_start, "total_weight": _rounded(total)}
            for (week_start, _), total in zip(parsed_weeks, totals)
        ],
        "latest_week": latest,
        "products": product_insights,
    }


def _percent_change(previous: float | None, current: float) -> float | None:
    if previous is None:
        return None
    if previous == 0:
        return 0.0 if current == 0 else None
    return _rounded((current - previous) / previous * 100)


def _unusual(current: float, history: list[float]) -> bool | None:
    if len(history) < MIN_HISTORY_WEEKS:
        return None
    return current > statistics.mean(history) + (
        UNUSUAL_STANDARD_DEVIATIONS * statistics.pstdev(history)
    )


def _unusual_explanation(current: float, history: list[float]) -> str:
    if len(history) < MIN_HISTORY_WEEKS:
        return (
            f"Not assessed: at least {MIN_HISTORY_WEEKS} prior weeks are "
            "required."
        )
    mean = statistics.mean(history)
    deviation = statistics.pstdev(history)
    threshold = mean + UNUSUAL_STANDARD_DEVIATIONS * deviation
    if current > threshold:
        return (
            f"Above the historical mean plus {UNUSUAL_STANDARD_DEVIATIONS} "
            f"population standard deviations ({_rounded(threshold)} kg). "
            "This is an advisory signal, not a forecast."
        )
    return (
        f"Not above the historical mean plus {UNUSUAL_STANDARD_DEVIATIONS} "
        f"population standard deviations ({_rounded(threshold)} kg)."
    )


def _rounded(value: float) -> float:
    return round(value, 4)


def main() -> int:
    payload = sys.stdin.buffer.read(MAX_INPUT_BYTES + 1)
    result = analyze_json(payload)
    sys.stdout.write(json.dumps(result, allow_nan=False, separators=(",", ":")))
    sys.stdout.write("\n")
    return 2 if "error" in result else 0


if __name__ == "__main__":
    raise SystemExit(main())
