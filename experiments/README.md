# Mixed-integer fingerprint selection

`optimize_fingerprint.py` turns bounded coefficient selection into a 0--1
covering problem. For each candidate coordinate `j`, let `x_j` indicate whether
that coordinate is retained. For each mutation `u` and transform family `f`,
let `D[u,f,j]` be one exactly when mutation `u` changes coordinate `j` in
family `f`. The experiment solves

```text
minimize     sum_j x_j
subject to   sum_j D[u,f,j] x_j >= k    for every mutation u and family f
             x_j in {0,1}.
```

The default catalogue contains every unordered pair of distinct valid
operations at every position of a four-operation block with four qubits. Thus
it covers every possible **single-operation substitution** in that scope,
independently of the unchanged operations in the block.

## Reproduce

```text
python -m pip install -r requirements-experiments.txt
python experiments/optimize_fingerprint.py
```

With SciPy 1.17.1/HiGHS, the default run has:

- 40 valid `X`/`CX`/`CCX` operations;
- 3,120 substitution classes;
- 32 candidate coordinates;
- 6 selected coordinates; and
- zero uncovered constraints in a separate exact verification pass.

The selected coordinates in that run are:

```text
haar:arg1:1
haar:arg2:1
haar:arg3:1
walsh:arg1:3
walsh:arg2:3
walsh:arg3:3
```

The absence of `tag` is not an omission: within the present canonical
`X`/`CX`/`CCX` encoding, the operand channels and `-1` sentinels already
separate the operation constructors.

## Nearest-collision audit

Following the robustness-radius pattern used in
[`kemeny-dp-posets`](https://github.com/rbajaj5/kemeny-dp-posets), a second
MILP searches the operation-block Hamming graph for the closest distinct block
with the same retained coordinates. For the baseline

```text
[X(0), CX(0,1), CCX(0,1,2), X(3)]
```

the nearest collision is at distance 2:

```text
[X(0), CCX(0,3,2), CCX(0,1,2), CCX(3,1,2)]
```

The script verifies the collision from exact integer coefficients. This makes
the boundary sharp for that baseline: all single substitutions are detected,
but a two-substitution cancellation exists.

## Claim boundary

These are optima reported by the MILP solver for finite models and stated
objectives. The script rechecks feasibility and the exhibited collision using
exact integer transform values, but the optimization is not Lean-verified.
The radius is baseline-specific. The experiment therefore does not establish
semantic equivalence, universal injectivity, or cryptographic collision
resistance.
