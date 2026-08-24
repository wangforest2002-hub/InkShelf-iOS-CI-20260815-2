import PDFKit
import SwiftUI
import UIKit

struct PDFKitReaderView: UIViewRepresentable {
    let url: URL
    @Binding var currentPage: Int
    let layout: ReaderLayout
    let flow: ReaderFlow
    let transition: ReaderPageTransition
    let order: ReadingOrder
    let coverSingle: Bool
    let password: String
    let onTap: () -> Void
    let onDocumentState: (_ pageCount: Int, _ isLocked: Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView(frame: .zero)
        pdfView.backgroundColor = .clear
        pdfView.displaysPageBreaks = true
        pdfView.pageBreakMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        pdfView.pageShadowsEnabled = false
        pdfView.displayBox = .cropBox
        pdfView.autoScales = true
        pdfView.minScaleFactor = 0.25
        pdfView.maxScaleFactor = 12

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        pdfView.addGestureRecognizer(tap)

        context.coordinator.attach(to: pdfView)
        context.coordinator.loadDocument(in: pdfView)
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        context.coordinator.parent = self

        if context.coordinator.loadedURL != url {
            context.coordinator.loadDocument(in: pdfView)
        }

        context.coordinator.applyConfiguration(to: pdfView)
        context.coordinator.tryPasswordIfNeeded(in: pdfView)

        context.coordinator.navigate(to: currentPage, in: pdfView)
    }

