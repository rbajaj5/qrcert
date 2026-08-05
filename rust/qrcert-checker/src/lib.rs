#![no_std]
#![forbid(unsafe_code)]
#![doc = r"
Restricted-Rust implementation of the fixed-byte `QRCert` blueprint.

The accepted format is exactly the one modeled by `QRCertBlueprint.lean`:

- `[n_qubits, num_ops, payload...]`;
- `0x00 q` encodes `X q`;
- `0x01 control target` encodes `CX control target`;
- `0x02 control1 control2 target` encodes `CCX control1 control2 target`.

Every operand is checked against `n_qubits`, controls and targets must be
distinct, and successful decoding consumes the input exactly. The critical
library is `no_std`, has no dependencies, allocates no heap memory, contains no
unsafe code, and rejects every checked-arithmetic failure.

This source shape is intentionally conservative for Charon/Aeneas extraction.
The Lean refinement proof connecting this implementation to the existing pure
specification remains a separate obligation.
"]

/// Maximum operation count representable by the one-byte header.
pub const MAX_OPS: u8 = u8::MAX;

// One extra slot makes the storage bound strict for every `u8` index. The
// serialized format still admits at most 255 operations.
const STORAGE_CAPACITY: usize = 256;

/// A gate in the current fixed-byte circuit fragment.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Op {
    /// Single-qubit X gate.
    X { q: u8 },
    /// Controlled X gate.
    Cx { control: u8, target: u8 },
    /// Doubly-controlled X gate.
    Ccx {
        control1: u8,
        control2: u8,
        target: u8,
    },
}

/// Identifies an operand in a structured decoding error.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OperandRole {
    Qubit,
    Control,
    Control1,
    Control2,
    Target,
}

/// Identifies the byte that was missing from a truncated operation.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ByteField {
    Opcode,
    Qubit,
    Control,
    Control1,
    Control2,
    Target,
}

/// Fail-closed errors from the canonical decoder.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DecodeError {
    /// Fewer than two header bytes were supplied.
    HeaderTooShort { actual_len: usize },
    /// An operation ended before all of its bytes were present.
    UnexpectedEnd { op_index: u8, field: ByteField },
    /// The opcode is not part of the current X/CX/CCX format.
    InvalidOpcode { op_index: u8, opcode: u8 },
    /// A parsed operand is not strictly below `n_qubits`.
    OperandOutOfBounds {
        op_index: u8,
        role: OperandRole,
        value: u8,
        n_qubits: u8,
    },
    /// Two roles that must be distinct contain the same qubit.
    DuplicateOperand {
        op_index: u8,
        first: OperandRole,
        second: OperandRole,
        value: u8,
    },
    /// Bytes remained after exactly `num_ops` operations were parsed.
    TrailingBytes { count: usize },
    /// A cursor or operation counter failed checked addition.
    CounterOverflow,
    /// An operation would exceed the fixed storage capacity.
    StorageCapacityExceeded,
}

/// Fail-closed errors from the finite-word cost calculation.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CostError {
    /// The public `u32` cost accumulator overflowed.
    CostOverflow,
    /// The operation counter failed checked addition.
    CounterOverflow,
    /// A private circuit invariant did not match fixed storage.
    StorageCapacityExceeded,
}

/// Errors exposed by the resource-claim endpoint.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VerifyError {
    Decode(DecodeError),
    Cost(CostError),
    ClaimedCostMismatch { claimed: u32, actual: u32 },
}

/// Fixed-capacity decoded circuit. Private fields preserve its invariants.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Circuit {
    n_qubits: u8,
    num_ops: u8,
    ops: [Op; STORAGE_CAPACITY],
}

impl Circuit {
    /// Number of qubits declared by the header.
    #[must_use]
    pub const fn n_qubits(&self) -> u8 {
        self.n_qubits
    }

    /// Number of operations declared by the header and successfully decoded.
    #[must_use]
    pub const fn num_ops(&self) -> u8 {
        self.num_ops
    }

    /// Returns a decoded operation when `index < num_ops`.
    #[must_use]
    #[allow(clippy::manual_map)] // Explicit dereference avoids an opaque extraction helper.
    pub fn op(&self, index: u8) -> Option<Op> {
        if index >= self.num_ops {
            return None;
        }
        match self.ops.get(usize::from(index)) {
            Some(op) => Some(*op),
            None => None,
        }
    }

