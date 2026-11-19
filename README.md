# 单词记录本

macOS 原生的本地优先单词采集与间隔复习应用。

Agent 接手时先阅读 [`AGENT_HANDOFF.md`](AGENT_HANDOFF.md) 获取项目入口、架构地图和安全约束，再阅读 [`PROJECT_MEMORY.md`](PROJECT_MEMORY.md) 查看完整产品决策与历史记录。交接文档会区分已核对的代码事实和仍需重新验证的历史基线。

本机验收构建位于 [`Build/单词记录本.app`](Build/单词记录本.app)，可直接双击运行。它是带稳定本地签名的 Debug 构建，用于个人测试；公开发布前仍需 Apple Developer 正式签名与公证。

## 当前里程碑

M0–M4：

- 工程骨架、领域模型、term normalization 与 mastery policy
- GRDB/SQLite schema、默认标签与核心 CRUD
- 手动添加单词与可编辑 AI 词卡确认
- 生成前重复检测与 Add Encounter
- 相遇记录底座：每次记录可归属具体词义，并保存本地原句、来源应用与时间
- 多词义底座：一个词条可拥有多个独立词义、记忆线索、相遇记录和 FSRS 状态
- 重复词根据原句建议归入已有词义或创建新词义；新词义始终需要用户确认
- Library 按词义展示释义、例句、记忆线索、相遇轨迹和独立学习状态；一个词条的总体状态取最薄弱词义
- Today、提醒和 Review Session 已迁移到词义级队列；同一拼写的不同词义会分别出现、分别评分和排期
- 可替换 `AIProvider`、Gemini Interactions API 严格 JSON Schema 输出
- Gemini API Key 的 macOS Keychain 存储
- 保存后自动刷新的 Today、Library 与基础 Statistics
- Statistics 使用词义级口径展示学习阶段、到期、本周节奏和 7/30 天活动图，不用自评分数包装成“记住率”
- 学习诊断只根据反复遗忘、持续难度、逾期、语境覆盖和内容完整度给出少量可行动建议
- Library 搜索、Language / Tag / Mastery / Due Status 筛选及五种排序
- Library 标签展示、完整详情、词卡编辑与确认删除
- Gemini 自动生成 IPA 音标与可靠的“记忆线索”；旧词可单独补充音标，记忆线索支持“有帮助 / 换一种记法”
- 官方 FSRS 6 间隔调度（固定 vendored 源码提交）
- 英→中 / 中→英复习模式、显示答案与四档评分
- 默认自适应复习会为确有需要的词义选择主动回忆、听音辨义、语境填空、拼写回忆或易混辨析；手动英→中 / 中→英仍可随时切换
- 每次复习会话随机打乱卡片顺序；英→中与中→英都会在新卡出现时自动朗读词条，并可用 `Listen Again` 随时重播
- 选择“忘了”的词义会回到本轮队尾再次巩固，不会提前显示完成；退出复习后 Today 会立即刷新最新到期数量
- `Space` 显示答案，`1`–`4` 快速评分
- 评分后原子更新复习状态并追加不可变 ReviewLog
- Settings 可配置每日新词义额度，并根据当天首次学习记录严格扣减
- macOS 每日复习提醒、通知权限状态、提醒时间与“仅到期时提醒”
- 点击提醒后自动进入 Today 并打开复习会话
- Today 到期队列与 Statistics 当日复习、记住率、最近历史
- Chrome、Safari、PDF 等应用中的可配置全局快捷键快速采词
- 辅助功能选中文字读取，以及 `Command + C` / 剪贴板 fallback
- 独立轻量 Quick Add 浮窗、Enter 保存、Esc 关闭与保存成功反馈
- Gemini 自动重试、API Key 连接测试、词卡 AI 重新生成
- 自定义标签创建/重命名/删除与系统标签保护
- macOS 菜单栏 Quick Add / Review Today / Settings 入口
- Settings 可使用 macOS 原生登录项开启或关闭“登录时自动启动”，并显示已启用、未启用或等待系统批准的真实状态
- 数据健康检查与包含学习元数据的 CSV 导出
- 深茄紫与暖象牙纸张构成的原生 macOS App Icon：一个统一折页同时表达“打开的词页、书签与进入记忆”，完整覆盖 16–1024 px 图标规格
- Spotify Wrapped 启发的沉浸式多色设计系统：黑色侧边栏与炭灰内容层作为舞台，酸性绿、亮紫、粉色、橙红、湖蓝和暖黄按内容语义组合；Today、Library、Statistics、Settings、添加/编辑和复习会话已完整统一

## 使用手动添加

1. 在 Xcode 运行 `VocabularyApp`。
2. 在 Google AI Studio 创建 Gemini API Key，然后打开 `Settings` 在 AI 区域保存。
3. 点击工具栏 `Add Word` 或按 `Command + N`。
4. 输入单词或短语，可选填上下文，生成后修改字段与标签并保存。

## 从浏览器或 PDF 快速添加

1. 重新运行应用后，在 `Settings > Quick Add` 请求辅助功能权限。
2. 在 Chrome、Safari 或 PDF 中选中单词或短语。
3. 按默认快捷键 `Control + Option + W`，Add Word 会自动带入选中的文字。
4. 如果当前应用不提供可访问的选中文字，先按 `Command + C`，再按全局快捷键。

可以在 `Settings > Quick Add` 更换快捷键。默认不再使用 `Option + Space`，避免与 ChatGPT 的快速对话快捷键冲突。

App 在前台时还可以按 `Command + Shift + N` 打开 Quick Add；菜单栏图标也提供同一入口。Quick Add 中按 Enter 执行当前主要操作，按 Esc 取消。

