import QRCertBlueprint

/-!
# Exact dyadic Haar fingerprints

This module gives QRCert a small, exact multiscale fingerprint specification.
It uses the unnormalised Haar butterfly over `Int`; no floating-point or
analytic approximation enters the proof.

The transform is a structural fingerprint, not a cryptographic hash.  A
production certificate must authenticate the resulting coefficient stream
with a standard cryptographic construction.
-/

namespace QRCert.Wavelet

/-! ## The integer butterfly -/

def butterfly (a b : Int) : Int × Int :=
  (a + b, a - b)

def inverseButterfly (sum difference : Int) : Int × Int :=
  ((sum + difference) / 2, (sum - difference) / 2)

theorem inverseButterfly_butterfly (a b : Int) :
    inverseButterfly (butterfly a b).1 (butterfly a b).2 = (a, b) := by
  simp only [butterfly, inverseButterfly]
  apply Prod.ext <;> omega

theorem butterfly_injective : Function.Injective (Function.uncurry butterfly) := by
  rintro ⟨a, b⟩ ⟨c, d⟩ h
  have recovered := congrArg
    (fun output => inverseButterfly output.1 output.2) h
  simpa [inverseButterfly_butterfly] using recovered

/-! ## Power-of-two traces and lazy Haar coefficients

`Dyadic α m` contains exactly `2^m` leaves.  A node splits a consecutive
interval into its left and right dyadic halves.  `Details m` stores the root
difference and then the details internal to both halves.  Together with one
global approximation coefficient this is the standard lazy/interleaved Haar
layout, represented without implementation-dependent array indices.
-/

inductive Dyadic (α : Type) : Nat → Type where
  | leaf (value : α) : Dyadic α 0
  | node {m : Nat} (left right : Dyadic α m) : Dyadic α (m + 1)
  deriving Repr, DecidableEq

namespace Dyadic

def map (f : α → β) : Dyadic α m → Dyadic β m
  | .leaf value => .leaf (f value)
  | .node left right => .node (map f left) (map f right)

@[simp] theorem map_leaf (f : α → β) (value : α) :
    map f (.leaf value) = .leaf (f value) := rfl

@[simp] theorem map_node (f : α → β)
    (left right : Dyadic α m) :
    map f (.node left right) = .node (map f left) (map f right) := rfl

end Dyadic

inductive Details : Nat → Type where
  | none : Details 0
  | node {m : Nat}
      (difference : Int) (left right : Details m) : Details (m + 1)
  deriving Repr, DecidableEq

namespace Details

def left : Details (m + 1) → Details m
  | .node _ left _ => left

def right : Details (m + 1) → Details m
  | .node _ _ right => right

end Details

structure Coefficients (m : Nat) where
  approximation : Int
  details : Details m
  deriving Repr, DecidableEq

def total : Dyadic Int m → Int
  | .leaf value => value
  | .node left right => total left + total right

def detailTree : Dyadic Int m → Details m
  | .leaf _ => .none
  | .node left right =>
      .node (total left - total right) (detailTree left) (detailTree right)

def forward (signal : Dyadic Int m) : Coefficients m :=
  { approximation := total signal
    details := detailTree signal }

def inverseFrom : (m : Nat) → Int → Details m → Dyadic Int m
  | 0, approximation, .none => .leaf approximation
  | _ + 1, approximation, .node difference left right =>
      .node
        (inverseFrom _ ((approximation + difference) / 2) left)
        (inverseFrom _ ((approximation - difference) / 2) right)

def inverse (coefficients : Coefficients m) : Dyadic Int m :=
  inverseFrom m coefficients.approximation coefficients.details

theorem inverse_forward (signal : Dyadic Int m) :
    inverse (forward signal) = signal := by
  induction signal with
  | leaf value => rfl
  | node left right ihLeft ihRight =>
      simp only [inverse, forward, total, detailTree, inverseFrom]
      have hLeft :
          ((total left + total right) + (total left - total right)) / 2 =
            total left := by
        omega
      have hRight :
          ((total left + total right) - (total left - total right)) / 2 =
            total right := by
        omega
      rw [hLeft, hRight]
      have ihLeft' :
          inverseFrom _ (total left) (detailTree left) = left := by
        simpa [inverse, forward] using ihLeft
      have ihRight' :
          inverseFrom _ (total right) (detailTree right) = right := by
        simpa [inverse, forward] using ihRight
      rw [ihLeft', ihRight']

