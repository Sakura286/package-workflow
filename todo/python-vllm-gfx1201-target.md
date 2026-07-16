# TODO: validate the vLLM ROCm gfx1201 build target on hardware

- **Status:** packaging done and the **x86_64 RPM verified to carry gfx1201 code
  objects** (2026-07-13). Remaining: the riscv64 build (gated on riscv64 torch)
  and **runtime acceptance on the RX 9070 XT** — needs the physical card.
- **Scope:** `rocm-specs-7.2.4/SPECS/python-vllm/python-vllm.spec`, vLLM 0.25.0
- **Test hardware:** SG2044 with either an RX 7900 XTX (`gfx1100`) or an RX
  9070 XT (`gfx1201`); only one GPU can be installed at a time

## What was done (2026-07-13)

The rocm flavor no longer hardcodes a single arch. `%global rocm_gpu_arch`
now expands to the same shared macro the rest of the ROCm 7.2.4 stack uses:

```spec
%global rocm_gpu_arch %{rocm_gpu_list_default}   # = gfx1100;gfx1101;gfx1200;gfx1201
```

so `python-vllm-rocm` compiles code objects for **gfx1201 (RX 9070 XT)**
alongside gfx1100 (RX 7900 XTX), gfx1101 and gfx1200 — matching the torch and
ROCm libraries it depends on.

- Commit `f47fd01` `python-vllm: build rocm flavor for the full gfx target list`
  (identity `CHEN Xuan <chenxuan@iscas.ac.cn>`), pushed to `rocm-specs` branch
  `7.2.4`; OBS `home:Sakura286:ROCm_724` picked it up and rebuilt.
- **Unrelated blocker surfaced and fixed (commit `8bee9e8`
  `python-vllm: require torch devel after the dev/test split`).** The first
  rebuild failed at cmake configure — `find_package(Torch)` at
  `CMakeLists.txt:104` could not find `TorchConfig.cmake`. Cause: a concurrent
  commit `6eb4eb2 python-torch: split development and test payloads` moved
  `torch/include/` and `torch/share/cmake/` into a new `python-torch-rocm-devel`
  subpackage, so the base `python-torch-rocm` (2.13.0-27.1) vLLM `BuildRequires`
  no longer supplies torch's headers/cmake. This is independent of the arch
  change (the failed run showed `-DCMAKE_HIP_ARCHITECTURES=gfx1100;gfx1101;
  gfx1200;gfx1201` passed correctly). Fixed by `BuildRequires:
  python-torch-rocm-devel`. Only the rocm flavor was touched: the CPU
  `python-torch` itself currently fails in ROCm_724, so the base `python-vllm`
  (CPU) flavor is already non-viable there and out of scope for this branch.
- **Shell-quoting fix (important):** `%{rocm_gpu_list_default}` expands to a
  value that *includes its own double quotes* (`"gfx1100;...;gfx1201"`), which is
  how python-torch uses it bare in `export PYTORCH_ROCM_ARCH=...`. But vLLM also
  embedded the arch inside an already double-quoted `CMAKE_ARGS="..."`, where
  those inner quotes close the string early and leave the `;` separators as bare
  shell command separators (verified: only `gfx1100` survives, `gfx1101: command
  not found`). Fixed by passing `CMAKE_HIP_ARCHITECTURES=$PYTORCH_ROCM_ARCH`
  (the already-exported shell var holds the bare `;`-list) instead of the macro.
  This is the "changing the macro alone is not sufficient" trap the earlier note
  warned about.

## Confirmed facts

- The **entire** ROCm 7.2.4 stack already targets gfx1201: python-torch,
  hipblaslt, miopen, rocblas, rccl, rocsparse, rocsolver, rocfft, rocrand,
  hipfft, magma all build `%{rocm_gpu_list_default}` (= gfx1100;gfx1101;gfx1200;
  gfx1201). So torch + the ROCm libs vLLM links already carry gfx1201 code
  objects — the "dependency coverage" question is answered for everything except
  the two exceptions below.
