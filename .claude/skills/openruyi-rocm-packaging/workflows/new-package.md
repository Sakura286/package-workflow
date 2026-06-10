# Workflow: Add a new package

Goal: create `rocm-specs/SPECS/<pkg>/<pkg>.spec` for a package that doesn't exist
yet, in openRuyi declarative style, then commit and trigger its OBS build.

Inputs from the user: the package name; sometimes a source URL. Ask only if the
name is ambiguous or no source can be found.

> Read the shared conventions in `SKILL.md` first (identity, SPDX, declarative
> cheat-sheet, OBS). The reformatting checklist lives in
> `reference/declarative-build.md`.

## Step 1 — Get a reference spec (Fedora rawhide first)

Fedora is the starting point. Clone its spec into `rpms/` (reference only — keep
its `.git`, never commit it into `rocm-specs`):

```bash
cd rpms
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
  provides plus a sibling spec in `rocm-specs` as the format template. Good
  templates: `rccl`, `rocrand`, `hipsparse` (cmake); `python-triton` (pyproject
  with a bundled build).

Also look at how `rocm-specs` already handles related packages and at this
package's history if it ever existed: `git -C rocm-specs log --oneline -- SPECS/<pkg>`.

## Step 2 — Get the source

Fuzzy-match `orig_code/` for the upstream source (see SKILL.md). If absent,
download per the spec's `Source0:` into `orig_code/` (ROCm github:
`git clone --depth=1 --branch=rocm-<ver> <repo>`; tag missing → note it and use the
default branch; non-github → fetch the tarball and extract).

Read the upstream `CMakeLists.txt` (or `pyproject.toml`) to learn which build
options the project **actually** uses — you'll prune the spec down to those.

## Step 3 — Write the openRuyi spec

Create `rocm-specs/SPECS/<pkg>/<pkg>.spec` by adapting the Fedora spec (or writing
fresh) to satisfy every rule in `reference/declarative-build.md`. The essentials:

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

## Step 4 — Commit

```bash
git -C rocm-specs add SPECS/<pkg>
git -C rocm-specs commit -m "<pkg>: init"
git -C rocm-specs push
```

If you want to mirror the historical two-step (import, then reformat), make the
first commit a faithful import and a second `"<pkg>: reformat"` for the declarative
rewrite. For a spec written clean from the start, a single well-formed
`"<pkg>: init"` is fine.

## Step 5 — Trigger the OBS build

If the OBS package **already exists**, the push in Step 4 already triggered a
rebuild — you're done (don't poll; see SKILL.md). If it **doesn't exist yet**,
create it (details and the `_service` template in `reference/obs.md`):

```bash
wsl.exe -d ubuntu-26.04 -- bash -lc 'cd ~/Repo/package-workflow/home:Sakura286:ROCm_PyTorch_Submit \
  && osc mkpac <pkg> \
  && cp python-torch/_service <pkg>/_service'
# edit <pkg>/_service: change the extract path to SPECS/<pkg>/*
wsl.exe -d ubuntu-26.04 -- bash -lc 'cd ~/Repo/package-workflow/home:Sakura286:ROCm_PyTorch_Submit/<pkg> \
  && osc add _service && osc ci -m "<pkg>: init"'
```

After a clean `osc ci`, **stop**. The user reviews the build and returns a log if a
fix is needed (→ `workflows/fix-build.md`).