theorem forward_injective : Function.Injective (@forward m) := by
  intro left right h
  have recovered := congrArg inverse h
  simpa [inverse_forward] using recovered

/-! ## Walsh--Hadamard Boolean-semantics transform

The Walsh transform uses the same butterfly with a different schedule.  At
each stage it combines corresponding coefficients from both halves, so a
single truth-table change is global rather than Haar-local.  The theorem below
establishes exact injectivity over integer truth tables without normalization.
-/

def Dyadic.zipWith (f : α → β → γ) :
    Dyadic α m → Dyadic β m → Dyadic γ m
  | .leaf left, .leaf right => .leaf (f left right)
  | .node left₁ right₁, .node left₂ right₂ =>
      .node (zipWith f left₁ left₂) (zipWith f right₁ right₂)

@[simp] theorem Dyadic.zipWith_leaf (f : α → β → γ)
    (left : α) (right : β) :
    Dyadic.zipWith f (.leaf left) (.leaf right) = .leaf (f left right) := rfl

@[simp] theorem Dyadic.zipWith_node (f : α → β → γ)
    (left₁ right₁ : Dyadic α m) (left₂ right₂ : Dyadic β m) :
    Dyadic.zipWith f (.node left₁ right₁) (.node left₂ right₂) =
      .node (Dyadic.zipWith f left₁ left₂)
        (Dyadic.zipWith f right₁ right₂) := rfl

def walshHadamard : Dyadic Int m → Dyadic Int m
  | .leaf value => .leaf value
  | .node left right =>
      let leftSpectrum := walshHadamard left
      let rightSpectrum := walshHadamard right
      .node
        (Dyadic.zipWith (fun a b => a + b) leftSpectrum rightSpectrum)
        (Dyadic.zipWith (fun a b => a - b) leftSpectrum rightSpectrum)

theorem dyadic_add_sub_injective
    (left₁ right₁ left₂ right₂ : Dyadic Int m)
    (hSum :
      Dyadic.zipWith (fun a b => a + b) left₁ right₁ =
        Dyadic.zipWith (fun a b => a + b) left₂ right₂)
    (hDifference :
      Dyadic.zipWith (fun a b => a - b) left₁ right₁ =
        Dyadic.zipWith (fun a b => a - b) left₂ right₂) :
    left₁ = left₂ ∧ right₁ = right₂ := by
  induction left₁ with
  | leaf leftValue₁ =>
      cases right₁ with
      | leaf rightValue₁ =>
          cases left₂ with
          | leaf leftValue₂ =>
              cases right₂ with
              | leaf rightValue₂ =>
                  simp only [Dyadic.zipWith_leaf] at hSum hDifference
                  injection hSum with hSumValue
                  injection hDifference with hDifferenceValue
                  constructor <;> simp only [Dyadic.leaf.injEq] <;> omega
  | node leftLeft₁ leftRight₁ ihLeft ihRight =>
      cases right₁ with
      | node rightLeft₁ rightRight₁ =>
          cases left₂ with
          | node leftLeft₂ leftRight₂ =>
              cases right₂ with
              | node rightLeft₂ rightRight₂ =>
                  simp only [Dyadic.zipWith_node] at hSum hDifference
                  injection hSum with _ hSumLeft hSumRight
                  injection hDifference with _ hDifferenceLeft hDifferenceRight
                  obtain ⟨hLeftLeft, hRightLeft⟩ :=
                    ihLeft rightLeft₁ leftLeft₂ rightLeft₂
                      hSumLeft hDifferenceLeft
                  obtain ⟨hLeftRight, hRightRight⟩ :=
                    ihRight rightRight₁ leftRight₂ rightRight₂
                      hSumRight hDifferenceRight
                  cases hLeftLeft
                  cases hRightLeft
                  cases hLeftRight
                  cases hRightRight
                  exact ⟨rfl, rfl⟩

