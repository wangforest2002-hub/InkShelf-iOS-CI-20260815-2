import SwiftUI

enum ShelfFilter: Hashable {
    case all
    case ungrouped
    case group(UUID)
}

struct ShelfGroupStrip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: ShelfFilter
    let groups: [ShelfGroup]
    let totalCount: Int
    let ungroupedCount: Int
    let countForGroup: (UUID) -> Int
    let create: () -> Void
    let rename: (ShelfGroup) -> Void
    let delete: (ShelfGroup) -> Void

    var body: some View {
        ScrollView(.horizontal) {
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
                        .frame(width: 42, height: 42)
                        .inkGlass(cornerRadius: 21, interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("shelf-new-group")
                .accessibilityLabel("新建书架分组")
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 1)
        }
        .scrollIndicators(.hidden)
    }

    private func filterChip(
        title: String,
        symbol: String,
        count: Int,
        filter: ShelfFilter,
        tint: Color
    ) -> some View {
        let selected = selection == filter
        return Button {
            withAnimation(reduceMotion ? nil : AppMotion.panel) { selection = filter }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                Text(title).lineLimit(1)
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(selected ? .white.opacity(0.82) : .secondary)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(selected ? .white : .primary)
            .padding(.horizontal, 13)
            .frame(height: 42)
            .background(selected ? tint : Color.clear, in: Capsule())
            .inkGlass(cornerRadius: 21, interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，\(count) 本")
        .accessibilityAddTraits(selected ? .isSelected : [])
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
