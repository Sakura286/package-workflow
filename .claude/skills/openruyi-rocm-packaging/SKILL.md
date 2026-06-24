---
name: openruyi-rocm-packaging
description: >-
  Packaging workflow for the openRuyi RPM distribution (RPM 4.20+ declarative
  build), focused on the ROCm/PyTorch stack maintained in the rocm-specs repo.
  Use this whenever the task involves an openRuyi/ROCm spec: adding a new package,
  upgrading a package to a new version, or fixing a failing OBS build from a log.
  Also use it for any related step — writing or reformatting a .spec under
  rocm-specs/SPECS, converting a Fedora spec to openRuyi's declarative style,
  refreshing a Source/sha256/#!RemoteAsset, rebasing patches, committing spec
  changes as CHEN Xuan, or triggering/fetching builds on OBS (osc, projects
  home:Sakura286:ROCm_PyTorch_Submit for mainline or home:Sakura286:ROCm_724 for
  ROCm 7.2.4 testing). Trigger even when the user only names a package and an
  action ("打 half 这个包", "升级 rccl 到 7.2", "修一下 hipblaslt 的构建"), or pastes a build
  error from the ROCm stack, without mentioning "spec" or "OBS".
---

## Language convention

- Think and reason in English.
- Reply to the user in Chinese.
- Technical terms and code stay in English — do not translate them.

---

# openRuyi ROCm Packaging

Workflow skill for maintaining the ROCm / PyTorch package stack in the openRuyi
RPM distribution. openRuyi uses **RPM 4.20+ declarative builds**. The
authoritative packaging guide lives in this workspace at
`homepage/docs/packaging-guidelines/` — consult it when a rule here is unclear.

## First: detect your runtime — inside WSL vs Windows host

This workspace is on the WSL filesystem, but you may be driven from **either** inside
WSL or from the Windows host, and the command form differs. **Detect before running
anything** (run this in your Bash/sh tool):

```bash
grep -qi microsoft /proc/version 2>/dev/null && echo INSIDE-WSL || echo WINDOWS-HOST
```

- **INSIDE-WSL** — `WSL_DISTRO_NAME=Ubuntu-26.04`, `osc`/`git` are on PATH. Run every
  command **directly** from `~/Repo/package-workflow`; `$` works normally.
- **WINDOWS-HOST** — your shells are PowerShell + Git-Bash, `osc` is not on PATH, the repo
  is at `\\wsl.localhost\ubuntu-26.04\…`. Wrap every osc/git command through WSL:
  `wsl.exe -d ubuntu-26.04 -- bash -lc 'cd ~/Repo/package-workflow && <CMD>'`, and keep `$`
  out of the one-liner (it gets eaten — put variable logic in a WSL script). If your only
  shell is PowerShell, you're on the Windows host.

**All command examples in this skill use the WINDOWS-HOST (wrapped) form.** If you detected
INSIDE-WSL, strip the `wsl.exe … bash -lc '…'` wrapper and run the inner command directly.

## Pick the workflow

| The user wants to… | Read |
|---|---|
| Add a brand-new package to `rocm-specs` or `rocm-specs-7.2` | `workflows/new-package.md` |
| Bump an existing package to a new version | `workflows/upgrade-package.md` |
| Fix a failing build from the latest log | `workflows/fix-build.md` |

All three end the same way: commit to the spec repo and trigger the OBS build.
The conventions below apply to every workflow — read them first, then open the
workflow file. For depth, the workflow files point into `reference/`.

**Which repo/project to use:**
- **Mainline** (`rocm-specs/main` → `home:Sakura286:ROCm_PyTorch_Submit`): production packages
- **ROCm 7.2.4 testing** (`rocm-specs-7.2/7.2.4` → `home:Sakura286:ROCm_724`): testing ROCm 7.2.4 packages

**Default rule:** Unless explicitly specified otherwise, all fixes and changes target the **mainline** (`rocm-specs` folder, not `rocm-specs-7.2`).

---

## Workspace layout

Paths are relative to the workspace root (`package-workflow/`).

