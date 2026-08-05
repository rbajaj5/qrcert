# Rust, MIR, Charon, and Aeneas bridge

This repository now contains an extraction-oriented Rust implementation of the
fixed-byte QRCert checker in [`rust/qrcert-checker`](rust/qrcert-checker).  It is
an executable correspondence candidate, not yet a completed source-to-Lean
refinement proof.

## Pinned toolchain

[`bridge/toolchain.lock.toml`](bridge/toolchain.lock.toml) records the exact
Aeneas revision, its own Charon pin, the Rust nightly, the Lean version, and the
hashes of the official Linux release artifacts, extracted executables, and
Aeneas Lake manifest. The gate verifies the manifest both before and after
`lake update`. In particular:

- Aeneas `daa85d7e89400fa978be83fedbc7e475a83f0889` pins Charon
  `340b1af4df92608d0911fc2ba26eef3fd3a30ab4` in its
  [`charon-pin`](https://github.com/AeneasVerif/aeneas/blob/daa85d7e89400fa978be83fedbc7e475a83f0889/charon-pin).
- The Aeneas Lean backend pins Lean 4.31.0 in its
  [`lean-toolchain`](https://github.com/AeneasVerif/aeneas/blob/daa85d7e89400fa978be83fedbc7e475a83f0889/backends/lean/lean-toolchain).
- The compatible Charon revision pins Rust nightly 2026-06-01 in
  [`charon/rust-toolchain`](https://github.com/AeneasVerif/charon/blob/340b1af4df92608d0911fc2ba26eef3fd3a30ab4/charon/rust-toolchain).

Changing any one of these values creates a new verification configuration and
requires regeneration plus regression testing.

`bridge/extract.sh` is a reproducible Linux x86_64 gate. A clean local run
completed extraction and generated-Lean compilation for these pins, and a
separate GitHub Actions job runs the same cold gate alongside the independent
handwritten-Lean, Python, and Rust checks.

The clean August 5, 2026 run produced these normalized generated-Lean hashes:

| Generated file | SHA-256 |
|---|---|
| `Types.lean` | `113a0ba88d1d025c5aec6b8005610008fffbef946fa9190d5c549eac42e88afb` |
| `Funs.lean` | `d97e9a79f6db78cbcd53d06178ba04fe31def130dae9688a4e276483f9d3cb0b` |
| `Clauses/Clauses.lean` | `71dc4506f11df626474e5ca0f7a9ed236c81cfa2faf05bf83127cd055f0b9b72` |

The raw LLBC JSON is not assigned a reproducibility hash because Charon embeds
the destination path and serializes an auxiliary short-name map in an
order-sensitive form. Independent runs produced the same three generated Lean
hashes above.

## Which MIR Charon actually extracts

The recommended command is:

```text
charon cargo --preset=aeneas --mir promoted
```

The explicit `--mir promoted` documents the intended boundary; it is also the
current default for local-crate bodies.  The current Charon implementation
selects `mir_promoted` for that level and falls back to `optimized_mir` only
when the requested local body has been stolen or when only dependency MIR is
available.  See
[`get_mir.rs`](https://github.com/AeneasVerif/charon/blob/340b1af4df92608d0911fc2ba26eef3fd3a30ab4/charon/src/bin/charon-driver/translate/get_mir.rs).

An external `RUSTFLAGS="-Z mir-opt-level=0"` is not the security control.  The
Charon driver already sets `mir_opt_level = Some(0)`, enables MIR encoding, and
preserves undefined-behaviour checks internally; see
[`driver.rs`](https://github.com/AeneasVerif/charon/blob/340b1af4df92608d0911fc2ba26eef3fd3a30ab4/charon/src/bin/charon-driver/driver.rs).
For this checker, comparing `promoted` and `elaborated` extraction is more
informative than varying rustc optimization levels.  `--precise-drops` forces
at least elaborated MIR; the critical checker deliberately avoids custom drop
logic.

This distinction is about proof shape and tool coverage, not program meaning.
A correct Rust compiler must preserve behaviour across optimization levels.
Low-optimization MIR merely keeps the correspondence obligation easier to
inspect.  A compiler bug remains inside the trusted-computing-base assumptions
until a separate translation-validation result discharges it.

## Restricted Rust profile

The critical library is deliberately small:

- safe Rust only;
- no dynamic dispatch, FFI, custom `Drop`, async, macros that hide control
  flow, or external library calls in the parser;
- fixed-size circuit storage and explicit operation count;
- checked/fail-closed cursor and resource arithmetic;
- bounds and register-distinctness checks at parse time;
- exact input consumption; and
- deterministic errors for malformed input.

The host tests cover representative Lean regression vectors,
malformed/truncated payloads, every invalid opcode, targeted operand-bound and
distinctness cases, trailing-byte rejection, the maximum operation header, and
resource-claim agreement.  A separate differential test checks all 335,923
strings of length at most seven over a six-byte boundary-focused alphabet
against an independent reference decoder.  These tests can find divergence,
but are not a proof of translation correctness.

## Required refinement theorem

The bridge is complete only after the generated Aeneas functions are related
to the existing Lean model.  The central statement should have this shape:

```lean
theorem extracted_verifyResourceClaim_refines
    (bytes : RustByteSlice) (claimed : RustU32) :
    rustBytesRel bytes leanBytes ->
    extractedVerifyResourceClaim bytes claimed =
      .ok (QRCert.Reflection.verifyResourceClaim leanBytes claimed.toNat)
```

It decomposes into the following obligations:

1. byte-slice, fixed-array, opcode, circuit, error, and result representation
   relations;
2. parser-step refinement and exact cursor accounting;
3. success implies operand bounds and control/target separation;
4. failure and panic correspondence, including proof that every indexing and
   arithmetic assertion is unreachable on the accepted path;
5. checked finite-word cost agreement with `QRCert.Blueprint.costSpec`;
6. canonical reconstruction of every accepted byte string; and
7. composition with `QRCert.Reflection.verifyResourceClaim_sound`.

The final theorem should be proved about generated definitions, not a second
handwritten Lean transcription of the Rust source.

## Trust boundary

```text
restricted Rust source
  -- rustc MIR construction --> promoted MIR
  -- Charon --> LLBC
  -- Aeneas + local elaborator patch --> raw generated Lean
  -- unverified normalizer + handwritten termination clauses
       --> compiling generated Lean
  -- refinement proof --> QRCertBlueprint + ReflectionKernel
```

The last arrow is kernel checked. The preceding compiler, extraction, local
patch, normalization, and termination-clause steps are all inside the untrusted
translation boundary; successful compilation does not establish their semantic
preservation. Charon describes itself as alpha software,
states that it can incorrectly translate edge cases, and lists known
unsoundnesses and missing information in its
[`limitations`](https://github.com/AeneasVerif/charon/blob/340b1af4df92608d0911fc2ba26eef3fd3a30ab4/docs/limitations.md).
For that reason this project treats Charon/Aeneas as pinned, high-assurance but
untrusted translation steps and keeps differential tests in the regression
gate.

Even after the refinement proof, a production claim about an optimized RISC-V
or native binary still assumes or separately validates rustc/LLVM code
generation, linking, the runtime, and the target execution model.  SP1 and ZK
soundness/privacy are additional composition layers.
