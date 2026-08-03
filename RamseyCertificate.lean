import Std

/-!
# A reflected Ramsey lower-bound certificate

An external program (including a GPU search) may propose the bit matrix in a
`GraphCertificate`.  The proposal is untrusted.  `verify` checks the matrix and
exhaustively checks its `k`-vertex subsets.  The theorem `verify_sound` turns a
successful Boolean computation into the proposition that the represented
two-colouring has no monochromatic clique of size `k`.

The executable example is the five-cycle colouring of `K_5`.  It certifies the
classical lower bound `R(3,3) > 5`: neither colour contains a triangle.
-/

namespace QRCert.Ramsey

/-- A row-major Boolean adjacency matrix.  `true` and `false` are the two
colours of an edge of the complete graph. -/
structure GraphCertificate where
  vertexCount : Nat
  colours : List Bool
  deriving Repr, DecidableEq

/-- Interpret the canonical edge-list payload emitted by
`tools/ramsey_gpu.py`.  Parsing the JSON envelope is intentionally a separate
obligation; once the list is present in Lean, this definition fixes its graph
semantics. -/
def GraphCertificate.ofRedEdges
    (vertexCount : Nat) (redEdges : List (Nat × Nat)) : GraphCertificate :=
  { vertexCount
    colours := (List.range vertexCount).flatMap (fun u =>
      (List.range vertexCount).map (fun v =>
        decide ((u, v) ∈ redEdges ∨ (v, u) ∈ redEdges))) }

/-- Total lookup.  A short matrix reads as `false`, but `graphWellFormedB`
rejects every matrix whose length is not exactly `vertexCount ^ 2`. -/
def GraphCertificate.colour (g : GraphCertificate) (u v : Nat) : Bool :=
  g.colours[u * g.vertexCount + v]?.getD false

/-- All words of a fixed length over a finite alphabet.  Enumerating ordered
words makes completeness especially transparent; repeated vertices are later
ignored by the checker. -/
def words {α : Type} (alphabet : List α) : Nat → List (List α)
  | 0 => [[]]
  | k + 1 => alphabet.flatMap (fun x =>
      (words alphabet k).map (fun tail => x :: tail))

theorem mem_words_iff {α : Type} (alphabet : List α) (k : Nat)
    (ys : List α) :
    ys ∈ words alphabet k ↔
      ys.length = k ∧ ∀ y ∈ ys, y ∈ alphabet := by
  induction k generalizing ys with
  | zero => cases ys <;> simp [words]
  | succ k ih =>
      cases ys with
      | nil => simp [words]
      | cons y ys =>
          simp [words, ih, and_left_comm, and_comm, and_assoc]

/-- Every pair in `vertices` has the requested colour. -/
def pairwiseColourB (g : GraphCertificate) (wanted : Bool) : List Nat → Bool
  | [] => true
  | u :: us =>
      us.all (fun v => g.colour u v == wanted) &&
        pairwiseColourB g wanted us

def PairwiseColour (g : GraphCertificate) (wanted : Bool) : List Nat → Prop
  | [] => True
  | u :: us =>
      (∀ v ∈ us, g.colour u v = wanted) ∧ PairwiseColour g wanted us

def monochromaticB (g : GraphCertificate) (vertices : List Nat) : Bool :=
  pairwiseColourB g true vertices || pairwiseColourB g false vertices

def Monochromatic (g : GraphCertificate) (vertices : List Nat) : Prop :=
  PairwiseColour g true vertices ∨ PairwiseColour g false vertices

/-- The mathematical statement is independent of the enumeration routine: no
list of `k` distinct, in-range vertices is monochromatic. -/
def NoMonochromaticClique (g : GraphCertificate) (k : Nat) : Prop :=
  ∀ vertices : List Nat,
    vertices.length = k →
    vertices.Nodup →
    (∀ v ∈ vertices, v < g.vertexCount) →
    ¬ Monochromatic g vertices

/-- Matrix shape, irreflexivity, and symmetry. -/
def GraphWellFormed (g : GraphCertificate) : Prop :=
  g.colours.length = g.vertexCount * g.vertexCount ∧
  (∀ u < g.vertexCount, g.colour u u = false) ∧
  (∀ u < g.vertexCount, ∀ v < g.vertexCount,
    g.colour u v = g.colour v u)

def graphWellFormedB (g : GraphCertificate) : Bool :=
  decide (g.colours.length = g.vertexCount * g.vertexCount) &&
    ((List.range g.vertexCount).all (fun u => g.colour u u == false) &&
      (List.range g.vertexCount).all (fun u =>
        (List.range g.vertexCount).all (fun v =>
          g.colour u v == g.colour v u)))

def candidateSafeB (g : GraphCertificate) (vertices : List Nat) : Bool :=
  !decide vertices.Nodup || !(monochromaticB g vertices)

