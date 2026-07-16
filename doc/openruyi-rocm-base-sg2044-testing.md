# openRuyi Base ROCm SG2044 测试指南

## 1. 目的与范围

本文用于指导测试人员在 SG2044（riscv64）真机上，对已经合入 openRuyi Base 的 ROCm 基础软件包进行安装和运行时验证。测试分别使用：

- AMD Radeon RX 7900 XTX，预期架构为 `gfx1100`
- AMD Radeon RX 9070 XT，预期架构为 `gfx1201`

## 2. 本轮软件包

下表中的“源码包”对应 openRuyi spec 目录，“安装 RPM”是测试机上使用的包名。

| 源码包 | 安装 RPM |
|---|---|
| `rocm-cmake` | `rocm-cmake` |
| `rocm-llvm` | `hipcc`、`rocm-device-libs`、`rocm-comgr`、`rocm-comgr-devel`、`rocm-llvm-macros` |
| `rocr-runtime` | `rocr-runtime`、`rocr-runtime-devel` |
| `rocclr` | `rocm-hip`、`rocm-hip-devel` |
| `rocminfo` | `rocminfo` |
| `rocm-smi` | `rocm-smi`、`rocm-smi-devel` |
| `rocprofiler-register` | `rocprofiler-register`、`rocprofiler-register-devel` |
| `rocblas` | `rocblas`、`rocblas-devel` |
| `hipblas-common` | `hipblas-common-devel` |
| `hipblas` | `hipblas`、`hipblas-devel` |
| `rocsolver` | `rocsolver`、`rocsolver-devel` |
| `rocsparse` | `rocsparse`、`rocsparse-devel` |
| `rocprim` | `rocprim-devel` |
| `hipify` | `hipify` |
| `rocm-bandwidth-test` | `rocm-bandwidth-test` |
| `python-tensile` | `python-tensile` |

## 3. 安装

不需要显卡

使用测试机正常配置的 openRuyi Base 仓库，不添加额外 ROCm 仓库：

```bash
sudo dnf clean metadata
sudo dnf makecache
sudo dnf install -y gcc-c++ cmake pciutils \
  rocm-cmake hipcc rocm-device-libs \
  rocm-comgr rocm-comgr-devel rocm-llvm-macros \
  rocr-runtime rocr-runtime-devel rocm-hip rocm-hip-devel \
  rocminfo rocm-smi rocm-smi-devel \
  rocprofiler-register rocprofiler-register-devel \
  rocblas rocblas-devel hipblas-common-devel hipblas hipblas-devel \
  rocsolver rocsolver-devel rocsparse rocsparse-devel rocprim-devel \
  hipify rocm-bandwidth-test python-tensile
```

## 4. ROCm 设备信息枚举

需要显卡

使用 ROCm 自身工具枚举 GPU：

```bash
rocminfo
rocm_agent_enumerator
rocm-smi --showallinfo
hipconfig --full
```

通过条件：

- 命令不崩溃、不挂死，退出码为 0；
- `rocminfo` 能列出 CPU agent 和当前 Radeon GPU agent；
- `rocm_agent_enumerator` 包含当前显卡的 `gfx1100` 或 `gfx1201`；
- `rocm-smi` 能识别显卡。个别传感器不支持时应记录具体字段，不要只写“失败”。

## 5. HIP 编译与运行

下面的单个程序同时验证 `hipcc`、ROCm device libraries、HIP runtime、host/device 内存传输和 kernel 执行。

无显卡的情况下，手动指定 GPU_ARCH 为 gfx1100 或 gfx1201，可以进行除了执行二进制之外的所有操作

将文件保存为 `vector-add.cpp`：

