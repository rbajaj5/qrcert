#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
lock_file="$repo_root/bridge/toolchain.lock.toml"
out_dir=${QRCERT_BRIDGE_OUT:-"$repo_root/.bridge-work"}
cache_root=${XDG_CACHE_HOME:-"${HOME}/.cache"}
cache_base=${QRCERT_BRIDGE_CACHE:-"$cache_root/qrcert-bridge"}
export PATH="${CARGO_HOME:-${HOME}/.cargo}/bin:${ELAN_HOME:-${HOME}/.elan}/bin:$PATH"

lock_value() {
  local key=$1
  sed -n "s/^${key} = \"\([^\"]*\)\"$/\1/p" "$lock_file"
}

aeneas_revision=$(lock_value aeneas_revision)
aeneas_release=$(lock_value aeneas_release)
charon_revision=$(lock_value charon_revision)
rust_toolchain=$(lock_value rust_toolchain)
lean_toolchain=$(lock_value lean_toolchain)
charon_preset=$(lock_value charon_preset)
mir_level=$(lock_value mir_level)
aeneas_sha=$(lock_value aeneas_linux_x86_64_sha256)
aeneas_lean_sha=$(lock_value aeneas_lean_linux_x86_64_sha256)
aeneas_lake_manifest_sha=$(lock_value aeneas_lake_manifest_sha256)
aeneas_binary_sha=$(lock_value aeneas_binary_sha256)
charon_binary_sha=$(lock_value charon_binary_sha256)
charon_driver_binary_sha=$(lock_value charon_driver_binary_sha256)
aeneas_elab_original_sha=$(lock_value aeneas_elab_original_sha256)
aeneas_elab_patched_sha=$(lock_value aeneas_elab_patched_sha256)
aeneas_patch_sha=$(lock_value aeneas_patch_sha256)
normalizer_sha=$(lock_value normalizer_sha256)
clauses_sha=$(lock_value clauses_sha256)
mathlib_cache="$cache_base/mathlib-cache-${aeneas_revision}"

for value in "$aeneas_revision" "$aeneas_release" "$charon_revision" \
    "$rust_toolchain" "$lean_toolchain" "$charon_preset" "$mir_level" \
    "$aeneas_sha" "$aeneas_lean_sha" "$aeneas_lake_manifest_sha" \
    "$aeneas_binary_sha" "$charon_binary_sha" "$charon_driver_binary_sha" \
    "$aeneas_elab_original_sha" "$aeneas_elab_patched_sha" \
    "$aeneas_patch_sha" "$normalizer_sha" "$clauses_sha"; do
  if [[ -z "$value" ]]; then
    echo "incomplete bridge lock file: $lock_file" >&2
    exit 1
  fi
done

if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
  echo "the pinned bridge artifact currently supports Linux x86_64 only" >&2
  exit 2
fi

for command_name in curl sha256sum tar git rustup elan lake grep sed; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "required command not found: $command_name" >&2
    exit 2
  fi
done

mkdir -p -- "$cache_base" "$mathlib_cache" "$out_dir/QrcertChecker/Clauses"
archive="$cache_base/aeneas-linux-x86_64-${aeneas_revision}.tar.gz"
lean_archive="$cache_base/lean-build-aeneas-x86_64-${aeneas_revision}.tar.gz"
tools_dir="$cache_base/aeneas-${aeneas_revision}"
release_url="https://github.com/AeneasVerif/aeneas/releases/download/${aeneas_release}/aeneas-linux-x86_64.tar.gz"
lean_release_url="https://github.com/AeneasVerif/aeneas/releases/download/${aeneas_release}/lean-build-aeneas-x86_64-unknown-linux-gnu.tar.gz"
charon_pin_url="https://raw.githubusercontent.com/AeneasVerif/aeneas/${aeneas_revision}/charon-pin"

if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 3 --output "$archive" "$release_url"
fi
if [[ ! -f "$lean_archive" ]]; then
  curl --fail --location --retry 3 --output "$lean_archive" "$lean_release_url"
fi
printf '%s  %s\n' "$aeneas_sha" "$archive" | sha256sum --check --status
printf '%s  %s\n' "$aeneas_lean_sha" "$lean_archive" | \
  sha256sum --check --status