def noMonochromaticCliqueB (g : GraphCertificate) (k : Nat) : Bool :=
  (words (List.range g.vertexCount) k).all (candidateSafeB g)

/-- The small trusted checker.  Certificate search is deliberately outside
this function and may be parallel, heuristic, or GPU-accelerated. -/
def verify (g : GraphCertificate) (k : Nat) : Bool :=
  graphWellFormedB g && noMonochromaticCliqueB g k

theorem pairwiseColourB_refines
    (g : GraphCertificate) (wanted : Bool) (vertices : List Nat) :
    pairwiseColourB g wanted vertices = true ↔
      PairwiseColour g wanted vertices := by
  induction vertices with
  | nil => simp [pairwiseColourB, PairwiseColour]
  | cons u us ih =>
      simp [pairwiseColourB, PairwiseColour, ih]

theorem monochromaticB_refines
    (g : GraphCertificate) (vertices : List Nat) :
    monochromaticB g vertices = true ↔ Monochromatic g vertices := by
  simp [monochromaticB, Monochromatic, pairwiseColourB_refines]

theorem monochromaticB_false_refines
    (g : GraphCertificate) (vertices : List Nat) :
    monochromaticB g vertices = false ↔ ¬ Monochromatic g vertices := by
  constructor
  · intro hfalse hmono
    have htrue := (monochromaticB_refines g vertices).2 hmono
    simp [hfalse] at htrue
  · intro hnot
    cases h : monochromaticB g vertices with
    | false => rfl
    | true => exact False.elim (hnot ((monochromaticB_refines g vertices).1 h))

theorem candidateSafeB_refines
    (g : GraphCertificate) (vertices : List Nat) :
    candidateSafeB g vertices = true ↔
      (vertices.Nodup → ¬ Monochromatic g vertices) := by
  constructor
  · intro hb hnodup
    have hor : ¬ vertices.Nodup ∨ ¬ Monochromatic g vertices := by
      simpa [candidateSafeB, monochromaticB_false_refines] using hb
    exact hor.resolve_left (not_not_intro hnodup)
  · intro himp
    have hor : ¬ vertices.Nodup ∨ ¬ Monochromatic g vertices := by
      by_cases hnodup : vertices.Nodup
      · exact Or.inr (himp hnodup)
      · exact Or.inl hnodup
    simpa [candidateSafeB, monochromaticB_false_refines] using hor

theorem graphWellFormedB_refines (g : GraphCertificate) :
    graphWellFormedB g = true ↔ GraphWellFormed g := by
  simp [graphWellFormedB, GraphWellFormed]

theorem noMonochromaticCliqueB_refines (g : GraphCertificate) (k : Nat) :
    noMonochromaticCliqueB g k = true ↔ NoMonochromaticClique g k := by
  constructor
  · intro h vertices hlength hnodup hbounds
    have hall : ∀ candidate ∈ words (List.range g.vertexCount) k,
        candidateSafeB g candidate = true := by
      simpa [noMonochromaticCliqueB] using h
    have hmem : vertices ∈ words (List.range g.vertexCount) k :=
      (mem_words_iff (List.range g.vertexCount) k vertices).2
        ⟨hlength, by simpa using hbounds⟩
    exact (candidateSafeB_refines g vertices).1 (hall vertices hmem) hnodup
  · intro h
    simp only [noMonochromaticCliqueB, List.all_eq_true]
    intro vertices hmem
    apply (candidateSafeB_refines g vertices).2
    intro hnodup
    have hshape :=
      (mem_words_iff (List.range g.vertexCount) k vertices).1 hmem
    exact h vertices hshape.1 hnodup (by simpa using hshape.2)

/-- Curry--Howard endpoint: checker acceptance constructs both mathematical
facts.  No property of the certificate generator is assumed. -/
theorem verify_sound (g : GraphCertificate) (k : Nat) :
    verify g k = true → GraphWellFormed g ∧ NoMonochromaticClique g k := by
  simp [verify, graphWellFormedB_refines, noMonochromaticCliqueB_refines]

/-! ## Executable certificate: the 5-cycle -/

def cycle5RedEdges : List (Nat × Nat) :=
  [(0, 1), (0, 4), (1, 2), (2, 3), (3, 4)]

def cycle5 : GraphCertificate :=
  .ofRedEdges 5 cycle5RedEdges

/-- Kernel-reduced acceptance of the concrete certificate. -/
example : verify cycle5 3 = true := by decide

/-- The complete reflected result for the concrete certificate. -/
theorem cycle5_certificate_sound :
    GraphWellFormed cycle5 ∧ NoMonochromaticClique cycle5 3 :=
  verify_sound cycle5 3 (by decide)

/-- The accepted certificate yields the proposition used in a Ramsey
lower-bound argument. -/
theorem cycle5_has_no_monochromatic_triangle :
    NoMonochromaticClique cycle5 3 :=
  cycle5_certificate_sound.2

end QRCert.Ramsey
