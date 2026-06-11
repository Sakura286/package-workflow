# Reference: OBS / osc

Coordinates for the OBS instance used by this stack:

| | |
|---|---|
| API | `https://pickaxe.oerv.ac.cn` |
| Project | `home:Sakura286:ROCm_PyTorch_Submit` |
| Repo | `amd64_build` |
| Arch | `x86_64` (some packages also `riscv64`) |
| Local checkout | `home:Sakura286:ROCm_PyTorch_Submit/` (one subdir per package) |

## Running osc from this machine

The Bash/PowerShell tools here run on Windows; `osc` is installed **inside WSL**
(`/usr/bin/osc`), not on the Windows PATH. Wrap every osc invocation through WSL:

```bash
wsl.exe -d ubuntu-26.04 -- bash -lc 'cd ~/Repo/package-workflow && osc -A https://pickaxe.oerv.ac.cn <args>'
```

Credentials are already cached in WSL — osc runs non-interactively. Inside the OBS
checkout directory the apiurl is stored in `.osc/`, so plain `osc <cmd>` works there
without `-A`. `git` does **not** need the bridge — `git -C //wsl.localhost/...`
(or `git -C <abs-path>`) works directly from the Windows-side shell.

## Commands

**Build status** (CSV: repo,arch,package,state,dirty,code,details):

```bash
osc -A https://pickaxe.oerv.ac.cn results home:Sakura286:ROCm_PyTorch_Submit <pkg> -r amd64_build -a x86_64 --csv
```

**Fetch the build log** (`rbl` = remotebuildlog). Save to `log/<pkg>-<NN>.log`,
where `<NN>` is one past the latest existing log for that package:

```bash
osc -A https://pickaxe.oerv.ac.cn rbl home:Sakura286:ROCm_PyTorch_Submit <pkg> amd64_build x86_64
```

**Trigger a rebuild.** `obs_scm` never polls the remote repo and this OBS has no
webhook; a trigger happens one of three ways:

1. **Automatic (the normal path):** `git push github main` on `rocm-specs`. The
   repo's GitHub Actions workflow (`.github/workflows/trigger-obs.yml`) diffs the
   push and, for every changed `SPECS/<pkg>/`, POSTs the OBS trigger API:
   `POST https://pickaxe.oerv.ac.cn/trigger/runservice?project=…&package=…` with
   header `Authorization: Token <secret>`. The secret is a global runservice
   token (`osc token --create --operation runservice`) stored as the GitHub repo
   secret `OBS_TRIGGER_TOKEN`.
2. **Manual workflow re-run:** GitHub → Actions → "Trigger OBS services" → Run
   workflow with `package=<pkg>` (useful after a 404 for a freshly created
   package, or when a run failed).
3. **Manual via osc:**

```bash
osc -A https://pickaxe.oerv.ac.cn service rr home:Sakura286:ROCm_PyTorch_Submit <pkg>
# rebuild without re-running services:
osc -A https://pickaxe.oerv.ac.cn rebuildpac home:Sakura286:ROCm_PyTorch_Submit <pkg> amd64_build x86_64
```

## Watching a build round: `scripts/watch-obs.sh`

`scripts/watch-obs.sh <pkg> [pkg...]` (bash, runs inside WSL) waits for the
pushed commit to be picked up by the OBS service, then polls `osc results`
until every repo/arch of every named package reaches a final state. One stdout
line per event — run it under the **Monitor tool** with `persistent: true` so
each event wakes the agent and the watch survives multi-hour builds:

```
wsl.exe -d ubuntu-26.04 -- bash -lc '~/Repo/package-workflow/scripts/watch-obs.sh <pkg> [pkg...]'
```

Events:

```
TRIGGERED <pkg> <hash>              service picked up the pushed commit
TRIGGER-TIMEOUT <pkg> …             commit never appeared — Actions run lost;
                                    fall back to `osc service rr`, restart watcher
RESULT <pkg> <repo>/<arch> <code>   one build row reached a final state
WARN …                              repeated API failures (watch continues)
DONE <n> failed / <m> rows final    all rows final; watcher exits
```

Final codes: `succeeded | failed | unresolvable | broken | excluded | disabled`.
Exit 0 when nothing failed, 1 otherwise.

Env knobs: `POLL` (status poll seconds, default 60), `TRIGGER_TIMEOUT`
(default 900), `EXPECT_COMMIT` (default: current rocm-specs HEAD),
`SKIP_TRIGGER_CHECK=1` (watch the current round as-is — ad-hoc status watching,
or after a manual `service rr` of an old commit).

Notes:

- A `RESULT` only fires after **two consecutive clean (`dirty=False`) final
  reads**, so the stale pre-rebuild status right after a service run can't end
  the watch early.
- After pushing a fix mid-round, **TaskStop the old watcher and arm a fresh
  one** — its row state belongs to the previous round.
- A package is watched on *all* repos it builds for (amd64_build and, where
  enabled, riscv64_build); `blocked` (waiting on deps) counts as in-progress.

### Quoting trap: `$` dies on the wsl.exe command line

Git Bash rewrites `'…'` as `"…"` when building the Windows command line, and
wsl.exe hands that line to the WSL login shell to parse — so `$?`, `$$`, and
`$vars` are expanded by the *outer* WSL shell before the inner command runs
(`…; echo $?` always prints 0). Keep wsl.exe one-liners free of `$`; logic that
needs variables belongs in a script stored inside WSL (like watch-obs.sh).
Plain literal commands — everything else in this file — are unaffected.

## Creating a new OBS package

Only when the package isn't in the project yet. From the local checkout:

```bash
cd home:Sakura286:ROCm_PyTorch_Submit
osc mkpac <pkg>
cp python-torch/_service <pkg>/_service     # start from a known-good _service
# edit <pkg>/_service: set the extract path to SPECS/<pkg>/*
cd <pkg>
osc add _service
osc ci -m "<pkg>: init"
```

`osc ci` uploads `_service`, and OBS runs it to pull the spec from git and build.
After a clean `ci`, arm the watcher (see above) instead of polling — the `ci`
itself ran the service, so use `SKIP_TRIGGER_CHECK=1` if the spec commit was
already on `main` before the package existed on OBS.

### `_service` template (current form, with `exclude`)

```xml
<services>
  <service name="obs_scm">
    <param name="scm">git</param>
    <param name="url">https://github.com/Sakura286/rocm-specs</param>
    <param name="revision">main</param>
    <param name="exclude">*</param>
    <param name="extract">SPECS/<pkg>/*</param>
  </service>
  <service name="download_files"></service>
</services>
```

Only the `extract` path changes per package. The `download_files` service fetches
the `Source0:` tarball declared by the `#!RemoteAsset` line.

## Log naming

The convention is `<pkg>-<NN>.log` with a manually incremented two-digit sequence,
occasionally with an arch or status suffix (`amdsmi-04-riscv64.log`,
`python-torch-02-success.log`). When you fetch a log, follow this convention — pick
the next `<NN>`.
