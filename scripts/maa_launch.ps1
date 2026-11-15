<#
  maa_launch.ps1 —— 一键拉起「模拟器 → 游戏 → MAA」
  用法：
    maa_launch.ps1                 # 拉起 MuMu + 明日方舟 + MAA，等到就绪
    maa_launch.ps1 -SkipGame       # 只拉模拟器和 MAA
    maa_launch.ps1 -SkipMaa        # 只拉模拟器和游戏
  关键顺序（踩过坑）：**必须先把 MuMu 主程序 MuMuNxMain.exe 起来，再 MuMuManager control launch**。
  否则实例会以 headless 模式跑：adb 能用，但桌面上没有任何模拟器窗口，用户以为没启动；
  而且 headless 起来后 adb 端口常常不是 16384 而是 emulator-5554，MAA 就连不上。
#>
param(
  [switch]$SkipGame,
  [switch]$SkipMaa,
  [int]$WaitSec = 240
)
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
. (Join-Path $PSScriptRoot 'maa_config.ps1')

$MuMuRoot = if ($env:MUMU_ROOT) { $env:MUMU_ROOT } else { 'D:/mumu/MuMuPlayer' }
$MuMuMgr  = Join-Path $MuMuRoot 'nx_main\MuMuManager.exe'
$MuMuMain = Join-Path $MuMuRoot 'nx_main\MuMuNxMain.exe'
$GameAct  = 'com.hypergryph.arknights.bilibili/com.u8.sdk.U8UnityContext'

if (-not (Test-Path $MuMuMgr)) { '  ✗ 找不到 MuMuManager: ' + $MuMuMgr + '（可设 MUMU_ROOT）'; exit 2 }

# 1) 主程序（窗口）
if (-not (Get-Process MuMuNxMain -ErrorAction SilentlyContinue)) {
  '  [1/4] 启动 MuMu 主程序（窗口）…'
  Start-Process -FilePath $MuMuMain -WorkingDirectory (Split-Path $MuMuMain -Parent)
  Start-Sleep -Seconds 10
} else { '  [1/4] MuMu 主程序已在运行' }

# 2) 实例（带窗口）
if (-not (Get-Process MuMuNxDevice -ErrorAction SilentlyContinue)) {
  '  [2/4] 启动模拟器实例…'
  & $MuMuMgr control -v 0 launch 2>&1 | Out-Null
} else { '  [2/4] 模拟器实例已在运行' }

$dl = (Get-Date).AddSeconds(90)
while ((Get-Date) -lt $dl) {
  if (Get-Process MuMuNxDevice -ErrorAction SilentlyContinue) { break }
  Start-Sleep -Seconds 5
}
$dev = Get-Process MuMuNxDevice -ErrorAction SilentlyContinue
if ($dev) { '      MuMu 窗口: ' + $dev.MainWindowTitle + ' (hwnd=' + $dev.MainWindowHandle + ')' }
else {
  '  ! 没看到模拟器窗口，重试一次 launch…'
  & $MuMuMgr control -v 0 launch 2>&1 | Out-Null
  Start-Sleep -Seconds 15
  $dev = Get-Process MuMuNxDevice -ErrorAction SilentlyContinue
  if ($dev) { '      MuMu 窗口: ' + $dev.MainWindowTitle } else { '  ✗ 仍然是 headless：桌面上不会有画面，但 adb 可用' }
}

# 3) adb（同一进程内 connect + 校验，避免 adb daemon 被别的程序重启后掉线）
$dl = (Get-Date).AddSeconds($WaitSec)
$ok = $false
while ((Get-Date) -lt $dl) {
  & $Adb connect $AdbAddr 2>&1 | Out-Null
  $st = ((& $Adb -s $AdbAddr get-state 2>&1) -join '' -replace "`r", '').Trim()
  if ($st -eq 'device') { $ok = $true; break }
  Start-Sleep -Seconds 5
}
if (-not $ok) {
  & $Adb devices 2>&1 | Out-String
  '  ✗ adb ' + $AdbAddr + ' 连不上。看上面设备列表：如果是 emulator-5554，把 MAA 的连接地址改成它，或 shutdown+launch 重来'; exit 2
}
'  [3/4] adb ' + $AdbAddr + ' = device'

# 4) 游戏
if (-not $SkipGame) {
  $gpid = ((& $Adb -s $AdbAddr shell pidof $GamePkg 2>&1) -join '').Trim()
  if ($gpid) { '      游戏已在运行 pid=' + $gpid }
  else {
    '      启动明日方舟…'
    & $Adb -s $AdbAddr shell am start -n $GameAct 2>&1 | Out-Null
    $dl = (Get-Date).AddSeconds(120)
    while ((Get-Date) -lt $dl) {
      Start-Sleep -Seconds 5
      $gpid = ((& $Adb -s $AdbAddr shell pidof $GamePkg 2>&1) -join '').Trim()
      if ($gpid) { break }
    }
    '      游戏 pid=' + $gpid
  }
  '      等 25s 让游戏进主界面…'
  Start-Sleep -Seconds 25
} else { '      (跳过游戏)' }

# 5) MAA
if (-not $SkipMaa) {
  $maa = Get-Process MAA -ErrorAction SilentlyContinue
  if ($maa) { '  [4/4] MAA 已在运行 pid=' + $maa.Id }
  else {
    '  [4/4] 启动 MAA…'
    Start-Process -FilePath (Join-Path $MaaRoot 'MAA.exe') -WorkingDirectory $MaaRoot
    $dl = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $dl) { Start-Sleep -Seconds 3; if (Get-Process MAA -ErrorAction SilentlyContinue) { break } }
    Start-Sleep -Seconds 6
    $p = Get-Process MAA -ErrorAction SilentlyContinue
    if ($p) { '      MAA pid=' + $p.Id + ' 窗口=' + $p.MainWindowTitle } else { '  ✗ MAA 没起来' }
  }
} else { '      (跳过 MAA)' }

'  ==> 就绪'
