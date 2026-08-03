"""Select Haar/Walsh coordinates with a reproducible 0-1 MILP.

The threat catalogue contains every single-operation substitution in every
position of a fixed-size block.  The optimization minimizes the number of
retained coordinates while requiring each substitution to change at least
``minimum_family_detections`` retained Haar coordinates and the same number of
retained Walsh coordinates.

This is a bounded experiment, not a collision-resistance theorem.
"""

from __future__ import annotations

import argparse
import itertools
import json
from dataclasses import dataclass

import numpy as np
from scipy.optimize import Bounds, LinearConstraint, milp


CHANNELS = ("tag", "arg1", "arg2", "arg3")
TRANSFORMS = ("haar", "walsh")


@dataclass(frozen=True, order=True)
class Op:
    tag: int
    arg1: int
    arg2: int = -1
    arg3: int = -1

    def channel(self, name: str) -> int:
        return getattr(self, name)

    def label(self) -> str:
        if self.tag == 0:
            return f"X({self.arg1})"
        if self.tag == 1:
            return f"CX({self.arg1},{self.arg2})"
        return f"CCX({self.arg1},{self.arg2},{self.arg3})"


@dataclass(frozen=True)
class Feature:
    transform: str
    channel: str
    index: int

    def label(self) -> str:
        return f"{self.transform}:{self.channel}:{self.index}"


@dataclass(frozen=True)
class Threat:
    position: int
    before: Op
    after: Op

    def label(self) -> str:
        return f"slot {self.position}: {self.before.label()} -> {self.after.label()}"


def valid_ops(n_qubits: int) -> list[Op]:
    ops = [Op(0, q) for q in range(n_qubits)]
    ops.extend(Op(1, control, target) for control in range(n_qubits)
               for target in range(n_qubits) if control != target)
    ops.extend(
        Op(2, control1, control2, target)
        for control1 in range(n_qubits)
        for control2 in range(n_qubits)
        for target in range(n_qubits)
        if len({control1, control2, target}) == 3
    )
    return ops


def require_power_of_two(value: int) -> None:
    if value <= 0 or value & (value - 1):
        raise ValueError("block size must be a positive power of two")


def haar(values: list[int]) -> list[int]:
    """Lean module order: approximation, then preorder detail tree."""
    require_power_of_two(len(values))

    def details(segment: list[int]) -> list[int]:
        if len(segment) == 1:
            return []
        middle = len(segment) // 2
        left = segment[:middle]
        right = segment[middle:]
        return [sum(left) - sum(right), *details(left), *details(right)]

    return [sum(values), *details(values)]


def walsh(values: list[int]) -> list[int]:
    require_power_of_two(len(values))
    if len(values) == 1:
        return values.copy()
    middle = len(values) // 2
    left = walsh(values[:middle])
    right = walsh(values[middle:])
    return [*(a + b for a, b in zip(left, right, strict=True)),
            *(a - b for a, b in zip(left, right, strict=True))]


def features(block_size: int) -> list[Feature]:
    return [
        Feature(transform, channel, index)
        for transform in TRANSFORMS
        for channel in CHANNELS
        for index in range(block_size)
    ]


def threats(n_qubits: int, block_size: int) -> list[Threat]:
    ops = valid_ops(n_qubits)
    return [
        Threat(position, before, after)
        for position in range(block_size)
        for before, after in itertools.combinations(ops, 2)
    ]


def changed_features(threat: Threat, block_size: int) -> set[Feature]:
    changed: set[Feature] = set()
    for channel in CHANNELS:
        delta = [0] * block_size
        delta[threat.position] = (
            threat.after.channel(channel) - threat.before.channel(channel)
        )
        for transform_name, transform in (("haar", haar), ("walsh", walsh)):
            for index, value in enumerate(transform(delta)):
                if value != 0:
                    changed.add(Feature(transform_name, channel, index))
    return changed


def feature_value(feature: Feature, block: list[Op]) -> int:
    values = [op.channel(feature.channel) for op in block]
    coefficients = haar(values) if feature.transform == "haar" else walsh(values)
    return coefficients[feature.index]