    /// Calculate the current unit-weight gate cost. The loop lives in the
    /// free function so Aeneas emits a portable, unqualified decreases-tactic
    /// name; this method preserves the ergonomic public API.
    ///
    /// # Errors
    ///
    /// Propagates checked-arithmetic or fixed-storage invariant failures from
    /// [`compute_checked_cost`].
    pub fn checked_cost(&self) -> Result<u32, CostError> {
        compute_checked_cost(self)
    }
}

/// Calculate the current unit-weight gate cost using checked `u32`
/// arithmetic. This deliberately traverses the decoded operations rather than
/// trusting the header as the final resource report.
///
/// # Errors
///
/// Fails closed if checked addition fails or if the private fixed-storage
/// invariant is violated.
pub fn compute_checked_cost(circuit: &Circuit) -> Result<u32, CostError> {
    let mut index = 0_u8;
    let mut cost = 0_u32;
    let mut error = None;

    while index < circuit.num_ops {
        match circuit.ops.get(usize::from(index)) {
            None => {
                error = Some(CostError::StorageCapacityExceeded);
                index = circuit.num_ops;
            }
            Some(op) => match cost.checked_add(cost_op(*op)) {
                None => {
                    error = Some(CostError::CostOverflow);
                    index = circuit.num_ops;
                }
                Some(next_cost) => match index.checked_add(1) {
                    None => {
                        error = Some(CostError::CounterOverflow);
                        index = circuit.num_ops;
                    }
                    Some(next_index) => {
                        cost = next_cost;
                        index = next_index;
                    }
                },
            },
        }
    }

    match error {
        Some(error) => Err(error),
        None => Ok(cost),
    }
}

/// Public facts returned only after a resource claim is checked.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ResourceReport {
    pub n_qubits: u8,
    pub num_ops: u8,
    pub cost: u32,
}

/// Unit cost in the current Lean blueprint.
#[must_use]
pub const fn cost_op(_op: Op) -> u32 {
    1
}

fn read_byte(
    bytes: &[u8],
    cursor: &mut usize,
    op_index: u8,
    field: ByteField,
) -> Result<u8, DecodeError> {
    let value = match bytes.get(*cursor) {
        Some(value) => *value,
        None => return Err(DecodeError::UnexpectedEnd { op_index, field }),
    };
    *cursor = match cursor.checked_add(1) {
        Some(next) => next,
        None => return Err(DecodeError::CounterOverflow),
    };
    Ok(value)
}

fn require_in_bounds(
    value: u8,
    n_qubits: u8,
    op_index: u8,
    role: OperandRole,
) -> Result<(), DecodeError> {
    if value < n_qubits {
        Ok(())
    } else {
        Err(DecodeError::OperandOutOfBounds {
            op_index,
            role,
            value,
            n_qubits,
        })
    }
}

fn require_distinct(
    first_value: u8,
    first: OperandRole,
    second_value: u8,
    second: OperandRole,
    op_index: u8,
) -> Result<(), DecodeError> {
    if first_value == second_value {
        Err(DecodeError::DuplicateOperand {
            op_index,
            first,
            second,
            value: first_value,
        })
    } else {
        Ok(())
    }
}

fn parse_op(
    bytes: &[u8],
    cursor: &mut usize,
    n_qubits: u8,
    op_index: u8,
) -> Result<Op, DecodeError> {
    let opcode = read_byte(bytes, cursor, op_index, ByteField::Opcode)?;

    match opcode {
        0x00 => {
            let q = read_byte(bytes, cursor, op_index, ByteField::Qubit)?;
            require_in_bounds(q, n_qubits, op_index, OperandRole::Qubit)?;
            Ok(Op::X { q })
        }
        0x01 => {
            let control = read_byte(bytes, cursor, op_index, ByteField::Control)?;
            let target = read_byte(bytes, cursor, op_index, ByteField::Target)?;
            require_in_bounds(control, n_qubits, op_index, OperandRole::Control)?;
            require_in_bounds(target, n_qubits, op_index, OperandRole::Target)?;
            require_distinct(
                control,
                OperandRole::Control,
                target,
                OperandRole::Target,
                op_index,
            )?;
            Ok(Op::Cx { control, target })
        }
        0x02 => {
            let control1 = read_byte(bytes, cursor, op_index, ByteField::Control1)?;
            let control2 = read_byte(bytes, cursor, op_index, ByteField::Control2)?;
            let target = read_byte(bytes, cursor, op_index, ByteField::Target)?;
            require_in_bounds(control1, n_qubits, op_index, OperandRole::Control1)?;
            require_in_bounds(control2, n_qubits, op_index, OperandRole::Control2)?;
            require_in_bounds(target, n_qubits, op_index, OperandRole::Target)?;
            require_distinct(
                control1,
                OperandRole::Control1,
                control2,
                OperandRole::Control2,
                op_index,
            )?;
            require_distinct(
                control1,
                OperandRole::Control1,
                target,
                OperandRole::Target,
                op_index,
            )?;
            require_distinct(
                control2,
                OperandRole::Control2,
                target,
                OperandRole::Target,
                op_index,
            )?;
            Ok(Op::Ccx {
                control1,
                control2,
                target,
            })
        }
        _ => Err(DecodeError::InvalidOpcode { op_index, opcode }),
    }
}

