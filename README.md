# QRCert verified checker and certificate blueprint

This is a compiling Lean 4 and safe-Rust research artifact for six deliberately
narrow QRCert milestones:

1. a checked decoder and finite-word cost model for a tiny circuit format;
2. exact integer Haar and Walsh--Hadamard transforms for structural circuit
   fingerprints;
3. reflected resource and Ramsey certificates with an untrusted GPU search
   boundary;
4. a reflected custody-authorization state machine with an explicit
   authentication interface; and
5. an assured-autonomy payment model that checks an arbitrary agent-supplied
   proposal against authenticated mandates, exact quote binding, replay and
   cumulative-budget state, and optional human escalation; and
6. an extraction-oriented, dependency-free Rust implementation plus pinned
   Charon/Aeneas bridge configuration.

A prospective application direction is agentic payments: useful agents could
search, negotiate, and assemble checkout proposals, while a small verified
authorization model determines which exact requests may advance budget state.
This is a research and product hypothesis, not market validation or a claim of
production security. The repository proves model-level containment properties;
it does not yet connect the model to a payment rail or signer.

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
requires CUDA-enabled PyTorch and rejects any CPU/GPU score disagreement. Its
reusable gather plan materializes immutable clique-edge index tensors once per
workload. On the recorded RTX 5070 Ti batch workload this reduced repeated GPU
scoring from 44.4 ms to 10.5 ms (4.23x); the 67.0 ms setup cost is recovered
after about two batches.
See `OPEN-MATH-APPLICATIONS.md` for measured results, precise trust boundaries,
and applications to Ramsey numbers, Hadamard matrices, bounded Collatz
verification, and the companion Kemeny-poset work.

## Custody authorization example

`CustodyPolicy.lean` is a concrete non-quantum application of the reflected
checker pattern. It proves that an accepted request has the right chain, key
epoch, replay nonce, amount and destination; every counted approval binds all
request fields; signer identifiers are authorized and distinct; the attainable
threshold is met; and the state transition increments only the nonce.

Approval authenticity is supplied through a proof-carrying
`ApprovalAuthenticator`. A deployment must instantiate it with a separately
verified signature, threshold-share, or attestation checker. The module does
not claim key secrecy, signature unforgeability, MPC security, enclave
isolation, or side-channel resistance. See
`SIGNATURE-CUSTODY-APPLICATIONS.md`.

## Assured agentic payments

`AgenticPayments.lean` applies the same reflected-checker pattern at a
money-moving boundary. Separate proof-carrying authenticators cover the user's
mandate, merchant quote, and any required human approvals. The checker binds
the agent, merchant, currency, amount, cart and checkout-state digests, policy
and key epoch, trusted time, and next nonce. It enforces per-payment and
cumulative limits, and its successful functional transition returns one
next-state value that advances the nonce and adds the accepted amount to the
accounted `spent` total. Durable and concurrent atomicity remain implementation
obligations.

The model places planners outside the trusted boundary; they may be
prompt-injected, colluding, or simply wrong. Its theorem is about what the
abstract authorization function can accept, not what agents understand or what
a deployed gateway will necessarily enforce. The initial model is
protocol-neutral; AP2 is the first candidate for mandate semantics, while ACP,
x402, and MPP are candidate checkout or settlement adapters. None is implemented
here. See `AGENTIC-PAYMENTS.md` for the architecture, protocol mapping, exact
trust boundary, and roadmap.

## Rust extraction candidate

`rust/qrcert-checker` implements the fixed-byte decoder and resource endpoint
in `no_std`, dependency-free, safe Rust with fixed-capacity storage and
fail-closed checked arithmetic. Its exhaustive bounded regression test compares
335,923 byte strings with an independent reference implementation.

The pinned Linux x86_64 bridge gate produces LLBC and generates compiling Lean
definitions without opaque external-function templates. That gate includes a
local Aeneas elaborator patch, a fail-closed normalization pass, and the two
handwritten termination measures in `bridge/Clauses.lean`; all remain inside
the untrusted translation boundary. GitHub Actions reproduces the same cold
bridge run in a separate job. The generated-code-to-blueprint refinement
theorem is still open, and successful extraction alone is not counted as
semantic preservation. See `RUST-MIR-BRIDGE.md`.

## Build and audit

The pinned toolchain is Lean `4.31.0`, matching the reviewed hax/Aeneas integration pin.

```text
lake build
lake env lean -E warning QRCertAxiomAudit.lean
cd rust/qrcert-checker
cargo fmt --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test
```

The separate pinned bridge gate is reproducible on Linux x86_64 with
`bash bridge/extract.sh` and runs as its own GitHub Actions job.

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
- The Rust parser now extracts through the pinned Charon/Aeneas versions, but
  its generated functions do not yet have the required Lean refinement proof
  against `QRCertBlueprint.lean`.
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
- Circuit semantics, semantic certificates, authenticated hashing,
  generated-Rust refinement, rustc/RISC-V correspondence, SP1, and the ZK
  composition theorem remain separate obligations.
- The payment module is a protocol-neutral authorization model, not yet an AP2,
  ACP, x402, MPP, card-network, or banking wire implementation. Cryptographic
  authentication, trusted time, atomic storage, signer isolation, settlement,
  refunds, and distributed consensus remain explicit external assumptions.
