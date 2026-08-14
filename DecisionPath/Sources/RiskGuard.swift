import Foundation

// MARK: - 高风险输入的硬边界
//
// prompt 里已经写了「医疗法律财务只做结构化，不给建议」。但 prompt 是**请求**，不是**边界** ——
// 换个服务商、换个模型、用户自己填了别家的 key，那句叮嘱就可能不生效，
// 而这类失败是安静的：界面一切正常，只是某一天它开始劝人停药。
//
// 所以边界放在客户端：不管哪个大脑产出的结果，都要经过这里。
// 这里做三件事，都不依赖模型：
//   1. 危机输入不进决策结构，也**不发给云端**；
//   2. 专业领域的输入照常结构化，但追问要过一遍净化，并挂一句边界说明；
//   3. 任何领域的追问，只要在给建议，就换成不给建议的那句。

enum RiskTier {
    case none
    /// 医疗 / 法律 / 财务。照常帮他摆选项，但不评判、不建议。
    case professional
    /// 自伤、轻生。这不是一个「可以比较的选择」，不该被做成两个路标。
    case crisis
}

enum RiskGuard {

    // MARK: 危机
    //
    // 这份词表刻意只收**明确**的说法。漏判的代价是少说一句话，
    // 误判的代价是把「累得要死」的人推到一个危机页面上 —— 后者更伤。
    // 中文里「想死」「烦死了」是日常修辞，所以不在表里。

    private static let crisisSignals = [
        "自杀", "轻生", "自残", "割腕", "跳楼",
        "不想活", "活不下去", "不想活了", "结束生命", "结束自己", "了结自己",
        "没意思活着", "活着没意义", "消失掉算了",
        // 输入框是自由文本，英文也进得来（模型本来就吃得下）。
        // 同样只收明确说法 —— 英文里 "I want to die" 和中文「想死」一样是日常修辞。
        "kill myself", "killing myself", "end my life", "suicide",
        "self-harm", "self harm", "cut myself"
    ]

    /// 危机时说的话。不劝、不分析、不追问，只给一个此刻能立刻说上话的地方。
    static let crisisResponse = """
    这件事比一个选择更重要。
    我只是一个记录纠结的小工具，帮不了你现在正在扛的东西。

    如果你此刻很难受，找个能马上说上话的人：
    全国心理援助热线 12356，24 小时。
    """

    // MARK: 专业领域

    private static let professionalSignals = [
        // 医疗
        "吃药", "停药", "换药", "剂量", "手术", "化疗", "放疗", "抗生素", "激素",
        "打针", "疫苗", "住院", "就医", "看病", "挂号", "复查", "确诊", "病理",
        "抑郁症", "焦虑症", "精神科", "偏方", "保健品",
        // 法律
        "起诉", "诉讼", "打官司", "律师", "仲裁", "报警", "赔偿", "工伤",
        "合同", "违约", "签字", "离婚", "遗嘱", "取保", "拘留",
        // 财务
        "投资", "炒股", "股票", "基金", "杠杆", "期货", "加仓", "抄底",
        "贷款", "房贷", "网贷", "借钱", "理财", "保险", "首付", "全款",
        "比特币", "虚拟货币", "数字货币", "还债"
    ]

    /// 专业领域挂的那一句。说的是「我不做什么」，不是「你该找谁」——
    /// 后者又变成一条建议了。
    static let professionalNote = "这类事我只帮你把选项摆出来，不替你判断。"

    static func tier(for text: String) -> RiskTier {
        let text = text.lowercased()
        if crisisSignals.contains(where: text.contains) { return .crisis }
        if professionalSignals.contains(where: text.contains) { return .professional }
        return .none
    }

    // MARK: 追问净化
    //
    // 追问的定义是「只问，不建议」。这条规矩在 prompt 里写了，在这里执行。

    private static let advicePatterns = [
        "你应该", "你就应该", "建议你", "我建议", "的建议", "推荐你", "我推荐",
        "最好是", "最好还是", "不如就", "还是选", "显然", "当然要", "肯定要",
        "必须选", "别犹豫", "果断"
    ]

    /// 兜底追问。它本身不含建议，所以永远可以拿来顶替被拦下的那一句。
    private static let neutralQuestion = "你更想要哪个？和你觉得该选哪个，是同一个吗？"

    /// 专业领域的兜底追问。同样只问不建议，但把落点放在
    /// 「你自己能判断的那部分」上 —— 承受力和信息缺口，这两个只有他自己知道。
    private static let professionalQuestion = "两个结果里，哪一个是你更承受不起的？"

    static func sanitizedQuestion(_ question: String?, tier: RiskTier) -> String? {
        let fallback = tier == .professional ? professionalQuestion : neutralQuestion
        guard let question = question?.trimmingCharacters(in: .whitespacesAndNewlines),
              !question.isEmpty
        else { return fallback }
        // 一句「你应该早点睡」和一句真追问，长得很像，判不出来就换掉。
        // 换掉的成本是一句稍微通用一点的话，留下的成本是这个产品在给医疗建议。
        return advicePatterns.contains(where: question.contains) ? fallback : question
    }

    /// 所有理解结果的必经之路 —— 云端的、本地的、以后可能有的任何一种。
    static func apply(to understanding: DecisionUnderstanding, input: String) -> DecisionUnderstanding {
        let tier = tier(for: input)
        guard tier != .crisis else { return .notADecision() }
        var guarded = understanding
        guarded.question = sanitizedQuestion(understanding.question, tier: tier)
        return guarded
    }
}
