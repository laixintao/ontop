# OnTop

把一个窗口的实时画面放进原生置顶浮窗，边工作边参考文档。

支持 **macOS 14+**。Swift + AppKit + ScreenCaptureKit，无第三方依赖。

## 使用

1. 打开 OnTop，在系统选择器中选择要参考的窗口，并确认共享。
2. 预览浮窗保持置顶，**画面区域的点击、拖动和滚动穿透到下方窗口**。可以把参考文档放在编辑器上方，继续操作下面的编辑器。
3. 鼠标移入时显示控制条：**返回 App**、**停止**、更换窗口，以及不透明度滑块。移出后自动隐藏；控制条显隐不会改变画面大小。
4. **只有「返回 App」按钮会主动切回来源 App**。来源 App 在前台时预览收起，切到其他 App 后原位恢复；直接通过 Dock 或 ⌘Tab 切换也一样。
5. 用控制条左侧的拖动手柄移动浮窗，用右下角的手柄等比例缩放。位置、大小和不透明度自动记住；采集画面中的空白填充会被去除，避免缩放和切换后越看越小。
6. 不透明度支持 **30%–100%**，控制条始终保持清晰。也可在菜单栏图钉 → **不透明度**选择预设值；**重置浮窗大小和位置**可恢复易用的默认布局。
7. 点 **停止**或菜单栏的 **停止置顶**，立即关闭预览并停止采集。菜单栏 → **退出 OnTop** 完全退出。

浮窗是实时预览，不会把操作转发到被采集的窗口；操作的是鼠标所在位置实际位于下方的窗口。要编辑来源文档，先点「返回 App」。临时收起不会停止采集，也不需要重新选择窗口；如果选择来源时它已经是前台 App，切到其他 App 后才会显示预览。同一 App 有多个窗口时，具体显示哪个窗口由来源 App 决定，使用该 App 期间预览都会收起。原窗口被遮挡时仍可更新；最小化、休眠或来源 App 停止绘制后可能停在最后一帧。只有系统明确报告暂停时才显示暂停标记，静态文档不会被误报。来源关闭或共享被系统停止后，可从悬停控制条重新选择窗口。

OnTop 不出现在 Dock 中；取消首次选择后，可通过菜单栏图钉重新选择。界面支持英文和简体中文，跟随系统语言。

## 构建

使用 Apple Command Line Tools（Swift 6 / macOS 15.2 或更新的 SDK；构建出的 App 仍支持 macOS 14+）。没有安装时先运行 `xcode-select --install`：

```bash
./scripts/build.sh
open build/Release/OnTop.app
```

Debug 构建：`./scripts/build.sh Debug`。脚本为本机架构编译并做本机临时签名，不要求 Apple Developer 账号。可将生成的 `OnTop.app` 拖入「应用程序」。

可选架构：`./scripts/build.sh Release universal`（Apple Silicon + Intel），或使用 `arm64` / `x86_64`。指定架构的构建输出到 `build/Release-<架构>/`，不会覆盖本机开发版本。

也可使用 Xcode 16.2 或更新版本打开 `OnTop.xcodeproj`，选择 **OnTop → My Mac** 并运行。首次使用 Xcode 需先完成它的许可确认和组件安装；不需要修改全局 `xcode-select` 设置。

## 一键打包

```bash
./scripts/package.sh
```

从源码重新构建通用版，输出到 `dist/`（版本号读取 `OnTop/Info.plist`）：

```text
dist/
  OnTop.app
  OnTop-1.1.0-universal.dmg
  OnTop-1.1.0-universal.zip
  SHA256SUMS
```

打开 DMG，将 **OnTop** 拖到 **Applications** 即可安装；ZIP 解压后得到同一 App。校验下载文件：`cd dist && shasum -a 256 -c SHA256SUMS`。重复打包会更新上述产物；构建失败不会覆盖上次成功的安装包。`build/` 和 `dist/` 不进入 Git。

