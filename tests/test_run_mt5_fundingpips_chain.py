import csv
import hashlib
import importlib.util
import json
import os
import sys
import tempfile
import unittest
from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/run-mt5-fundingpips-chain.py"
SPEC = importlib.util.spec_from_file_location("fundingpips_chain", SCRIPT)
assert SPEC and SPEC.loader
CHAIN = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = CHAIN
SPEC.loader.exec_module(CHAIN)
ANALYZE_SPEC = importlib.util.spec_from_file_location(
    "analyze_mt5_trades", ROOT / "scripts/analyze-mt5-trades.py"
)
assert ANALYZE_SPEC and ANALYZE_SPEC.loader
ANALYZE = importlib.util.module_from_spec(ANALYZE_SPEC)
sys.modules[ANALYZE_SPEC.name] = ANALYZE
ANALYZE_SPEC.loader.exec_module(ANALYZE)
SUMMARY_SPEC = importlib.util.spec_from_file_location(
    "summarize_mt5_reports", ROOT / "scripts/summarize-mt5-reports.py"
)
assert SUMMARY_SPEC and SUMMARY_SPEC.loader
SUMMARY = importlib.util.module_from_spec(SUMMARY_SPEC)
sys.modules[SUMMARY_SPEC.name] = SUMMARY
SUMMARY_SPEC.loader.exec_module(SUMMARY)


def valid_state_rows(**overrides):
    rows = {
        "schema_version": "1",
        "valid": "true",
        "flat": "true",
        "original_challenge_balance": "50000.00",
        "ending_balance": "50400.00",
        "ending_equity": "50400.00",
        "next_start_balance": "50400.00",
        "equity_peak": "50600.00",
        "phase_target_completed": "false",
        "segment_end_timestamp": "1754265599",
        "compound_peak_equity": "50600.0",
        "compound_month": "202507",
        "compound_month_start_equity": "50000.0",
        "compound_month_profit_lock": "0",
        "monthly_loss_month": "202507",
        "monthly_loss_start_equity": "50000.0",
        "monthly_loss_halt": "0",
        "completed_trade_month": "202507",
        "completed_trade_count": "8",
        "streak_cooldown_end": "0",
        "streak_consecutive_losses": "0",
        "rolling_count": "0",
        "rolling_index": "0",
        "rolling_fail_streak": "0",
        "rolling_pause_until": "0",
        "rolling_lookback": "20",
    }
    rows.update(overrides)
    return rows