    static func dismantleUIView(_ pdfView: PDFView, coordinator: Coordinator) {
        coordinator.detach()
        pdfView.document = nil
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PDFKitReaderView
        var loadedURL: URL?
        private weak var observedPDFView: PDFView?
        private var lastConfiguration = ""
        private var attemptedPassword = ""
        private var navigationGeneration = 0
        private var pendingTargetPage: Int?

        init(parent: PDFKitReaderView) {
            self.parent = parent
        }

        func attach(to pdfView: PDFView) {
            observedPDFView = pdfView
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pageChanged(_:)),
                name: .PDFViewPageChanged,
                object: pdfView
            )
        }

        func detach() {
            cancelPendingNavigation()
            NotificationCenter.default.removeObserver(self, name: .PDFViewPageChanged, object: observedPDFView)
            observedPDFView = nil
        }

        @objc private func pageChanged(_ notification: Notification) {
            guard let pdfView = observedPDFView,
                  let document = pdfView.document,
                  let page = pdfView.currentPage
            else { return }
            let index = document.index(for: page)
            let anchor = normalizedAnchor(for: index, pageCount: document.pageCount)
            // PDFKit can emit intermediate page-change notifications while
            // reconfiguring or executing `go(to:)`. Those notifications must
            // not overwrite a newer slider/thumbnail request.
            guard pendingTargetPage == nil else { return }
            if parent.currentPage != anchor {
                parent.currentPage = anchor
            }
        }

        func loadDocument(in pdfView: PDFView) {
            loadedURL = parent.url
            attemptedPassword = ""
            lastConfiguration = ""
            let document = PDFDocument(url: parent.url)
            cancelPendingNavigation()
            if let document, !document.isLocked {
                beginPendingNavigation(
                    to: normalizedAnchor(for: parent.currentPage, pageCount: document.pageCount),
                    in: pdfView
                )
            }
            pdfView.document = document
            applyConfiguration(to: pdfView)
            tryPasswordIfNeeded(in: pdfView)

            guard let document else {
                parent.onDocumentState(0, false)
                return
            }
            parent.onDocumentState(document.pageCount, document.isLocked)
            if !document.isLocked { navigate(to: parent.currentPage, in: pdfView) }
        }

        func applyConfiguration(to pdfView: PDFView) {
            let key = "\(parent.layout.rawValue)-\(parent.flow.rawValue)-\(parent.transition.rawValue)-\(parent.order.rawValue)-\(parent.coverSingle)"
            guard key != lastConfiguration else { return }
            lastConfiguration = key

            let preservedPage = pdfView.document.map {
                normalizedAnchor(for: parent.currentPage, pageCount: $0.pageCount)
            }
            if let preservedPage, pdfView.document?.isLocked == false {
                beginPendingNavigation(to: preservedPage, in: pdfView)
            }

            pdfView.displaysRTL = parent.order == .rightToLeft
            pdfView.displaysAsBook = parent.coverSingle
            let usesBookPresentation = parent.transition == .book && parent.flow == .horizontal
            pdfView.pageShadowsEnabled = usesBookPresentation
            let pageSpacing: CGFloat = usesBookPresentation ? 4 : 12
            pdfView.pageBreakMargins = UIEdgeInsets(
                top: pageSpacing,
                left: pageSpacing,
                bottom: pageSpacing,
                right: pageSpacing
            )

            switch parent.flow {
            case .horizontal:
                pdfView.displayDirection = .horizontal
                pdfView.displayMode = parent.layout == .single ? .singlePage : .twoUp
                pdfView.usePageViewController(
                    true,
                    withViewOptions: [UIPageViewController.OptionsKey.interPageSpacing: pageSpacing]
                )
            case .vertical:
                pdfView.displayDirection = .vertical
                pdfView.displayMode = parent.layout == .single ? .singlePage : .twoUp
                pdfView.usePageViewController(
                    true,
                    withViewOptions: [UIPageViewController.OptionsKey.interPageSpacing: pageSpacing]
                )
            case .continuous:
                pdfView.usePageViewController(false, withViewOptions: nil)
                pdfView.displayDirection = .vertical
                pdfView.displayMode = parent.layout == .single ? .singlePageContinuous : .twoUpContinuous
            }

            pdfView.autoScales = true
            if let preservedPage, pdfView.document?.isLocked == false {
                navigate(to: preservedPage, in: pdfView, force: true)
            }
        }

        func tryPasswordIfNeeded(in pdfView: PDFView) {
            guard let document = pdfView.document else { return }
            guard document.isLocked else {
                parent.onDocumentState(document.pageCount, false)
                return
            }
            guard !parent.password.isEmpty, parent.password != attemptedPassword else {
                parent.onDocumentState(document.pageCount, true)
                return
            }

            attemptedPassword = parent.password
            let unlocked = document.unlock(withPassword: parent.password)
            parent.onDocumentState(document.pageCount, !unlocked)
            if unlocked {
                pdfView.autoScales = true
                navigate(to: parent.currentPage, in: pdfView, force: true)
            }
        }

        func navigate(to requestedPage: Int, in pdfView: PDFView, force: Bool = false) {
            guard let document = pdfView.document, !document.isLocked, document.pageCount > 0 else { return }
            let target = normalizedAnchor(for: requestedPage, pageCount: document.pageCount)
            let visibleAnchor = pdfView.currentPage.map {
                normalizedAnchor(for: document.index(for: $0), pageCount: document.pageCount)
            }

            if visibleAnchor == target, !force {
                if let pendingTargetPage, pendingTargetPage != target {
                    beginPendingNavigation(to: target, in: pdfView)
                }
                return
            }

            beginPendingNavigation(to: target, in: pdfView)
            guard let page = document.page(at: target) else { return }
            pdfView.go(to: page)
        }

        private func normalizedAnchor(for page: Int, pageCount: Int) -> Int {
            ReaderPagePosition(
                currentPage: page,
                pageCount: pageCount,
                layout: parent.layout,
                flow: parent.flow,
                coverSingle: parent.coverSingle,
                isEBook: false
            ).anchorPage
        }

        private func beginPendingNavigation(to target: Int, in pdfView: PDFView) {
            guard pendingTargetPage != target else { return }
            navigationGeneration += 1
            let generation = navigationGeneration
            pendingTargetPage = target

            // Keep the gate open across PDFKit's delayed notifications, then
            // reconcile once with the page that is actually visible. A newer
            // request increments the generation and cancels this reconciliation.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self, weak pdfView] in
                guard let self, let pdfView,
                      self.navigationGeneration == generation,
                      self.pendingTargetPage == target
                else { return }
                self.pendingTargetPage = nil
                guard let document = pdfView.document,
                      let visiblePage = pdfView.currentPage
                else { return }
                let visibleAnchor = self.normalizedAnchor(
                    for: document.index(for: visiblePage),
                    pageCount: document.pageCount
                )
                if self.parent.currentPage != visibleAnchor {
                    self.parent.currentPage = visibleAnchor
                }
            }
        }

        private func cancelPendingNavigation() {
            navigationGeneration += 1
            pendingTargetPage = nil
        }

        @objc func handleTap() {
            parent.onTap()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