| Path | What it is |
|---|---|
| `rocm-specs/SPECS/<pkg>/<pkg>.spec` | **Primary spec repo (mainline). Full write access — commit and push freely.** Lives on GitHub: `git@github.com:Sakura286/rocm-specs.git`, branch `main`. **The local remote is named `github`** — push with `git push github main`; `origin` still points at the retired Gitea instance and pushing there does nothing. |
| `rocm-specs-7.2/SPECS/<pkg>/<pkg>.spec` | **ROCm 7.2.4 testing spec repo.** Cloned from the same GitHub repo, branch `7.2.4`. Remote `origin` points to `git@github.com:Sakura286/rocm-specs.git`. Push with `git push origin 7.2.4`. |
| `rpms/<pkg>/` | Fedora rawhide reference specs, cloned from `https://src.fedoraproject.org/rpms/<pkg>.git`. Reference only — keep their `.git`, never commit them into `rocm-specs`. |
| `orig_code/<SourceName>/` | Unpacked upstream source. The directory name is a **fuzzy match** of the package name (see below). |
| `openRuyi/SPECS/` | The rest of the distro's specs. Reference for format and for how a dependency is packaged. |
| `log/<pkg>-<NN>.log` | Build logs, manually sequence-numbered. Sometimes an arch/status suffix (`amdsmi-04-riscv64.log`, `python-torch-02-success.log`). |
| `home:Sakura286:ROCm_PyTorch_Submit/` | OBS local checkout for mainline (one subdir per OBS package, each with a `_service`). |
| `home:Sakura286:ROCm_724/` | OBS local checkout for ROCm 7.2.4 testing (one subdir per OBS package, each with a `_service`). |
| `homepage/docs/packaging-guidelines/` | The openRuyi packaging guide (authoritative). |

### Matching a package to its source in `orig_code/`

The source directory is usually the upstream project name, which differs from the
spec name in **case** and sometimes entirely. Match case-insensitively and by
known aliases; confirm by reading the spec's `Url:`/`Source0:`. Examples seen here:

```
hipblaslt -> hipBLASLt      rocfft    -> rocFFT        miopen        -> MIOpen
hiprand   -> hipRAND        rocrand   -> rocRAND       fplus         -> FunctionalPlus
hipsparse -> hipSPARSE      rocthrust -> rocThrust     rocm-origami  -> origami
python-torch -> pytorch     python-triton -> triton    python-mistral-common -> mistral-common
```

If no source dir exists, download it per the spec's `Source0:` into `orig_code/`
(ROCm github: `git clone --depth=1 --branch=rocm-<ver> <repo>`; if that tag is
missing, note it in a comment and use the default branch; non-github: fetch the
tarball and extract).

---

## Git identity and commit style

The `rocm-specs` and `openRuyi` repos are configured to commit as
**`CHEN Xuan <chenxuan@iscas.ac.cn>`** (set once via `git config user.name/email`).
Never commit as Claude or any other identity. If you ever clone a fresh repo to
commit into, set this identity first (via WSL):

```bash
wsl.exe -d ubuntu-26.04 -- bash -lc 'git -C ~/Repo/package-workflow/<repo> config user.name  "CHEN Xuan"'
wsl.exe -d ubuntu-26.04 -- bash -lc 'git -C ~/Repo/package-workflow/<repo> config user.email "chenxuan@iscas.ac.cn"'
```

Commit messages mimic the existing history — **one line, `<package>: <short desc>`**,
lowercase description. A multi-line body is allowed only to add reference links
(upstream issue/PR/commit URLs) for a fix. **One package per commit.** Examples
from the log:

```
half: init
rccl: reformat
hipblaslt: use declarative building method
hiprand: build test but do not run
magma: add missing release section
python-torch: fix magma version
```

---

## SPDX header

Every spec starts with an SPDX block. **If a spec has no header, add exactly this**
(only CHEN Xuan as contributor):

```
# SPDX-FileCopyrightText: (C) 2026 Institute of Software, Chinese Academy of Sciences (ISCAS)
# SPDX-FileCopyrightText: (C) 2026 openRuyi Project Contributors
# SPDX-FileContributor: CHEN Xuan <chenxuan@iscas.ac.cn>
#
# SPDX-License-Identifier: MulanPSL-2.0
```

If a spec **already** has a header (e.g. an older one also listing Yifan Xu, or a
"Originally extracted from Fedora" note), preserve it — don't strip existing
contributors or provenance notes just to match the template.

---

## Declarative build cheat-sheet (RPM 4.20+)

