import Std

/-!
# Reflected custody authorization policy

This module demonstrates a small policy-gated signing endpoint. An untrusted
service may construct an approval certificate, but the Boolean decision is
accepted only through the proved `Prop` specification below.

The scope is deliberately limited to authorization. `Digest256` values are
opaque, fixed-size identifiers; this module does not prove collision
resistance, signature unforgeability, secret-key custody, MPC security,
enclave isolation or attestation, side-channel resistance, or correct
execution by a signing device. Those properties require separate models and
composition theorems.
-/

namespace QRCert.Custody

/-- A digest has exactly four 64-bit limbs. There is no variable-length or
non-minimal representation at this policy layer. The interpretation of each
limb (including byte order at an external serialization boundary) must be
fixed by the surrounding protocol. -/
@[ext]
structure Digest256 where
  limb0 : UInt64
  limb1 : UInt64
  limb2 : UInt64
  limb3 : UInt64
  deriving DecidableEq, Repr

/-- The unique four-limb view used by the policy checker. -/
def Digest256.toWords (digest : Digest256) : List UInt64 :=
  [digest.limb0, digest.limb1, digest.limb2, digest.limb3]

@[simp]
theorem Digest256.toWords_length (digest : Digest256) :
    digest.toWords.length = 4 := by
  rfl

/-- The fixed-size representation loses no digest information. -/
theorem Digest256.toWords_injective : Function.Injective Digest256.toWords := by
  intro left right heq
  cases left
  cases right
  simp [Digest256.toWords] at heq
  simp_all

abbrev SignerId := UInt64
abbrev ChainId := UInt64

/-- Public policy for one custody account. -/
structure Policy where
  authorizedSigners : List SignerId
  threshold : Nat
  allowedDestinations : List Digest256
  maxAmount : Nat
  chainId : ChainId
  keyEpoch : Nat
  deriving Repr

/-- Every field that must be authorized before signing. `messageDigest` is
opaque here: a transaction encoder must separately prove that it commits to
the intended transaction semantics. -/
structure SigningRequest where
  destination : Digest256
  amount : Nat
  chainId : ChainId
  keyEpoch : Nat
  nonce : Nat
  messageDigest : Digest256
  deriving DecidableEq, Repr

/-- Replay state stored by the policy service. -/
structure CustodyState where
  keyEpoch : Nat
  nextNonce : Nat
  deriving DecidableEq, Repr

/-- One signer approval, including a copy of every request field. This makes
field substitution visible to the checker instead of relying on an implicit
ambient request. -/
structure Approval where
  signer : SignerId
  destination : Digest256
  amount : Nat
  chainId : ChainId
  keyEpoch : Nat
  nonce : Nat
  messageDigest : Digest256
  deriving DecidableEq, Repr

structure ApprovalCertificate where
  approvals : List Approval
  deriving DecidableEq, Repr

/-- Authentication boundary for approval evidence. Membership of a claimed
signer identifier is not evidence that the signer approved anything, so every
accepted approval must additionally satisfy `Authentic` through this proved
Boolean checker.

A deployment must fix this value as trusted configuration and instantiate it
with a separately verified signature, threshold-share, or attestation checker.
It must not accept an authenticator supplied by the certificate producer. The
theorems below are parametric in the chosen authenticity notion; they do not
prove that a particular cryptographic implementation is secure. -/
structure ApprovalAuthenticator where
  Authentic : Approval → Prop
  check : Approval → Bool
  check_iff : ∀ approval, check approval = true ↔ Authentic approval

/-- A usable threshold is nonzero, attainable, and based on unique policy
signer identifiers. -/
def PolicyWellFormed (policy : Policy) : Prop :=
  (0 < policy.threshold ∧
    policy.threshold ≤ policy.authorizedSigners.length) ∧
    policy.authorizedSigners.Nodup

/-- The request is permitted by policy and is fresh for the current state. -/
def RequestPermitted
    (policy : Policy) (request : SigningRequest) (state : CustodyState) : Prop :=
  (((((request.destination ∈ policy.allowedDestinations ∧
    request.amount ≤ policy.maxAmount) ∧
    request.chainId = policy.chainId) ∧
    request.keyEpoch = policy.keyEpoch) ∧
    state.keyEpoch = policy.keyEpoch) ∧
    request.nonce = state.nextNonce)

/-- An approval comes from an authorized identifier and binds every relevant
request field: destination, amount, chain, key epoch, nonce, and message. -/
def ApprovalValid
    (policy : Policy) (request : SigningRequest) (approval : Approval) : Prop :=
  ((((((approval.signer ∈ policy.authorizedSigners ∧
    approval.destination = request.destination) ∧
    approval.amount = request.amount) ∧
    approval.chainId = request.chainId) ∧
    approval.keyEpoch = request.keyEpoch) ∧
    approval.nonce = request.nonce) ∧
    approval.messageDigest = request.messageDigest)

