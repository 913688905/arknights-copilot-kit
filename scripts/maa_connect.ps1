<#
  maa_connect.ps1 —— 「用户自己开模拟器，我负责 MAA 侧的连接设定」
  场景：本机沙箱拦 sc.exe，MuMu 由脚本拉起会变成 headless（桌面看不到窗口）。
        所以流程是：**让用户手动打开 MuMu** → 本脚本自动等 adb、必要时改 MAA 连接地址 → 启动 MAA → 校验真的连上。
  用法：
    maa_connect.ps1                    # 等用户开好 MuMu（最多 300s），然后拉 MAA 并连上
    maa_connect.ps1 -WaitSec 600       # 多等一会儿
    maa_connect.ps1 -Address 127.0.0.1:16384   # 指定地址
    maa_connect.ps1 -RestartMaa        # 需要改地址而 MAA 正开着时，允许我关掉它（会打断任务）
  退出码：0 已连上 / 2 等不到模拟器 / 3 改配置失败 / 4 MAA 起不来 / 5 MAA 连不上
#>
param(
  [int]$WaitSec = 300,
  [string]$Address,
  [switch]$RestartMaa
)
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
. (Join-Path $PSScriptRoot 'maa_config.ps1')

$CfgPath = Join-Path $MaaRoot 'config\gui.new.json'

function Get-AdbState([string]$addr) {
  $st = ((& $Adb -s $addr get-state 2>&1) -join '') -replace "`r", ''
  return $st.Trim()
}

function Find-WorkingAddress {
  $cands = @()
  if ($Address) { $cands += $Address }
  # 先试配置里的，再试常见端口
  if (Test-Path $CfgPath) {
    try {
      $j = [IO.File]::ReadAllText($CfgPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
      $cur = $j.Configurations.Default.Gui.ConnectSettings.Address
      if ($cur) { $cands += $cur }
    } catch { }
  }
  $cands += @($AdbAddr, '127.0.0.1:16384', '127.0.0.1:5555', 'emulator-5554')
  $cands = $cands | Select-Object -Unique
  foreach ($c in $cands) {
    if ($c -match '^[\d\.]+:\d+$') { & $Adb connect $c 2>&1 | Out-Null; Start-Sleep -Milliseconds 500 }
    if ((Get-AdbState $c) -eq 'device') { return $c }
  }
  return $null
}

# MAA 的连接地址只吃 ip:port，遇到 emulator-5554 这种名字要换成 127.0.0.1:5555
function Normalize-Address([string]$addr) {
  if ($addr -match '^emulator-(\d+)$') { return '127.0.0.1:' + ([int]$Matches[1] + 1) }
  return $addr
}

function Set-MaaAddress([string]$addr) {
  if (-not (Test-Path $CfgPath)) { return $false }
  $bak = Backup-MaaConfig
  try {
    $cfg = Read-MaaConfig
    (Get-MaaCurrentConfig $cfg).Gui.ConnectSettings.Address = $addr
    Write-MaaConfig $cfg
    '  MAA 连接地址 -> ' + $addr + '（备份: ' + $bak + '）'
    return $true
  } catch {
    '  ✗ 改配置出错: ' + $_.Exception.Message
    return $false
  }
}

# 1) 等用户开模拟器 / 等 adb
'  [1/3] 等模拟器 adb 就绪（请手动打开 MuMu，我不去启动它）…'
$dl = (Get-Date).AddSeconds($WaitSec)
$dev = $null
while ((Get-Date) -lt $dl) {
  $dev = Find-WorkingAddress
  if ($dev) { break }
  Start-Sleep -Seconds 10
  '      还没连上，继续等…（先确认 MuMu 已启动、游戏能进）'
}
if (-not $dev) {
  & $Adb devices 2>&1 | Out-String
  '  ✗ 等不到模拟器。请确认 MuMu 已启动；若设备显示 offline，试 adb kill-server 后重开 MuMu'
  exit 2
}
'      adb 可用地址: ' + $dev

# 2) 地址和 MAA 配置不一致就改配置（必须 MAA 关着）
$cfgAddr = $null
if (Test-Path $CfgPath) {
  try { $cfgAddr = ([IO.File]::ReadAllText($CfgPath, [Text.Encoding]::UTF8) | ConvertFrom-Json).Configurations.Default.Gui.ConnectSettings.Address } catch { }
}
if ($cfgAddr -and $cfgAddr -ne $dev) {
  $dev = Normalize-Address $dev
  '  [2/3] MAA 里配的是 ' + $cfgAddr + '，实际可用 ' + $dev + '，需要改配置'
  $maa = Get-Process MAA -ErrorAction SilentlyContinue
  if ($maa) {
    if (-not $RestartMaa) { '  ✗ MAA 正开着，改配置会被它覆写。先关掉 MAA，或加 -RestartMaa 让我关（会打断当前任务）'; exit 3 }
    Stop-Process -Id $maa.Id -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 3
  }
  if (-not (Set-MaaAddress $dev)) { '  ✗ 改配置失败'; exit 3 }
} else { '  [2/3] MAA 连接地址已匹配' ; }

# 3) MAA 必须由用户启动：本环境下 agent 起的 GUI 子进程会在工具调用结束时被回收
$p = Get-Process MAA -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) {
  '  [3/3] MAA 没在运行 —— 配置已就绪，请你手动打开 MAA（我起的进程会被沙箱回收）'
  '  ==> 等你开好 MAA 后，再跑 maa_daily.ps1 -Attach 点开始并盯任务'
  exit 9
}
'  [3/3] MAA 已在运行 pid=' + $p.Id + '，检查连接…'

