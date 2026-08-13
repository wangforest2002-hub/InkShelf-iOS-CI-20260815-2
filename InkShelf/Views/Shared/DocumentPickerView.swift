import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// UIKit's document picker gives us explicit delegate callbacks and control
/// over import-vs-open semantics. Using `asCopy` for local imports asks iOS to
/// materialize File Provider and iCloud items inside the app sandbox before the
/// importer touches them, avoiding short-lived security-scope failures.
struct DocumentPickerView: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    var allowsMultipleSelection = false
    var asCopy = false
    let onResult: (Result<[URL], Error>) -> Void
    var onCancel: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: contentTypes,
            asCopy: asCopy
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let parent: DocumentPickerView
        private var completed = false

        init(parent: DocumentPickerView) {
            self.parent = parent
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            guard !completed else { return }
            completed = true
            parent.onResult(.success(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            guard !completed else { return }
            completed = true
            parent.onCancel()
        }
    }
}
