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
# example for a github release tarball
curl -fL -o /tmp/<pkg>.tar.gz '<resolved Source0 URL>'
sha256sum /tmp/<pkg>.tar.gz
```

For PyPI packages you can read the sha256 directly off the PyPI release page. Also
refresh the source in `orig_code/` to the new tag so you can test patches in Step 3.

## Step 3 — Refresh patches

For each `PatchN:` in the spec, check it still applies to the new source:

- Applies cleanly → keep it.
- Fails → rebase/regenerate it against the new source, keeping the patch header and
  its upstream reference (see `homepage/docs/packaging-guidelines/patches.md`).
- Already merged upstream → drop the `PatchN:` and its `%patch`/autosetup line, and
  note in the commit why it's gone.

## Step 4 — Reconcile packaging with upstream changes

A new version may change what gets installed or how it builds. Check for:

- New / removed installed files → update the `%files` lists.
- New or renamed build options → update `BuildOption(conf):` (diff against the new
  upstream `CMakeLists.txt` / `pyproject.toml`).
- New or dropped dependencies → update `BuildRequires` / `Requires`.
- **Cross-package version coupling.** Some packages pin a sibling that must move in
  lockstep — e.g. `python-triton` pins `%global llvm_commit` to the value in the new
  tag's `cmake/llvm-hash.txt`, and `python-torch` is coupled to a specific `magma`.
  Honor any such note in the spec's comments and update the pinned value + its
  checksum together.

## Step 5 — Commit and trigger

```bash
# Mainline
wsl.exe -d ubuntu-26.04 -- bash -lc 'cd ~/Repo/package-workflow && git -C rocm-specs add SPECS/<pkg> && git -C rocm-specs commit -m "<pkg>: update to <version>" && git -C rocm-specs push github main'
# ROCm 7.2.4 testing
wsl.exe -d ubuntu-26.04 -- bash -lc 'cd ~/Repo/package-workflow && git -C rocm-specs-7.2.4 add SPECS/<pkg> && git -C rocm-specs-7.2.4 commit -m "<pkg>: update to <version>" && git -C rocm-specs-7.2.4 push origin 7.2.4'
```

The push to the GitHub remote triggers the rebuild automatically via the repo's
Actions workflow (see SKILL.md; `osc … service rr` remains the manual fallback).
**Then stop — don't poll.** If a patch or option fix is needed afterward, that's
a separate fix-build pass (→ `workflows/fix-build.md`).
