import CustodyPolicy

/-!
# Assured-autonomy boundary for agentic payments

An LLM, coordinator, marketplace agent, or GPU search process may propose the
payment request, evidence, and human certificate.  None is trusted merely
because it "understands" a payment protocol.  The trusted decision boundary is
the reflected checker, the separately instantiated evidence authenticators,
and the runtime clock value supplied outside the request.

The model proves authorization safety and one functional accounting/replay
state transition.  It deliberately does not prove durable or concurrent
atomicity, signature unforgeability, digest collision resistance, merchant
honesty, settlement, or the correctness of an external clock or payment rail.
-/

namespace QRCert.AgenticPayments

open QRCert.Custody (Digest256)

abbrev PrincipalId := UInt64
abbrev AgentId := UInt64
abbrev MerchantId := UInt64
abbrev CurrencyId := UInt64
abbrev ApproverId := UInt64

/-- A generic, explicit authentication boundary.  Deployments instantiate
this with a verified signature, credential, attestation, or threshold checker;
certificate producers do not get to choose it. -/
structure EvidenceAuthenticator (Evidence : Type) where
  Authentic : Evidence → Prop
  check : Evidence → Bool
  check_iff : ∀ evidence, check evidence = true ↔ Authentic evidence

/-- A principal's least-authority delegation to one payment agent. -/
structure PaymentMandate where
  principal : PrincipalId
  agent : AgentId
  merchant : MerchantId
  currency : CurrencyId
  allowedCartDigests : List Digest256
  maxPerPayment : Nat
  maxCumulative : Nat
  validFrom : Nat
  validUntil : Nat
  keyEpoch : Nat
  humanApprovalAbove : Option Nat
  humanApprovers : List ApproverId
  humanThreshold : Nat
  deriving DecidableEq, Repr

/-- The authenticated mandate includes the canonical digest referenced by all
downstream messages. -/
structure MandateEvidence where
  digest : Digest256
  mandate : PaymentMandate
  deriving DecidableEq, Repr

/-- A merchant quote.  Its digest commits to the canonical external encoding;
the checker binds all decision-relevant fields again rather than trusting that
digest implicitly. -/
structure CheckoutQuote where
  digest : Digest256
  merchant : MerchantId
  currency : CurrencyId
  amount : Nat
  cartDigest : Digest256
  checkoutStateDigest : Digest256
  validUntil : Nat
  deriving DecidableEq, Repr

/-- The exact payment instruction submitted by an untrusted planning agent. -/
structure PaymentRequest where
  agent : AgentId
  mandateDigest : Digest256
  quoteDigest : Digest256
  merchant : MerchantId
  currency : CurrencyId
  amount : Nat
  cartDigest : Digest256
  checkoutStateDigest : Digest256
  nonce : Nat
  deriving DecidableEq, Repr

/-- Persistent state for one mandate.  `spent` is an unbounded natural number,
so the model cannot wrap; an extracted finite-word implementation must refine
this addition with checked arithmetic. -/
structure PaymentState where
  mandateDigest : Digest256
  keyEpoch : Nat
  spent : Nat
  nextNonce : Nat
  lastCheckoutState : Option Digest256
  deriving DecidableEq, Repr

/-- Optional human evidence is bound to this exact payment, not merely to an
agent or account. -/
structure HumanApproval where
  approver : ApproverId
  mandateDigest : Digest256
  quoteDigest : Digest256
  checkoutStateDigest : Digest256
  amount : Nat
  nonce : Nat
  deriving DecidableEq, Repr

structure HumanCertificate where
  approvals : List HumanApproval
  deriving DecidableEq, Repr

/-- Escalation configuration is irrelevant when disabled.  When enabled its
threshold must be positive, attainable, and based on unique approver IDs. -/
def HumanPolicyWellFormed (mandate : PaymentMandate) : Prop :=
  match mandate.humanApprovalAbove with
  | none => True
  | some _ =>
      0 < mandate.humanThreshold ∧
      mandate.humanThreshold ≤ mandate.humanApprovers.length ∧
      mandate.humanApprovers.Nodup

def MandateWellFormed (mandate : PaymentMandate) : Prop :=
  mandate.validFrom ≤ mandate.validUntil ∧
  mandate.maxPerPayment ≤ mandate.maxCumulative ∧
  mandate.allowedCartDigests.Nodup ∧
  HumanPolicyWellFormed mandate

