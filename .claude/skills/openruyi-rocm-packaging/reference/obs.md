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
**After a clean `ci`, stop** — don't poll the build (see SKILL.md).

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
