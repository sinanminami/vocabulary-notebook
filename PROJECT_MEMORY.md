# 项目记忆：单词记录本

> 最近核对：2026-11-19（交接资料、源码目录结构、包测试与未签名 Debug 构建）；最近一次功能实现记录：2026-09-11。  
> 作用：保存跨对话必须延续的产品决定、当前实现状态和下一步优先级。后续开发前先阅读本文件；完成重要功能后同步更新。不要在这里记录 API Key 或其他秘密。

## 1. 产品方向

- 产品是 macOS 原生、local-first、privacy-first、keyboard-first 的 AI 单词采集与间隔复习 App。
- 核心价值是“低摩擦收词 + AI 自动解释 + 自动安排复习”。目标流程：阅读时选词，按全局快捷键，AI 生成词卡，用户确认后保存。
- 第一阶段个人使用，但架构需为未来公开发布、移动端复习和云同步保留迁移空间。
- MVP 只处理单词和短语，不做语法分析、长句润色或通用聊天。
- 当前 AI Provider 已从 OpenAI 改为 Google Gemini；API Key 只存 macOS Keychain。
- 当前不做登录、付费、云同步。词库和复习数据只存本地 SQLite；AI 生成时只发送词条和用户主动填写的上下文。

### 长期产品主线（2026-08-27 决定持续推敲与迭代）

- 产品不应停留在“AI 词典 + 闪卡”，而要发展为理解用户个人阅读经历的“活的词汇记忆系统”。长期体验链路是：**遇见 → 理解 → 记住 → 使用**。
- **相遇轨迹（最高产品辨识度）**：重复遇到同一词时，不只增加次数；保存每次真实语境、来源、时间，形成 Encounter Trail。后续可让 AI 总结跨语境的稳定含义、搭配和主题。来源采集必须保持隐私克制、可见、可编辑。
- **一个单词多个词义**：底层从“一词一卡”逐步升级为“单词 → 多个 sense → 每次 encounter 归属某个 sense”。AI 根据原句判断已有/新词义，不应因掌握一个含义而把整个多义词视为已掌握。
- **多维掌握度**：未来在 FSRS 时间调度之外，区分视觉识别、听力识别、主动回忆、语境理解、拼写和实际使用；复杂度留在后台，前台只给清晰诊断和下一步动作。
- **词义边界与易混辨析**：比堆同义词更重视“为什么不能互换”和拼写相似词，生成少而精的 contrast，例如 `considerable / considerate / substantial`。
- **自适应微型复习**：根据遗忘原因安排普通回忆、听音辨词、语境填空、易混选择、拼写回忆或一句话使用，而不是所有词重复同一种卡片。
- **个人记忆偏好**：通过“有帮助 / 换一种记法”等轻反馈，逐步学习用户更适合构词、词族、辨析、语境、画面还是声音联想；后续让 Gemini 按个人偏好生成。
- **学习诊断而非报表堆叠**：Statistics 应回答“为什么还没记住、哪些词反复混淆、哪些只有单一语境、哪些已能使用、哪种线索最有效”，每周给少量可行动结论。
- **进入表达**：成熟阶段增加克制的“今日表达”，用当天少量词完成两句话，AI 只反馈正确性、搭配自然度和更自然表达，不演变为通用聊天窗口。
- 推荐演进顺序：1) 相遇轨迹；2) 多词义结构；3) 记忆线索；4) 自适应复习；5) 个人记忆偏好；6) 学习诊断与输出。记忆线索第一版已提前落地；下一项底层设计优先讨论相遇轨迹与多词义结构。

## 2. 当前技术结构

- `VocabularyApp/App`：SwiftUI 界面、应用环境、全局快捷键和页面 ViewModel。
- `Packages/VocabularyKit/Sources/VocabularyCore`：领域模型、协议、词条规范化、掌握度规则。
- `Packages/VocabularyKit/Sources/VocabularyPersistence`：GRDB/SQLite、迁移、Repository、FSRS 6 调度。
- `Packages/VocabularyKit/Sources/VocabularyAI`：Gemini structured output、HTTP、Keychain。
- 本地依赖：vendored GRDB 和官方 `swift-fsrs`，避免核心调度逻辑漂移。
- 数据库位于 Application Support 下，实体已有 VocabularyCard、VocabularySense、VocabularyEncounter、Tag、词卡标签关联、卡片级与词义级 ReviewState/ReviewLog、AppSettings；AppSettings v5 已包含每日新词额度和复习提醒偏好。v9 后卡片级复习表暂时作为兼容层，与主词义双向同步。
- 本地 Debug 使用 `VocabularyApp/LocalSigningRequirements.txt` 提供稳定 designated requirement，避免每次构建后 Accessibility 授权因临时代码签名变化失效。
- `VocabularyApp/App/DesignSystem.swift` 是统一视觉入口：2026-11-19 起为浅色「浪漫 Romantic」主题——珍珠白 canvas、淡丁香 sidebar、白色 surface、珍珠白 raised surface、深梅紫正文与灰紫次级文字；`grape/sakura/lilac/pearl` 保存原始色板，`accent/violet/pink/orange/cyan/yellow` 为同语义的加深可读版本。App 与 Quick Add 浮窗强制 `.light` 外观。

## 3. 已实现且可用

### 收词与 AI

- `Command + N` 手动添加；输入词条和可选上下文后调用 Gemini。
- Gemini 使用严格 JSON Schema 生成：规范词条、语言、中文释义、简单英文释义、英文例句、1–3 个建议标签。
- 生成结果全部可编辑，保存到本地；AI/网络/Key/schema 错误有简短提示。
- 快捷采词自动触发 AI 生成；手动添加仍由用户点击 Generate。
- Gemini 对网络错误、429 和 5xx 自动做有限退避重试；Settings 可用 `Test Connection` 验证当前 Key。
- 默认 12 个系统标签，可在新增词卡时多选并保存。
- 规范化去重已实现；重复词不创建第二张卡，可 Add Encounter，增加遇见次数且不改变复习排期。
- 重复检测在 AI 识别语言后按“语言 + normalized term”执行，不会把不同语言的同形词误判为重复。
- 2026-09-03：完成相遇轨迹与多词义的第一阶段底座。新增 `VocabularySense`，每个词义拥有独立释义、例句、记忆线索、反馈和 FSRS 状态/日志；`VocabularyEncounter` 现在必须归属一个具体词义。新增词卡原子创建主词义、首次相遇、卡片级状态和词义级状态；可新增/编辑/删除次要词义，主词义受删除保护；相遇记录可明确写入指定词义。
- v9 追加迁移为每张旧卡创建且仅创建一个主词义，把现有真实相遇记录指向主词义，并原样复制旧 ReviewState/ReviewLog 到词义级表。历史 `encounter_count` 不展开为虚构轨迹。Library、Today、提醒和 Review Session 已读取词义级数据；过渡期继续保留卡片级兼容表，并对主词义双写，确保旧排期与日志不会分叉。

