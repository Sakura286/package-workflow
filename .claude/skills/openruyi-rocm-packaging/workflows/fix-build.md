# Workflow: Fix a failing build

Goal: diagnose a failing OBS build from its log, fix the spec (preferably with a
properly-sourced patch), commit, and trigger a rebuild.

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
wsl.exe -d ubuntu-26.04 -- bash -lc 'cd ~/Repo/package-workflow && osc -A https://pickaxe.oerv.ac.cn results home:Sakura286:ROCm_PyTorch_Submit <pkg> -r amd64_build -a x86_64 --csv'
# log -> log/<pkg>-<NN>.log
wsl.exe -d ubuntu-26.04 -- bash -lc 'cd ~/Repo/package-workflow && osc -A https://pickaxe.oerv.ac.cn rbl home:Sakura286:ROCm_PyTorch_Submit <pkg> amd64_build x86_64' > log/<pkg>-<NN>.log
```

Most ROCm packages fail on `x86_64`; some also build `riscv64`. If the failure is
arch-specific, fetch the failing arch's log (swap `x86_64` for `riscv64`).

## Step 2 — Find the real error

The decisive error is usually near the **end** of the log. Read the tail, then grep
the whole log for the failure. Useful patterns: `error:`, `Error`, `FAILED`,
`undefined reference`, `cannot find`, `No such file`, `fatal error:`, `CMake Error`,
`Could NOT find`, `ninja: build stopped`. Distinguish the first real error from the
cascade of follow-on errors it triggers.

Cross-reference:
- the spec at `rocm-specs/SPECS/<pkg>/<pkg>.spec`,
- the upstream source in `orig_code/<SourceName>/` (fuzzy match) when the error is
  in the code/build, and
- earlier logs in `log/` for the same package to see what changed.

## Step 3 — Research the fix (and cite it)

Investigate online — this is expected, not optional. Search the upstream project's
GitHub issues, PRs, and commits (and distro bug trackers / forums) for the error
string or symptom. Prefer adopting an upstream or another distro's fix over
inventing one. **Record where the fix came from** (the issue/PR/commit URL) — it
goes in the patch header and the commit message.

Also check how `rocm-specs` handled this package before — past commits often encode
the right approach or a related workaround:

```bash
git -C rocm-specs log --oneline -- SPECS/<pkg>
git -C rocm-specs show <commit>     # inspect a relevant past fix
```

## Step 4 — Apply the fix

Prefer a **patch** over ad-hoc edits, because patches are reviewable, carry their
provenance, and survive version bumps:

- Put the patch file in `rocm-specs/SPECS/<pkg>/`, add `PatchN:  <file>` and apply
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

## Step 5 — Commit and trigger the rebuild

One-line subject; add the reference URL(s) as a body when there's an upstream
source to credit:

```bash
git -C rocm-specs add SPECS/<pkg>
git -C rocm-specs commit -m "<pkg>: fix <issue>"   # add -m "<url>" body if citing upstream
git -C rocm-specs push github main
```

The push to the GitHub remote is all it takes: the repo's Actions workflow
triggers the OBS service for exactly the packages whose `SPECS/<pkg>/` changed
(`origin` is the retired Gitea — pushing there does nothing). If the Actions run
failed, fall back to a manual `osc … service rr` (see SKILL.md).

**Then stop — do not poll the build.** The user watches it and
returns the next log if another iteration is needed (loop back to Step 1).
