import csv
import importlib.util
from pathlib import Path
import sys
from tempfile import TemporaryDirectory


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "qbr_analyzer", ROOT / "scripts/qbr/analyze_backtest.py"
)
ANALYZER = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = ANALYZER
SPEC.loader.exec_module(ANALYZER)


def write_csv(path: Path, header: list[str], records: list[list[object]]) -> None:
    with path.open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(header)
        writer.writerows(records)


def test_report_reconciliation_accepts_matching_native_stop():
    with TemporaryDirectory() as directory:
        tmp_path = Path(directory)
        logs = tmp_path / "logs"
        logs.mkdir()
        write_csv(
            logs / "baskets.csv",
            ["net_profit", "closed_deals", "closed_positions"],
            [[3.0, 1, 1], [-7.5, 1, 1]],
        )
        write_csv(
            logs / "deals.csv",
            ["deal_ticket", "position_id", "entry", "net_profit"],
            [[1, 101, "DEAL_ENTRY_IN", 0.0], [2, 101, "DEAL_ENTRY_OUT", 3.0],
             [3, 102, "DEAL_ENTRY_IN", 0.0], [4, 102, "DEAL_ENTRY_OUT", -7.5]],
        )
        report = tmp_path / "report.htm"
        report.write_text(
            "Total Net Profit: -4.50 Total Trades: 2 History Quality: 100% real ticks"
        )
        result = ANALYZER.reconcile_with_report(
            ANALYZER.rows(logs / "baskets.csv"), ANALYZER.rows(logs / "deals.csv"),
            report, tolerance=0.01
        )
        assert result["passed"] is True
        assert result["basket_report_net_difference"] == 0.0
        assert result["deal_report_net_difference"] == 0.0
        assert result["basket_deal_difference"] == 0


def test_report_reconciliation_rejects_missing_native_stop():
    with TemporaryDirectory() as directory:
        tmp_path = Path(directory)
        logs = tmp_path / "logs"
        logs.mkdir()
        write_csv(logs / "baskets.csv", ["net_profit", "closed_deals", "closed_positions"], [[3.0, 1, 1]])
        write_csv(logs / "deals.csv", ["deal_ticket", "position_id", "entry", "net_profit"], [[1, 101, "DEAL_ENTRY_OUT", 3.0]])
        report = tmp_path / "report.htm"
        report.write_text(
            "Total Net Profit: -4.50 Total Trades: 2 History Quality: 100% real ticks"
        )
        try:
            ANALYZER.reconcile_with_report(
                ANALYZER.rows(logs / "baskets.csv"), ANALYZER.rows(logs / "deals.csv"),
                report, tolerance=0.01
            )
        except RuntimeError as exc:
            assert "reconciliation failed" in str(exc)
        else:
            raise AssertionError("missing broker-native stop must fail reconciliation")


def test_partial_close_reconciles_two_deals_as_one_closed_position():
    with TemporaryDirectory() as directory:
        tmp_path = Path(directory)
        logs = tmp_path / "logs"
        logs.mkdir()
        write_csv(logs / "baskets.csv", ["net_profit", "closed_deals", "closed_positions"], [[2.5, 2, 1]])
        write_csv(
            logs / "deals.csv",
            ["deal_ticket", "position_id", "entry", "net_profit"],
            [[10, 500, "DEAL_ENTRY_OUT", 1.0], [11, 500, "DEAL_ENTRY_OUT", 1.5]],
        )
        report = tmp_path / "report.htm"
        report.write_text("Total Net Profit: 2.50 Total Trades: 1 History Quality: 100% real ticks")
        result = ANALYZER.reconcile_with_report(
            ANALYZER.rows(logs / "baskets.csv"), ANALYZER.rows(logs / "deals.csv"), report
        )
        assert result["deal_exit_count"] == 2
        assert result["deal_unique_closed_positions"] == 1
        assert result["passed"] is True


def test_discovery_baseline_is_compared_as_percent_not_dollars():
    baskets = [{"run_id": "v113-control", "end_time": "2026.01.15 12:00:00", "net_profit": "70"}]
    report = {
        "initial_deposit": 2000.0,
        "profit_factor": 1.5,
        "win_rate_pct": 75.0,
        "equity_drawdown_pct": 5.0,
        "history_quality_pct": 100.0,
        "total_trades": 360,
        "net_profit": 70.0,
        "from_date": "2026.01.01",
        "to_date": "2026.06.30",
    }
    result = ANALYZER.acceptance_result(report, baskets, [])
    assert result is not None
    assert result["checks"]["return_above_v112_control"] is False


def test_scaled_acceptance_uses_geometric_monthly_return():
    profits = [500.0, 750.0, 1125.0, 1687.5, 2531.25, 3796.875]
    baskets = [
        {
            "run_id": "v113-scale200",
            "end_time": f"2026.{month:02d}.15 12:00:00",
            "net_profit": str(profit),
        }
        for month, profit in enumerate(profits, start=1)
    ]
    report = {
        "initial_deposit": 1000.0,
        "profit_factor": 1.5,
        "win_rate_pct": 75.0,
        "equity_drawdown_pct": 20.0,
        "history_quality_pct": 100.0,
        "total_trades": 600,
        "net_profit": sum(profits),
        "from_date": "2026.01.01",
        "to_date": "2026.06.30",
    }
    result = ANALYZER.acceptance_result(report, baskets, [])
    assert result is not None
    assert result["safety_gate_passed"] is True
    assert result["target_50pct_geometric_monthly_passed"] is True
    assert round(result["monthly"]["geometric_mean_monthly_return_pct"], 8) == 50.0
