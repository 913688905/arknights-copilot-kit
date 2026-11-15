<#
  maa_config.ps1 —— 路径/端口集中配置（被其它脚本 dot-source）
  优先级：本机私有配置 maa_config.local.ps1 > 环境变量 > 常见安装位置自动探测。
  想改路径又不想设环境变量，就在同目录建 maa_config.local.ps1 写：
      $MaaRoot = 'D:\MAA'
      $Adb     = 'D:\mumu\MuMuPlayer\nx_device\12.0\shell\adb.exe'
  环境变量：
    MAA_ROOT          MAA 安装目录（含 MAA.exe）
    MAA_ADB           adb.exe 路径（不填则找 MuMu 自带 adb，再退回 PATH 里的 adb）
    MAA_ADB_ADDRESS   模拟器 adb 地址，默认 127.0.0.1:16384
    MAA_GAME_PKG      游戏包名，默认 B 服 com.hypergryph.arknights.bilibili
    MUMU_ROOT         MuMu 安装根目录（maa_launch.ps1 用），默认 D:\mumu\MuMuPlayer
#>

$script:LocalCfg = Join-Path $PSScriptRoot 'maa_config.local.ps1'
if (Test-Path $script:LocalCfg) { . $script:LocalCfg }

function Resolve-MaaRoot {
  if ($MaaRoot -and (Test-Path (Join-Path $MaaRoot 'MAA.exe'))) { return $MaaRoot }
  if ($env:MAA_ROOT -and (Test-Path (Join-Path $env:MAA_ROOT 'MAA.exe'))) { return $env:MAA_ROOT }
  $cands = @(
    (Join-Path $PSScriptRoot '..\MAA'),
    (Join-Path $PSScriptRoot '..\..\MAA'),
    'C:\MAA',
    (Join-Path $env:LOCALAPPDATA 'MAA'),
    (Join-Path $env:USERPROFILE 'MAA'),
    (Join-Path $env:USERPROFILE 'Desktop\MAA')
  )
  foreach ($c in $cands) {
    if ($c -and (Test-Path (Join-Path $c 'MAA.exe'))) { return (Resolve-Path $c).Path }
  }
  throw '找不到 MAA 安装目录：请设置环境变量 MAA_ROOT，或在本目录建 maa_config.local.ps1 指定 $MaaRoot'
}

function Resolve-Adb {
  if ($Adb -and (Test-Path $Adb)) { return $Adb }
  if ($env:MAA_ADB -and (Test-Path $env:MAA_ADB)) { return $env:MAA_ADB }
  $cands = @(
    (Join-Path (if ($env:MUMU_ROOT) { $env:MUMU_ROOT } else { 'D:\mumu\MuMuPlayer' }) 'nx_device\12.0\shell\adb.exe'),
    'C:\Program Files\Netease\MuMuPlayer-12.0\shell\adb.exe',
    'C:\Program Files\Netease\MuMu Player 12\shell\adb.exe',
    'D:\LDPlayer\LDPlayer9\adb.exe',
    'C:\Program Files\BlueStacks_nxt\HD-Adb.exe'
  )
  foreach ($c in $cands) { if (Test-Path $c) { return $c } }
  $cmd = Get-Command adb -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  throw '找不到 adb：请设置环境变量 MAA_ADB，或在 maa_config.local.ps1 里指定 $Adb'
}

$MaaRoot  = Resolve-MaaRoot
$Adb      = Resolve-Adb
$AdbAddr  = if ($env:MAA_ADB_ADDRESS) { $env:MAA_ADB_ADDRESS } else { '127.0.0.1:16384' }
$GamePkg  = if ($env:MAA_GAME_PKG) { $env:MAA_GAME_PKG } else { 'com.hypergryph.arknights.bilibili' }
$GuiLog   = Join-Path $MaaRoot 'debug\gui.log'
$AsstLog  = Join-Path $MaaRoot 'debug\asst.log'
$IfaceDir = Join-Path $MaaRoot 'debug\interface'
$OperBox  = Join-Path $MaaRoot 'data\OperBoxData.json'
$ShotDir  = Join-Path $env:TEMP 'maa-shot'   # 截图统一落这里，配合 maa_clean.ps1 清理

if (-not (Test-Path $ShotDir)) { New-Item -ItemType Directory -Path $ShotDir -Force | Out-Null }

# ---- MAA 配置读写（gui.new.json，纯 PS 实现，不依赖 python）----
$MaaCfgPath = Join-Path $MaaRoot 'config\gui.new.json'

function Backup-MaaConfig {
  if (-not (Test-Path $MaaCfgPath)) { return $null }
  $bakDir = Join-Path $MaaRoot 'config\_daily_bak'
  if (-not (Test-Path $bakDir)) { New-Item -ItemType Directory -Path $bakDir -Force | Out-Null }
  $bak = Join-Path $bakDir ('gui.new.' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.json')
  Copy-Item $MaaCfgPath $bak -Force
  Get-ChildItem $bakDir -Filter 'gui.new.*.json' | Sort-Object LastWriteTime -Descending |
    Select-Object -Skip 5 | Remove-Item -Force -ErrorAction SilentlyContinue
  return $bak
}

function Read-MaaConfig {
  return ([IO.File]::ReadAllText($MaaCfgPath, [Text.Encoding]::UTF8) | ConvertFrom-Json)
}

function Write-MaaConfig($cfg) {
  $txt = $cfg | ConvertTo-Json -Depth 100
  [IO.File]::WriteAllText($MaaCfgPath, $txt, (New-Object Text.UTF8Encoding($false)))
}

function Get-MaaCurrentConfig($cfg) {
  $cur = if ($cfg.Current) { $cfg.Current } else { 'Default' }
  return $cfg.Configurations.$cur
}