```cpp
#include <hip/hip_runtime.h>
#include <cstdio>
#include <vector>

#define HIP_CHECK(expr) do {                                      \
    hipError_t e = (expr);                                        \
    if (e != hipSuccess) {                                        \
        std::fprintf(stderr, "%s\n", hipGetErrorString(e));      \
        return 1;                                                  \
    }                                                             \
} while (0)

__global__ void add(const int *a, const int *b, int *c, int n)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n)
        c[i] = a[i] + b[i];
}

int main()
{
    int count = 0;
    HIP_CHECK(hipGetDeviceCount(&count));
    if (count != 1) {
        std::fprintf(stderr, "expected 1 GPU, got %d\n", count);
        return 2;
    }

    hipDeviceProp_t prop{};
    HIP_CHECK(hipGetDeviceProperties(&prop, 0));
    std::printf("device=%s arch=%s\n", prop.name, prop.gcnArchName);

    constexpr int n = 4096;
    std::vector<int> a(n), b(n), c(n);
    for (int i = 0; i < n; ++i) {
        a[i] = i;
        b[i] = i * 2;
    }

    int *da = nullptr, *db = nullptr, *dc = nullptr;
    HIP_CHECK(hipMalloc(reinterpret_cast<void **>(&da), n * sizeof(int)));
    HIP_CHECK(hipMalloc(reinterpret_cast<void **>(&db), n * sizeof(int)));
    HIP_CHECK(hipMalloc(reinterpret_cast<void **>(&dc), n * sizeof(int)));
    HIP_CHECK(hipMemcpy(da, a.data(), n * sizeof(int), hipMemcpyHostToDevice));
    HIP_CHECK(hipMemcpy(db, b.data(), n * sizeof(int), hipMemcpyHostToDevice));

    hipLaunchKernelGGL(add, dim3((n + 255) / 256), dim3(256), 0, 0,
                       da, db, dc, n);
    HIP_CHECK(hipGetLastError());
    HIP_CHECK(hipDeviceSynchronize());
    HIP_CHECK(hipMemcpy(c.data(), dc, n * sizeof(int), hipMemcpyDeviceToHost));

    for (int i = 0; i < n; ++i) {
        if (c[i] != i * 3) {
            std::fprintf(stderr, "mismatch at %d: %d\n", i, c[i]);
            return 3;
        }
    }

    HIP_CHECK(hipFree(da));
    HIP_CHECK(hipFree(db));
    HIP_CHECK(hipFree(dc));
    std::puts("HIP vector add: PASS");
    return 0;
}
```

编译并运行：

```bash
GPU_ARCH=$(rocm_agent_enumerator | awk '/^gfx[0-9]+/ {print; exit}')
test -n "$GPU_ARCH"
hipcc --offload-arch="$GPU_ARCH" vector-add.cpp -o vector-add
file vector-add
ldd vector-add
./vector-add
```

通过条件是程序输出当前 GPU 名称、正确架构和 `HIP vector add: PASS`。

## 6. 已有工具的功能测试

### 6.1 hipify

不需要显卡

使用一个 CUDA API 调用检查转换结果：

```bash
printf '%s\n' 'void f(int *a, const cudaDeviceProp *b) { cudaChooseDevice(a,b); }' \
  > hipify-input.cu
hipify-perl hipify-input.cu -o hipify-output.cpp
grep -E 'hipDeviceProp_t|hipChooseDevice' hipify-output.cpp
hipify-clang --version
```

`hipify-perl` 应当生成 HIP API，且两个入口均可执行。此测试不要求本机安装 CUDA SDK。

### 6.2 Tensile

不需要显卡

`python-tensile` 是 rocBLAS 使用的代码生成和调优工具，验证安装完整性及Python/命令入口

```bash
python3 -c 'import Tensile; print(Tensile.__file__)'
TensileGetPath
test -d "$(TensileGetPath)"
Tensile --version
Tensile --help
```

通过条件是 Python 模块可以导入，`TensileGetPath` 指向现存目录，命令能正常输出版本和帮助

### 6.3 rocm-bandwidth-test

需要显卡

```bash
rocm-bandwidth-test
```

通过条件是工具识别当前 GPU、完成默认测试且没有崩溃或 HIP/HSA 初始化错误。

## 7. 换卡与结果记录

先用 RX 7900 XTX 完成第 3 至第 6 节，关机并人工换成 RX 9070 XT 后再执行一次。
两张卡的结果分别保存，不进行单机多卡测试。

