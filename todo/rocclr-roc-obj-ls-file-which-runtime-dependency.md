# `rocm-hip-devel` misses Perl runtime dependencies for `roc-obj-ls`

## Symptom

On openRuyi Creek x86_64 with `rocm-hip-devel-7.2.4-4.1.or`, invoking
`roc-obj-ls` fails before inspecting its input:

```text
Can't locate File/Which.pm in @INC ... at /usr/bin/roc-obj-ls line 25.
BEGIN failed--compilation aborted at /usr/bin/roc-obj-ls line 25.
```

After installing `perl-File-Which`, the next import fails as well:

```text
Can't locate URI/Escape.pm in @INC ... at /usr/bin/roc-obj-ls line 29.
BEGIN failed--compilation aborted at /usr/bin/roc-obj-ls line 29.
```

This was found by the openruyi-autotest GPU-less HIP offline compilation test.
Both `gfx1100` and `gfx1201` binaries compiled successfully, but code-object
inspection failed for the same reason.

## What has been ruled out

- `/usr/bin/roc-obj-ls` is owned by `rocm-hip-devel-7.2.4-4.1.or.x86_64`.
- The installed RPM requires `/usr/bin/perl`, `binutils`, and `gawk`, but does
  not require `perl(File::Which)` or `perl(URI::Escape)`.
- openRuyi Base provides the missing modules as
  `perl-File-Which-1.27-6.3.or.noarch` and `perl-URI-5.34-4.4.or.noarch`.
- `openRuyi/SPECS/rocclr/rocclr.spec` already labels `binutils` and `gawk` as
  requirements for `roc-obj-ls`, so the Perl module belongs in the same runtime
  dependency block.

## Reproduction

```bash
sudo dnf install -y rocm-hip-devel
rpm -qR rocm-hip-devel | grep -E 'perl\((File::Which|URI::Escape)\)'
roc-obj-ls /bin/true
```

The `grep` returns no matches and `roc-obj-ls` reports the missing modules in
sequence.

## Next steps

1. Add `Requires: perl(File::Which)` and `Requires: perl(URI::Escape)` to the
   `rocm-hip-devel` subpackage in the relevant `rocclr.spec` development repo.
2. Build and install the resulting RPM in a clean guest.
3. Verify that installing only `rocm-hip-devel` pulls in `perl-File-Which` and
   `perl-URI`, and that `roc-obj-ls` starts without a Perl import error.
4. Submit the corresponding one-package openRuyi spec update following the
   official repository's commit convention.
