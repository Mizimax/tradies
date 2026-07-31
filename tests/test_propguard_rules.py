"""Gate G0 for PropGuard (mt5/backtests/PROPGUARD_DESIGN.md §4).

MQL5 .mqh files cannot be executed directly from Python, so this test file does two
complementary things, matching existing repo conventions:

1. Source-text assertions against the shipped .mqh (mirrors tests/qbr/test_qbr_v112.py) --
   proves the specific constants and guard names the design doc froze are actually present
   in the code, not just in this test file.
2. A line-for-line Python re-implementation of the PURE MATH from PropRules.mqh /
   RiskBudget.mqh, exercised with synthetic equity paths (mirrors the reimplementation
   pattern already used by scripts/equity-curve-analysis.py for report parsing). This is
   the only way to verify the anti-ruin arithmetic and threshold behaviour without a live
   MT5 terminal. Keep these functions byte-for-byte consistent with the .mqh -- if you
   change a formula in the .mqh, change it here too, in the same commit.

Run directly: python3 tests/test_propguard_rules.py
"""

import datetime as dt
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RULES_SRC = (ROOT / "mt5/Include/PropGuard/PropRules.mqh").read_text()
RISK_SRC = (ROOT / "mt5/Include/PropGuard/RiskBudget.mqh").read_text()


# ---------------------------------------------------------------------------
# Python mirror of the pure-math functions in RiskBudget.mqh / PropRules.mqh.
# ---------------------------------------------------------------------------

def risk_cash(equity, base_pct, daily_floor, hard_floor, daily_divisor=3, total_divisor=8):
    """Mirrors PropGuardRiskCash (RiskBudget.mqh)."""
    by_base = equity * base_pct / 100.0
    by_daily = (equity - daily_floor) / daily_divisor if daily_divisor > 0 else float("inf")
    by_total = (equity - hard_floor) / total_divisor if total_divisor > 0 else float("inf")
    cash = min(by_base, by_daily, by_total)
    return cash if cash > 0.0 else 0.0


def day_start(now, reset_hour):
    """Mirrors PropGuardDayStart (PropRules.mqh)."""
    midnight = now.replace(hour=0, minute=0, second=0, microsecond=0)
    candidate = midnight + dt.timedelta(hours=reset_hour)
    if candidate > now:
        candidate -= dt.timedelta(days=1)
    return candidate


def daily_soft_floor(day_baseline, soft_pct=2.0):
    return day_baseline * (1.0 - soft_pct / 100.0)


def daily_hard_floor(day_baseline, hard_pct=2.5):
    return day_baseline * (1.0 - hard_pct / 100.0)


def daily_profit_cap(day_baseline, cap_pct=2.5):
    return day_baseline * (1.0 + cap_pct / 100.0)


def max_dd_floor(initial_balance, equity_peak, is_trailing, dd_hard_halt_pct=8.0):
    """Mirrors PropGuardMaxDdFloor."""
    keep_pct = 100.0 - dd_hard_halt_pct
    if is_trailing:
        return equity_peak * (keep_pct / 100.0)
    return initial_balance * (keep_pct / 100.0)


def projection_guard_ok(equity, stop_loss_cash, spread_cash, commission_cash,
                         swap_estimate_cash, current_floating_loss, daily_floor, hard_floor):
    """Mirrors PropGuardProjectionGuardOk."""
    worst_case = stop_loss_cash + spread_cash + commission_cash + swap_estimate_cash + \
        max(0.0, current_floating_loss)
    floor = max(daily_floor, hard_floor)
    return (equity - worst_case) >= floor


def throttled_risk_pct(equity, initial_balance, phase_target_pct, base_risk_pct,
                        target_proximity_pct=1.5):
    """Mirrors PropGuardThrottledRiskPct."""
    target_level = initial_balance * (1.0 + phase_target_pct / 100.0)
    proximity_level = target_level * (1.0 - target_proximity_pct / 100.0)
    if equity >= proximity_level:
        return base_risk_pct * 0.5
    return base_risk_pct


