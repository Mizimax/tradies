import importlib.util
import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "run_qbr_candidate", ROOT / "scripts/run-qbr-candidate.py"
)
RUNNER = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = RUNNER
SPEC.loader.exec_module(RUNNER)


def test_candidate_ladder_has_fixed_contracts():
    expected = {
        "v113-control",
        "v113-minlot-cap",
        "v113-stop60",
        "v113-stop45",
        "v113-lock40",
        "v113-qsync22",
        "v113-conf64",
        "v113-m5-15-30",
        "v113-m5-20-40",
        "v113-scale100",
        "v113-scale150",
        "v113-scale200",
    }
    assert set(RUNNER.CANDIDATES) == expected
    assert RUNNER.BUILD_TAG == "QBR-1.13-aggressive"


def test_scaled_candidates_keep_safety_and_loss_target_ratio():
    for name, risk in (("v113-scale100", "1.0"), ("v113-scale150", "1.5"), ("v113-scale200", "2.0")):
        values = RUNNER.CANDIDATES[name].overrides
        assert values["InpRiskPerBasketPct"] == risk
        assert values["InpMaxEquityDrawdownPct"] == "25.0"
        assert values["InpMaxDailyLossPct"] == "4.0"
        assert values["InpMaxWeeklyLossPct"] == "8.0"
        assert values["InpMaxLossTargetRatio"] == "2.0"


def test_m5_candidates_are_closed_bar_profiles():
    first = RUNNER.CANDIDATES["v113-m5-15-30"].overrides
    second = RUNNER.CANDIDATES["v113-m5-20-40"].overrides
    assert first["InpEnableM5ScalpLayer"] == "true"
    assert first["InpM5TargetPct"] == "0.15"
    assert first["InpM5HardStopPct"] == "0.3"
    assert second["InpM5TargetPct"] == "0.2"
    assert second["InpM5HardStopPct"] == "0.4"


def test_runner_waits_for_stable_report_and_reconciles():
    source = (ROOT / "scripts/run-qbr-candidate.py").read_text()
    assert "wait_for_report" in source
    assert "configured_terminal_running" in source
    assert '"--report"' in source
    assert "analyze_backtest.py" in source


def test_process_detection_accepts_truncated_metatester_name():
    original = RUNNER.process_commands
    try:
        RUNNER.process_commands = lambda: ["C:/Program Files/MetaTrader 5/metateste --run"]
        assert RUNNER.configured_terminal_running("candidate.ini") is True
    finally:
        RUNNER.process_commands = original


def write_evidence(root: Path, name: str, *, trades: int, net: float, pf: float = 1.5) -> None:
    path = root / f"QBR-{name}-XAUUSD-M15-2026.01.01-2026.06.30.qbr-analysis"
    path.mkdir()
    (path / "analysis_summary.json").write_text(json.dumps({
        "report_metrics": {
            "expert": "QuantumBehavioralReplica",
            "build_tag": "QBR-1.13-aggressive",
            "run_id": name,
            "initial_deposit": 1000.0,
            "leverage": 100,
            "history_quality_pct": 100.0,
            "net_profit": net,
            "total_trades": trades,
            "win_rate_pct": 75.0,
            "profit_factor": pf,
            "equity_drawdown_pct": 5.0,
        },
        "acceptance": {"safety_gate_passed": trades >= 360},
        "data_quality": {"report_reconciliation": {"passed": True}},
    }))


def test_lock40_inherits_best_evidenced_stop_configuration():
    with TemporaryDirectory() as directory:
        original = RUNNER.REPORT_DIR
        try:
            RUNNER.REPORT_DIR = Path(directory)
            write_evidence(RUNNER.REPORT_DIR, "v113-stop60", trades=100, net=20.0, pf=1.4)
            write_evidence(RUNNER.REPORT_DIR, "v113-stop45", trades=100, net=30.0, pf=1.6)
            resolved, lineage = RUNNER.resolved_candidate(
                "v113-lock40", "XAUUSD", "2026.01.01", "2026.06.30"
            )
            assert lineage == ["v113-stop45"]
            assert resolved.overrides["InpBasketHardStopPct"] == "0.45"
            assert resolved.overrides["InpProfitLockFloorFraction"] == "0.4"
        finally:
            RUNNER.REPORT_DIR = original


def test_m5_layer_is_blocked_when_m15_frequency_is_already_60_per_month():
    with TemporaryDirectory() as directory:
        original = RUNNER.REPORT_DIR
        try:
            RUNNER.REPORT_DIR = Path(directory)
            write_evidence(RUNNER.REPORT_DIR, "v113-stop60", trades=100, net=20.0)
            write_evidence(RUNNER.REPORT_DIR, "v113-stop45", trades=100, net=10.0)
            write_evidence(RUNNER.REPORT_DIR, "v113-lock40", trades=100, net=20.0)
            write_evidence(RUNNER.REPORT_DIR, "v113-qsync22", trades=100, net=20.0)
            write_evidence(RUNNER.REPORT_DIR, "v113-conf64", trades=360, net=50.0)
            try:
                RUNNER.resolved_candidate(
                    "v113-m5-15-30", "XAUUSD", "2026.01.01", "2026.06.30"
                )
            except RuntimeError as exc:
                assert "M5 layer is forbidden" in str(exc)
            else:
                raise AssertionError("M5 must not run after M15 reaches 60 trades/month")
        finally:
            RUNNER.REPORT_DIR = original


def test_prerequisite_rejects_wrong_deposit_or_unreconciled_logs():
    with TemporaryDirectory() as directory:
        original = RUNNER.REPORT_DIR
        try:
            RUNNER.REPORT_DIR = Path(directory)
            write_evidence(RUNNER.REPORT_DIR, "v113-stop60", trades=100, net=20.0)
            path = next(RUNNER.REPORT_DIR.glob("*stop60*.qbr-analysis/analysis_summary.json"))
            summary = json.loads(path.read_text())
            summary["report_metrics"]["initial_deposit"] = 10000.0
            summary["data_quality"]["report_reconciliation"]["passed"] = False
            path.write_text(json.dumps(summary))
            try:
                RUNNER.evidence_summary("v113-stop60", "XAUUSD", "2026.01.01", "2026.06.30")
            except RuntimeError as exc:
                assert "initial_deposit" in str(exc)
                assert "reconciliation" in str(exc)
            else:
                raise AssertionError("invalid prerequisite evidence must be rejected")
        finally:
            RUNNER.REPORT_DIR = original
