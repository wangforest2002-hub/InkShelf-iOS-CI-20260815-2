import Foundation

struct DeepSeekPageSettings: Sendable {
    let model: AIModelChoice
    let persona: AICompanionPersona
    let density: AIDanmakuDensity
    let strictSpoilers: Bool
    let includeRecognizedText: Bool
    let allowsCellularAccess: Bool

    var cacheVariant: String {
        [model.rawValue, persona.rawValue, density.rawValue, strictSpoilers ? "strict" : "context", includeRecognizedText ? "ocr" : "noocr"]
            .joined(separator: "-")
    }
}

actor DeepSeekService {
    static let shared = DeepSeekService()

    private let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func validate(apiKey: String, model: AIModelChoice, allowsCellularAccess: Bool) async throws {
        _ = try await completion(
            apiKey: apiKey,
            model: model,
            messages: [
                ChatMessage(role: "system", content: "只回复 OK。"),
                ChatMessage(role: "user", content: "连接测试")
            ],
            maxTokens: 16,
            temperature: 0,
            json: false,
            allowsCellularAccess: allowsCellularAccess
        )
    }

    func pageReaction(
        apiKey: String,
        bookTitle: String,
        insight: AIPageInsight,
        recentReactions: [AIPageReaction],
        settings: DeepSeekPageSettings
    ) async throws -> AIPageReaction {
        let pageNumber = insight.page + 1
        let recent = recentReactions.suffix(4).map {
            "第\($0.page + 1)页：\($0.summary)；氛围：\($0.mood)"
        }.joined(separator: "\n")
        let text = settings.includeRecognizedText ? insight.recognizedText : "（用户已关闭对白上传）"
        let spoilerRule = settings.strictSpoilers
            ? "只能依据当前页和下方已读页摘要，绝不能推测或暗示后续剧情。"
            : "可以联系下方已读页摘要，但绝不能使用或暗示尚未阅读的内容。"

        let prompt = """
        请为《\(bookTitle)》第 \(pageNumber)/\(insight.pageCount) 页生成陪读内容。
        陪伴风格：\(settings.persona.promptDescription)
        弹幕数量：准确生成 \(settings.density.messageCount) 条。
        防剧透规则：\(spoilerRule)

        本机识别到的页面信息：
        - 来源：\(insight.sourceKind)
        - 人脸数量：\(insight.faceCount)
        - 画面标签：\(insight.visualLabels.isEmpty ? "无可靠标签" : insight.visualLabels.joined(separator: "、"))
        - 对白/文字：
        \(text.isEmpty ? "（未识别到文字）" : text)

        最近已读页摘要：
        \(recent.isEmpty ? "（这是本次阅读中首个由 AI 分析的页面）" : recent)

        输出一个 JSON 对象，结构必须是：
        {"summary":"一句不超过60字的本页概述","mood":"2到8字氛围","danmaku":[{"text":"不超过24字、像真实观众即时反应","tone":"normal|excited|amused|touched|curious"}],"talking_points":["最多3条可继续聊的话题"]}
        弹幕要彼此不同，避免空洞夸赞；信息不足时表达直观情绪，不要编造角色姓名和剧情事实。
        """

        let content = try await completion(
            apiKey: apiKey,
            model: settings.model,
            messages: [ChatMessage(role: "system", content: Self.companionSystemPrompt), ChatMessage(role: "user", content: prompt)],
            maxTokens: 900,
            temperature: 0.95,
            json: true,
            allowsCellularAccess: settings.allowsCellularAccess
        )
        let payload = try decode(PagePayload.self, from: content)
        let messages = payload.danmaku
            .prefix(settings.density.messageCount)
            .compactMap { item -> AIDanmakuMessage? in
                let text = cleaned(item.text, limit: 28)
                guard !text.isEmpty else { return nil }
                return AIDanmakuMessage(text: text, tone: AIDanmakuTone(rawValue: item.tone) ?? .normal)
            }

        return AIPageReaction(
            page: insight.page,
            summary: cleaned(payload.summary, limit: 90),
            mood: cleaned(payload.mood, limit: 14),
            danmaku: messages,
            talkingPoints: payload.talkingPoints.prefix(3).map { cleaned($0, limit: 60) }.filter { !$0.isEmpty }
        )
    }

    func endDiscussion(
        apiKey: String,
        bookTitle: String,
        pageCount: Int,
        reactions: [AIPageReaction],
        settings: DeepSeekPageSettings
    ) async throws -> AIEndDiscussion {
        let readingTrail = reactions.suffix(16).map {
            "第\($0.page + 1)页：\($0.summary)（\($0.mood)）"
        }.joined(separator: "\n")
        let prompt = """
        用户刚读到《\(bookTitle)》的最后一页，全书/画集共 \(pageCount) 页。请根据本次阅读中已经生成的摘要，模拟一个温暖、有趣但明确是虚构的片尾评论区。

        已读摘要：
        \(readingTrail.isEmpty ? "没有足够摘要，只能围绕完成阅读的感受评论，不得编造具体剧情。" : readingTrail)

        生成 8 位表达方式明显不同的虚构读者：有人关注情绪、有人看细节、有人幽默、有人简短感叹。用户名自然但不要冒充真实公众人物。评论不应声称来自互联网或其他真实用户。
        输出 JSON：
        {"title":"片尾评论区标题","closing_note":"AI陪读员给用户的两三句收尾陪伴","comments":[{"username":"虚构昵称","avatar_emoji":"单个emoji","body":"评论正文","likes":12,"badge":"可选短标签或空字符串"}]}
        """
        let content = try await completion(
            apiKey: apiKey,
            model: settings.model,
            messages: [ChatMessage(role: "system", content: Self.companionSystemPrompt), ChatMessage(role: "user", content: prompt)],
            maxTokens: 1_700,
            temperature: 1.05,
            json: true,
            allowsCellularAccess: settings.allowsCellularAccess
        )
        let payload = try decode(EndPayload.self, from: content)
        var seenNames = Set<String>()
        let comments = payload.comments.prefix(10).compactMap { item -> AISimulatedComment? in
            let username = cleaned(item.username, limit: 18)
            let body = cleaned(item.body, limit: 180)
            guard !username.isEmpty, !body.isEmpty, seenNames.insert(username).inserted else { return nil }
            return AISimulatedComment(
                username: username,
                avatarEmoji: cleaned(item.avatarEmoji, limit: 4).isEmpty ? "💬" : cleaned(item.avatarEmoji, limit: 4),
                body: body,
                likes: min(max(item.likes, 0), 9_999),
                badge: cleaned(item.badge ?? "", limit: 10).nilIfEmpty
            )
        }
        return AIEndDiscussion(
            title: cleaned(payload.title, limit: 40),
            closingNote: cleaned(payload.closingNote, limit: 260),
            comments: comments
        )
    }

    func answer(
        apiKey: String,
        question: String,
        bookTitle: String,
        insight: AIPageInsight?,
        reaction: AIPageReaction?,
        conversation: [AIChatMessage],
        settings: DeepSeekPageSettings
    ) async throws -> String {
        let pageContext: String
        if let insight, let reaction {
            pageContext = """
            当前是《\(bookTitle)》第 \(insight.page + 1)/\(insight.pageCount) 页。
            本页摘要：\(reaction.summary)
            氛围：\(reaction.mood)
            已识别文字：\(settings.includeRecognizedText ? insight.recognizedText : "用户未允许上传")
            """
        } else {
            pageContext = "当前页还没有分析结果。回答时说明信息有限，不要编造。"
        }
        let history = conversation.suffix(8).map {
            "\($0.role == .user ? "用户" : "陪读员")：\($0.text)"
        }.joined(separator: "\n")
        let spoilerRule = settings.strictSpoilers ? "绝不讨论当前页之后的内容。" : "只能联系已经提供的阅读上下文。"
        let prompt = """
        \(pageContext)
        陪伴风格：\(settings.persona.promptDescription)
        防剧透：\(spoilerRule)
        最近对话：
        \(history)

        用户现在问：\(question)
        请像一起看书的朋友一样直接回答，控制在 220 字以内；信息不足时坦诚说明。
        """
        return cleaned(try await completion(
            apiKey: apiKey,
            model: settings.model,
            messages: [ChatMessage(role: "system", content: Self.companionSystemPrompt), ChatMessage(role: "user", content: prompt)],
            maxTokens: 500,
            temperature: 0.8,
            json: false,
            allowsCellularAccess: settings.allowsCellularAccess
        ), limit: 500)
    }

    private func completion(
        apiKey: String,
        model: AIModelChoice,
        messages: [ChatMessage],
        maxTokens: Int,
        temperature: Double,
        json: Bool,
        allowsCellularAccess: Bool
    ) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw DeepSeekError.missingKey }

        let body = ChatRequest(
            model: model.modelID,
            messages: messages,
            thinking: Thinking(type: "disabled"),
            maxTokens: maxTokens,
            temperature: temperature,
            responseFormat: json ? ResponseFormat(type: "json_object") : nil
        )
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 50
        request.allowsCellularAccess = allowsCellularAccess
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        let session = URLSession(configuration: configuration)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DeepSeekError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data)
            throw DeepSeekError.server(status: http.statusCode, message: envelope?.error.message)
        }
        let decoded = try decoder.decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw DeepSeekError.emptyResponse }
        return content
    }

    private func decode<T: Decodable>(_ type: T.Type, from content: String) throws -> T {
        let cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8) else { throw DeepSeekError.invalidJSON }
        do { return try decoder.decode(type, from: data) }
        catch { throw DeepSeekError.invalidJSON }
    }

    private func cleaned(_ value: String, limit: Int) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }

    private static let companionSystemPrompt = """
    你是“二次元小家”的 AI 陪读员。你只依据应用提供的已读页面信息陪伴用户阅读，不把猜测说成事实，不泄露后续剧情。语气自然、有温度、简洁，不使用营销腔。模拟评论必须是虚构内容，不能暗示它来自真实网络用户。你看到的是本机视觉识别后的文字与标签，不是原图，因此要承认信息边界。
    """
}