/-- An approval is usable only when it is both authenticated and structurally
bound to the policy and request. -/
def AuthenticatedApproval
    (authenticator : ApprovalAuthenticator) (policy : Policy)
    (request : SigningRequest) (approval : Approval) : Prop :=
  authenticator.Authentic approval ∧ ApprovalValid policy request approval

/-- Mathematical authorization specification. Threshold counting is sound
because the certificate's signer identifiers must be pairwise distinct. -/
def Authorized
    (authenticator : ApprovalAuthenticator) (policy : Policy)
    (request : SigningRequest) (state : CustodyState)
    (certificate : ApprovalCertificate) : Prop :=
  ((((PolicyWellFormed policy ∧
    RequestPermitted policy request state) ∧
    policy.threshold ≤ certificate.approvals.length) ∧
    (certificate.approvals.map (fun approval => approval.signer)).Nodup) ∧
    ∀ approval ∈ certificate.approvals,
      AuthenticatedApproval authenticator policy request approval)

/-! ## Executable reflected checks -/

def checkPolicy (policy : Policy) : Bool :=
  decide (0 < policy.threshold) &&
  decide (policy.threshold ≤ policy.authorizedSigners.length) &&
  decide policy.authorizedSigners.Nodup

def checkRequest
    (policy : Policy) (request : SigningRequest) (state : CustodyState) : Bool :=
  decide (request.destination ∈ policy.allowedDestinations) &&
  decide (request.amount ≤ policy.maxAmount) &&
  decide (request.chainId = policy.chainId) &&
  decide (request.keyEpoch = policy.keyEpoch) &&
  decide (state.keyEpoch = policy.keyEpoch) &&
  decide (request.nonce = state.nextNonce)

def checkApprovalFields
    (policy : Policy) (request : SigningRequest) (approval : Approval) : Bool :=
  decide (approval.signer ∈ policy.authorizedSigners) &&
  decide (approval.destination = request.destination) &&
  decide (approval.amount = request.amount) &&
  decide (approval.chainId = request.chainId) &&
  decide (approval.keyEpoch = request.keyEpoch) &&
  decide (approval.nonce = request.nonce) &&
  decide (approval.messageDigest = request.messageDigest)

/-- Authenticate first, then check signer eligibility and exact request-field
binding. -/
def checkApproval
    (authenticator : ApprovalAuthenticator) (policy : Policy)
    (request : SigningRequest) (approval : Approval) : Bool :=
  authenticator.check approval && checkApprovalFields policy request approval

/-- Small executable kernel: certificate producers, including enclave or MPC
systems, are untrusted inputs to this function. -/
def checkAuthorization
    (authenticator : ApprovalAuthenticator) (policy : Policy)
    (request : SigningRequest) (state : CustodyState)
    (certificate : ApprovalCertificate) : Bool :=
  checkPolicy policy &&
  checkRequest policy request state &&
  decide (policy.threshold ≤ certificate.approvals.length) &&
  decide (certificate.approvals.map (fun approval => approval.signer)).Nodup &&
  certificate.approvals.all (checkApproval authenticator policy request)

theorem checkPolicy_eq_true_iff (policy : Policy) :
    checkPolicy policy = true ↔ PolicyWellFormed policy := by
  simp [checkPolicy, PolicyWellFormed]

theorem checkRequest_eq_true_iff
    (policy : Policy) (request : SigningRequest) (state : CustodyState) :
    checkRequest policy request state = true ↔
      RequestPermitted policy request state := by
  simp [checkRequest, RequestPermitted]

theorem checkApprovalFields_eq_true_iff
    (policy : Policy) (request : SigningRequest) (approval : Approval) :
    checkApprovalFields policy request approval = true ↔
      ApprovalValid policy request approval := by
  simp [checkApprovalFields, ApprovalValid]

theorem checkApproval_eq_true_iff
    (authenticator : ApprovalAuthenticator) (policy : Policy)
    (request : SigningRequest) (approval : Approval) :
    checkApproval authenticator policy request approval = true ↔
      AuthenticatedApproval authenticator policy request approval := by
  simp [checkApproval, AuthenticatedApproval,
    authenticator.check_iff, checkApprovalFields_eq_true_iff]

/-- Reflection boundary: the executable Boolean checker is exactly the
mathematical authorization policy. -/
theorem checkAuthorization_eq_true_iff
    (authenticator : ApprovalAuthenticator) (policy : Policy)
    (request : SigningRequest) (state : CustodyState)
    (certificate : ApprovalCertificate) :
    checkAuthorization authenticator policy request state certificate = true ↔
      Authorized authenticator policy request state certificate := by
  simp [checkAuthorization, Authorized, checkPolicy_eq_true_iff,
    checkRequest_eq_true_iff, checkApproval_eq_true_iff, List.all_eq_true]