### Chrome / PDF 全局快捷收词

- 可选快捷键：`⌃⌥W`、`⌃⇧W`、`⌃⌥A`；用户目前偏好 `⌃⌥A`，实际选择持久化在 UserDefaults。
- 优先通过 Accessibility 读取选区。
- Chrome 内置 PDF 不暴露 AX selected text 时，向原前台进程定向发送 `Command + C`，轮询剪贴板后带入词条。
- 自动复制失败时支持用户先手动 `Command + C` 的保底流程，并展示具体诊断信息。
- 全局快捷键现在打开独立轻量 NSPanel，不再把主窗口和 sheet 拉到阅读现场；Enter 保存、Esc 取消，保存后显示短暂成功反馈。
- App 内可用 `Command + Shift + N` 打开 Quick Add，菜单栏也提供 Quick Add、Review Today、主窗口和 Settings 入口。

### 词库与复习

- Today 显示到期词义、今日可学新词义、预计时间与总词数，可开始复习。
- Settings 可配置 0–100 的每日新词义额度；额度按本地自然日和当天首次学习的唯一词义计算，同一拼写的两个新词义会占用两个学习单元，多次开启复习不会绕过上限，设为 0 时只复习到期旧词义。
- Settings 可开启 macOS 每日复习提醒、选择时间，并选择“仅在有到期词义时提醒”；页面显示通知权限状态，拒绝后可跳转系统设置。
- 提醒按未来 14 天滚动安排，在 App 启动/激活、词库或复习数据变化后刷新；点击通知会激活 App、进入 Today 并打开 Review Session。
- Library 有搜索、Language / Tag / Mastery / Due Status 筛选、五种排序和主从栏详情；可读取并展示标签，可编辑全部词卡字段和标签，也可在确认后删除词卡。
- Library 详情按 sense 分卡展示中文释义、英文定义、英文例句、记忆线索、独立掌握度和排期；每个词义可展开“在 X 个场景遇到”，查看原句、来源应用和相对时间。词条总体掌握度取最薄弱词义。
- 次词义可独立编辑或确认删除，主词义受保护；编辑词义不会重置历史排期。
- Library 编辑页可用 AI 重新生成定义、例句和推荐标签，保存时不重置复习历史与排期。
- Settings 支持创建、重命名和删除自定义标签；12 个默认标签受保护。
- FSRS 6 四档评分已接入词义级队列，评分后原子更新对应 Sense ReviewState 并追加 Sense ReviewLog；主词义同时写入旧卡片级兼容层，次词义完全独立。
- 支持英→中、中→英；Space 显示答案，1–4 评分并显示预计间隔。
- 每次创建 Review Session 都会随机打乱本轮到期旧词与额度内新词；英→中和中→英都在卡片出现时用 macOS 系统语音自动朗读词条。朗读任务直接绑定当前卡片 ID，首次打开与每次切换都会执行，并立即停止上一条语音；卡片词条下方有 `Listen Again` 按钮可随时从头重播。
- Statistics 已迁移为词义级口径，分别显示词条数与学习词义数、Mastered / Familiar / Learning / New、到期词义、本周新增词义、本周复习和 7/30 天活动图；不再把自评分数包装成记住率。底部只展示最多四条有客观理由和明确动作的学习诊断。
- Settings 的 Data & Privacy 显示缺字段/未打标签数据健康状态，并可导出包含词卡、标签、掌握度和复习时间的 CSV。
- 2026-08-27：新增结构化 **记忆线索**。Gemini 为每张新词卡从构词拆解、词族联想、易混辨析、语义桥梁、画面、声音/拼写、语境和直接联想中只选择一种最佳策略；输出包含策略、短标题、可选拆解、中文记忆逻辑、记忆句和可选易混提醒。提示词与 JSON Schema 明确禁止强行拆词根、虚构词源或把不确定词源当事实；`cue_zh` 尽量不重复目标词，以便用于主动回忆提示。
- 记忆线索使用 v6 追加迁移，以 JSON + 可选反馈保存；旧词和全部原有复习数据无损兼容。新增/编辑词卡中可继续编辑所有线索字段；Library 详情完整展示，旧词可单独生成；“换一种记法”会明确排除当前策略后重新调用 Gemini 并替换，“有帮助”会持久化反馈，替换线索后反馈自动清空。
- Review Session 在答案揭晓前增加按需“给我一个提示”。英→中显示策略、可选可靠拆解与中文线索；中→英隐藏完整拆解，降低直接泄露答案的程度。每张新卡切换后提示状态自动重置，未生成线索的旧卡不显示无效按钮。
- 数据健康状态新增“without memory insight”计数；CSV 导出新增记忆策略、标题、拆解、中文线索、记忆句、辨析和反馈字段。
- 2026-08-27：音标成为词卡正式字段。Gemini 完整词卡 structured output 新增必填 `pronunciation_ipa`，要求返回带 `/…/` 的标准 IPA；v7 追加迁移给旧词安全补空字段。Add/Edit 可查看和修改，Library 列表与详情显示；旧词缺少音标时可用独立 AI 请求补充，不覆盖已有释义、例句、标签或复习状态。数据健康与 CSV 同步新增 missing IPA 与 `pronunciation_ipa`。
- Review Session 对新词学习卡和到期复习卡统一显示 IPA，英→中和中→英均可见，并保留自动朗读及 Listen Again。答案前仍只显示渐进提示；答案揭晓后在释义和例句下完整展示已生成的记忆线索，包含策略、拆解、中文逻辑、记忆句和易混提醒。
- Review Session 默认进入自适应模式，并保留手动英→中 / 中→英。`LearningDiagnosticsPlanner` 依据 sense 的 reps/lapses/difficulty/due、最近日志、相遇语境、IPA 和记忆线索，在主动回忆、听音辨义、语境填空、拼写回忆、易混辨析中选择一种；新词和证据不足的词义保持普通识别。实际题型通过既有 `review_mode` 写入词义日志，无需改变 FSRS 数据或重置排期。

### 当前验证基线

