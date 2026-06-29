$libDir = "c:\Users\acy97\Documents\FYP\MyEmas\lib"
$files = Get-ChildItem -Path $libDir -Filter *.dart -Recurse

$utf8NoBom = New-Object System.Text.UTF8Encoding($False)

foreach ($f in $files) {
    # Read bytes to check for BOM (EF BB BF)
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Write-Host "Removing BOM from $($f.Name)"
        $content = [System.IO.File]::ReadAllText($f.FullName)
        [System.IO.File]::WriteAllText($f.FullName, $content, $utf8NoBom)
    }
}
Write-Host "BOM stripping complete."