/-- Exact field binding prevents an agent from substituting a cheaper quote's
digest for a more expensive checkout, or changing a cart after approval. -/
def RequestBindsEvidence
    (evidence : MandateEvidence) (quote : CheckoutQuote)
    (request : PaymentRequest) : Prop :=
  request.mandateDigest = evidence.digest ∧
  request.quoteDigest = quote.digest ∧
  request.merchant = quote.merchant ∧
  request.currency = quote.currency ∧
  request.amount = quote.amount ∧
  request.cartDigest = quote.cartDigest ∧
  request.checkoutStateDigest = quote.checkoutStateDigest

/-- Safety envelope checked independently of the planner: identity and scope,
time validity, quote expiry, replay state, and cumulative-budget conservation.
`now` is a separate runtime input and is deliberately absent from
`PaymentRequest`: a deployment must source it from its trusted-clock adapter,
not from the proposing agent.  Clock integrity itself remains an external
assumption. -/
def MandatePermits
    (evidence : MandateEvidence) (quote : CheckoutQuote)
    (now : Nat) (request : PaymentRequest) (state : PaymentState) : Prop :=
  let mandate := evidence.mandate
  request.agent = mandate.agent ∧
  request.merchant = mandate.merchant ∧
  request.currency = mandate.currency ∧
  request.cartDigest ∈ mandate.allowedCartDigests ∧
  0 < request.amount ∧
  request.amount ≤ mandate.maxPerPayment ∧
  mandate.validFrom ≤ now ∧
  now ≤ mandate.validUntil ∧
  now ≤ quote.validUntil ∧
  state.mandateDigest = evidence.digest ∧
  state.keyEpoch = mandate.keyEpoch ∧
  request.nonce = state.nextNonce ∧
  state.spent + request.amount ≤ mandate.maxCumulative

def HumanApprovalValid
    (authenticator : EvidenceAuthenticator HumanApproval)
    (mandate : PaymentMandate) (request : PaymentRequest)
    (approval : HumanApproval) : Prop :=
  authenticator.Authentic approval ∧
  approval.approver ∈ mandate.humanApprovers ∧
  approval.mandateDigest = request.mandateDigest ∧
  approval.quoteDigest = request.quoteDigest ∧
  approval.checkoutStateDigest = request.checkoutStateDigest ∧
  approval.amount = request.amount ∧
  approval.nonce = request.nonce

/-- Payments at or below the configured boundary need no human certificate.
Payments above it require a distinct authenticated threshold. -/
def HumanApprovalSatisfied
    (authenticator : EvidenceAuthenticator HumanApproval)
    (mandate : PaymentMandate) (request : PaymentRequest)
    (certificate : HumanCertificate) : Prop :=
  match mandate.humanApprovalAbove with
  | none => True
  | some boundary =>
      request.amount ≤ boundary ∨
      (mandate.humanThreshold ≤ certificate.approvals.length ∧
       (certificate.approvals.map (fun approval => approval.approver)).Nodup ∧
       ∀ approval ∈ certificate.approvals,
         HumanApprovalValid authenticator mandate request approval)

/-- Complete mathematical authorization predicate. -/
def PaymentAuthorized
    (mandateAuth : EvidenceAuthenticator MandateEvidence)
    (quoteAuth : EvidenceAuthenticator CheckoutQuote)
    (humanAuth : EvidenceAuthenticator HumanApproval)
    (evidence : MandateEvidence) (quote : CheckoutQuote)
    (now : Nat) (request : PaymentRequest) (state : PaymentState)
    (certificate : HumanCertificate) : Prop :=
  mandateAuth.Authentic evidence ∧
  quoteAuth.Authentic quote ∧
  MandateWellFormed evidence.mandate ∧
  RequestBindsEvidence evidence quote request ∧
  MandatePermits evidence quote now request state ∧
  HumanApprovalSatisfied humanAuth evidence.mandate request certificate

/-! ## Reflected fail-closed checker -/

def checkHumanPolicy (mandate : PaymentMandate) : Bool :=
  match mandate.humanApprovalAbove with
  | none => true
  | some _ =>
      decide (0 < mandate.humanThreshold) &&
      (decide (mandate.humanThreshold ≤ mandate.humanApprovers.length) &&
       decide mandate.humanApprovers.Nodup)

def checkMandate (mandate : PaymentMandate) : Bool :=
  decide (mandate.validFrom ≤ mandate.validUntil) &&
  (decide (mandate.maxPerPayment ≤ mandate.maxCumulative) &&
   (decide mandate.allowedCartDigests.Nodup &&
    checkHumanPolicy mandate))

