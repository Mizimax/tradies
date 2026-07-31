import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROP_MODE = (ROOT / "mt5/Include/GoldBot/PropMode.mqh").read_text()
GOLD_BOT = (ROOT / "mt5/Experts/GoldBot/GoldBot.mq5").read_text()


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


if __name__ == "__main__":
    unittest.main()
