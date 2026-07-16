# TODO: bring `python-torch` on ROCm 7.2.4 into packaging compliance

- **Status:** open / ready to implement (2026-07-12)
- **Primary target:** `rocm-specs-7.2.4/SPECS/python-torch`
  (`rocm-specs-7.2.4`, branch `7.2.4`)
- **OBS project:** `home:Sakura286:ROCm_724`
- **OBS packages:** `python-torch` and `python-torch:rocm`
- **Current packaged version:** `2.13.0`
- **Source tree:** `src/pytorch-v2.13.0`
- **Retained source archive:** `src/pytorch-v2.13.0.tar.gz`
- **Verified Source0 SHA-256:**
  `66614a19060f69cfd63cd0295f65a1241bd15df2fa65c60ae51066c11c2ce812`

## Scope and user decisions

This task follows a review against the authoritative openRuyi guidelines in
`homepage/docs/packaging-guidelines/` and current non-ROCm specs under
`openRuyi/SPECS/`.

The user has explicitly approved all of the following:

1. Split the bundled LibTorch C/C++ SDK into flavor-specific `-devel`
   subpackages.
2. Keep the native tests built for installation and real-machine testing, but
   put them in flavor-specific `-test` subpackages instead of the runtime RPM.
3. Restore the upstream `fsspec` runtime dependency now that openRuyi packages
   it.
4. Correct the PEP 639 and RPM license handling and re-audit the `License`
   expression.
5. Filter private shared-library RPM capabilities.
6. Make the wheel/distribution metadata version exactly `2.13.0`, not
   `2.13.0+gitunknown`.
7. Renumber the local smoke-test source from `Source11` to the contiguous
   `Source1`.
8. Convert the preparation stage to the declarative `%prep -a` form.
9. Replace hardcoded standard paths with RPM path/Python macros.
10. Use the public linker-flags macro rather than the internal-style
    `%{?__global_ldflags}` reference.
11. Replace fragile source-editing `sed` commands with tool-generated patches
    or supported build configuration where possible.

**Explicit non-goal:** do not expand, replace, or redesign the existing OBS
`%check` coverage. The user rejected the proposal to run a larger upstream test
subset during the package build. Preserve the declarative import check and the
current `pytorch-smoke-test.py` behavior unless a strictly mechanical change is
required by the subpackage work. The purpose of `-test` is post-install testing
on suitable real hardware, not expanding the OBS test gate.

Do not modify the similar mainline spec in `rocm-specs/SPECS/python-torch` as
part of this task. Do not change the upstream PyTorch version or ROCm version.

## Important distinction: Python package versus LibTorch SDK

A normal pure-Python package would not need a `-devel` subpackage. PyTorch is a
mixed deliverable: its wheel installs a complete C/C++ SDK used by LibTorch and
`torch.utils.cpp_extension`.

The inspected `python-torch-rocm-2.13.0` RPM contains approximately:

- 9,579 entries below `torch/include/`;
- 38 CMake files below `torch/share/cmake/`;
- the private-path LibTorch runtime libraries below `torch/lib/`.

The openRuyi package-splitting rules require C/C++ headers and development
metadata to live in `-devel`. This does **not** mean moving every unversioned
`torch/lib/*.so` into `-devel`: those libraries are loaded by `import torch` and
must remain in the runtime package. The development subpackage should own the
headers and CMake metadata while depending exactly on its matching runtime
flavor.

Expected binary packages:

```text
python-torch
python-torch-devel
python-torch-test

python-torch-rocm
python-torch-rocm-devel
python-torch-rocm-test
```

Because `Name:` already changes with the multibuild flavor, `%package devel`
and `%package test` should naturally produce the expected names. Each must use
an exact, architecture-specific dependency:

```spec
Requires:       %{name}%{?_isa} = %{version}-%{release}
```

After splitting, audit in-tree consumers such as `python-vllm`,
`python-torchvision`, and any package that compiles a C++/HIP extension. Add a
build dependency on the matching `-devel` package only where the consumer
actually needs LibTorch headers/CMake metadata. Do not add blanket runtime
dependencies on `-devel`.

## Why a `-test` subpackage is required