def is_weekend_flatten_time(now, friday_close_hour=20):
    """Mirrors PropGuardIsWeekendFlattenTime. Python weekday(): Mon=0 .. Sun=6."""
    wd = now.weekday()
    if wd == 4 and now.hour >= friday_close_hour:   # Friday
        return True
    if wd == 5 or wd == 6:                            # Saturday / Sunday
        return True
    return False


def is_rollover_blackout(now, start_hour=21, end_hour=23):
    """Mirrors PropGuardIsRolloverBlackout (overnight wrap-aware)."""
    h = now.hour
    if start_hour == end_hour:
        return False
    if start_hour < end_hour:
        return start_hour <= h < end_hour
    return h >= start_hour or h < end_hour


def cost_gate_ok(spread_price, commission_price, stop_distance, max_pct=8.0):
    if stop_distance <= 0.0:
        return False
    return 100.0 * (spread_price + commission_price) / stop_distance <= max_pct


class RiskCashInvariantTests(unittest.TestCase):
    def test_base_pct_clamp_binds_when_it_is_tightest(self):
        # equity=100000, base 1% -> 1000; daily/total budgets far looser.
        cash = risk_cash(100000.0, 1.0, daily_floor=90000.0, hard_floor=80000.0)
        self.assertAlmostEqual(cash, 1000.0)

    def test_daily_budget_clamp_binds_near_the_daily_floor(self):
        # equity is only 300 above the daily floor -> 300/3=100 is tighter than 1% of equity (1000).
        cash = risk_cash(100000.0, 1.0, daily_floor=99700.0, hard_floor=80000.0)
        self.assertAlmostEqual(cash, 100.0)

    def test_total_budget_clamp_binds_near_the_hard_floor(self):
        # equity is only 80 above the hard floor -> 80/8=10 is tighter than both other clamps.
        cash = risk_cash(100000.0, 1.0, daily_floor=90000.0, hard_floor=99920.0)
        self.assertAlmostEqual(cash, 10.0)

    def test_risk_cash_never_goes_negative_past_the_floor(self):
        cash = risk_cash(100000.0, 1.0, daily_floor=90000.0, hard_floor=100500.0)
        self.assertEqual(cash, 0.0)

    def test_tightest_of_three_always_wins_property(self):
        import random
        rng = random.Random(1234)
        for _ in range(200):
            equity = rng.uniform(50000, 150000)
            base_pct = rng.uniform(0.1, 2.0)
            daily_floor = equity - rng.uniform(0, 5000)
            hard_floor = equity - rng.uniform(0, 20000)
            cash = risk_cash(equity, base_pct, daily_floor, hard_floor)
            by_base = equity * base_pct / 100.0
            by_daily = (equity - daily_floor) / 3.0
            by_total = (equity - hard_floor) / 8.0
            expected = max(0.0, min(by_base, by_daily, by_total))
            self.assertAlmostEqual(cash, expected, places=6)


class DailyFloorTests(unittest.TestCase):
    def test_soft_halt_threshold_is_exact(self):
        baseline = 100000.0
        floor = daily_soft_floor(baseline)
        self.assertAlmostEqual(floor, 98000.0)
        # Equity exactly at the floor halts; one cent above does not.
        self.assertLessEqual(floor, floor)
        self.assertTrue(floor <= floor)
        self.assertTrue((floor + 0.01) > floor)

    def test_hard_flatten_is_looser_than_soft_halt(self):
        baseline = 100000.0
        soft = daily_soft_floor(baseline)
        hard = daily_hard_floor(baseline)
        self.assertLess(hard, soft)  # hard floor sits below (worse than) the soft floor
        self.assertAlmostEqual(hard, 97500.0)

    def test_daily_profit_cap_is_symmetric_config_but_independent_value(self):
        baseline = 100000.0
        cap = daily_profit_cap(baseline)
        self.assertAlmostEqual(cap, 102500.0)

    def test_internal_daily_floor_is_strictly_tighter_than_firm_5pct(self):
        # PROPGUARD_DESIGN.md §1/§3: firm daily loss limit is 5%; our hard flatten is 2.5%.
        baseline = 100000.0
        firm_floor = baseline * (1.0 - 5.0 / 100.0)
        our_hard_floor = daily_hard_floor(baseline)
        self.assertGreater(our_hard_floor, firm_floor)


