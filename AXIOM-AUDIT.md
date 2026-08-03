# QRCert blueprint audit

Audit date: August 3, 2026.

## Build gates

- All three library roots compiled under Lean `4.31.0` with warnings treated
  as errors.
- The original `QRCertBlueprint.lean` was also compiled under Lean
  `4.33.0-rc1` with warnings treated as errors.
- Lake build under the pinned Lean `4.31.0`: passed.
- Source scan for `sorry`, `admit`, axiom declarations, `unsafe`, and `partial`: no matches.
- `QRCertBlueprint.lean` SHA-256: `FC43C4A278C6BAE25DEEDCAAF21CBE9B3C8C17F26F827A8E89B78D5B2CA51DDC`.
- `ReflectionKernel.lean` SHA-256: `4858A7D05BFFD966B7EC89271193D4161558D33963BDBE4DA672EC746AF7BC70`.
- `RamseyCertificate.lean` SHA-256: `EF3BEB937A4DD8C34964D2A218DDBF9A4E869B505A3C6131AA7FC2BF2D77FC54`.

## Kernel axiom report

`lake env lean -E warning QRCertAxiomAudit.lean` reported:

| Theorem group | Axioms reported |
|---|---|
| parser/checker refinement | `propext`, `Quot.sound` |
| fixed-byte encode/decode | `propext` or `propext`, `Quot.sound` |
| well-formedness | `propext` |
| checked-cost agreement | `propext` or `propext`, `Quot.sound` |
| reflected QRCert resource claim | `propext`, `Quot.sound` |
| Ramsey enumeration and checker reflection | `propext`, `Classical.choice`, `Quot.sound` |

These are standard Lean axioms used through library/tactic proofs. No
project-defined axiom appears in the audited dependency closure.
`QRCertAxiomAudit.lean` lists every theorem checked so the report can be
reproduced exactly.
