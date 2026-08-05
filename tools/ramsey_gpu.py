#!/usr/bin/env python3
"""Search for and check two-colour Ramsey lower-bound certificates.

The untrusted search may use a CUDA GPU, but the emitted witness is deliberately
small and deterministic.  ``RamseyCertificate.lean`` fixes the edge-list graph
semantics and proves its Boolean checker sound.  A verified parser for this
JSON envelope remains a separate trust-boundary obligation.

Canonical certificate format (``QRCert-Ramsey-v1``)
---------------------------------------------------

The certificate is exactly one UTF-8 JSON object followed by one LF byte::

  {"format":"QRCert-Ramsey-v1","n":5,"red_clique":3,"blue_clique":3,"red_edges":[[0,1],[0,4],[1,2],[2,3],[3,4]]}

The keys have the order shown above.  Vertices are ``0, ..., n-1``.  Every red
edge is ``[u,v]`` with ``u < v`` and the edge list is strictly lexicographically
sorted.  Edges not listed are blue.  No other fields or whitespace are allowed.
These rules make the byte representation unique and straightforward to convert
to ``List (Nat x Nat)`` in Lean.  Exact acceptance demonstrates the finite
colouring property behind ``R(r,b) > n`` when ``red_clique = r`` and
``blue_clique = b``; a formal theorem requires the Lean conversion and checker.

PyTorch is optional.  ``--device auto`` uses PyTorch CUDA when it is available;
otherwise the search uses a deterministic, standard-library CPU implementation.
GPU output is never trusted: ``--check`` also performs an independent exact
Python check, and the intended architecture is to check the same witness in
Lean before treating it as a proof.
"""

from __future__ import annotations

import argparse
import itertools
import json
import math
import random
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence


FORMAT = "QRCert-Ramsey-v1"
FORMAT_FIELDS = ("format", "n", "red_clique", "blue_clique", "red_edges")


class CertificateError(ValueError):
    """Raised when a certificate is malformed or non-canonical."""


@dataclass(frozen=True)
class Certificate:
    """A red graph; its complement is the blue graph."""

    n: int
    red_clique: int
    blue_clique: int
    red_edges: tuple[tuple[int, int], ...]

    def __post_init__(self) -> None:
        if type(self.n) is not int or self.n < 1:
            raise CertificateError("n must be a positive integer")
        if type(self.red_clique) is not int or self.red_clique < 2:
            raise CertificateError("red_clique must be an integer at least 2")
        if type(self.blue_clique) is not int or self.blue_clique < 2:
            raise CertificateError("blue_clique must be an integer at least 2")

        previous: tuple[int, int] | None = None
        for edge in self.red_edges:
            if not isinstance(edge, tuple) or len(edge) != 2:
                raise CertificateError("each red edge must contain two integers")
            u, v = edge
            if type(u) is not int or type(v) is not int:
                raise CertificateError("edge endpoints must be integers")
            if not (0 <= u < v < self.n):
                raise CertificateError(
                    f"red edge {edge!r} must satisfy 0 <= u < v < n"
                )
            if previous is not None and previous >= edge:
                raise CertificateError(
                    "red_edges must be strictly lexicographically sorted"
                )
            previous = edge

    @classmethod
    def from_object(cls, value: Any) -> "Certificate":
        if not isinstance(value, dict):
            raise CertificateError("certificate root must be a JSON object")
        if tuple(value.keys()) != FORMAT_FIELDS:
            raise CertificateError(
                "certificate fields must occur exactly in canonical order: "
                + ", ".join(FORMAT_FIELDS)
            )
        if value["format"] != FORMAT:
            raise CertificateError(f"unsupported format {value['format']!r}")
        raw_edges = value["red_edges"]
        if not isinstance(raw_edges, list):
            raise CertificateError("red_edges must be a JSON array")

        edges: list[tuple[int, int]] = []
        for edge in raw_edges:
            if not isinstance(edge, list) or len(edge) != 2:
                raise CertificateError("each red edge must be a two-element array")
            edges.append((edge[0], edge[1]))
        return cls(
            n=value["n"],
            red_clique=value["red_clique"],
            blue_clique=value["blue_clique"],
            red_edges=tuple(edges),
        )

    def canonical_text(self) -> str:
        value = {
            "format": FORMAT,
            "n": self.n,
            "red_clique": self.red_clique,
            "blue_clique": self.blue_clique,
            "red_edges": [list(edge) for edge in self.red_edges],
        }
        return json.dumps(value, ensure_ascii=True, separators=(",", ":")) + "\n"