/// Decode the fixed-byte format, checking every operation as it is parsed and
/// accepting only if the payload is consumed exactly.
///
/// # Errors
///
/// Returns a structured [`DecodeError`] for truncated or non-canonical input,
/// an unknown opcode, an invalid operand, or any checked-arithmetic/storage
/// failure.
#[allow(clippy::get_first)] // `get(0)` has a pinned Aeneas model; `first()` does not.
pub fn decode(bytes: &[u8]) -> Result<Circuit, DecodeError> {
    if bytes.len() < 2 {
        return Err(DecodeError::HeaderTooShort {
            actual_len: bytes.len(),
        });
    }

    let n_qubits = match bytes.get(0) {
        Some(value) => *value,
        None => {
            return Err(DecodeError::HeaderTooShort {
                actual_len: bytes.len(),
            });
        }
    };
    let num_ops = match bytes.get(1) {
        Some(value) => *value,
        None => {
            return Err(DecodeError::HeaderTooShort {
                actual_len: bytes.len(),
            });
        }
    };

    let mut ops = [Op::X { q: 0 }; STORAGE_CAPACITY];
    let mut cursor = 2_usize;
    let mut op_index = 0_u8;
    let mut error = None;

    while op_index < num_ops {
        match parse_op(bytes, &mut cursor, n_qubits, op_index) {
            Err(parse_error) => {
                error = Some(parse_error);
                op_index = num_ops;
            }
            Ok(op) => match ops.get_mut(usize::from(op_index)) {
                None => {
                    error = Some(DecodeError::StorageCapacityExceeded);
                    op_index = num_ops;
                }
                Some(slot) => match op_index.checked_add(1) {
                    None => {
                        error = Some(DecodeError::CounterOverflow);
                        op_index = num_ops;
                    }
                    Some(next_index) => {
                        *slot = op;
                        op_index = next_index;
                    }
                },
            },
        }
    }

    match error {
        Some(error) => Err(error),
        None if cursor != bytes.len() => match bytes.len().checked_sub(cursor) {
            Some(count) => Err(DecodeError::TrailingBytes { count }),
            None => Err(DecodeError::CounterOverflow),
        },
        None => Ok(Circuit {
            n_qubits,
            num_ops,
            ops,
        }),
    }
}

/// Check a public unit-weight resource claim. Success means decoding, all
/// well-formedness checks, exact consumption, checked cost calculation, and
/// equality with `claimed_cost` all succeeded.
///
/// # Errors
///
/// Returns [`VerifyError::Decode`] for rejected bytes,
/// [`VerifyError::Cost`] for a finite-word cost failure, or
/// [`VerifyError::ClaimedCostMismatch`] when the checked cost differs from the
/// public claim.
pub fn verify_resource_claim(
    bytes: &[u8],
    claimed_cost: u32,
) -> Result<ResourceReport, VerifyError> {
    let circuit = match decode(bytes) {
        Ok(circuit) => circuit,
        Err(error) => return Err(VerifyError::Decode(error)),
    };
    let actual = match circuit.checked_cost() {
        Ok(cost) => cost,
        Err(error) => return Err(VerifyError::Cost(error)),
    };
    if actual != claimed_cost {
        return Err(VerifyError::ClaimedCostMismatch {
            claimed: claimed_cost,
            actual,
        });
    }
    Ok(ResourceReport {
        n_qubits: circuit.n_qubits(),
        num_ops: circuit.num_ops(),
        cost: actual,
    })
}

