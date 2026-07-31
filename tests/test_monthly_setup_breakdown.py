import importlib.util
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "monthly-setup-breakdown.py"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class MonthlySetupBreakdownTests(unittest.TestCase):
    def setUp(self):
        self.module = load_module(SCRIPT, "monthly_setup_breakdown")

    def test_journal_stem_strips_trades_csv_suffix(self):
        module = self.module
        self.assertEqual(
            module.journal_stem(Path("GoldBot-real-daily2-ai-s3-2y-1000.trades.csv")),
            "GoldBot-real-daily2-ai-s3-2y-1000",
        )

    def test_month_bucket_parses_mt5_timestamp(self):
        module = self.module
        self.assertEqual(module.month_bucket("2024.07.05 09:53:16"), "2024-07")

    def test_build_rows_groups_closed_trades_by_month_and_setup(self):
        module = self.module
        journal = ROOT / "scratch" / "sample-monthly-setup.trades.csv"
        journal.parent.mkdir(exist_ok=True)
        journal.write_text(
            "time\tmessage\n"
            "2026.01.01 10:00:00\tDeal event deal=1 entry=0 reason=3 profit=0.00 setup=m5_scalp\n"
            "2026.01.01 10:30:00\tDeal event deal=2 entry=1 reason=4 profit=-5.00 setup=m5_scalp\n"
            "2026.01.15 11:00:00\tDeal event deal=3 entry=1 reason=3 profit=8.00 setup=smc\n"
            "2026.02.01 09:00:00\tDeal event deal=4 entry=1 reason=4 profit=-3.00 setup=m5_scalp\n"
        )
        self.addCleanup(journal.unlink)

        rows, months, setups, cells = module.build_rows(journal)

        self.assertEqual(months, ["2026-01", "2026-02"])
        self.assertEqual(setups, ["m5_scalp", "smc"])

        jan_total = next(
            r for r in rows if r["month"] == "2026-01" and r["setup"] == module.ALL_SETUPS
        )
        self.assertEqual(jan_total["closed_deals"], "2")
        self.assertEqual(jan_total["net_profit"], "3.00")

        grand_total = next(
            r for r in rows if r["month"] == module.ALL_MONTHS and r["setup"] == module.ALL_SETUPS
        )
        self.assertEqual(grand_total["closed_deals"], "3")
        self.assertEqual(grand_total["net_profit"], "0.00")


if __name__ == "__main__":
    unittest.main()