- 2026-08-25：`swift test` 通过，44 tests / 10 suites。
- 2026-08-25：无签名与本地稳定签名的 Debug `xcodebuild` 均成功。
- 测试已覆盖 normalization、语言范围内去重、数据库 CRUD、初始复习状态、Add Encounter、默认/自定义标签、AppSettings/提醒偏好、每日新词额度、提醒计划、FSRS 队列/评分/日志、mastery、Statistics 日期边界/留存口径、Gemini 请求/解码/错误映射/重试、CSV 转义与数据健康检查。
- 已用真实 macOS 构建验收 Today、Library/详情/编辑、Statistics、Settings 和独立 Quick Add 浮窗；验收未写入测试词、未调用 Gemini、未改变系统权限。
- 可直接测试的稳定本地签名 Debug App 已复制到 `Build/单词记录本.app`，并通过 `codesign --verify --deep --strict`；它不是正式公证发行包。
- 2026-08-25：App Icon 已更新为最终选择的高级磨砂玻璃方案。视觉语义为“叠放词卡 + 玉石书签 + 蚀刻 `W`”，材质为暖白乳光玻璃与烟灰透明玻璃；设计源在 `VocabularyApp/Resources/AppIcon-master.png`，完整 16–1024 px 资源在 `VocabularyApp/Resources/Assets.xcassets/AppIcon.appiconset`。候选与生成过程稿保存在 `VocabularyApp/Resources/IconConcepts/AppleStyleRound2`；`Scripts/clean_icon_alpha.swift` 用于确定性清理生成图外围透明杂点。Xcode 构建已生成 `AppIcon.icns` 与 `Assets.car`，Info.plist 已包含 `CFBundleIconName = AppIcon`。
- 2026-08-25：完成第一轮全局 UI/UX 设计升级。Today 改为聚焦式复习入口；Library 提升列表信息密度并将详情拆为层次卡片；Statistics 建立统一指标和活动图表视觉；Settings 改为分组设置面板；Add/Edit Word、Quick Add 成功反馈和 Review Session 统一到同一设计语言。复习答案与评分区已做实机检查，验收过程中未新增/删除词卡，也未提交复习评分。
- 2026-08-25：上述设计升级完成无签名及稳定本地签名 Debug 编译，`swift test` 仍为 44 tests / 10 suites 全部通过，并逐页实机验收 Today、Library/详情、Statistics、Settings、Add Word、Edit Word、Review Session。
- 2026-08-25：完成第二轮“减法式”视觉精修：系统 List 侧边栏替换为自定义产品导航和 Local First 状态；全局背景、主卡片和按钮增加极克制的渐变/内高光；Today 的三张指标卡合并为连续数据带，预计时长圆环明确采用 15 分钟专注参照；Statistics 的九宫格重构为词库总览、成熟度进度和本周节奏；Library 顶部详情使用主卡片材质并减少重复排序标签与多余紫色。目标是减少 SaaS 仪表盘感和“卡片汤”，用层级、留白与材质建立设计感。
- 2026-08-25：第二轮精修再次通过稳定本地签名 Debug 编译和 44 tests / 10 suites；使用最终签名 App 实机复检 Today、Statistics 和 Library，未改变任何词库或复习数据。
- 2026-08-25：视觉方向切换为 Spotify 启发的沉浸式深色主题。采用黑色侧边栏、深绿顶部氛围渐变、炭灰卡片、高对比粗体标题和鲜绿色圆形主按钮；左上角 App 图标扩大到 44pt、品牌名提升到 18pt 粗体、副标题提升到 12pt，导航文字提升到 15pt 并加宽侧边栏。主窗口与独立 Quick Add 都固定深色外观。实机检查 Today、Library、Statistics、Settings、Add Word 和 Review Session 后对比度与控件外观正常。
- 2026-08-25：深色复习页验收时自动化点击因异步刷新误触了 `normalization` 的 Good 和 `novel` 的 Hard。已在关闭 App 后按两条 ReviewLog 的 `previous_state_json` 精确恢复两张卡的原始 ReviewState，并删除仅这两条误触日志；复核 `review_logs = 0`，两卡均为 `new / reps 0 / stability 0 / lastReviewed nil`。操作前备份保存在 `Build/Vocabulary-before-ui-qa-20260825-1844.sqlite`。
- 2026-08-25：深色主题最终稳定签名 Debug 构建成功，`swift test` 仍为 44 tests / 10 suites 全部通过，代码签名验证通过。
- 2026-08-25：在 Spotify 主应用深色主题上继续引入 Wrapped 风格。参考官方 2024 Wrapped 的高能量配色、循环图形与可变布局，以及 2025 Wrapped 的“混乱与清晰张力”、层叠纹理和克制色板；实现六色语义系统：绿色=主操作/完成，紫色=Library/新词，橙色=Statistics/学习压力，湖蓝=信息/复习活动，粉色=最近活动/例句，暖黄=新内容/提示。主卡片支持双色渐变与循环线条，页面背景使用低透明紫蓝光晕。
- 2026-08-25：Wrapped 多色主题完成无签名与稳定本地签名 Debug 编译，44 tests / 10 suites 全部通过，代码签名验证通过；实机复检 Today、Library、Statistics、Settings，颜色比例、正文对比度和左上角 18pt 品牌字号正常，最终 App 停留在 Today。
- 2026-08-25：App 图标同步为 Wrapped 多色视觉：保留白色磨砂词卡、书签与 “W” 的既有识别资产，外层升级为黑曜石玻璃，并使用紫粉、橙黄、蓝绿光带与界面六色系统呼应。已生成 16px–1024px 完整 macOS AppIcon 资源，64px 小尺寸识别检查通过，重新编译并替换 `Build/单词记录本.app`，严格代码签名验证通过。旧版浅色图标和生成原稿保存在 `VocabularyApp/Resources/IconConcepts/SpotifyWrapped`。
- 2026-08-26：根据“过亮、赛博朋克感过强”的反馈收敛 App 图标：删除发光环与霓虹管线，将综合色饱和度和发光感降低约 65–75%，改为黑银主体和少量低饱和紫、琥珀、青色玻璃折射；白色磨砂词卡、书签和深色 “W” 保持不变。复用上一版正确透明通道完成确定性圆角裁边，16px–1024px 全尺寸资源重新生成，64px 识别检查、Debug 编译和严格代码签名验证通过。高亮版仍保存在 `VocabularyApp/Resources/IconConcepts/SpotifyWrapped/AppIcon-wrapped-neon-production.png`，便于回退。
- 2026-08-26：复习体验新增随机卡序与自动发音。`ReviewSessionModel` 在每次加载会话时通过 `ReviewQueueRandomizer` 打乱完整队列；`WordPronouncer` 使用 `AVSpeechSynthesizer`，英语选择 `en-US`、日语选择 `ja-JP`，新卡切换时停止上一条语音。为保护中→英检索，该模式延迟到显示答案后朗读。新增固定随机种子测试验证卡序改变且成员不丢不重；完整基线提升为 45 tests / 11 suites，稳定签名 Debug 构建通过。
- 2026-08-26：用户实测切卡未听到朗读。原因是首版为避免泄露答案，主动抑制了中→英模式的切卡发音，且使用 `onChange` 间接观察卡片。按用户明确预期改为两种模式都在新卡出现时朗读，并使用 `.task(id: currentItem.id)` 直接绑定卡片生命周期，覆盖首张卡和后续每次切换。
- 2026-08-26：复习卡片新增常驻 `Listen Again` 重播按钮，使用扬声器图标与安静胶囊按钮样式；点击后停止当前语音并从头朗读当前词条，答案显示前后以及两种复习方向均可使用。
- 2026-08-26：用户反馈短单词播放时出现由小到大的起音渐强，前半段听不清。离线波形检查证明普通 `preUtteranceDelay` 不会写入合成音频：测试词仅约 2.9ms 后就开始发声，峰值约 0.74。改用 Apple 支持的 SSML，在同一音频内部加入 350ms `<break>`，并用 `volume="loud"` + 固定 1.0 音量；实测得到约 276.6ms 真实静音预卷、1.0 峰值与 22050Hz 采样率。这样先用静音唤醒输出链路，再以恒定满幅朗读，避免第一个音节被渐强吞掉；保留 60ms 尾部缓冲和 XML 转义。
- 2026-08-26：用户复测仍只能听到半个单词。再次改造为“先完整离线合成 PCM → 写入 CAF → `AVAudioPlayer.prepareToPlay()` → 一次性播放”，不再让系统合成器直接追着实时音频流启动。实机打开 Review Session 触发生产代码后分析 `omit` 文件：总长 743ms、语音 352.4ms 开始、740.6ms 结束、有效语音 388.3ms、峰值 0.682，证明整词已生成，但尾音距 EOF 仅 2.4ms，存在输出设备关闭时吞尾音的风险。因此文件头加入 350ms 极低幅预热信号，文件尾再追加 250ms 静音保护，保证首尾音节都在稳定音频链路内播放。
- 2026-08-26：为避免本机多个相同 bundle identifier 的旧进程干扰，额外构建 `com.wordnotebook.VocabularyApp.SpeechTest` 唯一标识测试 App，并通过 SQLite 只读备份使用独立词库副本。真实 Review Session 自动播放 `emphasis` 的最终 CAF：总长 1300.3ms、语音 353.4ms 开始、1047.3ms 结束、有效语音 694.0ms、尾部保护约 253ms、峰值 0.6814、22050Hz；点击 `Listen Again` 后生成文件的全部指标完全一致。未显示答案、未提交评分；测试库副本完成后移到 `/private/tmp/com.wordnotebook.VocabularyApp.SpeechTest-20260826-1712`，正式数据库未改动。
- 2026-08-27：记忆线索切片完成 `swift test`，当前基线为 **47 tests / 11 suites**；新增测试覆盖完整词卡的嵌套 structured output、禁止虚构词源的请求约束、排除旧策略的单独再生成、v6 持久化、帮助反馈、替换后反馈清空和 CSV 新字段。无签名及稳定本地签名 Debug Xcode 构建均成功。
- 2026-08-27：IPA 与复习完整记忆线索切片完成后，当前基线提升为 **49 tests / 11 suites**。新增测试覆盖完整词卡 IPA 解码、旧词独立 IPA 生成、v7 持久化与补充、数据健康和 CSV 字段；无签名与稳定本地签名 Debug 构建均成功。新版已替换 `/Applications/单词记录本.app`，严格签名验证通过，`Build/单词记录本.app` 继续指向该安装包；旧安装版备份在 `/private/tmp/单词记录本-before-ipa-20260827.app`。
- 2026-08-27：桌面目录由 File Provider 管理，会在复制后的 `.app` 内写入 FinderInfo，导致 `codesign --strict` 失败。因此最终稳定签名测试版安装到 `/Applications/单词记录本.app`，`Build/单词记录本.app` 是指向它的软链接；两条路径解析到同一份 App，designated requirement 继续为 `identifier "com.wordnotebook.VocabularyApp"`，严格签名验证通过。该变化不会改变现有 Keychain 或 Accessibility 身份。
- 2026-08-28：App Icon 按 Apple Design Awards 与新版 HIG 的设计原则重做，但不复制任何获奖作品。旧方案同时堆叠底座、词卡、书签、`W`、折射和多圈高光，小尺寸视觉中心过多；新方案收敛为一个连续暖象牙折页，正形表达打开的词页，中心负形表达书签，并隐约形成 memory 的 `M`，深茄紫背景与小面积柿橙内折提供识别色。明确去除文字、卡片堆、霓虹、厚玻璃和装饰环。16–1024 px 全尺寸已生成，32/64 px 识别检查通过；源图、首稿与旧图备份在 `VocabularyApp/Resources/IconConcepts/AppleDesignAwards2026`。稳定签名 Debug 构建成功，新版已替换 `/Applications/单词记录本.app`，严格代码签名及 designated requirement 验证通过；旧安装版可从 `/private/tmp/单词记录本-before-ada-icon-20260828.app` 恢复。
- 2026-09-03：多词义底座完成后基线为 **53 tests / 12 suites**。合成 v7/v8 旧库测试验证主词义、相遇、排期和日志映射；真实词库一致性副本验证迁移前后均为 14 张词卡、14 个旧状态、60 条旧日志和 14 条真实相遇，迁移后对应为 14 个主词义、14 个词义状态和 60 条词义日志，0 条未分配相遇，SQLite integrity/foreign key 检查正常。正式迁移前备份位于 `Build/Vocabulary-before-senses-20260903.sqlite`。稳定签名 Debug App 已替换 `/Applications/单词记录本.app` 并严格验证；为避免打断用户，未强制退出或重启正在运行的旧进程，正式库会在下次正常启动时执行 v9。
- 2026-09-05：第二兼容切片的收词/相遇交互完成。全局快捷键会在激活 App 前记住来源应用名，新词和重复词均将来源、时间与用户填写的原句保存到本地 encounter；不采集窗口标题或 URL，来源应用名也不发送给 Gemini。受 macOS Accessibility/Chrome PDF 能力边界影响，只选中单词时无法可靠读取周边整句，因此生成后和重复词确认页都保留可编辑原句入口。
- 2026-09-05：重复词不再直接写入主词义。Gemini 使用原句、已有 senses 和当前候选释义输出“已有词义 / 可能新词义”建议；未知 sense ID 会被严格拒绝。用户可手动改选，且只有明确点击 `Create Meaning & Save` 才会创建新词义，AI 不会静默写入。原句后补或变化时可显式重新生成语境释义并匹配。基线提升为 **55 tests / 12 suites**，完整 App 编译和严格稳定签名验证通过；新版已安装到 `/Applications/单词记录本.app`，旧版备份位于 `/private/tmp/单词记录本-before-encounter-sense-20260905.app`。
- 2026-09-09：第三兼容切片完成。Library 已按词义展示内容、记忆线索、独立状态与可展开相遇轨迹；Today、复习提醒和 Review Session 改为 sense 级队列，同一词条的不同词义会分别学习、评分和排期。每日额度改按唯一 sense 计算，词条总体掌握度取最薄弱词义；主词义继续双写卡片级兼容层，旧排期和日志未重置。
- 2026-09-09：真实词库在写入前已用 SQLite `.backup` 保存为 `Build/Vocabulary-before-sense-review-ui-20260909.sqlite`。副本核验为 14 张词卡、14 个词义、14 条相遇、14 个卡片状态、14 个词义状态、86 条卡片日志和 86 条词义日志；SQLite integrity/foreign key 检查正常且无孤立状态。另用独立 bundle identifier 和独立测试词库注入一个虚构次词义，实机验收 Library 的 `MEANING 1/2`、独立相遇与复习卡片，未打开或改写正式数据库。
- 2026-09-09：完整基线提升为 **57 tests / 12 suites**，新增覆盖“同一拼写的两个新词义分别占用每日额度”和“每个 sense 独立进入队列/评分”。无签名 Debug 编译、稳定本地签名与严格代码签名验证均通过。
- 2026-09-09：第四兼容切片完成。新增纯 Core `LearningDiagnosticsPlanner`，只使用反复遗忘、持续高难度、明显逾期、语境过窄和学习支架缺失等客观信号；前台最多展示四条“原因 + 下一步动作”，不输出竞争分数或记住率。Statistics 全面切换到 sense 口径，并同时保留词条总数作为结构信息。
- 2026-09-09：复习页新增默认“自适应”模式以及五类可解释题型，仍保留手动英→中 / 中→英、IPA、自动发音、Listen Again、提示与四档 FSRS 评分。自适应题型复用既有 `review_mode` 字段记录，无 schema 变化，因此本切片不新增空迁移；旧日志的两个 mode 继续可读。独立测试词库模拟高难度次词义后成功触发 `LISTEN & RECALL`，Statistics 的词条/词义分层和诊断卡片完成实机验收。
- 2026-09-09：最终基线为 **61 tests / 13 suites**；新增覆盖反复遗忘优先易混辨析、高难度触发听音、语境挖空、全量相遇读取及自适应题型日志持久化。完整 Debug App 编译和严格稳定签名验证通过，新版已安装到 `/Applications/单词记录本.app`；安装前版本备份在 `/private/tmp/单词记录本-before-adaptive-review-20260909.app`。
- 2026-09-10：修复“完成每日复习后仍提示一个词义待复习”。正式数据库只读核验发现，相关词义在约一分钟前选择了“忘了”，FSRS 正确安排了短时学习步骤，但旧会话使用静态队列并提前显示完成。现在“忘了”的词义会携带最新状态回到本轮队尾，显示“再巩固一次”，再次出现时也会重新朗读；完成页分别显示唯一词义数与主动回忆次数，Today 在关闭复习后主动刷新。隔离 bundle identifier 与独立数据库的完整 UI 流程已验证：1 个到期词义 → 忘了 → 2/2 再巩固 → 记得 → 完成 1 个词义 / 2 次主动回忆 → Today 立即显示 0。正式数据库未改动。
- 2026-09-10：本次稳定性修复新增 `ReviewRequeuePolicy` 纯逻辑测试，覆盖 Again 重排队及 Hard/Good/Easy 正常完成；完整基线提升为 **63 tests / 14 suites**，完整 Debug App 编译通过。稳定签名修复版已安装到 `/Applications/单词记录本.app`，严格签名及固定 designated requirement 验证通过；安装前版本备份在 `/private/tmp/单词记录本-before-review-requeue-20260910.app`，隔离 UI 测试数据已移至 `/private/tmp/com.wordnotebook.VocabularyApp.SenseUITest20260909-requeue-completed`。
- 2026-09-10：Today 将“到期复习”和“今日新词额度”拆开表达，不再把 `0 / 20` 混在复习任务摘要中。摘要明确显示到期词义与本次加入的新词义；额度改为“已学 X · 上限 Y”，且在既无待学新词、今天也未首次学习新词时隐藏，避免被误读成到期复习完成进度。63 tests / 14 suites 与完整 Debug 编译均通过；稳定签名新版已安装到 `/Applications/单词记录本.app`，安装前版本备份在 `/private/tmp/单词记录本-before-today-quota-20260910.app`。
- 2026-09-11：Settings 新增“启动与后台”，使用 macOS `SMAppService.mainApp` 原生登录项控制“登录时自动启动”。状态始终读取系统真实值，区分已启用、未启用、等待批准与不可用；需要批准时可直接打开系统登录项设置并重新检查。该偏好由 macOS 管理，不写入 SQLite，也不引入常驻 helper。63 tests / 14 suites 与完整 Debug 编译通过；安装包确认链接系统 ServiceManagement framework、稳定签名和 designated requirement 均有效，新版已安装到 `/Applications/单词记录本.app`，安装前版本备份在 `/private/tmp/单词记录本-before-launch-at-login-20260911.app`。隔离 UI 自动化两次连接超时，未代替用户切换登录项。
- 2026-09-11：复习答案补齐中文释义。主动回忆与易混辨析原本直接以中文作为答案，听音题原本显示“词条 · 中文”；语境填空和拼写回忆此前只显示词条、英文释义与例句，现在会在词条下方以独立黄色层级展示当前 sense 的中文翻译，五种题型的答案信息由此保持完整一致。63 tests / 14 suites、完整 Debug 编译及稳定签名均通过，新版已安装到 `/Applications/单词记录本.app`；安装前版本备份在 `/private/tmp/单词记录本-before-answer-translation-20260911.app`。
- 2026-11-19：按用户提供的「浪漫 Romantic」配色图（葡萄紫 #A78AD4、樱花粉 #F5B5CF、淡丁香 #D8C8ED、珍珠白 #FFF1E9）将整体视觉从深色 Wrapped 主题切换为浅色主题。只改 `DesignSystem.swift` 的 token、卡片/阴影/背景修饰器、主按钮（白字 + 葡萄紫渐变）以及三处 `preferredColorScheme(.dark)` → `.light`；页面结构与颜色语义不变。文字用语义色经对比度计算加深（正文 13.5:1，次级 4.8:1，语义色 3.4–4.8:1）。App 图标未改。Library 选中行改为自绘淡丁香底（系统失焦选中色为灰色，不受 tint 影响），侧边栏选中项改为白底。未签名 Debug 构建通过；用独立 bundle id 的预览副本启动验证，未触碰真实词库与 /Applications 安装版。
- 2026-11-20：修复窄窗口下侧边栏被推出窗口左侧（"ord Notebook" 被截断）的旧布局问题。根因：detail 内容的最小宽度会被 NavigationSplitView 叠加在侧边栏宽度之上（所需窗口宽 ≈ 侧边栏 ×2 + Library 两栏最小宽度，旧值 1277pt，1040pt 窗口必然溢出），NSSplitView 还会把错误宽度持久化。修复：RootView 的 detail 内容包一层 `.frame(minWidth: 0, maxWidth: .infinity, …)` 阻断最小宽度上传；Library 列表/详情由 AppKit `HSplitView` 改为纯 SwiftUI `HStack`（详情 300–420pt，列表填充剩余，代价是不能拖动分隔线）；窗口最小宽 840→960。验证：预览副本保存的 detail 宽度从 1197 变为等于窗口宽度 1040（与正式版 1440/1440 的健康模式一致），用户确认 Library 侧边栏完整。`defaultSize` 改为 1120×720，但预览副本仍以 1040×700 打开，原因未查明。
- 2026-11-20：根据“首页颜色有点脏”的反馈清理浅色主题：`appHeroCard` 的大面积填充改用原始淡丁香/樱花粉色板加白色（加深后的语义色以低透明度铺在暖白上会发灰），装饰从两环一光晕减为一个柔光加一道细环；页面背景去掉底部珍珠白渐变并降低樱花粉强度，canvas 调为更干净的 #FDFBFA；Today 进度环由远山蓝改为葡萄紫渐变，复习计划标签由玫瑰珊瑚改为主紫色。侧边栏品牌区原本被 VStack 默认居中，现与导航行、底部 LOCAL FIRST 卡片共用 `SidebarMetrics` 网格（行边距 11pt、图标列 21pt、标题 63pt，品牌图标按 macOS 图标约 9.8% 透明边距补偿）。App 图标用 `Scripts/recolor_icon_romantic.swift` 逐像素重新着色为葡萄紫底、珍珠白折页、樱花粉记忆入口，保留原造型、纸纹和投影；原图备份在 `IconConcepts/Romantic2026`。未签名预览构建通过；Dock 可能缓存旧图标。
- 2026-11-20：按“再高级、丰富一些”的反馈做编辑式精修：页面标题、品牌名、词条大字和统计数字统一改用衬线显示字体（`AppTheme.display`，系统 New York / 中文宋体回退），眉标改为细线加 3.2 字距衬线小字；卡片与 hero 改为环境光 + 主光两层柔和阴影，图标徽章改为同色渐变底加细描边。Today 在 hero 加入日期行，并新增三块全部来自本地真实数据的内容：「近 7 天复习」（次数 + 7 日柱状，今天高亮樱花粉）、「连续学习」（截至今天或昨天的连续复习天数）、「已熟悉」（熟悉+已掌握词义 / 全部词义）；「Memory Garden」按待学习/学习中/熟悉/已掌握展示词义分布条；当天没有新词时「Recently Added」回退展示最近 5 个词，不再空白。当前真实复习记录最后一次为 2026-09-22，故前两块如实显示 0。
- 2026-11-20：按“现在偏极简，再复杂一些”的反馈加入取自参考图的程序化装饰（`DesignSystem.swift` 末尾，固定随机种子，每次启动构图一致）：`WisteriaOrnament`（顶部藤蔓与羽状叶、弯曲花梗、上宽下窄由淡丁香过渡到深葡萄紫的蝶形小花串，偶有樱花粉点缀）、`PetalScatter`（樱花瓣）、`AppPaletteChips`（四色色卡）、`AppOrnamentDivider`（细线·❦·细线）。页面标题右侧加色卡与「Romantic Garden · 浪漫」衬线斜体署名，副标题改衬线；`AppSectionHeading` 改为参考图式「标题 | ———」渐隐细线；`appHeroCard` 加顶部四色细带、内嵌双线卡纸边框、紫藤与花瓣——紫藤只占文字区（左 380pt）与右侧圆环区（140pt）之间的空白并左侧渐隐，卡片过窄时自动隐藏，避免压字；页面背景只保留右下角淡花瓣。验证方式：`Scripts/render_design_preview.swift` 可脱离 App 用 ImageRenderer 把组件渲染成 PNG（终端无屏幕录制权限时也能看图），已在 900/700pt 宽度检查无压字。
- 2026-11-20：用户反馈首页“印花看上去像乱码”。按真实窗口宽度（hero 约 708pt）离屏渲染确认：可用空白仅约 188pt，紫藤被左侧渐隐和顶部边框裁成零碎小点。已删除 `WisteriaOrnament`、`PetalScatter` 及随机数生成器；`appHeroCard` 新增可选 `watermark`，Today 传入当天日期两位数，以 150pt 衬线斜体、淡丁香→樱花粉渐变绘制在文字区与圆环之间并从底边出血（呼应参考图的大号“05”），空白不足 130pt 时不画。教训：程序化细碎花纹在不同宽度下会被裁成噪点，装饰应优先用整块、可缩放、不依赖可用宽度的形状，并在真实窗口宽度下渲染验证。
- 2026-11-20：用户认为“20”日期底纹也丑，要求参考获奖设计。参考 2025 Apple Design Award「Delight and Fun」得主 CapWords（语言学习：把真实词语做成可收集的实体词卡、强调卡片过渡与感官反馈）及「Visuals and Graphics」评审标准（精心绘制的界面、统一鲜明的主题），结论是“让内容本身成为视觉主角，而不是加装饰”。已删除 watermark 与 Today 进度圆环（分钟数已在按钮上），新增 `WordCardFan`：今天真正要复习的前 3 个词义（最逾期优先，其次是额度内新词义）做成贴纸式词卡扇形——白色粗描边模切边、两层阴影、珍珠白/樱花粉/淡丁香底、衬线词条、序号 01–03；只有最前一张显示词条以免后排露出残字；悬停时弹簧动画展开；下方衬线斜体“还有 N 个词义在等你”。已在 772/1000pt 宽度离屏渲染检查。
- 2026-11-20：另做了 B–H 七个 hero 备选（单词聚光、星图、词束、填空句、书架、逾期点阵、票根，均离屏渲染、未进 App），用户仍选 A 词卡扇，但指出大卡“颜色有些乱”并希望加手绘。原因：淡丁香斜向底色 + 右上樱花粉光晕 + 顶部四色细带，再叠同色系词卡，色源互相竞争、词卡与底色融在一起。修复：`appHeroCard` 底色改为单一纸色（白→#FFF9F5），去掉光晕与四色带，只保留卡纸内框细线——颜色只由卡上内容承担（Library 详情卡同样受益）。新增手绘涂鸦（`DesignSystem.swift`「Hand-drawn doodles」）：`HandUnderline`（双笔马克笔下划线，用于“24”）、`HandArrow`（从“还有 N 个词义在等你”指向词卡的弧形箭头）、`Sparkle`（内凹四角星）、`Sprig`（线描枝叶，藏在卡堆左后）、`WashiTape`（半透明樱花粉和纸胶带，撕边 + 细斜纹，斜贴在首张词卡左上角）。全部是连续线条或整块形状，手绘抖动用平滑正弦而非随机点，避免再次出现“乱码”观感；已在 772/1000pt 宽度离屏检查。
- 2026-11-20：用户反馈“整体页面很乱”，要求从零重看。审计发现 Today 同时使用约 11 种颜色、9 类装饰（背景光晕、色卡署名、粉色字距眉标、卡纸框、下划线、枝叶、星光、箭头、和纸胶带、❦ 分隔、标题渐隐线、渐变图标徽章）和衬线/斜体/无衬线混排——每轮迭代只加不减。重设并固化规则（新增设计时须遵守）：① 颜色＝墨色＋纸色＋唯一强调色葡萄紫；樱花粉只用于“新”和胶带，淡丁香只用于轨道和卡背；② 衬线只用于页面标题、大数字和词条，其余一律无衬线、不用斜体；③ 装饰预算只有一个——首张词卡上的和纸胶带。实现：`AppPageHeader` 只剩眉标/衬线标题/副标题（Today 眉标即日期）；`AppSectionHeading` 去掉徽章与渐隐线；`appHeroCard` 改为白纸卡＋细描边＋柔和阴影，并删除 tint 参数（Library/Statistics/ReviewSession 调用同步）；`appPageBackground` 改为纯 canvas；删除色卡、❦ 分隔与所有涂鸦组件。Today 结构：页眉 → 词卡扇 hero（词卡同色系：白→淡丁香，后排不显示词条与语言标签）→ 一张「节奏」卡三栏（近 7 天复习+单色柱、连续学习、已熟悉，竖线分隔，无图标）→ 宽度够时「学习阶段」（单色紫阶分段条＋图例）与「最近收录」（衬线词条＋释义＋时间，无彩色徽章）并排等高、不够时纵向堆叠。`Scripts/render_design_preview.swift` 已改为镜像整页 Today 布局，用于离屏检查（772/1100pt 已验证）。
- 2026-11-20：用户希望在克制基础上加“动态 / 手绘 / 油画”元素。做法：三者合并成 hero 里唯一的“签名时刻”——词卡放在一抹油画笔触上，其余页面保持安静（装饰预算仍只给 hero）。新增 `ImpastoStroke`：先填不透明笔触主体（淡丁香→葡萄紫→樱花粉竖向调色），再叠 120 条顺笔向的明暗鬃毛纹、6 条高光脊线；起笔为四分之一圆的饱满圆头，收笔不收尖而是散成干刷丝（多次离屏渲染迭代：最初像蜡笔线→改主体＋纹理；两端平切→圆角；整体变杏仁形→改为不对称起收笔；加圆帽像灯泡→改为宽度曲线圆起笔）。`WordCardFan` 新增 `animatesIn`：首次出现时笔触由左向右“刷出”（0.7s），随后词卡由叠放弹簧展开成扇形；系统开启“减少动态效果”时直接显示最终状态；悬停展开保留；和纸胶带保留。笔触偏左下露出，起笔在卡左、干刷尾在卡右下。离屏渲染只能检查最终静态构图，入场动画需在 App 中目测。
- 2026-11-20：用户不喜欢油画笔触（“那一笔粗的痕迹太丑”），已删除 `ImpastoStroke` 及刷出动画；保留词卡扇的入场弹簧展开（0.15s 后，从叠放展开成扇形，减少动态效果时直接显示）、悬停展开和和纸胶带。教训：用户对首页的大块程序化装饰（紫藤、日期水印、油画笔触）三次否定，后续优先改进内容与排版，新增装饰前先离屏渲染给用户看效果图再进 App。
- 2026-11-20：在效果图中选了“手写批注”方向，并要求更多油画感。试过油画小人（书本形小书签助手）和三款可爱版（葡萄团子、小猫书童、胖胖书本）后，用户决定不要人偶。最终把手写批注放进 hero：`PaintedHandNote` 用手札体（HannotateSC-W5）写「先从这三个 / 开始吧」，字形用 `PaintTexture` 的油画笔触点染（葡萄紫底，樱花粉亮笔、深紫暗笔），旁边是一支起笔粗、收笔细的 `BrushArrow` 指向词卡。动态：词卡扇展开后（约 0.55s）文字淡入上浮，箭头从尾到头“刷出”；减少动态效果时直接显示。文案随词卡数量变化（一个/两个/三个）。布局用 `ViewThatFits`：宽窗口批注在词卡左侧并带箭头；窄窗口（实际约 772pt）放在词卡下方，单行、不带箭头，下面仍是“还有 N 个词义在等你”。772/1100pt 离屏渲染已检查。

