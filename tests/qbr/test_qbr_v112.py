from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MAIN = (ROOT / "mt5/Experts/QuantumBehavioralReplica/QuantumBehavioralReplica.mq5").read_text()
PATTERNS = (ROOT / "mt5/Include/QBR/PatternReader.mqh").read_text()
SIZER = (ROOT / "mt5/Include/QBR/PositionSizer.mqh").read_text()
EXECUTOR = (ROOT / "mt5/Include/QBR/TradeExecutor.mqh").read_text()
PRESET_DIR = ROOT / "mt5/Presets/QBR"


def test_build_and_bounded_loss_streak_block():
    assert 'InpBuildTag="QBR-1.13-aggressive"' in MAIN
    assert "g_loss_streak_block_until=NextBrokerDayStart(end_time)" in MAIN
    assert "RefreshLossStreakBlock();" in MAIN
    assert "g_consecutive_basket_losses=0;" in MAIN


def test_profit_lock_is_persistently_armed():
    assert "g_profit_lock_armed=true" in MAIN
    assert "SaveProfitLock();" in MAIN
    assert "g_basket_snapshot.floating_profit>0.0" not in MAIN


def test_pattern_controls_apply_before_best_pattern_selection():
    assert "PatternEnabled(name)" in PATTERNS
    assert "allow_trend_pullback_in_balanced" in PATTERNS
    for name in (
        "enable_trend_pullback",
        "enable_failed_breakout",
        "enable_breakout_retest",
        "enable_reversal_rejection",
        "enable_inside_bar_compression",
    ):
        assert name in PATTERNS


def test_basket_risk_and_native_stop_guards_exist():
    assert "ExistingRiskAtStop" in SIZER
    assert "risk_money-used_risk" in SIZER
    assert "SetBasketStop" in EXECUTOR
    assert "BasketCatastropheStop" in MAIN


def test_native_and_programmatic_exits_share_one_reconciled_finalizer():
    assert "FinalizeClosedBasket" in MAIN
    assert "ExitReasonFromDeal" in MAIN
    assert "g_last_finalized_basket_id" in MAIN
    assert "BROKER_NATIVE_SL" in MAIN
    assert 'FileWrite(m_baskets,"run_id"' in (ROOT / "mt5/Include/QBR/CSVLogger.mqh").read_text()
    assert '"closed_deals"' in (ROOT / "mt5/Include/QBR/CSVLogger.mqh").read_text()
    assert '"closed_positions"' in (ROOT / "mt5/Include/QBR/CSVLogger.mqh").read_text()
    assert '"deal_ticket","position_id"' in (ROOT / "mt5/Include/QBR/CSVLogger.mqh").read_text()


def test_permanent_equity_peak_survives_live_restart():
    safety = (ROOT / "mt5/Include/QBR/SafetyFocus.mqh").read_text()
    assert "EquityPeakKey" in safety
    assert "GlobalVariableGet(EquityPeakKey())" in safety
    assert "SaveEquityPeak();" in safety
    assert "MQLInfoInteger(MQL_TESTER)" in safety


def test_aggressive_frequency_controls_are_public_inputs():
    for name in (
        "InpAllowMinLotWithNativeRiskCap",
        "InpPostExitCooldownBars",
        "InpSpikeCooldownBars",
        "InpEnableM5ScalpLayer",
        "InpM5TargetPct",
        "InpM5HardStopPct",
    ):
        assert name in MAIN
    assert "allow_min_lot_with_native_risk_cap" in SIZER
    assert "CapVolumeToLimits" in SIZER
    assert "ProcessM5ScalpBar" in MAIN
    assert "iTime(_Symbol,PERIOD_M5,0)" in MAIN


def test_aggressive_base_preset_is_decision_complete():
    text = (PRESET_DIR / "aggressive.set").read_text()
    assert "InpBuildTag=QBR-1.13-aggressive" in text
    assert "InpRunId=v113-control" in text
    assert "InpAllowMinLotWithNativeRiskCap=false" in text
    assert "InpPostExitCooldownBars=2" in text
    assert "InpSpikeCooldownBars=2" in text
    assert "InpEnableM5ScalpLayer=false" in text