@dataclass(frozen=True)
class Backend:
    name: str
    torch: Any | None = None
    device: Any | None = None


@dataclass(frozen=True)
class SearchResult:
    certificate: Certificate | None
    batches: int
    candidates: int
    best_score: int | None


@dataclass(frozen=True)
class CudaGatherPlan:
    """Read-only CUDA indices for one Ramsey scoring workload.

    The tuple structure prevents callers from adding, removing, or reordering
    chunks after construction.  PyTorch tensors are mutable objects, so the
    tensors remain an internal read-only convention; ``gpu_scores`` never
    modifies them.
    """

    n: int
    red_clique: int
    blue_clique: int
    clique_chunk: int
    edge_count: int
    device: str
    red_index_chunks: tuple[Any, ...]
    blue_index_chunks: tuple[Any, ...]


def all_edges(n: int) -> tuple[tuple[int, int], ...]:
    return tuple(itertools.combinations(range(n), 2))


def edge_index(n: int) -> dict[tuple[int, int], int]:
    return {edge: i for i, edge in enumerate(all_edges(n))}


def certificate_mask(certificate: Certificate) -> int:
    positions = edge_index(certificate.n)
    result = 0
    for edge in certificate.red_edges:
        result |= 1 << positions[edge]
    return result


def certificate_from_mask(
    n: int, red_clique: int, blue_clique: int, mask: int
) -> Certificate:
    edges = all_edges(n)
    red_edges = tuple(edge for i, edge in enumerate(edges) if (mask >> i) & 1)
    return Certificate(n, red_clique, blue_clique, red_edges)


def clique_masks(n: int, size: int) -> tuple[int, ...]:
    positions = edge_index(n)
    masks: list[int] = []
    for vertices in itertools.combinations(range(n), size):
        mask = 0
        for edge in itertools.combinations(vertices, 2):
            mask |= 1 << positions[edge]
        masks.append(mask)
    return tuple(masks)


def cpu_scores(
    candidates: Sequence[int], red_masks: Sequence[int], blue_masks: Sequence[int]
) -> list[int]:
    """Count forbidden monochromatic cliques with exact integer bitsets."""

    scores: list[int] = []
    for candidate in candidates:
        red_count = sum((candidate & mask) == mask for mask in red_masks)
        blue_count = sum((candidate & mask) == 0 for mask in blue_masks)
        scores.append(red_count + blue_count)
    return scores


def first_violation(
    certificate: Certificate,
) -> tuple[str, tuple[int, ...]] | None:
    """Return an exact witness to rejection, or ``None`` on acceptance."""

    red = set(certificate.red_edges)
    for vertices in itertools.combinations(range(certificate.n), certificate.red_clique):
        if all(edge in red for edge in itertools.combinations(vertices, 2)):
            return "red", vertices
    for vertices in itertools.combinations(range(certificate.n), certificate.blue_clique):
        if all(edge not in red for edge in itertools.combinations(vertices, 2)):
            return "blue", vertices
    return None


def select_backend(requested: str) -> Backend:
    if requested == "cpu":
        return Backend("cpu-python")

    try:
        import torch  # type: ignore[import-not-found]
    except (ImportError, OSError) as exc:
        if requested == "cuda":
            raise RuntimeError(f"PyTorch CUDA requested but PyTorch failed to load: {exc}")
        return Backend("cpu-python")

    if not torch.cuda.is_available():
        if requested == "cuda":
            raise RuntimeError("PyTorch CUDA requested but CUDA is not available")
        return Backend("cpu-python")

    # The operations below are deterministic for a fixed PyTorch/CUDA stack and
    # seed.  The independent CPU/Lean check remains the source of assurance.
    torch.use_deterministic_algorithms(True)
    return Backend(f"cuda:{torch.cuda.current_device()}", torch, torch.device("cuda"))


