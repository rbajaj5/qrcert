# QRCert fingerprint roadmap

This note separates the proved transform layer from possible coding and
cryptographic layers. It is a design ledger, not a claim that all listed layers
have been implemented.

## Current theorem boundary

| Layer | Status | What is established |
|---|---|---|
| Checked fixed-byte decoder | Lean-checked | Refinement, well-formedness, exact consumption, canonicity, injectivity, and checked cost agreement. |
| Integer Haar transform | Lean-checked | Exact reconstruction, injectivity, and dyadic sibling-locality. |
| Four-channel operation trace | Lean-checked | The `tag` and three operand channels uniquely determine every power-of-two `X`/`CX`/`CCX` block. |
| Integer Walsh--Hadamard transform | Lean-checked | Exact injectivity and energy scaling by `2^m`. |
| Lossy coefficient selection | Not implemented | Requires an explicit distortion or soundness theorem. |
| Cryptographic authentication | Not implemented | Requires a standard hash or MAC over a domain-separated canonical encoding. |
| Circuit semantics | Not implemented | Requires basis-state permutation/unitary semantics for the current fixed-width gates. |
| Growing-register semantics | Not implemented | A zero-ancilla allocation map should be proved isometric (`V†V = I`), not unitary onto the larger space. |

The exact transform is information preserving, so it cannot by itself compress
the trace or provide cryptographic collision resistance. A deployable
certificate can hash the canonical coefficient stream, but its security then
comes from the selected cryptographic primitive and its domain separation, not
from Haar or Walsh algebra.

## Candidate coding layers

### Reed--Muller

A truth table on `m` Boolean variables naturally has `2^m` entries, so the
Walsh transform is a useful coordinate system for Boolean semantics. A
Reed--Muller layer could certify that a Boolean function has degree at most
`r`, and standard parameters such as minimum distance can then support exact
error-detection statements.

Two qualifications are essential:

- affine Boolean phases have especially simple Walsh spectra, but low
  polynomial degree does **not** generally imply a sparse Walsh spectrum;
  nondegenerate quadratic phases can be spectrally flat;
- code membership and distance are coding statements, not cryptographic
  collision-resistance statements.

### Polar and Reed--Muller selection

Polar and Reed--Muller codes can be described using closely related binary
butterfly kernels after suitable choices of bit ordering and convention.
Their selection rules differ: reliability ordering for polar codes versus
monomial/degree ordering for Reed--Muller codes. A future formalization should
state the permutation convention explicitly before proving any equivalence.

### LDPC, convolutional LDPC, and spatial coupling

These are plausible outer reliability layers for storing or transmitting an
authenticated certificate. Their sparse parity checks can detect or correct
channel errors, and convolutional/spatial coupling can provide streaming and
boundary-seeded decoding structures. Threshold-saturation results concern
iterative decoding on specified channel ensembles; they do not show that an
LDPC syndrome is a secure circuit fingerprint.

## Proposed certificate pipeline

1. Decode the canonical fixed-byte circuit.
2. Partition or pad its operation trace with an explicit length/domain tag.
3. Produce exact Haar coefficients for localized audit and exact Walsh
   coefficients for Boolean spectral analysis.
4. Serialize the selected coefficients canonically.
5. Authenticate that serialization with a standard hash or MAC.
6. Optionally encode the authenticated payload with a separately verified
   Reed--Muller, polar, or LDPC reliability layer.

Each arrow needs its own refinement or security theorem. In particular, error
correction, transform invertibility, semantic equivalence, and collision
resistance are four different properties.

## Mathematical provenance

- I. Daubechies, *Ten Lectures on Wavelets*, SIAM, 1992,
  <https://doi.org/10.1137/1.9781611970104>.
- The related exact affine-spectrum and matroid hashing experiments are kept in
  [`rbajaj5/hypercube-probabilistic-estimates`](https://github.com/rbajaj5/hypercube-probabilistic-estimates).

The expression "Haar" here refers to the wavelet transform. It is distinct
from Haar probability measure on orthogonal or unitary groups in random-matrix
theory. Random-matrix universality may later inform robustness experiments,
but no such result is used by the present deterministic Lean proofs.
