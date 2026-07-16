# `dnf5` transactions fail after the Base `rpm` 6 upgrade

## Symptom

In the openRuyi Creek x86_64 QEMU image used for the ROCm autotest, the first
large Base-only dependency installation upgraded `rpm` from 4.20.1 to
`rpm-6.0.1-12.4.or`. Every later `dnf5 install` downloaded and checksum-verified
its packages, then failed immediately at the transaction stage with only:

```text
Running transaction
Transaction failed: Rpm transaction failed.
```

This affected `rsync`, `xxhash`, `perl-File-Which`, and `perl-URI`, including
when `dnf5` was invoked with `--nogpgcheck`.

## What has been ruled out

- Base metadata resolution and package downloads succeeded.
- `/var/log/dnf5.log` records RPM verify and transaction start/stop callbacks,
  but no underlying transaction error.
- `rpm -ivh --test --nosignature` accepted the cached packages.
- `rpm -ivh --nosignature` installed the same cached packages successfully.
- The affected guest currently has `dnf5-5.4.2.0-11.3.or`,
  `libdnf5-5.4.2.0-11.3.or`, and `rpm-6.0.1-12.4.or`.

The evidence narrows the problem to the `dnf5`/RPM transaction or signature
policy path, but does not yet establish which component is at fault.

## Reproduction

Start from a fresh copy of the same x86_64 image, enable only Base, and run:

```bash
sudo dnf --disablerepo=obs-rocm install -y \
  beakerlib python-six gcc-c++ cmake rpm file binutils gawk glibc gcc make
rpm -q rpm dnf5 libdnf5
sudo dnf --nogpgcheck --disablerepo=obs-rocm install -y rsync
sudo tail -n 200 /var/log/dnf5.log
```

The observed result was a successful first transaction, followed by the
generic RPM transaction failure while installing `rsync`.

## Next steps

1. Reproduce on a disposable fresh image while retaining the pre-upgrade and
   post-upgrade RPM/DNF package sets.
2. Capture `strace` and RPM debug output for the failing `dnf5` transaction.
3. Test whether importing the Base signing key changes the result separately
   from `--nogpgcheck`.
4. Check whether upgrading `dnf5`/`libdnf5` together with `rpm`, or rebuilding
   them against the shipped RPM 6 libraries, resolves the failure.
5. Report or fix the responsible openRuyi package once the failing boundary is
   proven.