def report_backend(backend: Backend) -> None:
    if backend.torch is None:
        print("[ramsey_gpu] backend=cpu-python", file=sys.stderr)
    else:
        device_name = backend.torch.cuda.get_device_name(backend.device)
        print(
            f"[ramsey_gpu] backend={backend.name} "
            f"torch={backend.torch.__version__} device={device_name}",
            file=sys.stderr,
        )


def clique_edge_rows(n: int, size: int) -> list[list[int]]:
    positions = edge_index(n)
    return [
        [positions[edge] for edge in itertools.combinations(vertices, 2)]
        for vertices in itertools.combinations(range(n), size)
    ]


def clique_edge_chunks(
    n: int, size: int, clique_chunk: int
) -> tuple[tuple[tuple[int, ...], ...], ...]:
    """Return the immutable host-side chunk layout used by a CUDA plan."""

    if clique_chunk < 1:
        raise ValueError("clique_chunk must be positive")
    rows = clique_edge_rows(n, size)
    return tuple(
        tuple(tuple(row) for row in rows[start : start + clique_chunk])
        for start in range(0, len(rows), clique_chunk)
    )


def prepare_cuda_gather_plan(
    *,
    n: int,
    red_clique: int,
    blue_clique: int,
    backend: Backend,
    clique_chunk: int,
) -> CudaGatherPlan:
    """Materialize reusable clique-index tensors for one CUDA workload.

    Equal red and blue clique sizes share the exact same tuple of CUDA tensors,
    avoiding duplicate construction and device memory.  Plan construction is
    intentionally separate from scoring so a search or benchmark can exclude
    this one-time setup from every batch.
    """

    torch = backend.torch
    if torch is None:
        raise RuntimeError("prepare_cuda_gather_plan requires a CUDA backend")
    if n < 1:
        raise ValueError("n must be positive")
    if red_clique < 2 or blue_clique < 2:
        raise ValueError("clique sizes must be at least 2")
    if clique_chunk < 1:
        raise ValueError("clique_chunk must be positive")

    requested_device = torch.device(backend.device)
    if requested_device.type != "cuda":
        raise ValueError("CUDA gather plans require a CUDA device")
    device_index = requested_device.index
    if device_index is None:
        device_index = torch.cuda.current_device()
    canonical_device = str(torch.device("cuda", device_index))

    chunks_by_size: dict[int, tuple[Any, ...]] = {}
    for size in (red_clique, blue_clique):
        if size in chunks_by_size:
            continue
        host_chunks = clique_edge_chunks(n, size, clique_chunk)
        chunks_by_size[size] = tuple(
            torch.tensor(chunk, dtype=torch.int64, device=backend.device)
            for chunk in host_chunks
        )

    return CudaGatherPlan(
        n=n,
        red_clique=red_clique,
        blue_clique=blue_clique,
        clique_chunk=clique_chunk,
        edge_count=math.comb(n, 2),
        device=canonical_device,
        red_index_chunks=chunks_by_size[red_clique],
        blue_index_chunks=chunks_by_size[blue_clique],
    )


def _validate_cuda_gather_plan(
    plan: CudaGatherPlan,
    *,
    candidates: Any,
    n: int,
    red_clique: int,
    blue_clique: int,
    backend: Backend,
    clique_chunk: int,
) -> None:
    expected = (n, red_clique, blue_clique, clique_chunk)
    actual = (plan.n, plan.red_clique, plan.blue_clique, plan.clique_chunk)
    if actual != expected:
        raise ValueError(
            "CUDA gather plan does not match "
            f"(n, red_clique, blue_clique, clique_chunk)={expected}"
        )
    if candidates.ndim != 2 or candidates.shape[1] != plan.edge_count:
        raise ValueError(
            f"candidates must have shape [batch, {plan.edge_count}]"
        )
    torch = backend.torch
    if torch is None:
        raise RuntimeError("CUDA gather plan validation requires a CUDA backend")
    backend_device = torch.device(backend.device)
    backend_index = backend_device.index
    if backend_index is None:
        backend_index = torch.cuda.current_device()
    canonical_backend_device = str(torch.device("cuda", backend_index))
    if canonical_backend_device != plan.device or str(candidates.device) != plan.device:
        raise ValueError("CUDA gather plan, backend, and candidates must share a device")