项目为没有 Apple Development 证书的本地 Debug 构建配置了稳定的 designated requirement。首次切换到该签名后，需要在“系统设置 > 隐私与安全性 > 辅助功能”删除旧的单词记录本条目，再从 App 请求一次权限；后续重新构建不会再因临时代码哈希变化而丢失授权。

`Command + N` 是应用内快捷键；当 Chrome 在前台时，它仍然表示新建 Chrome 窗口。

## 使用间隔复习

1. 打开 `Today`，点击 `Start Review`。
2. 默认使用“自适应”；也可手动选择 `英 → 中` 或 `中 → 英`。按空格显示答案。
3. 使用按钮或数字键 `1`–`4` 选择“忘了 / 模糊 / 记得 / 很熟”。
4. 返回 `Today` 查看更新后的到期数量，或在 `Statistics` 查看复习历史。

队列优先包含已经到期的旧词义，并按 `Settings > Review > 每日新词义` 的额度加入新词义；同一拼写的不同词义是独立学习单元，分别拥有例句、记忆线索、相遇轨迹和 FSRS 排期。进入会话后会随机打乱本轮全部词义。选择“忘了”时，FSRS 会安排短时再次学习，该词义同时回到本轮队尾并标记“再巩固一次”；随后选择“模糊 / 记得 / 很熟”才算完成本轮，不会出现刚完成又立即提示待复习的错觉。默认自适应模式会从客观学习信号中选择主动回忆、听音辨义、语境填空、拼写回忆或易混辨析；新词先使用普通识别，不会过早增加难度。全部题型保留 IPA 和自动朗读，点击 `Listen Again` 可随时从头重播。答案前可按需查看渐进提示，揭晓后会展示当前词义的完整记忆线索。当天已首次学习的新词义会自动占用额度，多次开启会话不会绕过上限。

## 开启复习提醒

1. 打开 `Settings > Review`，开启 `Daily Reminder`。
2. 选择提醒时间；如果只想在旧词到期时收到提醒，保持 `Only notify when learned words are due` 开启。
3. 点击 `Save Review Settings`，并在 macOS 首次询问时允许通知。
4. 点击收到的提醒会打开 `Today` 并直接进入复习。

如果通知权限显示为“未授权”，可从同一区域打开系统通知设置，允许后返回 App 点击刷新。提醒会滚动安排未来 14 天，并在 App 激活、词库或复习数据变化后自动更新。

## 登录时自动启动

打开 `Settings > 启动与后台`，开启“登录时自动启动”。该选项直接由 macOS 登录项管理，不需要额外后台辅助程序；如果系统状态显示“等待系统批准”，点击“打开登录项设置”并允许单词记录本，然后返回 App 重新检查。

## 管理与备份

- 在 `Settings > Tags` 创建、重命名或删除自定义标签；默认标签不会被误删。
- 在 Library 的词条编辑页选择 `Regenerate with AI`，可重新生成音标、释义、例句、记忆线索和推荐标签，复习历史不会重置；旧词缺少音标时也可在详情中单独补充。
- 在 `Settings > Data & Privacy` 检查缺字段/未打标签词卡，并导出 CSV 本地备份。

词卡、标签和复习状态只存储在本机。生成词卡时仅发送当前词条和用户主动填写的上下文。

## 本地验证

```sh
cd Packages/VocabularyKit
swift test

cd ../..
xcodebuild -project VocabularyApp.xcodeproj -scheme VocabularyApp -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

验证基线：63 tests / 14 suites；覆盖 v8 → v9 合成旧库迁移、真实词库副本迁移、多词义 CRUD、指定词义相遇记录、词义级队列与每日额度、主/次词义独立复习、“忘了”后本轮重排队、客观学习诊断、题型选择与题型日志持久化、Gemini 重复词义匹配和未知 ID 拒绝验证；2026-09-11 时 Debug App 完整编译并保持稳定本地签名。2026-11-19 交接复核：当前源码 `swift test` 63 tests / 14 suites 全部通过，未签名 Debug 构建（`CODE_SIGNING_ALLOWED=NO`）成功；本次未重新验证本地签名，也未安装到 `/Applications`。

界面组件集中在 `VocabularyApp/App/DesignSystem.swift`：颜色、页面标题、信息卡、标签、图标徽章、主/次按钮与输入框表面都应优先复用这里的定义，避免后续页面重新引入浅色表面、系统蓝或不一致的灰色层级。

视觉原则是“沉浸、高对比、有节奏但不随机”：主任务使用双色 `appHeroCard` 和克制的循环图形；普通内容使用炭灰 `appCard`；同一层级的数字优先放进连续数据带。绿色用于主操作，紫色用于词库，橙色用于统计/学习压力，蓝色用于信息，粉色用于最近活动，黄色用于新内容或提示。

图标设计源文件位于 `VocabularyApp/Resources/AppIcon-master.png`：深茄紫底色承托一枚暖象牙色连续折页，正形像打开的书，中心负形像书签，并以一小块低饱和柿橙标记“进入记忆”的瞬间。设计遵循单一强隐喻、少量形状和小尺寸清晰度原则，不再使用 `W`、卡片堆叠、霓虹折射或厚重玻璃。Xcode 使用 `VocabularyApp/Resources/Assets.xcassets/AppIcon.appiconset` 中的完整 macOS 尺寸资源；本轮源图、第一稿和旧版备份保存在 `VocabularyApp/Resources/IconConcepts/AppleDesignAwards2026`，更早的 Wrapped 方案仍保存在 `VocabularyApp/Resources/IconConcepts/SpotifyWrapped`。
