# Changelog

## 1.3.1 (2026-11-15)

- 仓库/技能更名为 `arknights-copilot-kit`（原名 `arknights-maa` 容易被误认为 MAA 本体或官方分支）
- README 顶部增加定位说明：本仓库是围绕 MAA 的外围驱动套件，不包含、不修改 MAA
- 依赖表述改为通用「AI agent 客户端」（WorkBuddy / Claude Code / Cursor / Codex CLI 均可），不再绑定单一客户端
- 明确「只操作 MAA、不直接操作游戏」：**连游戏启动都交给 MAA 的「开始唤醒」**，脚本不 `am start`；仅剩两处用 adb（截图 / 导航到详情页）
- `maa_launch.ps1` 默认不再启动游戏，新增 `-StartGameViaAdb` 作为逃生口
- 新增「谁在做什么（AI 侧 vs MAA 侧）」职责表：明确 AI 只碰 MAA 界面与配置，游戏内操作全由 MAA 完成
- 新增「风险与合规」：只做输入注入，给出降风控建议（间隔 0.3~0.5s、控制时长、不多开）
- 环境说明改为「推荐安卓模拟器」（真机 adb 理论可连但未验证）；补充说明**明日方舟 PC 版不保证能接上**（无 adb 通道，未验证）

## 1.3.0 (2026-11-15)

- 新增 `maa_connect.ps1`：MAA 侧连接设定（等模拟器 adb → 探测可用地址 → 必要时改配置 → 校验 `截图耗时` 才算连上）
- 新增 `maa_daily.ps1`：日常一条龙（唤醒 / 理智作战 / 基建换班 / 自动公招 / 信用收支 / 领取奖励 / 更新数据），
  `-ApplyOnly` 只写配置、`-Attach` 用已运行的 MAA 点 `Link Start!` 并盯到完成
- 新增 `maa_launch.ps1`：一键拉起模拟器 + 游戏 + MAA（含 headless 检测）
- 理智药：`-UseExpMedicine` 才启用「24h 内过期自动使用」，默认一瓶不动
- 路径改为三级解析：`maa_config.local.ps1` > 环境变量 > 自动探测；新增 `.gitignore`、`LICENSE`、`maa_config.local.example.ps1`
- 修复：adb 状态判断用 `-match 'device'` 会把 `device offline` 误判为已连接
- 修复：`完成任务: 自动战斗` 曾被当成过关（现在明确「需回地图确认节点变灰」）

## 1.2.0 (2026-11-15)

- 新增 `maa_clean.ps1`（清截图缓存）；`maa_diag.ps1` 增加「需专三清单」；`find` 打印需专三干员
- 脚本迁到技能目录自包含，D 盘改为转发入口

## 1.1.0 (2026-11-14)

- 新增 `maa_guard.ps1`：作业加载校验、开关强制勾选并读回、卡住/报错自动重开、战斗中 300s 静默宽限
- 试错预算：同一关最多 3 次 / 3 份作业，超了必须停下出缺口报告

## 1.0.0

- 初版：`maa.ps1`（体检 / 找作业 / 装作业 / 等待）+ 抄作业执行手册
