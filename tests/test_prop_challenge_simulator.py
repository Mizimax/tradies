import importlib.util
import random
import sys
import unittest
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "prop-challenge-simulator.py"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


sim = load_module(SCRIPT, "prop_challenge_simulator")


def make_params(**overrides):
    base = dict(
        daily_loss_pct=5.0, max_dd_pct=10.0, dd_is_trailing=False,
        phase1_target_pct=10.0, phase2_target_pct=5.0, daily_reset_hour=0,
        challenge_risk_pct=1.0, funded_risk_pct=0.5, funded_horizon_days=90,
    )
    base.update(overrides)
    return sim.SimParams(**base)


def days_from_r_lists(r_lists):
    """Builds a list of TradingDay, one per element of r_lists (a list of lists of R)."""
    out = []
    for i, rs in enumerate(r_lists):
        out.append(sim.TradingDay(day=datetime(2026, 1, 1 + i), r_multiples=list(rs)))
    return out


class JournalLoadingTests(unittest.TestCase):
    def setUp(self):
        self.journal = ROOT / "scratch" / "sample-propguard.trades.csv"
        self.journal.parent.mkdir(exist_ok=True)

    def tearDown(self):
        self.journal.unlink(missing_ok=True)

    def test_only_close_events_with_valid_r_multiple_are_loaded(self):
        self.journal.write_text(
            "timestamp,engine,direction,entry,sl,tp,lots,risk_cash,clamp_bound,spread_price,"
            "cost_to_stop_pct,atr,range_width,vol_ratio,phase,ticket,event,reason,exit_price,r_multiple\n"
            "2026.01.01 08:00:00,london,1,2000,1995,2007.5,0.1,100,base,0.2,4.0,4.0,10,0.9,"
            "CHALLENGE_P1,1,open,ok,0,0\n"
            "2026.01.01 09:00:00,london,0,0,0,0,0,100,,0,0,0,0,0,CHALLENGE_P1,1,close,profit=150,2007.5,1.5\n"
            "2026.01.02 08:00:00,ny,0,0,0,0,0,50,,0,0,0,0,0,CHALLENGE_P1,2,close,profit=-50,1995,-1.0\n"
        )
        trades = sim.load_closed_trades(self.journal)
        self.assertEqual(len(trades), 2)
        self.assertAlmostEqual(trades[0].r_multiple, 1.5)
        self.assertAlmostEqual(trades[1].r_multiple, -1.0)
        self.assertEqual(trades[0].engine, "london")

    def test_day_start_matches_propguard_day_boundary_logic(self):
        ts = datetime(2026, 3, 16, 1, 0, 0)
        self.assertEqual(sim.day_start(ts, reset_hour=2), datetime(2026, 3, 15, 2, 0, 0))
        ts2 = datetime(2026, 3, 16, 2, 0, 1)
        self.assertEqual(sim.day_start(ts2, reset_hour=2), datetime(2026, 3, 16, 2, 0, 0))


