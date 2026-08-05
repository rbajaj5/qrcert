# Digital-signature and custody applications

QRCert does not replace a digital-signature, MPC, enclave, or ZK protocol.  Its
useful role is a small proof-carrying decision boundary immediately before a
signer releases a signature or signature share.

## Concrete custody kernel

[`CustodyPolicy.lean`](CustodyPolicy.lean) implements the first application
slice.  A request binds a 256-bit message identifier, destination, amount,
chain, key epoch, and replay nonce.  A policy fixes the authorized signers,
attainable positive threshold, destination allowlist, amount cap, chain, and
key epoch.  The reflected endpoint proves that success implies:

- the policy is internally well formed;
- the request matches the policy and current replay state;
- every counted approval binds every request field;
- counted signer identifiers are authorized and pairwise distinct;
- the threshold is met; and
- the only state change is incrementing the expected nonce.

Approval authenticity is not accepted as an untrusted Boolean field.  The
checker is parameterized by an `ApprovalAuthenticator` containing an executable
check, a mathematical authenticity predicate, and a proof relating them.  A
production deployment must instantiate this boundary with a separately
verified signature, threshold-share, or attestation checker and keep that
instance in trusted configuration.  The example authenticator in the file is
non-cryptographic test data only.

## Single signer, multisignature, and MPC

| Setting | What this kernel contributes | Separate security layer |
|---|---|---|
| Single signer or HSM | Canonical request fields, policy checks, key-epoch binding, freshness, and a proved decision before key use | Key isolation, entropy/nonces, constant time, rollback resistance, and device integrity |
| Several independent signatures | Distinct authorized-key counting and a precise `k`-of-`n` policy | Verification and unforgeability of each signature |
| Threshold/MPC signature | Every honest participant can check the same request and policy before emitting its share | DKG, share secrecy, malicious-security threshold, authenticated channels, nonce state, robustness, and aggregation correctness |
| Enclave-gated signing | Bind the checker/policy hash and request digest into attested data | Enclave isolation, vendor attestation PKI, side channels, rollback, and source-to-binary correspondence |
| ZK policy proof | Pin the exact public/private relation and its canonical inputs | Knowledge soundness, zero knowledge, setup assumptions, and circuit/prover correctness |

FROST is a clean threshold target because it outputs an ordinary Schnorr-family
signature while making participant identifiers, commitments, binding factors,
signature shares, and nonce lifecycle explicit.  It assumes fewer than the
threshold number of corrupted participants and does not itself provide a
complete custody system; see [RFC 9591](https://www.rfc-editor.org/rfc/rfc9591.html).
NIST likewise treats threshold schemes as MPC-based distribution of trust for
key generation and cryptographic operations; see the
[NIST Multi-Party Threshold Cryptography project](https://csrc.nist.gov/Projects/threshold-cryptography).

## Recommended signature roadmap

1. Define a canonical signed envelope and message-to-be-signed encoding.  COSE
   `Sign1` is a concrete target because its `Sig_structure` binds context,
   protected headers, external AAD, and payload; see
   [RFC 9052](https://www.rfc-editor.org/rfc/rfc9052.html).
2. Prove a deterministic Ed25519 public verifier equivalent to the standard
   group equation and connect it to `ApprovalAuthenticator`; see
   [RFC 8032](https://www.rfc-editor.org/rfc/rfc8032.html).
3. Add independent multi-signature policy checking.
4. Add a FROST transcript/share verifier and a modeled one-time nonce state
   machine.
5. Only then compose the relation with a SNARK/STARK or enclave attestation
   verifier if confidentiality or remote execution evidence is required.

Functional correctness does not establish computational unforgeability.  Nor
does a Lean nonce state machine prove physical deletion, entropy quality,
constant-time execution, crash consistency, or rollback resistance.  Those
boundaries must remain explicit in any custody claim.

## Why resource attestation still matters

Exact cost and canonical program identity can bound denial-of-service work in
an HSM/MPC service, freeze the approved algorithm suite, and predict ZK proving
cost.  GPU acceleration may help batch public verification or untrusted witness
production; it does not strengthen signature or custody security.  A GPU result
must still pass the trusted checker, and a succinct speedup requires a separate
proof system whose verifier is itself connected to the formal specification.
