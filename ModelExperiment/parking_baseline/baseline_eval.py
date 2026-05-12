"""
baseline_eval.py
────────────────
Runs OCR on every parking image, applies a Python port of VisionAnalyzer's
decision tree, then compares against your ground truth labels.

Usage:
    python baseline_eval.py --images /path/to/parking/folder --labels labels.csv

Output:
    baseline_results.csv   — full results with ocr_tokens + heuristic_label + match flag
    baseline_report.txt    — accuracy summary printed to console + saved
"""

import re
import os
import sys
import argparse
import pandas as pd
import pytesseract
from PIL import Image
from pathlib import Path


# ── OCR ───────────────────────────────────────────────────────────────────────

def run_ocr(image_path: str) -> list[dict]:
    """
    Returns list of {text, height} dicts sorted by bounding box height desc.
    Mirrors VNRecognizeTextRequest output — larger text = higher priority.
    """
    img = Image.open(image_path)
    img_h = img.height

    data = pytesseract.image_to_data(img, output_type=pytesseract.Output.DICT)

    tokens = []
    for i, text in enumerate(data["text"]):
        text = text.strip()
        if not text:
            continue
        conf = int(data["conf"][i])
        if conf < 20:  # mirrors ocrFallbackConfidence ~0.28 → ~28%
            continue
        h = data["height"][i]
        norm_h = h / img_h  # normalise to 0-1 like Vision's boundingBox.height
        tokens.append({"text": text, "height": norm_h, "conf": conf})

    tokens.sort(key=lambda x: x["height"], reverse=True)
    return tokens


# ── Text normalisation (mirrors normalizeOCRText) ────────────────────────────

def normalize(raw: str) -> str:
    s = raw.upper().strip()
    s = re.sub(r"[^A-Z0-9\s\-]", "", s)
    s = re.sub(r"\s+", " ", s)
    s = re.sub(r"\s*-\s*", "-", s)
    return s.strip()


# ── Decision tree (mirrors extractTextContext) ────────────────────────────────

PARKING_STOP_WORDS = {
    "ROW", "CENTRAL", "GALLERIA", "STREET", "ROAD",
    "EXIT", "ENTRANCE", "IKEA", "LOBBY"
}

PARKING_KEYWORDS = [
    "LEVEL", "FLOOR", "ZONE", "BASEMENT", "GROUND", "PARKING", "PARK"
]

EMIRATES = [
    "DUBAI", "ABU DHABI", "SHARJAH", "AJMAN", "RAK",
    "FUJAIRAH", "UAQ"
]


def regex_match(text: str, pattern: str) -> bool:
    return bool(re.match(pattern, text))


def extract_text_context(tokens: list[dict]) -> str | None:
    """Direct port of VisionAnalyzer.extractTextContext"""
    items = [
        {"text": normalize(t["text"]), "size": t["size"]}
        for t in tokens
        if normalize(t["text"])
    ]
    if not items:
        return None

    # ── Strong pass: row markers like P1, B5, G8 ──
    row_markers = sorted(
        [i for i in items if regex_match(i["text"], r"^[PGBL][0-9]{1,3}$")],
        key=lambda x: x["size"], reverse=True
    )
    row_suffix_candidates = sorted(
        [i for i in items
         if regex_match(i["text"], r"^[A-Z]{1,2}$")
         and i["text"] not in PARKING_STOP_WORDS
         and i["text"] not in EMIRATES],
        key=lambda x: x["size"], reverse=True
    )

    if row_markers:
        best_row = row_markers[0]
        if row_suffix_candidates:
            suffix = row_suffix_candidates[0]
            if suffix["size"] >= best_row["size"] * 0.35:
                return f"Parking · {best_row['text']} {suffix['text']}"
        return f"Parking · {best_row['text']}"

    # ── Parking candidates with scoring ──
    parking_candidates = []

    # Adjacent split tokens e.g. "P1" + "H"
    for i in range(len(items) - 1):
        left, right = items[i], items[i + 1]
        if (regex_match(left["text"], r"^[PGBL][0-9]{1,3}$")
                and regex_match(right["text"], r"^[A-Z]{1,2}$")
                and right["text"] not in PARKING_STOP_WORDS):
            combined = f"{left['text']} {right['text']}"
            score = (left["size"] + right["size"]) * 100 + 58
            parking_candidates.append({"value": combined, "score": score})

    for item in items:
        text = item["text"]
        if text in PARKING_STOP_WORDS:
            continue
        score = item["size"] * 100

        if regex_match(text, r"^[PGBL][0-9]{1,3}\s?[A-Z]{1,2}$"):
            score += 60
            parking_candidates.append({"value": text, "score": score})
        elif regex_match(text, r"^[PGBL][0-9]{1,3}$"):
            score += 42
            parking_candidates.append({"value": text, "score": score})
        elif regex_match(text, r"^[A-Z][0-9]{1,3}$") or regex_match(text, r"^[0-9]{1,3}[A-Z]$"):
            score += 34
            parking_candidates.append({"value": text, "score": score})
        elif regex_match(text, r"^(LEVEL|L)\s?[0-9]{1,2}$"):
            score += 26
            compact = re.sub(r"LEVEL\s?", "L", text)
            parking_candidates.append({"value": compact, "score": score})

    if parking_candidates:
        sorted_c = sorted(parking_candidates, key=lambda x: x["score"], reverse=True)
        primary = sorted_c[0]["value"]
        for candidate in sorted_c[1:]:
            v = candidate["value"]
            if v != primary and len(v) <= 4 and regex_match(v, r"^([A-Z]{1,2}|[0-9]{1,3}[A-Z]?)$"):
                return f"Parking · {primary} {v}"
        return f"Parking · {primary}"

    # ── Keyword fallback ──
    for item in items:
        for kw in PARKING_KEYWORDS:
            if kw in item["text"]:
                return f"Parking · {item['text']}"

    # ── Plate-like fallback ──
    letter_codes = sorted(
        [i for i in items if regex_match(i["text"], r"^[A-Z]{1,3}$")],
        key=lambda x: x["size"], reverse=True
    )
    numbers = sorted(
        [i for i in items if regex_match(i["text"], r"^[0-9]{1,6}$")],
        key=lambda x: x["size"], reverse=True
    )

    if not numbers:
        return None

    best_number = numbers[0]["text"]
    digits = len(best_number)

    emirate_match = next(
        (i["text"] for i in items
         if any(e in i["text"] for e in EMIRATES)),
        None
    )

    if emirate_match:
        parts = [emirate_match]
        if letter_codes:
            parts.append(letter_codes[0]["text"])
        parts.append(best_number)
        return " · ".join(parts)

    if digits >= 4 and letter_codes:
        return f"{letter_codes[0]['text']} · {best_number}"
    if digits <= 3 and letter_codes:
        return f"Parking · {letter_codes[0]['text']} {best_number}"
    if digits >= 4:
        return best_number

    return None


