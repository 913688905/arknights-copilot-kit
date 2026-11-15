<#
  maa_daily.ps1 —— 日常一条龙：唤醒 → 基建 → 公招 → 信用购物 → 领取奖励 →（可选）刷理智
  重要环境约束：**agent 起的 GUI 子进程会在工具调用结束时被沙箱回收**，所以 MAA 必须由用户手动打开。
  因此分两步走：
    ① maa_daily.ps1 -Stage TL-9 -ApplyOnly     # MAA 关着时：备份并写好任务队列，然后退出
    ② 让用户打开 MAA
    ③ maa_daily.ps1 -Attach                    # 用已在运行的 MAA 点「Link Start!」并盯到完成
  用法：
    maa_daily.ps1 -Stage TL-9 -ApplyOnly
    maa_daily.ps1 -Attach
    maa_daily.ps1 -Attach -NoFight
  规矩：不嗑药、不碎石（UseMedicine/UseStone 强制 false）；邮件与免费抽默认不动。
#>
param(
  [string]$Stage,
  [int]$Times = 0,
  [switch]$NoFight,
  [switch]$RestartMaa,
  [switch]$DryRun,
  [switch]$ApplyOnly,
  [switch]$Attach,
  [switch]$UseExpMedicine,
  [int]$TimeoutSec = 2400
)
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
. (Join-Path $PSScriptRoot 'maa_config.ps1')
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

$Cfg = Join-Path $MaaRoot 'config\gui.new.json'
if (-not (Test-Path $Cfg)) { '  ✗ 找不到配置: ' + $Cfg; exit 1 }

# MAA 运行时会覆写配置；改配置那一步必须要求 MAA 关着（-Attach 模式跳过改配置）
if (-not $Attach) {
  $maa = Get-Process MAA -ErrorAction SilentlyContinue
  if ($maa) {
    if ($RestartMaa) {
      '  ! 需要关闭正在运行的 MAA 才能写配置（会中断它当前任务），按 -RestartMaa 执行'
      Stop-Process -Id $maa.Id -Force -ErrorAction SilentlyContinue
      Start-Sleep -Seconds 3
    } else {
      '  ✗ MAA 正在运行，配置会被它覆写。先关掉 MAA 再改配置，或直接 maa_daily.ps1 -Attach 用现有配置开跑'; exit 2
    }
  }
}

# 1) 备份 + 改任务队列（-Attach 模式跳过，直接用 MAA 现有配置）
if (-not $Attach) {
  $bak = Backup-MaaConfig
  '  配置已备份: ' + $bak

  try {
    $cfg = Read-MaaConfig
    $cur = Get-MaaCurrentConfig $cfg
    foreach ($t in $cur.TaskQueue) {
      switch ($t.'$type') {
        'StartUpTask' { $t.IsEnable = $true }
        'FightTask' {
          $t.IsEnable = (-not $NoFight)
          if ($Stage) { $t.StagePlan = @($Stage) }
          # 不嗑普通理智药、不碎石；只有用户明确同意才用「24h 内将过期」的理智药
          $t.UseMedicine = $false; $t.MedicineCount = 0
          $t.UseStone = $false;    $t.StoneCount = 0
          $t.UseExpiringMedicine = [bool]$UseExpMedicine
          if ($UseExpMedicine) { $t.MedicineExpireDays = 1 }
          if ($Times -gt 0) { $t.EnableTimesLimit = $true;  $t.TimesLimit = $Times }
          else { $t.EnableTimesLimit = $false }
        }
        'InfrastTask' { $t.IsEnable = $true }
        'RecruitTask' { $t.IsEnable = $true }
        'MallTask' { $t.IsEnable = $true }
        'AwardTask' { $t.IsEnable = $true }
        'UserDataUpdateTask' { $t.IsEnable = $true }
        'RoguelikeTask' { $t.IsEnable = $false }
        'ReclamationTask' { $t.IsEnable = $false }
        'CopilotTask' { $t.IsEnable = $false }
        'CustomTask' { $t.IsEnable = $false }
      }
    }
    Write-MaaConfig $cfg
  } catch {
    '  ✗ 改配置失败: ' + $_.Exception.Message
    exit 3
  }
  '  == 任务队列（改完）'
  foreach ($t in (Read-MaaConfig | ForEach-Object { Get-MaaCurrentConfig $_ } | ForEach-Object { $_.TaskQueue })) {
    $flag = if ($t.IsEnable) { '  [x] ' } else { '  [ ] ' }
    $extra = ''
    if ($t.'$type' -eq 'FightTask') { $extra = '  stage=' + ($t.StagePlan -join ',') + '  次数=' + $(if ($t.EnableTimesLimit) { $t.TimesLimit } else { '不限（到理智耗尽）' }) + '  临期药=' + $(if ($t.UseExpiringMedicine) { '用（' + $t.MedicineExpireDays + '天内过期）' } else { '不动' }) }
    $flag + $t.'$type' + $extra
  }
  if ($DryRun -or $ApplyOnly) { '  ==> 配置已写好，未启动任务（下一步：请你手动打开 MAA，再跑 maa_daily.ps1 -Attach）'; exit 0 }

  '  MAA 没在运行 —— 配置已就绪，请你手动打开 MAA（我起的 GUI 进程会被沙箱回收）'
  '  ==> 开好 MAA 后跑：maa_daily.ps1 -Attach'
  exit 9
}

