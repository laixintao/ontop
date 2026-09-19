# Security / 安全

The latest published release receives fixes. OnTop handles window content locally; it does not save frames, capture audio, send analytics, or make network requests. A new session uses the macOS system picker to authorize its source.

## Reporting a vulnerability

Please [report privately through GitHub](https://github.com/laixintao/ontop/security/advisories/new). Include affected versions, reproduction steps, and impact. Use sample content rather than personal documents or credentials. Please do not post sensitive details in a public issue.

## Release verification

Release downloads include SHA-256 checksums and GitHub build provenance. See [Verifying a download](docs/RELEASING.md#verifying-a-download). Provenance identifies the producing workflow; it does **not** replace Apple Developer ID signing or notarization. Current installers are ad-hoc signed and not notarized.

## 中文

仅最新发布版本接收修复。窗口画面在本地处理，不保存图像、不采集音频、不发送统计或网络请求；新的共享会话由 macOS 系统选择器授权。

发现安全问题时，请通过 [GitHub 私密报告](https://github.com/laixintao/ontop/security/advisories/new)提供影响版本、复现方法与影响范围。请使用示例内容，不要在公开 Issue 中贴出私人文档、凭据或漏洞细节。

发布包包含校验值和 GitHub 构建来源证明；来源证明不等同于 Apple 签名或公证。详见[中文发布指南](docs/RELEASING.zh-CN.md)。