def gpu_scores(
    candidates: Any,
    *,
    n: int,
    red_clique: int,
    blue_clique: int,
    backend: Backend,
    clique_chunk: int,
    plan: CudaGatherPlan | None = None,
) -> Any:
    """Count violations for a ``[batch, edge]`` CUDA boolean tensor.

    Passing a prepared ``plan`` avoids rebuilding clique rows and copying index
    tensors to CUDA on every call.  Omitting it preserves the original public
    behavior by constructing a one-shot plan.
    """

    torch = backend.torch
    if torch is None:
        raise RuntimeError("gpu_scores requires a CUDA backend")
    if plan is None:
        plan = prepare_cuda_gather_plan(
            n=n,
            red_clique=red_clique,
            blue_clique=blue_clique,
            backend=backend,
            clique_chunk=clique_chunk,
        )
    _validate_cuda_gather_plan(
        plan,
        candidates=candidates,
        n=n,
        red_clique=red_clique,
        blue_clique=blue_clique,
        backend=backend,
        clique_chunk=clique_chunk,
    )
    scores = torch.zeros(candidates.shape[0], dtype=torch.int32, device=backend.device)

    for index_chunks, colour_is_red in (
        (plan.red_index_chunks, True),
        (plan.blue_index_chunks, False),
    ):
        for index in index_chunks:
            selected = candidates[:, index]
            if not colour_is_red:
                selected = ~selected
            scores += selected.all(dim=2).sum(dim=1, dtype=torch.int32)
    return scores


def score_one_backend(
    certificate: Certificate, backend: Backend, clique_chunk: int
) -> int:
    mask = certificate_mask(certificate)
    if backend.torch is None:
        return cpu_scores(
            [mask],
            clique_masks(certificate.n, certificate.red_clique),
            clique_masks(certificate.n, certificate.blue_clique),
        )[0]

    torch = backend.torch
    bits = [bool((mask >> i) & 1) for i in range(math.comb(certificate.n, 2))]
    candidates = torch.tensor([bits], dtype=torch.bool, device=backend.device)
    return int(
        gpu_scores(
            candidates,
            n=certificate.n,
            red_clique=certificate.red_clique,
            blue_clique=certificate.blue_clique,
            backend=backend,
            clique_chunk=clique_chunk,
        )[0].item()
    )


def search_cpu(
    *,
    n: int,
    red_clique: int,
    blue_clique: int,
    seed: int,
    batch_size: int,
    batches: int,
) -> SearchResult:
    random_source = random.Random(seed)
    edge_count = math.comb(n, 2)
    red_masks = clique_masks(n, red_clique)
    blue_masks = clique_masks(n, blue_clique)
    best_score: int | None = None

    for batch_index in range(1, batches + 1):
        candidates = [random_source.getrandbits(edge_count) for _ in range(batch_size)]
        scores = cpu_scores(candidates, red_masks, blue_masks)
        minimum = min(scores)
        best_score = minimum if best_score is None else min(best_score, minimum)
        if minimum == 0:
            first = scores.index(0)
            certificate = certificate_from_mask(
                n, red_clique, blue_clique, candidates[first]
            )
            return SearchResult(certificate, batch_index, batch_index * batch_size, 0)
    return SearchResult(None, batches, batches * batch_size, best_score)


