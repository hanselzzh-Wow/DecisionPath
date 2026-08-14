import Foundation

// MARK: - AI 的输出
//
// 不管是本地启发式还是云端模型，都产出这一个结构。
// 所以闭环从来不依赖网络 —— 云端只是把同一件事做得更好。

struct DecisionUnderstanding {
    /// 输入是不是一个「可以比较的选择」。不是的话温和回应，不硬编造选项。
    var isDecision: Bool
    var optionA: String
    var optionB: String
    var metric: MetricScale
    var followUpDelay: TimeInterval
    /// n=0 追问：不需要任何历史就成立的那一句。
    var question: String?
    var domain: String
    /// 低置信度时界面应该更明显地允许修改，而不是把猜测伪装成确定结果。
    var confidence: Double

    static func notADecision() -> DecisionUnderstanding {
        DecisionUnderstanding(isDecision: false,
                              optionA: "", optionB: "",
                              metric: .satisfaction,
                              followUpDelay: 3600,
                              question: nil,
                              domain: "未分类",
                              confidence: 0)
    }
}

protocol DecisionIntelligence {
    /// `history` 给了之后可以做「有历史追问」；没有历史时只能做 n=0 追问。
    func understand(_ text: String, history: [DecisionEpisode]) async throws -> DecisionUnderstanding
}

// MARK: - 领域白名单
//
// 模型再怎么被叮嘱也会自由发挥出「运动」「健康」这类近义词。
// 一旦漂了，同类对比和「认出」就永远匹配不上 —— 这种失败还很安静，
// 表面一切正常，只是洞察永远长不出来。所以在代码里收口，不指望模型自律。

enum DecisionDomain {

    static let canonical = ["身体", "饮食", "睡眠", "社交", "工作", "消费", "时间", "关系", "家务"]

    private static let synonyms: [String: String] = [
        "运动": "身体", "健身": "身体", "锻炼": "身体", "健康": "身体",
        "吃饭": "饮食", "餐饮": "饮食", "饮食习惯": "饮食",
        "睡觉": "睡眠", "作息": "睡眠", "休息": "睡眠",
        "人际": "社交", "朋友": "社交", "社交活动": "社交",
        "职场": "工作", "事业": "工作", "学习": "工作",
        "购物": "消费", "花钱": "消费", "财务": "消费",
        "日程": "时间", "安排": "时间", "计划": "时间", "娱乐": "时间",
        "感情": "关系", "亲密关系": "关系", "家庭": "关系",
        "家事": "家务", "杂事": "家务"
    ]

    static func normalize(_ raw: String?) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return "未分类"
        }
        if canonical.contains(raw) { return raw }
        if let mapped = synonyms[raw] { return mapped }
        // 再兜一层：模型有时会写「身体决策」「消费类」这种。
        if let hit = canonical.first(where: { raw.contains($0) }) { return hit }
        return "未分类"
    }
}

// MARK: - 指标表
//
// 模型只能从这些 key 里选，不能自由发挥 —— 指标必须可聚合，
// 否则同类对比永远长不出来。

enum MetricCatalog {
    static let all: [String: MetricScale] = [
        "energy": .energy,
        "satisfaction": .satisfaction,
        "regret": .regret,
        "efficiency": .efficiency,
        "body": .body,
        "connection": .connection,
        "clarity": .clarity,
        "relief": .relief
    ]

    static func scale(for key: String) -> MetricScale {
        all[key] ?? .satisfaction
    }
}

// MARK: - 云端配置
//
// 国内服务商（DeepSeek / 通义 / 豆包 / Kimi / 智谱）基本都提供 OpenAI 兼容的
// chat completions 接口，所以一个客户端全都能用，换家只是换 baseURL 和模型名。

struct IntelligenceConfig {
    var baseURL: URL
    var model: String
    var apiKey: String