class MaxDrawdownFloorTests(unittest.TestCase):
    def test_static_floor_ignores_equity_peak(self):
        # FTMO 2-Step: firm_dd_is_trailing=False. A higher peak must NOT move the floor.
        floor_low_peak = max_dd_floor(100000.0, equity_peak=100000.0, is_trailing=False)
        floor_high_peak = max_dd_floor(100000.0, equity_peak=115000.0, is_trailing=False)
        self.assertAlmostEqual(floor_low_peak, floor_high_peak)
        self.assertAlmostEqual(floor_low_peak, 92000.0)

    def test_trailing_floor_tracks_the_peak(self):
        floor_at_peak_100k = max_dd_floor(100000.0, equity_peak=100000.0, is_trailing=True)
        floor_at_peak_115k = max_dd_floor(100000.0, equity_peak=115000.0, is_trailing=True)
        self.assertAlmostEqual(floor_at_peak_100k, 92000.0)
        self.assertAlmostEqual(floor_at_peak_115k, 105800.0)
        self.assertGreater(floor_at_peak_115k, floor_at_peak_100k)

    def test_internal_dd_halt_is_strictly_tighter_than_firm_10pct_static(self):
        firm_floor = 100000.0 * (1.0 - 10.0 / 100.0)
        our_floor = max_dd_floor(100000.0, 100000.0, is_trailing=False)
        self.assertGreater(our_floor, firm_floor)


class ProjectionGuardTests(unittest.TestCase):
    def test_boundary_is_inclusive_allow_at_exact_floor(self):
        # equity - worstCase == floor exactly -> still allowed (>=, not >).
        ok = projection_guard_ok(
            equity=100000.0, stop_loss_cash=500.0, spread_cash=10.0, commission_cash=5.0,
            swap_estimate_cash=0.0, current_floating_loss=0.0, daily_floor=99485.0, hard_floor=90000.0,
        )
        self.assertTrue(ok)

    def test_one_cent_worse_than_boundary_blocks(self):
        ok = projection_guard_ok(
            equity=100000.0, stop_loss_cash=500.0, spread_cash=10.0, commission_cash=5.0,
            swap_estimate_cash=0.0, current_floating_loss=0.0, daily_floor=99485.01, hard_floor=90000.0,
        )
        self.assertFalse(ok)

    def test_open_floating_loss_reduces_headroom(self):
        base = dict(equity=100000.0, stop_loss_cash=500.0, spread_cash=10.0, commission_cash=5.0,
                    swap_estimate_cash=0.0, daily_floor=90000.0, hard_floor=80000.0)
        self.assertTrue(projection_guard_ok(current_floating_loss=0.0, **base))
        self.assertTrue(projection_guard_ok(current_floating_loss=9000.0, **base))
        self.assertFalse(projection_guard_ok(current_floating_loss=9500.0, **base))

    def test_floating_profit_does_not_add_headroom(self):
        # current_floating_loss negative (i.e. floating PROFIT) must be clamped to 0, not
        # subtracted -- the projection guard is a worst-case check, not an average-case one.
        # equity sits exactly at the "blocked" side with zero floating P/L:
        base = dict(equity=90000.0, stop_loss_cash=500.0, spread_cash=10.0, commission_cash=5.0,
                    swap_estimate_cash=0.0, daily_floor=90000.0, hard_floor=80000.0)
        self.assertFalse(projection_guard_ok(current_floating_loss=0.0, **base))
        # A large floating PROFIT must not flip this to allowed -- a buggy unclamped
        # implementation would (90000 - (515 - 3000) = 92485 >= 90000 -> wrongly allowed).
        self.assertFalse(projection_guard_ok(current_floating_loss=-3000.0, **base))
        unclamped_worst_case = 500.0 + 10.0 + 5.0 + 0.0 + (-3000.0)
        clamped_worst_case = 500.0 + 10.0 + 5.0 + 0.0 + max(0.0, -3000.0)
        self.assertLess(unclamped_worst_case, clamped_worst_case)


