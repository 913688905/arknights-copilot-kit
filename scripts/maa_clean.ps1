<#
  maa_clean.ps1 —— 打完扫尾，清掉截图/临时文件，避免堆积
  用法：
    maa_clean.ps1                       # 清 %TEMP%\maa-shot 截图 + 模拟器里的临时截图
    maa_clean.ps1 -Days 2               # 只清 2 天前的（默认 0 = 全清）
    maa_clean.ps1 -MaaDebug 7           # 顺带清 MAA\debug\interface 下 7 天前的出错现场图
    maa_clean.ps1 -DryRun               # 只看会删什么，不动手
  只删「脚本自己产生的」文件：%TEMP%\maa-shot\*.png、/sdcard/_maa*.png、/sdcard/c*.png、
  以及（可选 -MaaDebug）MAA 的 interface 抓图。不碰日志、不碰用户存档。
#>
param(
  [int]$Days = 0,
  [int]$MaaDebug = -1,
  [switch]$DryRun
)
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
. (Join-Path $PSScriptRoot 'maa_config.ps1')

function Remove-Old($files, $label) {
  $n = 0; $bytes = 0
  foreach ($f in $files) {
    $bytes += $f.Length
    if (-not $DryRun) { Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue }
    '   - ' + $f.FullName
    $n++
  }
  '  ' + $label + ': ' + $n + ' 个，' + [math]::Round($bytes / 1KB, 1) + ' KB' + $(if ($DryRun) { '（dry-run，未删除）' } else { ' 已删' })
}

# 1) 本地截图缓存
if (Test-Path $ShotDir) {
  $cut = (Get-Date).AddDays(-$Days)
  $files = Get-ChildItem $ShotDir -Filter *.png -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cut }
  Remove-Old $files ('%TEMP%\maa-shot 截图（' + $Days + ' 天前）')
} else { '  %TEMP%\maa-shot 不存在，跳过' }

# 2) MAA 目录里我早期直接放在根下的 check.png
$loose = Get-ChildItem (Split-Path $MaaRoot -Parent) -Filter 'check*.png' -File -ErrorAction SilentlyContinue
if ($loose) { Remove-Old $loose '旧版 check*.png' }

# 3) 模拟器里的临时截图
if (Test-Path $Adb) {
  & $Adb connect $AdbAddr 2>&1 | Out-Null
  $st = (& $Adb -s $AdbAddr get-state 2>&1) -join ''
  if ((($st -replace "`r",'').Trim()) -eq 'device') {
    $remote = @(& $Adb -s $AdbAddr shell 'ls /sdcard/*.png 2>/dev/null' 2>&1) | Where-Object { $_ -match '\.png' }
    if ($remote.Count -gt 0) {
      if (-not $DryRun) {
        foreach ($f in $remote) { $p = ($f -replace "`r", '').Trim(); & $Adb -s $AdbAddr shell "rm -f '$p'" 2>&1 | Out-Null }
      }
      '  模拟器截图: ' + $remote.Count + ' 个' + $(if ($DryRun) { '（dry-run，未删除）' } else { ' 已删' })
      foreach ($f in $remote) { '   - ' + $f.Trim() }
    } else { '  模拟器内没有残留截图' }
  } else { '  adb 未连接，跳过模拟器清理（先 maa.ps1 connect）' }
}

# 4) 可选：MAA 出错现场图
if ($MaaDebug -ge 0) {
  if (Test-Path $IfaceDir) {
    $cut = (Get-Date).AddDays(-$MaaDebug)
    $files = Get-ChildItem $IfaceDir -Filter *.png -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cut }
    Remove-Old $files ('MAA interface 抓图（' + $MaaDebug + ' 天前）')
  } else { '  ' + $IfaceDir + ' 不存在，跳过' }
} else { '  （MAA 出错现场图未动；要清加 -MaaDebug 7）' }
