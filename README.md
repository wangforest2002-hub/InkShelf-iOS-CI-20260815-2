# 墨阅 InkShelf

墨阅是一款面向 iPhone 与 iPad 的原生漫画、画集和 PDF 阅读器。项目使用 SwiftUI、PDFKit 与 UIKit 构建，最低支持 iOS 18；工程按 Xcode 27 整理，使用 iOS 26/27 SDK 构建时自动采用 Liquid Glass、浮动标签栏和最新系统控件。

## 已实现

- PDF 原文件导入与 PDFKit 矢量/原始页面渲染，不重新压缩 PDF
- CBZ、ZIP 图片漫画导入；保留原压缩包，并生成独立阅读页
- 多选 JPG、PNG、HEIC、WebP、GIF、TIFF、BMP、AVIF 组成画集
- 使用系统 PhotosPicker 从照片图库批量导入，并优先保留当前原始编码
- 直接选择整个文件夹创建独立画集，递归收集子文件夹图片并保持自然排序
- 文件夹/漫画多图拼贴封面、完整图片总览与系统 Quick Look 单张预览
- 单页/双页、封面单独显示、横向/纵向翻页、从左到右/日漫顺序
- PDF 与图片双指缩放；图片双击放大/还原
- 书架、封面缓存、搜索、收藏、重命名、原文件导出与阅读进度
- PDF 密码解锁、缩略图跳页、屏幕常亮与多种阅读背景
- 本机离线存储，无账号、无网络请求、无分析 SDK
- 动态字体、VoiceOver 标签、减少动态效果适配、iPad 指针悬停效果

“无损”指源文件按字节复制保存，应用不会对 PDF 或导入图片进行转码。书架封面是单独生成的轻量缓存，不会替换或修改源文件。

## 云端生成 IPA（不需要本地 Mac）

1. 将本目录提交到 GitHub 仓库。
2. 打开仓库的 **Actions** 页面。
3. 运行 **Build unsigned IPA**。
4. 构建完成后下载 `InkShelf-unsigned-ipa` artifact。
5. 使用你选择的证书或侧载工具对 IPA 签名安装。

工作流使用 GitHub 的 macOS 26 runner、XcodeGen 和 runner 中可用的最新 Xcode SDK。生成的 IPA 故意不签名，便于后续使用个人证书处理。

## 在 Mac 上构建（可选）

```sh
brew install xcodegen
xcodegen generate
open InkShelf.xcodeproj
```

在 Xcode 的 Signing & Capabilities 中选择自己的 Team 后即可运行到设备。

## 数据位置

导入内容保存在应用 Documents 下的 `InkShelf Library`：

- PDF：`<book-id>/source.pdf`
- CBZ/ZIP：`<book-id>/source.cbz|zip` 与 `<book-id>/pages/`
- 图片画集：`<book-id>/pages/`
- 元数据：`library.json`

启用了文件共享，必要时可通过系统文件管理或设备备份取回内容。删除书架项目会同时删除该项目在应用内保存的副本。

## 当前边界

- 支持 ZIP 系列漫画包（CBZ/ZIP），暂不支持需要额外解码器的 CBR/RAR/7z。
- 超大扫描图会按原图解码，极端尺寸可能受 iPhone 可用内存限制；PDF 由 PDFKit 分块渲染，更适合超大文档。
- 当前为纯本地版本，不包含 iCloud、WebDAV 或局域网传书；这些可以在后续版本中加入。
