# Reference: OBS / osc

Coordinates for the OBS instance used by this stack:

| | |
|---|---|
| API | `https://pickaxe.oerv.ac.cn` |
| Project | `home:Sakura286:ROCm_PyTorch_Submit` |
| Repo | `amd64_build` |
| Arch | `x86_64` (some packages also `riscv64`) |
| Local checkout | `home:Sakura286:ROCm_PyTorch_Submit/` (one subdir per package) |
| Spec repo | `rocm-specs` (branch `main`) |

> **Historical note:** a ROCm 7.2.4 testing rig (`rocm-specs` branch `7.2.4` →
> OBS project `home:Sakura286:ROCm_724`, local checkout `rocm-specs-7.2.4/`)
> existed until 2026-07-16, when the branch was merged into mainline
> (`21dab7d`). The OBS project and local checkouts were deleted; the `7.2.4`
> branch remains on GitHub as read-only history.

## `openruyi-obs/` — the official distro's OBS project (read-only reference)

Same instance (`https://pickaxe.oerv.ac.cn`), **different project**: `openruyi`
is the official openRuyi distribution's own OBS project — every package the
distro ships, with its real `_service`, spec, sources, and `.changes`. It is
checked out locally at `openruyi-obs/` (one subdir per package; the apiurl and
project name live in `openruyi-obs/.osc/`).

- **Read-only to us.** This is upstream's project, not ours — **never** `osc ci`
  / commit / push anything here. It is a *reference*: how the shipping distro
  actually packages a thing (naming, `_service`, build deps, patch layout), and
  a place to cross-check versions and see how a dependency of ours is built. The
  writable ROCm project above (`home:Sakura286:ROCm_PyTorch_Submit`) is the
  only one you push to.
- **Kept fresh automatically.** A user cron job runs `scripts/sync-openruyi-obs.sh`
  at 11:00 Asia/Shanghai every day; it does `osc up` in `openruyi-obs/` and
  appends a timestamped line to `log/openruyi-obs-sync.log`. To refresh on
  demand, run the script, or just `cd openruyi-obs && osc up`.
- **Not part of this git repo.** `openruyi-obs/` is in `.gitignore` — it is a
  working checkout, not tracked here. (Distinct from `openRuyi/SPECS/`, which is
  a git checkout of the distro's spec sources used the same way, for reference.)

## Running osc

`osc` and `git` are on PATH. Start from the **workspace root** defined in
`SKILL.md`; when a command needs working-copy context, enter that OBS checkout in
the command itself. Credentials are cached, so osc runs non-interactively; inside
an OBS checkout the apiurl is stored in `.osc/`, so plain `osc <cmd>` works
without `-A`. (If you are driven from a Windows host instead, wrap every osc/git
command through WSL — see `windows-wsl.md`.)

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

1. **Automatic (the normal path):** Push to the GitHub remote.
   The repo's GitHub Actions workflow (`.github/workflows/trigger-obs.yml`) diffs the
   push and, for every changed `SPECS/<pkg>/`, POSTs the OBS trigger API:
   `POST https://pickaxe.oerv.ac.cn/trigger/runservice?project=…&package=…` with
   header `Authorization: Token <secret>`. The secret is a global runservice
   token (`osc token --create --operation runservice`) stored as the GitHub repo
   secret `OBS_TRIGGER_TOKEN`.

   - Push `rocm-specs` with `git push github main` → triggers `home:Sakura286:ROCm_PyTorch_Submit`

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

`scripts/watch-obs.sh <pkg> [pkg...]` waits for the
pushed commit to be picked up by the OBS service, then watches only the gate
row `amd64_build/x86_64` (≈10× faster than riscv64) to a final state. A result
there — pass *or* fail — ends the round; **for speed, riscv64 and other arches
are not watched by default**, so the fix loop starts without waiting for the
slow arch. Pass `GATE=none` to watch every repo/arch to a final state instead.
One stdout line per
event — run it under the **Monitor tool** with `persistent: true` so each
event wakes the agent and the watch survives multi-hour builds:

```
scripts/watch-obs.sh <pkg> [pkg...]
```

`PRJ` defaults to `home:Sakura286:ROCm_PyTorch_Submit` and `EXPECT_COMMIT` to
the local `rocm-specs` HEAD — correct for the standard push-then-watch flow.

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

Env knobs: `PRJ` (OBS project, default `home:Sakura286:ROCm_PyTorch_Submit`),
`POLL` (status poll
seconds, default 60), `TRIGGER_TIMEOUT` (default 900), `EXPECT_COMMIT` (default:
current `rocm-specs` HEAD), `GATE` (gate row, default
`amd64_build/x86_64`; set `GATE=none` to watch every repo/arch),
`SKIP_TRIGGER_CHECK=1` (watch the
current round as-is — ad-hoc status watching, or after a manual `service rr` of
an old commit).

Notes:

- A `RESULT` only fires after **two consecutive clean (`dirty=False`) final
  reads**, so the stale pre-rebuild status right after a service run can't end
  the watch early.
- After pushing a fix mid-round, **TaskStop the old watcher and arm a fresh
  one** — its row state belongs to the previous round.
- By default only the `amd64_build/x86_64` gate is watched; `GATE=none` watches
  *all* repos the package builds for (amd64_build and, where enabled,
  riscv64_build). `blocked` (waiting on deps) counts as in-progress.

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
After a clean `ci`, arm the watcher when the requested outcome includes a
completed build, failure repair, or testing; otherwise stop after confirming the
trigger. The `ci` itself ran the service, so a watched build may use
`SKIP_TRIGGER_CHECK=1` if the spec commit was already on `main`
before the package existed on OBS.

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
