import Foundation

// MARK: - 本地启发式
//
// 不需要网络、不需要 key、不要钱。云端接上之后它也不会被删掉 ——
// 它是 PRD 19.3 要求的降级路径：云端失败时用户的输入不能丢。
//
// 这里同时是产品知识的落点：领域信号词、默认指标、回访经验值，
// 以及 15 个模板反转出来的 n=0 追问。这些不是「等 AI 来做」的东西，
// 它们是 AI 的先验，本地和云端共用同一套。

struct LocalIntelligence: DecisionIntelligence {

    private struct Domain {
        let name: String
        let signals: [String]
        let metric: MetricScale
        let followUp: FollowUpKind
        /// n=0 追问。模板库里的「洞察示例」是 n=20 的答案，
        /// 把答案改写成问句就是 n=0 的价值 —— 同一份知识，两种用法。
        let question: String
    }

    private enum FollowUpKind {
        case immediate      // 活动结束后 20–60 分钟
        case nextMorning    // 第二天早上
        case days(Int)      // 几天后
        case tonight        // 当天 21:00
    }

    private static let domains: [Domain] = [
        Domain(name: "身体",
               signals: ["健身", "跑步", "运动", "锻炼", "累", "酸痛", "游泳", "瑜伽"],
               metric: .energy, followUp: .immediate,
               question: "不去的那个晚上，你会拿这两小时做什么？"),
        Domain(name: "饮食",
               signals: ["吃", "喝", "外卖", "做饭", "火锅", "点餐", "下馆子", "夜宵"],
               metric: .satisfaction, followUp: .immediate,
               question: "你不想做饭，是不想做，还是不想收拾？"),
        Domain(name: "睡眠",
               signals: ["睡", "熬夜", "早起", "午睡", "困", "起床"],
               metric: .energy, followUp: .nextMorning,
               question: "你现在多要的这一小时，准备从明天哪里扣？"),
        Domain(name: "社交",
               signals: ["聚会", "约", "朋友", "同事", "联系", "饭局", "局", "见面"],
               metric: .connection, followUp: .immediate,
               question: "这次是你想去，还是不好意思不去？"),
        Domain(name: "工作",
               signals: ["会议", "发言", "老板", "任务", "项目", "汇报", "加班", "涨薪", "辞职"],
               metric: .relief, followUp: .tonight,
               question: "哪种后悔你更受不了：说错了，还是没说？"),
        Domain(name: "消费",
               signals: ["买", "下单", "花钱", "值得", "贵", "剁手", "退", "省"],
               metric: .regret, followUp: .days(3),
               question: "如果三天后它还在你脑子里，你会更想买，还是更不想？"),
        Domain(name: "时间",
               signals: ["周末", "假期", "安排", "计划", "宅", "出去玩", "旅行"],
               metric: .satisfaction, followUp: .nextMorning,
               question: "周一早上回头看，什么样的周末会让你觉得没白过？"),
        Domain(name: "关系",
               signals: ["女朋友", "男朋友", "伴侣", "表白", "吵架", "结婚", "分手", "老家", "爸妈"],
               metric: .relief, followUp: .tonight,
               question: "你在担心的那个画面，具体是什么样子？"),
        Domain(name: "家务",
               signals: ["洗碗", "整理", "打扫", "搬家", "收拾", "洗衣"],
               metric: .clarity, followUp: .tonight,
               question: "「攒着一起做」的那个时间，你能说出是什么时候吗？")
    ]

    /// 兜底追问：想要 vs 应该。
    /// 这是绝大多数纠结的真实结构 —— 想进步，但又觉得躺着更舒服。
    private static let fallbackQuestion = "你更想要哪个？和你觉得该选哪个，是同一个吗？"

    func understand(_ text: String, history: [DecisionEpisode]) async throws -> DecisionUnderstanding {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return .notADecision() }

        let domain = Self.domains.first { domain in
            domain.signals.contains { input.contains($0) }
        }

        guard let options = Self.extractOptions(from: input) else {
            // 抽不出对立面就不硬编造。宁可让用户手填，也不把猜测伪装成确定结果。
            return .notADecision()
        }

        return DecisionUnderstanding(
            isDecision: true,
            optionA: options.0,
            optionB: options.1,
            metric: domain?.metric ?? .satisfaction,
            followUpDelay: Self.delay(for: domain?.followUp ?? .tonight),
            question: domain?.question ?? Self.fallbackQuestion,
            domain: domain?.name ?? "未分类",
            confidence: domain == nil ? 0.45 : 0.7
        )
    }

    // MARK: 选项抽取

    private static func extractOptions(from text: String) -> (String, String)? {
        if let range = text.range(of: "还是") {
            let left = String(text[..<range.lowerBound]).decisionFragment
            let right = String(text[range.upperBound...]).decisionFragment
            if !left.isEmpty, !right.isEmpty { return (left, right) }
        }

        for marker in ["要不要", "该不该", "用不用", "值不值得"] {
            if text.contains(marker) {
                let action = text.replacingOccurrences(of: marker, with: "").decisionFragment
                if !action.isEmpty { return (action, "再等等") }
            }
        }

        // 「去不去」「买不买」这类 V不V 结构
        if let verb = vNotV(in: text) {
            return (verb, "不\(verb)")
        }

        return nil
    }

    private static func vNotV(in text: String) -> String? {
        let characters = Array(text)
        for index in 1..<max(characters.count - 1, 1) where characters[index] == "不" {
            let before = characters[index - 1]
            let after = characters[index + 1]
            if before == after { return String(before) }
        }
        return nil
    }

    // MARK: 回访时间

    private static func delay(for kind: FollowUpKind) -> TimeInterval {
        let calendar = Calendar.current
        let now = Date()
        switch kind {
        case .immediate:
            return 40 * 60
        case .nextMorning:
            let target = calendar.date(bySettingHour: 8, minute: 30, second: 0,
                                       of: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
            return max(target?.timeIntervalSince(now) ?? 57_600, 3600)
        case let .days(count):
            let target = calendar.date(byAdding: .day, value: count, to: now)
            return target?.timeIntervalSince(now) ?? Double(count) * 86_400
        case .tonight:
            // 当天 21:00；已经过了就顺延到明天同一时刻。
            var target = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: now)
            if let candidate = target, candidate.timeIntervalSince(now) < 1800 {
                target = calendar.date(byAdding: .day, value: 1, to: candidate)
            }
            return max(target?.timeIntervalSince(now) ?? 7200, 1800)
        }
    }
}

private extension String {
    var decisionFragment: String {
        var value = trimmingCharacters(in: CharacterSet(charactersIn: " ，。！？?,.\n"))
        for noise in ["我", "今晚", "今天", "现在", "到底", "究竟"] where value.hasPrefix(noise) {
            value.removeFirst(noise.count)
        }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: " ，。！？?,."))
    }
}
