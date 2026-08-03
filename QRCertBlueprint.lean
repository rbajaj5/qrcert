import Std

/-!
# QRCert checked-decoder refinement blueprint

This file models a deliberately small QRCert checker and proves its central
source-level obligations without axioms or placeholders:

* the public decoder checks bounds and register distinctness while parsing;
* a successful decode consumes the input exactly;
* success implies mathematical `WellFormedness`;
* a Boolean implementation refines the `Prop` specification; and
* a small finite-word cost model rejects overflow and agrees with an
  unbounded-`Nat` gate-count specification whenever the documented bound holds.

The byte format is intentionally tiny:

* `[nQubits, numOps, payload...]`;
* `0x00 q` encodes `X q`;
* `0x01 c t` encodes `CX c t`;
* `0x02 c1 c2 t` encodes `CCX c1 c2 t`.

All header fields and indices are bytes in this blueprint. A production format
can replace them with canonical multi-byte fields while preserving the same
proof decomposition.
-/

namespace QRCert.Blueprint

inductive Op where
  | x (q : Nat)
  | cx (control target : Nat)
  | ccx (control1 control2 target : Nat)
  deriving Repr, DecidableEq

structure Circuit where
  nQubits : Nat
  ops : List Op
  deriving Repr, DecidableEq

def Distinct3 (a b c : Nat) : Prop :=
  Not (a = b) /\ Not (a = c) /\ Not (b = c)

def WellFormedOp (n : Nat) : Op -> Prop
  | .x q => q < n
  | .cx control target =>
      control < n /\ target < n /\ Not (control = target)
  | .ccx control1 control2 target =>
      control1 < n /\ control2 < n /\ target < n /\
        Distinct3 control1 control2 target

instance instDecidableWellFormedOp (n : Nat) (op : Op) :
    Decidable (WellFormedOp n op) := by
  cases op <;> simp only [WellFormedOp, Distinct3] <;> infer_instance

def WellFormed (circuit : Circuit) : Prop :=
  forall op, op ∈ circuit.ops -> WellFormedOp circuit.nQubits op

/-! ## Boolean validation and its mathematical meaning -/

def checkOpImpl (n : Nat) : Op -> Bool
  | .x q => decide (q < n)
  | .cx control target =>
      decide (control < n) && decide (target < n) &&
        decide (control != target)
  | .ccx control1 control2 target =>
      decide (control1 < n) && decide (control2 < n) &&
        decide (target < n) && decide (control1 != control2) &&
        decide (control1 != target) && decide (control2 != target)

theorem checkOp_refines (n : Nat) (op : Op) :
    checkOpImpl n op = true <-> WellFormedOp n op := by
  cases op <;> simp [checkOpImpl, WellFormedOp, Distinct3, and_assoc]

def wellFormedImpl (circuit : Circuit) : Bool :=
  circuit.ops.all (checkOpImpl circuit.nQubits)

theorem wellFormed_refines (circuit : Circuit) :
    wellFormedImpl circuit = true <-> WellFormed circuit := by
  simp [wellFormedImpl, WellFormed, checkOp_refines]

/-! ## Raw syntax parsers

These functions only identify opcodes and field boundaries. They are kept
private to the proof decomposition: the public parsers below validate every
decoded operation before returning it.
-/

def parseOpRawSpec (bytes : List UInt8) : Option (Op × List UInt8) :=
  match bytes with
  | 0x00 :: q :: rest => some (.x q.toNat, rest)
  | 0x01 :: control :: target :: rest =>
      some (.cx control.toNat target.toNat, rest)
  | 0x02 :: control1 :: control2 :: target :: rest =>
      some (.ccx control1.toNat control2.toNat target.toNat, rest)
  | _ => none

def parseOpRawImpl (bytes : List UInt8) : Option (Op × List UInt8) :=
  match bytes with
  | opcode :: payload =>
      if opcode == 0x00 then
        match payload with
        | q :: rest => some (.x q.toNat, rest)
        | _ => none
      else if opcode == 0x01 then
        match payload with
        | control :: target :: rest =>
            some (.cx control.toNat target.toNat, rest)
        | _ => none
      else if opcode == 0x02 then
        match payload with
        | control1 :: control2 :: target :: rest =>
            some (.ccx control1.toNat control2.toNat target.toNat, rest)
        | _ => none
      else
        none
  | [] => none