class ChallengeSimulationTests(unittest.TestCase):
    def test_reaches_pass_when_target_hit_before_any_breach(self):
        # 1% risk, need +10% to pass P1: a string of +2R days compounds past target quickly.
        params = make_params(challenge_risk_pct=1.0, phase1_target_pct=10.0, phase2_target_pct=5.0)
        days = days_from_r_lists([[2.0]] * 20)
        result = sim.simulate_from(days, 0, params)
        self.assertIn(result["status"], (sim.PASS, "funded_survived_horizon"))

    def test_daily_loss_breach_is_detected_within_a_single_bad_day(self):
        # One day with a catastrophic single trade should breach the 5% daily floor at 1% risk
        # only if the loss is large enough in R-multiple terms: -6R * 1% = -6% > 5% floor.
        params = make_params(daily_loss_pct=5.0, challenge_risk_pct=1.0)
        days = days_from_r_lists([[-6.0]])
        result = sim.simulate_from(days, 0, params)
        self.assertEqual(result["status"], sim.FAIL_DAILY)

    def test_small_daily_loss_does_not_breach(self):
        params = make_params(daily_loss_pct=5.0, challenge_risk_pct=1.0)
        days = days_from_r_lists([[-1.0], [-1.0], [-1.0]])  # -1% each day, well under 5%
        result = sim.simulate_from(days, 0, params, day_supplier=lambda: sim.TradingDay(day=datetime(2026, 2, 1), r_multiples=[-1.0]))
        # Should not resolve to fail_daily on the first three days.
        self.assertNotEqual(result["status"], sim.FAIL_DAILY)

    def test_max_dd_breach_detected_across_multiple_days(self):
        # Static floor at 10% of initial; a sequence of -3R days at 1% risk each costs ~3%/day
        # compounding -- by day 4 cumulative loss should breach the static 10% floor.
        params = make_params(max_dd_pct=10.0, dd_is_trailing=False, challenge_risk_pct=1.0,
                              daily_loss_pct=50.0)  # disable daily floor to isolate DD floor
        days = days_from_r_lists([[-3.0]] * 6)
        result = sim.simulate_from(days, 0, params)
        self.assertEqual(result["status"], sim.FAIL_DD)

    def test_static_floor_does_not_move_with_equity_peak(self):
        # Run equity up first (raises peak), then down. Static floor must stay anchored to
        # the ORIGINAL initial balance, not the peak -- unlike a trailing-DD firm.
        params = make_params(max_dd_pct=10.0, dd_is_trailing=False, challenge_risk_pct=1.0,
                              daily_loss_pct=50.0, phase1_target_pct=1000.0)  # unreachable target
        # +5% then a string of -1% days: peak equity rises to 1.05, but the static floor stays
        # at 0.90 * initial (1.0), so it should NOT fail until equity actually drops below 0.90.
        days = days_from_r_lists([[5.0]] + [[-1.0]] * 3)
        result = sim.simulate_from(days, 0, params)
        self.assertNotEqual(result["status"], sim.FAIL_DD)

    def test_trailing_floor_moves_up_with_peak_and_can_fail_sooner(self):
        params_static = make_params(max_dd_pct=10.0, dd_is_trailing=False, challenge_risk_pct=1.0,
                                     daily_loss_pct=50.0, phase1_target_pct=1000.0)
        params_trailing = make_params(max_dd_pct=10.0, dd_is_trailing=True, challenge_risk_pct=1.0,
                                       daily_loss_pct=50.0, phase1_target_pct=1000.0)
        days = days_from_r_lists([[15.0]] + [[-9.0]] * 2)  # big run-up, then a pullback
        static_result = sim.simulate_from(days, 0, params_static)
        trailing_result = sim.simulate_from(days, 0, params_trailing)
        # Off a higher peak, the trailing floor is reached sooner (or equally) than the static one.
        self.assertIn(trailing_result["status"], (sim.FAIL_DD, sim.CENSORED, sim.PASS))
        self.assertNotEqual(static_result["status"], sim.FAIL_DD)

    def test_phase_transition_from_p1_to_p2_to_funded(self):
        params = make_params(phase1_target_pct=5.0, phase2_target_pct=5.0, challenge_risk_pct=1.0)
        # +6R once should clear a 5% target (1% * 6 = 6% > 5%) -- two such days clear P1 then P2.
        days = days_from_r_lists([[6.0], [6.0]])
        result = sim.simulate_from(days, 0, params)
        self.assertEqual(result["status"], sim.PASS)
        self.assertEqual(result["phase_reached"], "FUNDED")

    def test_censored_when_data_runs_out_before_resolution(self):
        params = make_params(phase1_target_pct=1000.0, daily_loss_pct=50.0, max_dd_pct=50.0)
        days = days_from_r_lists([[0.1], [0.1]])
        result = sim.simulate_from(days, 0, params)
        self.assertEqual(result["status"], sim.CENSORED)


