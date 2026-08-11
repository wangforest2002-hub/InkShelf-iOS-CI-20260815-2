import SwiftUI

struct EBookNavigatorView: View {
    @Environment(\.dismiss) private var dismiss
    let package: EBookPackage
    @Binding var chapterIndex: Int
    @State private var query = ""

    private var results: [EBookSearchResult] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return package.chapters.enumerated().compactMap { index, chapter in
            guard let range = chapter.searchText.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
            let lower = chapter.searchText.index(range.lowerBound, offsetBy: -45, limitedBy: chapter.searchText.startIndex) ?? chapter.searchText.startIndex
            let upper = chapter.searchText.index(range.upperBound, offsetBy: 85, limitedBy: chapter.searchText.endIndex) ?? chapter.searchText.endIndex
            var excerpt = String(chapter.searchText[lower..<upper])
            if lower != chapter.searchText.startIndex { excerpt = "…" + excerpt }
            if upper != chapter.searchText.endIndex { excerpt += "…" }
            return EBookSearchResult(chapterIndex: index, chapterTitle: chapter.title, excerpt: excerpt)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section("目录") {
                        ForEach(Array(package.chapters.enumerated()), id: \.element.id) { index, chapter in
                            Button {
                                chapterIndex = index
                                dismiss()
                            } label: {
                                HStack {
                                    Text(chapter.title)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if index == chapterIndex {
                                        Image(systemName: "bookmark.fill")
                                            .foregroundStyle(AppTheme.accent)
                                    }
                                }
                            }
                        }
                    }
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    Section("搜索结果") {
                        ForEach(results) { result in
                            Button {
                                chapterIndex = result.chapterIndex
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(result.chapterTitle)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(result.excerpt)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(4)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(package.title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜索正文")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
