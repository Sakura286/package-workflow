# TODO: validate hipSPARSELt GPU targets on the SG2044 Radeon test machines

- **Status:** open / deferred (2026-07-12)
- **Scope:** `rocm-specs-7.2.4/SPECS/hipsparselt/hipsparselt.spec`, ROCm 7.2.4
- **Test hardware:** SG2044 with either an RX 7900 XTX (`gfx1100`) or an RX
  9070 XT (`gfx1201`); only one GPU can be installed at a time

## Symptom / risk

The spec currently configures hipSPARSELt with:

```spec
BuildOption(conf):  -DGPU_TARGETS="gfx942;gfx950"
```

Neither Radeon test target (`gfx1100` or `gfx1201`) is in that list. The
`build_test` bcond is also disabled, so the current OBS repository contains the
runtime and devel RPMs but no `hipsparselt-test` RPM. We therefore have no
device-execution result for either Radeon card.

This is a risk, not yet a confirmed runtime bug. hipSPARSELt may intentionally
support only particular GPU families or structured-sparsity instructions.
Confirm the upstream support boundary before changing `GPU_TARGETS` or filing
an upstream issue.

## What has been confirmed

- The literal target list above is present in the 7.2.4 spec.
- `%bcond build_test 0` controls both `BUILD_CLIENTS_TESTS` and creation of the
  `hipsparselt-test` subpackage.
- `home:Sakura286:ROCm_724` currently builds `hipsparselt` successfully for
  `riscv64_build/riscv64`, but build success does not exercise a GPU.
- The current riscv64 published repository has no `hipsparselt-test.rpm`.

No SG2044 runtime result has been collected, and no conclusion has been made
about whether Radeon support is expected upstream.

## Reproduction / audit

Run from the workspace root:

```bash
rg -n 'bcond build_test|GPU_TARGETS|BUILD_CLIENTS_TESTS' \
  rocm-specs-7.2.4/SPECS/hipsparselt/hipsparselt.spec

osc -A https://pickaxe.oerv.ac.cn ls -b \
  home:Sakura286:ROCm_724 hipsparselt riscv64_build riscv64
```

After a test-enabled RPM exists, install it on the SG2044 and repeat the
upstream smoke/full client tests once with the RX 7900 XTX and once with the RX
9070 XT. Record `rocminfo`, PCI ID, GPU UUID, reported gfx target, exact RPM
NEVRA, command line, exit status, and complete log for each physical card.

## Next steps

1. Check the ROCm 7.2.4 hipSPARSELt documentation and source for its supported
   GPU architectures and any hardware requirements for structured sparsity.
2. Determine whether `gfx1100` and/or `gfx1201` are supported, unsupported, or
   merely absent from the packaging target list.
3. Split build-time test generation from test execution if necessary: OBS has
   no GPU, but it should be able to produce a `hipsparselt-test` RPM for the
   SG2044.
4. If upstream supports either Radeon target, generate the required Tensile
   artifacts/code objects and run the packaged upstream tests on that card.
5. If a supported target fails, reduce it to the smallest upstream client case
   and compare against an upstream-supported x86_64 environment before filing.
6. Make any spec changes as a dedicated `hipsparselt` commit using the required
   `CHEN Xuan <chenxuan@iscas.ac.cn>` identity.

