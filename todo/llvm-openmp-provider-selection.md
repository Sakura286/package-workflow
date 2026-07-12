# TODO: define policy for LLVM OpenMP provider ambiguity and unversioned symlinks

- **Status:** open / deferred (2026-07-12)
- **Packages involved:** `libomp`, `libomp22`, `libomp23`, `python-torch`,
  `python-triton`, `llvm-defaults`
- **Found while:** building `python-triton` in `home:Sakura286:ROCm_724`

## Symptom 1: OBS solver cannot choose a provider

Adding `BuildRequires: python3dist(torch)` for Triton's import check produced:

```text
unresolvable:
have choice for libomp.so()(64bit) needed by python-torch: libomp22 libomp23
have choice for libomp.so(VERSION)(64bit) needed by python-torch: libomp22 libomp23
```

The exact result can be queried with:

```bash
osc -A https://pickaxe.oerv.ac.cn results \
  home:Sakura286:ROCm_724 python-triton \
  -r amd64_build -a x86_64 -v
```

## Symptom 2: selecting the versioned runtime is insufficient

An explicit `BuildRequires: libomp22` resolved the solver choice, but `%check`
still failed when `triton.tools.mxfp` imported torch:

```text
ImportError: libomp.so: cannot open shared object file: No such file or directory
```

`libomp22` provides the real versioned runtime under the LLVM directory, but it
does not provide the unversioned `%{_libdir}/libomp.so` compatibility symlink
expected by the built `python-torch` RPM.

The successful package fix was `BuildRequires: libomp`, using the target
project's `llvm-defaults` wrapper. That wrapper requires the LLVM 22 runtime and
provides a corrected unversioned symlink.

Relevant log:

```text
log/python-triton-01.log
```

## Related Base/QEMU observation

The long-lived QEMU VM had Base `libomp-22-12.1.or`, whose symlink was:

```text
/usr/lib64/libomp.so -> llvm22/lib64/libomp.so
```

The target did not exist. The real library was:

```text
/usr/lib64/llvm22/lib/x86_64-openruyi-linux/libomp.so
```

`rocm-specs-7.2.4/SPECS/llvm-defaults` already carries a downstream correction,
but its EVR/provider interaction with the newer Base package needs a separate
policy discussion.

## What is already established

- This was not a missing Triton runtime dependency; it entered through the
  check-only `python3dist(torch)` dependency.
- Merely choosing `libomp22` fixes solver ambiguity but not the unversioned
  runtime lookup.
- Excluding `triton.tools.mxfp` would hide the broken torch runtime in the
  buildroot rather than resolve it.
- The final `python-triton` build succeeded with the generic `libomp` wrapper.

## Questions to settle

1. Should packages select the generic `libomp`, a versioned `libompNN`, or both?
2. Which package should own the unversioned `libomp.so`/`libompd.so` symlinks?
3. How should OBS prefer LLVM 22 when Base simultaneously exposes LLVM 22 and 23
   providers?
4. How should the downstream `llvm-defaults` EVR be ordered against Base so its
   corrected wrapper is actually selected on upgrades?
5. Should `python-torch` encode a direct LLVM-major runtime dependency rather
   than relying only on automatic `libomp.so` requirements?

## Next steps

Open a dedicated session, inspect the current Base and `llvm-defaults` package
metadata (`Provides`, `Requires`, `Obsoletes`, EVR), and choose an ownership and
provider-selection policy before generalizing this workaround to other specs.