class FundingPipsChainTests(unittest.TestCase):
    @staticmethod
    def _write_report(
        path,
        timestamp,
        initial,
        ending,
        gross_profit,
        gross_loss,
        total_trades=1,
        total_deals=1,
    ):
        cells = [
            timestamp, "1", "XAUUSD", "balance", "in", "0", "0", "0",
            "0", "0", f"{ending - initial:.2f}", f"{ending:.2f}", "test",
        ]
        deal_row = "<tr>" + "".join(f"<td>{value}</td>" for value in cells) + "</tr>"
        path.write_text(
            f"<table><tr><td>Gross Profit:</td><td>{gross_profit:.2f}</td></tr>"
            f"<tr><td>Gross Loss:</td><td>{gross_loss:.2f}</td></tr>"
            f"<tr><td>Total Trades:</td><td>{total_trades}</td></tr>"
            f"<tr><td>Total Deals:</td><td>{total_deals}</td></tr>"
            "<tr><td>Equity Drawdown Maximal:</td><td>0.00 (0.00%)</td></tr>"
            f"<tr><td>Initial Deposit:</td><td>{initial:.2f}</td></tr>"
            "<tr><th><b>Deals</b></th></tr>"
            f"{deal_row}</table>"
        )

    def test_default_boundaries_are_contiguous_weekend_flat(self):
        CHAIN.validate_weekend_boundaries(CHAIN.default_segments())
        # MT5 ToDate is exclusive: this is the smallest upper bound that still
        # exercises the final requested day, 2025-12-31.
        self.assertEqual(CHAIN.default_segments()[-1].end, date(2026, 1, 1))
        self.assertEqual(
            CHAIN.default_segments()[-1].end.toordinal() - 1,
            date(2025, 12, 31).toordinal(),
        )
        bad = [
            CHAIN.Segment(date(2025, 7, 1), date(2025, 8, 2)),
            CHAIN.Segment(date(2025, 8, 3), date(2025, 8, 31)),
        ]
        with self.assertRaises(CHAIN.ChainError):
            CHAIN.validate_weekend_boundaries(bad)

    def test_h1_2025_named_window_is_contiguous_and_includes_june_30(self):
        segments = CHAIN.named_window_segments("h1-2025")
        CHAIN.validate_weekend_boundaries(segments)
        self.assertEqual(segments[0].start, date(2025, 1, 1))
        self.assertEqual(segments[-1].end, date(2025, 7, 1))

    def test_locked_holdout_windows_are_contiguous_and_exact(self):
        expected = {
            "h1-2024": (date(2024, 1, 1), date(2024, 7, 1)),
            "h2-2024": (date(2024, 7, 1), date(2025, 1, 1)),
            "h1-2026": (date(2026, 1, 1), date(2026, 7, 1)),
        }
        for name, (start, end) in expected.items():
            with self.subTest(window=name):
                segments = CHAIN.named_window_segments(name)
                CHAIN.validate_weekend_boundaries(segments)
                self.assertEqual(segments[0].start, start)
                self.assertEqual(segments[-1].end, end)

    def test_segment_two_requires_prior_state(self):
        self.assertEqual(
            CHAIN.expected_chain_inputs(1)["InpTesterChainRequireState"], "false"
        )
        self.assertEqual(
            CHAIN.expected_chain_inputs(2)["InpTesterChainRequireState"], "true"
        )

    def test_state_deposit_carry_and_fail_closed_validation(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "state.csv"
            with path.open("w", newline="") as handle:
                csv.writer(handle).writerows(valid_state_rows().items())
            parsed = CHAIN.parse_state(path)
            self.assertEqual(float(parsed["ending_balance"]), 50400.0)
            CHAIN.validate_original_challenge_balance(parsed, 50_000.0)

            reset_anchor = dict(parsed)
            reset_anchor["original_challenge_balance"] = "50482.00"
            with self.assertRaises(CHAIN.ChainError):
                CHAIN.validate_original_challenge_balance(reset_anchor, 50_000.0)

            with path.open("w", newline="") as handle:
                csv.writer(handle).writerows(valid_state_rows(valid="false").items())
            with self.assertRaises(CHAIN.ChainError):
                CHAIN.parse_state(path)

    def test_state_rejects_missing_and_duplicate_fields(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "state.csv"
            rows = valid_state_rows()
            rows.pop("equity_peak")
            with path.open("w", newline="") as handle:
                csv.writer(handle).writerows(rows.items())
            with self.assertRaises(CHAIN.ChainError):
                CHAIN.parse_state(path)

            with path.open("w", newline="") as handle:
                writer = csv.writer(handle)
                writer.writerows(valid_state_rows().items())
                writer.writerow(["valid", "true"])
            with self.assertRaises(CHAIN.ChainError):
                CHAIN.parse_state(path)

    def test_inputs_manifest_hash_is_normalized_and_stable(self):
        with tempfile.TemporaryDirectory() as temporary:
            first = Path(temporary) / "a.htm"
            second = Path(temporary) / "b.htm"
            first.write_text("<td>Inputs:</td><td>InpTesterChainMode=true\n InpTesterChainStateFile=GoldBot/fundingpips-chain-state.csv\nInpScoreThreshold=75</td><td>Company:</td><td>X</td><td>Initial Deposit:</td><td>50000.00</td>")
            second.write_text("<td>Inputs:</td>\n<td> InpTesterChainMode=true\nInpTesterChainStateFile=GoldBot/fundingpips-chain-state.csv\nInpScoreThreshold=75 </td>\n<td>Company:</td><td>X</td><td>Initial Deposit:</td><td>50482.00</td>")
            self.assertEqual(CHAIN.inputs_hash(first), CHAIN.inputs_hash(second))

    def test_strategy_hash_excludes_only_chain_controls(self):
        with tempfile.TemporaryDirectory() as temporary:
            first = Path(temporary) / "a.htm"
            second = Path(temporary) / "b.htm"
            first.write_text("Inputs:\nInpTesterChainMode=true\nInpTesterChainStateFile=GoldBot/a.csv\nInpScoreThreshold=75\nCompany:")
            second.write_text("Inputs:\nInpTesterChainMode=false\nInpTesterChainStateFile=GoldBot/b.csv\nInpScoreThreshold=75\nCompany:")
            self.assertNotEqual(CHAIN.inputs_hash(first), CHAIN.inputs_hash(second))
            self.assertEqual(CHAIN.strategy_inputs_hash(first), CHAIN.strategy_inputs_hash(second))
            second.write_text(second.read_text().replace("InpScoreThreshold=75", "InpScoreThreshold=76"))
            self.assertNotEqual(CHAIN.strategy_inputs_hash(first), CHAIN.strategy_inputs_hash(second))

    def test_manifest_artifact_hash_is_enforced(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            journal = directory / "segment.trades.csv"
            journal.write_text("time,message\n2025.07.01 10:00:00,Deal event deal=1 position=1 entry=1 profit=10\n")
            manifest = directory / "chain.manifest.json"
            manifest.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "chain_name": "test-chain",
                        "segments": [
                            {
                                "start": "2025.07.01",
                                "end": "2025.08.03",
                                "valid": True,
                                "flat": True,
                                "report_fresh": True,
                                "journal": journal.name,
                                "journal_sha256": hashlib.sha256(journal.read_bytes()).hexdigest(),
                            }
                        ],
                    }
                )
            )
            name, rows = ANALYZE.read_chain_manifest(manifest)
            self.assertEqual(name, "test-chain")
            self.assertEqual(len(rows), 1)
            journal.write_text(journal.read_text() + "tampered\n")
            with self.assertRaises(ValueError):
                ANALYZE.read_chain_manifest(manifest)

    def _write_continuation_manifest(self, directory, name, journal_rows, preset, source_hash="source"):
        journal = directory / f"{name}.trades.csv"
        with journal.open("w", newline="") as handle:
            writer = csv.writer(handle)
            writer.writerow(["time", "message"])
            writer.writerows(journal_rows)
        report = directory / f"{name}.htm"
        report.write_text(
            "<table><tr><td>Period:</td><td>M15 (2025.01.01 - 2025.07.01)</td></tr>"
            "<tr><td>Initial Deposit:</td><td>50000.00</td></tr>"
            "<tr><td>Inputs:</td><td>InpPropFirmMaxDrawdownPct=10.0\n"
            "InpPropDdHardHaltPct=8.0</td></tr></table>"
        )
        manifest = directory / f"{name}.manifest.json"
        manifest.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "chain_name": name,
                    "preset": "GoldBot/prop-fundingpips-2step-continuation-core.set",
                    "preset_sha256": hashlib.sha256(preset.read_bytes()).hexdigest(),
                    "source_hashes": {"GoldBot.mq5": source_hash},
                    "ex5_sha256": "ex5",
                    "segments": [
                        {
                            "start": "2025.01.01",
                            "end": "2025.07.01",
                            "valid": True,
                            "flat": True,
                            "report_fresh": True,
                            "report": report.name,
                            "journal": journal.name,
                            "report_sha256": hashlib.sha256(report.read_bytes()).hexdigest(),
                            "journal_sha256": hashlib.sha256(journal.read_bytes()).hexdigest(),
                        }
                    ],
                    "stitched": {"stitched_equity_drawdown_pct": 2.0},
                }
            )
        )
        return manifest

    def test_continuation_study_reports_cohort_r_blocks_target_and_displacement(self):
        preset = ROOT / "mt5/Presets/GoldBot/prop-fundingpips-2step-continuation-core.set"
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            candidate = self._write_continuation_manifest(
                directory,
                "candidate",
                [
                    ["2025.01.02 07:00:00", "Continuation setup accepted dir=1 hour=7 adx=25 minAdx=18 diGap=7 minDiGap=4 ema=yes vwap=yes zone=1-2 m5Checks=2 required=2 score=70 confluences=4/5"],
                    ["2025.01.02 07:01:00", "Deal event deal=1 position=1 entry=0 profit=-5 setup=continuation setupMetadata=yes riskCash=100 comment=CONT1"],
                    ["2025.01.02 08:00:00", "Deal event deal=2 position=1 entry=1 profit=155 setup=continuation setupMetadata=yes riskCash=100 comment=CONT1"],
                    ["2025.01.03 12:00:00", "Continuation setup blocked dir=1 hour=12 adx=15 minAdx=18 diGap=2 minDiGap=4 ema=yes vwap=no zone=yes m5Checks=1 required=2 m5=no score=65 confluences=3/5"],
                    ["2025.01.04 08:00:00", "Deal event deal=3 position=2 entry=0 profit=-1 setup=m5_scalp setupMetadata=yes riskCash=100 comment=BASE1"],
                    ["2025.01.04 09:00:00", "Deal event deal=4 position=2 entry=1 profit=10 setup=m5_scalp setupMetadata=yes riskCash=100 comment=BASE1"],
                    ["2025.01.10 12:00:00", "Prop phase target lock reached completed=yes closed=1 triggerEquity=54010 balanceAfterClose=54010 target=54000 lockLevel=54010"],
                ],
                preset,
            )
            control = self._write_continuation_manifest(
                directory,
                "control",
                [
                    ["2025.01.04 08:00:00", "Deal event deal=1 position=1 entry=0 profit=-1 setup=m5_scalp comment=BASE1"],
                    ["2025.01.04 09:00:00", "Deal event deal=2 position=1 entry=1 profit=10 setup=m5_scalp comment=BASE1"],
                    ["2025.01.05 08:00:00", "Deal event deal=3 position=2 entry=0 profit=-1 setup=m1_micro_scalp comment=BASE2"],
                    ["2025.01.05 09:00:00", "Deal event deal=4 position=2 entry=1 profit=10 setup=m1_micro_scalp comment=BASE2"],
                ],
                preset,
            )
            rows = ANALYZE.continuation_study_rows(candidate, control)
            window = rows[0]
            self.assertEqual(window["high_score_zoneless_candidate_bars"], "2")
            self.assertEqual(window["continuation_accepted"], "1")
            self.assertEqual(window["blocked_adx"], "1")
            self.assertEqual(window["blocked_di_gap"], "1")
            self.assertEqual(window["blocked_vwap"], "1")
            self.assertEqual(window["blocked_m5"], "1")
            self.assertEqual(window["filled_continuation_positions"], "1")
            self.assertEqual(window["continuation_closing_deals"], "1")
            self.assertEqual(window["continuation_net"], "150.00")
            self.assertEqual(window["continuation_average_net_r"], "1.50000")
            self.assertEqual(window["base_positions_displaced"], "1")
            self.assertEqual(window["first_target_lock_timestamp"], "2025.01.10 12:00:00")
            self.assertEqual(window["elapsed_observed_trading_days"], "8")

    def test_continuation_study_fails_closed_on_missing_setup_metadata(self):
        preset = ROOT / "mt5/Presets/GoldBot/prop-fundingpips-2step-continuation-core.set"
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            candidate = self._write_continuation_manifest(
                directory,
                "candidate",
                [
                    ["2025.01.02 07:00:00", "Continuation setup accepted dir=1 hour=7 adx=25 minAdx=18 diGap=7 minDiGap=4 ema=yes vwap=yes zone=1-2 m5Checks=2 required=2 score=70 confluences=4/5"],
                    ["2025.01.02 07:01:00", "Deal event deal=1 position=1 entry=0 profit=-5 setup=continuation setupMetadata=no riskCash=100 comment=CONT1"],
                    ["2025.01.02 08:00:00", "Deal event deal=2 position=1 entry=1 profit=155 setup=continuation setupMetadata=no riskCash=100 comment=CONT1"],
                ],
                preset,
            )
            with self.assertRaises(ValueError):
                ANALYZE.continuation_study_rows(candidate)

    def test_stitched_metrics_deduplicate_and_compute_portfolio_drawdown(self):
        with tempfile.TemporaryDirectory() as temporary:
            first = Path(temporary) / "one.trades.csv"
            second = Path(temporary) / "two.trades.csv"
            header = ["time", "message"]
            deal1 = "Deal event deal=1 position=11 entry=1 reason=4 profit=100.00 setup=m5_scalp dir=-1 hour=8"
            loss = "Deal event deal=2 position=12 entry=1 reason=4 profit=-200.00 setup=m5_scalp dir=-1 hour=9"
            gain = "Deal event deal=3 position=13 entry=1 reason=3 profit=50.00 setup=m1_micro_scalp dir=-1 hour=10"
            with first.open("w", newline="") as handle:
                writer = csv.writer(handle)
                writer.writerow(header)
                writer.writerow(["2025.07.01 10:00:00", deal1])
                writer.writerow(["2025.07.02 10:00:00", loss])
            with second.open("w", newline="") as handle:
                writer = csv.writer(handle)
                writer.writerow(header)
                writer.writerow(["2025.07.01 10:00:00", deal1])
                writer.writerow(["2025.08.04 10:00:00", gain])
            stitched = CHAIN.stitched_metrics([first, second], 50_000.0)
            self.assertEqual(stitched["deal_count"], 3)
            self.assertEqual(stitched["net_profit"], -50.0)
            self.assertAlmostEqual(stitched["profit_factor"], 0.75)
            self.assertAlmostEqual(stitched["stitched_equity_drawdown_pct"], 200 / 50100 * 100, places=6)

    def test_report_stitch_offsets_whole_dollar_deposit_quantization(self):
        with tempfile.TemporaryDirectory() as temporary:
            first = Path(temporary) / "first.htm"
            second = Path(temporary) / "second.htm"
            self._write_report(first, "2025.07.31 23:00:00", 50_000.0, 50_000.75, 1.75, -1.0)
            self._write_report(second, "2025.08.29 23:00:00", 50_000.0, 50_000.50, 1.50, -1.0)
            stitched = CHAIN.stitched_report_metrics(
                [first, second],
                50_000.0,
                50_001.25,
                [0.0, 0.75],
            )
            self.assertEqual(stitched["ending_balance"], 50_001.25)
            self.assertEqual(stitched["net_profit"], 1.25)
            self.assertEqual(stitched["total_trades"], 2)
            self.assertEqual(stitched["total_deals"], 2)
            self.assertEqual(stitched["deal_count"], 2)
            self.assertEqual(stitched["balance_point_count"], 2)
            self.assertEqual(stitched["series"][-1]["balance"], 50_001.25)

    def test_report_stitch_does_not_count_segment_deposits_as_deals_or_trades(self):
        with tempfile.TemporaryDirectory() as temporary:
            first = Path(temporary) / "first.htm"
            second = Path(temporary) / "second.htm"
            self._write_report(
                first, "2025.07.01 00:00:00", 50_000.0, 50_100.0, 150.0, -50.0,
                total_trades=3, total_deals=5,
            )
            self._write_report(
                second, "2025.08.04 00:00:00", 50_100.0, 50_200.0, 125.0, -25.0,
                total_trades=4, total_deals=6,
            )
            stitched = CHAIN.stitched_report_metrics(
                [first, second], 50_000.0, 50_200.0
            )
            self.assertEqual(stitched["total_trades"], 7)
            self.assertEqual(stitched["total_deals"], 11)
            self.assertEqual(stitched["deal_count"], 11)
            self.assertEqual(stitched["balance_point_count"], 2)

    def test_manifest_summary_uses_report_trade_totals_for_legacy_accounting(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            first = directory / "first.htm"
            second = directory / "second.htm"
            self._write_report(
                first, "2025.07.01 00:00:00", 50_000.0, 50_100.0, 150.0, -50.0,
                total_trades=3, total_deals=5,
            )
            self._write_report(
                second, "2025.08.04 00:00:00", 50_100.0, 50_200.0, 125.0, -25.0,
                total_trades=4, total_deals=6,
            )
            segments = []
            dates = (("2025.07.01", "2025.07.31"), ("2025.08.01", "2025.08.31"))
            for report, (start, end) in zip((first, second), dates):
                segments.append(
                    {
                        "start": start,
                        "end": end,
                        "valid": True,
                        "flat": True,
                        "report_fresh": True,
                        "report": report.name,
                        "report_sha256": hashlib.sha256(report.read_bytes()).hexdigest(),
                    }
                )
            manifest = directory / "legacy.manifest.json"
            manifest.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "chain_name": "legacy",
                        "segments": segments,
                        # Legacy value included one deposit balance point per segment.
                        "stitched": {"deal_count": 13, "net_profit": 200.0},
                    }
                )
            )
            rows = SUMMARY.summarize_chain_manifest(manifest)
            self.assertEqual(rows[-1]["total_trades"], "7")

    def test_failure_checkpoint_confusion_metrics_include_pre_checkpoint_losses(self):
        rows = [
            (
                "2025.01.02 10:22:30",
                "Scalp failure checkpoint position=1 positionInstance=1_100 setup=m5_scalp "
                "triggered=yes checkpointR=-0.40 checkpointGrossR=-0.35",
            ),
            (
                "2025.01.02 10:45:00",
                "Scalp failure outcome position=1 positionInstance=1_100 setup=m5_scalp "
                "checkpointLogged=yes triggered=yes exitReason=4 netR=-1.00 netProfit=-100.00 "
                "counterfactualCashSavedBeforeCosts=65.00 counterfactualCashSavedAfterCosts=60.00 shadowOnly=yes",
            ),
            (
                "2025.01.03 10:05:00",
                "Scalp failure outcome position=2 positionInstance=2_200 setup=m5_scalp "
                "checkpointLogged=no triggered=no exitReason=4 netR=-1.00 netProfit=-100.00 "
                "counterfactualCashSavedBeforeCosts=0.00 counterfactualCashSavedAfterCosts=0.00 shadowOnly=yes",
            ),
            (
                "2025.01.04 10:22:30",
                "Scalp failure checkpoint position=3 positionInstance=3_300 setup=m5_scalp "
                "triggered=yes checkpointR=-0.36 checkpointGrossR=-0.31",
            ),
            (
                "2025.01.04 10:40:00",
                "Scalp failure outcome position=3 positionInstance=3_300 setup=m5_scalp "
                "checkpointLogged=yes triggered=yes exitReason=3 netR=0.50 netProfit=50.00 "
                "counterfactualCashSavedBeforeCosts=-81.00 counterfactualCashSavedAfterCosts=-86.00 shadowOnly=yes",
            ),
        ]
        metrics = ANALYZE.failure_checkpoint_metrics_from_rows("sample", rows)
        all_scalps = next(row for row in metrics if row["setup"] == "all_scalps")
        self.assertEqual(all_scalps["scalp_positions"], "3")
        self.assertEqual(all_scalps["triggers"], "2")
        self.assertEqual(all_scalps["full_losses"], "2")
        self.assertEqual(all_scalps["triggered_full_losses"], "1")
        self.assertEqual(all_scalps["trigger_to_full_loss_precision_pct"], "50.00")
        self.assertEqual(all_scalps["full_loss_recall_pct"], "50.00")
        self.assertEqual(all_scalps["false_trigger_rate_pct"], "100.00")
        self.assertEqual(all_scalps["counterfactual_cash_saved_after_costs"], "-26.00")
        self.assertEqual(all_scalps["positive_savings_after_costs"], "no")
        self.assertEqual(all_scalps["non_shadow_outcomes"], "0")

    def test_failure_checkpoint_outcome_must_match_checkpoint(self):
        rows = [
            (
                "2025.01.02 10:45:00",
                "Scalp failure outcome position=1 positionInstance=1_100 setup=m5_scalp "
                "checkpointLogged=yes triggered=yes exitReason=4 netR=-1 netProfit=-100 shadowOnly=yes",
            )
        ]
        with self.assertRaises(ValueError):
            ANALYZE.failure_checkpoint_metrics_from_rows("sample", rows)

    def test_profitable_stop_exit_is_not_counted_as_a_full_loss(self):
        rows = [
            (
                "2025.01.02 10:22:30",
                "Scalp failure checkpoint position=1 positionInstance=1_100 setup=m5_scalp "
                "triggered=yes checkpointR=-0.40 checkpointGrossR=-0.35",
            ),
            (
                "2025.01.02 10:45:00",
                "Scalp failure outcome position=1 positionInstance=1_100 setup=m5_scalp "
                "checkpointLogged=yes triggered=yes exitReason=4 netR=0.50 netProfit=50.00 "
                "counterfactualCashSavedBeforeCosts=-85.00 counterfactualCashSavedAfterCosts=-90.00 shadowOnly=yes",
            ),
            (
                "2025.01.03 10:22:30",
                "Scalp failure checkpoint position=2 positionInstance=2_200 setup=m5_scalp "
                "triggered=yes checkpointR=-0.40 checkpointGrossR=-0.35",
            ),
            (
                "2025.01.03 10:45:00",
                "Scalp failure outcome position=2 positionInstance=2_200 setup=m5_scalp "
                "checkpointLogged=yes triggered=yes exitReason=4 netR=-1.00 netProfit=-100.00 "
                "counterfactualCashSavedBeforeCosts=65.00 counterfactualCashSavedAfterCosts=60.00 shadowOnly=yes",
            ),
        ]

        metrics = ANALYZE.failure_checkpoint_metrics_from_rows("sample", rows)
        all_scalps = next(row for row in metrics if row["setup"] == "all_scalps")
        self.assertEqual(all_scalps["full_losses"], "1")
        self.assertEqual(all_scalps["triggered_full_losses"], "1")
        self.assertEqual(all_scalps["trigger_to_full_loss_precision_pct"], "50.00")
        self.assertEqual(all_scalps["full_loss_recall_pct"], "100.00")
        self.assertEqual(all_scalps["profitable_exits"], "1")
        self.assertEqual(all_scalps["false_profitable_triggers"], "1")
        self.assertEqual(all_scalps["false_trigger_rate_pct"], "100.00")


if __name__ == "__main__":
    unittest.main()