The current spec defaults `%bcond test 1`, sets `BUILD_TEST=ON`, builds native
PyTorch tests, but packages almost everything captured by
`%pyproject_save_files '*torch*'` into the main RPM. The available 2.13.0 ROCm
RPM contains native test programs and helper libraries such as:

```text
torch/bin/FileStoreTest
torch/bin/HashStoreTest
torch/bin/ProcessGroupGlooTest
torch/bin/ProcessGroupGlooAsyncTest
torch/bin/TCPStoreTest
torch/bin/test_aoti_abi_check
torch/bin/test_api
torch/bin/test_cpp_rpc
torch/bin/test_dist_autograd
torch/bin/test_jit
torch/bin/test_lazy
torch/bin/test_shim

torch/lib/libaoti_custom_ops.so
torch/lib/libbackend_with_compiler.so
torch/lib/libjitbackend_test.so
torch/lib/libtorchbind_test.so
```

These are useful for testing an installed package on a suitable physical
machine, especially for ROCm paths that OBS workers cannot execute. They should
therefore be retained but moved out of the runtime package into `%package test`.

Do **not** blindly move every file under `torch/bin/` or every library with an
unusual name. In particular, `torch/bin/torch_shm_manager` is a runtime helper
used by multiprocessing and must remain in the main package. Determine the
purpose of the following from the 2.13.0 source before classifying them:

```text
torch/bin/script_module_v4.ptl
torch/bin/test_interpreter_async.pt
torch/bin/upgrader_models/
```

Keep runtime compatibility data in the main package if installed PyTorch uses
it; put test-only fixtures in `-test`.

The `-test` subpackage is **not** automatically the complete upstream Python
test suite. The current wheel does not install all of PyTorch's `test/*.py`
tree, external model data, or every fixture. Do not describe it as a complete
test suite and do not add that large source tree unless the user explicitly
expands the scope later.

## Known current defects and evidence

### 1. Development files are mixed into the runtime RPM

`%files -f %{pyproject_files}` currently owns the complete generated file list,
including `torch/include/` and `torch/share/cmake/`. This violates the
development-file split rule.

### 2. Native tests and their dependencies leak into the runtime RPM

The latest retained build log is `log/python-torch-rocm-724-22.log`. Its final
RPM metadata exposes test helper libraries as global `Provides` and pulls in
`libgtest`/`libgmock` runtime requirements. The current `%install -a` only
deletes `ProcessGroupGlooTest` and `ProcessGroupGlooAsyncTest` to avoid their
dangling `libc10d_hip_test.so` dependency; it does not perform a real test split.

When the test files move to `-test`, reconsider that deletion. If the missing
`libc10d_hip_test.so` helper is still not installed, either package the matching
helper in `-test` or keep those two unusable binaries excluded. Never ship a
`-test` RPM with an unsatisfied soname dependency.

### 3. A packaged upstream dependency is deliberately erased

The spec runs:

```spec
sed -i -e '/fsspec/d' setup.py
```

PyTorch 2.13.0 declares `fsspec>=0.8.5`, and code under
`torch/distributed/checkpoint/_fsspec_filesystem.py` imports it. openRuyi now
ships `openRuyi/SPECS/python-fsspec/python-fsspec.spec` at a sufficiently new
version. The historical workaround is obsolete and suppresses a real runtime
dependency.

### 4. The PEP 639 comment and license handling are stale

The spec says `-l` is omitted because PyTorch declares no PEP 639
`License-File`. PyTorch 2.13.0 actually declares both `license` and
`license-files` in `src/pytorch-v2.13.0/pyproject.toml`. The built wheel already
contains a `dist-info/licenses/` tree, while `%files` also installs a duplicate
top-level `%license LICENSE`.

The current RPM expression is:

```spec
BSD-3-Clause AND BSD-2-Clause AND 0BSD AND Apache-2.0 AND MIT AND BSL-1.0 AND GPL-3.0-or-later AND Zlib
```

Upstream's 2.13.0 installed-package metadata instead includes
`Apache-2.0 WITH LLVM-exception` and does not match that expression exactly.
Neither expression should be copied blindly: the distro build prunes many
vendored directories, retains others, and uses system libraries for several
components. Re-audit the source that is actually compiled or copied into each
binary RPM. `rocm-specs-7.2.4/SPECS/python-torch/license.txt` is an old broad
source-tree inventory, not sufficient evidence for the final expression.