def checkBinding
    (evidence : MandateEvidence) (quote : CheckoutQuote)
    (request : PaymentRequest) : Bool :=
  decide (request.mandateDigest = evidence.digest) &&
  (decide (request.quoteDigest = quote.digest) &&
   (decide (request.merchant = quote.merchant) &&
    (decide (request.currency = quote.currency) &&
     (decide (request.amount = quote.amount) &&
      (decide (request.cartDigest = quote.cartDigest) &&
       decide (request.checkoutStateDigest = quote.checkoutStateDigest))))))

def checkPermission
    (evidence : MandateEvidence) (quote : CheckoutQuote)
    (now : Nat) (request : PaymentRequest) (state : PaymentState) : Bool :=
  let mandate := evidence.mandate
  decide (request.agent = mandate.agent) &&
  (decide (request.merchant = mandate.merchant) &&
   (decide (request.currency = mandate.currency) &&
    (decide (request.cartDigest ∈ mandate.allowedCartDigests) &&
     (decide (0 < request.amount) &&
      (decide (request.amount ≤ mandate.maxPerPayment) &&
       (decide (mandate.validFrom ≤ now) &&
        (decide (now ≤ mandate.validUntil) &&
         (decide (now ≤ quote.validUntil) &&
          (decide (state.mandateDigest = evidence.digest) &&
           (decide (state.keyEpoch = mandate.keyEpoch) &&
            (decide (request.nonce = state.nextNonce) &&
             decide (state.spent + request.amount ≤ mandate.maxCumulative))))))))))))

def checkHumanApproval
    (authenticator : EvidenceAuthenticator HumanApproval)
    (mandate : PaymentMandate) (request : PaymentRequest)
    (approval : HumanApproval) : Bool :=
  authenticator.check approval &&
  (decide (approval.approver ∈ mandate.humanApprovers) &&
   (decide (approval.mandateDigest = request.mandateDigest) &&
    (decide (approval.quoteDigest = request.quoteDigest) &&
     (decide (approval.checkoutStateDigest = request.checkoutStateDigest) &&
      (decide (approval.amount = request.amount) &&
       decide (approval.nonce = request.nonce))))))

def checkHumanCertificate
    (authenticator : EvidenceAuthenticator HumanApproval)
    (mandate : PaymentMandate) (request : PaymentRequest)
    (certificate : HumanCertificate) : Bool :=
  match mandate.humanApprovalAbove with
  | none => true
  | some boundary =>
      decide (request.amount ≤ boundary) ||
      (decide (mandate.humanThreshold ≤ certificate.approvals.length) &&
       (decide (certificate.approvals.map (fun approval => approval.approver)).Nodup &&
        certificate.approvals.all (checkHumanApproval authenticator mandate request)))

def checkPayment
    (mandateAuth : EvidenceAuthenticator MandateEvidence)
    (quoteAuth : EvidenceAuthenticator CheckoutQuote)
    (humanAuth : EvidenceAuthenticator HumanApproval)
    (evidence : MandateEvidence) (quote : CheckoutQuote)
    (now : Nat) (request : PaymentRequest) (state : PaymentState)
    (certificate : HumanCertificate) : Bool :=
  mandateAuth.check evidence &&
  (quoteAuth.check quote &&
   (checkMandate evidence.mandate &&
    (checkBinding evidence quote request &&
     (checkPermission evidence quote now request state &&
      checkHumanCertificate humanAuth evidence.mandate request certificate))))

theorem checkHumanPolicy_eq_true_iff (mandate : PaymentMandate) :
    checkHumanPolicy mandate = true ↔ HumanPolicyWellFormed mandate := by
  cases h : mandate.humanApprovalAbove <;>
    simp [checkHumanPolicy, HumanPolicyWellFormed, h]

theorem checkMandate_eq_true_iff (mandate : PaymentMandate) :
    checkMandate mandate = true ↔ MandateWellFormed mandate := by
  simp [checkMandate, MandateWellFormed, checkHumanPolicy_eq_true_iff]

theorem checkBinding_eq_true_iff
    (evidence : MandateEvidence) (quote : CheckoutQuote)
    (request : PaymentRequest) :
    checkBinding evidence quote request = true ↔
      RequestBindsEvidence evidence quote request := by
  simp [checkBinding, RequestBindsEvidence]

theorem checkPermission_eq_true_iff
    (evidence : MandateEvidence) (quote : CheckoutQuote)
    (now : Nat) (request : PaymentRequest) (state : PaymentState) :
    checkPermission evidence quote now request state = true ↔
      MandatePermits evidence quote now request state := by
  simp [checkPermission, MandatePermits]

