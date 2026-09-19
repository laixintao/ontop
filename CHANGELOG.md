# Changelog

## 1.1.0 — First public release

### English

- Native menu bar app with a single live, always-on-top window preview.
- Mouse clicks and scrolling pass through the picture; hover reveals explicit controls.
- Return to the source app, hide while it is active, and restore when switching away (macOS 15.2+).
- Opacity from 30–100%, dedicated movement and proportional resize handles, remembered layout, and a reset action.
- Crop capture padding using frame metadata, preserving legitimate black content and correct pixel orientation.
- English and Simplified Chinese UI, documentation, and native regression tests.
- Universal DMG and ZIP, verified packaging, CI on Apple Silicon and Intel, and automated releases with build provenance.
- `make release` handles version bumps, bilingual notes, commits, and atomic branch/tag pushes; CI publishes verified installers.

### 中文

- 原生菜单栏工具，单个窗口实时预览并置顶。
- 画面区域鼠标点击和滚动穿透，悬停时显示明确的操作按钮。
- 返回来源 App 时收起，切走后恢复（macOS 15.2+）。
- 30%–100% 不透明度、专用移动与等比例缩放手柄、布局记忆与重置。
- 根据采集帧元数据去除填充黑边，保留原本的黑色内容和正确的像素方向。
- 中英文界面、文档和原生回归测试。
- 通用 DMG / ZIP、安装包验证、双架构 CI，以及带来源证明的自动发布。
- `make release` 自动递增版本、生成双语说明、提交并原子推送分支和标签，由 CI 发布已验证的安装包。