# 2) -Attach：用已在运行的 MAA，点开始并盯任务
$p = Get-Process MAA -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) { '  ✗ MAA 没在运行，请先手动打开 MAA'; exit 9 }
'  使用已在运行的 MAA pid=' + $p.Id

$root = [Windows.Automation.AutomationElement]::RootElement
$cond = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
$win = $null
foreach ($w in $root.FindAll([Windows.Automation.TreeScope]::Children, $cond)) { if ($w.Current.Name -like 'MAA*') { $win = $w; break } }
if (-not $win) { '  ✗ 找不到 MAA 主窗'; exit 4 }

# 切到「任务」页
$tc = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::TabItem)
foreach ($t in $win.FindAll([Windows.Automation.TreeScope]::Descendants, $tc)) {
  if ($t.Current.Name -eq 'MaaWpfGui.ViewModels.UI.TaskQueueViewModel') {
    $t.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select(); Start-Sleep -Milliseconds 1200; break
  }
}
$bc = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Button)
$btn = $null
foreach ($b in $win.FindAll([Windows.Automation.TreeScope]::Descendants, $bc)) {
  # MAA 6.x 英文界面下开始按钮叫「Link Start!」
  if ($b.Current.Name -in @('Link Start!', '开始', '开始行动') -and -not $b.Current.IsOffscreen) { $btn = $b; break }
}
if (-not $btn) { '  ✗ 找不到「开始」按钮'; exit 5 }
$btn.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
'  已点「开始」，等任务链跑完（最多 ' + $TimeoutSec + 's）…'

# 4) 盯日志
function Read-Log { try { $fs = New-Object IO.FileStream($GuiLog, 'Open', 'Read', 'ReadWrite'); $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8); $a = $sr.ReadToEnd(); $sr.Close(); $fs.Close(); return @($a -split "`r?`n" | Where-Object { $_ -ne '' }) } catch { return @() } }
$n0 = (Read-Log).Count
$t0 = Get-Date
$done = $false
while (((Get-Date) - $t0).TotalSeconds -lt $TimeoutSec) {
  Start-Sleep -Seconds 6
  $lines = Read-Log
  if ($lines.Count -le $n0) { continue }
  $new = @($lines[$n0..($lines.Count - 1)]); $n0 = $lines.Count
  foreach ($l in $new) {
    if ($l -match '开始任务|完成任务|任务出错|全部任务|已停止|理智不足|材料不足') {
      '    ' + ($l -replace '^\[[\d\- :\.]+\]\[(INF|WRN|ERR|TRC)\]\[[^\]]*\]\s*', '')
    }
    if ($l -match '任务出错') { $done = 'error'; break }
    if ($l -match '全部任务完成|AllTasksCompleted|已完成全部任务') { $done = 'ok'; break }
  }
  if ($done) { break }
}
if ($done -eq 'ok') { '  ==> 日常全部完成'; exit 0 }
elseif ($done -eq 'error') { '  ==> 有任务出错，看上面的日志行'; exit 6 }
else { '  ==> 超时（可能还在跑，去看 MAA 界面）'; exit 7 }
