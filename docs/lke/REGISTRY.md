# 定制登记表（LKE customs registry）

每个定制一行登记，配合源码内 `// LKE-CUSTOM(LKE-xxx):` 标记与
[CUSTOMIZING.md](CUSTOMIZING.md) 的同步流程使用。状态取值：
`在库` / `上游化`（上游已采纳，本地 hunk 移除）/ `退役`（业务废弃）。

| ID | 状态 | 动机 | 上游对应 | 涉及文件 | 冲突风险 |
|----|------|------|----------|----------|----------|
| LKE-001 | 在库 | 人工发送消息修复：`escalate_to_human`/`ask_user`/`poll` 的 `recipient` 在 v0.8.7 发送点硬编码空串，聊天型渠道拒收（telegram "chat_id is empty"、lark "invalid receive_id"），转人工提示无法送达 | 上游未修；补丁曾存档于桌面仓 `docs/zero-engine/patches/v0.8.7-interactive-tools-recipient.patch`（PR 素材） | `crates/zeroclaw-runtime/src/agent/turn/delivery_defaults.rs`、`crates/zeroclaw-tools/src/ask_user.rs`、`crates/zeroclaw-tools/src/escalate.rs` | 低：纯增量（注入函数 + schema 参数 + 透传），不改既有行为；上游若修复即转"上游化" |
| LKE-002 | 在库 | 渠道传递客户真实名：飞书 DM 的 `sender` 是裸 `open_id`，agent 看不到客户姓名；新增可扩展的 `SenderProfile`（`display_name` + `extra` KV），lark 经 contact API 尽力解析并注入 turn-context，为后续传递更多客户信息留通道 | 无上游对应需求 | `crates/zeroclaw-api/src/channel.rs`、`crates/zeroclaw-channels/src/lark.rs`、`crates/zeroclaw-channels/src/orchestrator/mod.rs` | 中：lark 入站构造点与 orchestrator turn-context 前言随上游演进可能漂移，合并时按标记重表达 |

> 新增定制先加行再动代码；上游合并轮按本表逐项核对存活状态。
