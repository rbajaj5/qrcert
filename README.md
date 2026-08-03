# QRCert Lean blueprint and reflected certificates

This is a compiling Lean 4 proof artifact for the first QRCert parser/cost milestone. It uses a deliberately tiny fixed-byte circuit format:

- header: one byte each for `nQubits` and `numOps`;
- opcodes: `X`, `CX`, and `CCX` with one-byte operands;
- every operand is checked against `nQubits` while its opcode is parsed;
- `CX` operands and all three `CCX` operands must be distinct;
- the declared operation count must consume the payload exactly.

## Machine-checked results

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
See `OPEN-MATH-APPLICATIONS.md` for measured results, precise trust boundaries,
and applications to Ramsey numbers, Hadamard matrices, bounded Collatz
verification, and the companion Kemeny-poset work.

## Build and audit

The pinned toolchain is Lean `4.31.0`, matching the reviewed hax/Aeneas integration pin.

```text
lake build
lake env lean -E warning QRCertAxiomAudit.lean
```

The original blueprint was also compiled successfully with Lean `4.33.0-rc1`.
`#print axioms` reports only Lean's standard `propext`, `Quot.sound`, and
`Classical.choice` axioms across the expanded audited theorem set; there is no
project-defined axiom. See `AXIOM-AUDIT.md` for the exact result. The unchanged
`QRCertBlueprint.lean` SHA-256 is:

```text
FC43C4A278C6BAE25DEEDCAAF21CBE9B3C8C17F26F827A8E89B78D5B2CA51DDC
```

## Deliberate limitations

This is a proof blueprint, not the completed QRCert system:

- `U32Model` is a transparent, Nat-backed model of checked 32-bit addition. It is not claimed to be literal Aeneas output.
- The Boolean parser is implementation-shaped Lean, not yet extracted Rust.
- Every operation costs one; the production frozen resource vector still needs gate-specific weights and versioning.
- The format uses one-byte headers and operands. A multi-byte/variable-length format needs its own minimal-encoding and canonicality proofs.
- The committed 42-vertex Ramsey JSON is exactly checked by Python and CUDA,
  but is not yet parsed and evaluated end to end by Lean; the kernel-checked
  concrete example is the five-cycle.
- Circuit permutation/unitary semantics, semantic certificates, hashing, the Rust/Charon/Aeneas bridge, rustc/RISC-V correspondence, SP1, and the ZK composition theorem remain separate obligations.
