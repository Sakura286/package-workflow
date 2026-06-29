# Reference: running from a Windows host (WSL bridge)

**The default is native Linux** — `osc`/`git` are on PATH and you run every
command directly from `~/Desktop/package-workflow`; `$` works normally. Every
command example in this skill is written in that bare form. This file only
matters when you are driven from a **Windows host** instead: the workspace lives
on the WSL filesystem, so a Windows shell has to reach it through WSL.

## Detect where you are

```bash
command -v osc >/dev/null && echo "osc on PATH — run directly" || echo "no osc — likely Windows host, wrap via WSL"
```

- **Native Linux or inside WSL** (`osc` on PATH): run every command **directly**;
  `$` works normally. This is the default the skill assumes — nothing here applies.
- **Windows host** (shells are PowerShell + Git-Bash, `osc` not on PATH, repo at
  `\\wsl.localhost\ubuntu-26.04\…`): wrap every osc/git command through WSL, below.

## The wrapper

Run any inner command inside the `ubuntu-26.04` distro (`-d` is case-insensitive):

```bash
wsl.exe -d ubuntu-26.04 -- bash -lc 'cd ~/Desktop/package-workflow && <CMD>'
```

- The `cd ~/Desktop/package-workflow` is the **one** path that can't be relative
  (the `bash -lc` shell starts in a different cwd) — it's the workspace checkout
  inside WSL; adjust it if yours lives elsewhere. `<CMD>` itself is the bare,
  workspace-root-relative command from the skill.
- Applies to **both** `osc` and `git` — plain Windows-side
  `git -C //wsl.localhost/...` hits "dubious ownership", so route git through the
  same bridge.
- Credentials are cached in WSL, so `osc` runs non-interactively. Inside an OBS
  checkout the apiurl is stored in `.osc/`, so plain `osc <cmd>` works without `-A`.

So a bare example from the skill like:

```bash
osc -A https://pickaxe.oerv.ac.cn results home:Sakura286:ROCm_PyTorch_Submit <pkg> -r amd64_build -a x86_64 --csv
```

becomes, on a Windows host:

```bash
wsl.exe -d ubuntu-26.04 -- bash -lc 'cd ~/Desktop/package-workflow && osc -A https://pickaxe.oerv.ac.cn results home:Sakura286:ROCm_PyTorch_Submit <pkg> -r amd64_build -a x86_64 --csv'
```

## Quoting trap: `$` dies on the wsl.exe command line

Git Bash rewrites `'…'` as `"…"` when building the Windows command line, and
wsl.exe hands that line to the WSL login shell to parse — so `$?`, `$$`, and
`$vars` are expanded by the *outer* WSL shell before the inner command runs
(`…; echo $?` always prints 0). Keep wsl.exe one-liners free of `$`; logic that
needs variables belongs in a script stored inside WSL (like `scripts/watch-obs.sh`).
Plain literal commands are unaffected.
