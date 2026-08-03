import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROP_MODE = (ROOT / "mt5/Include/GoldBot/PropMode.mqh").read_text()
GOLD_BOT = (ROOT / "mt5/Experts/GoldBot/GoldBot.mq5").read_text()
TRADE_MANAGER = (ROOT / "mt5/Include/GoldBot/TradeManager.mqh").read_text()


class GoldBotPropBrokerSpecificationTests(unittest.TestCase):
    def test_sizing_uses_broker_profit_calculation(self):
        self.assertIn("GoldBotPropCashPerPriceUnitPerLot", PROP_MODE)
        self.assertIn("OrderCalcProfit(ORDER_TYPE_BUY", PROP_MODE)
        self.assertIn(
            "return riskCash / (stopDistancePrice * cashPerPriceUnit);",
            PROP_MODE,
        )

    def test_commission_and_spread_share_cash_per_price_unit(self):
        self.assertIn(
            "double commissionPrice = cfg.commissionPerLotUsd / cashPerPriceUnit;",
            PROP_MODE,
        )
        self.assertIn(
            "double spreadCash = spreadPrice * lots * cashPerPriceUnit;",
            PROP_MODE,
        )

    def test_matching_profit_currency_has_contract_size_fallback(self):
        self.assertIn("profitCurrency == depositCurrency", PROP_MODE)
        self.assertIn("return contractSize;", PROP_MODE)

    def test_pending_order_risk_cash_uses_prop_cash_per_price_unit(self):
        self.assertIn(
            "double propCashPerPriceUnit = GoldBotPropCashPerPriceUnitPerLot(symbol);",
            TRADE_MANAGER,
        )
        self.assertIn(
            "riskCash = risk * propCashPerPriceUnit * lot;",
            TRADE_MANAGER,
        )
        self.assertIn(
            'GlobalVariableSet(orderKey + ".riskCash", riskCash);',
            TRADE_MANAGER,
        )
        helper_assignment = TRADE_MANAGER.index(
            "riskCash = risk * propCashPerPriceUnit * lot;"
        )
        fallback_assignment = TRADE_MANAGER.index(
            "riskCash = (risk / tickSize) * tickValue * lot;"
        )
        self.assertLess(helper_assignment, fallback_assignment)

    def test_monitor_only_keeps_hard_monitor_but_bypasses_execution_controls(self):
        self.assertIn("input bool            InpPropMonitorOnly = false;", GOLD_BOT)
        self.assertIn(
            "if(InpEnablePropMode)\n   {\n      GoldBotPropConfig propCfg = GoldBotBuildPropConfig();",
            GOLD_BOT,
        )
        self.assertIn(
            "GoldBotPropMonitorResult propMon = GoldBotPropIntraBarMonitor",
            GOLD_BOT,
        )
        self.assertGreaterEqual(
            GOLD_BOT.count("InpEnablePropMode && !InpPropMonitorOnly"),
            4,
        )
        self.assertIn("lastPropBreachLogDay != breachDay", GOLD_BOT)
        self.assertIn(
            "if(InpPropMonitorOnly)\n         {\n            GoldBotDashboardRefresh();\n            return;",
            GOLD_BOT,
        )

    def test_phase_target_lock_flattens_and_persists_completion(self):
        self.assertIn("InpPropTargetLockBufferPct = 0.10", GOLD_BOT)
        self.assertIn("GoldBotPropPhaseTargetLockReached", PROP_MODE)
        self.assertIn("GoldBotPropSetPhaseTargetCompleted", PROP_MODE)
        self.assertIn("GoldBotFlattenAll(symbol, InpMagicNumber, trade)", GOLD_BOT)
        self.assertIn("Prop phase target lock reached completed=%s", GOLD_BOT)
        self.assertIn(
            'GlobalVariableDel(GoldBotPropKey(magic, "phaseTargetCompleted"));',
            PROP_MODE,
        )

    def test_m5_scalp_supports_direction_specific_sl_atr(self):
        self.assertIn("InpScalpLongSlAtr = 0.0", GOLD_BOT)
        self.assertIn("InpScalpShortSlAtr = 0.0", GOLD_BOT)
        self.assertIn("double GoldBotM5ScalpSlAtr", GOLD_BOT)
        self.assertIn("GoldBotM5ScalpSlAtr(DIR_LONG)", GOLD_BOT)
        self.assertIn("GoldBotM5ScalpSlAtr(DIR_SHORT)", GOLD_BOT)
        self.assertIn("double scalpSlAtr = GoldBotM5ScalpSlAtr(direction);", GOLD_BOT)

    def test_m5_scalp_supports_direction_specific_risk_multiplier(self):
        self.assertIn("InpM5ScalpLongRiskMultiplier = 0.0", GOLD_BOT)
        self.assertIn("InpM5ScalpShortRiskMultiplier = 0.0", GOLD_BOT)
        self.assertIn("double GoldBotM5ScalpRiskMultiplier", GOLD_BOT)
        self.assertIn("double scalpRiskMultiplier = GoldBotM5ScalpRiskMultiplier(direction);", GOLD_BOT)
        self.assertIn("InpScalpLotMultiplier * scalpRiskMultiplier", GOLD_BOT)

    def test_tester_chain_inputs_are_inert_by_default_and_tester_only(self):
        self.assertIn("InpTesterChainMode = false", GOLD_BOT)
        self.assertIn("InpTesterChainRequireState = false", GOLD_BOT)
        self.assertIn(
            'InpTesterChainStateFile = "GoldBot/fundingpips-chain-state.csv"',
            GOLD_BOT,
        )
        self.assertIn(
            "InpTesterChainMode && !(bool)MQLInfoInteger(MQL_TESTER)",
            GOLD_BOT,
        )
        self.assertIn("if(InpTesterChainMode && !GoldBotTesterChainExport())", GOLD_BOT)

    def test_tester_chain_seeds_original_challenge_anchor(self):
        self.assertIn("struct GoldBotPropTesterChainState", PROP_MODE)
        self.assertIn("GoldBotPropLoadTesterChainState", PROP_MODE)
        self.assertIn("GoldBotPropSeedTesterChainInitialBalance", PROP_MODE)
        self.assertIn("FILE_COMMON", PROP_MODE)
        self.assertIn(
            "GoldBotPropSeedTesterChainInitialBalance(magic, state.originalChallengeBalance);",
            PROP_MODE,
        )
        self.assertIn(
            'FileWrite(handle, "original_challenge_balance", DoubleToString(originalBalance, 2));',
            PROP_MODE,
        )
        self.assertIn(
            'FileWrite(handle, "next_start_balance", DoubleToString(MathFloor(balance), 2));',
            PROP_MODE,
        )

    def test_tester_chain_export_is_fail_closed_when_not_flat(self):
        self.assertIn("bool flat = positionCount == 0 && pendingCount == 0;", GOLD_BOT)
        self.assertIn("bool validState = flat && testerChainInitializationValid;", GOLD_BOT)
        self.assertIn('FolderCreate("GoldBot", FILE_COMMON);', GOLD_BOT)
        self.assertIn(
            "GoldBotPropWriteTesterChainBase(handle, InpMagicNumber, validState, flat, TimeCurrent())",
            GOLD_BOT,
        )
        self.assertIn('FileWrite(handle, "valid", valid ? "true" : "false");', PROP_MODE)
        self.assertIn('FileWrite(handle, "flat", flat ? "true" : "false");', PROP_MODE)

    def test_tester_chain_preserves_restored_state_and_rejects_malformed_seed(self):
        self.assertGreaterEqual(GOLD_BOT.count("&& !testerChainStateLoaded"), 3)
        self.assertIn("missing or unsupported required state fields", PROP_MODE)
        self.assertIn("previous segment state is invalid or non-flat", PROP_MODE)
        self.assertIn("missing carried GoldBot control state", GOLD_BOT)
        self.assertIn("required prior tester chain state is missing", GOLD_BOT)
        self.assertIn("gGoldBotPropTesterChainOriginalBalance", PROP_MODE)

    def test_scalp_failure_stage_one_is_default_off_and_shadow_only(self):
        self.assertIn("InpEnableScalpFailureExit = false", GOLD_BOT)
        self.assertIn("InpScalpFailureShadowOnly = true", GOLD_BOT)
        self.assertIn("InpScalpFailureCheckFraction = 0.50", GOLD_BOT)
        self.assertIn("InpScalpFailureMinMfeR = 0.10", GOLD_BOT)
        self.assertIn("InpScalpFailureCurrentR = -0.35", GOLD_BOT)
        self.assertIn(
            "InpEnableScalpFailureExit && !InpScalpFailureShadowOnly",
            GOLD_BOT,
        )
        self.assertIn("active scalp failure exit is unavailable", GOLD_BOT)

    def test_scalp_failure_telemetry_tracks_position_metadata_without_active_close(self):
        self.assertIn('posKey + ".mfeR"', TRADE_MANAGER)
        self.assertIn('posKey + ".maeR"', TRADE_MANAGER)
        self.assertIn('posKey + ".failureCheckpointLogged"', TRADE_MANAGER)
        self.assertIn('posKey + ".failureCheckpointR"', TRADE_MANAGER)
        self.assertIn('posKey + ".failureTriggered"', TRADE_MANAGER)
        self.assertIn("Scalp failure checkpoint position=", TRADE_MANAGER)
        telemetry_start = TRADE_MANAGER.index("// Stage 1 telemetry is strictly observational")
        telemetry_end = TRADE_MANAGER.index("double configuredTp1R", telemetry_start)
        telemetry_block = TRADE_MANAGER[telemetry_start:telemetry_end]
        self.assertNotIn("PositionClose(", telemetry_block)
        self.assertNotIn("PositionModify(", telemetry_block)
        self.assertIn('GlobalVariableDel(posKey + ".mfeR");', GOLD_BOT)
        self.assertIn("Scalp failure outcome position=", GOLD_BOT)


if __name__ == "__main__":
    unittest.main()
