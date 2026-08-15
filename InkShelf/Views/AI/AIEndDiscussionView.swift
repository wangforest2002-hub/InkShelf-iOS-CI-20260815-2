import SwiftUI

struct AIEndDiscussionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AICompanionStore.self) private var companion
    let bookTitle: String

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    Label("以下均为 AI 模拟读者，不是真实用户", systemImage: "wand.and.stars")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(AppTheme.accent.opacity(0.11), in: Capsule())

                    if let discussion = companion.endDiscussion {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(discussion.title)
                                .font(.title2.bold())
                            Text(discussion.closingNote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)

                        ForEach(discussion.comments) { comment in
                            commentRow(comment)
                        }
                    } else {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("正在组织片尾评论区…")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 50)
                    }
                }
                .padding(18)
            }
            .background(AuroraBackground())
            .navigationTitle(bookTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        companion.generateEndDiscussion(force: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(companion.activity == .generatingDiscussion)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func commentRow(_ comment: AISimulatedComment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(comment.avatarEmoji)
                .font(.title2)
                .frame(width: 42, height: 42)
                .background(.thinMaterial, in: Circle())

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text(comment.username).font(.subheadline.bold())
                    if let badge = comment.badge {
                        Text(badge)
                            .font(.caption2.bold())
                            .foregroundStyle(AppTheme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(AppTheme.accent.opacity(0.1), in: Capsule())
                    }
                }
                Text(comment.body)
                    .fixedSize(horizontal: false, vertical: true)
                Label("\(comment.likes)", systemImage: "heart")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
