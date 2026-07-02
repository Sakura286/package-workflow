# TODO: python-torch complex64 `linalg.eigh`/`eigvalsh` returns wrong eigenvalues (CPU)

- **Status:** open / deferred (2026-07-02)
- **Package:** `rocm-specs/SPECS/python-torch` (2.11.0), CPU flavor (`--without rocm`)
- **Severity:** real correctness bug in the built package, but narrow (complex64 only)
- **Found while:** enabling dynamic tests in `%check` (see commits
  `python-torch: fix complex dot/vdot returning 0 with openblas` and
  `python-torch: run a functional smoke and test-suite subset in %check`).

## Symptom

`torch.linalg.eigh` / `torch.linalg.eigvalsh` on a **complex64** Hermitian
matrix return grossly wrong eigenvalues — e.g. **negative** eigenvalues for a
positive-definite `A = M @ M.conj().T`. `complex128` and real dtypes are fine.

Upstream tests that fail (CPU, run from a checked-out pytorch `test/` dir):
`test_eigh_cpu_complex64`, `test_eigh_lower_uplo_cpu_complex64`,
`test_eigvalsh_cpu_complex64`.

## What it is NOT (already ruled out)

1. **Not the complex-dot bug.** That was `AT_BLAS_USE_CBLAS_DOT=0` (Patch4
   `2001-force-cblas-complex-dot-for-openblas.patch`) and only affects
   `torch.dot/vdot/inner`. eigh uses LAPACK `cheevd`, a different path; the dot
   fix does not change eigh (verified: after the fix, `test_eigh_cpu_complex64`
   still FAILS while `test_dot/vdot/inner_cpu_complex64` go OK).
2. **Not OpenBLAS's `cheevd`.** numpy uses the *same* system OpenBLAS
   (`/lib64/libopenblas.so.0`) and its complex64 `eigvalsh` is **correct**
   (matches the complex128 truth). So the LAPACK routine itself is fine; torch's
   use of it is wrong.
3. **Not the numpy/scipy LAPACK ABI breakage.** openRuyi's numpy/scipy hit
   `DLASCL`/`DPOTRF` "illegal value" (that is what breaks
   `test_pinv/matrix_rank/cond/lobpcg_scipy` — those compare against a broken
   numpy/scipy reference, not a torch bug). eigh is different: torch is
   *self-inconsistent* (reconstruction `V diag(w) Vᴴ != A`), independent of any
   numpy reference.

Conclusion: **torch-internal, complex64-specific.** Prime suspects: clang
codegen / `-flto=auto` miscompile of the complex-single eigh path, or torch's
`cheevd` wrapper / workspace handling in
`aten/src/ATen/native/BatchLinearAlgebra.cpp`. (numpy is built with gcc/gfortran
and is correct — so a clang-vs-gcc codegen difference is a strong hypothesis.)

## Reproduce

Repro env: the local x86-64 openRuyi QEMU VM (see the auto-memory
`x86-qemu-torch-repro`; ssh `localhost:2222`, user/pass `openruyi`). The
**fixed** torch (with Patch4) is currently installed there, and a pytorch
`test/` tree is at `/home/openruyi/pt-test`.

Self-consistency probe (no numpy needed — proves it is a torch bug):

```python
import torch
torch.manual_seed(0)
M = torch.randn(6, 6, dtype=torch.complex64); A = M @ M.conj().T   # Hermitian PD
w, V = torch.linalg.eigh(A)
recon = (V * w.to(torch.complex64)) @ V.conj().T
print("recon_rel =", (torch.linalg.norm((recon-A).reshape(-1))
                      / torch.linalg.norm(A.reshape(-1))).item())
print("eigenvalues (should all be > 0):", w.tolist())
# complex64: recon_rel ~2.2 and eigenvalues come out negative -> WRONG
# complex128: recon_rel ~1e-15 -> correct
```

torch-vs-numpy (proves OpenBLAS cheevd is fine, torch is wrong):

```python
import torch, numpy as np
torch.manual_seed(0)
M = torch.randn(6,6,dtype=torch.complex64); A = M @ M.conj().T
print("torch c64:", sorted(torch.linalg.eigvalsh(A).tolist()))
print("numpy c64:", sorted(np.linalg.eigvalsh(A.numpy().astype(np.complex64)).tolist()))
print("numpy c128:", sorted(np.linalg.eigvalsh(A.numpy().astype(np.complex128)).tolist()))
# numpy c64 == numpy c128 (correct); torch c64 disagrees (has negatives)
```

Upstream-test form:

```
cd /home/openruyi/pt-test
PYTORCH_TESTING_DEVICE_ONLY_FOR=cpu python3 test_linalg.py -v -k test_eigh_cpu_complex64
```

## Next steps to try

1. **Bisect the toolchain:** build python-torch CPU flavor with LTO off
   (drop `-flto=auto -ffat-lto-objects` from the flags used for
   `BatchLinearAlgebra.cpp`, or globally) and re-check eigh. If it fixes →
   clang LTO codegen bug; confine the workaround to that TU.
2. **Compare against a gcc build.** numpy (gcc/gfortran) is correct; a gcc-built
   torch would tell us if it is clang-specific. (Spec currently pins
   `%global toolchain clang`; a scoped experiment only.)
3. **Read the wrapper.** `aten/src/ATen/native/BatchLinearAlgebra.cpp` — the
   `cheev`/`cheevd` declaration, complex workspace (`cwork`) + `rwork` sizing and
   the workspace-query (`lwork = -1`) result read. Compare the complex64 vs
   complex128 code paths for an asymmetry.
4. **Search upstream** pytorch issues/PRs for complex64 eigh on CPU / clang /
   openblas before writing a fix (prefer upstream findings over guessing).

## Scope / current handling

- `%check` deliberately does **not** run `test_linalg` and does **not** gate on
  eigh; the functional smoke covers dot/matmul/autograd/training only.
- Impact on users: `torch.linalg.eigh`/`eigvalsh` (and possibly `eig`) are
  unreliable for **complex64** on CPU; complex128 and real dtypes are unaffected.
