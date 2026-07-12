# Reference: Testing in openRuyi Environments

Two environments for verifying built RPMs in a real openRuyi system.

## QEMU VM (x86_64) — preferred

KVM-accelerated, native speed. Use it for x86_64 RPM installation, dependency
resolution, imports, dynamic linking, binaries, and CPU-side runtime tests. Do
not claim ROCm device execution unless the VM has GPU passthrough, `/dev/kfd`, a
render node, and a working `rocminfo`.

### Prerequisites

- Image: `qemu/openruyi-virt_x86-64.tar.zst` (extract to `qemu/openruyi-virt_x86-64/`)
- KVM: `/dev/kvm` must exist
- QEMU: `qemu-system-x86_64` installed

### Connection and lifecycle

```
SSH:  ssh -p 2222 openruyi@localhost    (password: openruyi)
SCP:  scp -P 2222 <file> openruyi@localhost:/tmp/
sudo: echo openruyi | sudo -S <cmd>
```

**VM startup:** The user starts the VM externally — **never start it yourself**.
If SSH fails, check whether it is running:

```bash
pgrep -c qemu-system || echo "VM not running"
```

If the VM is not running, prompt the user to start it
(`qemu/openruyi-virt_x86-64/start_vm.sh`) and wait.

### OBS Repository (pre-configured)

The VM has the OBS repo already configured at `/etc/yum.repos.d/obs-rocm.repo`:

```
[obs-rocm]
name=OBS ROCm PyTorch Submit (amd64)
baseurl=https://repo.build.openruyi.cn/home:/Sakura286:/ROCm_PyTorch_Submit/amd64_build/
enabled=1
gpgcheck=0
```

For ROCm 7.2.4 testing, update the baseurl to:
`https://repo.build.openruyi.cn/home:/Sakura286:/ROCm_724/amd64_build/`

dnf resolves dependencies across Base + OBS repos automatically.

### Test workflow

1. **Update the Base baseline before installing the test package:**
   ```
   ssh -p 2222 openruyi@localhost \
     "echo openruyi | sudo -S dnf upgrade -y --disablerepo=obs-rocm"
   ```
   A package built against the latest Base must be tested against the latest
   Base, not against stale packages retained in a long-lived VM.

2. **Check GPU capability when the test needs ROCm device execution:**
   ```
   ssh -p 2222 openruyi@localhost \
     "test -e /dev/kfd && ls /dev/dri/renderD* && rocminfo"
   ```
   If this fails, continue with install/import/link/CPU-side checks but report
   that no ROCm device kernel was executed.

3. **SCP the RPM into the VM:**
   ```
   scp -P 2222 <pkg>.rpm openruyi@localhost:/tmp/
   ```

4. **Install with dependency resolution:**
   ```
   ssh -p 2222 openruyi@localhost "echo openruyi | sudo -S dnf install -y /tmp/<pkg>.rpm"
   ```

5. **Verify installation:**
   ```
   ssh -p 2222 openruyi@localhost "rpm -q <pkg>"
   ssh -p 2222 openruyi@localhost "rpm -ql <pkg> | head -20"
   ```

6. **Python import test (for Python packages):**
   ```
   ssh -p 2222 openruyi@localhost "python3 -c 'import <module>'"
   ```

7. **Binary execution test (if applicable):**
   ```
   ssh -p 2222 openruyi@localhost "<binary> --version"
   ```

### Cleanup (REQUIRED after every test session)

```
ssh -p 2222 openruyi@localhost "echo openruyi | sudo -S dnf remove -y <pkg>"
ssh -p 2222 openruyi@localhost "echo openruyi | sudo -S dnf autoremove -y"
ssh -p 2222 openruyi@localhost "rm -f /tmp/<pkg>.rpm"
```

`dnf remove` uninstalls the tested package; `dnf autoremove` cleans up
dependencies that are no longer needed.

---

## Docker Container (riscv64)

For testing riscv64 builds. Slower (QEMU emulation), but no VM setup needed.

### Pull image

```
docker pull ghcr.io/openruyi-project/creek:latest
```

### Test workflow

1. **Mount RPM directory and install:**
   ```
   docker run --rm --platform linux/riscv64 -v "$(pwd)/tmp/obs-rpms:/mnt/rpms" \
     ghcr.io/openruyi-project/creek:latest sh -c 'rpm -ivh /mnt/rpms/<pkg>.rpm'
   ```

2. **Python import test:**
   ```
   docker run --rm --platform linux/riscv64 ghcr.io/openruyi-project/creek:latest \
     python3 -c "import <module>"
   ```

### Cleanup

Docker containers use `--rm` and are destroyed on exit. No manual cleanup needed.