theorem checkHumanApproval_eq_true_iff
    (authenticator : EvidenceAuthenticator HumanApproval)
    (mandate : PaymentMandate) (request : PaymentRequest)
    (approval : HumanApproval) :
    checkHumanApproval authenticator mandate request approval = true ↔
      HumanApprovalValid authenticator mandate request approval := by
  simp [checkHumanApproval, HumanApprovalValid, authenticator.check_iff]

theorem checkHumanCertificate_eq_true_iff
    (authenticator : EvidenceAuthenticator HumanApproval)
    (mandate : PaymentMandate) (request : PaymentRequest)
    (certificate : HumanCertificate) :
    checkHumanCertificate authenticator mandate request certificate = true ↔
      HumanApprovalSatisfied authenticator mandate request certificate := by
  cases h : mandate.humanApprovalAbove <;>
    simp [checkHumanCertificate, HumanApprovalSatisfied, h,
      checkHumanApproval_eq_true_iff, List.all_eq_true]

/-- Curry--Howard reflection endpoint for the payment boundary. -/
theorem checkPayment_eq_true_iff
    (mandateAuth : EvidenceAuthenticator MandateEvidence)
    (quoteAuth : EvidenceAuthenticator CheckoutQuote)
    (humanAuth : EvidenceAuthenticator HumanApproval)
    (evidence : MandateEvidence) (quote : CheckoutQuote)
    (now : Nat) (request : PaymentRequest) (state : PaymentState)
    (certificate : HumanCertificate) :
    checkPayment mandateAuth quoteAuth humanAuth evidence quote now request state
        certificate = true ↔
      PaymentAuthorized mandateAuth quoteAuth humanAuth evidence quote now request
        state certificate := by
  simp [checkPayment, PaymentAuthorized, mandateAuth.check_iff,
    quoteAuth.check_iff, checkMandate_eq_true_iff, checkBinding_eq_true_iff,
    checkPermission_eq_true_iff, checkHumanCertificate_eq_true_iff]

/-! ## Functional state transition -/

def advance (request : PaymentRequest) (state : PaymentState) : PaymentState :=
  { mandateDigest := state.mandateDigest
    keyEpoch := state.keyEpoch
    spent := state.spent + request.amount
    nextNonce := state.nextNonce + 1
    lastCheckoutState := some request.checkoutStateDigest }

/-- Canonical data record for the authorization decision.  It binds both
authenticated evidence digests, the checkout state, the replay position, the
key epoch, and the exact accounting delta.  It does not carry a proof and must
be accepted only as the output of `authorizeAndAdvance`. -/
structure AuthorizationRecord where
  authorizedAt : Nat
  mandateDigest : Digest256
  quoteDigest : Digest256
  checkoutStateDigest : Digest256
  amount : Nat
  nonce : Nat
  keyEpoch : Nat
  preSpent : Nat
  postSpent : Nat
  deriving DecidableEq, Repr

def canonicalRecord
    (now : Nat) (request : PaymentRequest)
    (state : PaymentState) : AuthorizationRecord :=
  { authorizedAt := now
    mandateDigest := request.mandateDigest
    quoteDigest := request.quoteDigest
    checkoutStateDigest := request.checkoutStateDigest
    amount := request.amount
    nonce := request.nonce
    keyEpoch := state.keyEpoch
    preSpent := state.spent
    postSpent := state.spent + request.amount }

structure AuthorizationResult where
  nextState : PaymentState
  record : AuthorizationRecord
  deriving DecidableEq, Repr

def canonicalResult
    (now : Nat) (request : PaymentRequest)
    (state : PaymentState) : AuthorizationResult :=
  { nextState := advance request state
    record := canonicalRecord now request state }

def authorizeAndAdvance
    (mandateAuth : EvidenceAuthenticator MandateEvidence)
    (quoteAuth : EvidenceAuthenticator CheckoutQuote)
    (humanAuth : EvidenceAuthenticator HumanApproval)
    (evidence : MandateEvidence) (quote : CheckoutQuote)
    (now : Nat) (request : PaymentRequest) (state : PaymentState)
    (humanCertificate : HumanCertificate) : Option AuthorizationResult :=
  if checkPayment mandateAuth quoteAuth humanAuth evidence quote now request state
      humanCertificate then
    some (canonicalResult now request state)
  else
    none

