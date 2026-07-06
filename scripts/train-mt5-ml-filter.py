#!/usr/bin/env python3
"""Train an offline XGBoost/LightGBM filter from GoldBot MT5 journals.

This script is intentionally offline-only. It learns from closed MT5 deal
journals, reports out-of-sample classification metrics on a temporal split, and
optionally saves a model. The EA is still deterministic until a trained filter is
explicitly converted into candidate rules or a runtime gate.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any, Sequence


ROOT = Path(__file__).resolve().parents[1]
PARSER_PATH = ROOT / "scripts" / "mt5-ml-trim-analysis.py"
CATEGORICAL_FIELDS = ("setup", "direction", "hour", "scalp_variant", "confluences", "score_bucket")
NUMERIC_FIELDS = (
    "spread",
    "spread_to_tp_pct",
    "adx",
    "di_gap",
    "atr",
    "atr_ratio",
    "ema21",
    "ema50",
    "vwap",
    "zone_width",
    "sl_distance",
    "lot_multiplier",
    "setup_risk_multiplier",
)


def load_parser_module():
    spec = importlib.util.spec_from_file_location("mt5_ml_trim_analysis", PARSER_PATH)
    module = importlib.util.module_from_spec(spec)
    if spec.loader is None:
        raise RuntimeError(f"Cannot load parser module: {PARSER_PATH}")
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def load_backend(name: str):
    if name == "auto":
        errors: list[str] = []
        for candidate in ("xgboost", "lightgbm"):
            try:
                return candidate, load_backend(candidate)[1]
            except RuntimeError as exc:
                errors.append(str(exc))
                continue
        detail = "; ".join(errors)
        raise RuntimeError(
            "No usable ML backend. Install packages with: python3 -m pip install -r requirements-ml.txt. "
            "On macOS, native wheels also need OpenMP: brew install libomp. "
            f"Details: {detail}"
        )

    if name == "xgboost":
        try:
            import xgboost as xgb
        except Exception as exc:
            raise RuntimeError(f"xgboost import failed: {exc}") from exc
        return name, xgb

    if name == "lightgbm":
        try:
            import lightgbm as lgb
        except Exception as exc:
            raise RuntimeError(f"lightgbm import failed: {exc}") from exc
        return name, lgb

    raise ValueError(f"Unsupported backend: {name}")


def as_float(value: Any) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def build_feature_matrix(rows: Sequence[dict[str, Any]]) -> tuple[list[list[float]], list[int], list[str]]:
    categories: dict[str, list[str]] = {}
    for field in CATEGORICAL_FIELDS:
        categories[field] = sorted({str(row.get(field, "")) for row in rows})

    feature_names = list(NUMERIC_FIELDS)
    for field in CATEGORICAL_FIELDS:
        feature_names.extend(f"{field}={value}" for value in categories[field])

    matrix: list[list[float]] = []
    labels: list[int] = []
    for row in rows:
        vector = [as_float(row.get(field)) for field in NUMERIC_FIELDS]
        for field in CATEGORICAL_FIELDS:
            actual = str(row.get(field, ""))
            vector.extend(1.0 if actual == value else 0.0 for value in categories[field])
        matrix.append(vector)
        labels.append(int(row["label_win"]))
    return matrix, labels, feature_names


def temporal_split(total: int, test_ratio: float) -> tuple[slice, slice]:
    test_count = max(1, int(total * test_ratio))
    train_count = max(1, total - test_count)
    if train_count >= total:
        train_count = total - 1
    return slice(0, train_count), slice(train_count, total)


def auc_score(labels: Sequence[int], probabilities: Sequence[float]) -> float:
    positives = sum(1 for label in labels if label == 1)
    negatives = len(labels) - positives
    if positives == 0 or negatives == 0:
        return 0.0
    ranked = sorted(zip(probabilities, labels), key=lambda item: item[0])
    rank_sum = 0.0
    for rank, (_, label) in enumerate(ranked, start=1):
        if label == 1:
            rank_sum += rank
    return (rank_sum - positives * (positives + 1) / 2.0) / (positives * negatives)


def classification_report(labels: Sequence[int], probabilities: Sequence[float]) -> dict[str, float]:
    predictions = [1 if prob >= 0.5 else 0 for prob in probabilities]
    tp = sum(1 for label, pred in zip(labels, predictions) if label == 1 and pred == 1)
    tn = sum(1 for label, pred in zip(labels, predictions) if label == 0 and pred == 0)
    fp = sum(1 for label, pred in zip(labels, predictions) if label == 0 and pred == 1)
    fn = sum(1 for label, pred in zip(labels, predictions) if label == 1 and pred == 0)
    total = len(labels)
    return {
        "trades": float(total),
        "positive_rate": round(sum(labels) / total, 4) if total else 0.0,
        "accuracy": round((tp + tn) / total, 4) if total else 0.0,
        "precision": round(tp / (tp + fp), 4) if tp + fp else 0.0,
        "recall": round(tp / (tp + fn), 4) if tp + fn else 0.0,
        "auc": round(auc_score(labels, probabilities), 4),
    }


def train_model(backend_name: str, backend, x_train, y_train):
    if backend_name == "xgboost":
        model = backend.XGBClassifier(
            n_estimators=120,
            max_depth=3,
            learning_rate=0.05,
            subsample=0.8,
            colsample_bytree=0.8,
            eval_metric="logloss",
            random_state=42,
        )
        model.fit(x_train, y_train)
        return model

    model = backend.LGBMClassifier(
        n_estimators=160,
        max_depth=3,
        learning_rate=0.04,
        subsample=0.8,
        colsample_bytree=0.8,
        random_state=42,
        verbose=-1,
    )
    model.fit(x_train, y_train)
    return model


def predict_probabilities(model, x_test) -> list[float]:
    probabilities = model.predict_proba(x_test)
    return [float(row[1]) for row in probabilities]


def save_model(model, output_model: Path, feature_names: Sequence[str], metrics: dict[str, float]) -> None:
    output_model.parent.mkdir(parents=True, exist_ok=True)
    model.save_model(str(output_model))
    metadata_path = output_model.with_suffix(output_model.suffix + ".meta.json")
    metadata_path.write_text(
        json.dumps({"feature_names": list(feature_names), "metrics": metrics}, indent=2) + "\n"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("journals", nargs="+", type=Path, help="GoldBot *.trades.csv journal files")
    parser.add_argument("--backend", choices=("auto", "xgboost", "lightgbm"), default="auto")
    parser.add_argument("--min-trades", type=int, default=100)
    parser.add_argument("--test-ratio", type=float, default=0.30)
    parser.add_argument("--output-model", type=Path, help="Optional path for the trained model")
    args = parser.parse_args()

    missing = [str(path) for path in args.journals if not path.exists()]
    if missing:
        print("Missing journal(s): " + ", ".join(missing), file=sys.stderr)
        return 1

    try:
        backend_name, backend = load_backend(args.backend)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    parser_module = load_parser_module()
    deals = []
    for path in args.journals:
        deals.extend(parser_module.parse_closed_deals(path))
    rows = parser_module.deals_to_ml_rows(deals)

    if len(rows) < args.min_trades:
        print(f"Not enough closed deals for ML: {len(rows)} < {args.min_trades}", file=sys.stderr)
        return 1

    matrix, labels, feature_names = build_feature_matrix(rows)
    train_slice, test_slice = temporal_split(len(matrix), args.test_ratio)
    model = train_model(backend_name, backend, matrix[train_slice], labels[train_slice])
    probabilities = predict_probabilities(model, matrix[test_slice])
    metrics = classification_report(labels[test_slice], probabilities)
    metrics["train_trades"] = float(len(labels[train_slice]))
    metrics["backend"] = backend_name

    print(json.dumps(metrics, indent=2))
    if args.output_model:
        save_model(model, args.output_model, feature_names, metrics)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
