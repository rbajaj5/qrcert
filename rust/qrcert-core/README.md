# Extraction-oriented Rust core

This dependency-free crate implements the same fixed-byte decoder, validation,
exact-consumption rule, canonical encoder, and unit gate-cost loop as
`QRCertBlueprint.lean`.

```text
cargo test --manifest-path rust/qrcert-core/Cargo.toml
cargo fmt --manifest-path rust/qrcert-core/Cargo.toml -- --check
```

The library target is deliberately shaped for the current Charon/Aeneas
subset: safe Rust, plain enums and vectors, and unnested production loops.
Passing the Rust tests does **not**
establish refinement to the Lean specification. The next bridge milestone is:

1. extract LLBC with the exact Charon commit in `TOOLCHAIN-SNAPSHOT.md`;
2. translate it with the paired Aeneas commit;
3. commit the generated Lean behind a stable barrel module;
4. prove its success result equivalent to `deserializeImpl`; and
5. regenerate and reject `git diff` in CI whenever this crate changes.

Do not commit `.llbc`; it is a reproducible, Charon-version-coupled artifact.
