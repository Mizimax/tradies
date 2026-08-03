import csv
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "mt5/Presets/GoldBot/prop-fundingpips-2step.set"
SHADOW = ROOT / "mt5/Presets/GoldBot/prop-fundingpips-2step-continuation-causal-shadow.set"
MATRIX = ROOT / "mt5/backtests/FUNDINGPIPS_CONTINUATION_RUN_MATRIX.csv"
GOLD_BOT = (ROOT / "mt5/Experts/GoldBot/GoldBot.mq5").read_text()
SCRIPT = ROOT / "scripts/run-mt5-fundingpips-chain.py"
SPEC = importlib.util.spec_from_file_location("fundingpips_chain_causal_shadow", SCRIPT)
assert SPEC and SPEC.loader
CHAIN = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = CHAIN
SPEC.loader.exec_module(CHAIN)


def read_effective_inputs(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for line_number, raw in enumerate(path.read_text().splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith(";"):
            continue
        if "=" not in line:
            raise AssertionError(f"malformed preset line {line_number}: {path}")
        key, value = line.split("=", 1)
        if key in result:
            raise AssertionError(f"duplicate preset input {key}: {path}")
        result[key] = value
    return result


class FundingPipsContinuationCausalShadowTests(unittest.TestCase):
    def test_shadow_is_default_off_and_old_continuation_remains_disabled(self):
        self.assertIn("InpEnableContinuationCausalShadow = false", GOLD_BOT)
        self.assertIn("InpContinuationCausalShadowHorizonBars = 32", GOLD_BOT)
        self.assertIn("InpEnableContinuationPullbackSetup = false", GOLD_BOT)
        self.assertIn("continuation causal shadow is tester-only", GOLD_BOT)
        self.assertIn("requires the retired active continuation setup to remain disabled", GOLD_BOT)

    def test_shadow_preset_is_exact_canonical_copy_plus_two_declared_inputs(self):
        base = read_effective_inputs(BASE)
        shadow = read_effective_inputs(SHADOW)
        additions = {key: value for key, value in shadow.items() if key not in base}
        changed = {key: value for key, value in shadow.items() if key in base and value != base[key]}
        self.assertEqual(
            additions,
            {
                "InpEnableContinuationCausalShadow": "true",
                "InpContinuationCausalShadowHorizonBars": "32",
            },
        )
        self.assertEqual(changed, {})
        self.assertEqual({key: shadow[key] for key in base}, base)

    def test_frozen_mechanics_and_no_active_gate_loosening(self):
        shadow = read_effective_inputs(SHADOW)
        expected = {
            "InpEnableContinuationPullbackSetup": "false",
            "InpPropChallengeRiskPct": "0.50",
            "InpSlAtr": "0.90",
            "InpTp1R": "1.65",
            "InpTp2R": "2.0",
            "InpTp3R": "2.0",
            "InpLadderOrderCount": "2",
            "InpLadderFirstSplit": "1",
            "InpMaxHoldBars": "32",
            "InpPropMaxOpenAndPending": "1",
            "InpSmcAllowedLongHours": "7;12;18",
            "InpSmcAllowedShortHours": "99",
        }
        self.assertEqual({key: shadow[key] for key in expected}, expected)
        self.assertIn("indicators.adx >= 18.0", GOLD_BOT)
        self.assertIn("signedDiGap >= 4.0", GOLD_BOT)
        self.assertIn("m15Close > indicators.vwap", GOLD_BOT)
        self.assertIn("microChoCH", GOLD_BOT)

    def test_shadow_lifecycle_is_observational_and_conservative(self):
        observer = GOLD_BOT[
            GOLD_BOT.rindex("void GoldBotContinuationCausalShadowOnTick") :
            GOLD_BOT.rindex("void GoldBotContinuationCausalShadowRecordBaseSignal")
        ]
        self.assertNotIn("trade.", observer)
        self.assertNotIn("GoldBotPlaceLadder", observer)
        self.assertLess(observer.index("if(stopTouched)"), observer.index("else if(tpTouched)"))
        self.assertIn("spreadR", observer)
        self.assertIn("commissionR", observer)
        self.assertIn("grossR", observer)

    def test_observer_is_attached_only_at_the_existing_no_zone_branch(self):
        on_tick = GOLD_BOT[GOLD_BOT.index("void OnTick()") : GOLD_BOT.index("string GoldBotSymbol()")]
        call = "GoldBotContinuationCausalShadowObserve(symbol);"
        self.assertEqual(on_tick.count(call), 1)
        self.assertLess(on_tick.index("if(!zone.valid)"), on_tick.index(call))
        self.assertLess(on_tick.index(call), on_tick.index("GoldBotContinuationSetupPass"))

    def test_state_schema_carries_one_probe_and_fails_closed(self):
        required = {
            "causal_shadow_state_valid",
            "causal_shadow_state_complete",
            "causal_shadow_active_probe_count",
            "causal_shadow_probe_id",
            'StringFormat("causal_shadow_rung_%d_", i + 1)',
        }
        for value in required:
            self.assertIn(value, GOLD_BOT)
        self.assertIn("missing/corrupt causal shadow state metadata", GOLD_BOT)
        self.assertIn("incomplete active causal shadow probe state", GOLD_BOT)
        self.assertTrue(required - {'StringFormat("causal_shadow_rung_%d_", i + 1)'} <= CHAIN.CAUSAL_SHADOW_STATE_KEYS | CHAIN.CAUSAL_SHADOW_ACTIVE_STATE_KEYS)

        state = {key: "true" for key in CHAIN.CAUSAL_SHADOW_STATE_KEYS}
        state.update({"causal_shadow_state_version": "1", "causal_shadow_active_probe_count": "0", "causal_shadow_last_probe_id": ""})
        CHAIN.validate_causal_shadow_state(state, final_segment=True)
        state["causal_shadow_active_probe_count"] = "1"
        state.update({key: "1" for key in CHAIN.CAUSAL_SHADOW_ACTIVE_STATE_KEYS})
        with self.assertRaisesRegex(CHAIN.ChainError, "final segment ended"):
            CHAIN.validate_causal_shadow_state(state, final_segment=True)

    def test_matrix_contains_only_sequential_cs1_train_pairs_and_analyses(self):
        with MATRIX.open(newline="") as handle:
            rows = list(csv.DictReader(handle))
        self.assertEqual(len(rows), 6)
        self.assertTrue(all(row["stage"] == "CS1" for row in rows))
        self.assertEqual([int(row["order"]) for row in rows], list(range(1, 7)))
        self.assertEqual({row["window"] for row in rows}, {"h1-2025", "h2-2025"})
        self.assertEqual([row["role"] for row in rows], ["control", "shadow", "analysis"] * 2)
        self.assertNotIn("2024", MATRIX.read_text())
        self.assertNotIn("2026", MATRIX.read_text())
        for row in rows:
            if row["role"] in {"control", "shadow"}:
                self.assertIn("WINEDLLOVERRIDES=mmdevapi=d WINEDEBUG=-all", row["command"])
                self.assertIn("run-mt5-fundingpips-chain.py", row["command"])
            else:
                self.assertIn("--continuation-causal-shadow-study", row["command"])


if __name__ == "__main__":
    unittest.main()
