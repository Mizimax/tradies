import importlib.util
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "goldbot-prop-simulate.py"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


adapter = load_module(SCRIPT, "goldbot_prop_simulate")


class GoldBotPropSimulationTests(unittest.TestCase):
    def test_two_year_report_reconciles_including_swap(self):
        report = ROOT / "mt5" / "backtests" / "reports" / "GoldBot-prop-ftmo-p1-25000-2y.htm"
        if not report.exists():
            self.skipTest("local MT5 evidence report is not present")

        rows, deposit, extracted_net, _ = adapter.extract_r_multiple_rows(report)
        official_net = adapter.dd_attribution.official_net_profit(report)

        self.assertEqual(deposit, 25000.0)
        self.assertEqual(len(rows), 275)
        self.assertIsNotNone(official_net)
        self.assertAlmostEqual(extracted_net, official_net, places=2)


if __name__ == "__main__":
    unittest.main()