The point of declarative builds is to drop boilerplate: declare the build system
and only write the **deltas**. Full details and the Fedora→openRuyi reformatting
checklist are in `reference/declarative-build.md`; the distro's own docs are under
`homepage/docs/packaging-guidelines/buildsystems/`.

- `%global toolchain clang` — the entire ROCm stack builds with clang, not gcc.
- `BuildSystem: cmake | pyproject | autotools | meson | golang | rust`.
- `BuildOption(<section>):  <opts>` — **two spaces** after the colon, and **always**
  name the section (`conf`, `build`, `install`, `generate_buildrequires`, `check`).
- Customize a stage with prepend/append instead of rewriting it:
  `%build -p` (prepend), `%install -a` (append), `%prep -a`, `%check -a`. The build
  system already supplies `%cmake`/`%cmake_build`/`%pyproject_wheel`/etc.
- Don't pass `-DCMAKE_BUILD_TYPE` — the macros set it (`RelWithDebInfo`).
- Use path macros (`%{_bindir}`, `%{_libdir}`, `%{_includedir}`, …); never hardcode.
- BuildRequires: prefer `cmake(Foo)` / `pkgconfig(foo)` / `python3dist(foo)` over
  `-devel` names — but only when such a provider actually exists.
- Ninja: `BuildOption(conf):  -G Ninja` + `BuildRequires:  ninja`.
- Source from an official **release tarball** (not a git-commit archive), with the
  checksum on a `#!RemoteAsset:  sha256:<hash>` line immediately above `Source0:`.
- `Release:  %autorelease` and a `%changelog` body of just `%autochangelog`.
- Drop Fedora-isms: `ExclusiveArch`, hardcoded `Release`/changelog entries, and
  cmake options that are redundant with the macros or absent from upstream
  `CMakeLists.txt`.

A compact, real example is `rocm-specs/SPECS/rccl/rccl.spec` (cmake);
`rocm-specs/SPECS/python-triton/python-triton.spec` shows the pyproject variant.

---

## OBS: trigger builds and fetch logs

Two OBS projects are used:

| Project | Purpose | Repo/Branch |
|---|---|---|
| `home:Sakura286:ROCm_PyTorch_Submit` | Mainline ROCm packages (production) | `rocm-specs/main` |
| `home:Sakura286:ROCm_724` | ROCm 7.2.4 testing | `rocm-specs-7.2/7.2.4` |

Both use repo `amd64_build`, arch `x86_64` (some packages also build `riscv64`).
API: `https://pickaxe.oerv.ac.cn`.
Full command reference and the `_service` template: `reference/obs.md`.

**Running osc — WINDOWS-HOST form below; strip the wrapper if you detected INSIDE-WSL**
(see "First: detect your runtime" above):

```bash
wsl.exe -d ubuntu-26.04 -- bash -lc 'cd ~/Repo/package-workflow && osc -A https://pickaxe.oerv.ac.cn <args>'
```

On the Windows host neither `osc` nor `git` is on PATH, so both go through this WSL bridge
(plain Windows-side `git -C //wsl.localhost/...` also hits "dubious ownership"). Inside the
OBS checkout the apiurl is cached in `.osc/`, so plain `osc <cmd>` works without `-A`.

**Trigger a rebuild** of an existing package: **push to the GitHub remote and the
rest is automatic** — a GitHub Actions workflow in each repo
(`.github/workflows/trigger-obs.yml`) diffs every push and calls the OBS
trigger API (`POST /trigger/runservice`, global token stored as the repo secret
`OBS_TRIGGER_TOKEN`) for each package whose `SPECS/<pkg>/` changed.

- **Mainline** (`rocm-specs`): push with `git push github main` (via WSL) —
  triggers `home:Sakura286:ROCm_PyTorch_Submit`. `origin` is the retired Gitea
  and OBS never sees pushes there.
- **ROCm 7.2.4 testing** (`rocm-specs-7.2`): push with `git push origin 7.2.4`
  (via WSL) — triggers `home:Sakura286:ROCm_724`.

(`obs_scm` never polls git and this OBS has no webhook;
the Actions workflow is the only automatic path. Details: `reference/obs.md`.)

Manual fallback (Actions run failed, or re-trigger without a push) — either
GitHub → Actions → "Trigger OBS services" → Run workflow with `package=<pkg>`, or:

