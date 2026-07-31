import importlib.util
import sys
import unittest
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "analyze-drawdown-attribution.py"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class AnalyzeDrawdownAttributionTests(unittest.TestCase):
    def setUp(self):
        self.module = load_module(SCRIPT, "analyze_drawdown_attribution")

    def test_parse_journal_closes_extracts_only_closing_deal_events(self):
        module = self.module
        journal = ROOT / "scratch" / "sample-dd-attribution.trades.csv"
        journal.parent.mkdir(exist_ok=True)
        journal.write_text(
            "time\tmessage\n"
            "2026.01.01 10:00:00\tDeal event deal=1 position=1 entry=0 type=0 reason=3 profit=0.00 "
            "dir=1 split=1 hour=10 setup=m5_scalp\n"
            "2026.01.01 10:30:00\tDeal event deal=2 position=1 entry=1 type=1 reason=4 profit=-5.00 "
            "dir=1 split=1 hour=10 setup=m5_scalp comment=sl 2360.00\n"
            "2026.01.01 11:00:00\tDeal event deal=3 position=2 entry=1 type=1 reason=3 profit=8.00 "
            "dir=1 split=1 hour=12 setup=smc\n"
            "2026.01.01 11:15:00\tSignal skipped reason=hour\n"
        )
        self.addCleanup(journal.unlink)

        closes = module.parse_journal_closes(journal)

        self.assertEqual(len(closes), 2)
        self.assertEqual(closes[0].setup, "m5_scalp")
        self.assertTrue(closes[0].is_sl)
        self.assertEqual(closes[0].profit, -5.00)
        self.assertEqual(closes[1].setup, "smc")
        self.assertFalse(closes[1].is_sl)
        self.assertEqual(closes[1].profit, 8.00)

    def test_match_trades_joins_htm_deals_to_journal_closes_by_time(self):
        module = self.module

        class FakeDeal:
            def __init__(self, time, profit, direction="out"):
                self.time = time
                self.profit = profit
                self.direction = direction

        deals = [
            FakeDeal(datetime(2026, 1, 1, 10, 30, 0), -5.00),
            FakeDeal(datetime(2026, 1, 1, 11, 0, 0), 8.00),
        ]
        journal_closes = [
            module.JournalClose(
                time=datetime(2026, 1, 1, 10, 30, 1), profit=-5.00, setup="m5_scalp",
                direction="1", split="1", hour="10", exit_code="4", is_sl=True,
            ),
            module.JournalClose(
                time=datetime(2026, 1, 1, 11, 0, 0), profit=8.00, setup="smc",
                direction="1", split="1", hour="12", exit_code="3", is_sl=False,
            ),
        ]

        matched, unmatched = module.match_trades(deals, journal_closes)

        self.assertEqual(unmatched, 0)
        self.assertEqual(len(matched), 2)
        self.assertIsNotNone(matched[0].journal)
        self.assertEqual(matched[0].journal.setup, "m5_scalp")
        self.assertIsNotNone(matched[1].journal)
        self.assertEqual(matched[1].journal.setup, "smc")

    def test_episode_window_trades_excludes_the_peak_forming_trade(self):
        module = self.module

        class FakeEpisode:
            event_num = 1
            peak_date = datetime(2026, 1, 1, 10, 0, 0)
            trough_date = datetime(2026, 1, 3, 10, 0, 0)

        peak_trade = module.MatchedTrade(time=datetime(2026, 1, 1, 10, 0, 0), profit=50.0, journal=None)
        loss_trade = module.MatchedTrade(time=datetime(2026, 1, 2, 10, 0, 0), profit=-20.0, journal=None)
        trough_trade = module.MatchedTrade(time=datetime(2026, 1, 3, 10, 0, 0), profit=-10.0, journal=None)
        matched = [peak_trade, loss_trade, trough_trade]

        window = module.episode_window_trades(FakeEpisode(), matched)

        # The trade AT peak_date created the high-water mark (a win) and must
        # not be double-counted as part of the drawdown's losses.
        self.assertNotIn(peak_trade, window)
        self.assertIn(loss_trade, window)
        self.assertIn(trough_trade, window)
        self.assertEqual(sum(t.profit for t in window), -30.0)

    def test_detect_sl_streaks_breaks_on_non_sl_or_unmatched_trades(self):
        module = self.module

        def sl_close(t, profit):
            return module.MatchedTrade(
                time=t, profit=profit,
                journal=module.JournalClose(
                    time=t, profit=profit, setup="m5_scalp", direction="1",
                    split="1", hour="10", exit_code="4", is_sl=True,
                ),
            )

        def tp_close(t, profit):
            return module.MatchedTrade(
                time=t, profit=profit,
                journal=module.JournalClose(
                    time=t, profit=profit, setup="m5_scalp", direction="1",
                    split="1", hour="10", exit_code="3", is_sl=False,
                ),
            )

        matched = [
            sl_close(datetime(2026, 1, 1, 10, 0), -5.0),
            sl_close(datetime(2026, 1, 1, 11, 0), -4.0),
            sl_close(datetime(2026, 1, 1, 12, 0), -3.0),
            tp_close(datetime(2026, 1, 1, 13, 0), 6.0),
            sl_close(datetime(2026, 1, 1, 14, 0), -2.0),
        ]

        streaks = module.detect_sl_streaks(matched)

        self.assertEqual(len(streaks), 1)
        self.assertEqual(streaks[0].length, 3)
        self.assertAlmostEqual(streaks[0].total_loss, -12.0)


if __name__ == "__main__":
    unittest.main()
