# ByeSlides

ByeSlides 是一款为 macOS 开发的中文 Markdown 编辑器。编辑模式使用系统等宽字体，阅读模式使用随应用提供的霞鹜文楷。工具栏的 **Aa** 可以分别设置编辑字号、阅读字号和阅读行距。

## 阅读功能

支持标题、列表、引用、代码块、图片、文末引用链接，以及表格、任务列表和删除线。宽表格和长代码可以独立横向滚动。界面适配浅色和深色外观。

## 本地构建

需要 macOS 26 或更高版本，以及提供 Swift 6.4 或兼容版本的 Xcode 或 Command Line Tools。进入仓库根目录运行以下命令。

```sh
./Scripts/build-app.sh
open dist/ByeSlides.app
```

构建脚本会打包文档类型声明、中文本地化、图标、阅读引擎和字体，并为本机运行进行临时签名。将生成的应用拷贝到「应用程序」即可安装。

运行测试：

```sh
swift test
```

如果报错 `plugin for module 'TestingMacros' not found`，说明当前的 Command Line Tools 没有自动加载测试宏插件，可以手动指定插件路径：

```sh
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

## 代码结构

源码位于 `Sources/ByeSlides/`，测试位于 `Tests/ByeSlidesTests/`。

| 目录 | 内容 |
|---|---|
| `App/` | 应用入口、文档窗口和工具栏、显示模式 |
| `Document/` | Markdown 文档的读写，保存时保留原编码和 BOM |
| `Editor/` | 基于 `NSTextView` 的源码编辑器和底部状态栏 |
| `Reading/` | 阅读模式：网页生成、`document-resource://` 资源加载、链接打开规则 |
| `Settings/` | 排版设置项及其弹窗 |
| `Resources/` | `reading.js` 渲染脚本、`reading.css` 样式表、第三方脚本和字体 |

常见的扩展方式：

- 新增 Markdown 语法：在 `reading.js` 里写一个 markdown-it 插件，用 `.use()` 注册。
- 调整渲染后的页面：在 `reading.js` 的 `postProcessors` 里加一个处理函数。
- 修改阅读样式：编辑 `reading.css`。由应用控制的样式变量定义在 `ReadingStyle.swift`。
- 新增排版设置：在 `TypographySetting` 里声明设置项，再加到 `TypographyPanel` 中。
- 新增显示模式：在 `DisplayMode` 里加一个 case，然后在 `DocumentView` 里写对应的视图。

## 第三方资源

Markdown 解析和 HTML 清理使用 markdown-it 与 DOMPurify，许可见 [脚本许可](Sources/ByeSlides/Resources/LICENSE.md)。霞鹜文楷字体随附 [SIL Open Font License](Sources/ByeSlides/Resources/LXGWWenKai-OFL.txt)。
