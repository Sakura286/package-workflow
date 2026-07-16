# TODO: build and publish installable ROCm upstream test clients

- **Status:** in progress (2026-07-13) — matrix built; first two packages
  (`hipcub`, `rocrand`) converted and building on OBS. Original writeup
  2026-07-12.
- **Scope:** ROCm 7.2.4 specs and `home:Sakura286:ROCm_724`
- **Target environment:** openRuyi on SG2044/riscv64 with one physical Radeon
  GPU installed per test session

## Symptom

The ROCm specs do not apply a consistent policy for post-build hardware tests.
Many packages define upstream test clients and even a `%files test` section,
but disable their build with a bcond because OBS has no GPU. That prevents the
same test executables from being installed and run later on the SG2044.

During the 2026-07-12 audit, the published riscv64 repository exposed only
these test/benchmark artifacts:

```text
hipfft-test.rpm
hiprand-test.rpm
hipsparse-benchmark.rpm
rccl-test.rpm
rocfft-test.rpm
rocm-bandwidth-test.rpm
```

This is insufficient for the planned package-by-package ROCm runtime
validation.

## What has been confirmed

- `hipfft`, `hiprand`, `rocfft`, and `rccl` already build and package test
  programs without requiring OBS to execute them successfully on a GPU.
- Several other specs have disabled test switches or conditional `-test`
  subpackages, including `amdsmi`, `hipblaslt`, `hipcub`, `hipsolver`,
  `hipsparse`, `hipsparselt`, `miopen`, `rocm-smi`, `rocrand`, `rocblas`,
  `rocsolver`, `rocsparse`, `rocthrust`, and others.
- `rocr-runtime` declares a `kfdtest` subpackage, but the current riscv64 OBS
  artifacts contain only `rocr-runtime` and `rocr-runtime-devel`.
- Some projects build tests only for `%check` and do not install them, so they
  need a packaging decision rather than a simple bcond flip.

The buildability, runtime duration, privilege needs, and upstream support of
each disabled suite have not yet been established. Enabling every switch in a
single change would make failures difficult to attribute and violates the
one-package-per-commit rule.

## Reproduction / audit

Run from the workspace root:

```bash
osc -A https://pickaxe.oerv.ac.cn ls -b \
  home:Sakura286:ROCm_724 _repository riscv64_build riscv64 \
  | rg '(test|benchmark|kfdtest|bandwidth)'

rg -n 'bcond.*(test|check)|BUILD.*TEST|BUILD_CLIENTS|BUILD_TESTING|%files.*(test|benchmark|kfd)' \
  rocm-specs-7.2.4/SPECS --glob '*.spec'
```

For each candidate package, verify from its ROCm 7.2.4 source that the test
binary can be built on a GPU-less riscv64 builder, installed into a test RPM,
and executed later against the installed shared libraries rather than only the
OBS build tree.

## Desired packaging policy

- Build installable upstream test clients in OBS when technically possible.
- Do not execute device tests in GPU-less OBS workers.
- Separate `build_test` and `run_test` controls where one bcond currently does
  both jobs.
- Put hardware tests in a `-test` RPM (and performance tools in a clearly named
  benchmark package where appropriate) with exact runtime dependencies.
- Keep ordinary functional suites separate from destructive or long-running
  stress tests; stress-test procedure and safety rules belong in a separate
  document.
- Preserve upstream data/YAML/config files needed by the installed test binary.

## Conversion pattern (validated)

The reference specs that already ship a test/benchmark RPM (`rocfft`, `rccl`,
`hiprand`, `hipfft`) all follow one policy, and it is the target for every
package below:

- **Build the test client unconditionally.** HIP device-test code *compiles* on
  a GPU-less builder — only *running* it needs a GPU. So set the upstream test
  switch (`BUILD_TEST`/`BUILD_CLIENTS_TESTS`/`BUILD_TESTS`/…) to `ON`
  unconditionally, and make the test-only `BuildRequires` (usually
  `cmake(GTest)`) and the `%package test` / `%files test` unconditional too.
- **Never run device tests in OBS.** The declarative `cmake` buildsystem's
  default `%check` runs `%ctest`. If the suite registers `add_test(...)` (most
  do — verified for `hipcub`, `rocrand`), that default would execute GPU tests
  and fail on a GPU-less worker. Define an explicit `%check` whose body is
  guarded by a **default-off `%bcond run_test 0`**; when off, the empty `%check`
  replaces the default `%ctest` so nothing runs, and a packager with a GPU can
  opt in with `--with run_test`.
- Result: the single `%bcond test` that gated *build + package + run* together
  is split — build+package are always on, only the run is gated. Commit style
  matches the existing `hiprand: build test but do not run`.

## Package matrix

Build cost is the OBS build, not the test runtime. "GPU-less build" = the test
client compiles on the OBS worker (no `/dev/kfd`); running still needs a GPU on
the SG2044. `add_test` = suite registers ctest tests, so an explicit guarded
`%check` is mandatory.

