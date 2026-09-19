# 发布指南

[English](RELEASING.md) · [返回 OnTop](../README.zh-CN.md)

## 一条命令发布

在 `main` 提交好代码后，运行：

```bash
make release                   # 1.2.0 → 1.2.1
make release VERSION=1.3.0      # 或指定一个更高的版本
```

任选一条执行。命令会递增 App 版本和构建号，添加 Changelog，根据当前版本标签之后的提交生成中英文发布说明，自动 commit、创建注释 tag，并**原子推送 main 和 tag**。随后由 GitHub Actions 测试、构建、上传 DMG / ZIP / 校验文件、生成来源证明，再正式发布。无需本地打包或手动上传附件。

要求 Python 3.9+、Git、Make、干净的 `main` 工作区，以及 `origin` 推送权限。脚本会先拉取远程状态，拒绝远程领先或分叉、重复标签、未递增的版本。本地已提交但尚未推送的内容会一起发布。不使用强制推送。

如需精心编写发布说明，提前提交 `docs/releases/v<下个版本>.md` 和对应的 `CHANGELOG.md` 条目，脚本会保留这些内容。否则自动说明会包含原始提交标题和中英文安装指引。修改 App 行为时，请同步使用文档并完成[人工验收](DEVELOPMENT.zh-CN.md#人工验收)。

命令在推送成功后结束，Release 会在 **CI 通过后**出现，可打开命令输出的 workflow 链接查看。若推送失败，本地 commit 和 tag 会保留，同时打印可直接重试的 `git push --atomic …` 命令。不要为了重试推送再递增一次版本。

若版本已手动准备并提交（例如首次发布），先推送 `main`，再运行 `./scripts/tag-release.sh`。这个底层命令只打 tag 和推送，不修改版本或自动提交。

## CD 流程

[Release workflow](../.github/workflows/release.yml) 首先核对标签、App 版本、Changelog 与发布说明，然后调用 PR 使用的同一份 [CI workflow](../.github/workflows/ci.yml)：

1. 脚本与 workflow lint，文档链接、翻译与元数据检查，并使用临时 Git 仓库和模拟 GitHub CLI 实测发布脚本。
2. 在 Apple Silicon 与 Intel 上分别运行中英文原生测试。
3. 生成通用安装包，验证签名、架构、许可与资源、校验值和 ZIP / DMG 解包结果。
4. 下载 Apple Silicon 任务已验证的通用产物，再次校验传输完整性。
5. 为 DMG 和 ZIP 创建 GitHub 构建来源证明。
6. 上传资产到草稿，完成后连同中英文说明正式发布。

发布任务单独获取写入与 OIDC 权限；PR 测试保持只读，无需发布凭据。Actions 固定到提交 SHA，由 Dependabot 分组更新。

上传中断时可以重跑失败任务，脚本会继续完成已有草稿；**不会覆盖已发布版本**。发布后修复应使用新版本，不要移动已发布标签。

## 本地打包

```bash
./scripts/package.sh
./scripts/test-package.sh
```

`dist/` 包含 `OnTop.app`、通用 DMG / ZIP 与 `SHA256SUMS`。编译或打包失败时保留上次成功产物。安装包作为 Release 附件，不提交进源码仓库。

## 校验下载

从同一 Release 下载安装包和 `SHA256SUMS`。只下载了 DMG 时：

```bash
shasum -a 256 OnTop-1.2.0-universal.dmg
# 与 SHA256SUMS 中对应条目的摘要比对。
```

如果同时下载了 DMG 和 ZIP，在同一目录运行 `shasum -a 256 -c SHA256SUMS`。

安装 GitHub CLI 后，还可以验证构建来源：

```bash
gh attestation verify OnTop-1.2.0-universal.dmg --repo laixintao/ontop
```

## 签名状态

当前使用 **ad-hoc 临时签名**，**尚未经过 Apple 公证**。GitHub 来源证明用于验证产物来自哪个工作流，不等同于 Developer ID 签名，也不会消除 Gatekeeper 的首次打开提示。安装文档对此有明确说明。

未来如需 Apple 公证发布，需提供开发者账号、Developer ID 证书和公证凭据。当前流水线不包含、猜测或依赖这些凭据。不要为了安装 OnTop 关闭 Gatekeeper。
