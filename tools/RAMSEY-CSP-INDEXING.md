# Ramsey scoring as a finite Boolean CSP

This note specifies the tensor-indexing layer in `ramsey_gpu.py`. The layer
accelerates search and scoring; it is not part of the mathematical trust
boundary. A colouring becomes a Ramsey certificate only after the independent
exact checker, and ultimately the Lean reflection kernel, accepts it.

## 1. Variables and constraints

Fix a complete graph on `n` vertices. Its

```text
E = binom(n, 2)
```

unordered edges are listed lexicographically. A candidate colouring is a
Boolean vector `x : {0, ..., E - 1} -> {false, true}`, with `true` meaning red
and `false` meaning blue.

For every `red_clique`-element vertex set, the forbidden red relation is

```text
not (all incident clique edges are true).
```

For every `blue_clique`-element vertex set, the forbidden blue relation is

```text
not (all incident clique edges are false).
```

Thus the search instance is a finite Boolean CSP. Every potential clique is a
constraint scope, and the score is exactly the number of violated constraints.
A score of zero is equivalent to satisfaction of the whole CSP.

The CSP vocabulary follows the general scope/relation organization in
[*Notes on CSPs and Polymorphisms*](https://notzeb.com/csp-notes.pdf). No
polymorphism classification or tractability theorem from those notes is used
to prove a Ramsey result here.

## 2. Canonical edge numbering

`all_edges(n)` enumerates

```text
(0,1), (0,2), ..., (0,n-1), (1,2), ..., (n-2,n-1).
```

`edge_index(n)` is the inverse dictionary. For each `k`-vertex set,
`clique_edge_rows(n, k)` records the `binom(k, 2)` edge positions in that
clique. It therefore has shape

```text
[binom(n, k), binom(k, 2)].
```

The standard-library self-test reconstructs every corresponding integer
bitmask from these rows and requires exact equality with `clique_masks`.
This catches ordering, omission, duplication, and scope-size errors without
requiring PyTorch or CUDA.

## 3. Gather and reduce

For a CUDA Boolean tensor

```text
candidates : [batch, E]
index      : [chunk, binom(k, 2)]
```

PyTorch advanced indexing evaluates

```python
selected = candidates[:, index]
```

with result shape

```text
[batch, chunk, binom(k, 2)].
```

For the red pass, `selected.all(dim=2)` is true exactly for violated red
constraints. For the blue pass the code first complements `selected`, so the
same reduction is true exactly for violated blue constraints. Summing over the
chunk yields the violation count for each candidate.

This is the tensor form of the CPU bit tests

```python
(candidate & mask) == mask  # red violation
(candidate & mask) == 0     # blue violation
```

and the benchmark requires the two complete score vectors to agree bit for
bit.

## 4. Memory and trust boundary

The dominant temporary contains approximately

```text
batch * clique_chunk * binom(k, 2)
```

Boolean entries. `clique_chunk` bounds this allocation. The gather is normally
memory-bound; changing its layout or replacing it with bit packing is an
optimization question, not a proof step.

The current scorer compiles the clique rows into device-resident index tensors
once per search and reuses that `GpuScorePlan` for every candidate batch. This
removes repeated Python conversion and host-to-device index uploads from the
hot loop. Benchmark format `QRCert-Ramsey-Benchmark-v2` records
`device_plan_precompiled=true`; older v1 receipts included plan construction
in each timed call, so their timings are not directly comparable.

The assurance chain is deliberately asymmetric:

```text
untrusted CUDA search
    -> canonical finite colouring
    -> exact standard-library checker
    -> independent Lean Boolean checker
    -> proved Prop-level Ramsey statement.
```

Neither the tensor layout nor deterministic CUDA execution is trusted for the
final theorem. They need only produce a candidate that the smaller checkers can
reject or accept independently.