theorem authorizeAndAdvance_eq_some_iff
    (mandateAuth : EvidenceAuthenticator MandateEvidence)
    (quoteAuth : EvidenceAuthenticator CheckoutQuote)
    (humanAuth : EvidenceAuthenticator HumanApproval)
    (evidence : MandateEvidence) (quote : CheckoutQuote)
    (now : Nat) (request : PaymentRequest) (state : PaymentState)
    (humanCertificate : HumanCertificate) (result : AuthorizationResult) :
    authorizeAndAdvance mandateAuth quoteAuth humanAuth evidence quote now request
        state humanCertificate = some result ↔
      PaymentAuthorized mandateAuth quoteAuth humanAuth evidence quote now request
        state humanCertificate ∧ result = canonicalResult now request state := by
  cases hcheck :
      checkPayment mandateAuth quoteAuth humanAuth evidence quote now request state
        humanCertificate with
  | false =>
      have hnot :
          ¬ PaymentAuthorized mandateAuth quoteAuth humanAuth evidence quote
            now request state humanCertificate := by
        intro hauthorized
        have htrue := (checkPayment_eq_true_iff mandateAuth quoteAuth humanAuth
          evidence quote now request state humanCertificate).mpr hauthorized
        simp [hcheck] at htrue
      simp [authorizeAndAdvance, hcheck, hnot]
  | true =>
      have hauthorized :
          PaymentAuthorized mandateAuth quoteAuth humanAuth evidence quote
            now request state humanCertificate :=
        (checkPayment_eq_true_iff mandateAuth quoteAuth humanAuth evidence quote
          now request state humanCertificate).mp hcheck
      simp [authorizeAndAdvance, hcheck, hauthorized, eq_comm]

/-- Accepted execution entails every authorization invariant, exact budget
conservation, one-step nonce consumption, exact checkout-state binding, and
the canonical authorization record. -/
theorem authorizeAndAdvance_sound
    (mandateAuth : EvidenceAuthenticator MandateEvidence)
    (quoteAuth : EvidenceAuthenticator CheckoutQuote)
    (humanAuth : EvidenceAuthenticator HumanApproval)
    (evidence : MandateEvidence) (quote : CheckoutQuote)
    (now : Nat) (request : PaymentRequest) (state : PaymentState)
    (humanCertificate : HumanCertificate) (result : AuthorizationResult)
    (hstep : authorizeAndAdvance mandateAuth quoteAuth humanAuth evidence quote
      now request state humanCertificate = some result) :
    PaymentAuthorized mandateAuth quoteAuth humanAuth evidence quote now request
        state humanCertificate ∧
    result.nextState.mandateDigest = state.mandateDigest ∧
    result.nextState.keyEpoch = state.keyEpoch ∧
    result.nextState.spent = state.spent + request.amount ∧
    request.nonce = state.nextNonce ∧
    result.nextState.nextNonce = request.nonce + 1 ∧
    result.nextState.lastCheckoutState = some request.checkoutStateDigest ∧
    result.record = canonicalRecord now request state := by
  have h := (authorizeAndAdvance_eq_some_iff mandateAuth quoteAuth humanAuth
    evidence quote now request state humanCertificate result).mp hstep
  rcases h with ⟨hauthorized, rfl⟩
  have hpermission := hauthorized.2.2.2.2.1
  have hfresh : request.nonce = state.nextNonce :=
    hpermission.2.2.2.2.2.2.2.2.2.2.2.1
  refine ⟨hauthorized, rfl, rfl, rfl, hfresh, ?_, rfl, rfl⟩
  simp [canonicalResult, advance, hfresh]

/-- A focused budget corollary useful to downstream payment adapters. -/
theorem accepted_preserves_cumulative_budget
    (mandateAuth : EvidenceAuthenticator MandateEvidence)
    (quoteAuth : EvidenceAuthenticator CheckoutQuote)
    (humanAuth : EvidenceAuthenticator HumanApproval)
    (evidence : MandateEvidence) (quote : CheckoutQuote)
    (now : Nat) (request : PaymentRequest) (state : PaymentState)
    (humanCertificate : HumanCertificate) (result : AuthorizationResult)
    (hstep : authorizeAndAdvance mandateAuth quoteAuth humanAuth evidence quote
      now request state humanCertificate = some result) :
    result.nextState.spent ≤ evidence.mandate.maxCumulative := by
  have hsound := authorizeAndAdvance_sound mandateAuth quoteAuth humanAuth
    evidence quote now request state humanCertificate result hstep
  have hpermission := hsound.1.2.2.2.2.1
  have hbudget :
      state.spent + request.amount ≤ evidence.mandate.maxCumulative :=
    hpermission.2.2.2.2.2.2.2.2.2.2.2.2
  rw [hsound.2.2.2.1]
  exact hbudget

end QRCert.AgenticPayments
