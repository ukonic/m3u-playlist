$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$playlist = Join-Path $repo '热门剧集.m3u'
$titles = @('嫁金钗','小城良方','玉簟秋','尚公主','伟大的长征','美人余','蒸蒸日上','醉梦','魅影神捕','我不是大师')

Set-Location $repo
$status = git status --porcelain
if ($status) {
    throw '仓库存在未提交的本地修改，已停止，避免覆盖你的工作。'
}
git pull --ff-only origin main | Out-Host

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('#EXTM3U')
$total = 0

foreach ($title in $titles) {
    $encoded = [Uri]::EscapeDataString($title)
    $api = "https://api.ffzyapi.com/api.php/provide/vod/from/ffm3u8/at/xml/?ac=detail&wd=$encoded"
    $xml = $null
    for ($attempt = 1; $attempt -le 3 -and $null -eq $xml; $attempt++) {
        try {
            $xml = [xml](Invoke-WebRequest -Uri $api -UseBasicParsing -TimeoutSec 30).Content
        } catch {
            if ($attempt -eq 3) { throw "查询失败：$title - $($_.Exception.Message)" }
            Start-Sleep -Seconds 2
        }
    }
    $video = @($xml.rss.list.video | Select-Object -First 1)
    if ($null -eq $video) { throw "接口未返回：$title" }

    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $count = 0
    foreach ($item in ($video.dl.dd.InnerText -split '#')) {
        $parts = $item -split '\$', 2
        if ($parts.Count -ne 2) { continue }
        $episode = $parts[0].Trim()
        $stream = $parts[1].Trim()
        if ([string]::IsNullOrWhiteSpace($episode) -or $stream -notmatch '^https?://') { continue }
        if ($seen.Add($stream)) {
            $lines.Add(('#EXTINF:-1 group-title="{0}",{0} {1}' -f $title, $episode))
            $lines.Add($stream)
            $count++
        }
    }
    if ($count -eq 0) { throw "接口返回空播放列表：$title" }
    $total += $count
}

$newText = (($lines -join "`n") + "`n")
$oldText = if (Test-Path -LiteralPath $playlist) {
    [IO.File]::ReadAllText($playlist, [Text.UTF8Encoding]::new($true)) -replace "`r`n", "`n"
} else { '' }

if ($oldText -eq $newText) {
    Write-Output "无变化：$total 个视频。"
    exit 0
}

[IO.File]::WriteAllText($playlist, $newText, [Text.UTF8Encoding]::new($true))
git add -- '热门剧集.m3u'
git commit -m 'Auto-update popular drama playlist'
git push origin main
Write-Output "已更新并推送：$total 个视频。"