theorem walshHadamard_injective :
    Function.Injective (@walshHadamard m) := by
  intro left right h
  induction left with
  | leaf leftValue =>
      cases right with
      | leaf rightValue =>
          simp only [walshHadamard] at h
          cases h
          rfl
  | node leftLeft leftRight ihLeft ihRight =>
      cases right with
      | node rightLeft rightRight =>
          simp only [walshHadamard] at h
          injection h with _ hSum hDifference
          obtain ⟨hLeftSpectrum, hRightSpectrum⟩ :=
            dyadic_add_sub_injective
              (walshHadamard leftLeft) (walshHadamard leftRight)
              (walshHadamard rightLeft) (walshHadamard rightRight)
              hSum hDifference
          have hLeft : leftLeft = rightLeft := ihLeft hLeftSpectrum
          have hRight : leftRight = rightRight := ihRight hRightSpectrum
          cases hLeft
          cases hRight
          rfl

/-! ## Exact energy scaling

The unnormalised butterfly is orthogonal up to the scalar factor `2`.
Consequently the depth-`m` Walsh transform multiplies squared energy by
`2^m`.  Dividing by `sqrt (2^m)` over `Real` would therefore give the usual
isometry; the executable fingerprint stays integral and records the exact
scaling law instead.
-/

def energy : Dyadic Int m → Int
  | .leaf value => value * value
  | .node left right => energy left + energy right

theorem butterfly_energy (a b : Int) :
    (a + b) * (a + b) + (a - b) * (a - b) =
      2 * (a * a + b * b) := by
  simp only [Int.mul_add, Int.mul_sub, Int.add_mul, Int.sub_mul]
  omega

theorem dyadic_add_sub_energy (left right : Dyadic Int m) :
    energy (Dyadic.zipWith (fun a b => a + b) left right) +
        energy (Dyadic.zipWith (fun a b => a - b) left right) =
      2 * (energy left + energy right) := by
  induction left with
  | leaf leftValue =>
      cases right with
      | leaf rightValue =>
          simp only [Dyadic.zipWith_leaf, energy]
          exact butterfly_energy leftValue rightValue
  | node leftLeft leftRight ihLeft ihRight =>
      cases right with
      | node rightLeft rightRight =>
          simp only [Dyadic.zipWith_node, energy]
          calc
            _ =
                (energy (Dyadic.zipWith (fun a b => a + b) leftLeft rightLeft) +
                  energy (Dyadic.zipWith (fun a b => a - b) leftLeft rightLeft)) +
                (energy (Dyadic.zipWith (fun a b => a + b) leftRight rightRight) +
                  energy (Dyadic.zipWith (fun a b => a - b) leftRight rightRight)) := by
                    omega
            _ = 2 * (energy leftLeft + energy rightLeft) +
                2 * (energy leftRight + energy rightRight) := by
                  rw [ihLeft rightLeft, ihRight rightRight]
            _ = 2 *
                (energy leftLeft + energy leftRight +
                  (energy rightLeft + energy rightRight)) := by
                    omega

def scale : Nat → Int
  | 0 => 1
  | m + 1 => 2 * scale m

theorem walshHadamard_energy (signal : Dyadic Int m) :
    energy (walshHadamard signal) = scale m * energy signal := by
  induction signal with
  | leaf value => simp only [walshHadamard, energy, scale, Int.one_mul]
  | @node m left right ihLeft ihRight =>
      simp only [walshHadamard, energy]
      calc
        _ = 2 *
            (energy (walshHadamard left) +
              energy (walshHadamard right)) :=
          dyadic_add_sub_energy (walshHadamard left) (walshHadamard right)
        _ = 2 * (scale m * energy left + scale m * energy right) := by
          rw [ihLeft, ihRight]
        _ = scale (m + 1) * (energy left + energy right) := by
          simp only [scale, Int.mul_add, Int.mul_assoc]

/-! ## Structural locality

Changing one child interval may change its ancestors and its own detail
subtree, but the sibling detail subtree is bitwise unchanged.  Iterating these
two one-step statements down a dyadic address gives the usual multiscale
locality lemma.
-/

theorem change_left_preserves_right_details
    (before after sibling : Dyadic Int m) :
    Details.right (detailTree (.node before sibling)) =
      Details.right (detailTree (.node after sibling)) := rfl