enum DeepSeekError: LocalizedError {
    case missingKey
    case invalidResponse
    case emptyResponse
    case invalidJSON
    case server(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .missingKey: return "请先在设置中填写 DeepSeek API 密钥。"
        case .invalidResponse: return "DeepSeek 返回了无法识别的响应。"
        case .emptyResponse: return "AI 这次没有生成内容，请稍后重试。"
        case .invalidJSON: return "AI 返回的内容格式不完整，请重试。"
        case .server(let status, let message):
            if status == 401 { return "DeepSeek 密钥无效或已失效，请重新填写。" }
            if status == 402 { return "DeepSeek 账户余额不足。" }
            if status == 429 { return "请求有些频繁，请稍后再试。" }
            return message.map { "DeepSeek 请求失败（\(status)）：\($0)" } ?? "DeepSeek 请求失败（\(status)）。"
        }
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let thinking: Thinking
    let maxTokens: Int
    let temperature: Double
    let responseFormat: ResponseFormat?

    enum CodingKeys: String, CodingKey {
        case model, messages, thinking, temperature
        case maxTokens = "max_tokens"
        case responseFormat = "response_format"
    }
}

private struct ChatMessage: Encodable {
    let role: String
    let content: String
}

private struct Thinking: Encodable { let type: String }
private struct ResponseFormat: Encodable { let type: String }

private struct ChatResponse: Decodable {
    let choices: [Choice]
    struct Choice: Decodable { let message: ResponseMessage }
    struct ResponseMessage: Decodable { let content: String? }
}

private struct APIErrorEnvelope: Decodable {
    let error: APIErrorBody
    struct APIErrorBody: Decodable { let message: String }
}

private struct PagePayload: Decodable {
    let summary: String
    let mood: String
    let danmaku: [DanmakuPayload]
    let talkingPoints: [String]
}

private struct DanmakuPayload: Decodable {
    let text: String
    let tone: String
}

private struct EndPayload: Decodable {
    let title: String
    let closingNote: String
    let comments: [EndCommentPayload]
}

private struct EndCommentPayload: Decodable {
    let username: String
    let avatarEmoji: String
    let body: String
    let likes: Int
    let badge: String?
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
