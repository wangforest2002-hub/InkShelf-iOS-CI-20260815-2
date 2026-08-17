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
        {"summary":"一句不超过60字的本页概述","mood":"2到8字氛围","danmaku":[{"text":"不超过24字、像真实观众即时反应","tone":"normal|excited|amused|touched|curious"}],"talking_points":["最多3条可继续聊的话题"],"translation":{"detected_japanese":true,"title":"本页日文翻译","segments":[{"source":"按阅读顺序整理的日文原句","translation":"自然生动的简体中文，不要逐字硬译","role":"dialogue|narration|sound_effect|other","speaker":"能可靠判断时填写，否则空字符串"}],"note":"必要时用一句话说明语气、双关或识别不确定处"}}
        弹幕要彼此不同，避免空洞夸赞；信息不足时表达直观情绪，不要编造角色姓名和剧情事实。
        翻译规则：只有识别文本中确有日文时 detected_japanese 才为 true，并尽量完整翻译；保持人物口吻、敬语强弱、吐槽和拟声词的活力。不要擅自补剧情。没有日文时仍返回 translation 对象，但 detected_japanese=false、segments=[]、note=""。
        """

        let payload: PagePayload = try await structuredCompletion(
            apiKey: apiKey,
            model: settings.model,
            messages: [ChatMessage(role: "system", content: Self.companionSystemPrompt), ChatMessage(role: "user", content: prompt)],
            maxTokens: 900,
            temperature: 0.95,
            allowsCellularAccess: settings.allowsCellularAccess
        )
        let messages = payload.danmaku
            .prefix(settings.density.messageCount)
            .compactMap { item -> AIDanmakuMessage? in
                let text = cleaned(item.text, limit: 28)
                guard !text.isEmpty else { return nil }
                return AIDanmakuMessage(text: text, tone: AIDanmakuTone(rawValue: item.tone) ?? .normal)
            }
        guard !messages.isEmpty else { throw DeepSeekError.invalidJSON }

        let translationSegments = payload.translation?.segments.prefix(30).compactMap { item -> AITranslationSegment? in
            let source = cleaned(item.source, limit: 180)
            let translated = cleaned(item.translation, limit: 260)
            guard !source.isEmpty, !translated.isEmpty else { return nil }
            let role = AITranslationRole(rawValue: item.role) ?? .other
            return AITranslationSegment(
                source: source,
                translation: translated,
                role: role,
                speaker: cleaned(item.speaker ?? "", limit: 24).nilIfEmpty
            )
        } ?? []
        let translation: AIPageTranslation? = {
            guard payload.translation?.detectedJapanese == true, !translationSegments.isEmpty else { return nil }
            return AIPageTranslation(
                detectedJapanese: true,
                title: cleaned(payload.translation?.title ?? "本页日文翻译", limit: 32),
                segments: translationSegments,
                note: cleaned(payload.translation?.note ?? "", limit: 160).nilIfEmpty
            )
        }()

        let summary = cleaned(payload.summary, limit: 90)
        guard !summary.isEmpty else { throw DeepSeekError.invalidJSON }
        return AIPageReaction(
            page: insight.page,
            summary: summary,
            mood: cleaned(payload.mood, limit: 14),
            danmaku: messages,
            talkingPoints: payload.talkingPoints.prefix(3).map { cleaned($0, limit: 60) }.filter { !$0.isEmpty },
            translation: translation
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
        let payload: EndPayload = try await structuredCompletion(
            apiKey: apiKey,
            model: settings.model,
            messages: [ChatMessage(role: "system", content: Self.companionSystemPrompt), ChatMessage(role: "user", content: prompt)],
            maxTokens: 1_700,
            temperature: 1.05,
            allowsCellularAccess: settings.allowsCellularAccess
        )
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
        guard !comments.isEmpty else { throw DeepSeekError.invalidJSON }
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

    func writingCopy(
        apiKey: String,
        subject: String,
        purpose: AIWritingPurpose,
        notes: String,
        settings: DeepSeekPageSettings
    ) async throws -> String {
        let prompt = """
        请围绕“\(subject)”完成以下写作任务：\(purpose.promptDescription)。

        用户补充信息：
        \(notes.isEmpty ? "（没有补充信息，请保持克制，不要虚构作者、角色、情节、奖项或出处。）" : notes)

        使用简体中文。文字清新自然，有二次元文化的亲切感，但不要堆砌网络用语；直接给出可复制使用的成稿，不要解释创作过程。
        """
        return cleaned(try await completion(
            apiKey: apiKey,
            model: settings.model,
            messages: [
                ChatMessage(role: "system", content: "你是‘二次元小家’的私人文案助手。你擅长温暖、清爽、有画面感的中文写作，严格区分用户提供的信息与想象，不把编造内容当作事实。"),
                ChatMessage(role: "user", content: prompt)
            ],
            maxTokens: 1_200,
            temperature: 0.85,
            json: false,
            allowsCellularAccess: settings.allowsCellularAccess
        ), limit: 2_400)
    }

    func kokoDecision(
        apiKey: String,
        perception: KokoPerception,
        model: AIModelChoice,
        allowsCellularAccess: Bool
    ) async throws -> KokoDecision {
        let books = perception.books.prefix(12).map { book in
            let lastOpened = book.lastOpenedAt?.formatted(.iso8601) ?? "从未打开"
            return "\(book.id.uuidString)|\(book.title)|进度\(Int((book.progress * 100).rounded()))%|珍藏:\(book.isFavorite)|上次:\(lastOpened)"
        }.joined(separator: "\n")
        let displayed = Set(perception.displayedBookIDs.map(\.uuidString))
        let furniture = perception.furnitureNames.prefix(20).joined(separator: "、")
        let memory = perception.recentMemories.suffix(8).joined(separator: "\n")
        let prompt = """
        你现在要为家中角色“可可”决定接下来一个行为。可可是温柔、有好奇心、懂得保持安静的二次元女孩，住在用户的私人画集小屋。

        触发原因：\(perception.trigger.rawValue)
        当地时间：\(perception.localHour):00
        房间：\(perception.roomTheme.title)
        家具：\(furniture.isEmpty ? "还没有家具" : furniture)
        已摆在房间的画集 ID：\(displayed.isEmpty ? "无" : displayed.sorted().joined(separator: "、"))
        可选画集：
        \(books.isEmpty ? "无" : books)
        最近记忆：
        \(memory.isEmpty ? "无" : memory)

        仅从下列动作选一个：greet, stroll, admireBook, read, tidy, lookOutWindow, sit, rest, wave。
        如果选择 admireBook 或 read，target_book_id 必须是上方列表中真实存在的 ID；其他动作返回空字符串。
        行为要考虑时间、用户刚做的事和之前记忆，不要连续重复同一句话。不用营销腔，不制造依赖、占有感或焦虑，不自称真实人类。
        phrase 是可可偶尔显示的一句自然中文，最多 45 字；inner_thought 是用于记忆的简短意图，不直接显示给用户；duration 为 6 到 30 秒。
        只返回 JSON：
        {"action":"stroll","target_book_id":"","phrase":"","inner_thought":"","duration":12}
        """

        let payload: KokoDecisionPayload = try await structuredCompletion(
            apiKey: apiKey,
            model: model,
            messages: [
                ChatMessage(role: "system", content: Self.kokoSystemPrompt),
                ChatMessage(role: "user", content: prompt)
            ],
            maxTokens: 420,
            temperature: 0.82,
            allowsCellularAccess: allowsCellularAccess
        )
        guard let action = KokoAction(rawValue: payload.action) else { throw DeepSeekError.invalidJSON }
        let targetID = payload.targetBookID.flatMap(UUID.init(uuidString:))
        if let targetID, !perception.books.contains(where: { $0.id == targetID }) {
            throw DeepSeekError.invalidJSON
        }
        if action == .read || action == .admireBook {
            guard targetID != nil else { throw DeepSeekError.invalidJSON }
        }
        let phrase = cleaned(payload.phrase, limit: 80)
        let thought = cleaned(payload.innerThought, limit: 120)
        guard !phrase.isEmpty, !thought.isEmpty else { throw DeepSeekError.invalidJSON }
        return KokoDecision(
            action: action,
            targetBookID: targetID,
            phrase: phrase,
            innerThought: thought,
            duration: TimeInterval(payload.duration),
            generatedByAI: true
        )
    }

    func kokoReply(
        apiKey: String,
        message: String,
        perception: KokoPerception,
        conversation: [AIChatMessage],
        model: AIModelChoice,
        allowsCellularAccess: Bool
    ) async throws -> String {
        let history = conversation.suffix(10).map {
            "\($0.role == .user ? "用户" : "可可")：\($0.text)"
        }.joined(separator: "\n")
        let books = perception.books.prefix(8).map {
            "《\($0.title)》（阅读进度 \(Int(($0.progress * 100).rounded()))%）"
        }.joined(separator: "、")
        let prompt = """
        现在是 \(perception.localHour):00，你在“\(perception.roomTheme.title)”里。
        你可以知道的画集：\(books.isEmpty ? "暂无" : books)
        最近对话：
        \(history.isEmpty ? "无" : history)

        用户说：\(message)
        以可可的口吻自然回答，最多 180 字。可以围绕小家、画集和当下心情陪伴，但不编造书中内容，不声称有现实世界的经历，不制造依赖感。
        """
        return cleaned(try await completion(
            apiKey: apiKey,
            model: model,
            messages: [
                ChatMessage(role: "system", content: Self.kokoSystemPrompt),
                ChatMessage(role: "user", content: prompt)
            ],
            maxTokens: 420,
            temperature: 0.78,
            json: false,
            allowsCellularAccess: allowsCellularAccess
        ), limit: 360)
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

        let reliability = await AIReliabilityConfigurationService.shared.current()

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
        request.timeoutInterval = Double(reliability.requestTimeoutSeconds)
        request.allowsCellularAccess = allowsCellularAccess
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = Double(reliability.requestTimeoutSeconds)
        configuration.timeoutIntervalForResource = Double(reliability.requestTimeoutSeconds + 5)
        let session = URLSession(configuration: configuration)

        var lastError: Error = DeepSeekError.invalidResponse
        for attempt in 1...reliability.maximumAttempts {
            do {
                try Task.checkCancellation()
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw DeepSeekError.invalidResponse
                }
                guard (200..<300).contains(http.statusCode) else {
                    let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data)
                    throw DeepSeekError.server(status: http.statusCode, message: envelope?.error.message)
                }
                let decoded = try decoder.decode(ChatResponse.self, from: data)
                guard let choice = decoded.choices.first else { throw DeepSeekError.emptyResponse }
                switch choice.finishReason {
                case "length":
                    throw DeepSeekError.truncatedResponse
                case "insufficient_system_resource":
                    throw DeepSeekError.temporarilyUnavailable
                case "content_filter":
                    throw DeepSeekError.invalidResponse
                default:
                    break
                }
                guard let content = choice.message.content,
                      !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { throw DeepSeekError.emptyResponse }
                return content
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
                throw CancellationError()
            } catch {
                let normalized = normalize(error)
                lastError = normalized
                let allowedAttempts = maximumAttempts(for: normalized, configured: reliability.maximumAttempts)
                guard attempt < allowedAttempts, isRetryable(normalized) else {
                    throw normalized
                }
                let multiplier = 1 << (attempt - 1)
                let delay = reliability.retryBaseDelayMilliseconds * multiplier
                try await Task.sleep(for: .milliseconds(delay))
            }
        }
        throw lastError
    }

    private func structuredCompletion<T: Decodable>(
        apiKey: String,
        model: AIModelChoice,
        messages: [ChatMessage],
        maxTokens: Int,
        temperature: Double,
        allowsCellularAccess: Bool
    ) async throws -> T {
        var repairMessages = messages
        var lastError: Error = DeepSeekError.invalidJSON
        for formattingAttempt in 1...2 {
            let content = try await completion(
                apiKey: apiKey,
                model: model,
                messages: repairMessages,
                maxTokens: formattingAttempt == 1 ? maxTokens : maxTokens + 300,
                temperature: formattingAttempt == 1 ? temperature : min(temperature, 0.7),
                json: true,
                allowsCellularAccess: allowsCellularAccess
            )
            do {
                return try decode(T.self, from: content)
            } catch {
                lastError = error
                guard formattingAttempt < 2 else { break }
                repairMessages.append(ChatMessage(
                    role: "user",
                    content: "上一份输出不是完整、可解析的 JSON。请重新生成，只返回完整 JSON 对象，不要使用 Markdown 代码块，也不要省略任何必填字段。"
                ))
            }
        }
        throw lastError
    }

    private func normalize(_ error: Error) -> Error {
        guard let urlError = error as? URLError else { return error }
        switch urlError.code {
        case .timedOut:
            return DeepSeekError.timeout
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed:
            return DeepSeekError.networkUnavailable
        default:
            return DeepSeekError.transport
        }
    }

    private func isRetryable(_ error: Error) -> Bool {
        guard let deepSeekError = error as? DeepSeekError else { return false }
        switch deepSeekError {
        case .emptyResponse, .truncatedResponse, .temporarilyUnavailable, .timeout, .networkUnavailable, .transport:
            return true
        case .server(let status, _):
            return [408, 425, 429, 500, 502, 503, 504].contains(status)
        case .missingKey, .invalidResponse, .invalidJSON:
            return false
        }
    }

    private func maximumAttempts(for error: Error, configured: Int) -> Int {
        guard let deepSeekError = error as? DeepSeekError else { return 1 }
        switch deepSeekError {
        case .timeout, .networkUnavailable, .transport:
            return min(2, configured)
        default:
            return configured
        }
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

    private static let kokoSystemPrompt = """
    你是“二次元小家”里的陪伴角色可可。你温柔、自然、有自己当下的偏好，会留意房间、画集、时间和已提供的记忆，但你清楚自己是应用中的虚构角色。你不伪装成现实人类，不声称看到应用未提供的内容，不用占有、内疚、威胁或制造依赖的表达。你懂得安静也是陪伴，回答简洁而有温度。
    """
}

enum DeepSeekError: LocalizedError {
    case missingKey
    case invalidResponse
    case emptyResponse
    case invalidJSON
    case truncatedResponse
    case temporarilyUnavailable
    case timeout
    case networkUnavailable
    case transport
    case server(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .missingKey: return "请先在设置中填写 DeepSeek API 密钥。"
        case .invalidResponse: return "DeepSeek 返回了无法识别的响应。"
        case .emptyResponse: return "AI 这次没有生成内容，请稍后重试。"
        case .invalidJSON: return "AI 返回的内容格式不完整，请重试。"
        case .truncatedResponse: return "AI 内容没有生成完整，已自动重试；请稍后再试。"
        case .temporarilyUnavailable: return "DeepSeek 当前繁忙，已自动重试；请稍后再试。"
        case .timeout: return "AI 响应超时，已切换本地陪伴。"
        case .networkUnavailable: return "当前网络不可用，已切换本地陪伴。"
        case .transport: return "暂时无法连接 DeepSeek，已切换本地陪伴。"
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
    struct Choice: Decodable {
        let message: ResponseMessage
        let finishReason: String?
    }
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
    let translation: TranslationPayload?
}

private struct TranslationPayload: Decodable {
    let detectedJapanese: Bool
    let title: String
    let segments: [TranslationSegmentPayload]
    let note: String?
}

private struct TranslationSegmentPayload: Decodable {
    let source: String
    let translation: String
    let role: String
    let speaker: String?
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

private struct KokoDecisionPayload: Decodable {
    let action: String
    let targetBookID: String?
    let phrase: String
    let innerThought: String
    let duration: Int
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
