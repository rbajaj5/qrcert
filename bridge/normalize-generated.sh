#!/usr/bin/env bash
set -euo pipefail

# Compatibility normalization for Aeneas daa85d7 + Lean 4.31.0.
#
# The pinned generator currently emits three syntactic forms that its pinned
# Lean backend does not accept together:
#   * `termination_by` uses the pre-Lean-4.6 binder/arrow form; and
#   * `partial_fixpoint` is emitted after an explicit well-founded clause.
# It also beta-reduces the two loop-counter binds from `let x ← lift e` to
# `let x := e`. In Aeneas, `lift e` is definitionally `Result.ok e` and
# `bind_ok` reduces this bind to the same continuation; retaining it as a bind
# needlessly generalizes away the equality required by the decreases proof.
#
# These edits are intended to preserve the elaborated definitions; in
# particular, the two bind rewrites rely on definitional reduction of Aeneas's
# `lift`/`bind_ok` path. This script is not verified and remains part of the
# untrusted translation boundary. The exact-count checks make it fail closed
# when Aeneas changes its output. The companion patch to Aeneas's custom `do`
# elaborator handles the generated dependent conditionals.

if [[ $# -ne 1 ]]; then
  echo "usage: $0 PATH/TO/QrcertChecker/Funs.lean" >&2
  exit 2
fi

funs=$1
if [[ ! -f "$funs" ]]; then
  echo "generated Lean file not found: $funs" >&2
  exit 2
fi

require_count() {
  local expected=$1
  local pattern=$2
  local actual
  actual=$(grep -c -- "$pattern" "$funs" || true)
  if [[ "$actual" != "$expected" ]]; then
    echo "expected $expected occurrence(s) of '$pattern'; found $actual" >&2
    exit 1
  fi
}

require_count 1 '^termination_by compute_checked_cost_loop circuit index cost error =>$'
require_count 1 '^  compute_checked_cost_loop_terminates circuit index cost error$'
require_count 1 '^termination_by decode_loop bytes n_qubits num_ops ops cursor op_index error =>$'
require_count 1 '^  decode_loop_terminates bytes n_qubits num_ops ops cursor op_index error$'
require_count 1 '^        let o2 ← lift (U8.checked_add index 1#u8)$'
require_count 1 '^        let o1 ← lift (U8.checked_add op_index 1#u8)$'
require_count 1 '^decreasing_by compute_checked_cost_loop_decreases circuit index cost error$'
require_count 1 '^  decode_loop_decreases bytes n_qubits num_ops ops cursor op_index error$'
require_count 2 '^partial_fixpoint$'

sed -i.bak \
  -e 's/^termination_by compute_checked_cost_loop circuit index cost error =>$/termination_by compute_checked_cost_loop_terminates circuit index cost error/' \
  -e '/^  compute_checked_cost_loop_terminates circuit index cost error$/d' \
  -e 's/^termination_by decode_loop bytes n_qubits num_ops ops cursor op_index error =>$/termination_by decode_loop_terminates bytes n_qubits num_ops ops cursor op_index error/' \
  -e '/^  decode_loop_terminates bytes n_qubits num_ops ops cursor op_index error$/d' \
  -e 's/^        let o2 ← lift (U8.checked_add index 1#u8)$/        let o2 := U8.checked_add index 1#u8/' \
  -e 's/^        let o1 ← lift (U8.checked_add op_index 1#u8)$/        let o1 := U8.checked_add op_index 1#u8/' \
  -e 's/^decreasing_by compute_checked_cost_loop_decreases circuit index cost error$/decreasing_by compute_checked_cost_loop_decreases circuit index cost error o2/' \
  -e 's/^  decode_loop_decreases bytes n_qubits num_ops ops cursor op_index error$/  decode_loop_decreases bytes n_qubits num_ops ops cursor op_index error o1/' \
  -e '/^partial_fixpoint$/d' \
  "$funs"
rm -f -- "$funs.bak"

require_count 1 '^termination_by compute_checked_cost_loop_terminates circuit index cost error$'
require_count 1 '^termination_by decode_loop_terminates bytes n_qubits num_ops ops cursor op_index error$'
require_count 1 '^        let o2 := U8.checked_add index 1#u8$'
require_count 1 '^        let o1 := U8.checked_add op_index 1#u8$'
require_count 1 '^decreasing_by compute_checked_cost_loop_decreases circuit index cost error o2$'
require_count 1 '^  decode_loop_decreases bytes n_qubits num_ops ops cursor op_index error o1$'
require_count 0 '^partial_fixpoint$'
