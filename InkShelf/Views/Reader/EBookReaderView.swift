import SwiftUI
import WebKit

struct EBookReaderView: UIViewRepresentable {
    let packageURL: URL
    let package: EBookPackage
    @Binding var chapterIndex: Int
    @Binding var chapterProgress: Double
    let flow: EBookFlow
    let theme: EBookTheme
    let font: EBookFont
    let fontSize: Double
    let lineHeight: Double
    let margin: Double
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.navigationDelegate = context.coordinator
        webView.scrollView.delegate = context.coordinator
        webView.scrollView.decelerationRate = .fast
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.allowsBackForwardNavigationGestures = false

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        webView.addGestureRecognizer(tap)

        context.coordinator.loadChapter(in: webView, force: true)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.loadChapter(in: webView, force: false)
        context.coordinator.applyStyleIfNeeded(in: webView)
        context.coordinator.applyExternalProgressIfNeeded(in: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        webView.scrollView.delegate = nil
        webView.stopLoading()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: EBookReaderView
        private var loadedChapter = -1
        private var styleKey = ""
        private var isLoading = false
        private var needsRestore = false
        private var lastReportedProgress = -1.0

        init(parent: EBookReaderView) { self.parent = parent }

        func loadChapter(in webView: WKWebView, force: Bool) {
            let index = min(max(0, parent.chapterIndex), max(0, parent.package.chapters.count - 1))
            guard force || loadedChapter != index else { return }
            guard let chapterURL = parent.package.chapterURL(at: index, packageURL: parent.packageURL) else { return }
            loadedChapter = index
            styleKey = ""
            isLoading = true
            needsRestore = true
            lastReportedProgress = -1
            webView.loadFileURL(chapterURL, allowingReadAccessTo: parent.package.resourceRootURL(packageURL: parent.packageURL))
        }

        func applyStyleIfNeeded(in webView: WKWebView) {
            guard !isLoading else { return }
            let key = "\(parent.flow.rawValue)-\(parent.theme.rawValue)-\(parent.font.rawValue)-\(parent.fontSize)-\(parent.lineHeight)-\(parent.margin)"
            guard key != styleKey else { return }
            styleKey = key
            applyStyle(in: webView, restore: false)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
            applyStyle(in: webView, restore: needsRestore)
            needsRestore = false
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url
            else {
                decisionHandler(.allow)
                return
            }
            if url.isFileURL,
               let index = parent.package.chapters.firstIndex(where: {
                   parent.package.chapterURL(at: parent.package.chapters.firstIndex(of: $0) ?? -1, packageURL: parent.packageURL)?.standardizedFileURL.path == url.standardizedFileURL.path
               }) {
                parent.chapterIndex = index
                parent.chapterProgress = 0
            }
            decisionHandler(url.isFileURL ? .allow : .cancel)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !isLoading else { return }
            let maximum: CGFloat
            let current: CGFloat
            if parent.flow == .paged {
                maximum = max(0, scrollView.contentSize.width - scrollView.bounds.width)
                current = scrollView.contentOffset.x
            } else {
                maximum = max(0, scrollView.contentSize.height - scrollView.bounds.height)
                current = scrollView.contentOffset.y
            }
            let progress = maximum > 1 ? min(max(Double(current / maximum), 0), 1) : 0
            guard abs(progress - lastReportedProgress) >= 0.003 else { return }
            lastReportedProgress = progress
            DispatchQueue.main.async { [weak self] in
                guard let self, self.parent.chapterProgress != progress else { return }
                self.parent.chapterProgress = progress
            }
        }

        func applyExternalProgressIfNeeded(in webView: WKWebView) {
            guard !isLoading,
                  !webView.scrollView.isDragging,
                  !webView.scrollView.isDecelerating
            else { return }
            let requested = min(max(parent.chapterProgress, 0), 1)
            guard abs(requested - lastReportedProgress) >= 0.012 else { return }

            let scrollView = webView.scrollView
            let maximum: CGFloat
            let target: CGPoint
            if parent.flow == .paged {
                maximum = max(0, scrollView.contentSize.width - scrollView.bounds.width)
                target = CGPoint(x: maximum * requested, y: 0)
            } else {
                maximum = max(0, scrollView.contentSize.height - scrollView.bounds.height)
                target = CGPoint(x: 0, y: maximum * requested)
            }
            guard maximum > 1 else { return }
            lastReportedProgress = requested
            scrollView.setContentOffset(target, animated: false)
        }

        func scrollViewWillEndDragging(
            _ scrollView: UIScrollView,
            withVelocity velocity: CGPoint,
            targetContentOffset: UnsafeMutablePointer<CGPoint>
        ) {
            let axisVelocity = parent.flow == .paged ? velocity.x : velocity.y
            let offset = parent.flow == .paged ? scrollView.contentOffset.x : scrollView.contentOffset.y
            let content = parent.flow == .paged ? scrollView.contentSize.width : scrollView.contentSize.height
            let viewport = parent.flow == .paged ? scrollView.bounds.width : scrollView.bounds.height
            let maximum = max(0, content - viewport)

            if axisVelocity > 0.55, offset >= maximum - 3, parent.chapterIndex < parent.package.chapters.count - 1 {
                DispatchQueue.main.async { [weak self] in
                    self?.parent.chapterIndex += 1
                    self?.parent.chapterProgress = 0
                }
            } else if axisVelocity < -0.55, offset <= 3, parent.chapterIndex > 0 {
                DispatchQueue.main.async { [weak self] in
                    self?.parent.chapterIndex -= 1
                    self?.parent.chapterProgress = 1
                }
            }
        }

        @objc func handleTap() { parent.onTap() }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { true }

        private func applyStyle(in webView: WKWebView, restore: Bool) {
            webView.backgroundColor = UIColor(parent.theme.color)
            webView.scrollView.backgroundColor = UIColor(parent.theme.color)
            webView.scrollView.isPagingEnabled = parent.flow == .paged
            webView.scrollView.alwaysBounceHorizontal = parent.flow == .paged
            webView.scrollView.alwaysBounceVertical = parent.flow == .scroll

            let flow = parent.flow == .paged ? "paged" : "scroll"
            let css = """
            :root { color-scheme: \(parent.theme == .night ? "dark" : "light"); }
            html { background: \(parent.theme.backgroundHex) !important; }
            body {
              background: \(parent.theme.backgroundHex) !important;
              color: \(parent.theme.foregroundHex) !important;
              font-family: \(parent.font.cssFamily) !important;
              font-size: \(Int(parent.fontSize))px !important;
              line-height: \(parent.lineHeight) !important;
              overflow-wrap: break-word;
              -webkit-text-size-adjust: 100%;
              box-sizing: border-box;
            }
            p { margin: 0 0 0.95em 0; }
            h1,h2,h3,h4 { line-height: 1.28; break-after: avoid; }
            img,svg,video { max-width: 100% !important; height: auto !important; object-fit: contain; break-inside: avoid; }
            blockquote { margin-left: 0; padding-left: 1em; border-left: 3px solid #8CA8E8; opacity: .9; }
            a { color: #6B83D6; }
            pre,code { white-space: pre-wrap; font-family: ui-monospace, monospace; }
            """
            let escapedCSS = css
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
            let restoreValue = min(max(parent.chapterProgress, 0), 1)
            let script = """
            (function() {
              let style = document.getElementById('inkshelf-reader-style');
              if (!style) { style = document.createElement('style'); style.id = 'inkshelf-reader-style'; document.head.appendChild(style); }
              style.textContent = `\(escapedCSS)`;
              const body = document.body, html = document.documentElement;
              if ('\(flow)' === 'paged') {
                html.style.cssText += 'height:100%;overflow:hidden;';
                body.style.cssText += 'margin:0;padding:\(Int(parent.margin))px;height:calc(100vh - \(Int(parent.margin * 2))px);column-width:calc(100vw - \(Int(parent.margin * 2))px);column-gap:\(Int(parent.margin * 2))px;column-fill:auto;overflow:visible;';
              } else {
                html.style.cssText += 'height:auto;overflow:auto;';
                body.style.cssText += 'margin:0;padding:\(Int(parent.margin))px;min-height:100vh;column-width:auto;column-gap:normal;overflow:visible;';
              }
              \(restore ? "requestAnimationFrame(() => { const m='\(flow)'==='paged' ? document.documentElement.scrollWidth-window.innerWidth : document.documentElement.scrollHeight-window.innerHeight; window.scrollTo('\(flow)'==='paged' ? m*\(restoreValue) : 0, '\(flow)'==='scroll' ? m*\(restoreValue) : 0); });" : "")
            })();
            """
            webView.evaluateJavaScript(script)
        }
    }
}
