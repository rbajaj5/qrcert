#!/usr/bin/env python3
"""Reproducibly compare QRCert's exact CPU and CUDA Ramsey scorers.

The benchmark generates one deterministic batch of colourings, represents that
same batch as Python integer bitsets and as a CUDA boolean tensor, then compares
``cpu_scores`` with ``gpu_scores`` exactly.  CUDA is warmed up and synchronized
around every timed call.  A disagreement is an error, never a benchmark result.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import statistics
import sys
import time
from dataclasses import dataclass
from typing import Any, Callable, Sequence, TypeVar

try:
    from .ramsey_gpu import (
        Backend,
        clique_masks,
        compile_gpu_score_plan,
        cpu_scores,
        gpu_scores,
    )
except ImportError:
    # Support direct execution: ``python tools/benchmark_ramsey.py``.
    from ramsey_gpu import (
        Backend,
        clique_masks,
        compile_gpu_score_plan,
        cpu_scores,
        gpu_scores,
    )


FORMAT = "QRCert-Ramsey-Benchmark-v2"
T = TypeVar("T")


@dataclass(frozen=True)
class TimedResult:
    seconds: float
    value: Any


def deterministic_candidates(n: int, batch: int, seed: int) -> list[int]:
    """Generate a stable candidate batch from a dedicated seeded RNG."""

    edge_count = math.comb(n, 2)
    source = random.Random(seed)
    return [source.getrandbits(edge_count) for _ in range(batch)]


def candidate_digest(candidates: Sequence[int], edge_count: int) -> str:
    """Hash the fixed-width little-endian candidate representation."""

    width = max(1, (edge_count + 7) // 8)
    digest = hashlib.sha256()
    for candidate in candidates:
        digest.update(candidate.to_bytes(width, byteorder="little", signed=False))
    return digest.hexdigest()


def candidates_to_cuda(candidates: Sequence[int], edge_count: int, torch: Any, device: Any) -> Any:
    rows = [
        [bool((candidate >> edge) & 1) for edge in range(edge_count)]
        for candidate in candidates
    ]
    return torch.tensor(rows, dtype=torch.bool, device=device)


def time_cpu(call: Callable[[], T]) -> TimedResult:
    start = time.perf_counter()
    value = call()
    return TimedResult(time.perf_counter() - start, value)


def time_cuda(call: Callable[[], T], torch: Any, device: Any) -> TimedResult:
    torch.cuda.synchronize(device)
    start = time.perf_counter()
    value = call()
    torch.cuda.synchronize(device)
    return TimedResult(time.perf_counter() - start, value)


def rounded(values: Sequence[float]) -> list[float]:
    return [round(value, 9) for value in values]


def benchmark(args: argparse.Namespace) -> dict[str, Any]:
    if args.n < 1:
        raise ValueError("--n must be positive")
    if not 2 <= args.k <= args.n:
        raise ValueError("--k must satisfy 2 <= k <= n")
    if args.batch < 1:
        raise ValueError("--batch must be positive")
    if args.repeats < 1:
        raise ValueError("--repeats must be positive")
    if args.warmups < 1:
        raise ValueError("--warmups must be positive")
    if args.clique_chunk < 1:
        raise ValueError("--clique-chunk must be positive")

    try:
        import torch  # type: ignore[import-not-found]
    except (ImportError, OSError) as exc:
        raise RuntimeError(f"PyTorch failed to load: {exc}") from exc
    if not torch.cuda.is_available():
        raise RuntimeError("CUDA is not available to PyTorch")
    if not 0 <= args.device < torch.cuda.device_count():
        raise ValueError(
            f"--device must be between 0 and {torch.cuda.device_count() - 1}"
        )

    torch.cuda.set_device(args.device)
    torch.use_deterministic_algorithms(True)
    device = torch.device(f"cuda:{args.device}")
    backend = Backend(f"cuda:{args.device}", torch, device)

    constraints_per_colour = math.comb(args.n, args.k)
    constraints_total = 2 * constraints_per_colour
    if constraints_total > args.max_constraints:
        raise ValueError(
            f"benchmark has {constraints_total} constraints, exceeding "
            f"--max-constraints={args.max_constraints}"
        )

    edge_count = math.comb(args.n, 2)
    candidates = deterministic_candidates(args.n, args.batch, args.seed)
    digest = candidate_digest(candidates, edge_count)
    red_masks = clique_masks(args.n, args.k)
    # The diagonal case uses the same clique masks for both colours.
    gpu_candidates = candidates_to_cuda(candidates, edge_count, torch, device)
    gpu_plan = compile_gpu_score_plan(
        n=args.n,
        red_clique=args.k,
        blue_clique=args.k,
        backend=backend,
        clique_chunk=args.clique_chunk,
    )

    # Check that tensor construction did not change a single candidate bit.
    tensor_rows = gpu_candidates.to(device="cpu", dtype=torch.uint8).tolist()
    tensor_masks = [
        sum(int(bit) << edge for edge, bit in enumerate(row)) for row in tensor_rows
    ]
    if tensor_masks != candidates:
        raise RuntimeError("CPU and CUDA candidate representations differ")

    def cpu_call() -> list[int]:
        return cpu_scores(candidates, red_masks, red_masks)

    def cuda_call() -> Any:
        return gpu_scores(
            gpu_candidates,
            n=args.n,
            red_clique=args.k,
            blue_clique=args.k,
            backend=backend,
            clique_chunk=args.clique_chunk,
            plan=gpu_plan,
        )

    # Warm both paths so imports, CUDA context creation, and allocator startup do
    # not contaminate the reported measurements. CUDA synchronization makes the
    # asynchronous kernel work finish before timing begins.
    expected = cpu_call()
    for _ in range(args.warmups):
        warmed = cuda_call()
        torch.cuda.synchronize(device)
        if warmed.to(device="cpu").tolist() != expected:
            raise RuntimeError("CPU/CUDA score mismatch during warm-up")

    cpu_times: list[float] = []
    cuda_times: list[float] = []
    for _ in range(args.repeats):
        cpu_result = time_cpu(cpu_call)
        cuda_result = time_cuda(cuda_call, torch, device)
        cuda_values = cuda_result.value.to(device="cpu").tolist()
        if cpu_result.value != expected or cuda_values != expected:
            raise RuntimeError("CPU/CUDA score mismatch during measured run")
        cpu_times.append(cpu_result.seconds)
        cuda_times.append(cuda_result.seconds)

    cpu_median = statistics.median(cpu_times)
    cuda_median = statistics.median(cuda_times)
    speedup = cpu_median / cuda_median

    return {
        "format": FORMAT,
        "n": args.n,
        "k": args.k,
        "batch": args.batch,
        "constraints": {
            "per_colour": constraints_per_colour,
            "total": constraints_total,
        },
        "edges": edge_count,
        "seed": args.seed,
        "candidate_sha256": digest,
        "repeats": args.repeats,
        "warmups": args.warmups,
        "clique_chunk": args.clique_chunk,
        "device_plan_precompiled": True,
        "torch": str(torch.__version__),
        "cuda": str(torch.version.cuda),
        "device": torch.cuda.get_device_name(device),
        "times": {
            "cpu_seconds": rounded(cpu_times),
            "cuda_seconds": rounded(cuda_times),
            "cpu_median_seconds": round(cpu_median, 9),
            "cuda_median_seconds": round(cuda_median, 9),
        },
        "speedup": round(speedup, 6),
        "agreement": True,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Compare identical Ramsey batches on exact Python and CUDA scorers",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--n", type=int, default=20, help="number of vertices")
    parser.add_argument("--k", type=int, default=5, help="forbidden clique size")
    parser.add_argument("--batch", type=int, default=512, help="candidate colourings")
    parser.add_argument("--seed", type=int, default=0, help="candidate RNG seed")
    parser.add_argument("--repeats", type=int, default=3, help="measured repetitions")
    parser.add_argument("--warmups", type=int, default=2, help="unmeasured CUDA warm-ups")
    parser.add_argument(
        "--clique-chunk", type=int, default=1024, help="CUDA constraints per chunk"
    )
    parser.add_argument("--device", type=int, default=0, help="CUDA device index")
    parser.add_argument(
        "--max-constraints",
        type=int,
        default=2_000_000,
        help="refuse larger enumerations",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        result = benchmark(args)
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"[benchmark_ramsey] error: {exc}", file=sys.stderr)
        return 2
    output = json.dumps(result, ensure_ascii=True, separators=(",", ":")) + "\n"
    sys.stdout.buffer.write(output.encode("utf-8"))
    sys.stdout.buffer.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
