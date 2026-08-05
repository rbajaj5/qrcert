# QRCert blueprint audit

Audit date: August 5, 2026.

## Build gates

- All six library roots compiled under Lean `4.31.0` with warnings treated
  as errors.
- The original `QRCertBlueprint.lean` was also compiled under Lean
  `4.33.0-rc1` with warnings treated as errors.
- Lake build under the pinned Lean `4.31.0`: passed.
- Source scan for `sorry`, `admit`, axiom declarations, `unsafe`, and `partial`: no matches.
- `QRCertBlueprint.lean` SHA-256: `FC43C4A278C6BAE25DEEDCAAF21CBE9B3C8C17F26F827A8E89B78D5B2CA51DDC`.
- `QRCertWaveletFingerprint.lean` SHA-256: `30C213FED14E428E19464E69D55D4CE9510290ED4B5A1663782D587B2F137261`.
- `ReflectionKernel.lean` SHA-256: `4858A7D05BFFD966B7EC89271193D4161558D33963BDBE4DA672EC746AF7BC70`.
- `RamseyCertificate.lean` SHA-256: `EF3BEB937A4DD8C34964D2A218DDBF9A4E869B505A3C6131AA7FC2BF2D77FC54`.
- `CustodyPolicy.lean` SHA-256: `621A80265D2A04EEC6C634F08C195481204E3C547BDB93DDD5CC05355DF9930F`.
- `AgenticPayments.lean` SHA-256: `495C8CB443D13361CAD06E88854FB5256CBDF4C27BB07A6622F7D569336E29CD`.
- All six modules are included in the pinned Lake build and audit.

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
| Haar reconstruction and injectivity | `propext`, `Quot.sound` |
| Walsh injectivity and energy scaling | `propext`, `Quot.sound` |
| operation-block fingerprint injectivity | `propext`, `Classical.choice`, `Quot.sound` |
| custody authentication, authorization, and state transition | `propext` or `propext`, `Quot.sound` |
| agentic-payment authentication, authorization, state transition, and budget preservation | `propext` or `propext`, `Quot.sound` |

These are standard Lean axioms used through library/tactic proofs. No
project-defined axiom appears in the audited dependency closure.
`QRCertAxiomAudit.lean` lists every theorem checked so CI can reproduce the
exact report. This is an explicit theorem list and a human-reviewed report, not
an automatic allowlist for every declaration that could later be added to the
repository.
