# QRCert Lean checked-decoder and exact-fingerprint blueprint

This is a compiling Lean 4 proof artifact for two deliberately narrow QRCert
milestones:

1. a checked decoder and finite-word cost model for a tiny circuit format; and
2. exact integer Haar and Walsh--Hadamard transforms for structural circuit
   fingerprints.

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
- the integer Walsh--Hadamard transform is injective; and
- its squared energy is multiplied by exactly `2^m` at depth `m`, the integral
  form of the normalized transform's isometry law.

These transforms are reversible structural representations. They are **not**
cryptographic hashes, compression functions, or collision-resistant sketches.
See [`FINGERPRINT-ROADMAP.md`](FINGERPRINT-ROADMAP.md) for the security boundary
and the status of proposed Reed--Muller, polar, and LDPC layers.

## Build and audit

The pinned toolchain is Lean `4.31.0`, matching the reviewed hax/Aeneas integration pin.

```text
lake build
lake env lean -E warning QRCertAxiomAudit.lean
```

The original decoder blueprint was also compiled successfully with Lean
`4.33.0-rc1`. `#print axioms` reports only Lean's standard `propext`,
`Quot.sound`, and (for one fingerprint theorem) `Classical.choice` axioms
across the audited theorem set; there is no project-defined axiom. See
`AXIOM-AUDIT.md` for the exact result. The unchanged
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
- The transform input is a power-of-two operation block, not an arbitrary
  decoded circuit; padding and domain separation remain design obligations.
- Exact reconstruction disappears if coefficients are truncated. Any lossy
  sketch needs a separate soundness statement and adversarial analysis.
- Fixed-width `X`, `CX`, and `CCX` gates are permutations of basis states and
  therefore unitary. A future register-allocation operation would instead be
  modeled as an isometry into a larger state space; neither semantic layer is
  implemented here.
- Circuit semantics, semantic certificates, authenticated hashing, the
  Rust/Charon/Aeneas bridge, rustc/RISC-V correspondence, SP1, and the ZK
  composition theorem remain separate obligations.
