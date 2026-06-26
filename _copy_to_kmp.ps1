$utf8 = New-Object System.Text.UTF8Encoding($false)
$src = "e:\mediamix-young-\_temp_spider"
$dstMain = "e:\mediamix-kmp\shared\src\commonMain\kotlin\com\mediamix\shared"
$dstTest = "e:\mediamix-kmp\shared\src\commonTest\kotlin\com\mediamix\shared\spider"

# Ensure directories exist
New-Item -ItemType Directory -Force -Path "$dstMain\spider" | Out-Null
New-Item -ItemType Directory -Force -Path $dstTest | Out-Null

# Copy main source files
$mainFiles = @("SpiderAdapter.kt", "CmsSpider.kt", "JsonSpider.kt", "XpathSpider.kt", "JavaBridgeSpider.kt", "VideoApiService.kt")
foreach ($f in $mainFiles) {
    $content = [System.IO.File]::ReadAllText("$src\$f", [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText("$dstMain\spider\$f", $content, $utf8)
    Write-Host "Copied: spider/$f"
}

# Copy updated VideoModels.kt
$content = [System.IO.File]::ReadAllText("$src\VideoModels.kt", [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText("$dstMain\models\VideoModels.kt", $content, $utf8)
Write-Host "Copied: models/VideoModels.kt"

# Copy test files
$testFiles = @("JsonSpiderTest.kt", "XpathSpiderTest.kt")
foreach ($f in $testFiles) {
    $content = [System.IO.File]::ReadAllText("$src\$f", [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText("$dstTest\$f", $content, $utf8)
    Write-Host "Copied: test/spider/$f"
}

Write-Host "`nAll files copied successfully!"