reported_charon_revision=$(curl --fail --location --retry 3 --silent \
  "$charon_pin_url" | sed -n 's/^\([0-9a-f]\{40\}\)$/\1/p')
if [[ "$reported_charon_revision" != "$charon_revision" ]]; then
  echo "Aeneas upstream Charon pin does not match the lock file" >&2
  exit 1
fi

if [[ ! -x "$tools_dir/aeneas" || ! -x "$tools_dir/charon" ]]; then
  if [[ -e "$tools_dir" ]]; then
    echo "incomplete tool cache exists; remove this exact path and retry:" >&2
    echo "  $tools_dir" >&2
    exit 1
  fi
  mkdir -p -- "$tools_dir"
  tar -xzf "$archive" -C "$tools_dir"
fi

printf '%s  %s\n' "$aeneas_binary_sha" "$tools_dir/aeneas" | \
  sha256sum --check --status
printf '%s  %s\n' "$charon_binary_sha" "$tools_dir/charon" | \
  sha256sum --check --status
printf '%s  %s\n' "$charon_driver_binary_sha" "$tools_dir/charon-driver" | \
  sha256sum --check --status

lean_backend="$tools_dir/backends/lean"
lean_manifest="$lean_backend/lake-manifest.json"
# Pin the standalone precompiled Lean backend artifact explicitly, even though
# the full release archive currently contains the same build tree.
tar -xzf "$lean_archive" -C "$lean_backend/.lake/build"
printf '%s  %s\n' "$aeneas_lake_manifest_sha" "$lean_manifest" | \
  sha256sum --check --status

reported_revision=$($tools_dir/aeneas -version | sed -n 's/^aeneas .*[- ]\([0-9a-f]\{7,40\}\)$/\1/p')
if [[ "$aeneas_revision" != "$reported_revision"* ]]; then
  echo "Aeneas binary revision does not match the lock file" >&2
  exit 1
fi

patch_file="$repo_root/bridge/aeneas-dependent-if.patch"
normalizer="$repo_root/bridge/normalize-generated.sh"
clauses="$repo_root/bridge/Clauses.lean"
elab_source="$lean_backend/Aeneas/Do/Elab.lean"
printf '%s  %s\n' "$aeneas_patch_sha" "$patch_file" | \
  sha256sum --check --status
printf '%s  %s\n' "$normalizer_sha" "$normalizer" | \
  sha256sum --check --status
printf '%s  %s\n' "$clauses_sha" "$clauses" | \
  sha256sum --check --status
read -r current_elab_sha _ < <(sha256sum "$elab_source")
if [[ "$current_elab_sha" == "$aeneas_elab_original_sha" ]]; then
  git -C "$tools_dir" apply --check "$patch_file"
  git -C "$tools_dir" apply "$patch_file"
elif [[ "$current_elab_sha" != "$aeneas_elab_patched_sha" ]]; then
  echo "cached Aeneas elaborator source has an unexpected hash" >&2
  exit 1
fi
printf '%s  %s\n' "$aeneas_elab_patched_sha" "$elab_source" | \
  sha256sum --check --status

rustup toolchain install "$rust_toolchain" --profile minimal \
  --component rust-src --component rustfmt --component clippy
if ! elan toolchain list | grep -Fxq "$lean_toolchain"; then
  elan toolchain install "$lean_toolchain"
fi

