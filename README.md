# 墨阅 InkShelf

墨阅是一款面向 iPhone 与 iPad 的原生漫画、画集、PDF 和电子书阅读器。项目使用 SwiftUI、PDFKit、Vision、WebKit 与 UIKit 构建，最低支持 iOS 18；在最新 SDK 上会自动采用 Liquid Glass、浮动标签栏和新的系统动效。

## 阅读格式

- PDF：保留并打开原文件，使用 PDFKit 矢量/原始页面渲染，不重新压缩。
- 漫画与画集：CBZ、ZIP、JPG、PNG、HEIC、WebP、GIF、TIFF、BMP、AVIF 等常用图片格式。
- 电子书：EPUB、TXT、HTML/HTM、Markdown、RTF、FB2。
- 导入方式：文件、整个文件夹、照片图库、iCloud Drive 文件夹，以及私人服务器云书库。

暂不支持带 DRM 的电子书，也不绕过 DRM；CBR/RAR/7z、MOBI 与 AZW3 尚未加入。

## 主要功能

- 单页/双页、封面单独显示、横向/纵向翻页、从左到右/日漫顺序。
- PDF 与图片双指缩放，图片双击放大/还原；PDF 密码解锁和缩略图跳页。
- 电子书分页/滚动模式、目录、全文章节搜索、字体、字号、行距、页边距、纸张/护眼/夜间主题。
- 文件夹与漫画多图拼贴封面、画集总览、Quick Look 单图预览。
- 书架搜索、收藏、重命名、阅读进度、原文件导出与屏幕常亮。
- 动态字体、VoiceOver、减少动态效果适配和 iPad 指针悬停效果。

## AI 陪读

- 使用 Apple Vision 在本机识别页面文字、人脸和粗略画面标签。
- DeepSeek V4 Pro 根据这些摘要生成页面弹幕、陪读对话和片末模拟讨论。
- AI 生成的虚拟评论会明确标示为模拟内容，不冒充真实用户。
- DeepSeek 密钥只保存在 iOS Keychain；App 不把 PDF 或整页原图直接上传给 AI。
- AI 是可选功能，关闭后阅读器完全不发起 DeepSeek 请求。

## iCloud Drive 书库

“云书库”默认使用 iCloud。第一次在系统“文件”选择存放画集的 iCloud Drive 文件夹后，墨阅会保存系统授予的文件夹访问权限：

- 递归索引 PDF、CBZ、图片和电子书，只读取文件名、大小与更新时间，不预先复制整套书库。
- 首次打开一本书时由 iCloud 下载原文件并显示进度，整理完成后使用与本地书籍完全相同的阅读引擎。
- 已打开的书保留本地副本，之后可离线阅读；可以单独删除本地副本以释放空间。
- 断开文件夹或删除本地副本不会修改、移动或删除 iCloud Drive 中的原文件。
- 连接通过 iOS 文件选择器和 Apple ID 的系统权限完成，墨阅不接触账号或密码，也不需要自建 iCloud 数据库。

在 Windows 上，可先用 iCloud for Windows 把 `anmi`、`kantoku`、`rurudo`、`ももこ` 四个文件夹上传到同一个 iCloud Drive 文件夹；进入墨阅后只需选择它们的上级文件夹。

## 独立服务器书库

“云书库”的“服务器”模式连接 `https://4-3rail.top/` 的墨阅独立书库服务：

- 不需要账号或密码，进入页面即可查看、上传、下载、删除和同步阅读进度。
- 列表和小封面优先加载；原书首次打开时后台下载并显示进度。
- 下载完成后导入本地原生阅读引擎，之后打开与本地书籍一致，断网也可继续阅读。
- 服务器支持 HTTP Range、大文件流式传输和原文件字节级保存，不转码书籍。
- 它不读取文档中心的代码、账号、Cookie、数据库、环境变量或审计记录。

服务端扩展位于 `Server/`，线上安装在 `/home/admin/inkshelf-server`，以独立 systemd 服务运行在 `127.0.0.1:8001`，由 Nginx 仅代理 `/inkshelf-api/`。书籍存放在 `/home/admin/inkshelf-server/data/books`。

按当前需求，服务端故意不设置访问密码。因此，任何知道地址的人都可以查看、上传和删除书籍；它适合个人使用，但不应把 API 地址公开传播。

## “无损”的含义

导入、上传和缓存均复制源文件字节，不对 PDF、图片或电子书重新编码。书架封面是单独生成的轻量缓存，不会替换或修改源文件。漫画压缩包会为本地阅读展开独立页面，但原压缩包仍然保留。

## 云端生成 IPA（不需要本地 Mac）

1. 打开 GitHub 仓库的 **Actions** 页面。
2. 运行 **Build unsigned IPA**，或推送到 `main` 自动触发。
3. 构建完成后下载 `InkShelf-unsigned-ipa` artifact。
4. 使用个人证书或侧载工具为无签名 IPA 签名并安装。

工作流使用 GitHub macOS runner、XcodeGen 和可用的最新 Xcode SDK；同时运行单元测试、模拟器构建和真机 Release 构建。

## 本地 Mac 构建（可选）

```sh
brew install xcodegen
xcodegen generate
open InkShelf.xcodeproj
```

在 Xcode 的 Signing & Capabilities 中选择自己的 Team 后即可安装到设备。

## 本机数据位置

导入、iCloud 按需下载和服务器缓存内容保存在 App Documents 下的 `InkShelf Library`：

- PDF：`<book-id>/source.pdf`
- CBZ/ZIP：`<book-id>/source.cbz|zip` 与 `<book-id>/pages/`
- 图片画集：`<book-id>/pages/`
- 电子书：`<book-id>/source.*`、解析资源与 `ebook.json`
- 元数据：`library.json`

启用了文件共享，必要时可通过系统文件管理或设备备份取回内容。删除本地书架项目只会删除该项目的本地副本；iCloud 原文件保持不变。删除服务器项目则会单独确认，而且不会删除已经缓存的本地副本。
