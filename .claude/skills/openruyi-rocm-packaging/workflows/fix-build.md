# Workflow: Fix a failing build

Goal: diagnose a failing OBS build from its log, fix the spec (preferably with a
properly-sourced patch), commit, and trigger a rebuild.

**Which repo/project to use:**
- **Mainline** (`rocm-specs/SPECS/<pkg>/<pkg>.spec` → `home:Sakura286:ROCm_PyTorch_Submit`): production packages
- **ROCm 7.2.4 testing** (`rocm-specs-7.2.4/SPECS/<pkg>/<pkg>.spec` → `home:Sakura286:ROCm_724`): testing ROCm 7.2.4 packages

Inputs from the user: the package name, and usually a hint that it failed. The user
may have dropped a fresh log in `log/`, or expect you to fetch it.

> Read the shared conventions in `SKILL.md` first.

## Step 1 — Get the latest log

- If the user already handed you a log, use the newest `log/<pkg>-*.log`.
- Otherwise fetch it yourself. Check status first if useful, then pull the build
  log to the next sequence number `<NN>` (one higher than the latest existing
  `log/<pkg>-*.log`):

```bash
# status (optional)
# Mainline
osc -A https://pickaxe.oerv.ac.cn results home:Sakura286:ROCm_PyTorch_Submit <pkg> -r amd64_build -a x86_64 --csv
# ROCm 7.2.4 testing
osc -A https://pickaxe.oerv.ac.cn results home:Sakura286:ROCm_724 <pkg> -r amd64_build -a x86_64 --csv

# log -> log/<pkg>-<NN>.log
# Mainline
osc -A https://pickaxe.oerv.ac.cn rbl home:Sakura286:ROCm_PyTorch_Submit <pkg> amd64_build x86_64 > log/<pkg>-<NN>.log
# ROCm 7.2.4 testing
osc -A https://pickaxe.oerv.ac.cn rbl home:Sakura286:ROCm_724 <pkg> amd64_build x86_64 > log/<pkg>-<NN>.log
```

Most ROCm packages fail on `x86_64`; some also build `riscv64`. If the failure is
arch-specific, fetch the failing arch's log (swap `x86_64` for `riscv64`).

## Step 2 — Find the real error

The decisive error is usually near the **end** of the log. Read the tail, then grep
the whole log for the failure. Useful patterns: `error:`, `Error`, `FAILED`,
`undefined reference`, `cannot find`, `No such file`, `fatal error:`, `CMake Error`,
`Could NOT find`, `ninja: build stopped`. Distinguish the first real error from the
cascade of follow-on errors it triggers.

If the error looks like the package meeting a **newer LLVM** than it was written for
— a cmake "imported target … references … but this file does not exist", a
device-libs "'__builtin_amdgcn_X' needs target feature Y", a relocated clang
header/namespace/method in comgr, or a post-bump `%files` mismatch — switch to the
**`rocm-llvm-bump`** skill, which catalogs these by build phase with upstream-sourced
fixes.

Cross-reference:
- the spec at `rocm-specs/SPECS/<pkg>/<pkg>.spec` (or `rocm-specs-7.2.4/SPECS/<pkg>/<pkg>.spec`
  for ROCm 7.2.4 testing),
- the upstream source in `src/<SourceName>/` (fuzzy match) when the error is
  in the code/build, and
- earlier logs in `log/` for the same package to see what changed.

## Step 3 — Research the fix (and cite it)

> **HARD RULE: Do NOT write any code, patch, or sed fix before completing
> this step. If you have not searched upstream for an existing fix, you are
> not ready to write one.**
>
> This applies to spec files (`SPECS/<pkg>/<pkg>.spec` and associated
> patches). It does NOT apply to OBS operations (triggering builds,
> fetching logs, etc.).

Investigate online — this is **mandatory, not optional**. Search the upstream
project's GitHub issues, PRs, and commits for the error string or symptom.
Also check other distros (Fedora, Arch, Gentoo) and this repo's history.

### Search strategy (in order)

1. **Upstream GitHub issues/PRs** — search the error message or symptom on the
   upstream repo. Use `websearch` or `webfetch` on
   `https://github.com/<org>/<repo>/issues?q=<keywords>` and
   `https://github.com/<org>/<repo>/pulls?q=<keywords>`.
2. **Upstream commits** — check if a fix was merged but not yet released:
   `https://github.com/<org>/<repo>/commits/<branch>` or
   `https://github.com/<org>/<repo>/commit/<hash>`.
3. **Other distros** — search Fedora bugzilla, Arch AUR/GitLab, Gentoo
   Bugzilla for the same error.
4. **This repo's history** — check how `rocm-specs` (or `rocm-specs-7.2.4`)
   handled this package before:

```bash
# Mainline
git -C rocm-specs log --oneline -- SPECS/<pkg>
git -C rocm-specs show <commit>
# ROCm 7.2.4 testing
git -C rocm-specs-7.2.4 log --oneline -- SPECS/<pkg>
git -C rocm-specs-7.2.4 show <commit>
```

### Fix priority

