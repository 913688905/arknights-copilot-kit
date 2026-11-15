<#
  明日方舟 × MAA 抄作业助手（UIA + 日志驱动，尽量不截图）
  用法：
    maa.ps1 info                                # MAA / adb / 游戏 pid 体检
    maa.ps1 find   -Query TL-EX-4               # 查作业站候选
    maa.ps1 job    -Code prts://109723          # 装作业 + 勾好三个开关
    maa.ps1 start                               # 点「开始」
    maa.ps1 run    -Code prts://109723 -TimeoutSec 300
    maa.ps1 status -N 10                        # 最近任务行
    maa.ps1 wait   -TimeoutSec 300              # 等结果
    maa.ps1 shot                                # 截一张图到 %TEMP%\maa-shot 并返回路径
    maa.ps1 connect                             # adb 重连（MuMu 重启 adb 后必做）
  首选执行器是 maa_guard.ps1（带看门狗），本脚本用于体检/找作业/手动微操。
#>
param(
  [Parameter(Mandatory=$true)][ValidateSet('info','job','start','run','status','wait','find','shot','connect')][string]$Action,
  [string]$Code,
  [string]$Query,
  [int]$N = 8,
  [int]$TimeoutSec = 300
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
. (Join-Path $PSScriptRoot 'maa_config.ps1')
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

function Get-MaaWindow {
  $p = Get-Process MAA -ErrorAction SilentlyContinue
  if (-not $p) { throw 'MAA 没在运行（用普通权限启动，管理员权限下 UIA 读不到控件）' }
  $root = [Windows.Automation.AutomationElement]::RootElement
  $cond = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ProcessIdProperty, ($p | Select-Object -First 1).Id)
  foreach ($w in $root.FindAll([Windows.Automation.TreeScope]::Children, $cond)) {
    if ($w.Current.Name -like 'MAA*') { return $w }
  }
  throw '找不到 MAA 主窗（标题应以 MAA 开头）'
}

function Show-CopilotTab($win) {
  $tc = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::TabItem)
  foreach ($t in $win.FindAll([Windows.Automation.TreeScope]::Descendants, $tc)) {
    if ($t.Current.Name -eq 'MaaWpfGui.ViewModels.UI.CopilotViewModel') {
      $t.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select()
      Start-Sleep -Milliseconds 1500
      return
    }
  }
  throw '找不到「自动战斗」标签页'
}

function Find-ByType($win, $type, $name) {
  $c = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty, $type)
  $all = $win.FindAll([Windows.Automation.TreeScope]::Descendants, $c)
  foreach ($e in $all) {
    if (-not $name) { if (-not $e.Current.IsOffscreen) { return $e } }
    elseif ($e.Current.Name -eq $name) { return $e }
  }
  return $null
}

function Set-Job([string]$code) {
  $win = Get-MaaWindow
  Show-CopilotTab $win
  $edit = $win.FindFirst([Windows.Automation.TreeScope]::Descendants,
    (New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Edit)))
  if (-not $edit) { throw '找不到作业输入框' }
  $edit.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue($code)
  Start-Sleep -Seconds 3   # 关键：等作业 HTTP 加载完，否则下面勾的开关会被加载流程覆盖回 Off

  $cc = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::CheckBox)
  foreach ($cb in $win.FindAll([Windows.Automation.TreeScope]::Descendants, $cc)) {
    if ($cb.Current.Name -in @('自动编队', '忽略干员属性要求', '借助战')) {
      $tp = $cb.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern)
      if ($tp.Current.ToggleState -ne 'On') { $tp.Toggle(); Start-Sleep -Milliseconds 250 }
    }
  }
  foreach ($cb in $win.FindAll([Windows.Automation.TreeScope]::Descendants, $cc)) {
    if ($cb.Current.Name -eq '多作业模式') {
      $tp = $cb.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern)
      if ($tp.Current.ToggleState -eq 'On') { $tp.Toggle() }
    }
  }
  return $code
}

function Start-Copilot {
  $win = Get-MaaWindow
  Show-CopilotTab $win
  $btn = Find-ByType $win ([Windows.Automation.ControlType]::Button) '开始'
  if (-not $btn) { throw '找不到「开始」按钮' }
  $btn.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
}

function Read-LogLines {
  try {
    $fs = New-Object IO.FileStream($GuiLog, 'Open', 'Read', 'ReadWrite')
    $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
    $all = $sr.ReadToEnd(); $sr.Close(); $fs.Close()
    return @($all -split "`r?`n" | Where-Object { $_ -ne '' })
  } catch { return @() }
}

function Get-TaskLine($line) {
  return ($line -replace '^\[[\d\- :\.]+\]\[(INF|WRN|ERR|TRC)\]\[[^\]]*\]\s*', '')
}

function Show-Status([int]$n) {
  Read-LogLines | Where-Object {
    $_ -match '开始任务|完成任务|当前步骤|任务出错|战斗出错|干员不可用|已开始行动|未选择作业|解析作业文件'
  } | Select-Object -Last $n | ForEach-Object { '  ' + (Get-TaskLine $_) }
}

