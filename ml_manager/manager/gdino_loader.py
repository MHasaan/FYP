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


def load_gdino_model() -> Any:
    """Load GroundingDINO weights into memory. Raises if anything is missing."""
    if not Path(GDINO_CONFIG_PATH).exists():
        raise FileNotFoundError(f"GroundingDINO config not found at {GDINO_CONFIG_PATH}")
    if not Path(GDINO_CHECKPOINT_PATH).exists():
        raise FileNotFoundError(f"GroundingDINO checkpoint not found at {GDINO_CHECKPOINT_PATH}")

    # Local imports — these will only succeed once the groundingdino
    # package is installed in the container.
    from groundingdino.models import build_model
    from groundingdino.util.slconfig import SLConfig
    from groundingdino.util.utils import clean_state_dict

    args = SLConfig.fromfile(GDINO_CONFIG_PATH)
    args.device = GDINO_DEVICE
    model = build_model(args)

    checkpoint = torch.load(GDINO_CHECKPOINT_PATH, map_location="cpu")
    model.load_state_dict(clean_state_dict(checkpoint["model"]), strict=False)
    model = model.to(GDINO_DEVICE).eval()
    return model


def run_gdino_inference(
    *,
    model: Any,
    bgr_image: np.ndarray,
    prompt: str,
    box_threshold: float,
    text_threshold: float,
) -> list[dict]:
    """Run GroundingDINO on a single BGR frame and return a list of
    detections in the same shape GDinoService expects:

        [{"label": str, "confidence": float, "box": [x1, y1, x2, y2]}, ...]

    Coordinates are absolute pixels in the original image space.
    """
    import groundingdino.datasets.transforms as T
    from PIL import Image
    from groundingdino.util.utils import get_phrases_from_posmap

    h, w = bgr_image.shape[:2]
    pil_image = Image.fromarray(cv2.cvtColor(bgr_image, cv2.COLOR_BGR2RGB))

    transform = T.Compose([
        T.RandomResize([800], max_size=1333),
        T.ToTensor(),
        T.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
    ])
    image_tensor, _ = transform(pil_image, None)
    image_tensor = image_tensor.to(GDINO_DEVICE)

    caption = (prompt or "").strip().lower()
    if not caption.endswith("."):
        caption = caption + "."

    with torch.no_grad():
        outputs = model(image_tensor[None], captions=[caption])

    logits = outputs["pred_logits"].sigmoid()[0]   # (nq, 256)
    boxes = outputs["pred_boxes"][0]               # (nq, 4) in cxcywh, [0,1]

    # Filter by box threshold
    mask = logits.max(dim=1)[0] > box_threshold
    logits = logits[mask]
    boxes = boxes[mask]

    tokenizer = model.tokenizer
    tokenized = tokenizer(caption)

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
            "label": phrase,
            "confidence": float(logit.max().item()),
            "box": [x1, y1, x2, y2],
        })

    return detections
