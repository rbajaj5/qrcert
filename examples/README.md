# Ramsey example provenance

`r55-42.json` is a canonical `QRCert-Ramsey-v1` conversion of
[Geoffrey Exoo's 42-by-42 adjacency matrix](https://cs.indstate.edu/ge/RAMSEY/g55.42).
Every matrix entry was compared against the reconstructed JSON graph on
3 August 2026.

```text
SHA-256  1588B6287DDA6CBD6644A120C47DE112333004594D205D82706A27438F57F19E
vertices 42
red edges 428
claim    no red K5 and no blue K5; hence R(5,5) > 42
```

The exact Python and CUDA checkers both accept this file. As documented in
`OPEN-MATH-APPLICATIONS.md`, the repository does not yet include a verified
JSON parser or a scalable kernel evaluation of this large concrete instance.