## 4. 第一版范围完成情况与已知边界

### 已确认的后续产品路线（2026-09-01）

用户确认采用以下产品与隐私决策；后续实现必须以此为准：

- 保持“行动优先”的前台体验。排期与历史时间优先显示为“现在该复习、明天、X 天后、刚刚、X 天前”，完整日期只作为悬停或编辑态的辅助信息。
- 保持复习答案中的完整记忆线索展示，不因信息减法而折叠或省略。
- 不在 Statistics 中展示由用户自评评分推导的记住率、留存率或类似百分比；统计应提供复习节奏、词库阶段和可行动的回看建议。
- 相遇轨迹采用隐私克制的默认值：默认仅本地保存选中原句、时间和来源应用名；页面标题和 URL 默认不保存，必须由用户主动开启后才保存。
- 多词义采用独立复习方案：一个词条可包含多个 sense，每个 sense 具有独立释义、记忆线索、相遇记录和 FSRS 状态；不能因掌握一个词义而将整个多义词视为已掌握。

实现必须分四个兼容切片推进：

1. ✅ 领域与数据库基础：已追加 `encounters`、`senses` 和 sense 级复习状态/日志表；未修改已发布迁移，未删除词卡或历史复习数据。旧卡迁移为一个主 sense，旧的创建时间生成一条本地“首次收录”轨迹；历史 `encounter_count` 无来源信息，不伪造多条轨迹。过渡期主词义与旧卡片复习状态/日志双写。
2. ✅ 收词与相遇体验：Quick Add 自动保存来源应用名，并允许生成后补充原句作为本地相遇记录；遇到已有词时追加轨迹并显示“已有词义 / 可能新词义”的确认，不自动采集标题或 URL。Chrome/PDF 只选单词时周边整句仍需用户主动粘贴，不通过扩大屏幕读取权限绕过该隐私边界。
3. ✅ Library 与复习迁移：词条详情展示“在 X 个场景遇到”，按需展开轨迹；复习队列已改为 sense 级项目，并保留旧卡的完整排期和日志可读性。
4. ✅ 学习诊断与自适应题型：使用到期、遗忘、难度、词义/语境覆盖等客观信号给出少量下一步建议；不把评分汇总为竞争式分数。听音、语境、易混和拼写题型只在相应诊断有价值时出现；表达题型保留到成熟阶段的“今日表达”。

