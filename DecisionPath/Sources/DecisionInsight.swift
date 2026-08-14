import Foundation

// MARK: - 说什么
//
// 这个产品唯一的资产是它不说假话。所以所有对用户说的「结论」都收在这一个文件里，
// 每一句都写清楚它凭什么成立、样本不够时退到哪一层。
//
// 三层，按「有资格说」的顺序：
//
//   n=1   预期 vs 实际      —— 不需要统计、不涉及因果，一条记录就成立
//   n≥3   同类对比          —— 同一件事你选过不同的边，才有资格比
//   n≥5   校准度            —— 按**总样本**长，所以比同类对比快 7–10 倍到
//
// 够不着的层就不说。宁可只说一句「记下了」，也不要凑一句像洞察的话。

enum DecisionInsight {

    /// 打完分那一刻的两句话：主句必然有，脚注可能没有。
    static func afterRating(_ episode: DecisionEpisode,
                            store: DecisionStore = .shared) -> (headline: String, footnote: String?) {
        (headline(for: episode), comparison(for: episode, store: store) ?? calibration(store: store))
    }

    // MARK: n=1：你以为 X，实际 Y
    //
    // 「预期」这一步存在的唯一理由就是这句话 —— 它让第一条记录就有产出，
    // 而同类对比要等到第三条。

    static func headline(for episode: DecisionEpisode) -> String {
        guard let actual = episode.outcome else { return "记下了。" }
        guard let expected = episode.expectation else {
            return "记下了。你选了「\(episode.chosenTitle ?? "")」，回来说 \(actual) 分。"
        }
        if expected == actual {
            return "你以为 \(expected) 分。实际也是 \(actual) 分。\n这次你挺懂自己的。"
        }
        return "你以为 \(expected) 分。实际 \(actual) 分。\n\(direction(from: expected, to: actual, on: episode.metric))。"
    }

    /// 分数的方向不等于好坏：后悔度 8 分是很后悔，不是「比你以为的好」。
    /// 早先这里写死了「高就是好」，在后悔度上会说出完全相反的话。
    private static func direction(from expected: Int, to actual: Int, on metric: MetricScale) -> String {
        let higher = actual > expected
        if metric.higherIsBetter {
            return higher ? "比你以为的好" : "没有你以为的好"
        }
        return higher ? "比你以为的更难受" : "没有你以为的那么难受"
    }

    // MARK: 认出：同类 1 条就成立
    //
    // 这不是洞察，是记忆 —— 而记忆正是这个产品答应过的东西。
    // 必须**同类**：上次记健身、这次记买东西，说「上次你也在这儿停过」是假话。

    static func recognition(for domain: String, store: DecisionStore = .shared) -> String? {
        guard let recent = store.completed(in: domain).first,
              let title = recent.chosenTitle, let outcome = recent.outcome
        else { return nil }
        return "上次你也在这儿停过。你选了「\(title)」，回来说 \(outcome) 分。"
    }

    // MARK: n≥3：同类对比
    //
    // 门槛是三条，但**够了三条也不一定说得出对比** ——
    // 三次都选了同一边就没有可比的两组，那时候只能陈述，不能比较。

    static func comparison(for episode: DecisionEpisode, store: DecisionStore = .shared) -> String? {
        let domain = episode.domain
        guard domain != "未分类" else { return nil }

        // 包含刚打完分的这一条：它已经是一条完成记录，藏起来反而不诚实。
        var records = store.completed(in: domain, excluding: episode.id)
        if episode.outcome != nil { records.append(episode) }
        guard records.count >= 3 else { return nil }

        let label = "这类事你记过 \(records.count) 次"

        // 按选了什么分组。跨记录的选项是自由文本，只有**字面相同**才敢当成同一个选择 ——
        // 「去健身」和「去撸铁」也许是一回事，但那是猜的。
        var groups: [String: [Int]] = [:]
        for record in records {
            guard let title = record.chosenTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty, let outcome = record.outcome else { continue }
            groups[title, default: []].append(outcome)
        }

        let ranked = groups.sorted { lhs, rhs in
            lhs.value.count != rhs.value.count ? lhs.value.count > rhs.value.count
                                               : mean(lhs.value) > mean(rhs.value)
        }

        // 每次都选同一边：没有对照组，说不出「哪个更好」，但说得出「你从来没试过另一边」。
        guard ranked.count >= 2 else {
            guard let only = ranked.first else { return nil }
            return "\(label)，每次都选了「\(only.key)」，平均 \(format(mean(only.value))) 分。"
        }

        let top = ranked[0], second = ranked[1]
        let gap = mean(top.value) - mean(second.value)

        // 差不到 1 分就不排名次。1–10 的自评里，0.6 分的差距是噪声，
        // 把它说成「A 比 B 好」是拿噪声冒充结论。
        guard abs(gap) >= 1 else {
            return "\(label)。选「\(top.key)」和选「\(second.key)」，回来打的分差不多。"
        }

        // 分高不等于更好：后悔度 8 分是很后悔。
        let better = (gap > 0) == episode.metric.higherIsBetter ? top : second
        let other = better.key == top.key ? second : top
        return """
        \(label)。选「\(better.key)」的 \(better.value.count) 次平均 \(format(mean(better.value))) 分，\
        选「\(other.key)」的 \(other.value.count) 次平均 \(format(mean(other.value))) 分。
        """
    }

    // MARK: n≥5：校准度
    //
    // 它衡量的不是某一类事，是**这个人**猜自己的准头。所以按总样本长 ——
    // 同类要攒 3 条同一个领域的，校准度只要 5 条任意领域的。
    //
    // 措辞刻意不带褒贬：「偏低」是数字事实，「太悲观了」是评价。
    // 而且不同指标的方向不一样（后悔度高是难受），一句带褒贬的话必然在某个指标上说反。

    static func calibration(store: DecisionStore = .shared) -> String? {
        let samples = store.calibrationSamples
        guard samples.count >= 5 else { return nil }

        let errors = samples.map { Double($0.error) }
        let average = errors.reduce(0, +) / Double(errors.count)
        let count = samples.count

        // 平均误差半分以内就是准。再细分下去是在解读舍入噪声。
        if abs(average) < 0.5 {
            return "你留过 \(count) 次预期，实际结果和你猜的基本对得上。"
        }
        // 平均值会被一次离谱的偏差带跑。加一句「几次里有几次」，
        // 让用户看得出这是个稳定的倾向，还是被一次意外拉出来的。
        let direction = average > 0 ? "偏低" : "偏高"
        let sameSide = errors.filter { average > 0 ? $0 > 0 : $0 < 0 }.count
        return "你留过 \(count) 次预期，其中 \(sameSide) 次\(direction)，平均差 \(format(abs(average))) 分。"
    }

    // MARK: 小工具

    private static func mean(_ values: [Int]) -> Double {
        guard !values.isEmpty else { return 0 }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    /// 7.0 写成「7」，7.25 写成「7.3」。小数点后第二位在自评分里没有意义。
    private static func format(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
    }
}