theorem change_right_preserves_left_details
    (sibling before after : Dyadic Int m) :
    Details.left (detailTree (.node sibling before)) =
      Details.left (detailTree (.node sibling after)) := rfl

/-! ## A four-channel operation trace

The tag and three operand channels avoid the ambiguity of scalar feature
packing.  Unused operands use `-1`, outside the nonnegative index range.
This is a canonical structural feature map for the present `X/CX/CCX`
blueprint, not yet the basis-state semantics of those gates.
-/

def opTag : QRCert.Blueprint.Op → Int
  | .x _ => 0
  | .cx _ _ => 1
  | .ccx _ _ _ => 2

def opArg1 : QRCert.Blueprint.Op → Int
  | .x q => q
  | .cx control _ => control
  | .ccx control1 _ _ => control1

def opArg2 : QRCert.Blueprint.Op → Int
  | .x _ => -1
  | .cx _ target => target
  | .ccx _ control2 _ => control2

def opArg3 : QRCert.Blueprint.Op → Int
  | .x _ => -1
  | .cx _ _ => -1
  | .ccx _ _ target => target

theorem op_channels_injective
    (left right : QRCert.Blueprint.Op)
    (hTag : opTag left = opTag right)
    (hArg1 : opArg1 left = opArg1 right)
    (hArg2 : opArg2 left = opArg2 right)
    (hArg3 : opArg3 left = opArg3 right) :
    left = right := by
  cases left <;> cases right <;>
    simp_all [opTag, opArg1, opArg2, opArg3] <;> omega

theorem op_arguments_injective
    (left right : QRCert.Blueprint.Op)
    (hArg1 : opArg1 left = opArg1 right)
    (hArg2 : opArg2 left = opArg2 right)
    (hArg3 : opArg3 left = opArg3 right) :
    left = right := by
  cases left <;> cases right <;>
    simp_all [opArg1, opArg2, opArg3] <;> omega

structure OpBlockFingerprint (m : Nat) where
  tag : Coefficients m
  arg1 : Coefficients m
  arg2 : Coefficients m
  arg3 : Coefficients m
  deriving Repr, DecidableEq

def opBlockFingerprint
    (block : Dyadic QRCert.Blueprint.Op m) : OpBlockFingerprint m :=
  { tag := forward (Dyadic.map opTag block)
    arg1 := forward (Dyadic.map opArg1 block)
    arg2 := forward (Dyadic.map opArg2 block)
    arg3 := forward (Dyadic.map opArg3 block) }

theorem opBlock_channels_ext
    (left right : Dyadic QRCert.Blueprint.Op m)
    (hTag : Dyadic.map opTag left = Dyadic.map opTag right)
    (hArg1 : Dyadic.map opArg1 left = Dyadic.map opArg1 right)
    (hArg2 : Dyadic.map opArg2 left = Dyadic.map opArg2 right)
    (hArg3 : Dyadic.map opArg3 left = Dyadic.map opArg3 right) :
    left = right := by
  induction left with
  | leaf leftOp =>
      cases right with
      | leaf rightOp =>
          simp only [Dyadic.map_leaf] at hTag hArg1 hArg2 hArg3
          injection hTag with hTagValue
          injection hArg1 with hArg1Value
          injection hArg2 with hArg2Value
          injection hArg3 with hArg3Value
          have hOp := op_channels_injective leftOp rightOp
            hTagValue hArg1Value hArg2Value hArg3Value
          cases hOp
          rfl
  | node leftLeft leftRight ihLeft ihRight =>
      cases right with
      | node rightLeft rightRight =>
          simp only [Dyadic.map_node] at hTag hArg1 hArg2 hArg3
          injection hTag with _ hTagLeft hTagRight
          injection hArg1 with _ hArg1Left hArg1Right
          injection hArg2 with _ hArg2Left hArg2Right
          injection hArg3 with _ hArg3Left hArg3Right
          have hLeft : leftLeft = rightLeft :=
            ihLeft rightLeft hTagLeft hArg1Left hArg2Left hArg3Left
          have hRight : leftRight = rightRight :=
            ihRight rightRight hTagRight hArg1Right hArg2Right hArg3Right
          cases hLeft
          cases hRight
          rfl

