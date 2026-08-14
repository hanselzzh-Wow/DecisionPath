import UIKit

/// 完整闭环：说出纠结 → AI 理解 → 选择（可留预期）→ 等待 → 回访打分 → 洞察。
///
/// 一条纪律贯穿全程：**回访优先于新记录**。
/// 回访完成率是这个产品的单点故障 —— 没有结果的选择等于没有产品，
/// 所以只要有到点的回访，一进来就先问那件事。
final class RootViewController: UIViewController, UITextFieldDelegate {

    private enum Stage {
        case input          // 你在纠结什么
        case choosing       // 两条路 + 追问
        case expecting      // 选完了，可留一个预期
        case rating         // 回访：现在感觉怎么样
        case reflecting     // 你以为 X，实际 Y
    }

    private let roadScene = RoadSceneView()
    /// 文字区背后的一层纸色渐隐。
    ///
    /// 深色的楼压在白底黑字后面根本读不清，但加一块实心面板会立刻变成
    /// 一个 UI 控件、把「一个连续世界」打碎。渐隐读起来像晨雾，是世界的一部分。
    private let textHaze = GradientView()
    /// 底部那一层同样的雾。
    ///
    /// 世界里有建筑之后，下半屏不再是空纸：树和房子会从控件后面掠过，
    /// 刻度上的「虚脱 / 满电」压在树冠上就读不出来了。
    /// 和顶部同一个理由、同一个做法 —— 加实心面板会立刻把世界切成两半。
    private let controlHaze = GradientView()
    private let wordmarkLabel = UILabel()
    private let promptLabel = UILabel()
    private let questionLabel = UILabel()
    private let inputField = UITextField()
    private let inputHairline = UIView()
    private let continueButton = UIButton(type: .system)
    private let leftChoice = PathChoiceControl()
    private let rightChoice = PathChoiceControl()
    private let pushHintLabel = UILabel()
    private let expectationRail = ExpectationRailView()
    private let scaleControl = OutcomeScaleControl()
    private let skipButton = UIButton(type: .system)
    private let nextJunctionButton = UIButton(type: .system)
    private let footnoteLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    private let intelligence: DecisionIntelligence = DecisionIntelligenceRouter()
    private let store = DecisionStore.shared

