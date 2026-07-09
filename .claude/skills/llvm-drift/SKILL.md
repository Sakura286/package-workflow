---
name: llvm-drift
description: >-
  Playbook for upgrading a ROCm package on openRuyi when a new version — or being
  built against a newer system llvm — causes LLVM/clang version-drift build
  failures. Companion to the openruyi-rocm-packaging skill: use that for the
  general spec/OBS workflow, use THIS when a ROCm build breaks with signs of LLVM
  drift. Trigger on these symptoms even if the user never says "LLVM": cmake
  "The imported target ... references the file ... but this file does not exist"
  (libclang*.a / libLLVM*.a / libLLVMTestingAnnotations.a); device-libs
  "'__builtin_amdgcn_X' needs target feature Y"; comgr compile errors from
  relocated/renamed clang headers, namespaces or methods (clang/Driver/Options.h,
  clang::driver::options, Driver::GetResourcesPath, "no member named ... did you
  mean simply"); or %install/%files "File not found" / "Installed (but unpackaged)
  file(s) found". Also use when bumping a ROCm package across an LLVM major version
  or building ROCm against openRuyi's compat llvmNN (clangNN/llvmNN). Worked
  example inside: rocm-llvm 7.2.4 on llvm22 (22.1.8), which went green in ~10 OBS
  rounds.
---

## Language convention

Follow the repo-wide **Language** rule in `AGENTS.md`.

---

# Upgrading a ROCm package across an LLVM bump (openRuyi)

This is the **companion** to `openruyi-rocm-packaging`. That skill owns the
mechanics (spec format, `osc`, triggering/fetching OBS builds, committing as
CHEN Xuan, the watcher). **This** skill owns the *diagnosis and fixes* for the
failure family you hit when a ROCm package meets a newer LLVM than the one ROCm
was written against. Read both.

## The one idea that explains 90% of the failures

> **openRuyi does not build ROCm against the llvm that ROCm bundles. It builds
> against the system compat package `llvmNN` — a specific point release that is
> usually NEWER than ROCm's bundled snapshot.**

ROCm tarballs ship their own `llvm-project/` (which the spec discards with
`ls | grep -xv amd | xargs rm -r`) and the `amd/` consumers (comgr, device-libs,
hipcc) are written against *that* snapshot. We compile them with system
`clangNN`/`llvmNN` instead. Almost every error is the **gap** between "what the
ROCm source expects" and "what system `llvmNN` actually provides." So the newer
the system llvm relative to ROCm's bundled one, the more drift you hit.

## Step 0 — before you touch the spec

1. **Pin the exact system llvm version.** Read `openRuyi/SPECS/llvmNN/llvmNN.spec`
   (`%global maj_ver/min_ver/patch_ver`, e.g. 22.1.8). This is your reference
   point for everything below.
2. **Clone the relevant upstream trees for grep-able reference** (clone the
   matching tag/branch locally instead of WebFetch-ing files one at a time):
   - the ROCm release tag you're packaging — `git clone --filter=blob:none
     --sparse -b rocm-<ver> https://github.com/ROCm/llvm-project` then
     `git sparse-checkout set amd/comgr amd/device-libs` — to see what the source
     you build actually looks like;
   - **`amd-staging`** (ROCm/llvm-project default branch) — to see how upstream
     already adapted to the newer LLVM. This is where your fixes come from.
   - the matching `llvmorg-<maj.min.patch>` tag of `llvm/llvm-project`, sparse
     `clang/include/clang/Basic` — the authoritative source for clang builtin →
     target-feature mappings (`BuiltinsAMDGPU.def`).
3. **Know the build-phase order.** It is your progress bar; the phase you fail in
   tells you which class of fix you need:
   `cmake config → device-libs → comgr → hipcc → %install → %files`.

## Failure classes (in build-phase order)

### A. cmake config — "imported target references a file that does not exist"
```
CMake Error at .../cmake/clang/ClangTargets.cmake: The imported target
  "clangBasic" references the file ".../libclangBasic.a" but this file does not exist
```
**Cause:** the compat `clangNN-devel`/`llvmNN-devel` ship the cmake exports
(`ClangTargets.cmake`, `LLVMExports.cmake`) but the **static libs they reference
are split into separate `-static` subpackages**. The base (default-version) llvm
bundles them in `-devel`, so old specs never needed them.
**Fix:** `BuildRequires: clangNN-static` and `llvmNN-static`. Do **not** chase
this with symlink/sed hacks or per-target `message(WARNING ...)` downgrades — the
`-static` packages provide exactly these `.a` files (this is what the
`libLLVMTestingAnnotations.a` rabbit hole turned out to be).

### B. Path drift — versioned prefix, not the default locations
The compat package installs under `%{_libdir}/llvmNN/...`, not `/usr/include` or
`/usr/lib/clang/`. So:
- clang C++ API headers: `%{_libdir}/llvmNN/include/clang/...`
- clang resource headers (`opencl-c-base.h`): `%{_libdir}/llvmNN/lib/clang/NN/include/`
Any hardcoded `/usr/lib/clang/NN/...` from a default-llvm-era spec is wrong for
the compat package — point it at the versioned prefix. (For comgr's
`opencl_header.cmake`, the upstream `${CLANG_CMAKE_DIR}/../../../` actually
resolves correctly; an inherited sed can *break* it.)

### C. device-libs — "'__builtin_amdgcn_X' needs target feature Y"
```
ockl/src/image.cl: error: '__builtin_amdgcn_cubema' needs target feature cube-insts
ockl/src/media.cl: error: '__builtin_amdgcn_qsad_pk_u16_u8' needs target feature qsad-insts
```
**Cause:** newer clang gates some AMDGPU builtins behind fine-grained target
features. device-libs is compiled as **generic bitcode** (`-target
amdgcn-amd-amdhsa`, no `-mcpu`), so the feature isn't on. Upstream guards each
such function with a per-function `__attribute__((target("feature")))` (see
`dots.cl`, `wfredscan.cl`); a ROCm release that predates a gating has some
functions **unguarded** and fails.
**Fix:** backport the upstream device-libs commit that adds the attributes (e.g.
PR #651 → `bc1578256b48`). **Do not** globally inject features via OCL.cmake
`CLANG_OCL_FLAGS` — that works but is not how upstream does it.
**Enumerate, don't guess:** errors mask later ones (image.cl `cube` hid media.cl
`qsad`). Get the *complete* set from `clang/include/clang/Basic/BuiltinsAMDGPU.def`
at the matching `llvmorg` tag — grep every `__builtin_amdgcn_*` device-libs uses
and read the last `"feature"` field of its `TARGET_BUILTIN(...)` line. Only
**unguarded** usages need fixing (grep each file for `__attribute__((target`).

### D. comgr — clang C++ API drift
comgr embeds a clang driver/assembler and uses clang internals, so it's the most
exposed to API churn. Examples seen on llvm22:
- header relocated: `#include "clang/Driver/Options.h"` → `clang/Options/Options.h`
- namespace renamed: `using namespace clang::driver::options;` → `clang::options`
- static method → free function: `Driver::GetResourcesPath(x)` → `GetResourcesPath(x)`
  (compiler hint: *"no member named 'GetResourcesPath' ... did you mean simply
  'GetResourcesPath'?"*)
**Fix:** these are real upstream changes — **diff/backport from `amd-staging`**,
do not hand-guess the new API. The current `amd-staging` `comgr-compiler.cpp` is
the reference for the correct end-state.

### E. %install / %files — file moved/renamed/removed upstream
```
error: File not found: .../usr/share/licenses/<pkg>/NOTICES.txt        # %license points at a gone file
error: Installed (but unpackaged) file(s) found: .../doc/<pkg>/LICENSE.TXT  # rm path / case stale
```
**Cause:** across versions upstream renames/removes files (comgr dropped
`NOTICES.txt`) or changes install dir case (`ROCm-Device-Libs` →
`rocm-device-libs`). **Fix:** update `%license`/`%doc` lists and the `%install`
`rm` paths to match the new tarball. Verify against your cloned release tag.

## How to fix — method, not just symptoms

- **Upstream-first; patches, not seds.** When a fix mirrors an upstream change,
  express it as a **backported patch**, not an inline `prep.in` sed:
  `git format-patch -1 <commit> [-- <paths>]` from `amd-staging`, verify it lands
  with `git apply --check -p1` against the release-tag tree, drop it in
  `SPECS/<pkg>/`, add a `PatchN:` with the upstream commit/PR in a comment.
  `%autosetup -p1` applies them in order; confirm they apply **cumulatively**.
  Reserve seds for genuinely distro-specific adaptations with **no** upstream
  equivalent (e.g. the compat versioned-path rewrites).
- **Confirm you're reading the NEW log.** Before diagnosing, check OBS actually
  picked up your commit (expanded-sources hash). The GitHub→OBS auto-trigger is
  flaky; if the hash is stale, `osc service rr <prj> <pkg>` manually. A stale log
  sends you chasing a fix you already made.
- **Fail fast is fine.** cmake-config / early-compile failures return in
  1–2 min; let the build be the oracle for the *next* error rather than
  speculating five moves ahead — but once you hold an authoritative source
  (BuiltinsAMDGPU.def, amd-staging), pre-empt the whole cascade in one shot.
- **Know when to stop and ask the user:** the fix needs a version pin, disables
  tests/features beyond the repo's precedent, or turns into an open-ended source
  port that keeps cascading. Surface the situation with options rather than
  hand-patching indefinitely.
- **Watch the build with the watcher, don't poll** (`scripts/watch-obs.sh` under
  the Monitor tool; set `PRJ=` for the 7.2.4 project — see `openruyi-rocm-packaging`).

## Worked example — rocm-llvm 7.2.4 on llvm22 (22.1.8)

Order of fixes that took it green (each verified against source/upstream):
1. **B/A:** versioned BuildRequires + add `clang22-static` + `llvm22-static`.
2. **C:** device-libs `cube-insts/lerp-inst/qsad-insts/sad-insts` — only `image.cl`
   and `media.cl` were unguarded; backported PR #651 (`bc1578256b48`, device-libs
   hunks only — the clang/ hunks are already in llvm22).
3. **B:** `opencl_header.cmake` resource-dir path → `%{_libdir}/llvm22/lib/clang/`
   (kept as a sed — openRuyi-specific; note prep.sh macro substitution is **not**
   global, so keep each `%{...}` to one occurrence per line).
4. **D:** comgr → `clang/Options/Options.h`, `clang::options`, free-function
   `GetResourcesPath` (backports `ebcaa3d9226` + `ccb14ba83fd6`).
5. **E:** drop comgr `NOTICES.txt` from `%files`; fix device-libs doc `rm` path
   case (`ROCm-Device-Libs` → `rocm-device-libs`).

Final form: the comgr + device-libs fixes live as **upstream-backported patches**
(`0003`/`0004`/`0005` in `SPECS/rocm-llvm`), not seds.

**Guiding principle:** keep each fix at the smallest correct scope — a bug in the
`llvmNN` *packaging* (e.g. a missing `-static` dep) is fixed in the BuildRequires;
a *source/API drift* belongs in the consumer package as an upstream-backported
patch, never an ad-hoc sed that you'll have to re-derive on the next bump.
