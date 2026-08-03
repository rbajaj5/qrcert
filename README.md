# QRCert Lean checked-decoder blueprint

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

## Build and audit

The pinned toolchain is Lean `4.31.0`, matching the reviewed hax/Aeneas integration pin.

```text
lake build
lake env lean -E warning QRCertAxiomAudit.lean
```

The blueprint was also compiled successfully with Lean `4.33.0-rc1`. `#print axioms` reports only Lean's standard `propext` and `Quot.sound` axioms across the audited theorem set; there is no project-defined axiom. See `AXIOM-AUDIT.md` for the exact result. The final `QRCertBlueprint.lean` SHA-256 is:

```text
FC43C4A278C6BAE25DEEDCAAF21CBE9B3C8C17F26F827A8E89B78D5B2CA51DDC
```

## Deliberate limitations

This is a proof blueprint, not the completed QRCert system:

- `U32Model` is a transparent, Nat-backed model of checked 32-bit addition. It is not claimed to be literal Aeneas output.
- The Boolean parser is implementation-shaped Lean, not yet extracted Rust.
- Every operation costs one; the production frozen resource vector still needs gate-specific weights and versioning.
- The format uses one-byte headers and operands. A multi-byte/variable-length format needs its own minimal-encoding and canonicality proofs.
- Circuit permutation/unitary semantics, semantic certificates, hashing, the Rust/Charon/Aeneas bridge, rustc/RISC-V correspondence, SP1, and the ZK composition theorem remain separate obligations.