def nearest_collision(selected: set[Feature], baseline: list[Op],
                      operations: list[Op]) -> dict[str, object]:
    """Find the nearest distinct block with the same selected coordinates."""
    block_size = len(baseline)
    variable_count = block_size * len(operations)

    def variable(position: int, operation_index: int) -> int:
        return position * len(operations) + operation_index

    objective = np.ones(variable_count)
    for position, baseline_op in enumerate(baseline):
        objective[variable(position, operations.index(baseline_op))] = 0

    one_hot = np.zeros((block_size, variable_count))
    for position in range(block_size):
        for operation_index in range(len(operations)):
            one_hot[position, variable(position, operation_index)] = 1

    fingerprint = np.zeros((len(selected), variable_count))
    fingerprint_target = np.zeros(len(selected))
    for row, feature in enumerate(sorted(selected, key=Feature.label)):
        fingerprint_target[row] = feature_value(feature, baseline)
        for position in range(block_size):
            for operation_index, operation in enumerate(operations):
                # The transform is linear, so zero channel values are required
                # rather than a syntactically valid zero operation.
                channel_values = [0] * block_size
                channel_values[position] = operation.channel(feature.channel)
                coefficients = (
                    haar(channel_values)
                    if feature.transform == "haar"
                    else walsh(channel_values)
                )
                fingerprint[row, variable(position, operation_index)] = (
                    coefficients[feature.index]
                )

    distinct = np.zeros((1, variable_count))
    for position, baseline_op in enumerate(baseline):
        distinct[0, variable(position, operations.index(baseline_op))] = 1

    result = milp(
        c=objective,
        integrality=np.ones(variable_count),
        bounds=Bounds(0, 1),
        constraints=[
            LinearConstraint(one_hot, np.ones(block_size), np.ones(block_size)),
            LinearConstraint(fingerprint, fingerprint_target, fingerprint_target),
            LinearConstraint(distinct, -np.inf, block_size - 1),
        ],
        options={"presolve": True},
    )
    if not result.success or result.x is None:
        return {
            "collision_found": False,
            "minimum_substitutions": None,
            "alternative": None,
        }

    alternative: list[Op] = []
    for position in range(block_size):
        chosen = [
            operations[operation_index]
            for operation_index in range(len(operations))
            if result.x[variable(position, operation_index)] > 0.5
        ]
        if len(chosen) != 1:
            raise AssertionError("collision MILP output is not one-hot")
        alternative.append(chosen[0])

    if alternative == baseline:
        raise AssertionError("collision MILP returned the excluded baseline")
    for feature in selected:
        if feature_value(feature, alternative) != feature_value(feature, baseline):
            raise AssertionError("reported collision fails exact fingerprint check")
    distance = sum(left != right for left, right in zip(
        baseline, alternative, strict=True
    ))
    if distance != round(float(result.fun)):
        raise AssertionError("reported collision distance disagrees with objective")

    return {
        "collision_found": True,
        "minimum_substitutions": distance,
        "alternative": [op.label() for op in alternative],
    }


def solve(n_qubits: int, block_size: int,
          minimum_family_detections: int) -> dict[str, object]:
    require_power_of_two(block_size)
    if n_qubits < 3:
        raise ValueError("at least three qubits are needed to include CCX")
    if minimum_family_detections < 1:
        raise ValueError("minimum detections must be positive")

    candidate_features = features(block_size)
    threat_catalogue = threats(n_qubits, block_size)
    feature_index = {feature: index for index, feature in enumerate(candidate_features)}
    changed = [changed_features(threat, block_size) for threat in threat_catalogue]

    rows: list[np.ndarray] = []
    for changed_set in changed:
        for transform in TRANSFORMS:
            row = np.zeros(len(candidate_features))
            for feature in changed_set:
                if feature.transform == transform:
                    row[feature_index[feature]] = 1
            rows.append(row)

    matrix = np.stack(rows)
    lower = np.full(matrix.shape[0], minimum_family_detections, dtype=float)
    result = milp(
        c=np.ones(len(candidate_features)),
        integrality=np.ones(len(candidate_features)),
        bounds=Bounds(0, 1),
        constraints=LinearConstraint(matrix, lower, np.inf),
        options={"presolve": True},
    )
    if not result.success or result.x is None:
        raise RuntimeError(f"MILP failed: {result.message}")

    selected = {
        feature
        for feature, value in zip(candidate_features, result.x, strict=True)
        if value > 0.5
    }
    uncovered: list[str] = []
    for threat, changed_set in zip(threat_catalogue, changed, strict=True):
        for transform in TRANSFORMS:
            count = sum(
                feature in changed_set
                for feature in selected
                if feature.transform == transform
            )
            if count < minimum_family_detections:
                uncovered.append(f"{transform} / {threat.label()}")
    if uncovered:
        raise AssertionError(f"solver output failed exact verification: {uncovered[:3]}")

    baseline_seed = [
        Op(0, 0),
        Op(1, 0, 1),
        Op(2, 0, 1, 2),
        Op(0, min(3, n_qubits - 1)),
    ]
    baseline = [baseline_seed[index % len(baseline_seed)]
                for index in range(block_size)]
    collision = nearest_collision(selected, baseline, valid_ops(n_qubits))

    return {
        "scope": {
            "n_qubits": n_qubits,
            "block_size": block_size,
            "valid_operations": len(valid_ops(n_qubits)),
            "single_substitution_classes": len(threat_catalogue),
            "minimum_detections_per_transform_family": minimum_family_detections,
        },
        "candidate_coordinates": len(candidate_features),
        "selected_coordinate_count": len(selected),
        "selected_coordinates": sorted(feature.label() for feature in selected),
        "verified_uncovered_constraints": len(uncovered),
        "baseline_collision_audit": {
            "baseline": [op.label() for op in baseline],
            **collision,
        },
        "solver": "scipy.optimize.milp (HiGHS)",
        "claim_boundary": (
            "Optimal for the stated finite catalogue and objective only; "
            "not a universal or cryptographic collision-resistance claim."
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--n-qubits", type=int, default=4)
    parser.add_argument("--block-size", type=int, default=4)
    parser.add_argument("--minimum-family-detections", type=int, default=1)
    args = parser.parse_args()
    print(json.dumps(solve(
        args.n_qubits,
        args.block_size,
        args.minimum_family_detections,
    ), indent=2))


if __name__ == "__main__":
    main()