# 触发一次连接：点一下「链接开始」按钮（任务页的「开始」），MAA 会先连模拟器
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$root = [Windows.Automation.AutomationElement]::RootElement
$cond = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
$win = $null
foreach ($w in $root.FindAll([Windows.Automation.TreeScope]::Children, $cond)) { if ($w.Current.Name -like 'MAA*') { $win = $w; break } }
if (-not $win) { '  ✗ 找不到 MAA 主窗'; exit 4 }

function Read-GuiLog {
  try { $fs = New-Object IO.FileStream($GuiLog, 'Open', 'Read', 'ReadWrite'); $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8); $a = $sr.ReadToEnd(); $sr.Close(); $fs.Close(); return @($a -split "`r?`n" | Where-Object { $_ -ne '' }) } catch { return @() }
}
$n0 = (Read-GuiLog).Count
$tc = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::TabItem)
foreach ($t in $win.FindAll([Windows.Automation.TreeScope]::Descendants, $tc)) {
  if ($t.Current.Name -eq 'MaaWpfGui.ViewModels.UI.TaskQueueViewModel') {
    $t.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select(); Start-Sleep -Milliseconds 800; break
  }
}
$bc = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Button)
$btn = $null
foreach ($b in $win.FindAll([Windows.Automation.TreeScope]::Descendants, $bc)) {
  # 注意：MAA 6.x 英文界面下这个按钮叫「Link Start!」，不是「开始」
  if ($b.Current.Name -in @('Link Start!', '开始', '开始行动') -and -not $b.Current.IsOffscreen) { $btn = $b; break }
}
if ($btn) { $btn.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke(); '      已触发连接（点了开始，若任务队列已启用会直接开跑）' }
else { '      ! 找不到开始按钮，跳过触发，只看已有日志' }

$dl = (Get-Date).AddSeconds(90)
$state = ''
while ((Get-Date) -lt $dl) {
  Start-Sleep -Seconds 5
  $lines = Read-GuiLog
  if ($lines.Count -le $n0) { continue }
  $new = @($lines[$n0..($lines.Count - 1)]); $n0 = $lines.Count
  foreach ($l in $new) {
    if ($l -match '截图耗时') { $state = 'ok'; break }
    if ($l -match '连接失败') { $state = 'fail'; break }
  }
  if ($state) { break }
}
if ($state -eq 'ok') { '  ==> 连接正常（已能截图），可以跑 maa_daily.ps1'; exit 0 }
elseif ($state -eq 'fail') { '  ==> MAA 报连接失败：多半是地址/端口不对，或 MAA 需要以普通权限重启'; exit 5 }
else { '  ==> 90s 内没看到连接结果，去 MAA 界面看提示'; exit 5 }