每个切片都需要：追加 migration、Core/Repository 测试、真实旧库只读验证、可恢复备份与 UI 验收。任何会把既有 card 级 ReviewState 拆分为多个 sense 状态的迁移，必须先创建备份并单独核验历史日志映射。

原始需求的 P0 和 P1 已完成：本地数据库、手动/快捷采词、独立 Quick Add、Gemini 结构化生成、语言范围去重、FSRS、Today、Library/详情/编辑、通知、Settings/Keychain、基础统计、菜单栏、更多筛选和标签管理均已落地。

以下不是第一版阻塞项，保留为后续增强：

- System Services / 右键“添加到单词记录本”；目前全局快捷键 + Accessibility/剪贴板 fallback 是主入口，稳定性和可诊断性更高。
- `Command + K` 命令面板、连续学习天数、按标签/语言统计拆分。
- 旧数据批量 AI 补全、保存后的 Undo；语音后续可补语速/声音选择与自动朗读开关。
- 用户仍需亲自在目标 Mac 上完成通知授权，并在真实 Chrome/PDF 环境做一次端到端权限验收。

### 专业产品视角新增建议（首轮需求未明确）

- **旧数据一键补全**：数据健康检查已能发现缺失字段与未打标签词卡；后续可增加逐条或批量 AI 修复。
- **可选保存来源上下文**：保存原句、应用名、页面标题或 URL，让用户记住“在哪里遇见它”；必须默认克制、明确展示将发送给 AI 的文本，并允许只存本地。
- **系统语音发音**：优先使用 macOS 本地语音合成提供英语/日语朗读和复习键盘快捷键，成本和隐私风险都低于接入外部音频服务。
- **Undo**：快捷收词已有非打断式保存成功反馈；后续可增加短时间撤销。