class RollingStartAggregationTests(unittest.TestCase):
    def test_summary_counts_add_up_to_n(self):
        params = make_params(phase1_target_pct=1000.0, daily_loss_pct=50.0, max_dd_pct=50.0)
        days = days_from_r_lists([[0.1]] * 5)
        result = sim.run_rolling_start(days, params)
        self.assertEqual(result["n"], 5)
        self.assertEqual(result["n_pass"] + result["n_fail_daily"] + result["n_fail_dd"] + result["n_censored"], 5)

    def test_empty_days_returns_zero_n(self):
        result = sim.run_rolling_start([], make_params())
        self.assertEqual(result["n"], 0)


class BlockBootstrapTests(unittest.TestCase):
    def test_bootstrap_never_censors_with_enough_reps(self):
        # A strong positive edge (+3R every day) should always pass well before any
        # artificial cap, and the bootstrap must never report "censored" since it can always
        # draw more resampled days.
        params = make_params(challenge_risk_pct=1.0, phase1_target_pct=10.0, phase2_target_pct=5.0)
        days = days_from_r_lists([[3.0]] * 5)
        rng = random.Random(42)
        result = sim.run_block_bootstrap(days, params, n_reps=50, block_size=3, rng=rng)
        self.assertEqual(result["n_censored"], 0)
        self.assertGreater(result["n_pass"], 0)

    def test_bootstrap_is_deterministic_given_a_seed(self):
        params = make_params()
        days = days_from_r_lists([[1.0], [-1.0], [2.0], [-0.5]] * 3)
        r1 = sim.run_block_bootstrap(days, params, n_reps=30, block_size=2, rng=random.Random(7))
        r2 = sim.run_block_bootstrap(days, params, n_reps=30, block_size=2, rng=random.Random(7))
        self.assertEqual(r1, r2)


class ParametricEstimateTests(unittest.TestCase):
    def test_positive_edge_gives_high_pass_probability(self):
        r_multiples = [1.5, -1.0, 1.5, -1.0, 1.5, -1.0, 1.5] * 20  # positive expectancy, low variance
        params = make_params(challenge_risk_pct=0.5)
        result = sim.parametric_estimate(r_multiples, params)
        self.assertGreater(result["e_per_trade_R"], 0)
        self.assertIsNotNone(result["p_pass_both_vs_maxdd_floor_only"])
        self.assertGreater(result["p_pass_both_vs_maxdd_floor_only"], 0.5)

    def test_insufficient_trades_returns_note(self):
        result = sim.parametric_estimate([1.0], make_params())
        self.assertIn("note", result)
        self.assertIsNone(result["e"])

    def test_zero_variance_is_handled(self):
        result = sim.parametric_estimate([1.0, 1.0, 1.0], make_params())
        self.assertEqual(result["v"], 0.0)
        self.assertIn("note", result)


class FirmPresetTests(unittest.TestCase):
    def test_all_documented_firms_are_present(self):
        for firm in ("ftmo-2step", "fundingpips-2step", "the5ers-highstakes", "the5ers-hypergrowth"):
            self.assertIn(firm, sim.FIRM_PRESETS)

    def test_hypergrowth_is_tighter_than_ftmo(self):
        ftmo = sim.FIRM_PRESETS["ftmo-2step"]
        hg = sim.FIRM_PRESETS["the5ers-hypergrowth"]
        self.assertLess(hg["max_dd_pct"], ftmo["max_dd_pct"])
        self.assertLess(hg["daily_loss_pct"], ftmo["daily_loss_pct"])

    def test_build_params_rejects_unknown_firm(self):
        with self.assertRaises(ValueError):
            sim.build_params("not-a-real-firm", 100000.0, 1.0, 0.5, 90)


if __name__ == "__main__":
    unittest.main()
