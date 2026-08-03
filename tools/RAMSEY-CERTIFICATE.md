# Ramsey certificate tool

`ramsey_gpu.py` searches for two-colour Ramsey lower-bound witnesses. It uses
PyTorch CUDA when available and a deterministic pure-Python backend otherwise.
The search is untrusted: only checking the emitted finite witness establishes
the mathematical claim.

```powershell
python tools/ramsey_gpu.py --self-test --output c5.json
python tools/ramsey_gpu.py --check c5.json
python tools/ramsey_gpu.py --search 5 --red-clique 3 --blue-clique 3
python tools/ramsey_gpu.py --check examples/r55-42.json
python tools/benchmark_ramsey.py
```

The self-test checks the 5-cycle colouring proving `R(3,3) > 5`.
`examples/r55-42.json` is a canonical conversion of
[Exoo's published matrix](https://cs.indstate.edu/ge/RAMSEY/g55.42) and checks
the known lower bound `R(5,5) >= 43`.

## Canonical format

A certificate is one UTF-8 JSON line ending in LF:

```json
{"format":"QRCert-Ramsey-v1","n":5,"red_clique":3,"blue_clique":3,"red_edges":[[0,1],[0,4],[1,2],[2,3],[3,4]]}
```

The field order is fixed. Vertices are numbered `0` through `n - 1`.
`red_edges` is strictly lexicographically sorted and every edge satisfies
`0 <= u < v < n`. Every omitted edge is blue. No whitespace, duplicate fields,
or additional fields are accepted.

For Lean conversion, parse the five fields, map each `[u,v]` to `(u,v) : Nat ×
Nat`, and define:

```text
red(u,v)  := (min u v, max u v) is in red_edges
blue(u,v) := u != v and not red(u,v)
```

The small trusted checker then enumerates every `red_clique`-element subset and
rejects if all of its pairs are red, and does the analogous check for blue.
`RamseyCertificate.lean` defines the corresponding row-major graph semantics
through `GraphCertificate.ofRedEdges` and proves its reflected checker sound.
The committed C5 instance is kernel-checked. The canonical JSON parser and the
large 42-vertex instance are not yet evaluated end to end inside Lean, so the
`R(5,5)` file is an exact CPU/CUDA regression certificate, not yet a
kernel-checked theorem artifact. GPU search performance is always outside the
theorem's trust boundary.
