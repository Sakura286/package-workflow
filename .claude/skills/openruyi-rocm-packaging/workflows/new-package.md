# Workflow: Add a new package

Goal: create a spec file for a package that doesn't exist yet, in openRuyi
declarative style, then commit and trigger its OBS build.

**Which repo/project to use:**
- **Mainline** (`rocm-specs/SPECS/<pkg>/<pkg>.spec` → `home:Sakura286:ROCm_PyTorch_Submit`): production packages
- **ROCm 7.2.4 testing** (`rocm-specs-7.2.4/SPECS/<pkg>/<pkg>.spec` → `home:Sakura286:ROCm_724`): testing ROCm 7.2.4 packages

Inputs from the user: the package name; sometimes a source URL. Ask only if the
name is ambiguous or no source can be found.

> Read the shared conventions in `SKILL.md` first (identity, SPDX, declarative
> cheat-sheet, OBS). The reformatting checklist lives in
> `reference/declarative-build.md`.

## Step 1 — Get a reference spec (Fedora rawhide first)

Fedora is the starting point. Clone its spec into `rpms/` (reference only — keep
its `.git`, never commit it into `rocm-specs` or `rocm-specs-7.2.4`):

```bash
git clone https://src.fedoraproject.org/rpms/<pkg>.git
```

- If Fedora **has** the package, `rpms/<pkg>/<pkg>.spec` is your base to adapt.
- If Fedora **doesn't** have it (clone 404s), try the openRuyi draft-spec server
  `nekorouter` as a fallback — it sometimes carries a draft ROCm spec:

  ```bash
  git clone ssh://git@git.openruyi.cn:54865/nekorouter/<pkg>.git /tmp/<pkg>-draft
  ```

  If a draft exists, use it as the base (drop its `.git`; don't commit it as-is).
- If neither source has it, write from scratch: use the information the user
  provides plus a sibling spec in `rocm-specs` (or `rocm-specs-7.2.4`) as the format
  template. Good templates: `rccl`, `rocrand`, `hipsparse` (cmake); `python-triton`
  (pyproject with a bundled build).

Also look at how `rocm-specs` already handles related packages and at this
package's history if it ever existed: `git -C rocm-specs log --oneline -- SPECS/<pkg>`.

## Step 2 — Get the source

Fuzzy-match `src/` for the upstream source (see SKILL.md). If absent,
download per the spec's `Source0:` into `src/` — never `/tmp/` (ROCm github:
`git clone --depth=1 --branch=rocm-<ver> <repo>`; tag missing → note it and use the
default branch; non-github → fetch the tarball into `src/` and extract there,
keeping the archive for reuse).

Read the upstream `CMakeLists.txt` (or `pyproject.toml`) to learn which build
options the project **actually** uses — you'll prune the spec down to those.

## Step 3 — Write the openRuyi spec

Create the spec file by adapting the Fedora spec (or writing fresh) to satisfy
every rule in `reference/declarative-build.md`. The essentials:

1. SPDX header — add the CHEN-Xuan-only block if the base spec has none; otherwise
   preserve the existing header.
2. `%global toolchain clang` for ROCm packages.
3. Real **release tarball** as `Source0:` with `#!RemoteAsset:  sha256:<hash>` just
   above it. Get the hash by downloading the tarball and running `sha256sum`
   (for PyPI packages you can read the sha256 off the PyPI release page instead).
4. `BuildSystem:` + `BuildOption(<section>):  …`; convert the Fedora `%build` /
   `%install` bodies into `-p` / `-a` deltas. Drop `-DCMAKE_BUILD_TYPE`.
5. Path macros everywhere; `cmake()` / `pkgconfig()` / `python3dist()` BuildRequires
   instead of `-devel` (only where such a provider exists); `-G Ninja` + `ninja`.
6. Remove `ExclusiveArch`, hardcoded `Release`, and manual `%changelog` entries;
   use `%autorelease` and `%autochangelog`.
7. Prune cmake options to those present in the upstream `CMakeLists.txt`.

**Where to create the spec:**
- **Mainline**: `rocm-specs/SPECS/<pkg>/<pkg>.spec`
- **ROCm 7.2.4 testing**: `rocm-specs-7.2.4/SPECS/<pkg>/<pkg>.spec`

## Step 4 — Commit

```bash
# Mainline
git -C rocm-specs add SPECS/<pkg> && git -C rocm-specs commit -m "<pkg>: init" && git -C rocm-specs push github main
# ROCm 7.2.4 testing
git -C rocm-specs-7.2.4 add SPECS/<pkg> && git -C rocm-specs-7.2.4 commit -m "<pkg>: init" && git -C rocm-specs-7.2.4 push origin 7.2.4
```

If you want to mirror the historical two-step (import, then reformat), make the
first commit a faithful import and a second `"<pkg>: reformat"` for the declarative
rewrite. For a spec written clean from the start, a single well-formed
`"<pkg>: init"` is fine.

## Step 5 — Trigger the OBS build

If the OBS package **already exists**, the push in Step 4 already triggered the
rebuild via the repo's GitHub Actions workflow — you're done (don't poll; see
SKILL.md). If it **doesn't exist yet**, that push's Actions run fails with a 404
for the new package (expected: OBS has nothing to trigger yet — ignore it);
create the package (details and the `_service` template in `reference/obs.md`):

```bash
# Mainline
cd home:Sakura286:ROCm_PyTorch_Submit \
  && osc mkpac <pkg> \
  && cp python-torch/_service <pkg>/_service
# edit <pkg>/_service: change the extract path to SPECS/<pkg>/*
cd home:Sakura286:ROCm_PyTorch_Submit/<pkg> \
  && osc add _service && osc ci -m "<pkg>: init"

# ROCm 7.2.4 testing
cd home:Sakura286:ROCm_724 \
  && osc mkpac <pkg> \
  && cp ../home:Sakura286:ROCm_PyTorch_Submit/python-torch/_service <pkg>/_service
# edit <pkg>/_service: change the extract path to SPECS/<pkg>/* AND revision to 7.2.4
cd home:Sakura286:ROCm_724/<pkg> \
  && osc add _service && osc ci -m "<pkg>: init"
```

After a clean `osc ci`, **stop**. The user reviews the build and returns a log if a
fix is needed (→ `workflows/fix-build.md`).
