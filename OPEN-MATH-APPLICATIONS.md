# Proof-producing GPU applications

This repository uses GPUs only outside the trusted proof boundary. A GPU may
search for a witness or score many candidates in parallel, but a small Lean
checker must accept the resulting finite certificate before the associated
proposition is treated as proved. Failure to find a certificate proves
nothing.

## Implemented case study: Ramsey lower bounds

`RamseyCertificate.lean` proves that Boolean checker acceptance implies that a
well-formed two-colouring contains no monochromatic clique of the requested
size. The proof does not assume that the certificate producer, Python,
PyTorch, CUDA, or the GPU is correct. The five-cycle example is evaluated by
Lean's kernel and yields the finite statement underlying `R(3,3) > 5`.

`tools/ramsey_gpu.py` is an untrusted producer and independent exact Python
checker. It emits a canonical JSON edge list. Its CUDA and pure-Python scoring
paths are required to agree before a checked certificate is emitted.

The repository also contains `examples/r55-42.json`, a canonical conversion
of Geoffrey Exoo's published 42-vertex colouring. Both tool backends accept
it, independently rechecking the known lower bound `R(5,5) >= 43`. The exact
value remains open: the current published range is

```text
43 <= R(5,5) <= 46.
```

Sources:

- [Radziszowski, *Small Ramsey Numbers*, dynamic survey (April 2026)](https://doi.org/10.37236/21)
- [Exoo's published adjacency matrix for the 42-vertex witness](https://cs.indstate.edu/ge/RAMSEY/g55.42)
- [Angeltveit and McKay, `R(5,5) <= 46`](https://doi.org/10.1002/jgt.70029)

The 42-vertex JSON file is presently checked by the exact Python and CUDA
implementations, while Lean kernel-checks the smaller C5 instance and proves
the general checker-soundness theorem. A verified JSON parser and a more
scalable Lean combination enumerator are still required before claiming that
the committed 42-vertex file itself has been checked end to end by Lean.

## What the GPU improved

On 3 August 2026, an RTX 5070 Ti Laptop GPU using PyTorch 2.11.0 with CUDA 12.8
scored the same deterministic batch as the exact integer CPU implementation:

| Workload | CPU | GPU | Speedup | Agreement |
|---|---:|---:|---:|---:|
| 512 colourings of `K_20`, two sets of 15,504 `K_5` constraints | 0.876 s | 0.0466 s | 18.8x | exact |

The table reports the median of five measured repetitions after two warm-ups.
It measures the scoring kernel after candidate tensors have been prepared;
it excludes process startup and host-to-device conversion. For a single
42-vertex certificate, the complete GPU command was slower (9.41 s versus
2.76 s) because CUDA startup and the mandatory independent CPU recheck
dominated. The result is therefore specific and useful: GPU acceleration helps
batched search, not the final small trusted verification step.

These are one-machine engineering measurements, not mathematical claims or a
general performance guarantee. `tools/benchmark_ramsey.py` reproduces the
batch comparison and rejects any CPU/GPU score mismatch.

## Other open-problem targets

### Hadamard order 668

The Hadamard conjecture asks for a `+1/-1` Hadamard matrix at every positive
order divisible by four; 668 remains the smallest unresolved order in the
current construction tables. A GPU can search structured matrix families,
while Lean can check exact entries and the identity `H * H.transpose = 668 I`.
Acceptance of one exact matrix would settle existence at order 668. Failure in
one search family would not prove nonexistence.

- [Đoković and Kotsireas, current Hadamard construction tables](https://arxiv.org/abs/2411.18897)

### Bounded Collatz verification

Collatz trajectory blocks are massively parallel and existing GPU work reports
large acceleration. A proof-producing version would need exact coverage of
every residue block, checked transitions, overflow exclusion, and descent into
an already verified prefix. Its conclusion would remain bounded,
`forall n < N, CollatzReachesOne n`, rather than the global conjecture.

- [Barina, peer-reviewed verification below `2^71`](https://doi.org/10.1007/s11227-025-07337-0)

### Kemeny stability certificates

The companion [`kemeny-dp-posets`](https://github.com/rbajaj5/kemeny-dp-posets)
repository is a better reproducible GPU systems benchmark than open-ended
Ramsey search. Its distance-stratified subset dynamic program has regular
integer states. A proof-carrying version would emit the complete Bellman table,
predecessors, the claimed optimum, distance-layer minima, and destabilizing
ranking. Lean would check every recurrence before proving the exact Kemeny
optimum and uniqueness radius.

This does **not** by itself establish differential privacy. The dynamic
program, the DP privacy definition, ZK witness hiding, and information leaked
by public optimum/gap/radius values are separate concerns.

## CSP and polymorphism guidance

Zarathustra Brady's
[*Notes on CSPs and Polymorphisms*](https://doi.org/10.48550/arXiv.2210.07383)
suggest a useful producer-side dispatch rather than a new trust assumption.
The notes separate CSP templates amenable to local consistency, linear or
semidefinite relaxations, and compact representations from templates that
retain hard search behavior.

A symmetric Ramsey lower-bound instance is itself a Boolean CSP: one variable
chooses the colour of each edge, and each `k`-vertex set contributes a
constraint excluding the all-red and all-blue assignments. This perspective
can guide future search engines:

- bounded-width templates can emit a local-consistency elimination trace;
- affine fragments can emit exact linear-algebra certificates;
- few-subpowers fragments can use compact relation representations; and
- hard residual instances can still use SAT, branch-and-bound, or GPU batch
  search.

The Lean boundary does not change. A satisfying assignment is easy to check,
but an LP/SDP fractional solution or an approximately satisfied CSP is not an
exact Ramsey certificate. An upper bound or unsatisfiability claim needs a
complete checked refutation or exhaustive-coverage certificate. The notes'
"Ramsey-theoretic upgrade" concerns solvability inside bounded-width algebraic
templates; it does not improve the numerical bound on `R(5,5)` by itself.

The inspected 2 August 2026 PDF is a 583-page evolving set of seminar notes and
explicitly describes itself as unfinished, so the repository uses it as
algorithmic guidance rather than a frozen protocol dependency:

- [current PDF supplied for this assessment](https://notzeb.com/csp-notes.pdf)

## Boundary

This case study demonstrates Curry--Howard plus proof by reflection:

```text
untrusted GPU search -> finite certificate -> proved Lean checker -> proposition
```

It does not make CUDA part of Lean's trusted computing base, turn numerical
simulation into proof, or convert unsuccessful search into a theorem.