def build_heuristic_label(tokens: list[dict]) -> str:
    """Top-level label builder — mirrors buildSmartLabel for parking images."""
    text_with_sizes = [{"text": t["text"], "size": t["height"]} for t in tokens]
    result = extract_text_context(text_with_sizes)
    return result if result else "Memory"


# ── Evaluation ────────────────────────────────────────────────────────────────

def label_match(predicted: str, ground_truth: str) -> bool:
    """Exact match after normalising whitespace and case."""
    if pd.isna(ground_truth) or str(ground_truth).strip().lower() in ("<null>", "null", ""):
        return pd.isna(predicted) or str(predicted).strip() in ("", "Memory")
    return str(predicted).strip().lower() == str(ground_truth).strip().lower()


def run_eval(images_dir: str, labels_csv: str):
    df = pd.read_csv(labels_csv)

    # Normalise column names (strip whitespace)
    df.columns = df.columns.str.strip()

    results = []

    for _, row in df.iterrows():
        image_id = str(row["image_id"]).strip()
        true_label = row.get("true_label", "")
        true_class = row.get("true_classification", "parking")

        image_path = os.path.join(images_dir, f"{image_id}.jpg")

        if not os.path.exists(image_path):
            print(f"  ⚠️  {image_id}.jpg not found — skipping")
            continue

        # Run OCR
        try:
            tokens = run_ocr(image_path)
        except Exception as e:
            print(f"  ❌  OCR failed on {image_id}: {e}")
            tokens = []

        ocr_tokens_str = ", ".join([t["text"] for t in tokens[:10]])

        # Run heuristic
        heuristic_label = build_heuristic_label(tokens)

        # Compare
        match = label_match(heuristic_label, true_label)
        notes = row.get("notes", "")

        results.append({
            "image_id": image_id,
            "true_classification": true_class,
            "true_label": true_label,
            "ocr_tokens": ocr_tokens_str,
            "heuristic_label": heuristic_label,
            "match": match,
            "notes": notes,
        })

        status = "✅" if match else "❌"
        print(f"  {status}  {image_id}  |  true: {true_label!r:25}  |  predicted: {heuristic_label!r}")

    results_df = pd.DataFrame(results)

    # ── Metrics ──
    total = len(results_df)
    null_rows = results_df[
        results_df["true_label"].astype(str).str.lower().isin(["<null>", "null", "nan", ""])
    ]
    scoreable = results_df[
        ~results_df["true_label"].astype(str).str.lower().isin(["<null>", "null", "nan", ""])
    ]

    correct = scoreable["match"].sum()
    accuracy = correct / len(scoreable) * 100 if len(scoreable) > 0 else 0

    report = f"""
════════════════════════════════════════
  BASELINE EVAL — VisionAnalyzer Heuristic
════════════════════════════════════════
  Total images evaluated : {total}
  Null / unannotated     : {len(null_rows)}
  Scoreable              : {len(scoreable)}

  Exact match accuracy   : {correct}/{len(scoreable)}  ({accuracy:.1f}%)

  Failures ({len(scoreable) - correct} images):
"""

    failures = scoreable[~scoreable["match"]]
    for _, r in failures.iterrows():
        report += f"    {r['image_id']}  true={r['true_label']!r}  got={r['heuristic_label']!r}\n"

    report += "════════════════════════════════════════\n"

    print(report)

    # Save outputs
    out_csv = "baseline_results.csv"
    out_txt = "baseline_report.txt"
    results_df.to_csv(out_csv, index=False)
    with open(out_txt, "w") as f:
        f.write(report)

    print(f"  💾  Saved: {out_csv}")
    print(f"  💾  Saved: {out_txt}")


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--images", required=True, help="Path to folder containing park_001.jpg etc.")
    parser.add_argument("--labels", required=True, help="Path to your labels CSV exported from Google Sheets")
    args = parser.parse_args()
    run_eval(args.images, args.labels)
