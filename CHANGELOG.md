# Changelog

## 1.3.1 — Easier dragging

- Enlarge the move grip's hit area from 22 × 26 to 44 × 44 points, with a larger icon and a subtle background. The toolbar keeps its compact height and stays outside the picture.
- Verify that dragging from the grip's outer padding moves the preview without triggering adjacent buttons.
- 将拖动手柄的操作区域从 22 × 26 扩大到 44 × 44 点，放大图标并增加浅色底；控制条保持原有高度，仍在图片外侧。
- 验证从手柄边缘留白处也能开始拖动，且不会触发相邻按钮。

## 1.3.0 — Unobstructed controls and temporary hiding

### English

- Hover controls float above the picture, and the resize handle sits outside its bottom-right edge. The reference remains fully visible and click-through.
- Reserve space for controls at screen edges without moving or resizing the picture on hover. Pointer travel across the small gap keeps controls visible.
- Hide an individual preview without ending sharing. Restore it with Show Preview or Show All Previews in the menu bar.
- Manual hiding survives app switches and incoming frames, preserves layout/opacity, and stops hover polling until restored.
- Add native regression coverage for external button placement, edge cases, click-through, hover gaps, and per-window hide/restore.

### 中文

- 悬停控制条浮在图片上方，缩放手柄位于右下边缘外侧，画面完整可见且保持鼠标穿透。
- 屏幕边缘为控件预留空间，悬停时不移动或缩放图片；鼠标经过间隙时控件保持显示。
- 单独隐藏预览而不结束共享，可从菜单栏「显示预览」或「显示全部预览」恢复。
- 临时隐藏不会因切换 App 或新画面而取消，保留布局和透明度，并在隐藏期间停止鼠标轮询。
- 补充外置按钮、屏幕边缘、穿透、悬停间隙与独立隐藏/恢复的原生回归测试。

## 1.2.0 — Independent reference windows

### English

- Share multiple windows at once: each source has its own preview, stream, position, size, opacity, and controls.
- Add a reference from the menu bar or macOS sharing menu without replacing an existing one. The preview's chooser replaces only that source.
- Per-window menus, individual Stop actions, and Stop All. New windows start in separate positions and remember settings by preview slot.
- Only previews belonging to the active source app hide; other references remain visible.
- Route overlapping hover controls to the topmost preview. Reject late callbacks for closed windows and deduplicate repeated selections on macOS 15.2+.
- Native multi-window regression tests cover independent rendering, picker routing, state/settings isolation, source switching, and cleanup.

### 中文

- 同时共享多个窗口，每个来源都有独立的预览、采集流、位置、尺寸、不透明度和控件。
- 从菜单栏或 macOS 共享菜单添加参考窗口，不会替换已存在的预览；浮窗上的选择按钮只更换自身来源。
- 各窗口独立菜单、停止操作，以及「全部停止」；新窗口错开排列，按槽位分别记住设置。
- 激活来源 App 时，只隐藏该 App 的预览，其他参考窗口继续显示。
- 重叠时只显示最上方预览的控件；拒绝已关闭窗口的迟到回调，并在 macOS 15.2+ 对重复来源去重。
- 原生多窗口回归测试覆盖独立渲染、选择器路由、状态与设置隔离、来源切换和清理。

## 1.1.1 — 2026-09-19

[Release notes / 发布说明](docs/releases/v1.1.1.md)

- Prepare public release with bilingual docs and automated delivery (`7fea13c`)
- project init (`af25306`)

## 1.1.0 — Initial implementation

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