1. **Upstream has a fix** (merged PR, commit) → adopt it directly, cite the URL
2. **Another distro has a patch** → adapt it, cite the source
3. **Upstream issue has a workaround** → adopt it, cite the issue
4. **None of the above** → you may write your own fix, but note in the commit
   message that no upstream fix was found

**Record where the fix came from** — the URL goes in the patch header and the
commit message body.

## Step 4 — Apply the fix

Prefer a **patch** over ad-hoc edits, because patches are reviewable, carry their
provenance, and survive version bumps:

- Put the patch file in the spec directory (`rocm-specs/SPECS/<pkg>/` or
  `rocm-specs-7.2.4/SPECS/<pkg>/`), add `PatchN:  <file>` and apply
  it (autosetup, or `%patch -P N -p1`). Give it a descriptive name and a header
  that explains the change and links the upstream source
  (see `homepage/docs/packaging-guidelines/patches.md`).
- A small `%prep` `sed`, a flipped `BuildOption`, an added `BuildRequires`, or a
  `%files` correction is fine for **packaging-level** problems or genuinely trivial
  one-liners — don't manufacture a patch for those.
- Avoid dropping new standalone source files into the spec dir when a patch against
  the upstream tree expresses the change more honestly.

Mirror the kinds of fixes already in this repo's history: missing `BuildRequires`,
disabling/relaxing tests, `%files`/path corrections, linker flags for the AMDGPU
device link, version/coupling fixes.

### `%check` import failures — decision tree

When the openRuyi import-all-modules smoke test reports `ModuleNotFoundError` or
`ImportError` for a module:

1. **First, try to satisfy the dependency via `BuildRequires`.**  Check whether the
   missing package is already built in the OBS project
   (`osc results … <dep>`).  If it's there (or in the base distro), add
   `BuildRequires: python3dist(<dep>)` — never skip a test just because a dependency
   is absent when that dependency is available.

2. **If the module is structurally un-importable** (e.g. a `.so` that lacks a
   `PyInit_` symbol and is not a Python extension), use `BuildOption(check):  -e
   '<module>'` to exclude it.  This is the correct fix for MLIR helper libraries
   shipped alongside a Python package.

3. **If the dependency is not yet packaged at all**, stop, fetch the log, and
   present the situation to the user: explain what is missing, whether it looks like
   a trivial new package or a complex one, and ask whether to skip the failing
   import or open a new packaging task for the dependency first.  Do **not** push a
   blanket skip without this consultation.

## Step 5 — Commit and trigger the rebuild

One-line subject; add the reference URL(s) as a body when there's an upstream
source to credit:

```bash
# Mainline
git -C rocm-specs add SPECS/<pkg> && git -C rocm-specs commit -m "<pkg>: fix <issue>"   # add -m "<url>" body if citing upstream
git -C rocm-specs push github main
# ROCm 7.2.4 testing
git -C rocm-specs-7.2.4 add SPECS/<pkg> && git -C rocm-specs-7.2.4 commit -m "<pkg>: fix <issue>"   # add -m "<url>" body if citing upstream
git -C rocm-specs-7.2.4 push origin 7.2.4
```

The push to the GitHub remote is all it takes: the repo's Actions workflow
triggers the OBS service for exactly the packages whose `SPECS/<pkg>/` changed.
If the Actions run failed, fall back to a manual `osc … service rr` (see SKILL.md).

## Step 6 — Arm the watcher and loop

Don't poll in the foreground; arm the build watcher (Monitor tool,
`persistent: true`) and let its events call you back:

```
scripts/watch-obs.sh <pkg>
```

- `RESULT <pkg> … failed/unresolvable/broken` → loop back to Step 1: fetch the
  fresh log yourself, fix, push — then TaskStop the old watcher and arm a new one.
- `RESULT … succeeded` on every arch / `DONE 0 failed` → report success
  (PushNotification if the user is likely away).
- `TRIGGER-TIMEOUT` → the Actions run was lost: trigger manually
  (`osc service rr`, see SKILL.md), restart the watcher.

**Know when to stop looping.** Hand back to the user instead of pushing another
attempt when the same root error survives a fix, when ~3 attempts haven't moved
the package, when the fix requires a judgment call (version pins, disabling
tests/features beyond repo precedent, or an open-ended source port across an
LLVM/clang version bump — see the `rocm-llvm-bump` skill), or when the
failure is OBS infrastructure rather than the package. A log handed over by the
user mid-round always takes priority over watcher events.

## Step 7 — Verify in openRuyi environment (optional)

After a build succeeds, verify the package in a real openRuyi environment
**only when the user requests it**. See `reference/qemu-testing.md` for details.

For x86_64 (QEMU VM):
1. Check if VM is running (`pgrep -c qemu-system`), prompt user to start if not
2. Download the RPM from OBS: `osc api "/build/.../<pkg>/<rpm>" > /tmp/<rpm>`
3. SCP into VM: `scp -P 2222 /tmp/<rpm> openruyi@localhost:/tmp/`
4. Install: `ssh ... "echo openruyi | sudo -S dnf install -y /tmp/<rpm>"`
5. Verify: `rpm -q`, Python import, binary test
6. **Cleanup:** `ssh ... "echo openruyi | sudo -S dnf remove -y <pkg> && echo openruyi | sudo -S dnf autoremove -y"`
