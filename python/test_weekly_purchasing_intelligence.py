import json
import unittest

from weekly_purchasing_intelligence import analyze_json


def snapshot(weights):
    return {
        "schema_version": 1,
        "weeks": [
            {
                "week_start": f"2026-09-{day:02d}",
                "products": {"cashew": weight},
            }
            for day, weight in zip((7, 14, 21, 28), weights)
        ],
    }


class WeeklyPurchasingIntelligenceTests(unittest.TestCase):
    def test_normal_data_returns_totals_changes_and_history(self):
        data = snapshot([100, 120, 80, 110])
        data["weeks"].append(
            {"week_start": "2026-10-05", "products": {"cashew": 105}}
        )

        result = analyze_json(json.dumps(data))
        latest = result["latest_week"]
        self.assertEqual(result["weekly_totals"][-1]["total_weight"], 105)
        self.assertEqual(latest["week_over_week_percent"], -4.5455)
        self.assertEqual(latest["historical_mean"], 102.5)
        self.assertEqual(latest["historical_median"], 105)
        self.assertFalse(latest["unusual_volume"])
        self.assertFalse(result["products"][0]["unusual_volume"])

    def test_unusual_volume_is_explained_and_advisory(self):
        data = snapshot([100, 110, 90, 100])
        data["weeks"].append(
            {"week_start": "2026-10-05", "products": {"cashew": 500}}
        )

        result = analyze_json(json.dumps(data))
        self.assertTrue(result["latest_week"]["unusual_volume"])
        self.assertIn("not a forecast", result["latest_week"]["unusual_volume_explanation"])
        self.assertTrue(result["products"][0]["unusual_volume"])

    def test_zero_baseline_has_no_infinite_percentage(self):
        data = snapshot([0, 0, 0, 0])
        data["weeks"].append(
            {"week_start": "2026-10-05", "products": {"cashew": 25}}
        )

        result = analyze_json(json.dumps(data))
        self.assertIsNone(result["latest_week"]["week_over_week_percent"])
        self.assertTrue(result["latest_week"]["unusual_volume"])

    def test_insufficient_history_is_not_classified(self):
        data = {
            "schema_version": 1,
            "weeks": [
                {"week_start": "2026-09-28", "products": {"cashew": 100}},
                {"week_start": "2026-10-05", "products": {"cashew": 300}},
            ],
        }

        result = analyze_json(json.dumps(data))
        self.assertIsNone(result["latest_week"]["unusual_volume"])
        self.assertIn("at least 4 prior weeks", result["latest_week"]["unusual_volume_explanation"])

    def test_missing_values_are_zero_and_invalid_json_is_safe(self):
        data = {
            "schema_version": 1,
            "weeks": [
                {"week_start": "2026-09-28", "products": {"cashew": None}},
                {"week_start": "2026-10-05", "products": {}},
            ],
        }
        result = analyze_json(json.dumps(data))
        self.assertEqual(result["weekly_totals"], [
            {"week_start": "2026-09-28", "total_weight": 0.0},
            {"week_start": "2026-10-05", "total_weight": 0.0},
        ])
        self.assertEqual(analyze_json("{"), {"error": "Input is not valid UTF-8 JSON."})

    def test_rejects_invalid_types_and_oversized_payload(self):
        invalid = {
            "schema_version": 1,
            "weeks": [
                {"week_start": "2026-10-05", "products": {"cashew": True}}
            ],
        }
        self.assertIn("finite non-negative", analyze_json(json.dumps(invalid))["error"])
        self.assertIn("maximum allowed size", analyze_json(" " * (256 * 1024 + 1))["error"])


if __name__ == "__main__":
    unittest.main()
