import SwiftUI

struct AICompanionPanel: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AICompanionStore.self) private var companion
    let bookTitle: String
    let page: Int
    let pageCount: Int
    let isLastPage: Bool
    let showEndDiscussion: () -> Void
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    companionHeader

                    if !companion.hasAPIKey {
                        ContentUnavailableView {
                            Label("还没有 AI 密钥", systemImage: "key.horizontal")
                        } description: {
                            Text("请先到“设置 → AI 陪读”填写 DeepSeek API 密钥。")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    } else if let reaction = companion.currentReaction, reaction.page == page {
                        reactionCard(reaction)
                        if let translation = reaction.translation {
                            translationCard(translation)
                        }
                        quickQuestions(reaction)
                    } else if companion.activity.isBusy {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("正在理解当前页面…")
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .inkGlass(cornerRadius: 20)
                    } else {
                        Button {
                            companion.regenerateCurrentPage()
                        } label: {
                            Label("分析当前页", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .adaptiveProminentButton()
                    }

                    if let error = companion.errorMessage {
                        HStack(spacing: 12) {
                            Label(error, systemImage: "wifi.exclamationmark")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            Button("重试") { companion.regenerateCurrentPage() }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .disabled(companion.activity.isBusy)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    }

                    ForEach(companion.chatMessages) { message in
                        chatBubble(message)
                    }

                    if isLastPage, companion.endDiscussion != nil {
                        Button(action: showEndDiscussion) {
                            Label("打开 AI 片尾评论区", systemImage: "bubble.left.and.bubble.right.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .adaptiveProminentButton()
                    }
                }
                .padding(18)
            }
            .background(AuroraBackground())
            .navigationTitle("AI 陪读")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if companion.currentReaction?.page == page {
                        Button {
                            companion.regenerateCurrentPage()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(companion.activity.isBusy)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if companion.hasAPIKey {
                    HStack(spacing: 10) {
                        TextField("聊聊这一页…", text: $draft, axis: .vertical)
                            .lineLimit(1...4)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                            .submitLabel(.send)
                            .onSubmit(send)
                        Button(action: send) {
                            Image(systemName: "arrow.up")
                                .font(.headline.bold())
                                .frame(width: 40, height: 40)
                        }
                        .adaptiveProminentButton()
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || companion.activity == .answering)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                }
            }
        }
    }

    private var companionHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(AppTheme.accent.gradient)
                Image(systemName: "sparkles")
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(bookTitle).font(.headline).lineLimit(1)
                Text("第 \(page + 1) / \(pageCount) 页 · \(companion.selectedModelTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func reactionCard(_ reaction: AIPageReaction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(reaction.mood.isEmpty ? "当前页" : reaction.mood, systemImage: "wand.and.stars")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.accent)
                Spacer()
                Text(reaction.isLocalFallback ? "本地轻陪伴" : "本机识别 + DeepSeek")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(reaction.summary)
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .inkGlass(cornerRadius: 22)
    }

    private func quickQuestions(_ reaction: AIPageReaction) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                ForEach(reaction.talkingPoints, id: \.self) { question in
                    Button(question) { ask(question) }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                }
                Button("这一页的情绪？") { ask("这一页传达了什么情绪？") }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func translationCard(_ translation: AIPageTranslation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(
                    translation.title.isEmpty ? "本页日文翻译" : translation.title,
                    systemImage: "character.book.closed.fill"
                )
                .font(.headline)
                .foregroundStyle(AppTheme.coral)
                Spacer()
                Text("日文 OCR → 中文")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(translation.segments.prefix(24).enumerated()), id: \.element.id) { index, segment in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 7) {
                        Text("\(index + 1)")
                            .font(.caption2.monospacedDigit().weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(AppTheme.accent, in: Circle())
                        Text(segment.speaker ?? segment.role.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(segment.translation)
                        .font(.body.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(segment.source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)

                if index < translation.segments.prefix(24).count - 1 {
                    Divider().opacity(0.45)
                }
            }

            if let note = translation.note {
                Label(note, systemImage: "text.bubble")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .inkGlass(cornerRadius: 22)
    }

    private func chatBubble(_ message: AIChatMessage) -> some View {
        Text(message.text)
            .font(.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                message.role == .user ? AppTheme.accent.opacity(0.18) : Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .frame(maxWidth: 310, alignment: message.role == .user ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private func send() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        draft = ""
        ask(value)
    }

    private func ask(_ value: String) {
        Task { await companion.ask(value) }
    }
}