### 5. Private libraries publish global capabilities

The current RPM publishes global capabilities for libraries located under the
private Python path, including test libraries and LibTorch libraries. Remove
test-only libraries from the main package, then use narrowly scoped filters for
the remaining private-path capabilities. Follow the pattern used by
`openRuyi/SPECS/dotnet10.0/dotnet10.0.spec`, but derive the exact library list
from the newly built CPU and ROCm RPMs.

Be careful with filtering:

- filtering `Provides` by the `torch/lib/` path is reasonable because these are
  not visible in the system loader's default path;
- do not use an overbroad `__requires_exclude_from` that also suppresses genuine
  external dependencies of the libraries;
- if filtering private soname `Requires`, enumerate only the self-contained
  private names and verify all external ROCm/OpenBLAS/OpenMP dependencies remain;
- ensure consumers depend on the package name or the intended backend virtual
  capability, not an accidental `libtorch*.so()` capability.

### 6. Python distribution version does not equal the RPM version

The build log shows `torch-2.13.0+gitUnknown`, normalized to
`torch-2.13.0+gitunknown`, and the installed `.dist-info` directory carries that
local version. The RPM itself is `2.13.0`. Writing `version.txt` alone does not
prevent PyTorch's release archive without `.git` metadata from appending the
unknown Git suffix.

Use the upstream-supported release build variables wherever metadata is
generated:

```spec
export PYTORCH_BUILD_VERSION=%{version}
export PYTORCH_BUILD_NUMBER=1
```

At minimum, set them before `%pyproject_buildrequires` in
`%generate_buildrequires` and before the declarative wheel build in `%build -p`.
Verify the result is exactly `torch-2.13.0.dist-info` and that the CPU flavor's
generated `python3dist(torch)` version is exactly `2.13.0`.

## What has already been ruled out

1. **This is not a pure-Python package where `-devel` would be meaningless.**
   The installed wheel contains the LibTorch header/CMake SDK and
   `torch.utils.cpp_extension` discovers those in-tree paths.
2. **The correct response is not to move all `torch/lib/*.so` files into
   `-devel`.** The Python runtime loads the core LibTorch libraries from that
   private directory; only headers and development metadata are unambiguously
   development payload.
3. **The correct response is not to delete all native tests.** The user wants
   them retained for post-install testing on real hardware. The defect is their
   ownership by the runtime package and the absence of a real `-test`
   subpackage.
4. **`fsspec` is no longer unavailable.** It exists in the current openRuyi
   tree as `openRuyi/SPECS/python-fsspec/python-fsspec.spec`; do not preserve
   the old dependency deletion on that premise.
5. **PyTorch 2.13.0 does have PEP 639 metadata.** The current spec comment to
   the contrary is stale; this was confirmed directly from the retained source
   and built wheel metadata.
6. **The `+gitunknown` suffix is not an RPM display artifact.** It is present in
   the wheel filename, installed `.dist-info` directory, and METADATA version.
   Upstream's supported `PYTORCH_BUILD_VERSION`/`PYTORCH_BUILD_NUMBER`
   mechanism should be used.
7. **This task is not an opportunity to redesign `%check`.** Limited OBS test
   execution is an accepted constraint and the user explicitly declined a
   larger build-time suite.
8. **The known complex64 CPU eigenvalue error and LLVM 22 ROCm Loss.hip failure
   are separate issues.** Preserve their current handling and deferred-work
   records; do not fold speculative fixes into this packaging cleanup.

## Exact reproduction of the current packaging defects

Run all commands from the workspace root. The retained RPM predates the last
two-file Gloo cleanup but accurately reproduces the broader payload, metadata,
license, and capability problems that cleanup did not address.