def search_cuda(
    *,
    n: int,
    red_clique: int,
    blue_clique: int,
    seed: int,
    batch_size: int,
    batches: int,
    backend: Backend,
    clique_chunk: int,
) -> SearchResult:
    torch = backend.torch
    if torch is None:
        raise RuntimeError("search_cuda requires a CUDA backend")
    plan = prepare_cuda_gather_plan(
        n=n,
        red_clique=red_clique,
        blue_clique=blue_clique,
        backend=backend,
        clique_chunk=clique_chunk,
    )
    generator = torch.Generator(device=backend.device)
    generator.manual_seed(seed)
    edge_count = math.comb(n, 2)
    best_score: int | None = None

    for batch_index in range(1, batches + 1):
        candidates = torch.randint(
            0,
            2,
            (batch_size, edge_count),
            dtype=torch.uint8,
            device=backend.device,
            generator=generator,
        ).to(torch.bool)
        scores = gpu_scores(
            candidates,
            n=n,
            red_clique=red_clique,
            blue_clique=blue_clique,
            backend=backend,
            clique_chunk=clique_chunk,
            plan=plan,
        )
        minimum = int(scores.min().item())
        best_score = minimum if best_score is None else min(best_score, minimum)
        zero_indices = torch.nonzero(scores == 0, as_tuple=False)
        if zero_indices.numel() != 0:
            first = int(zero_indices[0, 0].item())
            bits = candidates[first].to(device="cpu", dtype=torch.uint8).tolist()
            mask = sum(int(bit) << i for i, bit in enumerate(bits))
            certificate = certificate_from_mask(n, red_clique, blue_clique, mask)
            return SearchResult(certificate, batch_index, batch_index * batch_size, 0)
    return SearchResult(None, batches, batches * batch_size, best_score)


def search(
    *,
    n: int,
    red_clique: int,
    blue_clique: int,
    seed: int,
    batch_size: int,
    batches: int,
    backend: Backend,
    clique_chunk: int,
    max_cliques: int,
) -> SearchResult:
    if n < 1:
        raise ValueError("n must be positive")
    if red_clique < 2 or blue_clique < 2:
        raise ValueError("clique sizes must be at least 2")
    if batch_size < 1 or batches < 1 or clique_chunk < 1:
        raise ValueError("batch_size, batches, and clique_chunk must be positive")

    red_count = math.comb(n, red_clique) if red_clique <= n else 0
    blue_count = math.comb(n, blue_clique) if blue_clique <= n else 0
    if red_count + blue_count > max_cliques:
        raise ValueError(
            f"request has {red_count + blue_count} clique constraints, exceeding "
            f"--max-cliques={max_cliques}"
        )

    if backend.torch is None:
        return search_cpu(
            n=n,
            red_clique=red_clique,
            blue_clique=blue_clique,
            seed=seed,
            batch_size=batch_size,
            batches=batches,
        )
    return search_cuda(
        n=n,
        red_clique=red_clique,
        blue_clique=blue_clique,
        seed=seed,
        batch_size=batch_size,
        batches=batches,
        backend=backend,
        clique_chunk=clique_chunk,
    )


def parse_certificate(path: str) -> Certificate:
    if path == "-":
        raw = sys.stdin.buffer.read()
    else:
        raw = Path(path).read_bytes()
    try:
        text = raw.decode("utf-8", errors="strict")
    except UnicodeDecodeError as exc:
        raise CertificateError(f"certificate is not valid UTF-8: {exc}") from exc
    try:
        value = json.loads(text)
    except json.JSONDecodeError as exc:
        raise CertificateError(f"invalid JSON: {exc}") from exc
    certificate = Certificate.from_object(value)
    if text != certificate.canonical_text():
        raise CertificateError(
            "certificate bytes are not canonical (check whitespace and final LF)"
        )
    return certificate


def emit_certificate(certificate: Certificate, output: str) -> None:
    text = certificate.canonical_text()
    if output == "-":
        # Bypass Windows text newline translation: canonical output always ends
        # in one LF byte, including when stdout is redirected to a file.
        sys.stdout.buffer.write(text.encode("utf-8"))
        sys.stdout.buffer.flush()
        return
    with Path(output).open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)


def c5_certificate() -> Certificate:
    # The red graph is C5, and its blue complement is another C5.
    return Certificate(
        n=5,
        red_clique=3,
        blue_clique=3,
        red_edges=((0, 1), (0, 4), (1, 2), (2, 3), (3, 4)),
    )


