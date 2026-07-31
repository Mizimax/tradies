import importlib.util
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
AI_SCRIPT = ROOT / "scripts" / "mt5-ai-maxret-experiment.py"
TRAIN_SCRIPT = ROOT / "scripts" / "train-mt5-ml-filter.py"
RUNNER_SCRIPT = ROOT / "scripts" / "run-mt5-candidate.py"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class Mt5AiMaxretExperimentTests(unittest.TestCase):
    def test_readiness_rejects_journals_with_zero_feature_snapshots(self):
        module = load_module(AI_SCRIPT, "mt5_ai_maxret_experiment")
        journal = ROOT / "scratch" / "sample-ai-zero-features.trades.csv"
        journal.parent.mkdir(exist_ok=True)
        journal.write_text(
            "time\tmessage\n"
            "2026.01.01 10:00:00\tDeal event deal=1 entry=1 profit=5.00 dir=1 hour=10 setup=m5_scalp scalpVariant=1 confluences=6/6 scoreBucket=60\n"
            "2026.01.02 10:00:00\tDeal event deal=2 entry=1 profit=-3.00 dir=1 hour=10 setup=m5_scalp scalpVariant=1 confluences=6/6 scoreBucket=60\n"
        )
        self.addCleanup(journal.unlink)

        result = module.audit_journal(
            journal,
            from_date="2026.01.01",
            to_date="2026.01.02",
            min_closed_trades=2,
            min_feature_rich_ratio=0.80,
        )

        self.assertFalse(result.ok)
        self.assertIn("feature_rich_ratio", ";".join(result.reasons))
        self.assertEqual(result.closed_trades, 2)

    def test_generated_ai_candidate_rows_are_config_only_and_named(self):
        module = load_module(AI_SCRIPT, "mt5_ai_maxret_experiment")

        rows = module.generated_candidate_rows()

        self.assertEqual(len(rows), 8)
        self.assertTrue(all(row["name"].startswith("ai-maxret-s1-") for row in rows))
        self.assertTrue(all("@scalp-" in row["overrides"] or "@ai-maxret" in row["overrides"] for row in rows))
        self.assertFalse(any("xgboost" in row["overrides"].lower() for row in rows))
        self.assertFalse(any("lightgbm" in row["overrides"].lower() for row in rows))

    def test_generated_daily2_s3_rows_are_config_only_and_named(self):
        module = load_module(AI_SCRIPT, "mt5_ai_maxret_experiment")

        rows = module.generated_daily2_s3_rows()

        self.assertEqual(len(rows), 5)
        self.assertTrue(all(row["name"].startswith("daily2-ai-s3-") for row in rows))
        self.assertTrue(all(row["overrides"].startswith("@") for row in rows))
        self.assertFalse(any("xgboost" in row["overrides"].lower() for row in rows))
        self.assertFalse(any("lightgbm" in row["overrides"].lower() for row in rows))

    def test_feature_matrix_category_encoding_is_stable(self):
        trainer = load_module(TRAIN_SCRIPT, "mt5_ml_filter_trainer")
        rows = [
            {"setup": "m5_scalp", "direction": "1", "hour": "10", "scalp_variant": "1", "confluences": "6", "score_bucket": "60", "label_win": 1},
            {"setup": "smc", "direction": "-1", "hour": "8", "scalp_variant": "0", "confluences": "3", "score_bucket": "60", "label_win": 0},
        ]

        matrix_a, labels_a, names_a = trainer.build_feature_matrix(rows)
        matrix_b, labels_b, names_b = trainer.build_feature_matrix(list(reversed(rows)))

        self.assertEqual(names_a, names_b)
        self.assertEqual(labels_a, [1, 0])
        self.assertEqual(labels_b, [0, 1])
        self.assertEqual(len(matrix_a[0]), len(names_a))

    def test_feature_threshold_slices_include_conditions(self):
        module = load_module(AI_SCRIPT, "mt5_ai_maxret_experiment")
        rows = [
            {"setup": "m5_scalp", "direction": "1", "hour": "10", "spread": 0.10, "profit": 4.0},
            {"setup": "m5_scalp", "direction": "1", "hour": "10", "spread": 0.12, "profit": 3.0},
            {"setup": "m5_scalp", "direction": "1", "hour": "10", "spread": 0.50, "profit": -2.0},
            {"setup": "m5_scalp", "direction": "1", "hour": "10", "spread": 0.60, "profit": -3.0},
        ]

        slices = module.feature_threshold_slice_rows(rows, min_trades=2)

        self.assertTrue(any(row["feature"] == "spread" for row in slices))
        self.assertTrue(any("<=" in row["condition"] or ">" in row["condition"] for row in slices))

    def test_ai_maxret_candidates_resolve_from_matrix(self):
        runner = load_module(RUNNER_SCRIPT, "mt5_candidate_runner")
        rows = runner.load_candidates(ROOT / "mt5/backtests/CANDIDATE_MATRIX.csv")
        candidate = runner.find_candidate(rows, "ai-maxret-s1-w3-debrick")
        self.assertIsNotNone(candidate)

        overrides = runner.expanded_overrides(rows, candidate)

        self.assertIn("InpCompoundMaxDrawdownPct=0.0", overrides)
        self.assertIn("InpEnableMonthlyLossThrottle=true", overrides)

    def test_daily2_s3_candidates_resolve_from_matrix(self):
        runner = load_module(RUNNER_SCRIPT, "mt5_candidate_runner")
        rows = runner.load_candidates(ROOT / "mt5/backtests/CANDIDATE_MATRIX.csv")
        candidate = runner.find_candidate(rows, "daily2-ai-s3-m5smc115-bk105-lock20")
        self.assertIsNotNone(candidate)

        overrides = runner.expanded_overrides(rows, candidate)

        self.assertIn("InpBreakoutRiskMultiplier=1.05", overrides)
        self.assertIn("InpSmcRiskMultiplier=1.15", overrides)
        self.assertIn("InpM5ScalpRiskMultiplier=1.15", overrides)
        self.assertIn("InpCompoundMonthlyProfitLockPct=20.0", overrides)


if __name__ == "__main__":
    unittest.main()
