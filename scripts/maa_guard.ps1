<#
  maa_guard.ps1 —— 带看门狗的抄作业执行器（首选入口）
  用法：
    maa_guard.ps1 -Code prts://109554                    # 装作业+开始+盯着跑
    maa_guard.ps1 -Code prts://109554 -StallSec 90       # 90s 无进展判为卡死
    maa_guard.ps1 -Code prts://109554 -MaxRetry 1        # 只重开 1 次（推荐）
  行为：
    - 装作业后校验是否真的加载出来（防「解析作业文件错误」空跑），再强制勾好
      自动编队 / 忽略干员属性要求 / 借助战，关掉 多作业模式，并读回确认
    - 每 4s 读 gui.log：任务出错 / 战斗出错 / 未选择作业 / 解析作业文件错误 → 自动重开
    - StallSec 秒没有任何进展行 → 判为卡死，点「停止」后重开
    - 进战斗后（出现「当前步骤」/「已开始行动」）给 300s 静默宽限，避免误杀正在打的战斗
  退出码：0 任务链结束（≠过关）/ 2 失败 / 3 超时 / 4 作业坏了 / 5 需要人工 / 6 开关没勾上
  规矩：同一关最多 3 次尝试 / 3 份作业。3 份都不过就停手，跑 maa_diag.ps1 总结缺口后问用户。
#>
param(
  [Parameter(Mandatory=$true)][string]$Code,
  [int]$TimeoutSec = 420,
  [int]$StallSec = 90,
  [int]$MaxRetry = 1
)
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
. (Join-Path $PSScriptRoot 'maa_config.ps1')
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

function Get-MaaWindow {
  $p = Get-Process MAA -ErrorAction SilentlyContinue
  if (-not $p) { throw 'MAA 没在运行（普通权限启动，管理员权限下 UIA 读不到控件）' }
  $root = [Windows.Automation.AutomationElement]::RootElement
  $cond = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ProcessIdProperty, ($p | Select-Object -First 1).Id)
  foreach ($w in $root.FindAll([Windows.Automation.TreeScope]::Children, $cond)) {
    if ($w.Current.Name -like 'MAA*') { return $w }
  }
  throw '找不到 MAA 主窗'
}

function Show-CopilotTab($win) {
  $tc = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::TabItem)
  foreach ($t in $win.FindAll([Windows.Automation.TreeScope]::Descendants, $tc)) {
    if ($t.Current.Name -eq 'MaaWpfGui.ViewModels.UI.CopilotViewModel') {
      $t.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select()
      Start-Sleep -Milliseconds 800
      return
    }
  }
  throw '找不到自动战斗标签页'
}

function Get-Button($win, $name) {
  $c = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Button)
  foreach ($b in $win.FindAll([Windows.Automation.TreeScope]::Descendants, $c)) {
    if ($b.Current.Name -eq $name -and -not $b.Current.IsOffscreen) { return $b }
  }
  return $null
}

function Get-Cbs($win) {
  $c = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::CheckBox)
  return @($win.FindAll([Windows.Automation.TreeScope]::Descendants, $c))
}

function Read-Log {
  try {
    $fs = New-Object IO.FileStream($GuiLog, 'Open', 'Read', 'ReadWrite')
    $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
    $a = $sr.ReadToEnd(); $sr.Close(); $fs.Close()
    return @($a -split "`r?`n" | Where-Object { $_ -ne '' })
  } catch { return @() }
}

function Set-JobReady([string]$code) {
  $win = Get-MaaWindow
  Show-CopilotTab $win
  $te = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Edit)
  $edit = $win.FindFirst([Windows.Automation.TreeScope]::Descendants, $te)
  if (-not $edit) { throw '找不到作业输入框' }
  $want = @{ 0 = 'On'; 2 = 'On'; 3 = 'On'; 7 = 'Off' }   # 自动编队 / 忽略干员属性要求 / 借助战 / 多作业模式
  $loaded = $false
  for ($try = 1; $try -le 3; $try++) {
    $n = (Read-Log).Count
    $edit.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue($code)
    Start-Sleep -Seconds 3   # 等作业 HTTP 拉取完成，之后勾开关才不会被加载流程覆盖
    $lines = Read-Log
    if ($lines.Count -gt $n) {
      foreach ($l in $lines[$n..($lines.Count - 1)]) {
        if ($l -match '共 \d+ 名干员|共\d+名干员') { $loaded = $true }
        if ($l -match '解析作业文件错误') { $loaded = $false; break }
      }
    }
    if ($loaded) { break }
    '    (作业没加载出来，重新填一次)'
  }
  if (-not $loaded) { return $false }
  for ($i = 1; $i -le 3; $i++) {
    $cbs = Get-Cbs $win
    foreach ($k in $want.Keys) {
      if ($k -ge $cbs.Count) { continue }
      $tp = $cbs[$k].GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern)
      if ($tp.Current.ToggleState.ToString() -ne $want[$k]) { $tp.Toggle(); Start-Sleep -Milliseconds 250 }
    }
    Start-Sleep -Milliseconds 400
    $cbs = Get-Cbs $win
    $ok = $true
    foreach ($k in @(0,2,3,7)) {
      if ($k -lt $cbs.Count) {
        $st = $cbs[$k].GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Current.ToggleState.ToString()
        if ($st -ne $want[$k]) { $ok = $false }
      }
    }
    if ($ok) { return 'switches-ok' }
  }
  return 'switches-bad'
}