### Future（不是当前 MVP 阻塞项）

- CSV 导入、Notion 导入、完整数据库备份恢复（CSV 导出已实现）。
- iOS/Android 复习端、账号、云同步、订阅。
- 浏览器扩展、上下文挖空、听写/拼写、AI 学习分析。

## 5. 产品优先级建议

### 下一开发切片（推荐）

四个兼容切片均已完成。下一阶段先做 **真实使用稳定化**：重点观察自适应题型是否过于频繁、Chrome/PDF 选区与原句补录、提醒权限 onboarding、多词义误匹配和语音首尾完整性；只根据真实问题校准规则，不继续堆功能。随后再做旧数据批量补全、数据库备份恢复和成熟阶段的“今日表达”。

### 随后顺序

1. 根据真实使用反馈做 bugfix、Accessibility/通知 onboarding 和文案校准。
2. 若准备公开发布，补正式开发者签名/公证、隐私说明、沙箱能力审计和匿名错误遥测选择。
3. 再评估 System Services、语音、批量 AI 补全和 Command Palette。
4. 移动端/云同步仍属于后续独立阶段。

## 6. 后续开发约束

- 保持 UI / Core / Persistence / AI 分层，不在 SwiftUI View 里直接写 SQL 或供应商请求。
- 供应商能力继续通过 `AIProvider` 抽象；API Key 永不写入源码、日志、README 或本文件。
- ReviewLog 保持 append-only；改变排期必须通过 ReviewSessionRepository。
- 所有 schema 变化使用追加 migration，不修改已经发布执行过的 migration。
- 修改全局快捷键和签名配置时，优先保护 Accessibility TCC 稳定性。
- 新功能至少覆盖其纯逻辑和 Repository 层；重要 SwiftUI 流程补 ViewModel 测试。
- 做完一个产品切片后，更新“已实现”“未完成”和验证基线，避免项目记忆失真。

