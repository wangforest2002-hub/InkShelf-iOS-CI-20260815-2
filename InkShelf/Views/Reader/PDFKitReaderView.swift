import PDFKit
import SwiftUI
import UIKit

struct PDFKitReaderView: UIViewRepresentable {
    let url: URL
    @Binding var currentPage: Int
    let layout: ReaderLayout
    let flow: ReaderFlow
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

        guard let document = pdfView.document,
              !document.isLocked,
              currentPage >= 0,
              currentPage < document.pageCount,
              let target = document.page(at: currentPage)
        else { return }

        let visibleIndex = pdfView.currentPage.flatMap { document.index(for: $0) }
        if visibleIndex != currentPage {
            pdfView.go(to: target)
        }
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
            NotificationCenter.default.removeObserver(self, name: .PDFViewPageChanged, object: observedPDFView)
            observedPDFView = nil
        }

        @objc private func pageChanged(_ notification: Notification) {
            guard let pdfView = observedPDFView,
                  let document = pdfView.document,
                  let page = pdfView.currentPage
            else { return }
            let index = document.index(for: page)
            if parent.currentPage != index {
                parent.currentPage = index
            }
        }

        func loadDocument(in pdfView: PDFView) {
            loadedURL = parent.url
            attemptedPassword = ""
            lastConfiguration = ""
            let document = PDFDocument(url: parent.url)
            pdfView.document = document
            applyConfiguration(to: pdfView)
            tryPasswordIfNeeded(in: pdfView)

            guard let document else {
                parent.onDocumentState(0, false)
                return
            }
            parent.onDocumentState(document.pageCount, document.isLocked)
            if !document.isLocked,
               parent.currentPage < document.pageCount,
               let page = document.page(at: parent.currentPage) {
                pdfView.go(to: page)
            }
        }

        func applyConfiguration(to pdfView: PDFView) {
            let key = "\(parent.layout.rawValue)-\(parent.flow.rawValue)-\(parent.order.rawValue)-\(parent.coverSingle)"
            guard key != lastConfiguration else { return }
            lastConfiguration = key

            pdfView.displaysRTL = parent.order == .rightToLeft
            pdfView.displaysAsBook = parent.coverSingle

            if parent.flow == .horizontal {
                pdfView.displayDirection = .horizontal
                pdfView.displayMode = parent.layout == .single ? .singlePage : .twoUp
                pdfView.usePageViewController(
                    true,
                    withViewOptions: [UIPageViewController.OptionsKey.interPageSpacing: 12]
                )
            } else {
                pdfView.usePageViewController(false, withViewOptions: nil)
                pdfView.displayDirection = .vertical
                pdfView.displayMode = parent.layout == .single ? .singlePageContinuous : .twoUpContinuous
            }

            pdfView.autoScales = true
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
                if parent.currentPage < document.pageCount,
                   let page = document.page(at: parent.currentPage) {
                    pdfView.go(to: page)
                }
            }
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