当前产物使用 ad-hoc 临时签名，没有 Developer ID 签名或 Apple 公证。从网络下载后，首次打开可能需要在「系统设置 → 隐私与安全性」中确认。[Apple 的打开说明](https://support.apple.com/zh-cn/102445)

## 授权与限制

- 通过 macOS 系统窗口选择器授权所选窗口；不预先枚举所有窗口，也不主动申请整屏录制权限。系统显示的共享指示器属于正常行为。[Apple 的说明](https://developer.apple.com/videos/play/wwdc2023/10053/)
- 每次只保留一个预览，最高 15fps，按浮窗大小及屏幕缩放比例调整分辨率。
- 点击返回来源 App、随来源 App 自动收起和恢复使用系统提供的窗口归属信息，需要 macOS 15.2+；macOS 14 至 15.1 仍支持预览、移动和缩放。不额外申请辅助功能或自动化权限。
- 不采集音频，不保存画面，不发送网络请求，不跨重启恢复共享来源。
- 浮窗配置为跨桌面、支持原生全屏辅助窗口。独占全屏及系统界面可能有自己的窗口层级限制。
- 受系统保护的内容可能无法预览。

## 验证

```bash
./scripts/test.sh
```

分别在中文、英文 App bundle 中检查构建、签名、资源、真实 AppKit 浮窗和 WindowServer 鼠标命中、原生按钮点击、移动和等比例缩放、透明度及设置恢复、连续 30 次来源 App 显隐，以及停止后的清理。渲染测试使用带黑边和四角颜色标记的合成帧，逐像素验证 1x / 2x / 3x 裁剪、坐标方向、画面恢复和资源上限；也验证原本为黑色的文档不会被误裁。测试有超时保护，不需要录屏或辅助功能授权。AppKit 测试需要 macOS 图形登录会话。

完整本地 CI（检查、测试、通用版打包和安装包验证）：

```bash
./scripts/ci.sh
```

仅验证已有安装包：`./scripts/test-package.sh`。它会验证校验值、两种 CPU 架构、签名、资源、ZIP 解压及 DMG 只读挂载后的内容，以及 Applications 安装快捷方式。

涉及系统选择器的交互需人工验收：

- 选择浏览器文档或 PDF，确认静态文字清晰，滚动原窗口后预览更新。
- 切换其他 App、Space、原生全屏 App，确认预览可见且不抢输入焦点。
- 重选窗口后仍只有一个浮窗；取消重选保持原预览。
- 在画面区域点击、滚动、拖动，确认下方 App 正常接收操作，OnTop 不抢焦点；只有「返回 App」按钮主动切换来源。
- 调整不透明度，确认仅画面变透明，控制条清晰可用；重新启动后保留设置。
- 使用专用手柄移动和缩放，画面保持比例；修改原窗口大小、反复返回来源后没有累积黑边或尺寸漂移。
- 来源 App 在前台时预览收起，切换到其他 App 后原位恢复；反复切换不会停止采集或重置大小。预览收起时点「停止置顶」，之后切换 App 不会再次出现。
- 鼠标移入、移出后，控制条正常显示、隐藏；操作滑块、拖动手柄期间不闪退，显示时画面区域仍能穿透。
- 关闭来源、停止系统共享、最小化及恢复来源时，检查画面和状态。
- 在正在打开预览或调整尺寸时关闭浮窗，再重新选择，确认没有残留采集。
- 更换 Retina / 非 Retina 屏幕并缩放浮窗，检查画面比例和分辨率。

## GitHub Actions

[CI workflow](.github/workflows/ci.yml) 在 push、pull request 及手动运行时执行：

- ShellCheck / actionlint 检查脚本和 workflow。
- 在 `macos-15`（Apple Silicon）和 `macos-15-intel` 上运行同一个 `scripts/ci.sh`。
- 保存通用版 DMG、ZIP 和校验文件到 Actions Artifacts，保留 14 天；测试截图保留 7 天。

推送 `v1.1.0` 这样的版本标签时，CI 会核对标签与 `CFBundleShortVersionString` 一致；两种架构的测试与 lint 全部通过后，创建附带安装包的 **Release 草稿**。在 GitHub 上补充变更说明、检查后发布。普通 PR 只有读权限，不需要配置 secrets；Release 使用 GitHub 提供的 `GITHUB_TOKEN`。Dependabot 每月检查 Actions 更新。

本地可额外运行 workflow lint：

```bash
brew install shellcheck actionlint
shellcheck scripts/*.sh
actionlint
```

图标由 AppKit 绘制；需要重新生成时，在仓库根目录运行 `xcrun swift scripts/MakeIcon.swift`。
