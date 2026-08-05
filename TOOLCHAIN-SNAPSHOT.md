# Verification toolchain snapshot

Audited 5 August 2026. This file distinguishes the versions QRCert actually
pins from newer releases that are merely visible upstream.

| Component | QRCert status | Exact revision or release | Reason |
|---|---|---|---|
| Lean | pinned | `v4.31.0` | Current Aeneas Lean backend pins this version. |
| Aeneas | bridge target | `daa85d7e89400fa978be83fedbc7e475a83f0889` | Current public `AeneasVerif/aeneas` head inspected for the bridge. |
| Charon | bridge target | `340b1af4df92608d0911fc2ba26eef3fd3a30ab4` | The exact `charon-pin` recorded by that Aeneas revision. |
| Charon Rust | extraction toolchain | `nightly-2026-06-01` | Exact nightly in Charon's `rust-toolchain`. |
| PyTorch | optional search backend | API tested by QRCert; not trusted | CUDA is acceleration only and generated witnesses are rechecked. |
| GitHub Actions | pinned CI inputs | Checkout `v7.0.1`, setup-python `v7.0.0`, lean-action `v1.5.0`, each by commit SHA | Floating action tags are excluded from the build boundary. |

Upstream had also published Lean `v4.32.2`, PyTorch `v2.13.0`, and Verus
`release/0.2026.08.02.b677dd5` by the audit date. QRCert does not claim
compatibility merely because a newer tag exists. In particular, moving Lean
ahead of Aeneas would make the planned generated-code bridge less reproducible,
not more current.

The bridge follows practices visible in current public Rust-verification work:

- keep Rust and generated Lean separate;
- pin a compatible Aeneas/Charon pair rather than two independent heads;
- do not commit `.llbc`;
- put hand proofs behind a stable module boundary; and
- regenerate generated Lean in CI and fail on drift.

CI actions are likewise pinned to immutable commits. Their release tags are
left in comments for readability, but a tag move cannot silently change the
workflow implementation.

Relevant upstream repositories:

- <https://github.com/AeneasVerif/aeneas>
- <https://github.com/AeneasVerif/charon>
- <https://github.com/coproduct-opensource/aeneas-ci>
- <https://github.com/opencsvnet/formal-aeneas>
- <https://github.com/runtimeverification/kernel-rust-verification-spike>
- <https://github.com/verus-lang/verus>
- <https://github.com/pytorch/pytorch>

These are implementation references, not endorsements and not part of the
trusted theorem base.
