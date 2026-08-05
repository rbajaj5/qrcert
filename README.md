# QRCert Lean decoder, fingerprints, and reflected certificates

This is a compiling Lean 4 proof artifact for three deliberately narrow QRCert
milestones:

1. a checked decoder and finite-word cost model for a tiny circuit format; and
2. exact integer Haar and Walsh--Hadamard transforms for structural circuit
   fingerprints; and
3. reflected resource and Ramsey certificates with an untrusted GPU search
   boundary.

The fixed-byte circuit format has:

- header: one byte each for `nQubits` and `numOps`;
- opcodes: `X`, `CX`, and `CCX` with one-byte operands;
- every operand is checked against `nQubits` while its opcode is parsed;
- `CX` operands and all three `CCX` operands must be distinct;
- the declared operation count must consume the payload exactly.

## Machine-checked decoder results

`QRCertBlueprint.lean` proves, without `sorry`, `admit`, project axioms, `unsafe`, or `partial` definitions:

- Boolean operation validation is equivalent to the mathematical `WellFormedOp` predicate.
- The implementation-style parser equals the specification parser.
- Successful parsing establishes bounds and register separation.
- Successful deserialization implies `WellFormed`.
- A successful decode consumes the input exactly.
- `encodeCircuit` is a section on well-formed `FixedByteEncodable` circuits.
- Every accepted byte string equals the canonical encoding of its result.
- Two byte strings accepted as the same circuit are equal.
- A checked finite-word cost model rejects overflow and agrees with the unbounded `Nat` gate count.
- This byte format's one-byte operation count makes exact finite-word costing succeed after every successful decode.
- Regression examples reject invalid opcodes, zero/out-of-bounds indices, aliased registers, and trailing bytes.

`ReflectionKernel.lean` turns that theorem chain into an explicit
Curry--Howard endpoint: if the Boolean resource-claim verifier accepts, Lean
recovers a canonical decoded circuit, well-formedness, exact unbounded cost,
and a successful agreeing finite-word cost computation.

## Machine-checked transform results

`QRCertWaveletFingerprint.lean` proves:

- the integer Haar butterfly is exactly invertible;
- a recursively indexed `Dyadic` trace has length `2^m` by construction;
- the full lazy Haar coefficient tree reconstructs its input exactly and is
  injective;
- changing one dyadic child leaves the opposite child's detail subtree
  bitwise unchanged;
- four canonical opcode channels (`tag`, `arg1`, `arg2`, `arg3`) determine an
  `X`/`CX`/`CCX` operation and every power-of-two operation block uniquely;
- the three operand channels alone remain injective because their `-1`
  sentinels distinguish gate arities, yielding a proved 25% channel reduction;
- the integer Walsh--Hadamard transform is injective; and
- its squared energy is multiplied by exactly `2^m` at depth `m`, the integral
  form of the normalized transform's isometry law.

These transforms are reversible structural representations. They are **not**
cryptographic hashes, compression functions, or collision-resistant sketches.
See [`FINGERPRINT-ROADMAP.md`](FINGERPRINT-ROADMAP.md) for the security boundary
and the status of proposed Reed--Muller, polar, and LDPC layers.

## Bounded coefficient optimization

The optional experiment in [`experiments/`](experiments/) formulates lossy
coordinate selection as a 0--1 mixed-integer covering problem. Its default
four-qubit/four-operation run selects 6 of 32 coordinates while detecting all
3,120 possible single-operation substitution classes in both the Haar and
Walsh families. A second optimization finds an exact two-substitution collision
for the documented baseline, sharply demonstrating why this remains a finite
threat-model result rather than a cryptographic or universal collision theorem.

## Untrusted GPU, trusted Lean

`RamseyCertificate.lean` is a proof-by-reflection case study. An external
program may search for a two-colour graph on a GPU, but the graph becomes a
proof only after the Lean checker accepts it. The checker has independent
`Prop` semantics and a proved-complete finite enumeration; its soundness does
not assume that Python, PyTorch, CUDA, or the GPU is correct.

