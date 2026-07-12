# TODO: define a reusable runtime smoke-test policy for compiler/JIT packages

- **Status:** open / deferred (2026-07-12)
- **Scope:** `openruyi-rocm-packaging` skill and ROCm/PyTorch compiler/JIT packages
- **Found while:** migrating `python-triton` 3.7.1 to `rocm-specs-7.2.4`

## Why this needs a separate decision

An RPM can build successfully and pass import-all checks while a real runtime
path is broken. During the Triton migration, the AMD-only packaging patch
removed `triton.experimental.gluon.nvidia`, assuming it was NVIDIA-backend-only.
The wheel's import check passed because removed modules are absent from the
generated module list. A later `TRITON_INTERPRET=1` vector-add failed because
native `specialize.cc` unconditionally imports the pure-Python NVIDIA
`TensorDescriptor` type when initializing its common specialization cache.

Temporarily restoring the three descriptor files made the same kernel pass.
The final package retains those pure-Python types without restoring the NVIDIA
codegen backend.

## Candidate validation levels to consider

This is a proposal for later discussion, not an accepted skill rule.

1. **Package contents:** confirm expected backend, plugin, metadata, and helper
   files are present or intentionally absent.
2. **Imports:** import the public module plus backend-specific and optional
   modules used by consumers.
3. **Dynamic linking:** run `ldd`/`readelf` on native extensions and reject
   `not found` or an unintended toolchain SONAME/path.
4. **Frontend/interpreter execution:** execute one small deterministic kernel or
   compiled function without claiming that this validates GPU code generation.
5. **JIT host path:** exercise runtime compilation of any generated host
   launcher/helper when the package has one.
6. **Device execution:** when `/dev/kfd`, render nodes, and `rocminfo` are
   available, compile and launch a minimal AMDGPU kernel and validate its result.
7. **Consumer integration:** optionally test the exact public entry point used
   by a primary consumer, such as a framework compiler or inference engine.

## Questions to settle

- Which levels should be mandatory for every compiler/JIT package, and which
  should be package-specific?
- Should smoke scripts live beside each spec, under `scripts/`, or only in test
  documentation?
- Which levels belong in OBS `%check` versus post-build QEMU/GPU testing?
- How should results distinguish interpreter/CPU validation from real ROCm
  device execution?
- What is the minimum stable kernel/function that avoids benchmarking or
  hardware-generation-specific assumptions?

## Reproduction from the Triton case

The original failing path was:

```bash
TRITON_INTERPRET=1 python3 tmp/triton-interpreter-smoke.py
```

It raised:

```text
ModuleNotFoundError: No module named 'triton.experimental.gluon.nvidia'
```

After retaining the descriptor package, the output was:

```text
triton=3.7.1 torch=2.11.0 interpreter_vector_add=PASS
```

The QEMU VM had no `/dev/kfd`, so this did not validate AMDGPU compilation or
device launch.

## Next steps

1. Decide the mandatory validation levels and where their scripts should live.
2. Trial the policy on two unlike packages before adding it to the skill.
3. Keep the wording capability-based: a test must state what it proved and what
   it could not prove in the available environment.