> **DO NOT TOUCH — currently sourced from openRuyi, not `rocm-specs`.** Several
> base/core ROCm packages have their `home:Sakura286:ROCm_724` `_service`
> temporarily pointing at `github.com/Sakura286/openRuyi @ rocm-7.2.4` instead of
> `rocm-specs @ 7.2.4` (the migration in memory `migrate-rocm-724-into-openruyi`,
> a temporary workaround to be dismantled). Editing their spec under
> `rocm-specs-7.2.4/SPECS/` and pushing `origin 7.2.4` will **not** rebuild them.
> As of 2026-07-13 the openRuyi-sourced set is: `rocblas`, `rocsolver`,
> `rocsparse`, `rocm-smi`, `rocprim`, `rocm-llvm`, `rocr-runtime`, `rocminfo`,
> `rocm-cmake`, `rocclr`, `rocprofiler-register`, `hipblas`, `hipblas-common`,
> `hipify`, `python-tensile`. Leave their test clients for after the migration is
> dismantled (do not edit them here, and do not extend the workaround). Verify a
> package's source with `cat home:Sakura286:ROCm_724/<pkg>/_service` before
> starting. Everything in the tables below is confirmed `rocm-specs`-sourced
> unless marked `[openRuyi-sourced]`.

### Tier 0 — already shipping a test/benchmark RPM (reference)

| pkg | artifact | mechanism |
|---|---|---|
| `hipfft` | `hipfft-test` | `%bcond test 1`; `BUILD_CLIENTS_TESTS=ON` |
| `hiprand` | `hiprand-test` | `BUILD_TEST=ON`; `run_test` gates `%check` |
| `rocfft` | `rocfft-test` | `BUILD_CLIENTS_TESTS=ON`; `test` bcond gates `%check` |
| `rccl` | `rccl-test` | `BUILD_TESTS=ON`; no `%check` |
| `hipsparse` | `hipsparse-benchmark` | `BUILD_CLIENTS_BENCHMARKS=ON` (test still gated) |
| `rocm-bandwidth-test` | itself | the package *is* the bandwidth tool |

### Tier 1 — ready to convert (GPU-less build, deps available, no external data)

| pkg | kind | switch / current gate | notes | status |
|---|---|---|---|---|
| `hipcub` | header | `BUILD_TEST` | needs `cmake(GTest)`; `add_test` → guarded `%check` | **DONE — round 1 green.** ⚠ `-test` RPM is **227 MB** (many test binaries × 4 gfx targets) |
| `rocrand` | compiled RNG | `BUILD_TEST` | `add_test` → guarded `%check` | **DONE — round 1 green, 11 MB `-test` RPM** |
| `amdsmi` | CPU SMI | `BUILD_TESTS` | needs `cmake(GTest)`; buildsystem forces `SHARE_INSTALL_PREFIX=/usr/share`, so tests land in `%{_datadir}/tests` not `%{_datadir}/amd_smi/tests` — relocate them | **DONE — round 2 green, `-test` RPM shipped** |
| `rocthrust` | header | `BUILD_TEST` | 3 gotchas: (1) pulls SQLite via FetchContent → `-DSQLITE_USE_SYSTEM_PACKAGE=ON` + `pkgconfig(sqlite3)`; (2) builds ~500 tests → **~3h build**; (3) two suites: `test/` → `%{_bindir}/*.hip`, `testing/` → `%{_bindir}/test_*` | **DONE — round 2 green.** ⚠ `-test` RPM is **628 MB** |

> **Size note (decided 2026-07-13: keep full coverage).** The header-lib test
> suites compile one binary per algorithm × every default gfx target
> (`gfx1100;gfx1101;gfx1200;gfx1201`), so `hipcub-test` (227 MB) and
> `rocthrust-test` (628 MB) are far larger than the other `-test` RPMs (all
> ≤11 MB). Trimming their **test** `GPU_TARGETS` to the SG2044 set
> (`gfx1100;gfx1201`) would ~halve them without touching the shipped headers,
> but the user chose to **keep all 4 targets** for full coverage. Revisit only if
> repo/SG2044 storage becomes a constraint.
| `rocm-smi` | CPU SMI | — | **[openRuyi-sourced]** don't touch here | out of scope |
| `rocblas` | compiled BLAS | — | **[openRuyi-sourced]** don't touch here; would be a heavy Tensile build | out of scope |
| `rocsolver` | compiled LAPACK | — | **[openRuyi-sourced]** don't touch here | out of scope |

### Tier 2 — needs upstream test data fetched at build time

| pkg | blocker |
|---|---|
| `hipsparse` (test) | upstream test needs ~19 test matrices downloaded; benchmark already ships. Confirm the OBS worker can fetch (or vendor the matrices as a Source). |
| `rocsparse` | **[openRuyi-sourced]** don't touch here. (Test build downloads matrices into `CMAKE_MATRICES_DIR`; same fetch concern for whoever owns it.) |

