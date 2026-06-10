# Reference: openRuyi declarative builds & Fedora→openRuyi reformatting

Background and per-build-system docs live in this workspace at
`homepage/docs/packaging-guidelines/buildsystems/` (`buildsystem.md`, `cmake.md`,
`pyproject.md`, `autotools.md`, `meson.md`, `golang.md`, `rust.md`). This file is
the working summary plus the checklist for converting a Fedora spec.

## How declarative builds work

RPM 4.20+ lets a spec declare its build system and write only the deltas, instead
of spelling out `%prep`/`%build`/`%install` boilerplate.

- **Declare**: `BuildSystem:  cmake` (or `pyproject`, `autotools`, `meson`,
  `golang`, `rust`). The system then provides the standard unpack/configure/build/
  install/check steps.
- **Pass options**: `BuildOption(<section>):  <string>`. Sections are `conf`,
  `build`, `install`, `generate_buildrequires`, `check`. **Two spaces** after the
  colon. openRuyi requires the section to be named explicitly (RPM allows omitting
  it; we don't). The tag may repeat any number of times.
- **Prepend / append** to a generated stage instead of replacing it:
  - `%build -p` — prepend (e.g. `export CC=clang CXX=clang++` before the build).
  - `%install -a` — append (e.g. `rm` a stray file after install).
  - `%prep -a`, `%check -a` likewise.
  Use these for fine-tuning; don't re-emit `%cmake`/`%cmake_build`/`%pyproject_wheel`
  yourself — the build system already runs them.

## cmake specifics

`BuildRequires:  cmake` (gcc is preinstalled; clang stack adds `%global toolchain
clang` + `BuildRequires: clang`). The macros (`/usr/lib/rpm/macros.d/macros.cmake`)
already preset, so **don't repeat these**:

- `CMAKE_BUILD_TYPE = RelWithDebInfo` — never pass `-DCMAKE_BUILD_TYPE`.
- out-of-source build, `CMAKE_VERBOSE_MAKEFILE=ON`, `CMAKE_INSTALL_DO_STRIP=OFF`
  (RPM strips), `BUILD_SHARED_LIBS=ON`.
- All install paths: `CMAKE_INSTALL_PREFIX=%{_prefix}`, `…_LIBDIR`, `…_INCLUDEDIR`,
  `INCLUDE_INSTALL_DIR`, `LIB_INSTALL_DIR`, `SYSCONF_INSTALL_DIR`,
  `SHARE_INSTALL_PREFIX`, `LIB_SUFFIX=64`, etc.

So a typical Fedora `%build` of `cmake -S . -B build -DLOTS_OF_PATHS … && cmake
--build build -- all doc` collapses to a couple of `BuildOption(conf):` lines for
the *non-default* options plus `BuildOption(build):  -- all doc`, and a `%build -p`
only if you need to export env first. A Fedora `%install` of `cmake --install build`
+ cleanup becomes just `%install -a` with the cleanup lines.

## pyproject specifics

For PEP 517 projects (`pyproject.toml` present, standard build):

```
BuildSystem:  pyproject
BuildRequires:  pyproject-rpm-macros
BuildRequires:  pkgconfig(python3)

%generate_buildrequires
%pyproject_buildrequires
```

- Always pass the importable module name to `BuildOption(install):  <module>`.
- Extra build deps: `BuildOption(generate_buildrequires):  -x test` (extras), `-t`
  (tox test deps). `%generate_buildrequires` may print errors in the log — expected.
- A smoke import test runs by default — don't blank `%check`. Exclude un-importable
  modules with `BuildOption(check):  -e 'pkg.tests*'` and a comment saying why.
  Add pytest with `%check -a` + `%pytest`.
- A project can ship `pyproject.toml` yet not fit this system (custom build steps,
  bundled native builds). `python-triton` is exactly that case — it keeps
  `BuildSystem: pyproject` but builds a pinned LLVM in `%build -p` first; read it
  when a Python package needs heavy native work.

## Fedora → openRuyi reformatting checklist

When adapting a Fedora rawhide spec (`rpms/<pkg>/<pkg>.spec`) into
`rocm-specs/SPECS/<pkg>/<pkg>.spec`:

1. **SPDX header** — add the CHEN-Xuan-only block (SKILL.md) if absent; preserve an
   existing header otherwise.
2. **Toolchain** — add `%global toolchain clang` for ROCm packages.
3. **Source = release tarball** — point `Source0:` at the official upstream release
   archive (not an `archive/<commit>.tar.gz`), and add `#!RemoteAsset:  sha256:<h>`
   immediately above it (hash the downloaded tarball with `sha256sum`).
4. **BuildSystem + BuildOption** — replace the `%build`/`%install` boilerplate; keep
   only options that are non-default and actually present in upstream
   `CMakeLists.txt`. Two spaces after `BuildOption(<section>):`.
5. **No `-DCMAKE_BUILD_TYPE`** — the macros set it.
6. **Path macros** — `%{_bindir}`, `%{_libdir}`, `%{_includedir}`, … everywhere; no
   hardcoded `/usr/...`.
7. **BuildRequires style** — `cmake(Foo)` / `pkgconfig(foo)` / `python3dist(foo)`
   instead of `*-devel`, but only where such a provider exists
   (`homepage/docs/packaging-guidelines/pkgconfigbuildrequires.md`).
8. **Ninja** — `BuildOption(conf):  -G Ninja` + `BuildRequires:  ninja`.
9. **Remove `ExclusiveArch`.**
10. **`%autorelease` / `%autochangelog`** — drop hardcoded `Release` and manual
    changelog entries.
11. **Prune options** — remove cmake flags that are redundant with the macros or not
    in the upstream `CMakeLists.txt`.
12. **"compat" flag** — these are standard (non-compat) packages; drop a `compat`
    marker if the Fedora spec carries one.

## ROCm stack patterns worth knowing

- `%global toolchain clang` is mandatory across the stack.
- GPU targets come from a shared macro, e.g. `-DGPU_TARGETS=%{rocm_gpu_list_default}`.
- Long AMDGPU device links can run for hours producing no output; some specs add a
  heartbeat loop in `%build` so the builder isn't killed for silence (see `rccl`).
- Big links (bundled LLVM, pytorch) cap parallelism by RAM and may disable LTO/dwz
  (`%global _lto_cflags %{nil}`, `_find_debuginfo_dwz_opts %{nil}`) — see
  `python-triton`, `python-torch`.

Authoritative rules, when in doubt, are in `homepage/docs/packaging-guidelines/`
(`rpmspecification.md`, `naming.md`, `sourceurl.md`, `versioning.md`, `licenses.md`,
`patches.md`, `scriptlets.md`).