    /// 常见服务商的接入点。填哪家都行，接口形状一样。
    static let presets: [String: (base: String, model: String)] = [
        "deepseek": ("https://api.deepseek.com/v1", "deepseek-chat"),
        "qwen": ("https://dashscope.aliyuncs.com/compatible-mode/v1", "qwen-plus"),
        "moonshot": ("https://api.moonshot.cn/v1", "moonshot-v1-8k"),
        "zhipu": ("https://open.bigmodel.cn/api/paas/v4", "glm-4-plus"),
        "doubao": ("https://ark.cn-beijing.volces.com/api/v3", "")
    ]

    /// 从 UserDefaults 读。**不要把 key 提交进仓库** ——
    /// MVP 阶段在设置里填一次即可，正式版应该走自己的服务端中转。
    static func current() -> IntelligenceConfig? {
        let defaults = UserDefaults.standard
        guard let key = defaults.string(forKey: "ai.apiKey"), !key.isEmpty else { return nil }
        let provider = defaults.string(forKey: "ai.provider") ?? "deepseek"
        let preset = presets[provider] ?? presets["deepseek"]!
        let base = defaults.string(forKey: "ai.baseURL") ?? preset.base
        let model = defaults.string(forKey: "ai.model") ?? preset.model
        guard let url = URL(string: base + "/chat/completions") else { return nil }
        return IntelligenceConfig(baseURL: url, model: model, apiKey: key)
    }

    static func store(provider: String, apiKey: String, model: String? = nil) {
        let defaults = UserDefaults.standard
        defaults.set(provider, forKey: "ai.provider")
        defaults.set(apiKey, forKey: "ai.apiKey")
        if let model { defaults.set(model, forKey: "ai.model") }
    }
}

// MARK: - 云端实现

enum IntelligenceError: Error {
    case notConfigured
    case badResponse
}

struct CloudIntelligence: DecisionIntelligence {

    let config: IntelligenceConfig

    /// 不开 json 模式时模型常会用 ```json 把结果包起来。
    private static func stripCodeFence(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("```") else { return text }
        text = text.replacingOccurrences(of: "```json", with: "")
                   .replacingOccurrences(of: "```", with: "")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let systemPrompt = """
    你在帮一个叫「未选择的路」的 App 理解用户此刻的纠结。

    规则：
    1. 先判断这是不是一个可以比较的选择。像「今天天气真好」「帮我写周报」这种不是，
       isDecision 填 false，其余字段留空。
    2. 抽出两个互斥、具体、可执行的选项。每个不超过 8 个字，用户能一眼分清。
       没有显式对立面时可以推断隐含选项，但置信度要如实下调，不要把猜测说成确定。
    3. 从这些 key 里选一个主指标（只能选一个）：
       energy 精力 / satisfaction 满足感 / regret 后悔度 / efficiency 效率感 /
       body 身体感受 / connection 连接深度 / clarity 心理清爽度 / relief 说完后的感受
    4. 估一个回访延迟（秒）。**按事情本身多久能看到结果来定，不是按它有多重要**：
       - 运动、吃饭、午睡、开会发言、见面 → 事情结束后就知道感受了，2400（40分钟）
       - 熬夜/早睡、周末怎么过 → 要到第二天才知道，57600
       - 买东西、联系旧人 → 要等冲动退去，259200（3天）
       - 说不准的 → 当天晚上，21600
       用户说了「今晚/明天/周末/下周」就以那个为锚点。
       常见错误：把「今晚去不去健身」排到第二天 —— 运动完当场就知道了，别等。
    5. 写一句追问。这是最重要的一条：
       - 只问，不建议。绝对不能出现「你应该」「建议你」。
       - 不需要任何历史就成立：让模糊的那一边变具体、或者问「想要」和「应该」是不是同一个、
         或者问哪一种后悔更受不了。
       - 一句话，不超过 30 个字，口语，像一个记得你说过什么的朋友。
    6. domain **只能**是这九个词之一，不要自己造词：
       身体 饮食 睡眠 社交 工作 消费 时间 关系 家务
       它是内部分类，用户看不到，但同类对比全靠它对齐。
    7. 医疗、法律、财务这类高风险输入：只做选择结构化，追问里不给任何专业建议。

    只输出 JSON，不要解释：
    {"isDecision":true,"optionA":"","optionB":"","metric":"energy",
     "followUpDelay":3600,"question":"","domain":"","confidence":0.8}
    """

    private func send(user: String, jsonMode: Bool) async throws -> Data {
        var body: [String: Any] = [
            "model": config.model,
            "temperature": 0.4,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": user]
            ]
        ]
        if jsonMode { body["response_format"] = ["type": "json_object"] }

        var request = URLRequest(url: config.baseURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw IntelligenceError.badResponse
        }
        return data
    }

