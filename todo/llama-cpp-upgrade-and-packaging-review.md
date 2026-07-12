# TODO: upgrade and improve `llama-cpp` on the ROCm 7.2.4 branch

- **Status:** open / ready to implement (2026-07-10)
- **Primary target:** `rocm-specs-7.2.4/SPECS/llama-cpp`
  (`rocm-specs-7.2.4`, branch `7.2.4`)
- **OBS project:** `home:Sakura286:ROCm_724`, package `llama-cpp`
- **Current packaged version:** `b9859`
- **Current source commit:** `4fc4ec5541b243957ae5099edb67372f8f3b550e`
- **Current spec:** CPU, ROCm, and Vulkan multibuild flavors; all six baseline
  OBS targets (x86_64/riscv64 x CPU/ROCm/Vulkan) succeeded before this work.

## Scope clarification

The original request named `rocm-specs-7.4.2`, but that directory does not
exist in this workspace. The review and all subsequent user decisions were
made against `rocm-specs-7.2.4`; continue there. The similar mainline spec in
`rocm-specs/SPECS/llama-cpp` is not part of this task unless the user explicitly
extends the scope.

## Decisions already made by the user

1. Upgrade llama.cpp as part of this work. Do the upgrade first, then reconcile
   all fixes against the new source rather than polishing `b9859` first.
2. Express the optional ffmpeg integration as:

   ```spec
   Suggests:       ffmpeg
   ```

   Do not use `Requires:` or `Recommends:` for ffmpeg.
3. ROCm and Vulkan flavors must run only pure parsing/formatting tests. Do not
   run model, download/network, inference, or GPU/backend execution tests for
   those flavors.
4. Extract the numeric llama.cpp build number into one macro and derive both the
   RPM `Version` and CMake build number from it.

## Why this work is needed

### 1. Upgrade is due

`b9859` is a genuine upstream non-prerelease GitHub release, not a snapshot, so
the current version format is valid. However, llama.cpp releases very rapidly.
On 2026-07-10, the latest formal release was `b9948` (and newer tags already
existed). Re-query upstream at implementation time and choose the latest
**formal, non-draft, non-prerelease release**, not merely the numerically newest
tag.

The `bNNNN` scheme is safe for RPM ordering (`b9859 < b9948` and
`b9999 < b10000`) and conforms to the homepage rule permitting a literal
upstream release version. Preserve the `b` prefix.

### 2. The riscv64 ROCm workaround is applied too broadly

`2000-limit-rocm-batch-size.patch` changes the defaults from `2048/512` to
`8/8`. Its documented symptom is unstable output in openRuyi's **riscv64 ROCm**
environment, but the current spec applies it to every ROCm build, including
x86_64. This unnecessarily degrades the default x86_64 ROCm performance.

After upgrading, first check whether upstream has fixed the issue or changed the
affected code. If the workaround is still necessary, regenerate/rebase it with
a tool and apply it only under nested ROCm + riscv64 conditions, for example:

```spec
%if %{with rocm}
%ifarch riscv64
# Explain the riscv64 ROCm instability and retain the verified reference.
Patch0:         2000-limit-rocm-batch-size.patch
%endif
%endif
```

If upstream has fixed the problem, drop the patch instead. Never hand-edit a
unified diff; use an upstream patch, `diff -Naur`, or `git format-patch`.

### 3. The license expression carries a Fedora-specific identifier

The current expression is:

```spec
License:        MIT AND Apache-2.0 AND LicenseRef-Fedora-Public-Domain
```

In `b9859`, code actually compiled into the package includes full Unlicense
templates in `common/base64.hpp` and `vendor/sheredom/subprocess.h`;
`vendor/miniaudio/miniaudio.h` and `vendor/stb/stb_image.h` are dual-licensed.
The homepage license rules say an explicit Unlicense template must be recorded
as `Unlicense`, not a Fedora-local public-domain LicenseRef. A likely correction
for the current source is:

```spec
License:        MIT AND Apache-2.0 AND Unlicense
```

Do not copy that expression blindly after upgrading. Re-run a focused license
audit on the files actually compiled or installed by the new release, preserve
only applicable licenses, and ensure every separate upstream license text is
handled with `%license` where required.

### 4. Private implementation libraries leak global RPM capabilities

The runtime RPM currently ships unversioned private libraries such as:

```text
libllama-cli-impl.so
libllama-server-impl.so
libllama-quantize-impl.so
```

