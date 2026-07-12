# Workflow: Upgrade a package to a new version

Goal: bump an existing package to a target version, refresh its
source/checksum and patches, commit, and trigger the rebuild.

**Which repo/project to use:**
- **Mainline** (`rocm-specs/SPECS/<pkg>/<pkg>.spec` → `home:Sakura286:ROCm_PyTorch_Submit`): production packages
- **ROCm 7.2.4 testing** (`rocm-specs-7.2.4/SPECS/<pkg>/<pkg>.spec` → `home:Sakura286:ROCm_724`): testing ROCm 7.2.4 packages

Inputs from the user: package name + target version.

> Read the shared conventions in `SKILL.md` first.

## Step 1 — Understand how the version is encoded

Open the spec file and see how `Version` is built. Two common shapes:

- **Plain**: `Version:  3.6.0` → just edit it.
- **ROCm split macros** (most of the ROCm stack), e.g. `rccl`:

  ```
  %global rocm_release 7.1
  %global rocm_patch   1
  %global rocm_version %{rocm_release}.%{rocm_patch}
  ```

  To go to 7.2.0, set `rocm_release` to `7.2` and `rocm_patch` to `0`. The
  `Source0:` (`…/archive/rocm-%{rocm_version}.tar.gz`) follows automatically.

Don't touch `Release:` — `%autorelease` handles it. `%autochangelog` handles the
changelog. No manual bump of either.

## Step 2 — Refresh the source and checksum

Work out the new `Source0:` URL for the target version, download that exact
tarball, and update the `#!RemoteAsset:  sha256:` line above it:

```bash
# example for a github release tarball — save to src/ for reuse
curl -fL -o src/<pkg>.tar.gz.part '<resolved Source0 URL>'
sha256sum src/<pkg>.tar.gz.part
gzip -t src/<pkg>.tar.gz.part
tar -tf src/<pkg>.tar.gz.part >/dev/null
mv src/<pkg>.tar.gz.part src/<pkg>.tar.gz
```

The example is for gzip tarballs; use the matching integrity/listing command for
another archive format. Do not resume a partial download unless the server is
confirmed to honor the byte range with `206 Partial Content`—an incorrectly
appended response can leave a readable archive with trailing garbage.

For PyPI packages you can read the sha256 directly off the PyPI release page.
Extract the tarball in `src/` (e.g. `tar xf src/<pkg>.tar.gz -C src/`) so you can
test patches in Step 3.

## Step 3 — Refresh patches

For each `PatchN:` in the spec, check it still applies to the new source:

- Applies cleanly → keep it.
- Fails → rebase/regenerate it against the new source, keeping the patch header and
  its upstream reference (see `homepage/docs/packaging-guidelines/patches.md`).
  Regenerate it with a tool, never by hand — see fix-build.md Step 4 *"Producing
  the patch file"* for the three routes (upstream artifact → `diff` → `git
  format-patch`).
- Already merged upstream → drop the `PatchN:` and its `%patch`/autosetup line, and
  note in the commit why it's gone.

## Step 4 — Reconcile packaging with upstream changes

A new version may change what gets installed or how it builds. Check for:

- New / removed installed files → update the `%files` lists.
- New or renamed build options → update `BuildOption(conf):` (diff against the new
  upstream `CMakeLists.txt` / `pyproject.toml`).
- New or dropped dependencies → update `BuildRequires` / `Requires`.
- **A newer LLVM.** ROCm builds against the system `llvmNN` (often newer than the
  snapshot ROCm bundles), so a bump can surface LLVM/clang drift — missing
  `-static` imported targets, gated AMDGPU builtins, relocated clang headers. When
  that happens, use the `llvm-drift` skill.
- **Cross-package version coupling.** Some packages pin a sibling that must move in
  lockstep or a compiler snapshot. Read the new source and the actual consumer
  requirements, then update every verified pin and checksum together; do not turn
  one package's current pinning strategy into a general rule.

## Step 5 — Commit and trigger

```bash
# Mainline
git -C rocm-specs add SPECS/<pkg> && git -C rocm-specs commit -m "<pkg>: update to <version>" && git -C rocm-specs push github main
# ROCm 7.2.4 testing
git -C rocm-specs-7.2.4 add SPECS/<pkg> && git -C rocm-specs-7.2.4 commit -m "<pkg>: update to <version>" && git -C rocm-specs-7.2.4 push origin 7.2.4
```

The push to the GitHub remote triggers the rebuild automatically via the repo's
Actions workflow (see SKILL.md; `osc … service rr` remains the manual fallback).
Stop after confirming the trigger when the user only requested commit/push/trigger.
If the requested outcome includes a completed build, failure repair, or runtime
test, arm the watcher and continue through `workflows/fix-build.md` as needed.
