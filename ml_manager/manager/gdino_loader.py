"""
Real GroundingDINO inference adapter.

This module is imported lazily by GDinoService when GDINO_USE_STUB=0 and
a Visual Search request comes in. If the GroundingDINO package or its
checkpoint isn't installed, the import raises and the service stays in
stub mode (no inference, just placeholder boxes) without crashing.

To enable real inference:

  1. Install GroundingDINO inside the ml_manager container:
       pip install -e /app/GroundingDINO       # source tree mounted at /app/GroundingDINO
       (or: pip install groundingdino-py)

     The custom CUDA op (`MultiScaleDeformableAttention`) needs nvcc at
     install time. If nvcc is missing inside the runtime image, install
     during the Docker build instead.

  2. Download the model checkpoint to /app/models/groundingdino_swint_ogc.pth
     The official URL:
       https://github.com/IDEA-Research/GroundingDINO/releases/download/v0.1.0-alpha/groundingdino_swint_ogc.pth

  3. Make sure the config file is reachable at
     /app/GroundingDINO/groundingdino/config/GroundingDINO_SwinT_OGC.py

  4. Set GDINO_USE_STUB=0 in the ml_manager environment (docker-compose
     env_file) and restart the service.

If any of those preconditions is missing, GDinoService prints the import
error once and falls back to the stub path for that request. The user
sees fake boxes but the rest of the system still works.

────────────────────────────────────────────────────────────────
Tiled inference (for small / far-away objects)
────────────────────────────────────────────────────────────────
The model sees the full image downscaled to SHORT_SIDE × MAX_SIZE. Objects
that are small relative to the image become very small in the model input,
which hurts recall significantly.

Tiled inference solves this: the image is divided into overlapping tiles
and the model runs once per tile. Inside each tile the objects are much
larger relative to the input tensor, so the model can find them. Tile
detections are mapped back to full-image coordinates and duplicate boxes
from the overlap zones are removed by NMS.

The full image is also always processed alongside the tiles so that large
objects or objects that straddle a tile boundary are still caught.

Env vars (all optional, sensible defaults):
  GDINO_SHORT_SIDE   Shorter-side target for the model transform (default 1600)
  GDINO_MAX_SIZE     Longest-side cap for the model transform (default 2400)
  GDINO_TILE_ROWS    Rows in the tile grid (default 2)
  GDINO_TILE_COLS    Columns in the tile grid (default 2)
  GDINO_TILE_OVERLAP Overlap between adjacent tiles as a fraction (default 0.25)
  GDINO_NMS_IOU      IoU threshold for merging duplicate tile detections (default 0.5)
"""

import os
from pathlib import Path
from typing import Any

import cv2
import numpy as np
import torch

GDINO_CONFIG_PATH = os.environ.get(
    "GDINO_CONFIG_PATH",
    "/app/GroundingDINO/groundingdino/config/GroundingDINO_SwinT_OGC.py",
)
GDINO_CHECKPOINT_PATH = os.environ.get(
    "GDINO_CHECKPOINT_PATH",
    "/app/models/groundingdino_swint_ogc.pth",
)
GDINO_DEVICE = os.environ.get("GDINO_DEVICE", "cuda" if torch.cuda.is_available() else "cpu")

# ── resolution ──────────────────────────────────────────────────────────────
# Keep these at the training values (800 / 1333). The Swin Transformer backbone
# uses position biases calibrated to this scale — going significantly higher
# causes confidence scores to collapse to near-zero (0 detections).
# Small-object recall is improved by tiling below, not by increasing these.
GDINO_SHORT_SIDE = int(os.environ.get("GDINO_SHORT_SIDE", "800"))
GDINO_MAX_SIZE   = int(os.environ.get("GDINO_MAX_SIZE",   "1333"))

# ── tiling ───────────────────────────────────────────────────────────────────
GDINO_TILE_ROWS    = int(os.environ.get("GDINO_TILE_ROWS",    "2"))
GDINO_TILE_COLS    = int(os.environ.get("GDINO_TILE_COLS",    "2"))
GDINO_TILE_OVERLAP = float(os.environ.get("GDINO_TILE_OVERLAP", "0.25"))
GDINO_NMS_IOU      = float(os.environ.get("GDINO_NMS_IOU",      "0.5"))


