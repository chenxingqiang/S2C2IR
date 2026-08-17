`--convert-comp-to-linalg` is a **correctness baseline**, not a target
kernel IR.

- `comp.matmul` means `C = A @ B`. The current realization uses
  `tensor.empty` + `linalg.fill(0)` + `linalg.matmul`. That zero-fill is
  an implementation choice for tensor-based linalg, not S²C² semantics.
- `comp.elemwise` carries **canonical math** (`silu` = `x / (1+exp(-x))`,
  etc.). Expanding to `math.exp` / `math.erf` / `arith` is one legal
  sequence; CUDA / NPU / CIM may use different instructions.

Further `comp` → `vector` / `scf` tiling can live here later.