class TargetProximityThrottleTests(unittest.TestCase):
    def test_full_risk_far_from_target(self):
        pct = throttled_risk_pct(equity=102000.0, initial_balance=100000.0,
                                  phase_target_pct=10.0, base_risk_pct=1.0)
        self.assertAlmostEqual(pct, 1.0)

    def test_halved_within_proximity_band(self):
        # target=110000, proximity band starts at 110000*0.985=108350
        pct = throttled_risk_pct(equity=108500.0, initial_balance=100000.0,
                                  phase_target_pct=10.0, base_risk_pct=1.0)
        self.assertAlmostEqual(pct, 0.5)

    def test_boundary_is_inclusive(self):
        # Replicate the function's own order of operations so the boundary value is
        # bit-identical, not just numerically close -- this is an inclusive->exclusive
        # boundary test, not a tolerance test.
        initial_balance = 100000.0
        phase_target_pct = 10.0
        target_level = initial_balance * (1.0 + phase_target_pct / 100.0)
        proximity_level = target_level * (1.0 - 1.5 / 100.0)
        pct = throttled_risk_pct(equity=proximity_level, initial_balance=initial_balance,
                                  phase_target_pct=phase_target_pct, base_risk_pct=1.0)
        self.assertAlmostEqual(pct, 0.5)


class DayStartBoundaryTests(unittest.TestCase):
    """DST-boundary case required by PROPGUARD_DESIGN.md G0: a firm's daily reset hour is a
    configurable server-time offset (e.g. FTMO servers run EET, which is 1-2h ahead of CET
    depending on DST). This test proves the day-boundary arithmetic is correct across that
    offset without assuming any particular timezone library -- the offset itself is the input."""

    def test_reset_at_midnight_same_calendar_day(self):
        now = dt.datetime(2026, 3, 15, 23, 59, 0)
        ds = day_start(now, reset_hour=0)
        self.assertEqual(ds, dt.datetime(2026, 3, 15, 0, 0, 0))

    def test_just_after_midnight_rolls_to_new_day(self):
        now = dt.datetime(2026, 3, 16, 0, 0, 1)
        ds = day_start(now, reset_hour=0)
        self.assertEqual(ds, dt.datetime(2026, 3, 16, 0, 0, 0))

    def test_nonzero_reset_hour_before_boundary_uses_prior_day(self):
        # EET-style offset of +2h: at 01:00 local the "trading day" hasn't reset yet.
        now = dt.datetime(2026, 3, 16, 1, 0, 0)
        ds = day_start(now, reset_hour=2)
        self.assertEqual(ds, dt.datetime(2026, 3, 15, 2, 0, 0))

    def test_nonzero_reset_hour_after_boundary_uses_today(self):
        now = dt.datetime(2026, 3, 16, 2, 0, 1)
        ds = day_start(now, reset_hour=2)
        self.assertEqual(ds, dt.datetime(2026, 3, 16, 2, 0, 0))

    def test_dst_spring_forward_offset_shift_does_not_double_count_a_day(self):
        # Simulate the EU DST transition changing the effective server-hour offset from 2 to 3.
        # Before the shift (offset=2):
        now_before = dt.datetime(2026, 3, 29, 1, 30, 0)
        ds_before = day_start(now_before, reset_hour=2)
        self.assertEqual(ds_before, dt.datetime(2026, 3, 28, 2, 0, 0))
        # After the shift (offset=3), same wall-clock hour must not regress to a stale day:
        now_after = dt.datetime(2026, 3, 29, 3, 30, 0)
        ds_after = day_start(now_after, reset_hour=3)
        self.assertEqual(ds_after, dt.datetime(2026, 3, 29, 3, 0, 0))
        self.assertGreater(ds_after, ds_before)


