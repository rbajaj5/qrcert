"""CPU-only structural tests for the Ramsey CUDA gather-plan input."""

from __future__ import annotations

import math
import unittest

try:
    from .ramsey_gpu import clique_edge_chunks, clique_edge_rows
except ImportError:
    from ramsey_gpu import clique_edge_chunks, clique_edge_rows


class CliqueEdgeChunkTests(unittest.TestCase):
    def test_k5_triangle_chunks_are_complete_and_ordered(self) -> None:
        rows = clique_edge_rows(5, 3)
        chunks = clique_edge_chunks(5, 3, 4)

        self.assertIsInstance(chunks, tuple)
        self.assertEqual([len(chunk) for chunk in chunks], [4, 4, 2])
        self.assertTrue(all(isinstance(chunk, tuple) for chunk in chunks))
        self.assertTrue(
            all(isinstance(row, tuple) for chunk in chunks for row in chunk)
        )
        self.assertEqual(
            [list(row) for chunk in chunks for row in chunk],
            rows,
        )
        self.assertEqual(len(rows), math.comb(5, 3))
        self.assertEqual(rows[0], [0, 1, 4])
        self.assertEqual(rows[-1], [7, 8, 9])

    def test_clique_larger_than_graph_has_empty_plan(self) -> None:
        self.assertEqual(clique_edge_chunks(4, 5, 2), ())

    def test_nonpositive_chunk_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "clique_chunk must be positive"):
            clique_edge_chunks(5, 3, 0)


if __name__ == "__main__":
    unittest.main()
