#![forbid(unsafe_code)]

//! Extraction-oriented implementation of QRCert's fixed-byte decoder.
//!
//! This crate intentionally uses no dependencies, concurrency, interior
//! mutability, or nested loops. It is executable Rust today and is shaped for
//! translation through Charon and Aeneas. The generated-Lean refinement proof
//! remains a separate milestone.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Op {
    X(u8),
    CX(u8, u8),
    CCX(u8, u8, u8),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Circuit {
    pub n_qubits: u8,
    pub ops: Vec<Op>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DecodeError {
    ShortHeader,
    ShortOperation,
    UnknownOpcode,
    OutOfBounds,
    AliasedRegisters,
    TrailingBytes,
}

fn checked_op(n_qubits: u8, op: Op) -> Result<Op, DecodeError> {
    match op {
        Op::X(q) => {
            if q < n_qubits {
                Ok(op)
            } else {
                Err(DecodeError::OutOfBounds)
            }
        }
        Op::CX(control, target) => {
            if control >= n_qubits || target >= n_qubits {
                Err(DecodeError::OutOfBounds)
            } else if control == target {
                Err(DecodeError::AliasedRegisters)
            } else {
                Ok(op)
            }
        }
        Op::CCX(control1, control2, target) => {
            if control1 >= n_qubits || control2 >= n_qubits || target >= n_qubits {
                Err(DecodeError::OutOfBounds)
            } else if control1 == control2 || control1 == target || control2 == target {
                Err(DecodeError::AliasedRegisters)
            } else {
                Ok(op)
            }
        }
    }
}

fn byte_at(bytes: &[u8], position: usize) -> Result<u8, DecodeError> {
    if position < bytes.len() {
        Ok(bytes[position])
    } else {
        Err(DecodeError::ShortOperation)
    }
}

fn byte_after(bytes: &[u8], position: usize, offset: usize) -> Result<u8, DecodeError> {
    let index = position
        .checked_add(offset)
        .ok_or(DecodeError::ShortOperation)?;
    byte_at(bytes, index)
}

fn next_position(position: usize, width: usize) -> Result<usize, DecodeError> {
    position
        .checked_add(width)
        .ok_or(DecodeError::ShortOperation)
}

fn parse_op(bytes: &[u8], position: usize, n_qubits: u8) -> Result<(Op, usize), DecodeError> {
    let opcode = byte_at(bytes, position)?;
    let parsed = match opcode {
        0x00 => (
            Op::X(byte_after(bytes, position, 1)?),
            next_position(position, 2)?,
        ),
        0x01 => (
            Op::CX(
                byte_after(bytes, position, 1)?,
                byte_after(bytes, position, 2)?,
            ),
            next_position(position, 3)?,
        ),
        0x02 => (
            Op::CCX(
                byte_after(bytes, position, 1)?,
                byte_after(bytes, position, 2)?,
                byte_after(bytes, position, 3)?,
            ),
            next_position(position, 4)?,
        ),
        _ => return Err(DecodeError::UnknownOpcode),
    };
    Ok((checked_op(n_qubits, parsed.0)?, parsed.1))
}

pub fn deserialize(bytes: &[u8]) -> Result<Circuit, DecodeError> {
    if bytes.len() < 2 {
        return Err(DecodeError::ShortHeader);
    }
    let n_qubits = bytes[0];
    let num_ops = bytes[1] as usize;
    let mut position = 2usize;
    let mut ops = Vec::with_capacity(num_ops);
    let mut parsed = 0usize;
    while parsed < num_ops {
        let result = parse_op(bytes, position, n_qubits)?;
        ops.push(result.0);
        position = result.1;
        parsed += 1;
    }
    if position != bytes.len() {
        return Err(DecodeError::TrailingBytes);
    }
    Ok(Circuit { n_qubits, ops })
}

fn encode_op(op: Op, output: &mut Vec<u8>) {
    match op {
        Op::X(q) => {
            output.push(0x00);
            output.push(q);
        }
        Op::CX(control, target) => {
            output.push(0x01);
            output.push(control);
            output.push(target);
        }
        Op::CCX(control1, control2, target) => {
            output.push(0x02);
            output.push(control1);
            output.push(control2);
            output.push(target);
        }
    }
}

pub fn encode(circuit: &Circuit) -> Option<Vec<u8>> {
    if circuit.ops.len() > u8::MAX as usize {
        return None;
    }
    let mut output = Vec::new();
    output.push(circuit.n_qubits);
    output.push(circuit.ops.len() as u8);
    let mut position = 0usize;
    while position < circuit.ops.len() {
        let op = checked_op(circuit.n_qubits, circuit.ops[position]).ok()?;
        encode_op(op, &mut output);
        position += 1;
    }
    Some(output)
}

pub fn checked_gate_count(circuit: &Circuit) -> Option<u32> {
    let mut result = 0u32;
    let mut position = 0usize;
    while position < circuit.ops.len() {
        result = result.checked_add(1)?;
        position += 1;
    }
    Some(result)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepted_vector_matches_the_lean_blueprint() {
        let bytes = [4, 1, 0x02, 0, 1, 2];
        let circuit = Circuit {
            n_qubits: 4,
            ops: vec![Op::CCX(0, 1, 2)],
        };
        assert_eq!(deserialize(&bytes), Ok(circuit.clone()));
        assert_eq!(encode(&circuit), Some(bytes.to_vec()));
        assert_eq!(checked_gate_count(&circuit), Some(1));
    }

    #[test]
    fn exact_consumption_and_validation_are_enforced() {
        assert_eq!(deserialize(&[4, 0, 0]), Err(DecodeError::TrailingBytes));
        assert_eq!(deserialize(&[1, 1, 0x00, 1]), Err(DecodeError::OutOfBounds));
        assert_eq!(
            deserialize(&[2, 1, 0x01, 0, 0]),
            Err(DecodeError::AliasedRegisters)
        );
        assert_eq!(
            deserialize(&[4, 1, 0x02, 0, 1]),
            Err(DecodeError::ShortOperation)
        );
        assert_eq!(deserialize(&[4, 1, 0xff]), Err(DecodeError::UnknownOpcode));
    }

    #[test]
    fn representative_well_formed_circuits_round_trip() {
        let circuits = [
            Circuit {
                n_qubits: 0,
                ops: vec![],
            },
            Circuit {
                n_qubits: 1,
                ops: vec![Op::X(0)],
            },
            Circuit {
                n_qubits: 3,
                ops: vec![Op::X(2), Op::CX(0, 1), Op::CCX(0, 1, 2)],
            },
        ];
        for circuit in circuits {
            let encoded = encode(&circuit).expect("representative circuit is encodable");
            assert_eq!(deserialize(&encoded), Ok(circuit));
        }
    }

    #[test]
    fn every_small_single_operation_round_trips() {
        for n_qubits in 0u8..=8 {
            for q in 0u8..n_qubits {
                round_trip_one(n_qubits, Op::X(q));
            }
            for control in 0u8..n_qubits {
                for target in 0u8..n_qubits {
                    if control != target {
                        round_trip_one(n_qubits, Op::CX(control, target));
                    }
                }
            }
            for control1 in 0u8..n_qubits {
                for control2 in 0u8..n_qubits {
                    for target in 0u8..n_qubits {
                        if control1 != control2 && control1 != target && control2 != target {
                            round_trip_one(n_qubits, Op::CCX(control1, control2, target));
                        }
                    }
                }
            }
        }
    }

    fn round_trip_one(n_qubits: u8, op: Op) {
        let circuit = Circuit {
            n_qubits,
            ops: vec![op],
        };
        let encoded = encode(&circuit).expect("enumerated operation is well formed");
        assert_eq!(deserialize(&encoded), Ok(circuit));
    }
}