- **Exceptions (both pre-existing, orthogonal to this task):**
  - `hipsparselt` hardcodes `gfx942;gfx950` (data-center only — no gfx1100 *or*
    gfx1201 code). This already applied to the working gfx1100 build, so gfx1201
    is no worse off. Tracked separately in
    `todo/hipsparselt-radeon-gpu-targets.md`.
  - Upstream vLLM 0.25.0 has **no fully-merged native gfx1201 FP8 WMMA kernel**:
    FP8 models can silently fall back to FP32/FP16 (gfx1201 missing from AITER's
    arch table), plus container-startup bugs (amdsmi / circular import /
    torch.cuda.device_count). fp16/bf16 inference is unaffected. No packaging
    change fixes this — it is an upstream runtime limitation.
    Refs: vllm-project/vllm#28649, vllm-project/vllm#40081,
    ROCm/TransformerEngine#520.
- ROCm 7.2 officially lists the RX 9070 XT (gfx1201) as supported, and the
  stack's llvm22 clang emits gfx1201 code — so compiling for gfx1201 is
  supported.
- Before this change both `python-vllm:rocm` rows (x86_64 and riscv64) built
  green at gfx1100. The riscv64 status from the 2026-07-12 audit is now resolved:
  it had succeeded.

## Verified this round (2026-07-13)

- **x86_64 `python-vllm:rocm` is green** at commit `8bee9e8`; the built RPM is
  `python-vllm-rocm-0.25.0-4.1.nor.x86_64.rpm`.
- **gfx1201 code objects are actually present.** `roc-obj-ls` on the shipped
  extensions (`_rocm_C.abi3.so`, `_C.abi3.so`, `_moe_C_stable_libtorch.abi3.so`)
  lists `hipv4-amdgcn-amd-amdhsa--gfx1201` bundles with real non-zero sizes for
  every kernel group, alongside gfx1100/gfx1101/gfx1200. So the RPM carries
  genuine RX 9070 XT device code, not a stub. (Reproduce: `roc-obj-ls
  <ext>.abi3.so` or `llvm-objdump --offloading <ext>.abi3.so | grep -o gfx....`.)

## Open

1. **riscv64 build.** `python-vllm:rocm` on riscv64 is currently `unresolvable`
   ("nothing provides python-torch-rocm-devel") because riscv64 `python-torch:rocm`
   is still `blocked`/unbuilt, so its `-devel` subpackage is not published yet.
   This is a dependency-timing issue, not a spec error (vllm riscv64 was already
   gated on riscv64 torch before the split). Re-check once riscv64 torch lands;
   also watch for an OBS idle/build timeout now that riscv64 compiles device code
   for 4 arches — if it times out, add a build-time heartbeat (rccl/hipblaslt
   idiom) rather than dropping arches. **This step needs no GPU.**
2. **Acceptance run on hardware.** Install `python-vllm-rocm` on the SG2044.
   Enumerate the installed native extensions (`rpm -ql python-vllm-rocm`) and
   confirm their offload targets include gfx1201 with the ROCm LLVM tools
   (`roc-obj-ls` / `llvm-objdump --offloading`). Then run one small deterministic
   fp16/bf16 inference reproducer in two physical-card sessions — RX 7900 XTX
   (gfx1100) as the control, RX 9070 XT (gfx1201) after the manual card swap.
   **Do not** set `HSA_OVERRIDE_GFX_VERSION` — it would mask the real gfx1201
   result.
3. If the gfx1201 build is green but runtime fails, reduce the failure to the
   owning component (vLLM extension, Triton kernel, PyTorch, or a ROCm library)
   before choosing an upstream tracker. Keep FP8 vs fp16/bf16 separate — an FP8
   fallback is the known upstream gap above, not a packaging regression.

## Reproduction / audit

```bash
rg -n 'rocm_gpu_arch|PYTORCH_ROCM_ARCH|CMAKE_HIP_ARCHITECTURES' \
  rocm-specs-7.2.4/SPECS/python-vllm/python-vllm.spec

osc -A https://pickaxe.oerv.ac.cn results \
  home:Sakura286:ROCm_724 'python-vllm:rocm' --csv
```