    func understand(_ text: String, history: [DecisionEpisode]) async throws -> DecisionUnderstanding {
        var user = "用户说：\(text)"
        if !history.isEmpty {
            // 有历史时把最近几条同类喂进去，追问就能从「通用问题」升级成「照回他自己」。
            let lines = history.prefix(3).map { episode -> String in
                let outcome = episode.outcome.map { "\($0)分" } ?? "还没回访"
                return "・\(episode.rawInput) → 选了「\(episode.chosenTitle ?? "?")」，\(outcome)"
            }
            user += "\n\n他过去类似的选择：\n" + lines.joined(separator: "\n")
        }

        // 有些服务商（通义的部分模型）不认 response_format，会直接 400。
        // 那种情况下退一步、只靠 prompt 约束，比整条链路失败强。
        var data: Data
        do {
            data = try await send(user: user, jsonMode: true)
        } catch {
            data = try await send(user: user, jsonMode: false)
        }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String,
            let payload = try JSONSerialization.jsonObject(
                with: Data(Self.stripCodeFence(content).utf8)) as? [String: Any]
        else { throw IntelligenceError.badResponse }

        guard (payload["isDecision"] as? Bool) ?? false else { return .notADecision() }

        let optionA = (payload["optionA"] as? String) ?? ""
        let optionB = (payload["optionB"] as? String) ?? ""
        guard !optionA.isEmpty, !optionB.isEmpty else { return .notADecision() }

        // 夹逼到有意义的区间。太短用户还没做完，太长他已经忘了当时在纠结什么。
        let rawDelay = (payload["followUpDelay"] as? Double) ?? 3600
        let delay = min(max(rawDelay, 900), 7 * 86_400)

        return DecisionUnderstanding(
            isDecision: true,
            optionA: optionA,
            optionB: optionB,
            metric: MetricCatalog.scale(for: (payload["metric"] as? String) ?? "satisfaction"),
            followUpDelay: delay,
            question: (payload["question"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            domain: DecisionDomain.normalize(payload["domain"] as? String),
            confidence: (payload["confidence"] as? Double) ?? 0.6
        )
    }
}

// MARK: - 路由
//
// 云端没配或者失败时静默落回本地。用户的输入永远不会因为网络而丢 —— PRD 19.3。
//
// 这里也是**唯一**的出口，所以高风险边界挂在这一层：不管理解是哪个大脑产出的，
// 都要过一遍 `RiskGuard`。挂在调用方就会漏 —— 以后多一个入口就多一个缺口。

struct DecisionIntelligenceRouter: DecisionIntelligence {

    let local: DecisionIntelligence = LocalIntelligence()

    func understand(_ text: String, history: [DecisionEpisode]) async throws -> DecisionUnderstanding {
        // 危机输入连发都不发。云端不需要看到它，本地也不该把它拆成两个路标。
        guard RiskGuard.tier(for: text) != .crisis else { return .notADecision() }

        if let config = IntelligenceConfig.current() {
            do {
                let understanding = try await CloudIntelligence(config: config)
                    .understand(text, history: history)
                return RiskGuard.apply(to: understanding, input: text)
            } catch {
                // 不向用户报错。他此刻在纠结，不该被一个网络问题打断。
            }
        }
        return RiskGuard.apply(to: try await local.understand(text, history: history), input: text)
    }
}
