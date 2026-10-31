$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$playlist = Join-Path $repo '现在就出发.m3u'
$api = 'https://api.ffzyapi.com/api.php/provide/vod/from/ffm3u8/at/xml/?ac=detail&wd=%E7%8E%B0%E5%9C%A8%E5%87%BA%E5%8F%91'
$group = '现在就出发 第四季'

Set-Location $repo

if ((git status --porcelain) -ne '') {
    throw '仓库存在未提交的本地修改，已停止，避免覆盖你的工作。'
}

git pull --ff-only origin main | Out-Host

$response = Invoke-WebRequest -Uri $api -UseBasicParsing -TimeoutSec 30
$xml = [xml]$response.Content
$video = @($xml.rss.list.video | Where-Object { $_.name.InnerText -eq '现在就出发第四季' }) | Select-Object -First 1
if ($null -eq $video) { throw '接口没有返回“现在就出发第四季”。' }

$entries = New-Object System.Collections.Generic.List[string]
$seen = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($item in ($video.dl.dd.InnerText -split '#')) {
    $parts = $item -split '\$', 2
    if ($parts.Count -ne 2) { continue }
    $name = $parts[0].Trim()
    $url = $parts[1].Trim()
    if ([string]::IsNullOrWhiteSpace($name) -or $url -notmatch '^https?://') { continue }
    if ($seen.Add($url)) {
        $entries.Add(('#EXTINF:-1 group-title="{0}",{0} {1}' -f $group, $name))
        $entries.Add($url)
    }
}
if ($entries.Count -eq 0) { throw '接口返回的播放条目为空。' }

$oldLines = [System.IO.File]::ReadAllLines($playlist, [System.Text.Encoding]::UTF8)
$newLines = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $oldLines.Count; $i++) {
    if ($oldLines[$i] -match ('^#EXTINF:.*group-title="' + [regex]::Escape($group) + '"')) {
        if ($i + 1 -lt $oldLines.Count -and $oldLines[$i + 1] -notmatch '^#EXTINF:') { $i++ }
        continue
    }
    $newLines.Add($oldLines[$i])
}
while ($newLines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($newLines[$newLines.Count - 1])) { $newLines.RemoveAt($newLines.Count - 1) }
$newLines.AddRange($entries)
$newText = ($newLines -join "`n") + "`n"
$oldText = [System.IO.File]::ReadAllText($playlist, [System.Text.Encoding]::UTF8) -replace "`r`n", "`n"

if ($oldText -eq $newText) {
    Write-Output "无变化：$($entries.Count / 2) 个第四季条目。"
    exit 0
}

[System.IO.File]::WriteAllText($playlist, $newText, [System.Text.UTF8Encoding]::new($false))
git add -- '现在就出发.m3u'
git commit -m "Auto-update 现在就出发 第四季"
git push origin main
Write-Output "已更新并推送：$($entries.Count / 2) 个第四季条目。"