The built RPM publishes corresponding global automatic `Provides` and
`Requires`, even though these implementation libraries have no public headers,
pkg-config metadata, or supported external ABI. This conflicts with the
homepage package-splitting rule requiring private `.so` capabilities to be
filtered.

After checking the new version's installed libraries, add appropriately scoped
filters for the remaining private `libllama-*-impl.so` capabilities, e.g.:

```spec
%global __provides_exclude ^libllama-.*-impl\\.so
%global __requires_exclude ^libllama-.*-impl\\.so
```

Confirm from the built RPM that the private capabilities disappeared while the
files themselves and the executables that use them remain present.

### 5. ffmpeg is optional but discoverable

llama.cpp core text inference does not need ffmpeg. The `mtmd` multimodal layer
uses external `ffprobe` to inspect video metadata and external `ffmpeg` to
decode frames to RGB for vision-capable models. Text, image, and audio use cases
continue without it.

Keep video support enabled if the new upstream release still defaults
`MTMD_VIDEO` to `ON`, and add `Suggests: ffmpeg` as decided. If upstream removes
or redesigns this integration, re-evaluate rather than retaining a stale weak
dependency.

### 6. The current test handling is too coarse

The spec sets `LLAMA_BUILD_TESTS=OFF` and only runs `llama-cli --version`. This
was inherited from the Fedora packaging defaults; it was not backed by a
separate openRuyi analysis.

The complete upstream `ctest` suite cannot run unchanged in OBS because it
contains:

- `test-tokenizers-ggml-vocabs`, which contacts Hugging Face;
- `test-download-model` and dependent tests, which download a TinyLlama model;
- model/state/thread tests requiring downloaded model data;
- backend/inference tests that may require GPU hardware;
- known historical failures (`test-tokenizers-ggml-vocabs`, and ROCm
  `test-backend-ops`).

Nevertheless, many parser, grammar, chat-template, argument, and file-format
tests are local and hardware-independent.

## Implementation plan

### A. Preflight and upgrade

1. Work from the workspace root. Check `git -C rocm-specs-7.2.4 status` and
   preserve unrelated/user changes.
2. Query the latest upstream formal release and record its tag and exact commit.
3. Download its exact source archive into `src/`, retain the tarball, extract it
   under `src/`, and calculate SHA-256. Never use host `/tmp`.
4. Use one numeric macro, for example:

   ```spec
   %global build_number 9948

   Version:        b%{build_number}
   BuildOption(conf):  -DLLAMA_BUILD_NUMBER=%{build_number}
   ```

   Replace `9948` with the release chosen at implementation time. Verify that
   `Source0` resolves to the matching `b%{build_number}` tag and that the
   extraction directory still matches `BuildOption(prep)`.
5. Update the RemoteAsset SHA-256 and verify it against the retained tarball.

### B. Reconcile the new source

1. Read the new top-level and relevant subdirectory `CMakeLists.txt` files.
   Verify every existing `BuildOption(conf)` still exists and has the intended
   meaning.
2. Rebase, conditionally restrict, or drop the riscv64 ROCm batch patch as
   described above.
3. Re-audit licenses and update `License`/`%license` accordingly.
4. Inspect the staged install tree and reconcile all executables, SONAME files,
   unversioned linker symlinks, headers, CMake metadata, and pkg-config files
   with `%files`/`%files devel`.
5. Add private implementation-library capability filters based on the new
   actual file names.
6. Add `Suggests: ffmpeg` if the ffmpeg-backed video helper remains enabled.
7. Evaluate the current `BuildRequires: git`: release tarballs have no `.git`,
   and the `b9859` OBS log reports `not a git repository` and commit `unknown`.
   If the new build works without it, remove the dependency and pass the
   verified tag commit through the upstream-supported CMake variable if useful.
   Do not invent or guess a commit SHA.
8. Optionally set `-DGGML_CCACHE=OFF` if the new build still emits the expected
   “ccache not found” warning in OBS; this is log cleanup, not a primary fix.

### C. Enable an OBS-safe test subset

1. Enable test compilation and prevent test binaries from being installed:

   ```spec
   BuildOption(conf):  -DLLAMA_BUILD_TESTS=ON
   BuildOption(conf):  -DLLAMA_TESTS_INSTALL=OFF
   ```

   Confirm these option names still exist after the upgrade.