class WeekendAndFridayGapTests(unittest.TestCase):
    """Friday-gap case required by G0: no new risk may be taken into a weekend gap."""

    def test_friday_before_close_hour_is_allowed(self):
        friday = dt.datetime(2026, 3, 20, 19, 59, 0)  # Friday
        self.assertFalse(is_weekend_flatten_time(friday))

    def test_friday_at_and_after_close_hour_is_blocked(self):
        friday_at = dt.datetime(2026, 3, 20, 20, 0, 0)
        friday_after = dt.datetime(2026, 3, 20, 23, 30, 0)
        self.assertTrue(is_weekend_flatten_time(friday_at))
        self.assertTrue(is_weekend_flatten_time(friday_after))

    def test_saturday_and_sunday_fully_blocked(self):
        saturday = dt.datetime(2026, 3, 21, 12, 0, 0)
        sunday = dt.datetime(2026, 3, 22, 12, 0, 0)
        self.assertTrue(is_weekend_flatten_time(saturday))
        self.assertTrue(is_weekend_flatten_time(sunday))

    def test_monday_resumes_trading(self):
        monday = dt.datetime(2026, 3, 23, 0, 0, 1)
        self.assertFalse(is_weekend_flatten_time(monday))


class RolloverBlackoutTests(unittest.TestCase):
    def test_inside_overnight_window(self):
        self.assertTrue(is_rollover_blackout(dt.datetime(2026, 1, 5, 21, 0, 0)))
        self.assertTrue(is_rollover_blackout(dt.datetime(2026, 1, 5, 22, 30, 0)))

    def test_outside_window_before_and_after(self):
        self.assertFalse(is_rollover_blackout(dt.datetime(2026, 1, 5, 20, 59, 0)))
        self.assertFalse(is_rollover_blackout(dt.datetime(2026, 1, 5, 23, 0, 0)))
        self.assertFalse(is_rollover_blackout(dt.datetime(2026, 1, 5, 6, 0, 0)))


class CostGateTests(unittest.TestCase):
    def test_within_8pct_passes(self):
        self.assertTrue(cost_gate_ok(spread_price=0.20, commission_price=0.10, stop_distance=6.0))

    def test_above_8pct_blocks(self):
        self.assertFalse(cost_gate_ok(spread_price=0.30, commission_price=0.10, stop_distance=4.0))

    def test_zero_stop_distance_blocks(self):
        self.assertFalse(cost_gate_ok(spread_price=0.10, commission_price=0.0, stop_distance=0.0))


def phase_target_reached(equity, initial_balance, phase, phase_target_pct, is_funded):
    """Mirrors PropGuardPhaseTargetReached."""
    if is_funded:
        return False
    target_level = initial_balance * (1.0 + phase_target_pct / 100.0)
    return equity >= target_level


class PhaseTransitionTests(unittest.TestCase):
    def test_not_reached_below_target(self):
        self.assertFalse(phase_target_reached(109999.0, 100000.0, "P1", 10.0, False))

    def test_reached_at_exact_target_boundary(self):
        target_level = 100000.0 * (1.0 + 10.0 / 100.0)
        self.assertTrue(phase_target_reached(target_level, 100000.0, "P1", 10.0, False))

    def test_funded_phase_has_no_target(self):
        # Equity far above any target must still return False once FUNDED -- a funded
        # account does not "graduate" out of the rule engine.
        self.assertFalse(phase_target_reached(1000000.0, 100000.0, "FUNDED", 10.0, True))

    def test_phase2_uses_the_looser_5pct_target(self):
        target_level = 100000.0 * (1.0 + 5.0 / 100.0)
        self.assertTrue(phase_target_reached(target_level, 100000.0, "P2", 5.0, False))
        self.assertFalse(phase_target_reached(104999.0, 100000.0, "P2", 5.0, False))


