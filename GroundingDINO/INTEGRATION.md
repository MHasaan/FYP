# GroundingDINO Integration

This folder contains the upstream GroundingDINO source. It's integrated
into the FYP system as **Visual Search** — a standalone feature separate
from the live fall/seizure pipeline. Live cameras are untouched.

## Architecture (recap)

```
Frontend (Flutter)
  └─ "Visual Search" tab
       Upload image / video + text prompt → poll job → see results

Backend (FastAPI)
  └─ /api/grounding-dino/{detect/image|detect/video|jobs|jobs/{id}|jobs/{id}/output}
  └─ GroundingDinoJob row in DB
  └─ Publishes requests on Redis  'grounding_dino:requests'
  └─ GroundingDinoResultProcessor listens on 'grounding_dino:results'

ML Manager (separate daemon thread inside the same container)
  └─ GDinoService subscribes to 'grounding_dino:requests'
  └─ Runs inference, writes annotated output to /videos/gdino_outputs/
  └─ Publishes results on 'grounding_dino:results'
```

## Current state

✅ Backend: routes, model, schemas, result processor
✅ ML manager: GDinoService running in its own thread
✅ Frontend: "Visual Search" tab visible to admin + caregiver roles
✅ Stub inference: returns deterministic fake boxes per prompt phrase

The whole flow is **end-to-end testable today** with `GDINO_USE_STUB=1`
(the default in `docker-compose.yml`). The UI works, jobs queue, results
arrive, annotated outputs render.

## Enabling real GroundingDINO inference

The stub exists so the rest of the system is testable without taking on
the install pain below. To enable the real model:

### Checklist

- [ ] **Install the Python package.** Inside the `ml_manager` container:
      ```
      cd /app/GroundingDINO
      pip install -e .
      ```
      The custom CUDA op (`MultiScaleDeformableAttention`) compiles
      against the host's CUDA toolkit. The existing
      `nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04` image is a
      **runtime** image — it has `cuda` but not `nvcc`. Switch the base
      to `…-cudnn8-devel-ubuntu22.04` or install `cuda-toolkit-11-8` so
      the C++ extension can build.

- [ ] **Add the package + deps to requirements**. Put GroundingDINO's
      runtime deps into `ml_manager/requirements.txt`:
      ```
      transformers
      addict
      yapf
      supervision>=0.22.0
      pycocotools
      ```
      (PyTorch / torchvision / timm / opencv are already there.)

- [ ] **Download the checkpoint.** Roughly 700 MB. Either bake it into
      the image (`COPY` in the Dockerfile) or mount it:
      ```
      curl -L -o ml_manager/models/groundingdino_swint_ogc.pth \
        https://github.com/IDEA-Research/GroundingDINO/releases/download/v0.1.0-alpha/groundingdino_swint_ogc.pth
      ```

- [ ] **Confirm the config is reachable** at
      `/app/GroundingDINO/groundingdino/config/GroundingDINO_SwinT_OGC.py`.
      The docker-compose mount `./GroundingDINO:/app/GroundingDINO:ro`
      already covers this.

- [ ] **Flip the env var.** In `.env`:
      ```
      GDINO_USE_STUB=0
      ```
      Restart the `ml_manager` service.

- [ ] **Smoke test.** Submit a Visual Search job with prompt
      `"person ."` against a photo of a person. The annotated output
      should box the person; the detections list should contain a
      `person` entry with confidence > 0.4.

### Fallback behavior

If any of the above steps is missing at runtime, `GDinoService` catches
the import / load failure once, logs it, and falls back to the stub for
all subsequent requests. You'll see fake boxes in the UI — that's the
signal something is off in the install. Check the ml_manager logs for
`[GDinoService] GroundingDINO load failed: …`.

### Important: do not touch the live pipeline

GDinoService runs as a **separate thread** alongside `PipelineManager`.
It never opens a camera, never publishes to `pipeline:*` channels, and
never participates in the pose / fall_detection DAG. Even if its model
load fails or it crashes, the live pipeline keeps running.