2. Enumerate the new release's tests (`ctest -N` or the generated CTest files)
   before writing filters. Do not reuse a stale b9859 list without checking.
3. Ensure the declarative CMake `%check` does **not** run unfiltered `ctest`.
   Prefer conditional `BuildOption(check):  -R <whitelist-regex>` if it maps
   correctly to `%ctest`; verify the expanded OBS log. If declarative options
   cannot express the required flavor-specific whitelist, override `%check`
   explicitly and comment why.
4. CPU flavor may run the broader local, network-free, model-free CPU subset.
   Exclude all downloads, remote Hugging Face access, unavailable Python
   helpers, and tests needing external model fixtures. CPU backend-operation
   tests may be admitted only after they pass reliably in the clean OBS build.
5. **ROCm and Vulkan flavors:** use a positive whitelist containing only pure
   parsing/formatting tests from the upgraded source, such as applicable
   grammar parser, PEG parser, chat/chat-template, JSON-schema conversion,
   argument parser, tokenizer-format, and GGUF-format tests. Do not run:

   - `test-download-model` or any fixture that depends on it;
   - `test-tokenizers-ggml-vocabs` or other network tests;
   - model load/state/thread/inference tests;
   - `test-backend-ops`, quantization performance, or GPU execution tests.

6. Retain `llama-cli --version` as a linked-binary smoke test after the selected
   unit tests. Keep the required build-tree `LD_LIBRARY_PATH` setup.
7. Document every excluded test class by technical reason in the spec; do not
   claim that all upstream tests require a model or GPU.

### D. Verify and deliver

1. Run syntax/style checks available in the environment, `git diff --check`,
   checksum verification, and patch-application checks.
2. Commit only the llama-cpp package as
   `CHEN Xuan <chenxuan@iscas.ac.cn>`. Use a one-line lowercase private-repo
   subject such as `llama-cpp: update to bNNNN`.
3. Push branch `7.2.4` to `origin`; this triggers
   `home:Sakura286:ROCm_724/llama-cpp`.
4. Arm the OBS watcher for the 7.2.4 project with `PRJ` set to
   `home:Sakura286:ROCm_724` and `EXPECT_COMMIT` set to the new
   `rocm-specs-7.2.4` HEAD. Do not watch the mainline project by mistake.
5. Require all six rows to succeed:

   - x86_64: CPU, ROCm, Vulkan;
   - riscv64: CPU, ROCm, Vulkan.

6. Inspect the successful logs to prove the intended test whitelist ran for
   each flavor and no network/model/GPU tests slipped into ROCm or Vulkan.
7. Download the resulting RPMs into workspace-local `tmp/` and inspect:

   - `rpm -qp --requires/--provides/--suggests`;
   - file lists for runtime and `-devel` packages;
   - absence of public `libllama-*-impl.so` capabilities;
   - presence of `Suggests: ffmpeg` and absence of a hard/recommended ffmpeg
     dependency;
   - correct exact-version dependency from each `-devel` package to its runtime
     package.

8. If runtime verification is needed, install the x86_64 RPM in the openRuyi
   QEMU VM, run `llama-cli --version`, and clean up afterward per the packaging
   skill. GPU inference cannot be claimed from an OBS-only or CPU-only smoke.
9. Delete this todo file once all work is resolved and verified.

## Evidence and references already checked

- Authoritative local guidelines:
  `homepage/docs/packaging-guidelines/` (`rpmspecification.md`, `licenses.md`,
  `splitpackage.md`, `versioning.md`, `buildsystems/cmake.md`).
- Current spec and patch:
  `rocm-specs-7.2.4/SPECS/llama-cpp/llama-cpp.spec` and
  `2000-limit-rocm-batch-size.patch`.
- Current source/tarball:
  `src/llama.cpp-b9859/` and `src/llama.cpp-b9859.tar.gz`; SHA-256 matches the
  current spec.
- Fedora reference:
  `rpms/llama-cpp/llama-cpp.spec`; its tests are disabled by default and it
  records historical tokenizer and ROCm backend-test failures.
- openRuyi upstream accepts `Suggests:` in reviewed packages. Relevant examples:
  `openRuyi/SPECS/rocm-llvm/rocm-llvm.spec` (`hipcc` suggests `rocminfo`), GCC
  suggests its docs, and merged upstream PRs #290 and #651 retained `Suggests:`
  without reviewer objection.
- Baseline review RPMs and metadata are under `tmp/llama-cpp-review/`.