function Wait-Task([int]$timeout) {
  $lines0 = Read-LogLines
  $n0 = $lines0.Count
  $deadline = (Get-Date).AddSeconds($timeout)
  "  等待任务结束（最多 ${timeout}s）…"
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    $lines = Read-LogLines
    if ($lines.Count -le $n0) { continue }
    $new = @($lines[$n0..($lines.Count - 1)])
    $n0 = $lines.Count
    foreach ($l in $new) {
      if ($l -match '开始任务|当前步骤|完成任务|任务出错|战斗出错|未选择作业|解析作业文件') {
        '  ' + (Get-TaskLine $l)
        # 干员不可用（技能等级不足）是正常提示，作业会继续，绝不能当失败
        if ($l -match '未选择作业|解析作业文件错误') { '  ==> 作业不可用'; return $false }
        if ($l -match '任务出错|战斗出错') { '  ==> 失败'; return $false }
        if ($l -match '完成任务: 自动战斗') { '  ==> 任务链结束（不等于过关，回地图确认节点）'; return $true }
      }
    }
  }
  '  ==> 超时，没等到完成'; return $null
}

function Get-DeviceState {
  if (-not (Test-Path $Adb)) { return 'adb 不存在: ' + $Adb }
  $st = (& $Adb -s $AdbAddr get-state 2>&1) -join ''
  if (($st -replace "`r",'').Trim() -ne 'device') {
    & $Adb connect $AdbAddr 2>&1 | Out-Null
    Start-Sleep -Seconds 1
    $st = (& $Adb -s $AdbAddr get-state 2>&1) -join ''
  }
  return $st
}

function Show-Info {
  $p = Get-Process MAA -ErrorAction SilentlyContinue
  if ($p) { '  MAA pid=' + $p.Id + '  ' + $p.MainWindowTitle } else { '  MAA 没在运行（普通权限启动，别用管理员）' }
  '  MAA 目录 = ' + $MaaRoot
  '  adb       = ' + $Adb
  '  adb ' + $AdbAddr + ' = ' + (Get-DeviceState)
  if (Test-Path $Adb) {
    $gpid = (& $Adb -s $AdbAddr shell pidof $GamePkg 2>&1) -join ''
    '  游戏 pid = ' + $(if ($gpid) { $gpid } else { '未运行' })
  }
  '  == 最近任务行'
  Show-Status $N
}

function Find-Jobs([string]$q) {
  $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0 Safari/537.36'
  $u = 'https://prts.maa.plus/copilot/query?document=' + [uri]::EscapeDataString($q) + '&limit=30&page=1'
  $tmp = Join-Path $env:TEMP ('maa_find_' + [guid]::NewGuid().ToString('N') + '.json')
  & curl.exe -s -A $ua $u -o $tmp | Out-Null
  if (-not (Test-Path $tmp)) { '  查询失败'; return }
  $j = [IO.File]::ReadAllText($tmp, [Text.Encoding]::UTF8) | ConvertFrom-Json
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  '  total=' + $j.data.total
  foreach ($it in $j.data.data) {
    if (-not $it.content) { continue }
    $c = $it.content | ConvertFrom-Json
    if ($c -is [array]) { continue }
    $maxSkill = 0; $maxElite = 0; $s10 = @()
    foreach ($op in $c.opers) {
      if ($op.requirements.skill_level) {
        $s = [int]$op.requirements.skill_level
        if ($s -gt $maxSkill) { $maxSkill = $s }
        if ($s -ge 10) { $s10 += $op.name }
      }
      if ($op.requirements.elite -and [int]$op.requirements.elite -gt $maxElite) { $maxElite = [int]$op.requirements.elite }
    }
    '  id=' + $it.id + '  v=' + $it.views + '  stage=' + $c.stage_name + '  ops=' + $c.opers.Count + '  maxSkill=' + $maxSkill + '  maxElite=' + $maxElite
    '     「' + $c.doc.title + '」'
    if ($s10.Count -gt 0) { '     需专三(' + $s10.Count + '): ' + ($s10 -join ', ') }
  }
}

function Save-Shot {
  $name = 'shot_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.png'
  $dst = Join-Path $ShotDir $name
  & $Adb -s $AdbAddr shell screencap -p /sdcard/_maa.png 2>&1 | Out-Null
  & $Adb -s $AdbAddr pull /sdcard/_maa.png $dst 2>&1 | Out-Null
  & $Adb -s $AdbAddr shell rm -f /sdcard/_maa.png 2>&1 | Out-Null
  if (Test-Path $dst) { '  ' + $dst } else { '  截图失败（adb 掉线？先 connect）' }
}

switch ($Action) {
  'info'    { Show-Info }
  'job'     { if (-not $Code) { throw '缺少 -Code，例如 -Code prts://109723' }; '  已装作业 ' + (Set-Job $Code) }
  'start'   { Start-Copilot; '  已点「开始」' }
  'run'     {
    if (-not $Code) { throw '缺少 -Code，例如 -Code prts://109723' }
    '  已装作业 ' + (Set-Job $Code)
    Start-Copilot
    '  已点「开始」——确认游戏此刻停在关卡详情页（能看到「开始行动/开始突袭」）'
    Wait-Task $TimeoutSec
  }
  'status'  { Show-Status $N }
  'wait'    { Wait-Task $TimeoutSec }
  'find'    { if (-not $Query) { throw '缺少 -Query，例如 -Query TL-EX-4' }; Find-Jobs $Query }
  'shot'    { Save-Shot }
  'connect' { & $Adb connect $AdbAddr 2>&1 | Out-String; '  adb ' + $AdbAddr + ' = ' + (Get-DeviceState) }
}