function Start-Copilot {
  $win = Get-MaaWindow
  Show-CopilotTab $win
  $btn = Get-Button $win '开始'
  if (-not $btn) { throw '找不到开始按钮（可能还在跑，需先停止）' }
  $btn.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
}

function Stop-Copilot {
  $win = Get-MaaWindow
  Show-CopilotTab $win
  $btn = Get-Button $win '停止'
  if ($btn) { $btn.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep -Seconds 2; return $true }
  return $false
}

function Adb-Reconnect {
  if (Test-Path $Adb) { & $Adb connect $AdbAddr 2>&1 | Out-Null }
}

$attempt = 0
$n0 = (Read-Log).Count
while ($true) {
  $attempt++
  '  ---- 第 ' + $attempt + ' 次尝试 · ' + $Code
  $st = Set-JobReady $Code
  if (-not $st) { '  ==> 作业加载不出来（解析失败/网络），换一份作业（退出 4）'; exit 4 }
  if ($st -eq 'switches-bad') { '  ==> 开关没勾上（退出 6）'; exit 6 }
  Start-Copilot
  '  已点开始（游戏必须停在关卡详情页）'
  $n0 = (Read-Log).Count
  $t0 = Get-Date
  $lastProgress = Get-Date
  $graceUntil = (Get-Date).AddSeconds($StallSec)
  $verdict = ''
  $sawBattle = $false
  while (((Get-Date) - $t0).TotalSeconds -lt $TimeoutSec) {
    Start-Sleep -Seconds 4
    $lines = Read-Log
    if ($lines.Count -gt $n0) {
      $new = @($lines[$n0..($lines.Count - 1)])
      $n0 = $lines.Count
      foreach ($l in $new) {
        if ($l -match '当前步骤|完成任务|任务出错|战斗出错|已开始行动|选择干员|开始编队|未选择作业|解析作业文件') {
          '    ' + ($l -replace '^\[[\d\- :\.]+\]\[(INF|WRN|ERR|TRC)\]\[[^\]]*\]\s*', '')
        }
        if ($l -match '解析作业文件错误|未选择作业') { $verdict = 'job'; break }
        if ($l -match '任务出错|战斗出错') { $verdict = 'fail'; break }
        if ($l -match '完成任务: 自动战斗') { $verdict = 'ok'; break }
        if ($l -match '选择干员|开始编队') { $lastProgress = Get-Date }
        # 出现「当前步骤」= 已经在打，后面可能 1~2 分钟没有新步骤（等结束），给足 300s
        if ($l -match '当前步骤') { $lastProgress = Get-Date; $graceUntil = (Get-Date).AddSeconds(300); $sawBattle = $true }
        if ($l -match '已开始行动') { $lastProgress = Get-Date; $graceUntil = (Get-Date).AddSeconds(300); $sawBattle = $true }
        if ($l -match '开始挂机') { $lastProgress = Get-Date; $graceUntil = (Get-Date).AddSeconds(300) }
      }
    }
    if ($verdict) { break }
    if ((Get-Date) -gt $graceUntil) { $verdict = 'stall'; break }
  }
  if (-not $verdict) { $verdict = 'timeout' }

  switch ($verdict) {
    'ok' { '  ==> 任务链结束（注意：这不等于过关，必须回地图看节点是否变灰）'; exit 0 }
    'timeout' { '  ==> 超时没等到结果'; exit 3 }
    'job' {
      '  ==> 作业不可用（解析失败 / 未选上）'
      if ($attempt -gt 1) { '  ==> 换一份作业吧（退出 4）'; exit 4 }
    }
    'fail' {
      '  ==> 战斗出错'
      if ($sawBattle) {
        '  ==> 已经进过战斗才出错：多半是战斗中被打断（掉线/作业走位不匹配），游戏现在停在失败页或结算页，重启也没用（退出 5）'
        exit 5
      }
    }
    'stall' { '  ==> ' + $StallSec + 's 没进展，判为卡死，准备重开' }
  }
  if ($attempt -gt $MaxRetry) {
    '  ==> 连着重开 ' + $MaxRetry + ' 次还是不行：多半是编队残留 / 游戏不在详情页 / MAA 状态坏了，需要人工处理（退出 5）'
    exit 5
  }
  Stop-Copilot | Out-Null
  Adb-Reconnect
  Start-Sleep -Seconds 2
  # 不盲目点屏幕/按返回：重开前的界面状态由人确认，避免退到地图后空跑
}
