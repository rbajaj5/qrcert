# QRCert assured agentic-payments direction

## Research and product hypothesis

A prospective application is not a formally verified language model. It is a
wallet or payment gateway that lets useful, fallible agents negotiate and buy
things without giving those agents an unrestricted signing key. This is a
research and product hypothesis, not evidence of validated demand, protocol
adoption, or production security.

> Design target: intelligent agents optimize the purchase; a small,
> deterministic authorization kernel with a Lean-verified specification
> controls the signing boundary.

The proposed architecture applies runtime-assurance ideas to payments. Any
number of shopping, pricing, procurement, compliance, or risk agents may
propose actions. They may be buggy, prompt-injected, unavailable, or mutually
inconsistent. In a completed system, a proposal would move money only if a
separate checker accepted the exact canonical transaction and durably committed
the corresponding state transition.

## Architecture

```text
user policy / signed mandate
            |
            v
untrusted multi-agent planners ---- authenticated evidence
            |
            v
canonical PaymentRequest
            |
            v
Lean-specified authorization shield -- reject / hold / request approval
            |
            +-- durable nonce and budget accounting
            |
            v
exact approved digest
            |
            v
HSM, enclave, MPC signer, or smart account
            |
            v
ACP / x402 / MPP / card / account rail
            |
            v
receipt reconciled into authorization state
```

The shield follows the Simplex/runtime-assurance pattern: a capable but
unassured controller proposes an action, while an independently assured
component controls whether that action reaches the actuator. For payments,
the safe fallback is normally to hold or reject the proposal, not silently to
rewrite its recipient or amount.

## Protocol fit