```bash
# Confirm source and spec state.
sha256sum src/pytorch-v2.13.0.tar.gz
sed -n '1,720p' rocm-specs-7.2.4/SPECS/python-torch/python-torch.spec

# Confirm PEP 639 and upstream runtime dependency declarations.
sed -n '46,72p' src/pytorch-v2.13.0/pyproject.toml
sed -n '1128,1150p' src/pytorch-v2.13.0/setup.py
sed -n '1,100p' openRuyi/SPECS/python-fsspec/python-fsspec.spec

# Inspect the retained built ROCm package.
rpm_path=tmp/vllm-0.25-upgrade/python-torch-rocm-2.13.0-20.1.nor.x86_64.rpm
rpm -qpl "$rpm_path" | grep '/torch/include/' | wc -l
rpm -qpl "$rpm_path" | grep '/torch/share/cmake/' | wc -l
rpm -qpl "$rpm_path" | grep '/torch/bin/'
rpm -qp --provides "$rpm_path"
rpm -qp --requires "$rpm_path"
rpm -qp --licensefiles "$rpm_path"

# Confirm the latest retained build still emitted test/private capabilities and
# the gitunknown distribution version.
grep -n 'Provides:\|Requires:' log/python-torch-rocm-724-22.log | tail -n 4
grep -n '2.13.0+gitUnknown\|2.13.0+gitunknown' \
  log/python-torch-rocm-724-22.log | head
```

The host RPM command may print signature-policy and transaction-lock warnings
while still returning package metadata. Treat the query output, not those
host-environment warnings, as the evidence relevant to this task.

## Implementation plan

### A. Preflight

1. Work from the workspace root.
2. Check `git -C rocm-specs-7.2.4 status --short --branch` and preserve all
   unrelated/user changes.
3. Re-read:
   - `homepage/docs/packaging-guidelines/rpmspecification.md`;
   - `homepage/docs/packaging-guidelines/buildsystems/pyproject.md`;
   - `homepage/docs/packaging-guidelines/languages/python.md`;
   - `homepage/docs/packaging-guidelines/licenses.md`;
   - `homepage/docs/packaging-guidelines/splitpackage.md`.
4. Read the current spec and all patches in full. Preserve the LLVM 22
   `2008-loss-hip-O0-workaround-llvm22-codegen.patch`; its underlying toolchain
   bug is still deferred in
   `todo/python-torch-rocm-loss-hip-s-add-u64-pseudo.md`.
5. Do not accidentally claim the deferred CPU complex64 `linalg.eigh` bug is
   fixed; see `todo/python-torch-complex64-eigh.md`.

### B. Normalize source declarations and declarative prep

1. Rename `Source11: pytorch-smoke-test.py` to `Source1:` and update every
   `%{SOURCE11}` reference to `%{SOURCE1}`.
2. Add the source directory through the declarative prep option, for example:

   ```spec
   BuildOption(prep):  -n pytorch-v%{version}
   ```

3. Replace the manual `%prep`/`%autosetup` override with `%prep -a`, leaving only
   the package-specific post-prep operations in that appended section.
4. Confirm `%patchlist` remains immediately above `%description` and patches
   are still applied automatically at `-p1`.

### C. Restore accurate Python metadata

1. Remove the deletion of `fsspec` from `setup.py`.
2. Add `BuildRequires: python3dist(fsspec)` if the declarative import check or
   metadata generation needs it in the buildroot. The restored wheel metadata
   must generate the runtime `python3dist(fsspec) >= 0.8.5` requirement.
3. Set `PYTORCH_BUILD_VERSION` and `PYTORCH_BUILD_NUMBER` for both dynamic build
   requirements and wheel construction.
4. Inspect the resulting wheel `METADATA` and RPM `Requires`; do not hand-add
   duplicates already generated from `Requires-Dist`.

### D. Correct PEP 639 and license handling

1. Change the install file-selection option to use `-l`, preserving the
   required module patterns, for example:

   ```spec
   BuildOption(install):  -l '*torch*'
   ```

   Confirm the exact openRuyi macro syntax against current sibling specs and
   the OBS-expanded build; do not assume argument ordering without testing.
2. Remove the manual `%license LICENSE` only after verifying
   `rpm -q --licensefiles` shows the PEP 639 license files from the generated
   manifest.
3. Audit the actually retained/compiled code separately for CPU and ROCm if
   their payloads differ. Determine whether one common source-level expression
   is still correct or flavor-specific subpackage license tags are necessary.