# ── model loading ─────────────────────────────────────────────────────────────

def load_gdino_model() -> Any:
    """Load GroundingDINO weights into memory. Raises if anything is missing."""
    if not Path(GDINO_CONFIG_PATH).exists():
        raise FileNotFoundError(f"GroundingDINO config not found at {GDINO_CONFIG_PATH}")
    if not Path(GDINO_CHECKPOINT_PATH).exists():
        raise FileNotFoundError(f"GroundingDINO checkpoint not found at {GDINO_CHECKPOINT_PATH}")

    from groundingdino.models import build_model
    from groundingdino.util.slconfig import SLConfig
    from groundingdino.util.utils import clean_state_dict

    args = SLConfig.fromfile(GDINO_CONFIG_PATH)
    args.device = GDINO_DEVICE
    model = build_model(args)

    try:
        checkpoint = torch.load(GDINO_CHECKPOINT_PATH, map_location="cpu", weights_only=True)
    except Exception:
        # Older or non-standard checkpoints may embed non-tensor objects that
        # weights_only=True rejects. Fall back, but warn — only load files
        # from trusted sources when this path is taken.
        print(
            "[GDino] WARNING: checkpoint loaded with weights_only=False because "
            "weights_only=True failed. Ensure the checkpoint file is from a trusted source."
        )
        checkpoint = torch.load(GDINO_CHECKPOINT_PATH, map_location="cpu", weights_only=False)
    model.load_state_dict(clean_state_dict(checkpoint["model"]), strict=False)
    model = model.to(GDINO_DEVICE).eval()
    return model


# ── single-pass inference ─────────────────────────────────────────────────────

def run_gdino_inference(
    *,
    model: Any,
    bgr_image: np.ndarray,
    prompt: str,
    box_threshold: float,
    text_threshold: float,
) -> list[dict]:
    """Run GroundingDINO on a single BGR image.

    Returns detections with coordinates in the original (bgr_image) pixel space:
        [{"label": str, "confidence": float, "box": [x1, y1, x2, y2]}, ...]
    """
    import groundingdino.datasets.transforms as T
    from PIL import Image
    from groundingdino.util.utils import get_phrases_from_posmap

    h, w = bgr_image.shape[:2]
    pil_image = Image.fromarray(cv2.cvtColor(bgr_image, cv2.COLOR_BGR2RGB))

    transform = T.Compose([
        T.RandomResize([GDINO_SHORT_SIDE], max_size=GDINO_MAX_SIZE),
        T.ToTensor(),
        T.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
    ])
    image_tensor, _ = transform(pil_image, None)
    image_tensor = image_tensor.to(GDINO_DEVICE)

    caption = (prompt or "").strip().lower()
    if not caption.endswith("."):
        caption += "."

    with torch.no_grad():
        outputs = model(image_tensor[None], captions=[caption])

    logits = outputs["pred_logits"].sigmoid()[0]   # (nq, 256)
    boxes  = outputs["pred_boxes"][0]              # (nq, 4) cxcywh normalised

    mask   = logits.max(dim=1)[0] > box_threshold
    logits = logits[mask]
    boxes  = boxes[mask]

    tokenizer  = model.tokenizer
    tokenized  = tokenizer(caption)

    detections: list[dict] = []
    for logit, box in zip(logits, boxes):
        phrase = get_phrases_from_posmap(
            logit > text_threshold, tokenized, tokenizer
        ).strip()
        if not phrase:
            continue

        cx, cy, bw, bh = box.tolist()
        x1 = max(0, int((cx - bw / 2) * w))
        y1 = max(0, int((cy - bh / 2) * h))
        x2 = min(w, int((cx + bw / 2) * w))
        y2 = min(h, int((cy + bh / 2) * h))

        detections.append({
            "label":      phrase,
            "confidence": float(logit.max().item()),
            "box":        [x1, y1, x2, y2],
        })

    return detections


# ── tiled inference (public entry point) ──────────────────────────────────────

