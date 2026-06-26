$file = "e:\mediamix-kmp\shared\src\commonMain\kotlin\com\mediamix\shared\cache\CacheStrategyManager.kt"
$content = Get-Content $file -Raw -Encoding UTF8
$content = $content -replace 'import kotlinx\.datetime\.Clock', "import kotlin.math.roundToInt`nimport kotlinx.datetime.Clock"
$content = $content -replace 'return \(baseTtl \* suggestion\.ttlMultiplier\)\.toInt\(\)', 'return (baseTtl * suggestion.ttlMultiplier).roundToInt()'
[System.IO.File]::WriteAllText($file, $content, [System.Text.Encoding]::UTF8)
Write-Host "CacheStrategyManager.kt updated"
