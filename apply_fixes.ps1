$file = "e:\mediamix-kmp\shared\src\commonMain\kotlin\com\mediamix\shared\cache\CacheStrategyManager.kt"
$lines = [System.IO.File]::ReadAllLines($file)
$newLines = New-Object System.Collections.Generic.List[string]
foreach ($line in $lines) {
    if ($line.Trim() -eq "import kotlinx.datetime.Clock") {
        $newLines.Add("import kotlin.math.roundToInt")
    }
    if ($line.Contains("(baseTtl * suggestion.ttlMultiplier).toInt()")) {
        $line = $line.Replace("(baseTtl * suggestion.ttlMultiplier).toInt()", "(baseTtl * suggestion.ttlMultiplier).roundToInt()")
    }
    $newLines.Add($line)
}
[System.IO.File]::WriteAllLines($file, $newLines.ToArray(), [System.Text.UTF8Encoding]::new($false))
Write-Host "Source fix applied successfully"
