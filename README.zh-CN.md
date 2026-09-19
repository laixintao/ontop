<div align="center">
  <img src="docs/assets/icon.png" width="96" height="96" alt="OnTop 应用图标">
  <h1>OnTop</h1>
  <p><strong>参考资料，始终在眼前。</strong></p>
  <p>轻巧的原生 macOS 工具，把窗口实时预览放在工作区上方。<br>边看边写，鼠标操作直接穿透到下方窗口。</p>
  <p>
    <a href="https://github.com/laixintao/ontop/actions/workflows/ci.yml"><img src="https://github.com/laixintao/ontop/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI"></a>
    <a href="https://github.com/laixintao/ontop/releases/latest"><img src="https://img.shields.io/github/v/release/laixintao/ontop?color=6366f1" alt="最新版本"></a>
    <a href="#兼容性"><img src="https://img.shields.io/badge/macOS-14%2B-303642" alt="macOS 14 及以上"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-303642" alt="MIT 许可"></a>
  </p>
  <p><a href="https://github.com/laixintao/ontop/releases/latest"><strong>下载 macOS 版本 →</strong></a> · <a href="README.md">English</a> · <a href="https://github.com/laixintao/ontop/discussions">交流讨论</a></p>
</div>

![OnTop 使用示意：参考清单悬浮在文稿上方，下方工作区仍可正常操作。](docs/assets/hero.svg)

<p align="center"><sub>使用公开示例内容绘制的场景示意；实际预览显示你选择的窗口。</sub></p>

## 资料置顶，工作照常

写代码时看 API 文档，记笔记时参考图表，工作时对照清单，不必反复切窗口或重新排列整个桌面。

- **始终可见。** 实时预览置顶，支持跨 Space 和原生全屏工作区。
- **一个来源，一个浮窗。** 可以同时添加多份参考资料，每个窗口独立移动、调透明度、操作和采集。
- **鼠标穿透。** 直接在画面区域点击、滚动或选择下方窗口的文字。
- **按需显示控件。** 鼠标移入后出现返回 App、停止、更换窗口和不透明度控件。
- **自然切回原窗口。** 返回来源 App 时自动收起，切到其他 App 后原位恢复。
- **适合你的布局。** 不透明度 30%–100%，专用移动与等比例缩放手柄，自动记住位置、大小和不透明度。
- **原生、本地运行。** Swift、AppKit、ScreenCaptureKit；无需账号，没有分析统计、网络请求或第三方运行依赖。

## 安装