## 7. 交接状态核对（2026-11-19）

- 新增 [`AGENT_HANDOFF.md`](AGENT_HANDOFF.md) 作为新 agent 的快速入口；其中列出工程地图、数据/隐私不变量、构建命令和历史验证的适用范围。
- 本次核对了文档、源码目录结构、迁移入口、测试目录及 Build App 软链接，没有启动/修改应用和数据库。
- 随后重新验证：`swift test` 63 tests / 14 suites 全部通过；`xcodebuild ... CODE_SIGNING_ALLOWED=NO` Debug 构建成功（仅 AppIntents 元数据跳过警告）。
- 当前目录不含 Git 元数据，无法核对提交、分支或工作区改动；源码文件时间集中在 2026-09-11。测试与未签名构建已在 2026-11-19 重新确认；稳定本地签名及安装版与源码一致性仍为 2026-09-11 的历史验证，本次未重新验证。
- `Build/单词记录本.app` 是指向 `/Applications/单词记录本.app` 的软链接；该事实不证明安装版与当前源码一致。`Build/` 中的 SQLite 文件是迁移备份，按可能含真实个人数据处理。
- 本次未发现明确记录在案的 2026-09-11 之后实现状态或新优先级；开始新功能前应继续以用户当前要求为准，并在完成后记录真实验证结果。
