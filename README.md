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

## 第三方资源

Markdown 解析和 HTML 清理使用 markdown-it 与 DOMPurify，许可见 [脚本许可](Sources/ByeSlides/Resources/LICENSE.md)。霞鹜文楷字体随附 [SIL Open Font License](Sources/ByeSlides/Resources/LXGWWenKai-OFL.txt)。