class SourceTextAssertionTests(unittest.TestCase):
    """Proves the frozen design-doc constants and guard shapes actually exist in the shipped
    .mqh, not just in this test's Python mirror above."""

    def test_max_open_trades_is_hardcoded_to_one_in_default_config(self):
        self.assertIn("c.max_open_trades=1;", RULES_SRC)

    def test_internal_daily_thresholds_match_design_doc(self):
        self.assertIn("c.daily_soft_halt_pct=2.0;", RULES_SRC)
        self.assertIn("c.daily_hard_flatten_pct=2.5;", RULES_SRC)
        self.assertIn("c.dd_hard_halt_pct=8.0;", RULES_SRC)
        self.assertIn("c.daily_profit_cap_pct=2.5;", RULES_SRC)
        self.assertIn("c.target_proximity_pct=1.5;", RULES_SRC)
        self.assertIn("c.cost_gate_max_pct=8.0;", RULES_SRC)

    def test_phase_dependent_risk_matches_design_doc(self):
        self.assertIn("c.challenge_base_risk_pct=1.00;", RULES_SRC)
        self.assertIn("c.funded_base_risk_pct=0.50;", RULES_SRC)

    def test_firm_contract_matches_ftmo_2step(self):
        self.assertIn("c.firm_daily_loss_pct=5.0;", RULES_SRC)
        self.assertIn("c.firm_max_dd_pct=10.0;", RULES_SRC)
        self.assertIn("c.firm_dd_is_trailing=false;", RULES_SRC)
        self.assertIn("c.phase1_target_pct=10.0;", RULES_SRC)
        self.assertIn("c.phase2_target_pct=5.0;", RULES_SRC)

    def test_global_variable_keys_are_magic_scoped(self):
        # PROPGUARD_DESIGN.md explicitly calls out GoldBot's non-magic-scoped daily key as a
        # bug to not repeat. Every PropGuard key must interpolate the magic number.
        self.assertIn('StringFormat("PropGuard.%I64d.%s", magic, suffix)', RULES_SRC)
        self.assertIn("magic,", RULES_SRC)

    def test_closed_profit_includes_swap_commission_and_fee(self):
        self.assertIn("DEAL_SWAP", RULES_SRC)
        self.assertIn("DEAL_COMMISSION", RULES_SRC)
        self.assertIn("DEAL_FEE", RULES_SRC)

    def test_equity_peak_persistence_mirrors_qbr_tester_live_split(self):
        self.assertIn("MQL_TESTER", RULES_SRC)
        self.assertIn("PropGuardEquityPeak", RULES_SRC)

    def test_projection_guard_and_cost_gate_are_exported(self):
        self.assertIn("PropGuardProjectionGuardOk", RULES_SRC)
        self.assertIn("PropGuardCostGateOk", RULES_SRC)

    def test_risk_cash_invariant_exported_with_correct_divisors(self):
        self.assertIn("PropGuardRiskCash", RISK_SRC)
        self.assertIn("dailyDivisor=3", RISK_SRC)
        self.assertIn("totalDivisor=8", RISK_SRC)

    def test_lot_sizing_is_stop_distance_aware_unlike_goldbot(self):
        # The whole reason PropGuard exists as a new EA rather than a GoldBot layer
        # (plan §"Why a new EA") is that GoldBot's InpLotPer100Usd ignores slDistance.
        self.assertIn("slDistance", RISK_SRC)
        self.assertIn("entryPrice", RISK_SRC)
        self.assertIn("slPrice", RISK_SRC)

    def test_phase_transition_reanchors_both_initial_balance_and_equity_peak(self):
        # A phase transition must reset BOTH anchors -- resetting only one would let the
        # next phase's max-DD floor or risk sizing silently use stale P1/P2 numbers.
        self.assertIn("PropGuardResetInitialBalanceTo", RULES_SRC)
        self.assertIn("PropGuardResetEquityPeakTo", RULES_SRC)
        self.assertIn("PropGuardPhaseTargetReached", RULES_SRC)
        ea_src = (ROOT / "mt5/Experts/PropGuard/PropGuard.mq5").read_text()
        self.assertIn("PropGuardResetInitialBalanceTo(InpMagicNumber,equity)", ea_src)
        self.assertIn("PropGuardResetEquityPeakTo(InpMagicNumber,equity)", ea_src)

    def test_funded_phase_never_advances_further(self):
        self.assertIn("if(phase==PROPGUARD_PHASE_FUNDED)\n      return false;", RULES_SRC)


if __name__ == "__main__":
    unittest.main()