4. Account explicitly for `Apache-2.0 WITH LLVM-exception` if applicable.
5. Check whether top-level `NOTICE` contains required attribution not otherwise
   installed; package it appropriately if applicable.
6. Update or replace the stale `license.txt` evidence. A standalone audit or
   write-up belongs under `doc/`, not beside the spec, unless the file is an RPM
   source/payload artifact.

### E. Split the LibTorch development SDK

1. Add `%package devel`, `%description devel`, and `%files devel` using the
   conditional `%{name}` and exact ISA-qualified runtime dependency.
2. Move at least these generated paths out of the main `%{pyproject_files}`
   manifest and into `-devel`:

   ```text
   %{python3_sitearch}/torch/include/
   %{python3_sitearch}/torch/share/cmake/
   ```

3. Do not move runtime libraries merely because their filenames are
   unversioned. Verify `import torch`, `torchrun`, and the smoke test with only
   the runtime RPM installed.
4. With `-devel` installed, compile and link a minimal CPU C++ extension using
   `torch.utils.cpp_extension`. For the ROCm flavor, at least verify header and
   CMake discovery without requiring a GPU; run device execution only on a
   physical ROCm system if one is available.
5. Confirm uninstalling `-devel` leaves the Python runtime usable and does not
   remove files owned by the main package.

### F. Split native test artifacts

1. Keep `%bcond test 1` and `BUILD_TEST=ON` so OBS continues producing the
   post-install test payload requested by the user.
2. Add `%package test`, `%description test`, and `%files test`, with an exact
   ISA-qualified dependency on `%{name}`.
3. Inspect the wheel/install tree and source references. Build an explicit list
   of test-only executables, libraries, and fixtures; do not use a broad
   `torch/bin/*` glob that captures `torch_shm_manager`.
4. Remove those test paths from `%{pyproject_files}` before main-package file
   processing and assign them to `%files test`. Prefer a generated, auditable
   test file list if the file set is large, but fail the build if expected test
   files silently disappear after an upstream change.
5. Resolve the current `ProcessGroupGloo{,Async}Test` situation:
   - package `libc10d_hip_test.so` in `-test` if it is built and appropriate; or
   - continue excluding the two unusable programs, with the technical reason;
   - never suppress the missing dependency merely to make RPM resolution pass.
6. Ensure `python-torch-test` and `python-torch-rocm-test` can be installed
   without pulling the opposite backend.
7. Add concise `%description test` text stating that this is an installed native
   test payload for post-install validation, not the complete upstream Python
   test suite.
8. Do not add these native binaries to OBS `%check`; the user intends them for
   later execution on suitable real hardware.

### G. Filter private capabilities

1. Query both newly built RPM sets with:

   ```bash
   rpm -qp --provides <rpm>
   rpm -qp --requires <rpm>
   rpm -qpl <rpm>
   ```

2. Remove global capabilities for private-path test helpers and LibTorch
   libraries as appropriate. Keep normal Python provides for the CPU flavor and
   preserve the deliberate ROCm exclusion of `python3dist(torch)`.
3. Verify no accidental requirements such as the following remain unresolved:

   ```text
   libc10d_hip_test.so()(64bit)
   libjitbackend_test.so()(64bit)
   libbackend_with_compiler.so()(64bit)
   ```

4. Verify genuine external soname dependencies remain present, including the
   relevant OpenMP, OpenBLAS, fmt, protobuf, and ROCm libraries.

### H. Replace fragile edits and hardcoded paths

1. Replace standard paths with macros, including at least:

   ```text
   /usr/include                         -> %{_includedir}
   /usr/lib64                           -> %{_libdir}
   /usr                                -> %{_prefix}
   /usr/lib/python3.13/site-packages   -> %{python3_sitearch} or the correct Python macro
   ```

   Do not alter `/proc/meminfo`; it is not an install-prefix path.
2. Change the linker flags to preserve distro flags through the documented
   public macro, e.g. `-fuse-ld=lld %{build_ldflags}`, after confirming the
   expansion in an openRuyi build log.
