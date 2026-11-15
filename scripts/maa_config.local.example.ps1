# 复制为 maa_config.local.ps1 后按自己机器改（该文件已在 .gitignore 里，不会发布）
# Copy to maa_config.local.ps1 and edit. This file is git-ignored.

# MAA 安装目录（含 MAA.exe）
$MaaRoot = 'D:\MAA'

# 模拟器 adb.exe（MuMu / LD / 蓝叠 任选其一，也可以直接用系统 PATH 里的 adb）
$Adb = 'D:\mumu\MuMuPlayer\nx_device\12.0\shell\adb.exe'

# MuMu 安装根目录（只有 maa_launch.ps1 用得到）
$env:MUMU_ROOT = 'D:\mumu\MuMuPlayer'

# 可选：模拟器 adb 地址与游戏包名
# $env:MAA_ADB_ADDRESS = '127.0.0.1:16384'
# $env:MAA_GAME_PKG    = 'com.hypergryph.arknights.bilibili'
