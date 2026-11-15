# arknights-copilot-kit · 明日方舟抄作业自动化套件（基于 MAA）

用 [MAA](https://github.com/MaaAssistantArknights/MaaAssistantArknights) 的「自动战斗 / 抄作业」功能，配一套 PowerShell 脚本把关卡稳定打掉：脚本负责装作业、勾开关、盯日志、卡住就重开，失败后还会告诉你**到底缺什么**（等级 / 干员 / 专三）。

> **本仓库不是 MAA 本体**，是围绕 MAA（MaaAssistantArknights）做的外围驱动套件，不包含也不修改 MAA。
>
> **它只操作 MAA，不直接操作游戏。**
>
> - 打关、日常、抄作业：**全部是「点 MAA 的按钮」**（Windows UI 自动化），由 MAA 自己按作业去点游戏
> - 脚本本身**不做战斗操作**：不注入、不改内存、不读包体、不模拟战斗中的点击
> - **连游戏启动都交给 MAA**：MAA 的第一个任务「开始唤醒」会自己把游戏拉起来并进主界面，
>   脚本不需要、也不应该用 adb 去 `am start` 游戏
> - 只剩两处需要用 adb：**截图**、**把界面点到关卡详情页**（MAA 不会自己导航）。这两步你手点也完全一样
> - 想做到「零接触游戏」，跑到「MAA 已连上」就停，剩下全程手点即可

## 为什么会有这个 / 适合谁

**给"没时间但还想稳住日常"的人。** 每天的活动关、突袭、基建换班、公招、信用购物、领奖励，加起来 20~40 分钟，交给它跑，你只负责看一眼结果。

**用你手上现成的 AI agent 就能跑，不用额外花钱。** 整套东西依赖四样：MAA（开源）、安卓模拟器（免费）、adb（模拟器自带）、**任意具备 agent 能力的 AI 软件**——WorkBuddy、Claude Code、Cursor、Codex CLI 这类能"跑脚本 + 操作 Windows 界面"的都行，用你已有的额度即可，不需要订阅、不需要买第三方服务。
没有订阅、没有云手机、没有第三方代练账号；脚本全在本机跑，理智、石头、抽卡资源都不出你的机器。

**需要较高练度 —— 这是设计前提，不是缺点。** 「抄作业」本质是照着别人的阵容复现打法：作业多为**专三 + 精二高等级**，练度够了基本一摆到底、摆完挂机；
练度不够就会卡在「干员不可用：技能等级不足」或漏怪。所以本项目对**老咸鱼 / 回坑玩家 / 一堆精二专三但没时间点的人**最好用。

不适合：新手（干员和专精都缺）、想靠脚本凹高难的人（还是得手动）、完全不想看日志的人（脚本会把失败原因说清楚，但需要你决定换哪份作业）。

## 已知限制（先看这条，能省你半小时排查）

**让 AI agent 替你「启动」模拟器 / MAA 基本行不通 —— 通常是沙箱/权限限制，不是配置问题。**（WorkBuddy 实测：起的 GUI 进程会在工具调用结束时被回收）

- agent 启动的 GUI 进程会在**那次工具调用结束时被回收**：窗口能出来，几秒后就没了（MAA、MuMu、BBChannel 都实测过）
- 想用计划任务（`schtasks.exe`）绕过去，会被程序黑名单直接拦掉（`拒绝访问` + 安全策略提示）
- 所以分工是：**模拟器、MAA 这类界面程序由你自己双击打开**；AI 只负责改配置、点按钮、盯日志、汇报结果

这条不影响任何实际功能，只是「谁来点开程序」的区别。

## 为什么不是「点一下开始就完事」

MAA 自带的抄作业能跑，但实际刷活动 EX / 突袭会踩下面这些坑。本项目就是把这些坑固化成脚本逻辑：

| 坑 | 现象 | 脚本怎么处理 |
|---|---|---|
| 作业加载慢或作业本身坏 | `解析作业文件错误` + `未选择作业`，点了开始什么都没发生 | 填码后校验日志出现「共 N 名干员」，3 次没加载出来就退出并提示「作业坏了」 |
| 开关被覆盖 | 勾了「忽略干员属性要求」，实际是 Off | 等作业加载完再勾，读回状态确认，不对再重试 |
| 编队残留 | 卡在编队页几十秒后 `任务出错: 自动战斗` | 看门狗判卡死，自动停止并重开 |
| 战斗中长时间无日志 | 被误判卡死，把正在打的战斗掐掉 | 出现「当前步骤」后给 300s 静默宽限 |
| 假过关 | 日志 `完成任务: 自动战斗` 其实是输 | 明确提示「≠过关，回地图看节点是否变灰」 |

## 环境与依赖

### 必需软件

| 软件 | 实测版本 | 说明 |
|---|---|---|
| AI agent 客户端 | 任一 | WorkBuddy / Claude Code / Cursor / Codex CLI 等，只要能**执行脚本 + 操作 Windows 界面**；用已有额度，不需要额外付费 |
| MAA（MaaAssistantArknights） | v6.22.0（资源 #1109） | 抄作业内核。必须**普通权限**运行 —— 管理员权限下 UI 自动化读不到控件 |
| 安卓模拟器 | MuMu 12（`nx_device 12.0`） | 夜神 / 雷电 / 蓝叠也能用，只要 adb 能连上。MuMu 的 adb 端口常见 `127.0.0.1:16384`，也可能是 `127.0.0.1:5555` |
| 明日方舟 | B服 2.129.0 / 官服 | B服包名 `com.hypergryph.arknights.bilibili`，官服 `com.hypergryph.arknights`，可用环境变量 `MAA_GAME_PKG` 覆盖 |
| PS 版本 | 5.1（Win10/11 自带） | 不需要 7.x |

**明确不需要**：Python、Node.js、.NET SDK、云手机、任何付费服务、任何第三方代练账号。
脚本只用系统自带能力 + 你机器上已有的 adb。

### 环境细节

- **系统**：Windows 10 / 11 x64
- **分辨率**：模拟器 `1920×1080` 横屏，游戏内 UI 缩放 **100%**。换分辨率后脚本里记的坐标会偏，得自己用截图校准（硬约束，不是 bug）
- **网络**：要能访问 `prts.maa.plus`（作业站）和 `api.maa.plus`（MAA 资源与公告），否则装作业必失败
- **游戏侧**：活动关卡已解锁、干员练度够（作业多为精二 + 专三）、当前理智够打一关
- **推荐使用安卓模拟器**：MAA 靠 **adb** 控制游戏，模拟器天然支持（MuMu 12 实测最稳）。真机开 adb 理论上也能连，但本套脚本的坐标与流程按模拟器 1920×1080 实测，**真机未验证**。
  **明日方舟 PC 版（官方 PC 客户端 / Steam 版）不保证能接上**：它没有 adb 通道，MAA 只能走窗口截图 + 消息注入，
  能否识别取决于 MAA 版本与窗口实现，**PC 版未验证**。
  另外 Windows 版若开了「独占全屏 / 硬件光标」，UI 自动化大概率也会失效。
  结论：想少踩坑就用模拟器；PC 版想试请自备排查能力。
- **权限**：MAA 不要用管理员启动；脚本只做 UI 自动化 + 模拟器内 adb 注入，不读写游戏内存、不碰账号设置

### 首次自检（三道全过再开打）

```bat
REM 1) 环境：三行都必须正常 —— MAA 在跑、adb 是 device、游戏 pid 有值
scripts\maa.ps1 -Action info

REM 2) 网络与作业站：能列出候选作业（含「需专三」标注）
scripts\maa.ps1 -Action find -Query TL-9

REM 3) 干员箱：能出缺口表
scripts\maa_diag.ps1 -Codes 109874
```

## 配置

脚本按顺序解析路径：**`scripts/maa_config.local.ps1` > 环境变量 > 常见安装位置自动探测**。

想省事就在 `scripts/` 下建一个 `maa_config.local.ps1`（已 git-ignore，不会跟着发布）：

```
$MaaRoot = 'D:\MAA'
$Adb     = 'D:\mumu\MuMuPlayer\nx_device\12.0\shell\adb.exe'
```

也可以用环境变量：

```
setx MAA_ROOT        "D:\MAA"                              # 含 MAA.exe 的目录
setx MAA_ADB         "D:\mumu\...\shell\adb.exe"           # adb.exe
setx MAA_ADB_ADDRESS "127.0.0.1:16384"                     # 模拟器 adb 地址
setx MAA_GAME_PKG    "com.hypergryph.arknights.bilibili"   # 官服是 com.hypergryph.arknights
setx MUMU_ROOT       "D:\mumu\MuMuPlayer"                  # maa_launch.ps1 用
```

## 六个脚本

```
# 体检：MAA 进程 / MAA 目录 / adb 状态 / 游戏 pid / 最近任务行
.\maa.ps1 info

# 查作业站候选（额外标出「需专三」的干员）
.\maa.ps1 -Action find -Query TL-EX-4

# 首选执行器：装作业 → 强制勾开关 → 开始 → 看门狗盯着 → 卡住/报错自动重开
.\maa_guard.ps1 -Code prts://109727 -StallSec 90 -MaxRetry 1

# 失败诊断：作业需求 vs 本地干员箱，列等级差、缺失干员、需专三清单
.\maa_diag.ps1 -Codes 109871,109728,109696

# 模拟器由用户手动打开后，接管 MAA 侧连接：等 adb → 必要时改地址 → 起 MAA → 校验「截图耗时」
.\maa_connect.ps1

# 日常一条龙（先问用户刷哪关，再传 -Stage）：唤醒/基建/公招/信用购物/领奖/刷理智
.\maa_daily.ps1 -Stage TL-9

# 若确实需要脚本连模拟器一起拉（本机可能 headless，先看已知坑）
.\maa_launch.ps1

# 扫尾：清截图缓存（本地 %TEMP%\maa-shot + 模拟器内临时图）；-MaaDebug 7 顺带清 7 天前现场图
.\maa_clean.ps1 -DryRun
```

### 日常的固定顺序

1. 先问用户刷哪关（候选见 `data/stages.md`），不要沿用上一次。
2. 请用户手动打开模拟器（脚本拉起在本机可能变 headless）。
3. `maa_connect.ps1` 把 MAA 连上。
4. `maa_daily.ps1 -Stage <关卡>` 跑完日常。
5. `maa_clean.ps1` 收尾。

`maa.ps1` 另有 `job / start / run / status / wait / shot / connect` 子动作，适合手动微操。

### 退出码（maa_guard.ps1）

| 码 | 含义 | 下一步 |
|---|---|---|
| 0 | 任务链结束（**不等于过关**） | 回地图看节点是否变灰 |
| 3 | 超时 | 看现场图，通常是游戏不在详情页 |
| 4 | 作业坏了 | 同关换另一份作业 |
| 5 | 需要人工 | 编队残留、界面状态乱，先收拾 |
| 6 | 开关没勾上 | 重开 MAA 或手动勾一次 |

## 使用规矩（重要）

1. **同一关最多 3 次尝试 / 3 份作业**。3 份都不过就停手，跑 `maa_diag.ps1` 总结缺口，不要无脑重试。
2. **验收只认游戏内证据**：章节地图节点由蓝变灰，或关卡详情页第 4 个突袭图标点亮。`完成任务: 自动战斗` 只说明任务链跑完。
3. **专三要提前讲清**：作业里 `skill_level = 10` 就是专三。`maa_diag.ps1` 会列「需专三清单」；日志出现 `干员不可用: xxx, 原因: 技能等级不足` 就是该干员没到专三，能打但可能漏怪。
4. **打完扫尾**：跑 `maa_clean.ps1`，别让截图堆在 `%TEMP%` 和 `/sdcard`。
5. **不影响用户**：不抢鼠标键盘（只用 UI 自动化和 adb 注入）；不替用户同意好友申请；不动用户的编队预设；中断任务时把游戏停在详情页或地图。

## 干员箱是缓存

`maa_diag.ps1` 读 `MAA\data\OperBoxData.json`（MAA 的仓库识别结果）。刚练起来的干员在这里可能还是旧数据，判定请以 MAA 编队时的实机扫描为准（日志里的 `选择干员: xxx`）。

## 目录结构

```
arknights-copilot-kit/
├─ SKILL.md               # 给 AI 助手看的执行手册（流程、规矩、坑、坐标）
├─ README.md              # 本文件
├─ LICENSE                # MIT
├─ .gitignore
├─ data/
│  └─ stages.md           # 当期刷本关卡候选（换期更新）
└─ scripts/
   ├─ maa_config.ps1      # 路径/端口集中配置（其余脚本 dot-source 它）
   ├─ maa.ps1             # 体检 / 找作业 / 装作业 / 手动开打 / 截图
   ├─ maa_guard.ps1       # 带看门狗的执行器（抄作业首选）
   ├─ maa_diag.ps1        # 作业 vs 干员箱 缺口诊断（含需专三清单）
   ├─ maa_connect.ps1     # MAA 侧连接设定（等模拟器 / 改地址 / 校验截图耗时）
   ├─ maa_daily.ps1       # 日常一条龙（-ApplyOnly 写配置 / -Attach 点开始并盯）
   ├─ maa_launch.ps1      # 一键拉起模拟器+游戏+MAA（本机可能 headless）
   └─ maa_clean.ps1       # 打完清理截图/临时文件
```

## 安装 / 发布

```powershell
# 1) 放进 agent 的技能目录（WorkBuddy 是 ~/.workbuddy/skills/；其它 agent 放任意位置直接用脚本即可）
git clone https://github.com/913688905/arknights-copilot-kit.git "$env:USERPROFILE\.workbuddy\skills\arknights-copilot-kit"

# 2) 自己建本机配置（不入库）
Copy-Item .\scripts\maa_config.local.example.ps1 .\scripts\maa_config.local.ps1
# 编辑里面的 $MaaRoot / $Adb

# 3) 自检
.\scripts\maa.ps1 -Action info
```

打压缩包发布时排除本机配置即可：

```powershell
Compress-Archive -Path .\arknights-copilot-kit\* -DestinationPath .\arknights-copilot-kit.zip -Force
# 或在仓库里 git archive / 打 Release，会自动忽略 .gitignore 里的 maa_config.local.ps1
```

## 免责

- 作业数据来自社区作业站 [prts.maa.plus](https://prts.maa.plus)，版权归各作业作者，本项目只调用公开接口。
- 仅做本地 UI 自动化，不修改游戏数据。请自行遵守游戏用户协议与社区规范，使用风险自负。
- 坐标按 1920×1080 + MuMu 实测，换分辨率或模拟器会偏，需要截图重新校准。
