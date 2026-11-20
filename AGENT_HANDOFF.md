# Agent 交接说明：单词记录本

> 核对日期：2026-11-19。本文依据当前工作目录中的源码与项目文档整理；并已重新运行包测试与未签名 Debug 构建（结果见“构建与验证入口”）。项目目录目前不含 Git 元数据，因此无法核对分支、提交或工作区差异。

## 接手顺序

1. 先读本文，了解工程入口、重要边界与待核查事项。
2. 再读 [`PROJECT_MEMORY.md`](PROJECT_MEMORY.md)，了解完整产品决定、隐私约束、已完成切片和历史验证记录。
3. 按任务阅读对应源码；不要仅凭 README 中的历史验证数字断言当前源码已通过验证。

## 项目是什么

这是 macOS 14+ 原生、本地优先、隐私优先的 AI 单词采集和间隔复习应用。用户通过手动输入或全局快捷键采词，由 Gemini 生成可编辑词卡，保存到本地 SQLite，并按词义使用 FSRS 6 安排复习。应用当前不提供登录、云同步或付费功能。

## 工程地图

| 路径 | 职责 |
| --- | --- |
| `VocabularyApp/App/` | SwiftUI 页面、ViewModel、应用组装、全局快捷键、Quick Add 浮窗、通知和语音 |
| `Packages/VocabularyKit/Sources/VocabularyCore/` | 领域模型、协议、纯业务规则、统计与诊断 |
| `Packages/VocabularyKit/Sources/VocabularyPersistence/` | GRDB/SQLite、迁移、Repository、FSRS 调度 |
| `Packages/VocabularyKit/Sources/VocabularyAI/` | Gemini Provider、HTTP、Keychain API Key 存取 |
| `Packages/VocabularyKit/Tests/` | Core、Persistence、AI 单元及迁移测试 |
| `VocabularyApp/Resources/Assets.xcassets/` | 正式 App 图标资源 |
| `VocabularyApp/Resources/IconConcepts/` | 图标设计过程与备选稿，不是运行时资源 |
| `Build/` | 旧数据库迁移前备份，以及指向 `/Applications/单词记录本.app` 的本地快捷入口 |

主要入口：

- 依赖装配：`VocabularyApp/App/AppEnvironment.swift`
- 应用与窗口：`VocabularyApp/App/VocabularyApp.swift`、`RootView.swift`
- 统一视觉系统：`VocabularyApp/App/DesignSystem.swift`
- 数据迁移：`Packages/VocabularyKit/Sources/VocabularyPersistence/Database/DatabaseMigrations.swift`
- 词卡与词义持久化：`GRDBVocabularyRepository.swift`、`GRDBVocabularySenseRepository.swift`
- 复习和 FSRS：`GRDBSenseReviewRepository.swift`、`FSRSReviewScheduler.swift`、`ReviewSessionModel.swift`
- AI 结构化生成：`GeminiInteractionsProvider.swift`
- 项目产品记忆：`PROJECT_MEMORY.md`

## 数据与产品不变量

- 词库、相遇记录、复习状态和历史日志保存在本地；Gemini 只接收当前词条和用户主动提供的上下文。API Key 只放 macOS Keychain。
- 一个词条可以有多个 `VocabularySense`。相遇记录必须属于一个 sense；各 sense 独立拥有复习状态和日志。词条整体掌握度按最薄弱 sense 表达。
- 评分日志是追加历史。排期变更应通过 Review Session/Repository 流程，不能直接改写或删除历史日志。
- SQLite schema 采用追加式迁移。已经发布执行过的迁移不可修改；新增结构必须增加迁移并覆盖旧库映射。
- 旧卡片级 review 表仍是兼容层；主 sense 与之双写，次 sense 使用 sense 级记录。不要在未审计读写路径前移除兼容层。
- 不要伪造历史相遇语境。旧 `encounter_count` 没有来源数据，不能展开成多条虚构轨迹。
- 来源应用名、原句和时间可本地记录；默认不采集页面标题或 URL。不要为了方便扩大采集范围或把来源应用信息发送给 Gemini。
- AI 对重复词提出已有/新词义建议，但创建新 sense 必须由用户明确确认；拒绝未知 sense ID。
- 统计不得把主观评分包装成“记住率/留存率”。优先给出客观学习信号和少量可行动诊断。
- UI 优先复用 `DesignSystem.swift`，保持浅色「浪漫 Romantic」外观（2026-11-19 起取代深色 Wrapped 主题）和既有颜色语义；文字/图标用加深语义色，原色只用于填充与背景。
- 全局快捷键、签名和 bundle identity 可能影响 macOS Accessibility 授权；修改前检查 `LocalSigningRequirements.txt` 与 `PROJECT_MEMORY.md` 的本地签名记录。

## 构建与验证入口

在项目根目录：

```sh
cd Packages/VocabularyKit
swift test

cd ../..
xcodebuild -project VocabularyApp.xcodeproj -scheme VocabularyApp -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

2026-11-19 复核结果：`swift test` **63 tests / 14 suites** 全部通过；未签名 Debug 构建成功（仅有 AppIntents 元数据跳过的无害警告）。稳定本地签名与 `/Applications` 安装版的一致性仍只有 2026-09-11 的历史记录，本次未重新验证。做完代码修改后，根据任务范围运行相关测试/构建，并同步更新 README 与 `PROJECT_MEMORY.md` 的真实结果。

`Build/单词记录本.app` 当前是指向 `/Applications/单词记录本.app` 的软链接，不是项目内可独立分发的构建产物；不能仅凭该路径存在就断言安装包与源码一致。

## 当前已知状态与接手建议

- 源码树当前可见的最近文件时间集中在 2026-09-11；当前目录没有 `.git`，无法判断之后是否有其他版本或未保存的源码变更。
- README 和项目记忆详细记录了 M0–M4、多词义、相遇轨迹、自适应题型、复习提醒、登录启动项等实现；近期用户反馈和 2026-09-11 之后的产品决定没有体现在这些资料里，接手新需求时先以用户当前指令为准。
- 项目记忆建议的下一阶段是稳定化：观察自适应题型、Chrome/PDF 选区与原句补录、提醒 onboarding、多词义匹配和发音可靠性；之后再考虑批量补全、完整备份恢复和“今日表达”。这些是历史优先级建议，不是已排定任务。
- `Build/` 内含真实数据迁移前的 SQLite 备份。把它们视为可能含有用户数据的敏感文件；不要打开、复制、上传、覆盖或清理，除非任务明确需要且确有授权。
- 没有明确请求时，不要安装、覆盖 `/Applications` 中的 App，不要改用户真实数据库，也不要触发会改变 Accessibility、通知或登录项状态的 UI 操作。

## 文档维护

完成一个功能切片后，更新 `PROJECT_MEMORY.md` 中的实现状态、已知缺口和验证基线；若改变接手流程或工程入口，再更新本文。README 面向使用者，保持简洁并只记载已核实的构建和使用信息。