    private var stage: Stage = .input
    private var draft: DecisionEpisode?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.canvasBottom
        configureViews()
        configureLayout()
        configureActions()
        NotificationCenter.default.addObserver(
            self, selector: #selector(followUpTapped),
            name: FollowUpScheduler.didTapFollowUp, object: nil)
        // 从后台回来也要看一眼有没有到点的回访。
        // 只靠 viewDidAppear 是不够的：从后台切回前台根本不走那个回调，
        // 于是「通知都弹过了，进来还停在输入框」—— 而回访完成率是这个产品的单点故障。
        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationBecameActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationWillResignActive),
            name: UIApplication.willResignActiveNotification, object: nil)
        resume()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if stage == .input { resume() }
    }

    /// 不打断正在进行的事：只有停在输入框或者刚看完一句洞察时才切过去。
    @objc private func applicationBecameActive() {
        roadScene.resumeWorld()
        guard stage == .input || stage == .reflecting else { return }
        guard !store.due.isEmpty else { return }
        resume()
    }

    /// 切后台就把世界停住。视频在后台既画不出来也没人看，白烧电。
    @objc private func applicationWillResignActive() {
        roadScene.pauseWorld()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    // MARK: 入口：先回访，再新记录

    private func resume() {
        roadScene.setPendingCount(store.pending.count)
        if let episode = store.due.first {
            enterRating(for: episode)
        } else if let unfinished = store.unresolved.first {
            // 说到一半就退出去的那件事，回来还在。
            draft = unfinished
            enterChoosing(unfinished)
        } else {
            enterInput()
        }
    }

    // MARK: 阶段：输入

    private func enterInput() {
        stage = .input
        draft = nil
        promptLabel.text = "你在纠结什么？"
        questionLabel.text = ""
        footnoteLabel.text = ""
        inputField.text = ""
        roadScene.reset()
        apply(visible: [promptLabel, inputField, inputHairline, continueButton],
              hidden: [leftChoice, rightChoice, pushHintLabel, scaleControl,
                       skipButton, nextJunctionButton, footnoteLabel])
        questionLabel.isHidden = questionLabel.text?.isEmpty ?? true
        questionLabel.alpha = questionLabel.isHidden ? 0 : 1
    }

    @objc private func inputBegan() {
        guard stage == .input,
              !(inputField.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        else { return }
        // 只叉一次：`revealFork` 自己是幂等的，这里不用记状态。
        roadScene.revealFork()
    }

    @objc private func submitDecision() {
        let text = inputField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            inputField.becomeFirstResponder()
            flashHairline()
            return
        }
        view.endEditing(true)

        // 危机输入在这里就停住：不存、不问、不发给云端。
        // 把「要不要活下去」摆成两个路标是这个产品能犯的最严重的错误，
        // 而且它离得很近 —— 输入框是自由文本，什么都可能被说进来。
        if RiskGuard.tier(for: text) == .crisis {
            enterCrisis()
            return
        }

        spinner.startAnimating()
        continueButton.isEnabled = false

        Task { @MainActor in
            let history = store.episodes.filter { $0.outcome != nil }
            let understanding = (try? await intelligence.understand(text, history: history))
                ?? .notADecision()
            spinner.stopAnimating()
            continueButton.isEnabled = true

            guard understanding.isDecision else {
                // 不硬编造选项。PRD 9.2 的原话就是这句。
                promptLabel.text = "这看起来不像一个纠结的选择。\n试试说说你在比较的两个选项？"
                return
            }
            let episode = DecisionEpisode(rawInput: text, understanding: understanding)
            // 先存再说。用户已经把话说出口了，从这一刻起它就不该因为
            // 退出 App、切后台、网络断掉而消失 —— PRD 22 的验收标准。
            store.add(episode)
            draft = episode
            enterChoosing(episode)
        }
    }

    /// 危机输入：不做成选择，也不留在路上。
    /// 这里刻意没有「继续记录」的按钮 —— 页面停在这句话上，直到他自己开口说别的。
    private func enterCrisis() {
        stage = .reflecting
        draft = nil
        promptLabel.text = RiskGuard.crisisResponse
        questionLabel.text = ""
        footnoteLabel.text = ""
        roadScene.reset()
        nextJunctionButton.setTitle("说点别的", for: .normal)
        apply(visible: [promptLabel, nextJunctionButton],
              hidden: [inputField, inputHairline, continueButton, leftChoice,
                       rightChoice, pushHintLabel, scaleControl, skipButton, footnoteLabel])
    }

    // MARK: 阶段：选择

    private func enterChoosing(_ episode: DecisionEpisode) {
        stage = .choosing
        promptLabel.text = episode.rawInput
        // 追问和两条路同时出现，它不是必答的一步 —— 用户可以直接越过它。
        //
        // 有同类历史时用记忆顶掉追问：「上次你也在这儿停过」比任何通用问题都强。
        // 所以追问的频率随历史增长自动下降，不需要单独设计退出。
        questionLabel.text = DecisionInsight.recognition(for: episode.domain, store: store)
            ?? episode.question
        // 医疗/法律/财务：照常帮他摆选项，但把边界说在前面。
        let note = RiskGuard.tier(for: episode.rawInput) == .professional
            ? RiskGuard.professionalNote : nil
        footnoteLabel.text = note ?? ""
        leftChoice.title = episode.optionA
        rightChoice.title = episode.optionB
        expectationRail.scale = episode.metric
        roadScene.revealFork()
        skipButton.setTitle("都不对，我自己写", for: .normal)
        apply(visible: [promptLabel, questionLabel, leftChoice, rightChoice,
                        pushHintLabel, skipButton] + (note == nil ? [] : [footnoteLabel]),
              hidden: [inputField, inputHairline, continueButton, scaleControl,
                       nextJunctionButton] + (note == nil ? [footnoteLabel] : []))
    }

    /// PRD 9.6：抽取错了要能进完全手动模式，而且「错误后不再连续猜测」——
    /// 改完就用改完的，不再拿去让模型重猜一遍。
    ///
    /// 用 alert 是权宜：它会把「一个连续世界」打断一下。等美化阶段
    /// 要把它做成路标本身可以就地改写。
    private func presentManualEdit() {
        guard var episode = draft else { return }
        let alert = UIAlertController(title: "你在比较的是哪两个？",
                                      message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = episode.optionA
            field.placeholder = "第一条路"
        }
        alert.addTextField { field in
            field.text = episode.optionB
            field.placeholder = "另一条路"
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "就这样", style: .default) { [weak self] _ in
            guard let self else { return }
            let a = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let b = alert.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !a.isEmpty, !b.isEmpty else { return }
            episode.optionA = a
            episode.optionB = b
            self.draft = episode
            self.store.update(episode)
            self.enterChoosing(episode)
        })
        present(alert, animated: true)
    }

    @objc private func choseLeft() { choose(.a, left: true) }
    @objc private func choseRight() { choose(.b, left: false) }

    private func choose(_ option: ChosenOption, left: Bool, expectation: Int? = nil) {
        guard stage == .choosing, var episode = draft else { return }
        episode.chosen = option
        let now = Date()
        episode.chosenAt = now
        // 回访时间从**做出选择**的那一刻重算，不是从说出纠结的那一刻。
        // 中间可能隔了一整天 —— 那样排出来的回访会毫无意义。
        episode.followUpAt = now.addingTimeInterval(episode.followUpAt.timeIntervalSince(episode.createdAt))
        episode.expectation = expectation
        draft = episode
        store.update(episode)
        roadScene.choose(left: left)

        // 上推的时候预期已经留下了，就不用再问一遍。
        // 轻点的人还是走那一步 —— 没有它，n=1 的洞察就长不出来。
        if expectation == nil {
            enterExpecting(episode)
        } else {
            commitDraft()
        }
    }

    // MARK: 选择即预期
    //
    // 按住路标往上推：推多高就是预期几分，松手同时完成「选了」和「我以为会怎样」。
    // 两件事本来就是同一个念头，拆成两步只是实现上的方便。
    //
    // 手势挂在外面，`PathChoiceControl` 一行没动 —— 那个文件归美学侧，
    // 这里加一个识别器就够了，不必去改它的内部。

    private var pushOrigin: CGPoint = .zero

    @objc private func pushChoice(_ gesture: UILongPressGestureRecognizer) {
        guard stage == .choosing, let control = gesture.view as? PathChoiceControl else { return }
        let left = control === leftChoice

        switch gesture.state {
        case .began:
            pushOrigin = gesture.location(in: view)
            expectationRail.present(above: control, in: view)
            pushHintLabel.alpha = 0
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()

        case .changed:
            let lifted = pushOrigin.y - gesture.location(in: view).y
            let value = Self.expectationValue(forLift: lifted)
            if value != expectationRail.value, value != nil {
                UISelectionFeedbackGenerator().selectionChanged()
            }
            expectationRail.value = value

        case .ended:
            let value = expectationRail.value
            expectationRail.dismiss()
            if value != nil { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
            // 推了但没推出死区 = 他只是按了一下，按轻点处理。
            choose(left ? .a : .b, left: left, expectation: value)

        case .cancelled, .failed:
            expectationRail.dismiss()
            pushHintLabel.alpha = 1

        default:
            break
        }
    }

    /// 手指抬起的距离换算成 1–10。死区之内返回 nil —— 那还不算一个预期。
    private static func expectationValue(forLift lift: CGFloat) -> Int? {
        let effective = lift - ExpectationRailView.deadZone
        guard effective >= 0 else { return nil }
        let step = Int(effective / ExpectationRailView.stepHeight) + 1
        return min(step, ExpectationRailView.steps)
    }

    // MARK: 阶段：预期
    //
    // 这一步的存在理由：它让 n=1 就能产出洞察。
    // 「你以为 4 分，实际 7 分」不需要任何积累，而同类对比要等 3 条。
    // 所以它必须便宜到几乎没有成本 —— 一眼能跳过。

    private func enterExpecting(_ episode: DecisionEpisode) {
        stage = .expecting
        promptLabel.text = "你觉得做完之后会怎样？"
        questionLabel.text = "留一个预期，之后可以和真实的对照。也可以直接跳过。"
        scaleControl.scale = episode.metric
        scaleControl.reset()
        skipButton.setTitle("跳过，直接开始", for: .normal)
        apply(visible: [promptLabel, questionLabel, scaleControl, skipButton],
              hidden: [inputField, inputHairline, continueButton, leftChoice,
                       rightChoice, pushHintLabel, nextJunctionButton, footnoteLabel])
    }

    @objc private func scaleChanged() {
        guard let value = scaleControl.value else { return }
        switch stage {
        case .expecting:
            draft?.expectation = value
            commitDraft()
        case .rating:
            commitOutcome(value)
        default:
            break
        }
    }

    @objc private func skipTapped() {
        switch stage {
        case .choosing:
            presentManualEdit()
        case .expecting:
            commitDraft()
        case .rating:
            enterInput()
        default:
            break
        }
    }

    private func commitDraft() {
        guard let episode = draft else { return }
        store.update(episode)
        // 排提醒要等授权结果回来再排。
        // 之前是「请求授权」和「排提醒」紧挨着两行，但请求是异步的：
        // 第一条记录排进去的时候用户还没点「允许」，`add` 直接被拒，
        // 而且它不报错 —— 提醒就这么静默地没了，偏偏第一条是最不能丢的那条。
        FollowUpScheduler.requestAuthorization { granted in
            guard granted else { return }
            FollowUpScheduler.schedule(for: episode)
        }
        roadScene.setPendingCount(store.pending.count)
        draft = nil

        stage = .reflecting
        promptLabel.text = "好。\(Self.relativeDescription(until: episode.followUpAt))，我回来问你。"
        questionLabel.text = episode.expectation.map {
            "你留的预期是 \($0) 分，\(episode.metric.word(for: $0))。"
        } ?? ""
        footnoteLabel.text = ""
        nextJunctionButton.setTitle("记录下一个路口", for: .normal)
        apply(visible: [promptLabel, nextJunctionButton]
                + (episode.expectation == nil ? [] : [questionLabel]),
              hidden: [inputField, inputHairline, continueButton, leftChoice,
                       rightChoice, pushHintLabel, scaleControl, skipButton, footnoteLabel]
                + (episode.expectation == nil ? [questionLabel] : []))
    }

    // MARK: 阶段：回访

    private func enterRating(for episode: DecisionEpisode) {
        stage = .rating
        draft = episode
        // PRD 12.1 指定的文案。强调「系统记得」，不是干巴巴的评分提醒。
        promptLabel.text = "上次说的事，你做了。\n现在感觉怎么样？"
        questionLabel.text = "\(episode.chosenTitle ?? "")。\(episode.metric.name)"
        scaleControl.scale = episode.metric
        scaleControl.reset()
        skipButton.setTitle("晚点再说", for: .normal)
        roadScene.reset()
        apply(visible: [promptLabel, questionLabel, scaleControl, skipButton],
              hidden: [inputField, inputHairline, continueButton, leftChoice,
                       rightChoice, pushHintLabel, nextJunctionButton, footnoteLabel])
    }

    private func commitOutcome(_ value: Int) {
        guard var episode = draft else { return }
        episode.outcome = value
        episode.ratedAt = Date()
        store.update(episode)
        FollowUpScheduler.cancel(episode)
        draft = nil
        roadScene.setPendingCount(store.pending.count)
        enterReflecting(episode)
    }

    // MARK: 阶段：洞察
    //
    // 主句必然有（n=1 就成立），脚注要够格才出现：同类攒够 3 条给对比，
    // 否则看总样本够不够 5 条给校准度。句子怎么长出来全在 `DecisionInsight` 里。

    private func enterReflecting(_ episode: DecisionEpisode) {
        stage = .reflecting
        let insight = DecisionInsight.afterRating(episode, store: store)
        promptLabel.text = insight.headline
        questionLabel.text = ""
        footnoteLabel.text = insight.footnote ?? ""
        nextJunctionButton.setTitle("继续往前", for: .normal)
        apply(visible: [promptLabel, nextJunctionButton]
                + (insight.footnote == nil ? [] : [footnoteLabel]),
              hidden: [inputField, inputHairline, continueButton, leftChoice, rightChoice,
                       pushHintLabel, scaleControl, skipButton, questionLabel]
                + (insight.footnote == nil ? [footnoteLabel] : []))
    }

    @objc private func nextJunction() {
        resume()
    }

    /// 从通知点进来。resume 本来就先挑到点的那条，所以直接复用。
    @objc private func followUpTapped() {
        guard stage != .rating else { return }
        resume()
    }

    // MARK: 时间描述

    private static func relativeDescription(until date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval < 3600 { return "过\(max(Int(interval / 60), 1))分钟" }
        if interval < 6 * 3600 { return "过\(Int(interval / 3600))小时" }
        if interval < 36 * 3600 { return "明天" }
        return "过\(Int(interval / 86_400))天"
    }

    // MARK: 视图

    private func apply(visible: [UIView], hidden: [UIView]) {
        UIView.animate(withDuration: 0.32) {
            for element in visible {
                element.isHidden = false
                element.alpha = 1
            }
            for element in hidden {
                element.alpha = 0
            }
        } completion: { _ in
            for element in hidden { element.isHidden = true }
        }
    }

    private func flashHairline() {
        inputHairline.backgroundColor = Palette.copper.withAlphaComponent(0.7)
        UIView.animate(withDuration: 0.8) {
            self.inputHairline.backgroundColor = Palette.fadedInk.withAlphaComponent(0.25)
        }
    }

    private func configureViews() {
        roadScene.translatesAutoresizingMaskIntoConstraints = false

        textHaze.translatesAutoresizingMaskIntoConstraints = false
        textHaze.isUserInteractionEnabled = false
        textHaze.configure(top: Palette.canvasTop.withAlphaComponent(0.94),
                           bottom: Palette.canvasTop.withAlphaComponent(0))

        controlHaze.translatesAutoresizingMaskIntoConstraints = false
        controlHaze.isUserInteractionEnabled = false
        // 比顶部淡一档：底下的控件自己有底色，不需要压那么狠，
        // 压狠了路就断在半空中。
        controlHaze.configure(top: Palette.canvasBottom.withAlphaComponent(0),
                              bottom: Palette.canvasBottom.withAlphaComponent(0.86))

        wordmarkLabel.text = "未选择的路  ·  正在向前"
        wordmarkLabel.font = UIFont(name: "Songti SC", size: 12) ?? .systemFont(ofSize: 12, weight: .medium)
        wordmarkLabel.textColor = Palette.fadedInk.withAlphaComponent(0.72)
        wordmarkLabel.isUserInteractionEnabled = true
        wordmarkLabel.translatesAutoresizingMaskIntoConstraints = false

        promptLabel.font = UIFont(name: "Songti SC", size: 26) ?? .systemFont(ofSize: 26)
        promptLabel.textColor = Palette.ink
        promptLabel.numberOfLines = 0
        promptLabel.adjustsFontForContentSizeCategory = true
        promptLabel.translatesAutoresizingMaskIntoConstraints = false

        questionLabel.font = UIFont(name: "Songti SC", size: 16) ?? .systemFont(ofSize: 16)
        questionLabel.textColor = Palette.fadedInk
        questionLabel.numberOfLines = 0
        questionLabel.adjustsFontForContentSizeCategory = true
        questionLabel.translatesAutoresizingMaskIntoConstraints = false

        // 脚注：同类对比、校准度、专业领域的边界说明都落在这里。
        // 它永远比主句小一号 —— 这些话是背景，不是此刻要看的那一句。
        footnoteLabel.font = UIFont(name: "Songti SC", size: 14) ?? .systemFont(ofSize: 14)
        footnoteLabel.textColor = Palette.fadedInk.withAlphaComponent(0.85)
        footnoteLabel.numberOfLines = 0
        footnoteLabel.adjustsFontForContentSizeCategory = true

        // 手势不写在界面上就等于没有。但它也只说一次的分量 —— 小、灰、在路标正上方。
        pushHintLabel.text = "按住路标往上推，可以顺手留个预期"
        pushHintLabel.font = UIFont(name: "Songti SC", size: 13) ?? .systemFont(ofSize: 13)
        pushHintLabel.textColor = Palette.fadedInk.withAlphaComponent(0.62)
        pushHintLabel.textAlignment = .center

        inputField.placeholder = "比如：这周提出来，还是再等等"
        inputField.font = UIFont(name: "Songti SC", size: 18) ?? .systemFont(ofSize: 18)
        inputField.textColor = Palette.ink
        inputField.tintColor = Palette.copper
        inputField.returnKeyType = .continue
        inputField.clearButtonMode = .whileEditing
        inputField.delegate = self
        inputField.accessibilityLabel = "说出正在纠结的事"
        inputField.translatesAutoresizingMaskIntoConstraints = false

        inputHairline.backgroundColor = Palette.fadedInk.withAlphaComponent(0.25)
        inputHairline.translatesAutoresizingMaskIntoConstraints = false

        configureAmbientButton(continueButton, title: "把它放到路上")
        configureAmbientButton(skipButton, title: "跳过，直接开始")
        configureAmbientButton(nextJunctionButton, title: "记录下一个路口")

        scaleControl.translatesAutoresizingMaskIntoConstraints = false
        scaleControl.addTarget(self, action: #selector(scaleChanged), for: .valueChanged)

        leftChoice.accentColor = Palette.accent
        rightChoice.accentColor = Palette.accent
        leftChoice.addTarget(self, action: #selector(choseLeft), for: .touchUpInside)
        rightChoice.addTarget(self, action: #selector(choseRight), for: .touchUpInside)

        spinner.color = Palette.fadedInk
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false

        for element in [leftChoice, rightChoice, scaleControl, skipButton,
                        nextJunctionButton, questionLabel, footnoteLabel, pushHintLabel] {
            element.translatesAutoresizingMaskIntoConstraints = false
            element.alpha = 0
            element.isHidden = true
        }

        [roadScene, textHaze, controlHaze, wordmarkLabel, promptLabel, questionLabel, footnoteLabel,
         inputField, inputHairline, continueButton, spinner, pushHintLabel,
         leftChoice, rightChoice, scaleControl,
         skipButton, nextJunctionButton].forEach(view.addSubview)
    }

    private func configureLayout() {
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            roadScene.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            roadScene.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            roadScene.topAnchor.constraint(equalTo: view.topAnchor),
            roadScene.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            textHaze.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textHaze.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textHaze.topAnchor.constraint(equalTo: view.topAnchor),
            textHaze.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.52),

            controlHaze.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlHaze.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlHaze.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            controlHaze.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.3),

            wordmarkLabel.topAnchor.constraint(equalTo: guide.topAnchor, constant: 18),
            wordmarkLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 26),

            promptLabel.topAnchor.constraint(equalTo: guide.topAnchor, constant: 62),
            promptLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 34),
            promptLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -34),

            questionLabel.topAnchor.constraint(equalTo: promptLabel.bottomAnchor, constant: 16),
            questionLabel.leadingAnchor.constraint(equalTo: promptLabel.leadingAnchor),
            questionLabel.trailingAnchor.constraint(equalTo: promptLabel.trailingAnchor),

            footnoteLabel.topAnchor.constraint(equalTo: questionLabel.bottomAnchor, constant: 12),
            footnoteLabel.leadingAnchor.constraint(equalTo: promptLabel.leadingAnchor),
            footnoteLabel.trailingAnchor.constraint(equalTo: promptLabel.trailingAnchor),

            inputField.topAnchor.constraint(equalTo: questionLabel.bottomAnchor, constant: 22),
            inputField.leadingAnchor.constraint(equalTo: promptLabel.leadingAnchor),
            inputField.trailingAnchor.constraint(equalTo: promptLabel.trailingAnchor),
            inputField.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),

            inputHairline.topAnchor.constraint(equalTo: inputField.bottomAnchor, constant: 3),
            inputHairline.leadingAnchor.constraint(equalTo: inputField.leadingAnchor),
            inputHairline.trailingAnchor.constraint(equalTo: inputField.trailingAnchor),
            inputHairline.heightAnchor.constraint(equalToConstant: 1),

            continueButton.topAnchor.constraint(equalTo: inputHairline.bottomAnchor, constant: 16),
            continueButton.leadingAnchor.constraint(equalTo: inputField.leadingAnchor),

            spinner.centerYAnchor.constraint(equalTo: continueButton.centerYAnchor),
            spinner.leadingAnchor.constraint(equalTo: continueButton.trailingAnchor, constant: 12),

            scaleControl.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
            scaleControl.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),
            scaleControl.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -132),

            skipButton.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            skipButton.topAnchor.constraint(equalTo: scaleControl.bottomAnchor, constant: 18),

            leftChoice.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 22),
            leftChoice.widthAnchor.constraint(equalTo: guide.widthAnchor, multiplier: 0.42),
            leftChoice.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -108),

            rightChoice.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -22),
            rightChoice.widthAnchor.constraint(equalTo: guide.widthAnchor, multiplier: 0.42),
            rightChoice.bottomAnchor.constraint(equalTo: leftChoice.bottomAnchor),

            // 提示放在路标正上方：手势就是往这个方向推的，字本身指了路。
            pushHintLabel.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            pushHintLabel.bottomAnchor.constraint(equalTo: leftChoice.topAnchor, constant: -16),

            nextJunctionButton.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            nextJunctionButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -48)
        ])
    }

    private func configureActions() {
        // 轻点 = 选了（之后再问预期），按住上推 = 选了并顺手留下预期。
        // 0.16 秒足够把两者分开：低于它，正常点击会被误判成按住。
        for control in [leftChoice, rightChoice] {
            let push = UILongPressGestureRecognizer(target: self, action: #selector(pushChoice(_:)))
            push.minimumPressDuration = 0.16
            // 默认只容 10pt 位移，而这个手势的全部内容就是位移。
            push.allowableMovement = .greatestFiniteMagnitude
            control.addGestureRecognizer(push)
        }

        // 岔路在**开口的那一刻**就长出来，不等 AI 想完。
        //
        // PRD 15.1：选择是沿途发生的路口。用户开始说，路就已经在分了 ——
        // 等 AI 返回再叉，那是「系统给你两个选项」；一打字就叉，
        // 是「你自己走到了一个路口」。差别在谁是主语。
        inputField.addTarget(self, action: #selector(inputBegan), for: .editingChanged)

        continueButton.addTarget(self, action: #selector(submitDecision), for: .touchUpInside)
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        nextJunctionButton.addTarget(self, action: #selector(nextJunction), for: .touchUpInside)

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        // 调试：长按标题把所有等待中的回访拉到现在。
        // 回访本来是几小时到几天之后，不这样根本没法测闭环。
        let debug = UILongPressGestureRecognizer(target: self, action: #selector(fastForward))
        debug.minimumPressDuration = 1.2
        wordmarkLabel.addGestureRecognizer(debug)
    }

    @objc private func fastForward(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()

        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let configured = IntelligenceConfig.current() != nil
        sheet.addAction(UIAlertAction(title: configured ? "AI：已接入，重新设置" : "AI：未接入，去设置",
                                      style: .default) { [weak self] _ in
            self?.presentIntelligenceSetup()
        })
        sheet.addAction(UIAlertAction(title: "把所有回访拉到现在", style: .default) { [weak self] _ in
            guard let self else { return }
            self.store.fastForwardAllFollowUps()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            self.resume()
        })
        // 通知这一环没法用「拉到现在」测：到点了才发得出来。
        // 排到 10 秒后，退到后台等它自己弹 —— 这是唯一能真看到那一下的办法。
        sheet.addAction(UIAlertAction(title: "把最近一条回访排到 10 秒后", style: .default) { [weak self] _ in
            self?.scheduleImminentFollowUp()
        })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        sheet.popoverPresentationController?.sourceView = wordmarkLabel
        present(sheet, animated: true)
    }

    /// 调试：把一条等待中的回访排到 10 秒后，通知一起重排。
    /// 记录本身的 `followUpAt` 也跟着改，否则通知弹出来了、App 里却还没到点。
    private func scheduleImminentFollowUp() {
        guard var episode = store.pending.sorted(by: { $0.followUpAt < $1.followUpAt }).first else {
            promptLabel.text = "没有等待中的回访。先记一个路口。"
            return
        }
        FollowUpScheduler.cancel(episode)
        episode.followUpAt = Date().addingTimeInterval(10)
        store.update(episode)
        FollowUpScheduler.requestAuthorization { granted in
            FollowUpScheduler.schedule(for: episode)
            UINotificationFeedbackGenerator().notificationOccurred(granted ? .success : .error)
        }
    }

    /// 填 key 的地方。
    ///
    /// 存 UserDefaults 只够 MVP：key 在设备上是明文的。正式版必须走自己的
    /// 服务端中转，客户端不该拿着服务商的 key —— 那等于把它发给每一个装了 App 的人。
    private func presentIntelligenceSetup() {
        let alert = UIAlertController(
            title: "接入 AI",
            message: "国内服务商都是 OpenAI 兼容格式。\n服务商填 deepseek / qwen / moonshot / zhipu / doubao。",
            preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "服务商"
            field.text = UserDefaults.standard.string(forKey: "ai.provider") ?? "deepseek"
            field.autocapitalizationType = .none
        }
        alert.addTextField { field in
            field.placeholder = "API key"
            field.text = UserDefaults.standard.string(forKey: "ai.apiKey")
            field.autocapitalizationType = .none
            field.isSecureTextEntry = true
        }
        alert.addTextField { field in
            field.placeholder = "模型名（留空用默认）"
            field.text = UserDefaults.standard.string(forKey: "ai.model")
            field.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "存下", style: .default) { _ in
            let provider = alert.textFields?[0].text?.trimmingCharacters(in: .whitespaces) ?? "deepseek"
            let key = alert.textFields?[1].text?.trimmingCharacters(in: .whitespaces) ?? ""
            let model = alert.textFields?[2].text?.trimmingCharacters(in: .whitespaces)
            IntelligenceConfig.store(provider: provider.isEmpty ? "deepseek" : provider,
                                     apiKey: key,
                                     model: (model?.isEmpty ?? true) ? nil : model)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        })
        present(alert, animated: true)
    }

    private func configureAmbientButton(_ button: UIButton, title: String) {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.baseForegroundColor = Palette.copper
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont(name: "Songti SC", size: 16) ?? .systemFont(ofSize: 16, weight: .medium)
            return outgoing
        }
        button.configuration = configuration
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        submitDecision()
        return true
    }
}
