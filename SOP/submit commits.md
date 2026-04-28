# 将包的 SPEC 从 vllm-specs 仓库迁移到 openRuyi 仓库

以迁移 `foo` 与 `bar` 包为例

## 步骤

### 1. 同步 openRuyi 仓库的 main 分支

进入 openRuyi 仓库，切换到 `main` 分支，拉取最新代码。

### 2. 准备工作分支 `new-xxx`

其中 xxx 根据你对此任务的理解随意填写

### 3. 切换到 `new-xxx` 分支

### 4. 复制 SPEC 文件

将 `/vllm-specs/SPECS/foo` 文件夹复制到 openRuyi 仓库的 `SPECS/` 目录下。

### 5. 暂存并提交

暂存所有变更，提交信息为 `SPECS: add foo`。

重复 4 与 5，直至每一个包都形成了一个提交

### 6. 推送代码

使用 `--set-upstream` 推送代码到远端