1. [下载最新通用版 DMG](https://github.com/laixintao/ontop/releases/latest)。
2. 打开后把 **OnTop** 拖入 **Applications（应用程序）**。
3. 启动 OnTop，在 macOS 系统选择器中选择窗口并确认共享。

同一个安装包兼容 Apple Silicon 和 Intel，也提供 ZIP。

**首次打开：** 当前发布包使用临时签名，**尚未经过 Apple 公证**。如果 macOS 拦截从网络下载的 App，请先尝试打开，再到 **系统设置 → 隐私与安全性 → 仍要打开**。可参考 [Apple 的说明](https://support.apple.com/zh-cn/102445)，也可以[自行编译](#从源码构建)。

## 使用

OnTop 常驻菜单栏，图标是一枚**图钉**，不会显示在 Dock 中。

![OnTop 实际中文悬停控制条：移动、返回 App、停止、更换窗口、不透明度。](docs/assets/controls-zh-CN.png)

| 想做什么 | 如何操作 |
| --- | --- |
| 继续操作下方 App | 在画面区域点击、拖动、滚动，操作会穿透。 |
| 编辑来源文档 | 鼠标移入，点击 **返回 App**。 |
| 同时参考另一个窗口 | 从菜单栏选择 **添加窗口…**，再共享一个窗口。 |
| 移动或缩放预览 | 拖动控制条左侧手柄或浮窗右下角手柄。 |
| 调整不透明度 | 使用悬停滑块，或菜单栏中的预设值。 |
| 更换某个来源 | 点击它的重叠窗口图标，或对应子菜单中的 **选择其他窗口**。 |
| 找回合适的布局 | 在对应窗口的子菜单中选择 **重置浮窗大小和位置**。 |
| 结束使用 | **停止**只关闭当前浮窗；**全部停止**关闭所有浮窗；**退出 OnTop**退出应用。 |

浮窗是**实时画面预览**，不是原 App 的可交互副本。鼠标操作会交给当前位置实际位于下方的窗口，不会转发给被采集的文档。

## 兼容性

| 功能 | 要求 |
| --- | --- |
| 预览、穿透、悬停控件、不透明度、移动和缩放 | macOS 14+ |
| 返回来源 App、随来源 App 自动收起和恢复 | macOS 15.2+ |
| 预编译通用版 | Apple Silicon 或 Intel |
| 源码构建 | Swift 6 和 macOS 15.2+ SDK；Xcode 16.2+ 或兼容的 Command Line Tools |

<details>
<summary><strong>使用前了解这些细节</strong></summary>

- 通过系统选择器逐个添加来源，每个窗口独立预览，最高 15 fps。共享越多窗口，会使用更多 CPU / GPU 资源。
- 如果选择来源时它已在前台，切到其他 App 后它的预览才会出现。使用来源 App 时，会收起该 App 的全部预览，其他 App 的参考窗口保持可见；返回时具体抬起哪个窗口由来源 App 决定。
- 最小化、休眠、停止绘制或受保护的窗口可能暂停或无法采集；在可能的情况下保留最后一帧。
- 支持 Space 和原生全屏；独占全屏 App 或系统界面可能有自己的窗口层级规则。
- 停止预览立即停止采集；重新启动后需要通过系统选择器再次选择来源。

</details>

## 隐私

只共享你在 macOS 系统选择器中选中的窗口。不申请辅助功能或输入监控权限，不采集音频，不保存画面，不传输内容。仅在本地保存浮窗布局和不透明度。系统显示共享指示器是正常行为。

## 从源码构建

```bash
git clone https://github.com/laixintao/ontop.git
cd ontop
./scripts/build.sh
open build/Release/OnTop.app
```

| 命令 | 作用 |
| --- | --- |
| `./scripts/build.sh Debug` | 构建本机调试版 |
| `./scripts/test.sh` | 在中文、英文环境中运行原生 UI 和渲染测试 |
| `./scripts/package.sh` | 在 `dist/` 生成通用 App、DMG、ZIP 和 SHA-256 校验文件 |
| `./scripts/ci.sh` | 项目检查、测试、打包和安装包验证 |
| `make release` | 递增补丁版本、commit、tag、push，由 CI 构建并发布 |

维护者也可以通过 `make release VERSION=1.2.0` 指定版本。前置条件、定制发布说明和失败重试请见[发布指南](docs/RELEASING.zh-CN.md)。

自动测试覆盖真实窗口命中、原生按钮点击、1×/2×/3× 逐像素裁剪、不透明度、几何尺寸和反复切换来源。CI 在 Apple Silicon 与 Intel 上运行；版本标签通过同样的检查后自动发布安装包、校验值和 GitHub 构建来源证明。

[开发指南](docs/DEVELOPMENT.zh-CN.md) · [发布指南](docs/RELEASING.zh-CN.md) · [版本记录](CHANGELOG.md)

## 参与贡献

欢迎 Bug 报告、小改进、翻译和具体的功能建议，中英文均可。可以先看[贡献指南](CONTRIBUTING.md)、[提交 Issue](https://github.com/laixintao/ontop/issues/new/choose)，或[交流使用场景](https://github.com/laixintao/ontop/discussions)。

由 [@laixintao](https://github.com/laixintao) 开发，采用 [MIT 许可](LICENSE)。
