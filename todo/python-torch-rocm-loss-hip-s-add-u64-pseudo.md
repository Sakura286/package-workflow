# python-torch:rocm — Loss.hip 崩溃:`S_ADD_U64_PSEUDO` 漏到 MC (llvm 22.1.8 codegen bug)

**状态:已用 workaround 绕过(2026-07-11)。** 单文件 `-O0`(切 GlobalISel)让 Loss.hip 编译通过 →
`Patch2008-loss-hip-O0-workaround-llvm22-codegen.patch`(commit `b0e8759`)。底层 llvm22
SelectionDAG codegen bug 仍在——**待系统 toolchain 修复后撤销该补丁**(把 Loss.hip 恢复 -O3)。
下面保留完整分析供撤销/复查时参考。cpu flavor 早已全绿。
**项目/包:** `home:Sakura286:ROCm_724` 的 `python-torch:rocm`,`amd64_build/x86_64`。
**spec 仓库:** `rocm-specs-7.2.4` 分支 `7.2.4`,当前 HEAD `559be48`(含有效的 device-lib 修复)。

## 症状

`%build` 编译 `aten/src/ATen/native/hip/Loss.hip` 时(ninja 步骤 ~`[1701/2528]`,~746s),clang 22.1.8 后端崩溃:

```
fatal error: error in backend: Unsupported instruction : <MCInst 4399 <MCOperand Reg:7675> <MCOperand Reg:7679> <MCOperand Reg:7675>>
clang++: error: clang frontend command failed with exit code 70
```

HIP 编译,`--offload-arch=gfx1100 gfx1101 gfx1200 gfx1201`,编译器 `/usr/lib64/llvm22/bin/clang++`(系统 llvm22 = `22.1.8-14.4.or`)。

## 根因(已查明)

**opcode 4399 = `S_ADD_U64_PSEUDO`**(SIInstructions.td:399)—— 一条**均匀(标量)64-bit 加法伪指令**(`(set SReg_64, (UniformBinFrag<add> i64, i64))`,`usesCustomInserter=1, Defs=[SCC]`)。操作数 `<Reg7675, Reg7679, Reg7675>` 即 dst==src1 的累加。

它本该在 isel 阶段由自定义插入器 `Expand64BitScalarArithmetic`(`SIISelLowering.cpp:5425`)展开(gfx11 → `S_ADD_U32`+`S_ADDC_U32`+`REG_SEQUENCE`;gfx12 `hasScalarAddSub64` → 原生 `S_ADD_U64`)。但它**未被展开就漏到了 MC 编码阶段** → 伪指令无编码 → `MCCodeEmitter::reportUnsupportedInst`(`llvm/lib/MC/MCCodeEmitter.cpp`)。`Expand64BitScalarArithmetic` 本身读过是正确的,所以漏出来的这条是**某条 isel 之后的路径**新造、绕过了自定义插入器展开。

这是 **llvm 22.1.8 对 64-bit 规约/标量加法伪指令展开的 codegen bug**。`S_ADD_U64_PSEUDO` 在 LLVM 源码里只出现在 wave/DPP 规约相关代码(`lowerWaveReduce`,SIISelLowering.cpp:6016 等)。匹配的上游修复 PR(**都在 22.1.8 之后 merge 到 main**):#170811/#170812(wave reduce **double**,2026-01)、#189225/#189226(**DPP** wave reduction **long** types,2026-04)、#194810(i16)。

## 已排除

- **非 device-lib 路径**:那个修复(commit `b59b38a`,HIPFLAGS 加 `--rocm-device-lib-path=$(clang -print-resource-dir)/amdgcn/bitcode`)**有效**——configure 通过,编译推进到 1701/2528 才崩。见 [[rocm-clang22-device-lib-path]]。
- **非长跳转**:`-mllvm --amdgpu-s-branch-bits=15` 已进入编译调用(log 确认),Loss.hip 报**完全相同**的错。
- **非 arch 特定**:只编 `gfx1100;gfx1101`(纯 RDNA3)时报**同一个** MCInst 4399。其它 ROCm 包(rocblas/miopen/rocsolver)用相同 gfx1100-1201 都编译成功 → gfx codegen 总体正常。
- **非 true16**:`-Xclang -target-feature -Xclang -real-true16` 被 clang **前端**特性名校验拒绝(device+host 都报 "not a recognized feature",~6×/文件,807 次),根本没传到后端;而且指令根本不是 true16。**结论:clang flag 无法禁用后端 subtarget 特性**(前端不放行)。
- **非 atomic optimizer**:Loss.cu **无** atomicAdd(include 只有 elementwise `Loops.cuh`,无 cub/warp-reduce)。`-mllvm --amdgpu-atomic-optimizer-strategy=None`(值 DPP/Iterative/None,默认 Iterative,flag 在 AMDGPUTargetMachine.cpp:429)很可能是 no-op——**未测**。

