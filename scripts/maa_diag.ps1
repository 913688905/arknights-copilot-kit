<#
  maa_diag.ps1 —— 作业 vs 干员箱差距诊断（失败后用来总结「缺什么」）
  用法：
    maa_diag.ps1 -Codes 109871,109728,109696
    maa_diag.ps1 -Codes prts://109841
  输出：
    · 每份作业的干员需求 vs 干员箱（OperBoxData.json）的 elite/level 差值
    · 「需专三」清单：作业里 skill_level >= 10 的干员（账号技能等级本地无从得知，
      看 MAA 日志里的「干员不可用: xxx, 原因: 技能等级不足」即可确认没到专三）
    · 末尾「缺口汇总」，可直接用来向用户汇报
  注意：OperBoxData.json 是缓存，刚练起来的干员这里可能还是旧数据，别把它当唯一结论。
#>
param([Parameter(Mandatory=$true)][string[]]$Codes)
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
. (Join-Path $PSScriptRoot 'maa_config.ps1')

if (-not (Test-Path $OperBox)) { '找不到干员箱: ' + $OperBox; exit 1 }
$box = ([IO.File]::ReadAllText($OperBox, [Text.Encoding]::UTF8) | ConvertFrom-Json).own_opers
$eH = @{}; $lH = @{}
foreach ($o in $box) { $eH[$o.name] = [int]$o.elite; $lH[$o.name] = [int]$o.level }
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0 Safari/537.36'

$gaps = @{}
$needS10 = @{}
foreach ($raw in $Codes) {
  $id = ($raw -replace '^prts://', '').Trim()
  $t = Join-Path $env:TEMP ('diag_' + $id + '.json')
  & curl.exe -s -A $ua ('https://prts.maa.plus/copilot/get/' + $id) -o $t | Out-Null
  if (-not (Test-Path $t)) { '  id=' + $id + '  拉取失败'; continue }
  try { $j = [IO.File]::ReadAllText($t, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { '  id=' + $id + '  JSON 解析失败'; continue }
  Remove-Item $t -Force -ErrorAction SilentlyContinue
  $c = $j.data.content | ConvertFrom-Json
  '== prts://' + $id + '  ' + $c.doc.title + '  (' + $c.stage_name + ')'
  foreach ($op in $c.opers) {
    $n = $op.name; $r = $op.requirements
    $reqE = [int]$r.elite; $reqL = [int]$r.level; $reqS = [int]$r.skill_level
    if ($reqS -ge 10) { $needS10[$n] = $true }
    if (-not $eH.ContainsKey($n)) {
      '   ✗ ' + $n + '  未拥有（或作业里是干员组别名）  需 E' + $reqE + ' L' + $reqL + ' S' + $reqS
      $gaps[$n] = '未拥有'
      continue
    }
    $e = $eH[$n]; $l = $lH[$n]
    $flag = '✓'
    if ($e -lt $reqE -or $l -lt $reqL) { $flag = '✗'; $gaps[$n] = '需 E' + $reqE + ' L' + $reqL + '，实际 E' + $e + ' L' + $l }
    $line = '   ' + $flag + ' ' + $n + '  需 E' + $reqE + ' L' + $reqL + ' S' + $reqS + ' / 实际 E' + $e + ' L' + $l
    if ($e -eq 0) { $line += '   ← 未精英化，基本等于不可用' }
    elseif ($e -lt $reqE) { $line += '   ← 精英化不足' }
    elseif ($l -lt $reqL) { $line += '   ← 等级不足' }
    if ($reqS -ge 10) { $line += '   【需专三】' }
    $line
  }
}
' '
'== 需专三清单（作业要求 S10 = 专三）'
if ($needS10.Count -eq 0) { '   无：这套作业不要求专三' }
else { '   ' + (($needS10.Keys | Sort-Object) -join '、') + '   ← 干员箱不含技能等级；日志出现「干员不可用…技能等级不足」就是这个没到' }
' '
'== 缺口汇总'
if ($gaps.Count -eq 0) { '   等级/干员都够 → 失败原因在技能等级、打法匹配或随机性' }
else { foreach ($k in $gaps.Keys) { '   · ' + $k + ' : ' + $gaps[$k] } }
