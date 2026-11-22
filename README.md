# ByeSlides

ByeSlides 是一款为 macOS 开发的中文 Markdown 编辑器，只有「编辑」和「阅读」两种模式。编辑模式使用系统等宽字体，阅读模式使用随应用提供的霞鹜文楷。工具栏的 **Aa** 可以分别设置编辑和阅读的字号、行距。

应用固定使用浅色外观，文稿的强调色为蓝色（`#2458A6`）。

## 编辑

- 标题显示为半粗体，Markdown 符号和链接地址显示为灰色，粗体文字用强调色标出。
- 连续输入时隐藏蓝色双针，停笔约 0.4 秒后显示，点击正文或按方向键会立即显示。
- 在列表项末尾按回车会续写下一项，在空项上按回车则结束列表。Tab 和 Shift-Tab 调整列表缩进。
- 「格式」菜单提供粗体 ⌘B、斜体 ⌘I 和链接 ⌘K。
- 粘贴或拖入图片时，图片会拷贝到文稿旁边的 `assets` 文件夹，并插入引用。这要求文稿已经存储过。
- 底部显示字数：汉字逐字计数，英文按单词计数，Markdown 符号和链接地址不计入。选中文字时同时显示选区字数。

## 阅读

- 支持标题、列表、引用、代码块、图片、文末引用链接，以及表格、任务列表和删除线。
- 粗体和四到六级标题用强调色区分，不使用加粗。霞鹜文楷只有一种字重，加粗时字形会被涂粗。
- 中英文之间自动留出间隙，行末标点可以悬挂，段落两端对齐。
- 远程图片默认不载入，以免打开文稿时向图片所在的服务器发出请求。点击页面顶部的「载入」，可以为当前窗口载入远程图片。

## 通用

- 编辑和阅读的正文随窗口宽度调整，两侧各留 32 点。
- 「显示」菜单切换编辑模式 ⌘1 和阅读模式 ⌘2，切换前后停在同一段文字。
- 两种模式都支持 ⌘F 查找。编辑模式还提供查找与替换 ⌥⌘F。
- 「文件」菜单的「打印…」⌘P 和「导出为 PDF…」都使用阅读模式的排版，并始终以浅色外观输出。
- 在 Finder 中选中 Markdown 文件后按空格，会以阅读模式的排版预览。快速查看只能读取被预览的文件，所以不显示相对路径的图片。

## 本地构建

需要 macOS 26 或更高版本，以及提供 Swift 6.4 或兼容版本的 Xcode 或 Command Line Tools。进入仓库根目录运行以下命令。

```sh
./Scripts/build-app.sh
open dist/ByeSlides.app
```

构建脚本会生成 `dist/ByeSlides.app`，其中包含快速查看扩展。快速查看扩展只有在应用位于「应用程序」文件夹时才能读到阅读字体，所以安装时请把应用拷贝到 `/Applications`。

默认使用临时签名，生成的应用只能在本机运行。要分发给别人，需要设置以下环境变量：

| 变量 | 作用 |
|---|---|
| `SIGN_IDENTITY` | 签名身份，例如 `Developer ID Application: 名称 (团队 ID)`。设置后会启用公证所需的强化运行时和时间戳 |
| `NOTARY_PROFILE` | 用 `xcrun notarytool store-credentials` 保存的钥匙串配置名。设置后会提交公证，并把公证票据装订进应用 |

运行测试：

```sh
swift test
```

如果报错 `plugin for module 'TestingMacros' not found`，说明当前的 Command Line Tools 没有自动加载测试宏插件，可以手动指定插件路径：

```sh
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

GitHub Actions 会在每次推送到 `main` 和每个拉取请求上运行测试并构建应用，使用 `xcode-27` 运行环境。

## 代码结构

| 目录 | 内容 |
|---|---|
| `Sources/ByeSlidesCore/` | 应用与快速查看共用的部分：文本编码、排版设置项、阅读页面生成、`document-resource://` 资源加载，以及 `Resources/` 中的脚本、样式表和字体 |
| `Sources/ByeSlides/App/` | 应用入口、文档窗口、工具栏、菜单命令、旧版设置迁移 |
| `Sources/ByeSlides/Document/` | Markdown 文档的读写 |
| `Sources/ByeSlides/Editor/` | 源码编辑器：语法着色、列表编辑、格式命令、图片导入、字数统计 |
| `Sources/ByeSlides/Reading/` | 阅读视图、页内查找、打印与导出、链接打开规则 |
| `Sources/ByeSlides/Settings/` | 排版设置弹窗 |
| `Sources/ByeSlides/Support/` | 编辑与阅读之间的位置换算 |
| `Sources/ByeSlidesQuickLook/` | 快速查看扩展 |
| `Packaging/` | 应用和扩展的 Info.plist、扩展的权限声明、图标、本地化 |

常见的扩展方式：

- 新增 Markdown 语法：在 `reading.js` 里写一个 markdown-it 插件，用 `.use()` 注册。如果编辑模式也需要着色，在 `MarkdownHighlighter` 里加上对应规则。
- 调整渲染后的页面：在 `reading.js` 的 `postProcessors` 里加一个处理函数。
- 修改阅读样式：编辑 `reading.css`。由应用控制的样式变量定义在 `ReadingStyle.swift`，强调色定义在 `Palette`。
- 新增排版设置：在 `TypographySetting` 里声明设置项，再加到 `TypographyPanel` 中。
- 新增显示模式：在 `DisplayMode` 里加一个 case，然后在 `DocumentView` 里写对应的视图。

## 第三方资源

Markdown 解析和 HTML 清理使用 markdown-it 与 DOMPurify，许可见 [脚本许可](Sources/ByeSlidesCore/Resources/LICENSE.md)。霞鹜文楷字体随附 [SIL Open Font License](Sources/ByeSlidesCore/Resources/LXGWWenKai-OFL.txt)。
