use qrcert_checker::{DecodeError, Op, decode};

#[derive(Clone, Debug, PartialEq, Eq)]
struct ReferenceCircuit {
    n_qubits: u8,
    ops: Vec<Op>,
}

fn take(bytes: &[u8], cursor: &mut usize) -> Option<u8> {
    let value = *bytes.get(*cursor)?;
    *cursor = cursor.checked_add(1)?;
    Some(value)
}

fn reference_decode(bytes: &[u8]) -> Option<ReferenceCircuit> {
    let n_qubits = *bytes.first()?;
    let num_ops = *bytes.get(1)?;
    let mut cursor = 2_usize;
    let mut ops = Vec::with_capacity(usize::from(num_ops));

    for _ in 0..num_ops {
        let opcode = take(bytes, &mut cursor)?;
        let op = match opcode {
            0x00 => {
                let q = take(bytes, &mut cursor)?;
                (q < n_qubits).then_some(Op::X { q })?
            }
            0x01 => {
                let control = take(bytes, &mut cursor)?;
                let target = take(bytes, &mut cursor)?;
                (control < n_qubits && target < n_qubits && control != target)
                    .then_some(Op::Cx { control, target })?
            }
            0x02 => {
                let control1 = take(bytes, &mut cursor)?;
                let control2 = take(bytes, &mut cursor)?;
                let target = take(bytes, &mut cursor)?;
                (control1 < n_qubits
                    && control2 < n_qubits
                    && target < n_qubits
                    && control1 != control2
                    && control1 != target
                    && control2 != target)
                    .then_some(Op::Ccx {
                        control1,
                        control2,
                        target,
                    })?
            }
            _ => return None,
        };
        ops.push(op);
    }

    (cursor == bytes.len()).then_some(ReferenceCircuit { n_qubits, ops })
}

fn assert_agrees_with_reference(bytes: &[u8]) {
    let expected = reference_decode(bytes);
    let actual = decode(bytes);
    assert_eq!(
        actual.is_ok(),
        expected.is_some(),
        "acceptance mismatch for {bytes:?}: implementation={actual:?}, reference={expected:?}"
    );
    if let (Ok(circuit), Some(reference)) = (actual, expected) {
        assert_eq!(circuit.n_qubits(), reference.n_qubits);
        assert_eq!(usize::from(circuit.num_ops()), reference.ops.len());
        for (index, expected_op) in reference.ops.iter().enumerate() {
            let index = u8::try_from(index).expect("one-byte operation index");
            assert_eq!(circuit.op(index), Some(*expected_op));
        }
        let expected_cost = u32::try_from(reference.ops.len()).expect("one-byte operation count");
        assert_eq!(circuit.checked_cost(), Ok(expected_cost));
    }
}

fn enumerate_words(alphabet: &[u8], remaining: usize, word: &mut Vec<u8>) {
    assert_agrees_with_reference(word);
    if remaining == 0 {
        return;
    }
    for symbol in alphabet {
        word.push(*symbol);
        enumerate_words(alphabet, remaining - 1, word);
        let removed = word.pop();
        assert_eq!(removed, Some(*symbol));
    }
}

#[test]
fn exhaustive_small_byte_language_matches_independent_reference() {
    // 335,923 byte strings: all lengths 0..=7 over an alphabet containing all
    // valid opcodes, useful small bounds/operands, and an invalid 0xff opcode.
    let alphabet = [0, 1, 2, 3, 4, 0xff];
    enumerate_words(&alphabet, 7, &mut Vec::new());
}

#[test]
fn exhaustive_single_gate_bounds_and_distinctness() {
    for n_qubits in 0_u8..=8 {
        for q in 0_u8..=8 {
            assert_eq!(decode(&[n_qubits, 1, 0x00, q]).is_ok(), q < n_qubits);
        }

        for control in 0_u8..=8 {
            for target in 0_u8..=8 {
                let expected = control < n_qubits && target < n_qubits && control != target;
                assert_eq!(
                    decode(&[n_qubits, 1, 0x01, control, target]).is_ok(),
                    expected
                );
            }
        }

        for control1 in 0_u8..=8 {
            for control2 in 0_u8..=8 {
                for target in 0_u8..=8 {
                    let expected = control1 < n_qubits
                        && control2 < n_qubits
                        && target < n_qubits
                        && control1 != control2
                        && control1 != target
                        && control2 != target;
                    assert_eq!(
                        decode(&[n_qubits, 1, 0x02, control1, control2, target]).is_ok(),
                        expected
                    );
                }
            }
        }
    }
}

#[test]
fn every_unknown_opcode_is_rejected_at_the_opcode() {
    for opcode in 3_u8..=u8::MAX {
        assert_eq!(
            decode(&[4, 1, opcode]),
            Err(DecodeError::InvalidOpcode {
                op_index: 0,
                opcode
            })
        );
    }
}

#[test]
fn every_successful_single_gate_form_rejects_appended_data() {
    for n_qubits in 1_u8..=8 {
        for q in 0_u8..n_qubits {
            let canonical = [n_qubits, 1, 0x00, q];
            assert!(decode(&canonical).is_ok());
            let with_trailing = [n_qubits, 1, 0x00, q, 0];
            assert_eq!(
                decode(&with_trailing),
                Err(DecodeError::TrailingBytes { count: 1 })
            );
        }
    }
}
