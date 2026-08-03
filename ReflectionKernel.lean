import QRCertBlueprint

/-!
# QRCert resource claims by reflection

`verifyResourceClaim` is the small deterministic kernel-facing checker.  An
untrusted producer may supply bytes and a claimed cost; acceptance is converted
into mathematical facts by `verifyResourceClaim_sound`.

Static gate counting is too small to benefit from a GPU.  This file instead
records the reusable trust pattern: accelerators and heuristic programs may
produce claims or certificates, but only this Boolean checker and its Lean
soundness proof determine acceptance.
-/

namespace QRCert.Reflection

open QRCert.Blueprint

/-- Decode canonical circuit bytes and accept exactly when their unbounded
mathematical cost equals the public claim. -/
def verifyResourceClaim (bytes : List UInt8) (claimedCost : Nat) : Bool :=
  match deserializeSpec bytes with
  | none => false
  | some circuit => decide (claimedCost = costSpec circuit.ops)

/-- Checker acceptance produces the decoded circuit, its well-formedness, exact
cost agreement, and a successful agreeing run of the finite-word cost model. -/
theorem verifyResourceClaim_sound
    (bytes : List UInt8) (claimedCost : Nat) :
    verifyResourceClaim bytes claimedCost = true →
      ∃ circuit result,
        deserializeSpec bytes = some circuit ∧
        WellFormed circuit ∧
        claimedCost = costSpec circuit.ops ∧
        costExtractedModel circuit.ops = some result ∧
        result.toNat = costSpec circuit.ops := by
  intro haccept
  cases hdecode : deserializeSpec bytes with
  | none => simp [verifyResourceClaim, hdecode] at haccept
  | some circuit =>
      have hclaim : claimedCost = costSpec circuit.ops := by
        simpa [verifyResourceClaim, hdecode] using haccept
      have hwf : WellFormed circuit :=
        deserialize_implies_WellFormed bytes circuit hdecode
      obtain ⟨result, hrun, hagree⟩ :=
        deserializeSpec_implies_cost_success bytes circuit hdecode
      exact ⟨circuit, result, rfl, hwf, hclaim, hrun, hagree⟩

/-! Small executable regression examples. -/

example : verifyResourceClaim validCCX 1 = true := by decide
example : verifyResourceClaim validCCX 0 = false := by decide
example : verifyResourceClaim invalidOpcode 0 = false := by decide

theorem validCCX_claim_sound :
    ∃ circuit result,
      deserializeSpec validCCX = some circuit ∧
      WellFormed circuit ∧
      1 = costSpec circuit.ops ∧
      costExtractedModel circuit.ops = some result ∧
      result.toNat = costSpec circuit.ops :=
  verifyResourceClaim_sound validCCX 1 (by decide)

end QRCert.Reflection
