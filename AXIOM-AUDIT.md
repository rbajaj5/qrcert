# QRCert blueprint audit

Audit date: August 3, 2026.

## Build gates

- Lean `4.31.0`: compiled with warnings treated as errors.
- Lean `4.33.0-rc1`: compiled with warnings treated as errors.
- Lake build under the pinned Lean `4.31.0`: passed.
- Source scan for `sorry`, `admit`, axiom declarations, `unsafe`, and `partial`: no matches.
- `QRCertBlueprint.lean` SHA-256: `FC43C4A278C6BAE25DEEDCAAF21CBE9B3C8C17F26F827A8E89B78D5B2CA51DDC`.

## Kernel axiom report

`lake env lean -E warning QRCertAxiomAudit.lean` reported:

| Theorem group | Axioms reported |
|---|---|
| parser/checker refinement | `propext`, `Quot.sound` |
| fixed-byte encode/decode | `propext` or `propext`, `Quot.sound` |
| well-formedness | `propext` |
| checked-cost agreement | `propext` or `propext`, `Quot.sound` |

These are standard Lean axioms used through library/tactic proofs. No project-defined axiom appears in the audited dependency closure. `QRCertAxiomAudit.lean` lists every theorem checked so CI can reproduce the exact report.