theorem parseOpRaw_refines (bytes : List UInt8) :
    parseOpRawImpl bytes = parseOpRawSpec bytes := by
  cases bytes with
  | nil => rfl
  | cons opcode payload =>
      simp only [parseOpRawImpl]
      by_cases hx : opcode = 0x00
      · subst opcode
        cases payload <;> rfl
      · have hx' : (opcode == 0x00) = false := by simp [hx]
        rw [hx']
        by_cases hcx : opcode = 0x01
        · subst opcode
          cases payload with
          | nil => rfl
          | cons control rest => cases rest <;> rfl
        · have hcx' : (opcode == 0x01) = false := by simp [hcx]
          rw [hcx']
          by_cases hccx : opcode = 0x02
          · subst opcode
            cases payload with
            | nil => rfl
            | cons control1 rest1 =>
                cases rest1 with
                | nil => rfl
                | cons control2 rest2 => cases rest2 <;> rfl
          · have hccx' : (opcode == 0x02) = false := by simp [hccx]
            rw [hccx']
            cases opcode using UInt8.casesOn <;>
              simp_all [parseOpRawSpec]

/-! ## Checked public operation parsers -/

def parseOpSpec (n : Nat) (bytes : List UInt8) :
    Option (Op × List UInt8) :=
  match parseOpRawSpec bytes with
  | none => none
  | some (op, rest) =>
      if WellFormedOp n op then some (op, rest) else none

def parseOpImpl (n : Nat) (bytes : List UInt8) :
    Option (Op × List UInt8) :=
  match parseOpRawImpl bytes with
  | none => none
  | some (op, rest) =>
      if checkOpImpl n op = true then some (op, rest) else none

theorem parseOp_refines (n : Nat) (bytes : List UInt8) :
    parseOpImpl n bytes = parseOpSpec n bytes := by
  simp only [parseOpImpl, parseOpSpec, parseOpRaw_refines]
  cases parseOpRawSpec bytes with
  | none => rfl
  | some result =>
      rcases result with ⟨op, rest⟩
      change
        (if checkOpImpl n op = true then some (op, rest) else none) =
          (if WellFormedOp n op then some (op, rest) else none)
      by_cases hwf : WellFormedOp n op
      · have hcheck : checkOpImpl n op = true :=
          (checkOp_refines n op).2 hwf
        simp [hcheck, hwf]
      · have hcheck : Not (checkOpImpl n op = true) := by
          intro accepted
          exact hwf ((checkOp_refines n op).1 accepted)
        simp [hcheck, hwf]

theorem parseOpSpec_sound
    (n : Nat) (bytes : List UInt8) (op : Op) (rest : List UInt8)
    (h : parseOpSpec n bytes = some (op, rest)) :
    WellFormedOp n op := by
  simp only [parseOpSpec] at h
  cases hraw : parseOpRawSpec bytes with
  | none => simp [hraw] at h
  | some result =>
      rcases result with ⟨parsed, trailing⟩
      rw [hraw] at h
      change
        (if WellFormedOp n parsed then some (parsed, trailing) else none) =
          some (op, rest) at h
      by_cases hwf : WellFormedOp n parsed
      · simp only [if_pos hwf] at h
        have hpairs : (parsed, trailing) = (op, rest) :=
          Option.some.inj h
        have hop : parsed = op := congrArg Prod.fst hpairs
        cases hop
        exact hwf
      · simp [hwf] at h

/-! ## Checked multi-operation parsers -/

def parseOpsSpec (n : Nat) :
    Nat -> List UInt8 -> Option (List Op × List UInt8)
  | 0, bytes => some ([], bytes)
  | fuel + 1, bytes =>
      match parseOpSpec n bytes with
      | none => none
      | some (op, rest) =>
          match parseOpsSpec n fuel rest with
          | none => none
          | some (ops, trailing) => some (op :: ops, trailing)

def parseOpsImpl (n : Nat) :
    Nat -> List UInt8 -> List Op -> Option (List Op × List UInt8)
  | 0, bytes, acc => some (acc.reverse, bytes)
  | fuel + 1, bytes, acc =>
      match parseOpImpl n bytes with
      | none => none
      | some (op, rest) => parseOpsImpl n fuel rest (op :: acc)

theorem parseOps_refines
    (n fuel : Nat) (bytes : List UInt8) (acc : List Op) :
    parseOpsImpl n fuel bytes acc =
      (parseOpsSpec n fuel bytes).map
        (fun result => (acc.reverse ++ result.1, result.2)) := by
  induction fuel generalizing bytes acc with
  | zero => simp [parseOpsImpl, parseOpsSpec]
  | succ fuel ih =>
      simp only [parseOpsImpl, parseOpsSpec, parseOp_refines]
      cases hparse : parseOpSpec n bytes with
      | none => rfl
      | some result =>
          rcases result with ⟨op, rest⟩
          simp only [Option.map]
          rw [ih]
          cases hrest : parseOpsSpec n fuel rest with
          | none => rfl
          | some result =>
              rcases result with ⟨ops, trailing⟩
              simp [List.reverse_cons, List.append_assoc]

theorem parseOpsSpec_sound
    (n fuel : Nat) (bytes : List UInt8) (ops : List Op)
    (rest : List UInt8)
    (h : parseOpsSpec n fuel bytes = some (ops, rest)) :
    forall op, op ∈ ops -> WellFormedOp n op := by
  induction fuel generalizing bytes ops rest with
  | zero =>
      simp only [parseOpsSpec] at h
      have hpairs : ([], bytes) = (ops, rest) := Option.some.inj h
      have hops : [] = ops := congrArg Prod.fst hpairs
      cases hops
      intro op hmem
      cases hmem
  | succ fuel ih =>
      simp only [parseOpsSpec] at h
      cases hop : parseOpSpec n bytes with
      | none => simp [hop] at h
      | some parsed =>
          rcases parsed with ⟨op, tail⟩
          rw [hop] at h
          change
            (match parseOpsSpec n fuel tail with
              | none => none
              | some (tailOps, trailing) =>
                  some (op :: tailOps, trailing)) = some (ops, rest) at h
          cases hops : parseOpsSpec n fuel tail with
          | none => simp [hops] at h
          | some parsedOps =>
              rcases parsedOps with ⟨tailOps, trailing⟩
              rw [hops] at h
              change some (op :: tailOps, trailing) = some (ops, rest) at h
              have hpairs : (op :: tailOps, trailing) = (ops, rest) :=
                Option.some.inj h
              have hoplist : op :: tailOps = ops := congrArg Prod.fst hpairs
              cases hoplist
              intro candidate hmem
              cases hmem with
              | head =>
                  exact parseOpSpec_sound n bytes op tail hop
              | tail _ htail => exact ih tail tailOps trailing hops candidate htail

/-! ## Canonical encoder and parser reconstruction

The encoder below is the canonical encoder for this blueprint's fixed byte
format only: one-byte header fields and one-byte operation operands.  On
arbitrary mathematical `Circuit` values, `UInt8.ofNat` truncates modulo 256;
the canonicality theorem below is therefore deliberately stated for circuits
accepted by `deserializeSpec`.  Such circuits came from bytes in the first
place, so every encoded field is known to fit and is recovered exactly.
-/

def encodeOp : Op -> List UInt8
  | .x q => [0x00, UInt8.ofNat q]
  | .cx control target =>
      [0x01, UInt8.ofNat control, UInt8.ofNat target]
  | .ccx control1 control2 target =>
      [0x02, UInt8.ofNat control1, UInt8.ofNat control2,
        UInt8.ofNat target]

def encodeOps (ops : List Op) : List UInt8 :=
  ops.flatMap encodeOp

def encodeCircuit (circuit : Circuit) : List UInt8 :=
  UInt8.ofNat circuit.nQubits :: UInt8.ofNat circuit.ops.length ::
    encodeOps circuit.ops

-- Header fit is sufficient when paired with `WellFormed`: every operand is
-- then below `nQubits`, hence also representable by one byte.
def FixedByteEncodable (circuit : Circuit) : Prop :=
  circuit.nQubits < 2 ^ 8 /\ circuit.ops.length < 2 ^ 8

theorem uint8_ofNat_toNat_of_lt (value : Nat) (h : value < 2 ^ 8) :
    (UInt8.ofNat value).toNat = value := by
  change value % 2 ^ 8 = value
  exact Nat.mod_eq_of_lt h

theorem parseOpSpec_encodeOp
    (n : Nat) (op : Op) (rest : List UInt8)
    (hn : n < 2 ^ 8) (hwf : WellFormedOp n op) :
    parseOpSpec n (encodeOp op ++ rest) = some (op, rest) := by
  cases op with
  | x q =>
      have hq : q < 2 ^ 8 := Nat.lt_trans hwf hn
      simp [encodeOp, parseOpSpec, parseOpRawSpec,
        uint8_ofNat_toNat_of_lt q hq, hwf]
  | cx control target =>
      rcases hwf with ⟨hcontrol, htarget, hdistinct⟩
      have hcontrol' : control < 2 ^ 8 := Nat.lt_trans hcontrol hn
      have htarget' : target < 2 ^ 8 := Nat.lt_trans htarget hn
      have hwf' : WellFormedOp n (.cx control target) :=
        ⟨hcontrol, htarget, hdistinct⟩
      simp [encodeOp, parseOpSpec, parseOpRawSpec,
        uint8_ofNat_toNat_of_lt control hcontrol',
        uint8_ofNat_toNat_of_lt target htarget', hwf']
  | ccx control1 control2 target =>
      rcases hwf with ⟨hcontrol1, hcontrol2, htarget, hdistinct⟩
      have hcontrol1' : control1 < 2 ^ 8 := Nat.lt_trans hcontrol1 hn
      have hcontrol2' : control2 < 2 ^ 8 := Nat.lt_trans hcontrol2 hn
      have htarget' : target < 2 ^ 8 := Nat.lt_trans htarget hn
      have hwf' : WellFormedOp n (.ccx control1 control2 target) :=
        ⟨hcontrol1, hcontrol2, htarget, hdistinct⟩
      simp [encodeOp, parseOpSpec, parseOpRawSpec,
        uint8_ofNat_toNat_of_lt control1 hcontrol1',
        uint8_ofNat_toNat_of_lt control2 hcontrol2',
        uint8_ofNat_toNat_of_lt target htarget', hwf']

theorem parseOpRawSpec_reconstructs
    (bytes : List UInt8) (op : Op) (rest : List UInt8)
    (h : parseOpRawSpec bytes = some (op, rest)) :
    encodeOp op ++ rest = bytes := by
  cases bytes with
  | nil => simp [parseOpRawSpec] at h
  | cons opcode payload =>
      by_cases hx : opcode = 0x00
      · subst opcode
        cases payload with
        | nil => simp [parseOpRawSpec] at h
        | cons q trailing =>
            have hpairs : (.x q.toNat, trailing) = (op, rest) := by
              exact Option.some.inj h
            cases hpairs
            simp [encodeOp, UInt8.ofNat_toNat]
      · by_cases hcx : opcode = 0x01
        · subst opcode
          cases payload with
          | nil => simp [parseOpRawSpec] at h
          | cons control tail =>
              cases tail with
              | nil => simp [parseOpRawSpec] at h
              | cons target trailing =>
                  have hpairs :
                      (.cx control.toNat target.toNat, trailing) =
                        (op, rest) := by
                    exact Option.some.inj h
                  cases hpairs
                  simp [encodeOp, UInt8.ofNat_toNat]
        · by_cases hccx : opcode = 0x02
          · subst opcode
            cases payload with
            | nil => simp [parseOpRawSpec] at h
            | cons control1 tail1 =>
                cases tail1 with
                | nil => simp [parseOpRawSpec] at h
                | cons control2 tail2 =>
                    cases tail2 with
                    | nil => simp [parseOpRawSpec] at h
                    | cons target trailing =>
                        have hpairs :
                            (.ccx control1.toNat control2.toNat target.toNat,
                              trailing) = (op, rest) := by
                          exact Option.some.inj h
                        cases hpairs
                        simp [encodeOp, UInt8.ofNat_toNat]
          · have hnone : parseOpRawSpec (opcode :: payload) = none := by
              cases opcode using UInt8.casesOn <;>
                simp_all [parseOpRawSpec]
            rw [hnone] at h
            contradiction

theorem parseOpSpec_reconstructs
    (n : Nat) (bytes : List UInt8) (op : Op) (rest : List UInt8)
    (h : parseOpSpec n bytes = some (op, rest)) :
    encodeOp op ++ rest = bytes := by
  simp only [parseOpSpec] at h
  cases hraw : parseOpRawSpec bytes with
  | none => simp [hraw] at h
  | some parsed =>
      rcases parsed with ⟨parsedOp, parsedRest⟩
      rw [hraw] at h
      change
        (if WellFormedOp n parsedOp then
          some (parsedOp, parsedRest) else none) = some (op, rest) at h
      by_cases hwf : WellFormedOp n parsedOp
      · rw [if_pos hwf] at h
        have hpairs : (parsedOp, parsedRest) = (op, rest) :=
          Option.some.inj h
        cases hpairs
        exact parseOpRawSpec_reconstructs bytes op rest hraw
      · simp [hwf] at h

theorem parseOpsSpec_reconstructs
    (n fuel : Nat) (bytes : List UInt8) (ops : List Op)
    (rest : List UInt8)
    (h : parseOpsSpec n fuel bytes = some (ops, rest)) :
    encodeOps ops ++ rest = bytes /\ ops.length = fuel := by
  induction fuel generalizing bytes ops rest with
  | zero =>
      simp only [parseOpsSpec] at h
      have hpairs : ([], bytes) = (ops, rest) := Option.some.inj h
      cases hpairs
      simp [encodeOps]
  | succ fuel ih =>
      simp only [parseOpsSpec] at h
      cases hop : parseOpSpec n bytes with
      | none => simp [hop] at h
      | some parsed =>
          rcases parsed with ⟨op, tail⟩
          rw [hop] at h
          change
            (match parseOpsSpec n fuel tail with
              | none => none
              | some (tailOps, trailing) =>
                  some (op :: tailOps, trailing)) = some (ops, rest) at h
          cases hops : parseOpsSpec n fuel tail with
          | none => simp [hops] at h
          | some parsedOps =>
              rcases parsedOps with ⟨tailOps, trailing⟩
              rw [hops] at h
              obtain ⟨htail, hlength⟩ :=
                ih tail tailOps trailing hops
              have hpairs : (op :: tailOps, trailing) = (ops, rest) :=
                Option.some.inj h
              cases hpairs
              constructor
              · change (encodeOp op ++ encodeOps tailOps) ++ rest = bytes
                rw [List.append_assoc, htail]
                exact parseOpSpec_reconstructs n bytes op tail hop
              · simp [hlength]

theorem parseOpsSpec_encodeOps
    (n : Nat) (ops : List Op) (rest : List UInt8)
    (hn : n < 2 ^ 8)
    (hwf : forall op, op ∈ ops -> WellFormedOp n op) :
    parseOpsSpec n ops.length (encodeOps ops ++ rest) =
      some (ops, rest) := by
  induction ops generalizing rest with
  | nil => simp [parseOpsSpec, encodeOps]
  | cons op ops ih =>
      have hopWf : WellFormedOp n op := hwf op (by simp)
      have htailWf : forall candidate, candidate ∈ ops ->
          WellFormedOp n candidate := by
        intro candidate hmem
        exact hwf candidate (by simp [hmem])
      have hencode :
          encodeOps (op :: ops) ++ rest =
            encodeOp op ++ (encodeOps ops ++ rest) := by
        simp [encodeOps, List.append_assoc]
      rw [hencode]
      simp only [List.length_cons, parseOpsSpec]
      rw [parseOpSpec_encodeOp n op (encodeOps ops ++ rest) hn hopWf]
      simp only
      rw [ih rest htailWf]

/-! ## Canonical, exact-consumption deserializers -/

def deserializeSpec (bytes : List UInt8) : Option Circuit :=
  match bytes with
  | nQubits :: numOps :: payload =>
      match parseOpsSpec nQubits.toNat numOps.toNat payload with
      | some (ops, []) => some { nQubits := nQubits.toNat, ops }
      | _ => none
  | _ => none

def deserializeImpl (bytes : List UInt8) : Option Circuit :=
  match bytes with
  | nQubits :: numOps :: payload =>
      match parseOpsImpl nQubits.toNat numOps.toNat payload [] with
      | some (ops, []) => some { nQubits := nQubits.toNat, ops }
      | _ => none
  | _ => none

theorem deserialize_refines (bytes : List UInt8) :
    deserializeImpl bytes = deserializeSpec bytes := by
  cases bytes with
  | nil => rfl
  | cons nQubits rest =>
      cases rest with
      | nil => rfl
      | cons numOps payload =>
          simp only [deserializeImpl, deserializeSpec]
          rw [parseOps_refines]
          simp

theorem deserializeSpec_encode_of_fixedByteEncodable
    (circuit : Circuit)
    (henc : FixedByteEncodable circuit)
    (hwf : WellFormed circuit) :
    deserializeSpec (encodeCircuit circuit) = some circuit := by
  rcases henc with ⟨hn, hlength⟩
  have hnDecode : (UInt8.ofNat circuit.nQubits).toNat =
      circuit.nQubits := uint8_ofNat_toNat_of_lt circuit.nQubits hn
  have hlengthDecode : (UInt8.ofNat circuit.ops.length).toNat =
      circuit.ops.length :=
    uint8_ofNat_toNat_of_lt circuit.ops.length hlength
  simp only [encodeCircuit, deserializeSpec]
  rw [hnDecode, hlengthDecode]
  have hparse :
      parseOpsSpec circuit.nQubits circuit.ops.length
        (encodeOps circuit.ops) = some (circuit.ops, []) := by
    simpa using
      parseOpsSpec_encodeOps circuit.nQubits circuit.ops [] hn hwf
  rw [hparse]

theorem deserializeImpl_encode_of_fixedByteEncodable
    (circuit : Circuit)
    (henc : FixedByteEncodable circuit)
    (hwf : WellFormed circuit) :
    deserializeImpl (encodeCircuit circuit) = some circuit := by
  rw [deserialize_refines]
  exact deserializeSpec_encode_of_fixedByteEncodable circuit henc hwf

theorem deserializeSpec_exact_consumption
    (nQubits numOps : UInt8) (payload : List UInt8) (circuit : Circuit)
    (h : deserializeSpec (nQubits :: numOps :: payload) = some circuit) :
    exists ops,
      parseOpsSpec nQubits.toNat numOps.toNat payload = some (ops, []) := by
  simp only [deserializeSpec] at h
  cases hparse : parseOpsSpec nQubits.toNat numOps.toNat payload with
  | none => simp [hparse] at h
  | some parsed =>
      rcases parsed with ⟨ops, trailing⟩
      cases trailing with
      | nil => exact ⟨ops, rfl⟩
      | cons byte more => simp [hparse] at h

/-!
Accepted-byte canonicality is intentionally scoped to the fixed byte format
documented at the top of this file.  It says that every accepted byte string
is already the unique canonical encoding of its decoded circuit; it makes no
claim that every unconstrained mathematical `Circuit` is encodable.
-/

theorem deserializeSpec_accepted_canonical
    (bytes : List UInt8) (circuit : Circuit)
    (h : deserializeSpec bytes = some circuit) :
    encodeCircuit circuit = bytes := by
  cases bytes with
  | nil => simp [deserializeSpec] at h
  | cons nQubits rest =>
      cases rest with
      | nil => simp [deserializeSpec] at h
      | cons numOps payload =>
          simp only [deserializeSpec] at h
          cases hparse : parseOpsSpec nQubits.toNat numOps.toNat payload with
          | none => simp [hparse] at h
          | some parsed =>
              rcases parsed with ⟨ops, trailing⟩
              cases trailing with
              | cons byte more => simp [hparse] at h
              | nil =>
                  rw [hparse] at h
                  have hcircuit :
                      { nQubits := nQubits.toNat, ops := ops } = circuit :=
                    Option.some.inj h
                  cases hcircuit
                  obtain ⟨hreconstruct, hlength⟩ :=
                    parseOpsSpec_reconstructs nQubits.toNat numOps.toNat
                      payload ops [] hparse
                  have hpayload : encodeOps ops = payload := by
                    simpa using hreconstruct
                  simp [encodeCircuit, hlength, hpayload,
                    UInt8.ofNat_toNat]

theorem deserializeSpec_encode_on_image
    (bytes : List UInt8) (circuit : Circuit)
    (h : deserializeSpec bytes = some circuit) :
    deserializeSpec (encodeCircuit circuit) = some circuit := by
  rw [deserializeSpec_accepted_canonical bytes circuit h]
  exact h

theorem decode_encode_on_image
    (bytes : List UInt8) (circuit : Circuit)
    (h : deserializeSpec bytes = some circuit) :
    deserializeSpec (encodeCircuit circuit) = some circuit :=
  deserializeSpec_encode_on_image bytes circuit h

theorem deserialize_injective
    (bytes₁ bytes₂ : List UInt8) (circuit : Circuit)
    (h₁ : deserializeSpec bytes₁ = some circuit)
    (h₂ : deserializeSpec bytes₂ = some circuit) :
    bytes₁ = bytes₂ := by
  calc
    bytes₁ = encodeCircuit circuit :=
      (deserializeSpec_accepted_canonical bytes₁ circuit h₁).symm
    _ = bytes₂ :=
      deserializeSpec_accepted_canonical bytes₂ circuit h₂

theorem deserializeImpl_accepted_canonical
    (bytes : List UInt8) (circuit : Circuit)
    (h : deserializeImpl bytes = some circuit) :
    encodeCircuit circuit = bytes := by
  rw [deserialize_refines] at h
  exact deserializeSpec_accepted_canonical bytes circuit h

theorem deserializeImpl_injective
    (bytes₁ bytes₂ : List UInt8) (circuit : Circuit)
    (h₁ : deserializeImpl bytes₁ = some circuit)
    (h₂ : deserializeImpl bytes₂ = some circuit) :
    bytes₁ = bytes₂ := by
  calc
    bytes₁ = encodeCircuit circuit :=
      (deserializeImpl_accepted_canonical bytes₁ circuit h₁).symm
    _ = bytes₂ :=
      deserializeImpl_accepted_canonical bytes₂ circuit h₂

theorem deserializeSpec_accepted_ops_length_lt_byte_modulus
    (bytes : List UInt8) (circuit : Circuit)
    (h : deserializeSpec bytes = some circuit) :
    circuit.ops.length < 2 ^ 8 := by
  cases bytes with
  | nil => simp [deserializeSpec] at h
  | cons nQubits rest =>
      cases rest with
      | nil => simp [deserializeSpec] at h
      | cons numOps payload =>
          simp only [deserializeSpec] at h
          cases hparse : parseOpsSpec nQubits.toNat numOps.toNat payload with
          | none => simp [hparse] at h
          | some parsed =>
              rcases parsed with ⟨ops, trailing⟩
              cases trailing with
              | cons byte more => simp [hparse] at h
              | nil =>
                  rw [hparse] at h
                  have hcircuit :
                      { nQubits := nQubits.toNat, ops := ops } = circuit :=
                    Option.some.inj h
                  cases hcircuit
                  have hlength :=
                    (parseOpsSpec_reconstructs nQubits.toNat numOps.toNat
                      payload ops [] hparse).2
                  rw [hlength]
                  exact UInt8.toNat_lt numOps

theorem deserialize_implies_WellFormed
    (bytes : List UInt8) (circuit : Circuit)
    (h : deserializeSpec bytes = some circuit) :
    WellFormed circuit := by
  cases bytes with
  | nil => simp [deserializeSpec] at h
  | cons nQubits rest =>
      cases rest with
      | nil => simp [deserializeSpec] at h
      | cons numOps payload =>
          simp only [deserializeSpec] at h
          cases hparse : parseOpsSpec nQubits.toNat numOps.toNat payload with
          | none => simp [hparse] at h
          | some parsed =>
              rcases parsed with ⟨ops, trailing⟩
              cases trailing with
              | nil =>
                  simp [hparse] at h
                  cases h
                  exact parseOpsSpec_sound nQubits.toNat numOps.toNat
                    payload ops [] hparse
              | cons byte more => simp [hparse] at h

theorem deserializeImpl_sound
    (bytes : List UInt8) (circuit : Circuit)
    (h : deserializeImpl bytes = some circuit) :
    WellFormed circuit := by
  rw [deserialize_refines] at h
  exact deserialize_implies_WellFormed bytes circuit h

/-! ## Finite-word cost model

`U32Model` is intentionally a small mathematical stand-in for the checked
`u32` operations emitted by an extraction pipeline. It is not claimed to be
the literal Aeneas output. Its invariant makes the word range explicit and
its addition returns `none` exactly when the mathematical sum would overflow.
-/

def u32Modulus : Nat := 2 ^ 32
def maxCostExclusive : Nat := u32Modulus

structure U32Model where
  toNat : Nat
  isLt : toNat < u32Modulus
  deriving Repr, DecidableEq

namespace U32Model

def zero : U32Model :=
  ⟨0, by simp [u32Modulus]⟩

def one : U32Model :=
  ⟨1, by decide⟩

def checkedAdd (a b : U32Model) : Option U32Model :=
  if h : a.toNat + b.toNat < u32Modulus then
    some ⟨a.toNat + b.toNat, h⟩
  else
    none

theorem checkedAdd_success
    (a b : U32Model) (h : a.toNat + b.toNat < u32Modulus) :
    checkedAdd a b = some ⟨a.toNat + b.toNat, h⟩ := by
  simp [checkedAdd, h]

theorem checkedAdd_sound
    (a b result : U32Model)
    (h : checkedAdd a b = some result) :
    result.toNat = a.toNat + b.toNat := by
  simp only [checkedAdd] at h
  split at h
  next hlt =>
    cases h
    rfl
  next hnot => contradiction

end U32Model

def costOpSpec (_ : Op) : Nat := 1

def costSpec (ops : List Op) : Nat :=
  ops.foldl (fun acc op => acc + costOpSpec op) 0

theorem costSpec_eq_length (ops : List Op) :
    costSpec ops = ops.length := by
  simp [costSpec, costOpSpec]

def costFromModel : U32Model -> List Op -> Option U32Model
  | acc, [] => some acc
  | acc, _ :: ops =>
      match U32Model.checkedAdd acc U32Model.one with
      | none => none
      | some next => costFromModel next ops

def costExtractedModel (ops : List Op) : Option U32Model :=
  costFromModel U32Model.zero ops

theorem costFromModel_sound
    (ops : List Op) (acc : U32Model)
    (hbound : acc.toNat + ops.length < u32Modulus) :
    exists result,
      costFromModel acc ops = some result /\
      result.toNat = acc.toNat + ops.length := by
  induction ops generalizing acc with
  | nil =>
      refine ⟨acc, rfl, ?_⟩
      simp
  | cons op ops ih =>
      simp only [List.length_cons] at hbound
      have haddNat : acc.toNat + 1 < u32Modulus := by omega
      have hadd : acc.toNat + U32Model.one.toNat < u32Modulus := by
        simpa [U32Model.one] using haddNat
      let next : U32Model :=
        ⟨acc.toNat + U32Model.one.toNat, hadd⟩
      have hstep : U32Model.checkedAdd acc U32Model.one = some next := by
        simpa [next] using U32Model.checkedAdd_success acc U32Model.one hadd
      have htail : next.toNat + ops.length < u32Modulus := by
        dsimp [next]
        simp only [U32Model.one]
        omega
      obtain ⟨result, hrun, hvalue⟩ := ih next htail
      refine ⟨result, ?_, ?_⟩
      · simp [costFromModel, hstep, hrun]
      · rw [hvalue]
        simp [next, U32Model.one, Nat.add_comm,
          Nat.add_left_comm]

theorem costExtractedModel_sound
    (ops : List Op) (hbound : ops.length < maxCostExclusive) :
    exists result,
      costExtractedModel ops = some result /\
      result.toNat = costSpec ops := by
  have hbound' : U32Model.zero.toNat + ops.length < u32Modulus := by
    simpa [U32Model.zero, maxCostExclusive] using hbound
  obtain ⟨result, hrun, hvalue⟩ :=
    costFromModel_sound ops U32Model.zero hbound'
  refine ⟨result, hrun, ?_⟩
  simpa [U32Model.zero, costSpec_eq_length] using hvalue

theorem costExtractedModel_success_agrees
    (ops : List Op) (result : U32Model)
    (h : costExtractedModel ops = some result) :
    result.toNat = costSpec ops := by
  have helper : forall (tail : List Op) (acc out : U32Model),
      costFromModel acc tail = some out ->
      out.toNat = acc.toNat + tail.length := by
    intro tail
    induction tail with
    | nil =>
        intro acc out hrun
        simp [costFromModel] at hrun
        cases hrun
        simp
    | cons op tail ih =>
        intro acc out hrun
        simp only [costFromModel] at hrun
        cases hadd : U32Model.checkedAdd acc U32Model.one with
        | none => simp [hadd] at hrun
        | some next =>
            simp only [hadd] at hrun
            have htail := ih next out hrun
            have hnext := U32Model.checkedAdd_sound acc U32Model.one next hadd
            rw [htail, hnext]
            simp [U32Model.one, Nat.add_comm, Nat.add_left_comm]
  have hvalue := helper ops U32Model.zero result h
  simpa [U32Model.zero, costSpec_eq_length] using hvalue

/-!
For this fixed format, the one-byte operation-count header also supplies the
bound needed by the finite-word cost model.  Thus every successfully decoded
circuit has a successful exact-cost computation.
-/

theorem deserializeSpec_implies_cost_success
    (bytes : List UInt8) (circuit : Circuit)
    (h : deserializeSpec bytes = some circuit) :
    exists result,
      costExtractedModel circuit.ops = some result /\
      result.toNat = costSpec circuit.ops := by
  have hbyte : circuit.ops.length < 2 ^ 8 :=
    deserializeSpec_accepted_ops_length_lt_byte_modulus bytes circuit h
  have hword : circuit.ops.length < maxCostExclusive := by
    exact Nat.lt_trans hbyte (by decide)
  exact costExtractedModel_sound circuit.ops hword

theorem deserializeImpl_implies_cost_success
    (bytes : List UInt8) (circuit : Circuit)
    (h : deserializeImpl bytes = some circuit) :
    exists result,
      costExtractedModel circuit.ops = some result /\
      result.toNat = costSpec circuit.ops := by
  rw [deserialize_refines] at h
  exact deserializeSpec_implies_cost_success bytes circuit h

/-! ## Regression examples for concrete exploit shapes -/

def invalidOpcode : List UInt8 := [4, 1, 0xff, 0]
def outOfBoundsX : List UInt8 := [4, 1, 0x00, 4]
def zeroQubitX : List UInt8 := [0, 1, 0x00, 0]
def aliasedCX : List UInt8 := [4, 1, 0x01, 2, 2]
def aliasedCCX : List UInt8 := [4, 1, 0x02, 1, 2, 1]
def trailingBytes : List UInt8 := [4, 0, 0x00]
def validCCX : List UInt8 := [4, 1, 0x02, 0, 1, 2]

example : deserializeImpl invalidOpcode = none := by decide
example : deserializeImpl outOfBoundsX = none := by decide
example : deserializeImpl zeroQubitX = none := by decide
example : deserializeImpl aliasedCX = none := by decide
example : deserializeImpl aliasedCCX = none := by decide
example : deserializeImpl trailingBytes = none := by decide
example : deserializeImpl validCCX =
    some { nQubits := 4, ops := [.ccx 0 1 2] } := by decide

example : costExtractedModel [.x 0, .cx 0 1, .ccx 0 1 2] =
    some ⟨3, by decide⟩ := by decide

end QRCert.Blueprint
