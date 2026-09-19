# Contributing / 参与贡献

Thanks for helping make a small tool better. English and Chinese are both welcome.

## Before a change

- Check [existing issues](https://github.com/laixintao/ontop/issues) first.
- For a bug, include your macOS version, chip, OnTop version, source app, and a short reproduction. Remove private content from screenshots.
- For a larger feature, describe the use case in an issue or [discussion](https://github.com/laixintao/ontop/discussions) before building it.
- Report vulnerabilities through [private security reporting](https://github.com/laixintao/ontop/security/advisories/new), not a public issue.

## Pull requests

1. Fork the repository and create a focused branch.
2. Keep the app native, dependency-free, and respectful of the user's focus and permissions.
3. Update both language resources and both READMEs when changing visible behavior.
4. Add regression coverage for behavioral fixes. Run `./scripts/ci.sh` in a macOS graphical login session.
5. Describe the user-visible change, the reason, and how you verified it. Include before/after images for UI changes, using non-private sample content.

See the [development guide](docs/DEVELOPMENT.md) for architecture, tests, and manual checks. Contributions are provided under the repository's [MIT License](LICENSE).

## 中文

欢迎中英文反馈和贡献。提交问题前请先搜索现有 Issue；报告 Bug 时提供 macOS、芯片、OnTop 版本、来源 App 与复现步骤，截图请去除隐私内容。

较大的功能先讨论使用场景。PR 尽量聚焦一个改进，保持原生、精简，不额外干扰焦点或索取权限。涉及界面行为时同步更新中英文资源和文档，并补充必要的回归测试；提交前运行 `./scripts/ci.sh`。

更多信息见[中文开发指南](docs/DEVELOPMENT.zh-CN.md)。安全问题请通过[私密报告](https://github.com/laixintao/ontop/security/advisories/new)提交。