```bash
# Mainline
wsl.exe -d ubuntu-26.04 -- bash -lc 'cd ~/Repo/package-workflow && osc -A https://pickaxe.oerv.ac.cn service rr home:Sakura286:ROCm_PyTorch_Submit <pkg>'
# ROCm 7.2.4 testing
wsl.exe -d ubuntu-26.04 -- bash -lc 'cd ~/Repo/package-workflow && osc -A https://pickaxe.oerv.ac.cn service rr home:Sakura286:ROCm_724 <pkg>'
```

To confirm a trigger landed, list the expanded sources — the
`rocm-specs-<stamp>.<commit>.obscpio` entry must show the new commit (the
service takes ~1-2 min; the rebuild then schedules automatically). The watcher
script below performs this check automatically; the manual form is:

```bash
# Mainline
wsl.exe -d ubuntu-26.04 -- bash -lc 'cd ~/Repo/package-workflow && osc -A https://pickaxe.oerv.ac.cn api "/source/home:Sakura286:ROCm_PyTorch_Submit/<pkg>?expand=1"'
# ROCm 7.2.4 testing
wsl.exe -d ubuntu-26.04 -- bash -lc 'cd ~/Repo/package-workflow && osc -A https://pickaxe.oerv.ac.cn api "/source/home:Sakura286:ROCm_724/<pkg>?expand=1"'
```

**Create a new OBS package** (only when it doesn't exist yet): see
`workflows/new-package.md` / `reference/obs.md` (`osc mkpac` + `_service` + `osc ci`).

**Fetch the latest build log** for a fix, into the log dir with the next sequence
number `<NN>`:

```bash
# Mainline
wsl.exe -d ubuntu-26.04 -- bash -lc 'cd ~/Repo/package-workflow && osc -A https://pickaxe.oerv.ac.cn rbl home:Sakura286:ROCm_PyTorch_Submit <pkg> amd64_build x86_64' > log/<pkg>-<NN>.log
# ROCm 7.2.4 testing
wsl.exe -d ubuntu-26.04 -- bash -lc 'cd ~/Repo/package-workflow && osc -A https://pickaxe.oerv.ac.cn rbl home:Sakura286:ROCm_724 <pkg> amd64_build x86_64' > log/<pkg>-<NN>.log
```

**After triggering — arm the watcher, never poll in the foreground.** Builds
take minutes to hours, so don't sit in a status loop. Instead, once the push (or
`osc ci`) went through, start `scripts/watch-obs.sh` under the **Monitor tool**
with `persistent: true` (builds outlive any timeout), naming the package(s) just
pushed:

```
wsl.exe -d ubuntu-26.04 -- bash -lc '~/Repo/package-workflow/scripts/watch-obs.sh <pkg> [pkg...]'
```

The script first confirms the trigger landed (expanded sources pick up the new
commit), then polls every repo/arch to a final state. Each stdout line is an
event that wakes you (full reference: `reference/obs.md`):

| Event | React |
|---|---|
| `TRIGGERED <pkg> <hash>` | nothing — trigger confirmed |
| `TRIGGER-TIMEOUT <pkg> …` | Actions run lost: manual `osc service rr`, then restart the watcher |
| `RESULT <pkg> <repo>/<arch> failed/unresolvable/broken` | fetch the log, run `workflows/fix-build.md` |
| `RESULT … succeeded` | nothing |
| `DONE <n> failed / <m> rows final` | report the round's outcome to the user |

**The autonomous fix loop:** on a failure event, fetch the log to
`log/<pkg>-<NN>.log`, diagnose and fix per `workflows/fix-build.md`, commit and
push — then **TaskStop the old watcher and arm a fresh one** for the package(s)
re-pushed (the old watcher's state belongs to the previous round). Repeat until
green. Send a PushNotification when the round goes all-green, and **stop looping
and ask the user** instead when:

- the same package fails twice with the same root error, or ~3 fix attempts
  haven't moved it;
- the fix needs a judgment call that isn't yours (version pins, disabling
  features/tests beyond the repo's precedent, anything near `llvm-21`);
- the failure is infrastructure (OBS/worker trouble), not the package.

The watcher lives only as long as the Claude Code session — if the user is
about to close it mid-build, say so. The user may still hand back a saved log
manually at any time; that path keeps working regardless of the watcher.