# Fetch the exact Mathlib dependency graph selected by Aeneas and its Lean pin,
# then rebuild only the patched elaborator module over the official Aeneas
# release archive.
mathlib_modules=(
  Mathlib.Algebra.Algebra.ZMod
  Mathlib.Algebra.Group.Basic
  Mathlib.Algebra.Order.Ring.Canonical
  Mathlib.Algebra.Order.Sub.Basic
  Mathlib.Algebra.Order.Sub.Defs
  Mathlib.Control.Monad.Cont
  Mathlib.Data.BitVec
  Mathlib.Data.Fin.Basic
  Mathlib.Data.Int.Cast.Basic
  Mathlib.Data.Int.Init
  Mathlib.Data.List.Defs
  Mathlib.Data.List.GetD
  Mathlib.Data.Nat.Basic
  Mathlib.Data.Nat.Bitwise
  Mathlib.Data.Nat.Cast.Basic
  Mathlib.Data.Nat.Log
  Mathlib.Data.ZMod.Basic
  Mathlib.Logic.Basic
  Mathlib.Order.Basic
  Mathlib.RingTheory.Int.Basic
  Mathlib.Tactic.Attr.Register
  Mathlib.Tactic.Basic
  Mathlib.Tactic.Core
  Mathlib.Tactic.DefEqTransformations
  Mathlib.Tactic.Linarith
  Mathlib.Tactic.OfNat
  Mathlib.Tactic.Ring
  Mathlib.Tactic.Ring.RingNF
  Mathlib.Tactic.Simproc.ExistsAndEq
  Mathlib.Tactic.Tauto
)
(
  cd "$lean_backend"
  # Isolate Mathlib's archive cache from any global cache.  The cache tool
  # otherwise attempts to unpack every archive present in ~/.cache/mathlib,
  # including modules unrelated to this bridge's explicit import roots.
  export MATHLIB_CACHE_DIR="$mathlib_cache"
  lake update
  printf '%s  %s\n' "$aeneas_lake_manifest_sha" "$lean_manifest" | \
    sha256sum --check --status
  cache_ready=false
  for attempt in 1 2 3; do
    if lake exe cache get "${mathlib_modules[@]}"; then
      cache_ready=true
      break
    fi
    echo "Mathlib cache attempt $attempt failed; retrying missing archives" >&2
  done
  if [[ "$cache_ready" != true ]]; then
    echo "failed to materialize the pinned Mathlib dependency cache" >&2
    exit 1
  fi
  lake env lean -R "$lean_backend" \
    -o "$lean_backend/.lake/build/lib/lean/Aeneas/Do/Elab.olean" \
    "$lean_backend/Aeneas/Do/Elab.lean"
)

(
  cd "$repo_root/rust/qrcert-checker"
  cargo +"$rust_toolchain" fmt --check
  cargo +"$rust_toolchain" clippy --all-targets --all-features -- -D warnings
  cargo +"$rust_toolchain" test --locked
  "$tools_dir/charon" cargo "--preset=$charon_preset" "--mir=$mir_level" \
    --dest-file "$out_dir/QrcertChecker.llbc"
)

"$tools_dir/aeneas" -backend lean \
  -dest "$out_dir/QrcertChecker" \
  -split-files -emit-json -loops-to-rec -decreases-clauses \
  "$out_dir/QrcertChecker.llbc"

cp -- "$clauses" \
  "$out_dir/QrcertChecker/Clauses/Clauses.lean"
bash "$normalizer" \
  "$out_dir/QrcertChecker/Funs.lean"

template="$out_dir/QrcertChecker/Clauses/Template.lean"
if [[ "$(grep -c 'sorry' "$template" || true)" != 2 ]]; then
  echo "unexpected Aeneas termination template shape" >&2
  exit 1
fi
rm -f -- "$template"

(
  cd "$lean_backend"
  export LEAN_PATH="$out_dir${LEAN_PATH:+:$LEAN_PATH}"
  lake env lean -R "$out_dir" \
    -o "$out_dir/QrcertChecker/Types.olean" \
    "$out_dir/QrcertChecker/Types.lean"
  lake env lean -R "$out_dir" \
    -o "$out_dir/QrcertChecker/Clauses/Clauses.olean" \
    "$out_dir/QrcertChecker/Clauses/Clauses.lean"
  lake env lean -R "$out_dir" \
    -o "$out_dir/QrcertChecker/Funs.olean" \
    "$out_dir/QrcertChecker/Funs.lean"
)

for forbidden in sorry admit unsafe partial partial_fixpoint; do
  if grep -RIn --include='*.lean' -w "$forbidden" "$out_dir/QrcertChecker"; then
    echo "generated Lean contains forbidden token: $forbidden" >&2
    exit 1
  fi
done
if grep -RInE --include='*.lean' '^[[:space:]]*axiom[[:space:]]' \
    "$out_dir/QrcertChecker"; then
  echo "generated Lean contains an external axiom" >&2
  exit 1
fi

echo "bridge extraction and total generated-Lean compilation succeeded"
echo "generated Lean SHA-256 (raw LLBC embeds path/order metadata):"
sha256sum \
  "$out_dir/QrcertChecker/Types.lean" \
  "$out_dir/QrcertChecker/Funs.lean" \
  "$out_dir/QrcertChecker/Clauses/Clauses.lean"
