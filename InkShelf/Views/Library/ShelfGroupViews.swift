import SwiftUI

enum ShelfFilter: Hashable {
    case all
    case ungrouped
    case group(UUID)
}

struct ShelfGroupStrip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: ShelfFilter
    @State private var highlightedFilter: ShelfFilter = .all
    @Namespace private var selectionHighlight
    let groups: [ShelfGroup]
    let totalCount: Int
    let ungroupedCount: Int
    let countForGroup: (UUID) -> Int
    let create: () -> Void
    let rename: (ShelfGroup) -> Void
    let delete: (ShelfGroup) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            AdaptiveGlassContainer(spacing: 10) {
                HStack(spacing: 10) {
                    filterChip(
                        title: "全部",
                        symbol: "books.vertical.fill",
                        count: totalCount,
                        filter: .all,
                        tint: AppTheme.accent
                    )

                    ForEach(groups) { group in
                        filterChip(
                            title: group.title,
                            symbol: group.systemImage,
                            count: countForGroup(group.id),
                            filter: .group(group.id),
                            tint: tint(for: group.styleIndex)
                        )
                        .contextMenu {
                            Button { rename(group) } label: {
                                Label("重命名分组", systemImage: "pencil")
                            }
                            Button(role: .destructive) { delete(group) } label: {
                                Label("删除分组", systemImage: "trash")
                            }
                        }
                    }

                    filterChip(
                        title: "未分组",
                        symbol: "tray.fill",
                        count: ungroupedCount,
                        filter: .ungrouped,
                        tint: AppTheme.wood
                    )

                    Button(action: create) {
                        Image(systemName: "plus")
                            .font(.subheadline.bold())
                            .frame(width: 44, height: 44)
                            .inkGlass(cornerRadius: 22, interactive: true)
                    }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityIdentifier("shelf-new-group")
                    .accessibilityLabel("新建书架分组")
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 1)
        }
        .scrollIndicators(.hidden)
        .onAppear { highlightedFilter = selection }
        .onChange(of: selection) { _, next in
            // The shelf switches its content without animation to avoid cover
            // reflow. Only this small highlight gets an animated transaction.
            var transaction = Transaction(animation: reduceMotion ? nil : AppMotion.panel)
            transaction.disablesAnimations = reduceMotion
            withTransaction(transaction) { highlightedFilter = next }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func filterChip(
        title: String,
        symbol: String,
        count: Int,
        filter: ShelfFilter,
        tint: Color
    ) -> some View {
        let selected = highlightedFilter == filter
        return Button {
            selection = filter
        } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .foregroundStyle(selected ? tint : .secondary)
                Text(title).lineLimit(1)
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(selected ? .primary : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(selected ? tint.opacity(0.12) : Color.secondary.opacity(0.07), in: Capsule())
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background {
                if selected {
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.09) : Color.white.opacity(0.90))
                        .overlay { Capsule().strokeBorder(tint.opacity(0.30), lineWidth: 1) }
                        .matchedGeometryEffect(id: "shelf-selection", in: selectionHighlight)
                }
            }
            .inkGlass(cornerRadius: 24, interactive: true)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier(accessibilityIdentifier(for: filter))
        .accessibilityLabel("\(title)，\(count) 本")
        .accessibilityAddTraits(selection == filter ? .isSelected : [])
        .accessibilityHint("显示这个分组的读物")
    }

    private func accessibilityIdentifier(for filter: ShelfFilter) -> String {
        switch filter {
        case .all: "shelf-filter-all"
        case .ungrouped: "shelf-filter-ungrouped"
        case .group(let id): "shelf-filter-group-\(id.uuidString.lowercased())"
        }
    }

    private func tint(for index: Int) -> Color {
        let colors = [AppTheme.accent, AppTheme.coral, AppTheme.lilac, AppTheme.cyan, AppTheme.wood]
        return colors[abs(index) % colors.count]
    }
}

struct ShelfGroupEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let navigationTitle: String
    let initialTitle: String
    let save: (String) -> Void

    @State private var title: String
    @FocusState private var focused: Bool

    init(navigationTitle: String, initialTitle: String = "", save: @escaping (String) -> Void) {
        self.navigationTitle = navigationTitle
        self.initialTitle = initialTitle
        self.save = save
        _title = State(initialValue: initialTitle)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("分组名称") {
                    TextField("例如：插画集、待读、最喜欢", text: $title)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(commit)
                }
                Section {
                    Label("分组只整理书架，不移动、复制或删除原文件。", systemImage: "checkmark.shield.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AuroraBackground())
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: commit)
                        .disabled(cleanedTitle.isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private var cleanedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commit() {
        guard !cleanedTitle.isEmpty else { return }
        save(cleanedTitle)
        dismiss()
    }
}

struct EmptyShelfGroupCard: View {
    let createGroup: Bool

    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: createGroup ? "folder.badge.plus" : "tray")
                .font(.system(size: 38))
                .foregroundStyle(AppTheme.accent)
            Text("这个分组还没有读物")
                .font(.headline)
            Text("长按一本书，在“移动到分组”中把它放进来。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 38)
        .inkGlass(cornerRadius: 26)
    }
}