## 复现

```bash
osc -A https://pickaxe.oerv.ac.cn rbl home:Sakura286:ROCm_724 python-torch:rocm amd64_build x86_64
```
已存日志:`log/python-torch-13.log`(4 arch)、`log/python-torch-14-rdna3only.log`(仅 gfx1100;1101)、`log/python-torch-15-true16.log`(带被拒的 true16 flag)。

## 定位指令的方法(可复用)

host 的 `llvm-tblgen` 是 v21,**无法**解析 v22 的 .td(报 `HwMode ... does not have a field named Features`)。已用完整源码 `src/llvm-project-22.1.8`(tag `llvmorg-22.1.8`)构建了 v22 tblgen:

```bash
# 已构建:tmp/llvm-tblgen-build/bin/llvm-tblgen (v22.1.8)
cd src/llvm-project-22.1.8
../../tmp/llvm-tblgen-build/bin/llvm-tblgen -gen-instr-info llvm/lib/Target/AMDGPU/AMDGPU.td \
  -I llvm/lib/Target/AMDGPU -I llvm/include -I llvm/lib/Target -o out.inc
grep -E "= 4399[,;]?$" out.inc      # -> S_ADD_U64_PSEUDO
```
枚举已存:`tmp/instrenum/amdgpu-instr.inc`。

## 进展(2026-07-11 会话)

- **Step 1 上游检索 = 无解。** `S_ADD_U64_PSEUDO` 在 llvm 后端只由 isel 期产生(`SIISelLowering.cpp` + `SIInstrInfo.cpp getVALUOp` S→V),`Expand64BitScalarArithmetic` 无"漏展开"分支;上游近期改动清一色是 **wave-reduce 功能新增**(#189225 DPP-long add/sub、#170811 double min/max),**不是**通用展开修复。Loss.cu 也不用 `wave.reduce`/atomicAdd(归约是共享内存树形,Loss.cu:254-260)。**没有可 bump 到 `release/22.x` 的现成修复。** ROCm/pytorch issue tracker 亦无同错误。
- **Step 2 `-global-isel=0` = no-op。** 崩溃编译是 `-O3` HIP,AMDGPU 在 `-O1+` 默认 **SelectionDAG**(GISel 仅在显式传 `-global-isel`/`-fglobal-isel` 或 `-O0` 时启用,命令行里没有)。强制 `global-isel=0` = 现状。已放弃。
- **Step 3 尝试 A:单文件 `-O1` = 失败。** 新增补丁 `2008-loss-hip-*-workaround-llvm22-codegen.patch`(在 `caffe2/CMakeLists.txt` 的 `if(USE_ROCM)` 块内对 `Loss.hip` 单 TU 设 `COMPILE_OPTIONS`,排在 `-O3` 后生效)。`-O1` 确认生效(log 命令行 `-O3 ... -O1`)但**仍崩同一条 MCInst 4399** → 证明**在 SelectionDAG 内降 opt 级别不管用**,这条均匀 i64 标量加法在 `-O1` 下同样漏展开。log:`tmp/python-torch-16-O1.log`。
- **Step 3 尝试 B:单文件 `-O0`(切 GlobalISel)= 验证中。** commit `b0e8759`。`-O0` 使该 TU 换用 GlobalISel 选择器(完全不同路径)。**若成功即解锁 rocm flavor**(代价:nll_loss device 代码无优化,临时可接受)。

## 下一步(若 `-O0` 也失败)

- **GISel 路径同样坏 → 更深的 toolchain codegen bug,扰动路线穷尽。** 升级重型 IR 诊断:
  1. 从 `src/llvm-project-22.1.8` 构建**本地 AMDGPU `llc`/`llvm-mc`**(已有 `tmp/llvm-tblgen-build` 的 cmake 配置,加 `-DLLVM_TARGETS_TO_BUILD=AMDGPU` 重配后 `ninja llc llvm-mc`),使后端崩溃可离线零成本复现/二分。
  2. 从 OBS 捞失败 device IR:spec 里给 Loss.hip 加 `-save-temps` 或专门诊断编译,把 gfx1100 的 `.bc`/`.ll` 输出到构建日志(远程农场只回传日志,需 dump 到 stdout)。
  3. 本地 `llc -mcpu=gfx1100 loss.bc` 复现 → 二分定位产生未展开 `S_ADD_U64_PSEUDO` 的具体函数/pass → 针对性源码 workaround 或确认需 Base 级 llvm22 override/bump。

## 约束

系统 llvm22 是 **Base 包**,重建/打补丁是 Base 级、编译数小时,不适合快速迭代——真正修复走"上游修复进 release/22.x → Base bump",或 Base 级 override。相关:[[llvm-defaults-dangling-libomp-symlink]](libomp override 的前例)、[[migrate-rocm-724-into-openruyi]]。
