import csv
import hashlib
import importlib.util
import json
import re
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "analyze_mt5_trades_causal_shadow", ROOT / "scripts/analyze-mt5-trades.py"
)
assert SPEC and SPEC.loader
ANALYZE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = ANALYZE
SPEC.loader.exec_module(ANALYZE)


class ContinuationCausalShadowAnalyzerTests(unittest.TestCase):
    @staticmethod
    def _candidate(probe, day, slot=True):
        return [
            f"2025.01.{day:02d} 07:00:00",
            "Continuation causal shadow candidate "
            f"probeId=P{probe} time={1735772400 + probe * 86400} "
            f"sessionId=202501{day:02d} dir=1 hour=7 score=75 threshold=70 confluences=5/8 "
            "m15Close=2650 h1Close=2648 ema21=2645 ema50=2640 ema200=2600 "
            "vwap=2644 atr=10 adx=25 plusDI=30 minusDI=20 "
            "signedVwapAtr=0.6 signedDiGap=10 legacyVwapPass=no "
            "trendSideVwapPass=yes emaPass=yes zoneValid=yes zoneBottom=2644 zoneTop=2648 "
            "candlePatternM15=no rsiShiftM15=yes microChoCHM5=yes legacyAggregate=yes legacyChecks=2 "
            f"slotFreeAtSignal={'yes' if slot else 'no'} "
            f"causalEligible=yes deployable={'yes' if slot else 'no'} overlapSuppressed=no "
            f"failedCausalReasons={'none' if slot else 'slot'}",
        ]

    @staticmethod
    def _final(probe, day, rung, winner=True, deployable=True, displaced=False):
        gross = (1.65 if winner else -1.0) if deployable else 0.0
        spread = 0.05 if deployable else 0.0
        commission = 0.02 if deployable else 0.0
        net = gross - spread - commission
        return [
            f"2025.01.{day:02d} 10:00:00",
            "Continuation causal shadow final "
            f"probeId=P{probe} rung={rung} eligible=yes "
            f"deployable={'yes' if deployable else 'no'} "
            f"overlapSuppressed={'no' if deployable else 'yes'} "
            f"filled={'yes' if deployable else 'no'} virtualEntry=2647 fillTime=2025.01.{day:02d}T08:00:00 "
            f"expiryTime=2025.01.{day:02d}T15:00:00 sl=2638 riskDistance=9 "
            f"modeledRiskCash={100 if deployable else 0} firstBarrierReason={'tp1' if winner else 'sl'} "
            f"firstBarrierTime=2025.01.{day:02d}T10:00:00 mfeR={1.65 if winner else 0.2} "
            f"maeR={0.2 if winner else 1.0} grossR={gross:.2f} spreadR={spread:.2f} "
            f"commissionR={commission:.2f} netR={net:.2f} costsIncluded=yes "
            f"wouldDisplaceBase={'yes' if displaced else 'no'} "
            f"displacedBaseSignal={'BASE1' if displaced else 'none'} "
            f"displacedBaseSetup={'m5_scalp' if displaced else 'none'} "
            f"displacedBaseNet={50 if displaced else 0:.2f} stateFlat=yes metadataValid=yes",
        ]

    def _write_pair(self, directory, shadow_rows=None, control_rows=None, active_state=0):
        directory = Path(directory)
        preset = ROOT / "mt5/Presets/GoldBot/prop-fundingpips-2step.set"
        if shadow_rows is None:
            shadow_rows = []
            for probe in range(1, 7):
                day = probe + 1
                deployable = probe <= 5
                shadow_rows.append(self._candidate(probe, day, deployable))
                for rung in (1, 2):
                    shadow_rows.append(
                        self._final(
                            probe,
                            day,
                            rung,
                            winner=probe != 5,
                            deployable=deployable,
                            displaced=probe == 1,
                        )
                    )
            shadow_rows.append(
                [
                    "2025.01.15 08:00:00",
                    "Deal event deal=1 position=1 entry=0 profit=-5 setup=m5_scalp comment=BASE1",
                ]
            )
            shadow_rows.append(
                [
                    "2025.01.15 09:00:00",
                    "Deal event deal=2 position=1 entry=1 profit=55 setup=m5_scalp comment=BASE1",
                ]
            )
        if control_rows is None:
            control_rows = [
                row
                for row in shadow_rows
                if "Deal event" in row[-1]
            ]

        active_counts = (
            list(active_state)
            if isinstance(active_state, (list, tuple))
            else [active_state] * 6
        )

        windows = [
            ("2025.01.01", "2025.02.01"),
            ("2025.02.03", "2025.03.01"),
            ("2025.03.03", "2025.04.01"),
            ("2025.04.02", "2025.05.03"),
            ("2025.05.05", "2025.06.01"),
            ("2025.06.02", "2025.07.01"),
        ]

        def write_manifest(name, rows, enabled):
            segments = []
            for index, (start, end) in enumerate(windows, start=1):
                journal = directory / f"{name}-s{index:02d}.trades.csv"
                with journal.open("w", newline="") as handle:
                    writer = csv.writer(handle)
                    writer.writerow(["time", "message"])
                    writer.writerows(
                        row[-2:]
                        for row in rows
                        if (len(row) == 2 and index == 1)
                        or (len(row) == 3 and row[0] == index)
                    )
                report = directory / f"{name}-s{index:02d}.htm"
                report.write_text(
                    "<table><tr><td>Period:</td><td>M15 (2025.01.01 - 2025.07.01)</td></tr>"
                    "<tr><td>Initial Deposit:</td><td>50000.00</td></tr>"
                    "<tr><td>Inputs:</td><td>"
                    f"InpEnableContinuationCausalShadow={'true' if enabled else 'false'}\n"
                    "InpContinuationCausalShadowHorizonBars=32\n"
                    "InpPropFirmMaxDrawdownPct=10.0\nInpPropDdHardHaltPct=8.0"
                    "</td></tr><tr><td>Company:</td><td>Test</td></tr></table>"
                )
                candidate_history = []
                for row in rows:
                    row_segment = row[0] if len(row) == 3 else 1
                    if row_segment > index or "Continuation causal shadow candidate" not in row[-1]:
                        continue
                    match = re.search(r"probeId=([^\s,]+)", row[-1])
                    if match:
                        candidate_history.append((row_segment, row[-2], match.group(1)))
                last_probe = max(candidate_history)[2] if candidate_history else ""
                carried_state = {
                    "valid": "true",
                    "flat": "true",
                    "original_challenge_balance": "50000.00",
                    "causal_shadow_enabled": "true",
                    "causal_shadow_state_version": "1",
                    "causal_shadow_state_valid": "true",
                    "causal_shadow_state_complete": "true",
                    "causal_shadow_active_probe_count": str(active_counts[index - 1]),
                    "causal_shadow_last_probe_id": last_probe,
                    "causal_shadow_probe_id": "P1" if active_counts[index - 1] else "",
                }
                if active_counts[index - 1]:
                    carried_state.update(
                        {
                            "causal_shadow_signal_time": "1735772400",
                            "causal_shadow_expiry_time": "1735801200",
                            "causal_shadow_direction": "1",
                            "causal_shadow_sl": "2638",
                            "causal_shadow_signal_spread": "0.2",
                            "causal_shadow_would_displace_base": "false",
                            "causal_shadow_base_resolved": "true",
                            "causal_shadow_base_signal_id": "none",
                            "causal_shadow_base_setup": "none",
                            "causal_shadow_base_signal_code": "0",
                            "causal_shadow_displaced_base_net": "0",
                        }
                    )
                    for rung in (1, 2):
                        for field, value in {
                            "filled": "false",
                            "terminal": "false",
                            "fill_time": "0",
                            "barrier_time": "0",
                            "entry": "2647",
                            "risk_distance": "9",
                            "lot": "0.1",
                            "risk_cash": "100",
                            "spread_r": "0.05",
                            "commission_r": "0.02",
                            "mfe_r": "0",
                            "mae_r": "0",
                            "gross_r": "0",
                            "net_r": "0",
                            "reason": "pending",
                        }.items():
                            carried_state[f"causal_shadow_rung_{rung}_{field}"] = value
                segments.append(
                    {
                        "index": index,
                        "start": start,
                        "end": end,
                        "valid": True,
                        "flat": True,
                        "report_fresh": True,
                        "report": report.name,
                        "journal": journal.name,
                        "report_sha256": hashlib.sha256(report.read_bytes()).hexdigest(),
                        "journal_sha256": hashlib.sha256(journal.read_bytes()).hexdigest(),
                        "carried_state": carried_state,
                    }
                )
            manifest = directory / f"{name}.manifest.json"
            manifest.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "chain_name": name,
                        "preset": "GoldBot/prop-fundingpips-2step.set",
                        "preset_sha256": hashlib.sha256(preset.read_bytes()).hexdigest(),
                        "source_hashes": {"mt5/Experts/GoldBot/GoldBot.mq5": "same"},
                        "ex5_sha256": "same-ex5",
                        "segments": segments,
                        "stitched": {
                            "net_profit": 50.0,
                            "profit_factor": 2.0,
                            "stitched_equity_drawdown_pct": 1.0,
                            "total_trades": 1,
                            "total_deals": 2,
                        },
                    }
                )
            )
            return manifest

        return write_manifest("shadow", shadow_rows, True), write_manifest(
            "control", control_rows, False
        )

    def test_full_half_and_month_metrics_are_probe_and_rung_separate(self):
        with tempfile.TemporaryDirectory() as temporary:
            shadow, control = self._write_pair(temporary)
            rows = ANALYZE.continuation_causal_shadow_study_rows(shadow, control)
            self.assertEqual(len(rows), 21)
            window_probe = next(
                row
                for row in rows
                if row["scope"] == "window" and row["aggregation"] == "probe"
            )
            self.assertEqual(window_probe["universe_bars"], "6")
            self.assertEqual(window_probe["distinct_sessions"], "6")
            self.assertEqual(window_probe["causal_eligible"], "6")
            self.assertEqual(window_probe["deployable"], "5")
            self.assertEqual(window_probe["overlap_suppressed"], "1")
            self.assertEqual(window_probe["deployable_filled_probes"], "5")
            self.assertEqual(window_probe["virtual_filled_rungs"], "10")
            self.assertEqual(window_probe["failed_slot"], "1")
            self.assertEqual(window_probe["net_cash"], "1050.00")
            self.assertEqual(window_probe["positive_displaced_base_net"], "50.00")
            self.assertEqual(window_probe["conservative_incremental_net"], "1000.00")
            self.assertEqual(window_probe["real_deal_signature_parity"], "yes")
            self.assertEqual(window_probe["chain_state_integrity"], "yes")
            self.assertIn("target_later_than_66_weekdays", window_probe["frozen_train_gate_reasons"])
            self.assertTrue(
                any(row["scope"] == "2025-01" and row["aggregation"] == "rung" for row in rows)
            )
            june_probe = next(
                row
                for row in rows
                if row["scope"] == "2025-06" and row["aggregation"] == "probe"
            )
            self.assertEqual(june_probe["universe_bars"], "0")

    def test_duplicate_probe_and_missing_final_fail_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            base_rows = [self._candidate(1, 2), self._candidate(1, 2)]
            base_rows.extend(self._final(1, 2, rung) for rung in (1, 2))
            shadow, control = self._write_pair(temporary, base_rows, [])
            with self.assertRaisesRegex(ValueError, "duplicate causal shadow probe ID"):
                ANALYZE.continuation_causal_shadow_study_rows(shadow, control)

        with tempfile.TemporaryDirectory() as temporary:
            base_rows = [self._candidate(1, 2), self._final(1, 2, 1)]
            shadow, control = self._write_pair(temporary, base_rows, [])
            with self.assertRaisesRegex(ValueError, "missing causal shadow final"):
                ANALYZE.continuation_causal_shadow_study_rows(shadow, control)

    def test_missing_cost_or_displacement_and_non_flat_state_fail_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            rows = [self._candidate(1, 2)]
            for rung in (1, 2):
                final = self._final(1, 2, rung)
                final[1] = final[1].replace("costsIncluded=yes ", "")
                rows.append(final)
            shadow, control = self._write_pair(temporary, rows, [])
            with self.assertRaisesRegex(ValueError, "costsIncluded"):
                ANALYZE.continuation_causal_shadow_study_rows(shadow, control)

        with tempfile.TemporaryDirectory() as temporary:
            rows = [self._candidate(1, 2)]
            for rung in (1, 2):
                final = self._final(1, 2, rung, displaced=True)
                final[1] = final[1].replace("displacedBaseNet=50.00", "")
                rows.append(final)
            shadow, control = self._write_pair(temporary, rows, [])
            with self.assertRaisesRegex(ValueError, "displacedBaseNet"):
                ANALYZE.continuation_causal_shadow_study_rows(shadow, control)

        with tempfile.TemporaryDirectory() as temporary:
            shadow, control = self._write_pair(temporary, active_state=1)
            with self.assertRaisesRegex(ValueError, "non-flat virtual state"):
                ANALYZE.continuation_causal_shadow_study_rows(shadow, control)

    def test_real_deal_or_undeclared_input_difference_fails_parity(self):
        with tempfile.TemporaryDirectory() as temporary:
            shadow, control = self._write_pair(temporary)
            control_data = json.loads(control.read_text())
            journal = Path(temporary) / control_data["segments"][0]["journal"]
            text = journal.read_text().replace("profit=55", "profit=54")
            journal.write_text(text)
            control_data["segments"][0]["journal_sha256"] = hashlib.sha256(
                journal.read_bytes()
            ).hexdigest()
            control.write_text(json.dumps(control_data))
            with self.assertRaisesRegex(ValueError, "real deal signatures differ"):
                ANALYZE.continuation_causal_shadow_study_rows(shadow, control)

        with tempfile.TemporaryDirectory() as temporary:
            shadow, control = self._write_pair(temporary)
            shadow_data = json.loads(shadow.read_text())
            report = Path(temporary) / shadow_data["segments"][0]["report"]
            report.write_text(report.read_text().replace(
                "InpPropDdHardHaltPct=8.0", "InpPropDdHardHaltPct=7.5"
            ))
            shadow_data["segments"][0]["report_sha256"] = hashlib.sha256(
                report.read_bytes()
            ).hexdigest()
            shadow.write_text(json.dumps(shadow_data))
            with self.assertRaisesRegex(ValueError, "undeclared control/shadow input differences"):
                ANALYZE.continuation_causal_shadow_study_rows(shadow, control)

    def test_active_probe_round_trips_across_segment_boundary(self):
        with tempfile.TemporaryDirectory() as temporary:
            rows = [[1, *self._candidate(1, 31)]]
            for rung in (1, 2):
                final = self._final(1, 31, rung)
                final = [value.replace("2025.01.31", "2025.02.03") for value in final]
                rows.append([2, *final])
            shadow, control = self._write_pair(
                temporary,
                rows,
                [],
                active_state=[1, 0, 0, 0, 0, 0],
            )
            analyzed = ANALYZE.continuation_causal_shadow_study_rows(shadow, control)
            window = next(
                row
                for row in analyzed
                if row["scope"] == "window" and row["aggregation"] == "probe"
            )
            self.assertEqual(window["deployable_filled_probes"], "1")

            data = json.loads(shadow.read_text())
            data["segments"][1]["carried_state"]["causal_shadow_probe_id"] = "WRONG"
            data["segments"][1]["carried_state"]["causal_shadow_active_probe_count"] = "1"
            shadow.write_text(json.dumps(data))
            with self.assertRaisesRegex(ValueError, "active causal shadow state payload incomplete"):
                ANALYZE.continuation_causal_shadow_study_rows(shadow, control)


if __name__ == "__main__":
    unittest.main()