/// Boolean reflection endpoint corresponding to Lean's
/// `verifyResourceClaim`.
#[must_use]
pub fn accepts_resource_claim(bytes: &[u8], claimed_cost: u32) -> bool {
    verify_resource_claim(bytes, claimed_cost).is_ok()
}

#[cfg(test)]
extern crate std;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn valid_mixed_circuit_decodes_and_reports_exact_cost() {
        let bytes = [4, 3, 0x00, 3, 0x01, 0, 2, 0x02, 0, 1, 3];
        let circuit = decode(&bytes).expect("valid circuit");
        assert_eq!(circuit.n_qubits(), 4);
        assert_eq!(circuit.num_ops(), 3);
        assert_eq!(circuit.op(0), Some(Op::X { q: 3 }));
        assert_eq!(
            circuit.op(1),
            Some(Op::Cx {
                control: 0,
                target: 2
            })
        );
        assert_eq!(
            circuit.op(2),
            Some(Op::Ccx {
                control1: 0,
                control2: 1,
                target: 3
            })
        );
        assert_eq!(circuit.op(3), None);
        assert_eq!(circuit.checked_cost(), Ok(3));
        assert_eq!(
            verify_resource_claim(&bytes, 3),
            Ok(ResourceReport {
                n_qubits: 4,
                num_ops: 3,
                cost: 3
            })
        );
        assert!(accepts_resource_claim(&bytes, 3));
        assert!(!accepts_resource_claim(&bytes, 2));
    }

    #[test]
    fn empty_circuit_is_canonical_even_with_zero_qubits() {
        let circuit = decode(&[0, 0]).expect("empty circuit");
        assert_eq!(circuit.n_qubits(), 0);
        assert_eq!(circuit.num_ops(), 0);
        assert_eq!(circuit.checked_cost(), Ok(0));
        assert_eq!(
            decode(&[0, 0, 0]),
            Err(DecodeError::TrailingBytes { count: 1 })
        );
    }

    #[test]
    fn malformed_inputs_fail_closed_with_specific_errors() {
        assert_eq!(
            decode(&[]),
            Err(DecodeError::HeaderTooShort { actual_len: 0 })
        );
        assert_eq!(
            decode(&[3]),
            Err(DecodeError::HeaderTooShort { actual_len: 1 })
        );
        assert_eq!(
            decode(&[3, 1]),
            Err(DecodeError::UnexpectedEnd {
                op_index: 0,
                field: ByteField::Opcode
            })
        );
        assert_eq!(
            decode(&[3, 1, 0xff]),
            Err(DecodeError::InvalidOpcode {
                op_index: 0,
                opcode: 0xff
            })
        );
        assert_eq!(
            decode(&[3, 1, 0x00]),
            Err(DecodeError::UnexpectedEnd {
                op_index: 0,
                field: ByteField::Qubit
            })
        );
        assert_eq!(
            decode(&[3, 1, 0x00, 3]),
            Err(DecodeError::OperandOutOfBounds {
                op_index: 0,
                role: OperandRole::Qubit,
                value: 3,
                n_qubits: 3
            })
        );
        assert_eq!(
            decode(&[3, 1, 0x01, 1, 1]),
            Err(DecodeError::DuplicateOperand {
                op_index: 0,
                first: OperandRole::Control,
                second: OperandRole::Target,
                value: 1
            })
        );
        assert_eq!(
            decode(&[3, 1, 0x02, 0, 2, 2]),
            Err(DecodeError::DuplicateOperand {
                op_index: 0,
                first: OperandRole::Control2,
                second: OperandRole::Target,
                value: 2
            })
        );
    }

    #[test]
    fn maximum_operation_header_is_supported_without_heap_allocation() {
        let mut bytes = std::vec![1, MAX_OPS];
        for _ in 0..MAX_OPS {
            bytes.extend_from_slice(&[0x00, 0]);
        }
        let circuit = decode(&bytes).expect("255-operation circuit");
        assert_eq!(circuit.num_ops(), MAX_OPS);
        assert_eq!(circuit.checked_cost(), Ok(u32::from(MAX_OPS)));
    }
}
