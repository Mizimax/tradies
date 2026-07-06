import importlib.util
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "mt5-ml-trim-analysis.py"


def load_module():
    spec = importlib.util.spec_from_file_location("mt5_ml_trim_analysis", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class Mt5MlTrimAnalysisTests(unittest.TestCase):
    def test_closed_deals_are_parsed_from_goldbot_journal(self):
        module = load_module()
        journal = ROOT / "scratch" / "sample-ml-trim-test.trades.csv"
        journal.parent.mkdir(exist_ok=True)
        journal.write_text(
            "time\tmessage\n"
            "2026.01.01 10:00:00\tDeal event deal=1 entry=0 profit=0.00 dir=1 hour=10 setup=m1_micro_scalp scalpVariant=1 confluences=7/7 scoreBucket=60\n"
            "2026.01.01 10:05:00\tDeal event deal=2 entry=1 profit=-7.50 dir=1 hour=10 setup=m1_micro_scalp scalpVariant=1 confluences=7/7 scoreBucket=60\n"
            "2026.01.01 11:00:00\tDeal event deal=3 entry=1 profit=12.00 dir=-1 hour=8 setup=m5_scalp scalpVariant=1 confluences=6/6 scoreBucket=60\n"
        )
        self.addCleanup(journal.unlink)

        deals = module.parse_closed_deals(journal)

        self.assertEqual(len(deals), 2)
        self.assertEqual(deals[0].setup, "m1_micro_scalp")
        self.assertEqual(deals[0].profit, -7.50)
        self.assertEqual(deals[0].direction, "1")
        self.assertEqual(deals[1].setup, "m5_scalp")
        self.assertTrue(deals[1].is_win)

    def test_rule_miner_recommends_negative_pockets_only(self):
        module = load_module()
        deals = [
            module.Deal("2026.01.01 10:05:00", "m1_micro_scalp", "1", "10", "1", "7", "60", -7.0),
            module.Deal("2026.01.02 10:05:00", "m1_micro_scalp", "1", "10", "1", "7", "60", -5.0),
            module.Deal("2026.01.03 10:05:00", "m1_micro_scalp", "1", "10", "1", "7", "60", 1.0),
            module.Deal("2026.01.01 08:05:00", "m1_micro_scalp", "-1", "8", "1", "7", "60", 5.0),
            module.Deal("2026.01.02 08:05:00", "m1_micro_scalp", "-1", "8", "1", "7", "60", 6.0),
        ]

        rules = module.mine_trim_rules(
            deals,
            group_fields=("setup", "direction", "hour"),
            min_trades=3,
            max_pf=1.0,
            max_net=0.0,
        )

        self.assertEqual(len(rules), 1)
        self.assertEqual(rules[0].key, ("m1_micro_scalp", "1", "10"))
        self.assertEqual(rules[0].net_profit, -11.0)
        self.assertEqual(rules[0].saved_loss_if_trimmed, 11.0)

    def test_closed_deals_keep_ml_feature_snapshot(self):
        module = load_module()
        journal = ROOT / "scratch" / "sample-ml-features-test.trades.csv"
        journal.parent.mkdir(exist_ok=True)
        journal.write_text(
            "time\tmessage\n"
            "2026.01.01 10:05:00\tDeal event deal=2 entry=1 price=3342.10 profit=-7.50 dir=1 hour=10 setup=m1_micro_scalp scalpVariant=1 confluences=7/7 scoreBucket=60 spread=0.11 spreadToTpPct=8.25 adx=27.40 diGap=6.20 atr=2.10 atrRatio=1.15 ema21=3340.00 ema50=3338.00 vwap=3339.50 zoneBottom=3337.20 zoneTop=3341.20 zoneWidth=4.00 slDistance=3.50 lotMultiplier=1.50 setupRiskMultiplier=0.80\n"
        )
        self.addCleanup(journal.unlink)

        deals = module.parse_closed_deals(journal)

        self.assertEqual(len(deals), 1)
        self.assertEqual(deals[0].spread, 0.11)
        self.assertEqual(deals[0].spread_to_tp_pct, 8.25)
        self.assertEqual(deals[0].adx, 27.40)
        self.assertEqual(deals[0].di_gap, 6.20)
        self.assertEqual(deals[0].zone_width, 4.00)
        self.assertEqual(deals[0].sl_distance, 3.50)
        self.assertEqual(deals[0].lot_multiplier, 1.50)
        self.assertEqual(deals[0].setup_risk_multiplier, 0.80)

    def test_ml_rows_include_features_and_label(self):
        module = load_module()
        deal = module.Deal(
            "2026.01.01 10:05:00",
            "m1_micro_scalp",
            "1",
            "10",
            "1",
            "7",
            "60",
            -7.0,
            spread=0.11,
            spread_to_tp_pct=8.25,
            adx=27.4,
            di_gap=6.2,
            atr=2.1,
            atr_ratio=1.15,
            zone_width=4.0,
            sl_distance=3.5,
            lot_multiplier=1.5,
            setup_risk_multiplier=0.8,
        )

        rows = module.deals_to_ml_rows([deal])

        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["label_win"], 0)
        self.assertEqual(rows[0]["profit"], -7.0)
        self.assertEqual(rows[0]["setup"], "m1_micro_scalp")
        self.assertEqual(rows[0]["adx"], 27.4)
        self.assertEqual(rows[0]["spread_to_tp_pct"], 8.25)


if __name__ == "__main__":
    unittest.main()
