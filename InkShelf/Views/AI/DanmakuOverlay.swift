import SwiftUI

struct DanmakuOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let messages: [AIDanmakuMessage]
    let pageToken: String

    var body: some View {
        GeometryReader { proxy in
            if reduceMotion {
                VStack(alignment: .trailing, spacing: 8) {
                    ForEach(messages.prefix(3)) { message in
                        DanmakuBubble(message: message)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 16)
                .padding(.top, 92)
            } else {
                ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                    DanmakuTrack(
                        message: message,
                        token: pageToken,
                        lane: index % 6,
                        order: index,
                        canvasSize: proxy.size
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct DanmakuTrack: View {
    let message: AIDanmakuMessage
    let token: String
    let lane: Int
    let order: Int
    let canvasSize: CGSize
    @State private var started = false

    var body: some View {
        DanmakuBubble(message: message)
            .position(x: canvasSize.width / 2, y: 112 + CGFloat(lane) * max(42, min(58, (canvasSize.height - 260) / 6)))
            .offset(x: started ? -(canvasSize.width + 440) / 2 : (canvasSize.width + 440) / 2)
            .animation(.linear(duration: 7.5 + Double(order % 4) * 0.7), value: started)
            .task(id: "\(token)-\(message.id)") {
                started = false
                try? await Task.sleep(for: .milliseconds(250 + order * 430))
                guard !Task.isCancelled else { return }
                started = true
            }
    }
}

private struct DanmakuBubble: View {
    let message: AIDanmakuMessage

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(toneColor.gradient)
                .frame(width: 7, height: 7)
            Text(message.text)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.58), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        .fixedSize()
    }

    private var toneColor: Color {
        switch message.tone {
        case .normal: AppTheme.accent
        case .excited: .pink
        case .amused: .yellow
        case .touched: .mint
        case .curious: .cyan
        }
    }
}

struct AIReadingPill: View {
    let activity: AICompanionActivity

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(label)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .inkGlass(cornerRadius: 18)
        .accessibilityLabel(label)
    }

    private var label: String {
        switch activity {
        case .readingPage: "AI 正在读这一页"
        case .generatingDiscussion: "正在生成片尾评论"
        case .answering: "陪读员正在想"
        case .idle: "AI 陪读"
        }
    }
}