The first intended policy target is the current v0.2
[Agent Payments Protocol (AP2)](https://ap2-protocol.org/ap2/specification/).
AP2 already supplies open and closed mandates, constraint evaluation, agent-key
binding, and signed receipts. Its authorization model is designed to constrain
agents without assuming that they are trustworthy, and unknown constraints
must fail evaluation. AP2 has been
[contributed to FIDO](https://fidoalliance.org/fido-alliance-to-develop-standards-for-trusted-ai-agent-interactions/),
whose working groups are developing agentic-interaction and payment
specifications; that process should not be described as a finalized standard
or as evidence of adoption.
QRCert's proposed contribution is an independently specified, machine-checked
constraint and state-transition kernel, followed later by an exact AP2 wire
adapter. The repository does not currently claim AP2 conformance.

Execution protocols are complementary:

- [Agentic Commerce Protocol](https://github.com/agentic-commerce-protocol/agentic-commerce-protocol)
  specifies merchant-authoritative checkout and delegated-payment flows.
- [x402 v2](https://github.com/x402-foundation/x402/blob/main/specs/x402-specification-v2.md)
  specifies HTTP payment requirements, payloads, verification, and settlement
  responses. Nonces and validity windows belong to particular payment schemes,
  such as the EVM `exact` scheme, rather than to every x402 payment method.
- [Machine Payments Protocol](https://mpp.dev/) specifies a
  challenge--credential--receipt lifecycle for machine-to-machine payments.
- [Visa Trusted Agent Protocol](https://developer.visa.com/capabilities/trusted-agent-protocol/trusted-agent-protocol-specifications/)
  specifies merchant-side agent recognition and signed HTTP requests.

The authorization theorem should remain independent of any one rail. AP2 can
express why a payment is permitted; ACP can carry checkout state; x402 or MPP
can carry an execution request; an HSM, threshold group, or smart account can
hold the key. These are candidate adapters, not implemented dependencies or a
claim that the protocols are presently interoperable.

## Initial verified model slice

`AgenticPayments.lean` is deliberately smaller than AP2. It models one exact
payment proposal and proves its acceptance conditions and functional
accounting-state update. It does not establish durable or concurrent atomicity.
Its boundary contains:

- an authenticated mandate-evidence interface with a proved `Bool`/`Prop`
  correspondence;
- exact mandate-digest, quote, cart, merchant, currency, agent, and key-epoch
  binding;
- validity and quote-expiry checks against an explicit trusted-time input;
- per-payment and cumulative budgets over unbounded `Nat` arithmetic;
- an exact next nonce and a next-state theorem that advances it by one;
- optional human escalation above a policy threshold; and
- a returned authorization record bound to the pre-state and approved request.

The strongest intended statement has the following shape:

```text
authorize policy authenticator now state request = some (next, record)
  -> authentic mandate evidence
  /\ every request binding and policy constraint holds
  /\ state.spent + request.amount <= mandate.maxCumulative
  /\ next.nextNonce = request.nonce + 1
  /\ next.spent = state.spent + request.amount
  /\ record binds exactly this authorized transition
```

Within this model, the theorem contains arbitrary agent-supplied request values.
Giving every agent a copy of the assured-autonomy literature may improve
planning and availability, but it adds nothing to this safety implication.

## Why state is essential

A stateless limit check is insufficient in a multi-agent system. If two agents
both observe 70 units remaining, two concurrent 60-unit proposals can each pass
individually. The current Lean slice models a sequential transition that
immediately adds an accepted amount to `spent` and advances the nonce. A
deployment must durably serialize that transition before releasing signing
authority. A separate reservation/settlement/cancellation lifecycle remains
future work.

Threshold custody does not solve this state problem by itself. FROST distributes
signing authority across key shares; it does not synchronize budgets or prevent
two conflicting but individually well-formed signing sessions. A threshold
deployment additionally needs a mechanism that serializes or atomically
coordinates authorization state, such as suitable replicated state or a
consensus service.

## Multi-agent contracts

Agents may expose assume/guarantee contracts for composition, but a safety
theorem may use an assumption only after the gateway checks it or places it
outside the adversarial model. Useful evidence producers include:

- a shopping agent that binds a cart digest;
- a merchant agent that signs a quote and expiry;
- a compliance agent that supplies a credential decision;
- a risk agent that recommends escalation; and
- a settlement agent that supplies a receipt.

Their outputs are evidence, not votes. Majority agreement among language models
is not Byzantine consensus and does not replace the authorization kernel.

## Research roadmap

The protocol-neutral slice should grow in independently auditable layers:

1. canonical multi-byte payment and receipt encodings with domain separation;
2. a closed constraint language with independent `Prop` semantics and
   fail-closed unknown constraints;
3. attenuating delegation, proving that a child agent cannot gain merchants,
   assets, budget, time, or subdelegation rights;
4. reservation, settlement, cancellation, refund, expiry, and revocation state
   transitions;
5. trace safety for arbitrary interleavings of colluding agent proposals;
6. exact AP2 mandate/receipt and ACP/x402/MPP adapter refinements; and
7. an abstract signer theorem followed by separate HSM, enclave, MPC, or
   smart-account implementations.

Lean should prove decoding, policy evaluation, authority attenuation, replay
and budget invariants, state transitions, and exact digest binding. Signature
unforgeability, hash security, trusted time and oracle data, signer isolation,
consensus liveness, settlement finality, compiler correspondence, and network
availability remain explicit external assumptions.

## Demonstration target

The useful first integrated demonstration would be:

> Given proposals from any number of potentially colluding agents, the wallet
> never releases a payment signature outside the user's machine-checkable
> mandate, and every accepted proposal durably consumes its nonce and accounts
> for its amount before signing authority is released.

The current Lean module proves the authorization and state-transition portion
for an abstract request; it does not yet prove this end-to-end wallet statement.
That statement additionally requires a refined wire adapter, durable atomic
storage, and a signer that accepts only checker-approved digests. The proposed
demonstration reuses QRCert's general method -- canonical finite evidence, a
reflected Boolean checker, independent `Prop` semantics, explicit
authentication boundaries, and an axiom audit -- rather than treating the
existing quantum-circuit results as payment proofs.

## Assured-autonomy references

- [NASA, *Runtime Assurance for Increasingly Autonomous Systems*](https://ntrs.nasa.gov/citations/20220015734)
- [Bloem et al., *Shield Synthesis*](https://arxiv.org/abs/1501.02573)
- [Minimum-Cost Shields for Multi-Agent Systems](https://doi.org/10.23919/ACC.2019.8815233)
- [NIST AI Agent Standards Initiative](https://www.nist.gov/artificial-intelligence/ai-agent-standards-initiative)
