# 开发指南

[English](DEVELOPMENT.md) · [返回 OnTop](../README.zh-CN.md)

## 环境

- macOS 14+ 的 Mac。
- Swift 6 和 macOS 15.2+ SDK：Xcode 16.2+ 或兼容的 Apple Command Line Tools。
- Python 3.9+，用于项目元数据、文档检查和发布自动化。
- 原生窗口与渲染测试需要图形登录会话；不需要录屏、辅助功能或输入监控授权。

未安装命令行工具时运行 `xcode-select --install`。使用完整 Xcode 时先完成许可确认与组件安装。无需付费开发者账号或第三方运行依赖。

## 构建与运行

```bash
./scripts/build.sh Debug
open build/Debug/OnTop.app
```

默认构建本机架构的 `Release`。第二个参数可指定 `universal`、`arm64` 或 `x86_64`，输出到 `build/Release-<架构>/`。也可在 Xcode 中打开 `OnTop.xcodeproj`，运行 **OnTop → My Mac**。

替换开发版 App 前先退出正在运行的实例。重新启动需要重新选择来源；布局和不透明度会保留，共享授权不会跨启动恢复。

## 架构

| 文件 | 职责 |
| --- | --- |
| [`AppDelegate.swift`](../OnTop/AppDelegate.swift) | 菜单栏及各窗口操作、应用生命周期、来源 App 激活通知 |
| [`PinManager.swift`](../OnTop/PinManager.swift) | 共享选择器管理、采集流路由、独立采集与预览、去重和退出清理 |
| [`CaptureController.swift`](../OnTop/CaptureController.swift) | 单个采集流的串行生命周期、代际检查、帧率与分辨率调整 |
| [`PreviewPanelController.swift`](../OnTop/PreviewPanelController.swift) | 穿透画面、独立交互控件、悬停、几何尺寸、不透明度与设置 |
| [`FrameRenderer.swift`](../OnTop/FrameRenderer.swift) | 有效内容区域、有上限的 GPU 裁剪缓冲池、原生视频帧显示 |

画面窗口始终忽略鼠标事件。控件使用独立的不激活浮窗，出现时不会让整张画面拦截输入。仅在预览可见时以 20 Hz 读取鼠标位置，无需全局事件监听权限。

控制条在图片上方，缩放手柄在图片右侧。布局始终为它们预留屏幕空间，因此悬停不会移动或缩小图片。鼠标跨越间隙时保持控件可见，但间隙不会拦截点击。临时隐藏独立于来源 App 的激活状态：隐藏全部预览面板并停止鼠标轮询，采集继续。只有主动恢复或更换来源才会解除临时隐藏。

每个新来源都有独立的采集和预览。选择器回调带 stream 时只更新对应窗口，nil-stream 回调新增窗口。macOS 15.2+ 用窗口 ID 去重；各槽位独立保存布局和透明度，新槽位默认错开排列。重叠时只读取 AppKit 中本应用的窗口顺序来决定悬停控件归属。激活来源 App 只隐藏它自己的预览；单个采集流失败或停止不会关闭其他窗口的共享选择器。

采集最高 15 fps，队列深度为 3。常规画面不额外复制；有填充边缘的帧使用 Core Image 裁剪。裁剪依据元数据，不依据像素颜色。`contentRect` 以 surface point 为单位，乘以 `scaleFactor` 得到像素；`contentScale` 已被系统应用，不能再次缩小画面。

## 检查

```bash
make check
./scripts/test.sh
./scripts/ci.sh
```

完整 CI 会检查项目文件，编译 App，分别运行中英文原生测试，生成通用版，验证 ZIP / DMG 解包、签名、双架构、资源、许可文件和校验值。

原生测试覆盖 1×/2×/3× 逐像素裁剪、黑色文档、异常与空帧、裁剪内存上限、真实 WindowServer 命中、原生按钮事件、不抢焦点、悬停、透明度记忆、移动缩放、30 次显隐循环、实际视频图层尺寸、重置和退出清理。视觉检查产物在 `build/qa/`。

发布测试使用临时本地 Git 仓库和模拟 `gh`，覆盖版本递增、注释标签、原子推送、自定义说明、脏工作区、远程冲突、推送失败重试、草稿恢复与已发布附件保护。测试不会请求 GitHub，也不会修改真实仓库。

脚本和 workflow lint：

```bash
brew install shellcheck actionlint
shellcheck scripts/*.sh
actionlint
```

GitHub CI 在 Apple Silicon 和 Intel 上执行。编译警告（包括严格并发检查）视为错误；失败的任务也会上传已生成的视觉检查产物。

## 人工验收

自动测试使用合成帧，真实系统选择器和其他 App 仍需简短手动验证：

- 选择浏览器文档或 PDF，检查文字清晰度和滚动更新。
- 通过「添加窗口…」和 macOS 共享菜单添加第二个来源，检查画面、移动缩放、透明度、来源切换、取消、更换和单独停止；也验证同一 App 的两个窗口。
- 在预览下面点击、滚动、选择文字；悬停控件可操作且不抢键盘焦点。
- 将预览移到屏幕各个边缘并跨屏拖动，检查控件位于图片外侧，鼠标经过间隙时不会消失。
- 隐藏一个预览并切换 App，确认它保持隐藏、其他预览继续显示。通过对应菜单或「显示全部预览」恢复后，位置、尺寸和透明度应保持不变。
- 反复返回来源再切走，调整原窗口大小，确认没有黑边累积、尺寸漂移或重复浮窗。
- 调整不透明度、移动、缩放、重启，并通过菜单重置布局。
- 取消更换来源；在隐藏时、采集启动中停止；然后重新选择。
- 关闭、最小化来源，停止系统共享，切换 Space、原生全屏与 Retina / 非 Retina 屏幕。

## 文案与展示素材

界面文案同时更新英文和 `zh-Hans` 资源，用户可见行为同时更新两份 README。

首页场景是使用公开示例内容绘制的示意图，控制条来自实际 App 测试截图。运行 `python3 scripts/make-showcase.py` 可重建示意图；运行测试后可从 `build/qa/` 更新控制条图片。不要使用私人文档制作公开展示素材。

在仓库根目录运行 `xcrun swift scripts/MakeIcon.swift` 可重建图标。构建、安装包与测试产物不会进入 Git。
