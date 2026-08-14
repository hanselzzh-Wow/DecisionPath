import Foundation

// MARK: - 记录
//
// 一次决策实验的完整生命：说出纠结 → 选择 → 等待 → 回访打分 → 完成。
//
// 状态是**推导**出来的，不是存下来的。存状态迟早会和数据打架 ——
// 比如改了回访时间却忘了改状态。推导则永远自洽。

enum ChosenOption: String, Codable {
    case a
    case b
}

enum EpisodeState {
    case awaitingChoice     // 待选择
    case awaitingOutcome    // 已选择，等回访时间到
    case awaitingRating     // 回访时间到了，等用户记录感受
    case complete           // 有选择也有结果
}

/// 观察指标的场景化刻度。数据里存 1–10，给用户看的永远是这三个词。
struct MetricScale: Codable, Equatable {
    let name: String
    let low: String
    let mid: String
    let high: String

    static let energy = MetricScale(name: "精力", low: "虚脱", mid: "正常", high: "满电")
    static let satisfaction = MetricScale(name: "满足感", low: "不太满意", mid: "还行", high: "非常满意")
    static let regret = MetricScale(name: "后悔度", low: "完全不后悔", mid: "有点", high: "非常后悔")
    static let efficiency = MetricScale(name: "效率感", low: "低效", mid: "一般", high: "高效")
    static let body = MetricScale(name: "身体感受", low: "不舒服", mid: "无感", high: "很舒服")
    static let connection = MetricScale(name: "连接深度", low: "完全浪费", mid: "还好", high: "走得更近")
    static let clarity = MetricScale(name: "心理清爽度", low: "心里很乱", mid: "还行", high: "神清气爽")
    static let relief = MetricScale(name: "说完后的感受", low: "后悔", mid: "说不清", high: "松口气")

    /// 分数的方向不等于好坏：后悔度 8 分是很后悔。
    /// 洞察里凡是要说「好 / 不好」的地方都得先问这一句，否则会在后悔度上说反。
    ///
    /// 用名字判，不加存储字段 —— `MetricScale` 已经躺在用户的 `decisions.json` 里了，
    /// 加一个非可选字段会让老数据整个解不出来，而那种失败是静默的（`try?` → 空数组）。
    var higherIsBetter: Bool { name != MetricScale.regret.name }
}

struct DecisionEpisode: Codable, Identifiable {
    let id: UUID
    let rawInput: String
    let createdAt: Date

    /// 内部分类。用户永远看不到它，但同类对比和洞察全靠它。
    var domain: String
    var optionA: String
    var optionB: String
    var metric: MetricScale
    /// n=0 追问。没有历史时它就是产品的全部价值，所以是一等公民。
    var question: String?
    var followUpAt: Date

    var chosen: ChosenOption?
    var chosenAt: Date?
    /// 选择时顺手留下的预期（1–10）。可为空 —— 直接点选就是不留。
    var expectation: Int?

    var outcome: Int?
    var outcomeNote: String?
    var ratedAt: Date?

    init(rawInput: String,
         understanding: DecisionUnderstanding,
         now: Date = Date()) {
        self.id = UUID()
        self.rawInput = rawInput
        self.createdAt = now
        self.domain = understanding.domain
        self.optionA = understanding.optionA
        self.optionB = understanding.optionB
        self.metric = understanding.metric
        self.question = understanding.question
        self.followUpAt = now.addingTimeInterval(understanding.followUpDelay)
    }

    var state: EpisodeState {
        if chosen == nil { return .awaitingChoice }
        if outcome != nil { return .complete }
        return Date() >= followUpAt ? .awaitingRating : .awaitingOutcome
    }

    var chosenTitle: String? {
        switch chosen {
        case .a: return optionA
        case .b: return optionB
        case nil: return nil
        }
    }

    var unchosenTitle: String? {
        switch chosen {
        case .a: return optionB
        case .b: return optionA
        case nil: return nil
        }
    }
}

// MARK: - 存储

/// MVP 用一个 JSON 文件。几十上百条记录完全够用，而且可以直接打开看 ——
/// 等数据量或查询复杂度真的上来了再换，那时候需求也清楚了。
final class DecisionStore {

    static let shared = DecisionStore()

    private(set) var episodes: [DecisionEpisode] = []
    private let url: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("decisions.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        episodes = (try? decoder.decode([DecisionEpisode].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(episodes).write(to: url, options: .atomic)
    }

    func add(_ episode: DecisionEpisode) {
        episodes.append(episode)
        save()
    }

    func update(_ episode: DecisionEpisode) {
        guard let index = episodes.firstIndex(where: { $0.id == episode.id }) else { return }
        episodes[index] = episode
        save()
    }

    // MARK: 查询

    /// 到点该回访的。回访完成率是整个产品的单点故障，所以这个查询是热路径。
    var due: [DecisionEpisode] {
        episodes.filter { if case .awaitingRating = $0.state { return true } else { return false } }
            .sorted { $0.followUpAt < $1.followUpAt }
    }

    /// 已经理解出选项、但还没做选择的。
    /// PRD 20 要求「输入先本地暂存」—— 说出口的纠结不能因为退出 App 就没了。
    var unresolved: [DecisionEpisode] {
        episodes.filter { if case .awaitingChoice = $0.state { return true } else { return false } }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var pending: [DecisionEpisode] {
        episodes.filter { if case .awaitingOutcome = $0.state { return true } else { return false } }
    }

    /// 同类且已完成的记录，最近的在前。
    /// 「认出」只需要 1 条，「对比」才需要 3 条 —— 门槛不一样，见 PRD v0.2。
    func completed(in domain: String, excluding id: UUID? = nil) -> [DecisionEpisode] {
        episodes.filter {
            $0.domain == domain && $0.outcome != nil && $0.id != id
        }.sorted { ($0.ratedAt ?? $0.createdAt) > ($1.ratedAt ?? $1.createdAt) }
    }

    /// 预期与实际的偏差，用来长出「校准度」。
    /// 它按**总样本**增长，不按同类样本，所以比同类对比快 7–10 倍出结果。
    var calibrationSamples: [(domain: String, error: Int)] {
        episodes.compactMap { episode in
            guard let expected = episode.expectation, let actual = episode.outcome else { return nil }
            return (episode.domain, actual - expected)
        }
    }

    /// 调试用：把所有等待中的记录的回访时间拉到现在。
    /// 回访本来是几小时到几天之后，不这样根本没法测闭环。
    func fastForwardAllFollowUps() {
        for index in episodes.indices where episodes[index].outcome == nil {
            episodes[index].followUpAt = Date().addingTimeInterval(-1)
        }
        save()
    }
}