theorem opBlock_argument_channels_ext
    (left right : Dyadic QRCert.Blueprint.Op m)
    (hArg1 : Dyadic.map opArg1 left = Dyadic.map opArg1 right)
    (hArg2 : Dyadic.map opArg2 left = Dyadic.map opArg2 right)
    (hArg3 : Dyadic.map opArg3 left = Dyadic.map opArg3 right) :
    left = right := by
  induction left with
  | leaf leftOp =>
      cases right with
      | leaf rightOp =>
          simp only [Dyadic.map_leaf] at hArg1 hArg2 hArg3
          injection hArg1 with hArg1Value
          injection hArg2 with hArg2Value
          injection hArg3 with hArg3Value
          have hOp := op_arguments_injective leftOp rightOp
            hArg1Value hArg2Value hArg3Value
          cases hOp
          rfl
  | node leftLeft leftRight ihLeft ihRight =>
      cases right with
      | node rightLeft rightRight =>
          simp only [Dyadic.map_node] at hArg1 hArg2 hArg3
          injection hArg1 with _ hArg1Left hArg1Right
          injection hArg2 with _ hArg2Left hArg2Right
          injection hArg3 with _ hArg3Left hArg3Right
          have hLeft : leftLeft = rightLeft :=
            ihLeft rightLeft hArg1Left hArg2Left hArg3Left
          have hRight : leftRight = rightRight :=
            ihRight rightRight hArg1Right hArg2Right hArg3Right
          cases hLeft
          cases hRight
          rfl

theorem opBlockFingerprint_injective :
    Function.Injective (@opBlockFingerprint m) := by
  intro left right h
  have hTag :
      forward (Dyadic.map opTag left) = forward (Dyadic.map opTag right) :=
    congrArg OpBlockFingerprint.tag h
  have hArg1 :
      forward (Dyadic.map opArg1 left) = forward (Dyadic.map opArg1 right) :=
    congrArg OpBlockFingerprint.arg1 h
  have hArg2 :
      forward (Dyadic.map opArg2 left) = forward (Dyadic.map opArg2 right) :=
    congrArg OpBlockFingerprint.arg2 h
  have hArg3 :
      forward (Dyadic.map opArg3 left) = forward (Dyadic.map opArg3 right) :=
    congrArg OpBlockFingerprint.arg3 h
  exact opBlock_channels_ext left right
    (forward_injective hTag)
    (forward_injective hArg1)
    (forward_injective hArg2)
    (forward_injective hArg3)

/-! The `-1` sentinels make the tag channel redundant for exact identity. -/

structure CompactOpBlockFingerprint (m : Nat) where
  arg1 : Coefficients m
  arg2 : Coefficients m
  arg3 : Coefficients m
  deriving Repr, DecidableEq

def compactOpBlockFingerprint
    (block : Dyadic QRCert.Blueprint.Op m) : CompactOpBlockFingerprint m :=
  { arg1 := forward (Dyadic.map opArg1 block)
    arg2 := forward (Dyadic.map opArg2 block)
    arg3 := forward (Dyadic.map opArg3 block) }

theorem compactOpBlockFingerprint_injective :
    Function.Injective (@compactOpBlockFingerprint m) := by
  intro left right h
  have hArg1 :
      forward (Dyadic.map opArg1 left) = forward (Dyadic.map opArg1 right) :=
    congrArg CompactOpBlockFingerprint.arg1 h
  have hArg2 :
      forward (Dyadic.map opArg2 left) = forward (Dyadic.map opArg2 right) :=
    congrArg CompactOpBlockFingerprint.arg2 h
  have hArg3 :
      forward (Dyadic.map opArg3 left) = forward (Dyadic.map opArg3 right) :=
    congrArg CompactOpBlockFingerprint.arg3 h
  exact opBlock_argument_channels_ext left right
    (forward_injective hArg1)
    (forward_injective hArg2)
    (forward_injective hArg3)

/-! ## Concrete regression example -/

def exampleBlock : Dyadic QRCert.Blueprint.Op 2 :=
  .node
    (.node (.leaf (.x 0)) (.leaf (.cx 0 1)))
    (.node (.leaf (.ccx 0 1 2)) (.leaf (.x 3)))

example : (opBlockFingerprint exampleBlock).tag.approximation = 3 := by
  decide

end QRCert.Wavelet