### Tier 3 — blocked / heavy / known failure (document the reason)

| pkg | reason |
|---|---|
| `hipsolver` | test/benchmark require LAPACK; openRuyi `openblas` does not provide it (spec comment). Needs a LAPACK provider decision. |
| `hipsparselt` | client `CMakeLists` fatally requires LAPACK; Tensile-heavy; also GPU-target-limited (`todo/hipsparselt-radeon-gpu-targets.md`). |
| `hipblaslt` | Tensile client (`HIPBLASLT_ENABLE_CLIENT`); heavy; client deps unverified. |
| `miopen` | `BUILD_TESTING=ON` + `MIOPEN_TEST_ALL=ON` compiles an enormous kernel test set; build cost prohibitive without scoping. |
| `roctracer` | `test/CMakeLists.txt` uses legacy `find_package(HIP REQUIRED MODULE)` + `hip_add_executable`, which need `FindHIP.cmake` (deprecated; openRuyi's HIP ships CONFIG-mode `hip-config.cmake`, not the module). Enabling it failed with `No "FindHIP.cmake" found`; **reverted 2026-07-13**. To package, port the test to modern HIP (`enable_language(HIP)` + `add_executable` + `set_source_files_properties(... LANGUAGE HIP)`) via a patch. |
| `magma` | GPU test toggle only; no upstream installable test-client RPM. |
| `rocr-runtime` (`kfdtest`) | **[openRuyi-sourced]** don't touch here. (`%global kfdtest 0`; build on x86_64 fails with llvm static libs.) |
| `rocm-llvm` | **[openRuyi-sourced]** don't touch here. (`device_libs_test`/`comgr_test` are internal CTest, not an installable device client.) |

### Tier 4 — no test subpackage yet

| pkg | note |
|---|---|
| `rocprim` | **[openRuyi-sourced]** don't touch here. (`BUILD_TEST=OFF` hardcoded, no `%package test`; would need a new subpackage.) |

## Recommended order

Only `rocm-specs`-sourced packages are in scope (see the DO-NOT-TOUCH note
above); the heavy math libs `rocblas`/`rocsolver`/`rocsparse` are all currently
openRuyi-sourced, so they are out of scope until that migration is dismantled.

1. **Round 1 — DONE (green):** `hipcub` (header) + `rocrand` (compiled).
   Validated the pattern end to end; riscv64 `-test` RPMs shipped.
2. **Round 2 — in flight:** `rocthrust` (system-sqlite fix) + `amdsmi`
   (test-path fix). `roctracer` was attempted, hit the legacy-FindHIP blocker,
   and was **reverted** → moved to Tier 3.
3. **Round 3:** `hipsparse` (test) once the ~19-matrix fetch/vendor question is
   settled.
4. **Round 4:** Tier-3 packages that need a real unblock — `hipsolver` /
   `hipsparselt` (LAPACK provider), `hipblaslt` (Tensile client), `miopen`
   (scope `MIOPEN_TEST_ALL`), `roctracer` (port test off legacy `hip_add_executable`).
   Each is its own investigation.
5. Document blockers here as each is confirmed; only add a source-build fallback
   for suites that truly cannot be packaged. Revisit the openRuyi-sourced base
   packages once the migration is dismantled.

**Lesson from round 2:** a "cheap flip" is only cheap if `BUILD_TEST=ON` does
not (a) fetch something over the network at configure time (rocThrust → SQLite),
(b) install to an unexpected path under the declarative buildsystem's overrides
(amdSMI → `SHARE_INSTALL_PREFIX=/usr/share`), or (c) rely on a deprecated
`Find*.cmake` module openRuyi no longer ships (roctracer → `FindHIP.cmake`).
Check the upstream `test/CMakeLists.txt` for `FetchContent`/`find_package(... MODULE)`
before assuming a package is a simple flip.

## Next steps

1. ~~Build a package matrix~~ — done (above).
2. ~~Start with one small header/primitive project and one compiled math
   library~~ — `hipcub` + `rocrand` converted (round 1).
3. Continue enabling test-client builds one package at a time, each in its own
   commit and OBS round, following the recommended order.
4. Confirm each resulting `-test` RPM installs on a clean SG2044 and links only
   against packaged ROCm/openRuyi libraries; then graduate it from
   `BLOCKED-MISSING-TEST-RPM` to a runnable entry in
   `doc/rocm-7.2.4-sg2044-runtime-testing.md` (§11/§12).
5. Record suites that cannot be packaged and document the exact reason; for
   those only, provide a reproducible source-build procedure on the SG2044.
6. Once coverage is sufficient, write the non-stress manual runtime-test guide
   for testers and a separate stress-test guide with stronger safety controls.