The included five-cycle certificate is kernel-checked and proves the finite
property underlying `R(3,3) > 5`. The Python tool also independently checks
Exoo's known 42-vertex `R(5,5)` witness:

```text
python tools/ramsey_gpu.py --self-test --output c5.json
python tools/ramsey_gpu.py --check examples/r55-42.json
python tools/benchmark_ramsey.py
```

PyTorch is optional for certificate search and checking; the first two
commands have a deterministic standard-library CPU fallback. The benchmark
requires CUDA-enabled PyTorch and rejects any CPU/GPU score disagreement.
Clique-index tensors are compiled onto the selected device once and reused
across search batches; this optimization changes no certificate semantics and
remains outside the trusted base.
See `OPEN-MATH-APPLICATIONS.md` for measured results, precise trust boundaries,
and applications to Ramsey numbers, Hadamard matrices, bounded Collatz
verification, and the companion Kemeny-poset work.

[`tools/RAMSEY-CSP-INDEXING.md`](tools/RAMSEY-CSP-INDEXING.md) gives the
finite-Boolean-CSP semantics of the CUDA gather-and-reduce scorer. Its
incidence-table self-test is standard-library code; GPU scoring remains
untrusted acceleration and is still compared exactly with the CPU path.

## Build and audit

The pinned toolchain is Lean `4.31.0`, matching the current Aeneas Lean backend.
[`TOOLCHAIN-SNAPSHOT.md`](TOOLCHAIN-SNAPSHOT.md) records the audited Aeneas,
Charon, Charon-Rust, Lean, GPU, and alternative-verifier boundary. A newer
upstream tag is not silently treated as compatible.

```text
lake build
lake env lean -E warning QRCertAxiomAudit.lean
```

The original decoder blueprint was also compiled successfully with Lean
`4.33.0-rc1`. `#print axioms` reports only Lean's standard `propext`,
`Quot.sound`, and `Classical.choice` axioms
across the audited theorem set; there is no project-defined axiom. See
`AXIOM-AUDIT.md` for the exact result. The unchanged
`QRCertBlueprint.lean` SHA-256 is:

```text
FC43C4A278C6BAE25DEEDCAAF21CBE9B3C8C17F26F827A8E89B78D5B2CA51DDC
```

## Deliberate limitations

This is a proof blueprint, not the completed QRCert system:

- `U32Model` is a transparent, Nat-backed model of checked 32-bit addition. It is not claimed to be literal Aeneas output.
- [`rust/qrcert-core`](rust/qrcert-core/) is now an executable,
  extraction-oriented implementation of the Boolean parser and cost loop, but
  generated Lean and its refinement theorem are not yet committed. It must not
  be described as an already closed Rust/Charon/Aeneas bridge.
- Every operation costs one; the production frozen resource vector still needs gate-specific weights and versioning.
- The format uses one-byte headers and operands. A multi-byte/variable-length format needs its own minimal-encoding and canonicality proofs.
- The committed 42-vertex Ramsey JSON is exactly checked by Python and CUDA,
  but is not yet parsed and evaluated end to end by Lean; the kernel-checked
  concrete example is the five-cycle.
- The transform input is a power-of-two operation block, not an arbitrary
  decoded circuit; padding and domain separation remain design obligations.
- Exact reconstruction disappears if coefficients are truncated. Any lossy
  sketch needs a separate soundness statement and adversarial analysis.
- Fixed-width `X`, `CX`, and `CCX` gates are permutations of basis states and
  therefore unitary. A future register-allocation operation would instead be
  modeled as an isometry into a larger state space; neither semantic layer is
  implemented here.
- Circuit semantics, semantic certificates, authenticated hashing, completion
  of the Rust/Charon/Aeneas refinement bridge, rustc/RISC-V correspondence,
  SP1, and the ZK
  composition theorem remain separate obligations.
