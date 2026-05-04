$root = "c:\Alpaca"
$mdFiles = Get-ChildItem $root -Recurse -Filter '*.md' | Where-Object { $_.FullName -notmatch '\\_eski\\' }

$dict = @{
    "Ä±" = "ı"
    "ÅŸ" = "ş"
    "Åž" = "Ş"
    "Ã§" = "ç"
    "Ã‡" = "Ç"
    "Ã¶" = "ö"
    "Ã–" = "Ö"
    "Ã¼" = "ü"
    "Ãœ" = "Ü"
    "ÄŸ" = "ğ"
    "Äž" = "Ğ"
    "Ä°" = "İ"
    "Ã¢" = "â"
    "â€™" = "'"
}

$fixedFiles = 0

foreach ($f in $mdFiles) {
    if ($f.Length -gt 0) {
        $content = Get-Content $f.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($content) {
            $changed = $false
            foreach ($key in $dict.Keys) {
                if ($content -match $key) {
                    $changed = $true
                    $content = $content.Replace($key, $dict[$key])
                }
            }
            if ($changed) {
                Set-Content -Path $f.FullName -Value $content -Encoding UTF8
                Write-Host "Karakterler onarildi: $($f.Name)" -ForegroundColor Green
                $fixedFiles++
            }
        }
    }
}
Write-Host "`nToplam $fixedFiles dosya tamamen turkceye cevrildi ve kurtarildi." -ForegroundColor Cyan