def run_self_test(backend: Backend, clique_chunk: int) -> Certificate:
    certificate = c5_certificate()
    if first_violation(certificate) is not None:
        raise AssertionError("C5 unexpectedly has a monochromatic triangle")
    if score_one_backend(certificate, backend, clique_chunk) != 0:
        raise AssertionError("selected backend rejected the C5 certificate")

    reparsed = Certificate.from_object(json.loads(certificate.canonical_text()))
    if reparsed != certificate:
        raise AssertionError("canonical certificate round trip failed")

    # Sanity-check rejection too: all-red K3 contains a forbidden red triangle.
    invalid = Certificate(3, 3, 3, ((0, 1), (0, 2), (1, 2)))
    if first_violation(invalid) != ("red", (0, 1, 2)):
        raise AssertionError("exact checker failed to reject an all-red K3")

    print(
        "[ramsey_gpu] self-test=pass certificate=C5 conclusion=R(3,3)>5",
        file=sys.stderr,
    )
    return certificate


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="GPU-assisted search and exact checking for Ramsey certificates",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--self-test", action="store_true", help="check and emit C5")
    action.add_argument("--check", metavar="CERTIFICATE", help="check canonical JSON")
    action.add_argument("--search", metavar="N", type=int, help="search a colouring of K_N")
    parser.add_argument("--red-clique", type=int, default=3, help="forbidden red clique")
    parser.add_argument("--blue-clique", type=int, default=3, help="forbidden blue clique")
    parser.add_argument("--seed", type=int, default=0, help="search RNG seed")
    parser.add_argument("--batch-size", type=int, default=4096, help="candidates per batch")
    parser.add_argument("--batches", type=int, default=100, help="maximum search batches")
    parser.add_argument(
        "--clique-chunk", type=int, default=1024, help="GPU clique constraints per chunk"
    )
    parser.add_argument(
        "--max-cliques",
        type=int,
        default=2_000_000,
        help="refuse larger constraint enumerations",
    )
    parser.add_argument(
        "--device",
        choices=("auto", "cpu", "cuda"),
        default="auto",
        help="search backend",
    )
    parser.add_argument(
        "--output",
        metavar="PATH",
        default="-",
        help="certificate destination ('-' is stdout)",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        backend = select_backend(args.device)
        report_backend(backend)

        if args.self_test:
            emit_certificate(run_self_test(backend, args.clique_chunk), args.output)
            return 0

        if args.check is not None:
            certificate = parse_certificate(args.check)
            violation = first_violation(certificate)
            accelerated_score = score_one_backend(
                certificate, backend, args.clique_chunk
            )
            if (violation is None) != (accelerated_score == 0):
                raise RuntimeError("backend result disagrees with exact CPU checker")
            if violation is not None:
                colour, vertices = violation
                print(
                    f"[ramsey_gpu] invalid monochromatic={colour} "
                    f"vertices={','.join(map(str, vertices))}",
                    file=sys.stderr,
                )
                return 1
            print(
                f"[ramsey_gpu] valid conclusion=R({certificate.red_clique},"
                f"{certificate.blue_clique})>{certificate.n}",
                file=sys.stderr,
            )
            emit_certificate(certificate, args.output)
            return 0

        result = search(
            n=args.search,
            red_clique=args.red_clique,
            blue_clique=args.blue_clique,
            seed=args.seed,
            batch_size=args.batch_size,
            batches=args.batches,
            backend=backend,
            clique_chunk=args.clique_chunk,
            max_cliques=args.max_cliques,
        )
        if result.certificate is None:
            print(
                f"[ramsey_gpu] not-found batches={result.batches} "
                f"candidates={result.candidates} best_score={result.best_score}",
                file=sys.stderr,
            )
            return 1

        # Never emit a candidate without independently checking it.
        violation = first_violation(result.certificate)
        if violation is not None:
            raise RuntimeError(f"search backend emitted an invalid candidate: {violation}")
        print(
            f"[ramsey_gpu] found batches={result.batches} "
            f"candidates={result.candidates} conclusion=R({args.red_clique},"
            f"{args.blue_clique})>{args.search}",
            file=sys.stderr,
        )
        emit_certificate(result.certificate, args.output)
        return 0
    except (CertificateError, OSError, RuntimeError, ValueError) as exc:
        print(f"[ramsey_gpu] error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
