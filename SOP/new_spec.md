# 新建 Python RPM 包 SOP

## 背景

- **`vllm-specs/`**：git 仓库，存放所有包的 SPEC 文件，路径结构为 `SPECS/<pkgname>/<pkgname>.spec`
- **`home:Sakura286:vLLM/`**：OBS 本地工作目录（`osc co` 所得），每个子目录对应一个 OBS 包，内含 `_service` 文件

---

## 一、创建 SPEC 文件

### 步骤 1：复制模板

将 `vllm-specs/SPECS/python-template/` 目录整体复制，重命名目录及其中的 `.spec` 文件为目标包名，例如：

```
vllm-specs/SPECS/python-foo/python-foo.spec
```

### 步骤 2：替换占位符

SPEC 文件中所有 `<...>` 占位符的替换规则如下：

| 占位符 | 替换内容 | 来源 |
|---|---|---|
| `<srcname>` | PyPI 包名（即 `pip install` 时使用的名称） | 人工指定 |
| `<srcname_header>` | `<srcname>` 的第一个字母（用于构造 Source0 的 PyPI 下载 URL） | 取 srcname 首字母 |
| `<version>` | 软件包版本号 | 若无特殊要求，使用 PyPI 上的最新版本 |
| `<sha256>` | Source0 URL 对应压缩包的 SHA-256 值 | 在 PyPI 该版本的页面上直接查找，无需下载 |
| `<summary>` | 一句话简介 | 取自该包 GitHub 仓库的 About 字段 |
| `<description>` | 多行详细描述 | 取自该包 GitHub 仓库的 README |
| `<url>` | 项目主页 URL | 该包的 GitHub 仓库链接 |
| `<license>` | SPDX License 标识符 | 在 PyPI 页面的 License 字段查找 |
| `<doc_file>` | 文档文件名，通常为 `README.md` 或 `README.rst`，有时还包括 `AUTHORS`、`CHANGELOG`、`NEWS.txt` 等 | 查看源码根目录中实际存在的文件 |
| `<license_file>` | 许可证文件名，通常为 `LICENSE`、`LICENSE.txt` 或 `LICENSE.md` | 查看源码根目录中实际存在的文件 |

> **注意**：`<doc_file>` 和 `<license_file>` 可同时列出多个文件，以空格分隔，例如：`%doc AUTHORS README.md`

### 步骤 3：确定架构相关性并修改 Provides

判断该包是否包含 C 扩展（即是否需要编译 C 代码）：

**情况 A：纯 Python 包（无 C 扩展）**

- 保留 `BuildArch: noarch`
- 保留 `Provides: python3-%{srcname} = %{version}-%{release}`
- 删除被注释的那行 `# Provides: python3-%{srcname}%{?_isa} = %{version}-%{release}`

**情况 B：含 C 扩展的包（架构相关）**

- 删除 `BuildArch: noarch` 这一行
- 保留 `Provides: python3-%{srcname} = %{version}-%{release}`
- 取消注释 `# Provides: python3-%{srcname}%{?_isa} = %{version}-%{release}`（去掉行首的 `# `）

### 步骤 4：提交并推送

```bash
git add SPECS/python-<pkgname>/
git commit -m "python-<pkgname>: init"
git push
```

---

## 二、触发 OBS 构建

### 步骤 1：创建 OBS 包

进入 `home:Sakura286:vLLM/` 目录，执行：

```bash
osc mkpac python-<pkgname>
```

### 步骤 2：配置 _service 文件

进入新创建的目录，从任意已有包中复制 `_service` 文件，然后将其中的 `extract` 参数修改为当前包名。`_service` 文件的完整格式如下：

```xml
<services>
  <service name="obs_scm">
    <param name="scm">git</param>
    <param name="url">ssh://git@git.openruyi.cn:54865/Sakura286/vllm-specs.git</param>
    <param name="revision">main</param>
    <param name="extract">SPECS/python-<pkgname>/*</param>
  </service>
  <service name="download_files"/>
</services>
```

### 步骤 3：提交触发构建

```bash
osc add *
osc ci -m "python-<pkgname>: init"
```

提交后 OBS 将自动拉取 SPEC 并开始构建。
