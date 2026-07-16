# Base lld22 packaging breaks gcc `-fuse-ld=lld` (and ghost-owns /usr/bin/ld)

**Status:** worked around in rocm-bandwidth-test (`332846b`, pre-seed
`-DLD_LLD_PATH=` / `-DLD_MOLD_PATH=`); Base bug itself unreported/unfixed.

## Symptom

Since the 2026-07 Base snapshot (llvm22 22.1.8-14.5, binutils 2.46.0-14.5),
`lld22` gets pulled into some x86_64 buildroots (observed in every buildroot
that also installs the rocm/hip 7.2.4 CI-layer chain, e.g. rocm-bandwidth-test
and rocm-origami on 2026-07-16). Any build system that *probes* for `ld.lld`
and then links through **gcc** with `-fuse-ld=lld` dies at link time with:

    collect2: fatal error: cannot find 'ld'

rocm-bandwidth-test hit this: upstream `cmake/build_utils.cmake` does
`find_program(LD_LLD_PATH ld.lld)` and unconditionally adds `-fuse-ld=lld`
for the main executable when found (no disable option; mold is preferred but
absent). First failing round: `log/rocm-bandwidth-test-01.log`.

## Root cause (verified from the published RPMs, 2026-07-16)

`lld22-22.1.8-14.5.or.x86_64.rpm`:

- ships `/usr/bin/ld.lld-22` (versioned) and `/usr/lib64/llvm22/bin/ld.lld`,
  but **no unversioned `ld.lld` on PATH** — gcc's collect2 searches PATH for
  `ld.lld` and finds nothing (its error message still prints just `'ld'`);
- `%ghost`-owns `/usr/bin/ld` with **no scriptlets and no
  update-alternatives registration** (checked the llvm22 spec: zero
  `alternatives` calls), while binutils manages `/usr/bin/ld` via
  `update-alternatives --install ... ld.bfd`. The ghost is latent conflict
  bait with binutils' alternatives link.

CMake's `find_program` still finds `ld.lld` (llvm22 dir is reachable via
cmake search paths), so probes succeed while the gcc link then fails.

## Ruled out

- NOT the binutils 14.5 alternatives switch: green builds (llama-cpp 465 g++
  calls, rocm-origami g++ -flto link) ran the same day on binutils 14.5;
  origami's buildroot even contained lld22 — plain gcc links (no
  `-fuse-ld=lld`) are unaffected.
- NOT a rocm-specs regression: the same rbt spec was green in ROCm_724 on the
  June Base snapshot, whose buildroot had no lld22.

## Reproduction

In any openRuyi x86_64 environment with lld22 installed:

    echo 'int main(){}' > t.c && gcc -fuse-ld=lld t.c
    # collect2: fatal error: cannot find 'ld'

## Next steps

- Report to openRuyi Base (SPECS/llvm22): ship an unversioned
  `%{_bindir}/ld.lld` symlink (or register `ld`/`ld.lld` through
  update-alternatives like binutils does), and drop or properly manage the
  `%ghost %{_bindir}/ld`.
- If another package fails the same way before Base is fixed, reuse either
  workaround: neutralize the build system's lld probe (rbt idiom), or shim an
  unversioned `ld.lld` into PATH in `%build -p`.