def run_gdino_inference_tiled(
    *,
    model: Any,
    bgr_image: np.ndarray,
    prompt: str,
    box_threshold: float,
    text_threshold: float,
) -> list[dict]:
    """Run GroundingDINO with tiled inference for maximum small-object recall.

    Strategy:
      1. Run on the full image — catches large objects and gives global context.
      2. Run on each overlapping tile — objects that were tiny in the full image
         are much larger relative to the tile, so the model finds them.
      3. Remap tile detections back to full-image coordinates.
      4. Merge all detections with label-aware NMS to remove duplicates from
         overlapping tile regions.
    """
    H, W = bgr_image.shape[:2]
    all_detections: list[dict] = []

    # Pass 1: full image
    full_dets = run_gdino_inference(
        model=model,
        bgr_image=bgr_image,
        prompt=prompt,
        box_threshold=box_threshold,
        text_threshold=text_threshold,
    )
    all_detections.extend(full_dets)
    print(f"[GDino] full-image pass: {len(full_dets)} detections")

    # Pass 2: tiled passes (skip if 1×1 — same as full image)
    rows, cols = GDINO_TILE_ROWS, GDINO_TILE_COLS
    if rows > 1 or cols > 1:
        # Stride = image dimension ÷ grid size (non-overlapping base)
        stride_x = W // cols
        stride_y = H // rows
        # Tile size adds the overlap margin on top of the stride
        tile_w = min(W, int(stride_x * (1 + GDINO_TILE_OVERLAP)))
        tile_h = min(H, int(stride_y * (1 + GDINO_TILE_OVERLAP)))

        tile_total = 0
        for row in range(rows):
            for col in range(cols):
                # Anchor at stride position; clamp so the tile never goes OOB
                ox = min(col * stride_x, W - tile_w)
                oy = min(row * stride_y, H - tile_h)
                tile = bgr_image[oy: oy + tile_h, ox: ox + tile_w]

                tile_dets = run_gdino_inference(
                    model=model,
                    bgr_image=tile,
                    prompt=prompt,
                    box_threshold=box_threshold,
                    text_threshold=text_threshold,
                )

                # Remap coordinates back to full-image space
                for det in tile_dets:
                    bx1, by1, bx2, by2 = det["box"]
                    det["box"] = [bx1 + ox, by1 + oy, bx2 + ox, by2 + oy]

                all_detections.extend(tile_dets)
                tile_total += len(tile_dets)

        print(f"[GDino] {rows}×{cols} tile pass: {tile_total} detections before NMS")

    # Merge duplicates from overlapping tiles
    merged = _nms(all_detections, iou_threshold=GDINO_NMS_IOU)
    print(f"[GDino] after NMS: {len(merged)} detections")
    return merged


# ── NMS helpers ───────────────────────────────────────────────────────────────

def _iou(a: list, b: list) -> float:
    """Intersection-over-Union for two [x1,y1,x2,y2] boxes."""
    ix1 = max(a[0], b[0])
    iy1 = max(a[1], b[1])
    ix2 = min(a[2], b[2])
    iy2 = min(a[3], b[3])
    inter = max(0, ix2 - ix1) * max(0, iy2 - iy1)
    if inter == 0:
        return 0.0
    area_a = (a[2] - a[0]) * (a[3] - a[1])
    area_b = (b[2] - b[0]) * (b[3] - b[1])
    return inter / (area_a + area_b - inter)


def _nms(detections: list[dict], iou_threshold: float) -> list[dict]:
    """Label-aware greedy NMS.

    Only suppresses boxes that share the same label string. Boxes for
    different labels are never compared — a "person" box can overlap a
    "wheelchair" box without either being dropped.
    """
    if not detections:
        return detections

    # Group by label
    by_label: dict[str, list[dict]] = {}
    for det in detections:
        by_label.setdefault(det["label"], []).append(det)

    kept: list[dict] = []
    for dets in by_label.values():
        # Greedy NMS: highest confidence first
        dets = sorted(dets, key=lambda d: d["confidence"], reverse=True)
        while dets:
            best = dets.pop(0)
            kept.append(best)
            dets = [d for d in dets if _iou(best["box"], d["box"]) < iou_threshold]

    return kept
