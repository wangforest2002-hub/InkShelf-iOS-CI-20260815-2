import Foundation

enum LocalCompanionFallback {
    static func pageReaction(insight: AIPageInsight, settings: DeepSeekPageSettings) -> AIPageReaction {
        var messages: [AIDanmakuMessage] = [
            AIDanmakuMessage(text: "我还在这里陪你看", tone: .touched),
            AIDanmakuMessage(text: "这页值得慢慢停一下", tone: .normal)
        ]
        if insight.faceCount > 0 {
            messages.append(AIDanmakuMessage(text: "人物的表情很抓人", tone: .curious))
        }
        if !insight.recognizedText.isEmpty {
            messages.append(AIDanmakuMessage(text: "台词里好像藏着情绪", tone: .curious))
        }
        if !insight.visualLabels.isEmpty {
            messages.append(AIDanmakuMessage(text: "画面的氛围很完整", tone: .touched))
        }
        messages.append(contentsOf: [
            AIDanmakuMessage(text: "先把这一刻收进心里", tone: .touched),
            AIDanmakuMessage(text: "网络恢复后再细读一遍", tone: .normal),
            AIDanmakuMessage(text: "不着急，按你的节奏来", tone: .normal),
            AIDanmakuMessage(text: "这一页有收藏价值", tone: .excited),
            AIDanmakuMessage(text: "让我也多看两秒", tone: .amused),
            AIDanmakuMessage(text: "回到这里就很安心", tone: .touched)
        ])

        let summary: String
        if !insight.recognizedText.isEmpty {
            summary = "云端暂时没有回应，我先陪你留意这一页的文字与情绪。"
        } else if insight.faceCount > 0 {
            summary = "云端暂时没有回应，我先陪你看看人物表情和画面氛围。"
        } else {
            summary = "云端暂时没有回应，我先安静陪你把这一页看完。"
        }
        return AIPageReaction(
            page: insight.page,
            summary: summary,
            mood: "本地轻陪伴",
            danmaku: Array(messages.prefix(settings.density.messageCount)),
            talkingPoints: ["稍后重新细读这一页", "你最喜欢这一页的哪里？"],
            source: .localFallback
        )
    }

    static func endDiscussion(bookTitle: String, pageCount: Int) -> AIEndDiscussion {
        AIEndDiscussion(
            title: "先在家里聊聊《\(bookTitle)》",
            closingNote: "云端暂时没有回应，不过读完 \(pageCount) 页本身就是一段小小旅程。等网络恢复后，还可以重新生成更完整的片尾讨论。",
            comments: [
                AISimulatedComment(username: "窝在沙发角", avatarEmoji: "🛋️", body: "读到最后一页时，突然有种把一段时光好好收起来的感觉。", likes: 8, badge: "本地模拟"),
                AISimulatedComment(username: "窗边翻页人", avatarEmoji: "🌤️", body: "先不急着分析，喜欢的画面多停一会儿就很好。", likes: 6, badge: "本地模拟"),
                AISimulatedComment(username: "小家留声机", avatarEmoji: "🏠", body: "欢迎回来，下次也一起慢慢读。", likes: 9, badge: "本地模拟")
            ]
        )
    }
}
