"""
Synchronous Frame-Locked Pipeline Engine

Processes frames through a DAG of model workers. Each frame is fully
processed before the next one starts. Dependency ordering is enforced.

The pipeline is defined as a DAG where each step has:
  - A name
  - A worker (BaseWorker instance)
  - Dependencies (list of step names whose outputs this step needs)
  - Input mapping (which outputs from dependencies to pass)
"""

import time
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Any, Optional
from dataclasses import dataclass, field

from manager.workers.base_worker import BaseWorker


@dataclass
class PipelineStep:
    """A single step in the pipeline DAG."""
    name: str
    worker: BaseWorker
    depends_on: list[str] = field(default_factory=list)
    input_keys: list[str] = field(default_factory=list)
    # input_keys: which keys from the shared context this step needs
    # If empty, the worker receives all available context


class Pipeline:
    """
    Synchronous frame-locked ML pipeline.

    Usage:
        pipeline = Pipeline()
        pipeline.add_step("pose", pose_worker, depends_on=[], input_keys=["frame"])
        pipeline.add_step("preprocess", preproc_worker, depends_on=["pose"], input_keys=["frame", "pose"])
        pipeline.add_step("yolo", yolo_worker, depends_on=[], input_keys=["frame"])  # parallel
        pipeline.add_step("custom_model_1", cm1_worker, depends_on=["preprocess"], input_keys=["frame", "pose", "preproc_1"])
        pipeline.add_step("custom_model_2", cm2_worker, depends_on=["preprocess"], input_keys=["frame", "pose", "preproc_1", "preproc_2", "preproc_3"])

        pipeline.load_all_models()

        results, timing = pipeline.process_frame(frame, frame_id=1)

        # On shutdown:
        pipeline.shutdown()
    """

    def __init__(self, max_workers: int = 4):
        self.steps: dict[str, PipelineStep] = {}
        self._execution_order: list[list[str]] = []  # Groups of steps that can run in parallel
        self._executor = ThreadPoolExecutor(max_workers=max_workers)
        self._context_lock = threading.Lock()  # Protects concurrent context updates
        self._shutdown = False

    def add_step(
        self,
        name: str,
        worker: BaseWorker,
        depends_on: list[str] = None,
        input_keys: list[str] = None,
    ):
        """
        Add a step to the pipeline.

        Args:
            name: Unique step name
            worker: BaseWorker instance
            depends_on: List of step names this step depends on
            input_keys: Which context keys to pass as input. If None, pass all.
        """
        step = PipelineStep(
            name=name,
            worker=worker,
            depends_on=depends_on or [],
            input_keys=input_keys or [],
        )
        self.steps[name] = step
        self._recompute_execution_order()

    def _recompute_execution_order(self):
        """
        Topological sort of the DAG, grouped into parallel levels.
        Steps with no unresolved dependencies can run in parallel.
        """
        remaining = set(self.steps.keys())
        resolved = set()
        order = []

        while remaining:
            # Find all steps whose dependencies are fully resolved
            ready = []
            for name in remaining:
                step = self.steps[name]
                if all(dep in resolved for dep in step.depends_on):
                    ready.append(name)

            if not ready:
                raise ValueError(
                    f"Pipeline has circular dependencies! Remaining: {remaining}"
                )

            order.append(ready)
            resolved.update(ready)
            remaining -= set(ready)

        self._execution_order = order

    def load_all_models(self):
        """Load all model workers."""
        print("Loading all pipeline models...")
        for name, step in self.steps.items():
            try:
                if not step.worker.is_loaded:
                    step.worker.load_model()
            except Exception as e:
                print(f"Failed to load model '{name}': {e}")
                raise
        print(f"All {len(self.steps)} models loaded")

    def unload_all_models(self):
        """Unload all model workers."""
        for name, step in self.steps.items():
            try:
                if step.worker.is_loaded:
                    step.worker.unload_model()
            except Exception as e:
                print(f"Error unloading model '{name}': {e}")
        print("All models unloaded")

    def shutdown(self):
        """Shutdown the pipeline and release resources."""
        if self._shutdown:
            return
        self._shutdown = True
        print("Shutting down pipeline executor...")
        self._executor.shutdown(wait=True)
        print("Pipeline executor shutdown complete")

    def __del__(self):
        """Destructor - ensure executor is shut down."""
        if not self._shutdown:
            self.shutdown()

    def process_frame(self, frame, frame_id: int) -> tuple[dict[str, Any], dict[str, float]]:
        """
        Process a single frame through the entire pipeline.
        Blocks until all steps are complete.

        Args:
            frame: numpy array (H, W, C)
            frame_id: unique frame identifier

        Returns:
            (results_dict, timing_dict)
            - results_dict: all outputs keyed by step name's output keys
            - timing_dict: processing time in ms for each step
        """
        if self._shutdown:
            raise RuntimeError("Pipeline has been shut down")

        # Shared context — all step outputs accumulate here
        context = {"frame": frame, "frame_id": frame_id}
        timing = {}

        # Execute level by level (each level runs in parallel)
        for level in self._execution_order:
            if len(level) == 1:
                # Single step — run directly (no thread overhead)
                name = level[0]
                step = self.steps[name]
                inputs = self._gather_inputs(step, context)
                try:
                    outputs, elapsed_ms = step.worker.run(inputs)
                    context.update(outputs)
                    timing[name] = elapsed_ms
                except Exception as e:
                    print(f"Error in step '{name}': {e}")
                    timing[name] = 0.0
                    raise
            else:
                # Multiple steps — run in parallel
                futures = {}
                for name in level:
                    step = self.steps[name]
                    inputs = self._gather_inputs(step, context)
                    future = self._executor.submit(step.worker.run, inputs)
                    futures[future] = name

                for future in as_completed(futures):
                    name = futures[future]
                    try:
                        outputs, elapsed_ms = future.result()
                        # Thread-safe context update
                        with self._context_lock:
                            context.update(outputs)
                        timing[name] = elapsed_ms
                    except Exception as e:
                        print(f"Error in parallel step '{name}': {e}")
                        timing[name] = 0.0
                        raise

        # Remove raw frame from results (too large to serialize)
        results = {k: v for k, v in context.items() if k not in ("frame", "frame_id")}

        return results, timing

    def _gather_inputs(self, step: PipelineStep, context: dict) -> dict:
        """Gather the required inputs for a step from the shared context."""
        if step.input_keys:
            return {k: context[k] for k in step.input_keys if k in context}
        return dict(context)

    def get_model_names(self) -> list[str]:
        """Get list of all model/step names."""
        return list(self.steps.keys())

    def get_execution_plan(self) -> list[list[str]]:
        """Get the execution order (for debugging/logging)."""
        return self._execution_order

    def __repr__(self):
        lines = ["Pipeline:"]
        for i, level in enumerate(self._execution_order):
            lines.append(f"  Level {i}: {', '.join(level)}")
        return "\n".join(lines)