theorem checkAuthorization_sound
    (authenticator : ApprovalAuthenticator) (policy : Policy)
    (request : SigningRequest) (state : CustodyState)
    (certificate : ApprovalCertificate)
    (haccept :
      checkAuthorization authenticator policy request state certificate = true) :
    Authorized authenticator policy request state certificate :=
  (checkAuthorization_eq_true_iff
    authenticator policy request state certificate).mp haccept

/-! ## Fail-closed state transition -/

def advanceNonce (state : CustodyState) : CustodyState :=
  { keyEpoch := state.keyEpoch, nextNonce := state.nextNonce + 1 }

/-- Return an advanced replay state only after reflected authorization. This
does not call a signer and does not claim that a signature was produced. -/
def authorizeAndAdvance
    (authenticator : ApprovalAuthenticator) (policy : Policy)
    (request : SigningRequest) (state : CustodyState)
    (certificate : ApprovalCertificate) : Option CustodyState :=
  if checkAuthorization authenticator policy request state certificate then
    some (advanceNonce state)
  else
    none

theorem authorizeAndAdvance_eq_some_iff
    (authenticator : ApprovalAuthenticator) (policy : Policy)
    (request : SigningRequest) (state nextState : CustodyState)
    (certificate : ApprovalCertificate) :
    authorizeAndAdvance authenticator policy request state certificate =
        some nextState ↔
      Authorized authenticator policy request state certificate ∧
      nextState = advanceNonce state := by
  cases hcheck :
      checkAuthorization authenticator policy request state certificate with
  | false =>
      have hnot :
          ¬ Authorized authenticator policy request state certificate := by
        intro hauth
        have htrue :=
          (checkAuthorization_eq_true_iff
            authenticator policy request state certificate).mpr hauth
        simp [hcheck] at htrue
      simp [authorizeAndAdvance, hcheck, hnot]
  | true =>
      have hauth :
          Authorized authenticator policy request state certificate :=
        (checkAuthorization_eq_true_iff
          authenticator policy request state certificate).mp hcheck
      simp [authorizeAndAdvance, hcheck, hauth, eq_comm]

/-- Accepted execution proves the complete authorization predicate and the
exact replay-state transition. -/
theorem authorizeAndAdvance_sound
    (authenticator : ApprovalAuthenticator) (policy : Policy)
    (request : SigningRequest) (state nextState : CustodyState)
    (certificate : ApprovalCertificate)
    (hstep : authorizeAndAdvance authenticator policy request state certificate =
      some nextState) :
    Authorized authenticator policy request state certificate ∧
      nextState.keyEpoch = state.keyEpoch ∧
      nextState.nextNonce = state.nextNonce + 1 := by
  have h := (authorizeAndAdvance_eq_some_iff
    authenticator policy request state nextState certificate).mp hstep
  rcases h with ⟨hauth, rfl⟩
  exact ⟨hauth, rfl, rfl⟩

/-! A small regression certificate. -/

def exampleDestination : Digest256 := ⟨1, 2, 3, 4⟩
def exampleMessage : Digest256 := ⟨10, 20, 30, 40⟩

def examplePolicy : Policy where
  authorizedSigners := [11, 22, 33]
  threshold := 2
  allowedDestinations := [exampleDestination]
  maxAmount := 1000
  chainId := 1
  keyEpoch := 7

def exampleRequest : SigningRequest where
  destination := exampleDestination
  amount := 250
  chainId := 1
  keyEpoch := 7
  nonce := 9
  messageDigest := exampleMessage

def exampleState : CustodyState := ⟨7, 9⟩

def exampleApproval (signer : SignerId) : Approval where
  signer := signer
  destination := exampleDestination
  amount := 250
  chainId := 1
  keyEpoch := 7
  nonce := 9
  messageDigest := exampleMessage

/-- Synthetic authenticator used only to exercise the reflected kernel. It
recognizes two exact in-file approval values and provides no cryptographic
security. Production code must replace it with a separately verified checker
for signatures, MPC shares, or attestation evidence. -/
def syntheticExampleAuthenticator : ApprovalAuthenticator where
  Authentic := fun approval =>
    approval = exampleApproval 11 ∨ approval = exampleApproval 22
  check := fun approval =>
    decide (approval = exampleApproval 11 ∨ approval = exampleApproval 22)
  check_iff := by
    intro approval
    simp

def exampleCertificate : ApprovalCertificate :=
  ⟨[exampleApproval 11, exampleApproval 22]⟩

example : checkAuthorization syntheticExampleAuthenticator examplePolicy
    exampleRequest exampleState exampleCertificate = true := by
  decide

example : authorizeAndAdvance syntheticExampleAuthenticator examplePolicy
    exampleRequest exampleState exampleCertificate = some ⟨7, 10⟩ := by
  decide

theorem example_authorization_sound :
    Authorized syntheticExampleAuthenticator examplePolicy exampleRequest
      exampleState exampleCertificate :=
  checkAuthorization_sound syntheticExampleAuthenticator examplePolicy
    exampleRequest exampleState exampleCertificate (by decide)

end QRCert.Custody