3. Inventory every source-changing `sed` in `%prep`. For each one:
   - prefer an upstream-supported build variable or CMake option when it exists;
   - otherwise generate a patch using `git format-patch`, `diff -Naur`, or an
     upstream patch;
   - never hand-write a unified diff;
   - retain comments and upstream issue/PR links;
   - use the correct four-digit origin range.
4. Logical patch groups are acceptable, but do not combine unrelated ABI,
   dependency, ROCm, and test changes merely to reduce the patch count.
5. High-priority conversions include the unguarded edits to:
   - `pyproject.toml` build requirements;
   - `setup.py` dependency pins and submodule checks;
   - system fmt/FXdiv/concurrentqueue integration;
   - `rocm_smi64` linking;
   - `CUDABlas.h` template mangling workaround;
   - `LoadHIP.cmake` paths/detection;
   - tensorpipe compatibility edits;
   - test CMake files and benchmark configuration.
6. After conversion, remove patches that are only needed for artifacts no
   longer built or packaged. Do not remove
   `2008-loss-hip-O0-workaround-llvm22-codegen.patch` until the deferred LLVM
   bug is genuinely fixed and verified.

## Verification and acceptance criteria

### Static checks

1. Run repository pre-commit hooks for every changed spec/source/patch file.
2. Run `git -C rocm-specs-7.2.4 diff --check`.
3. Verify the Source0 archive SHA-256 remains the value recorded above.
4. Inspect the expanded spec in a matching openRuyi RPM 4.20+ environment; a
   host parser lacking declarative macros is not authoritative.

### OBS builds

1. Commit as `CHEN Xuan <chenxuan@iscas.ac.cn>` with one package in the commit
   and a lowercase subject such as:

   ```text
   python-torch: split development and test payloads
   ```

2. Push branch `7.2.4` to `origin`; this should trigger
   `home:Sakura286:ROCm_724`.
3. Watch both `python-torch` and `python-torch:rocm` on
   `amd64_build/x86_64`. Use the 7.2.4 project and expected commit explicitly;
   do not use mainline watcher defaults.
4. Fetch the final logs into the next sequential `log/python-torch-*.log` files.

### RPM layout and metadata

For both CPU and ROCm flavors, verify:

- runtime, `-devel`, and `-test` RPMs are produced;
- no file is owned by more than one sibling package;
- runtime RPM contains no C/C++ header tree, CMake SDK tree, or native test
  binaries/helper libraries;
- `-devel` owns the headers/CMake metadata and exact-requires its runtime;
- `-test` owns only test programs/libraries/fixtures and exact-requires its
  runtime;
- `torch_shm_manager` and any genuine runtime compatibility data remain in the
  runtime RPM;
- CPU and ROCm siblings retain their deliberate mutual conflicts and backend
  identity behavior;
- CPU provides `python3dist(torch) = 2.13.0` and ROCm still excludes the generic
  Python distribution provide as designed;
- wheel metadata and the `.dist-info` directory use `2.13.0`, not
  `2.13.0+gitunknown`;
- the generated runtime requirements include `fsspec >= 0.8.5`;
- `rpm -q --licensefiles` shows the intended PEP 639 license files without an
  unnecessary duplicate top-level copy;
- private test/LibTorch soname capabilities are filtered without deleting
  genuine external runtime dependencies;
- every RPM is installable with no unresolved soname dependency.

### Runtime checks

With only the runtime RPM installed:

```bash
python3 -c 'import torch; print(torch.__version__)'
torchrun --help >/dev/null
```

Run the existing `pytorch-smoke-test.py` behavior through the normal build; do
not add a larger OBS test suite.

With `-devel` installed, build a minimal `torch.utils.cpp_extension` extension
and confirm it imports. With `-test` installed, enumerate the shipped test
binaries and record which can run on CPU-only systems and which require ROCm
hardware or other services. Do not claim ROCm device validation unless the
tests actually ran on a machine with a supported GPU and working `/dev/kfd`.

## Completion

Delete this TODO only after both CPU and ROCm OBS builds succeed, the six
expected binary RPMs pass the metadata/layout checks above, and any verification
that could not be performed due to unavailable physical ROCm hardware is stated
explicitly in the handoff. If implementation uncovers a separate non-trivial
bug that is consciously deferred, add a focused new file under `todo/` rather
than silently broadening this task.
