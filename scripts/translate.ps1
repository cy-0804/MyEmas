$ErrorActionPreference = "Stop"
try {
    $libDir = "c:\Users\acy97\Documents\FYP\MyEmas\lib"
    $files = Get-ChildItem -Path $libDir -Filter *.dart -Recurse

    $strings = @()

    foreach ($f in $files) {
        $content = Get-Content -Raw -Path $f.FullName -Encoding UTF8
        $original = $content
        
        $regex1 = [regex]"Text\(\s*'([^''`\$]+)'\s*([,\)])"
        $matches1 = $regex1.Matches($content)
        foreach ($m in $matches1) {
            $strings += $m.Groups[1].Value
        }
        $content = $regex1.Replace($content, {
            param($m)
            $text = $m.Groups[1].Value
            $suffix = $m.Groups[2].Value
            return "Text('$text'.tr())$suffix"
        })
        
        $regex2 = [regex]'Text\(\s*"([^"`\$]+)"\s*([,\)])'
        $matches2 = $regex2.Matches($content)
        foreach ($m in $matches2) {
            $strings += $m.Groups[1].Value
        }
        $content = $regex2.Replace($content, {
            param($m)
            $text = $m.Groups[1].Value
            $suffix = $m.Groups[2].Value
            return "Text(`"$text`".tr())$suffix"
        })
        
        if ($content -cne $original) {
            if (-not $content.Contains("package:easy_localization/easy_localization.dart")) {
                $content = "import 'package:easy_localization/easy_localization.dart';`r`n" + $content
            }
            Set-Content -Path $f.FullName -Value $content -Encoding UTF8
        }
    }

    $uniqueStrings = $strings | Select-Object -Unique
    $jsonObj = @{}
    foreach ($s in $uniqueStrings) {
        $jsonObj[$s] = $s
    }

    $outDir = "c:\Users\acy97\Documents\FYP\MyEmas\assets\translations"
    if (-not (Test-Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }

    $jsonStr = $jsonObj | ConvertTo-Json -Depth 10
    Set-Content -Path "$outDir\en.json" -Value $jsonStr -Encoding UTF8

    Write-Host "SUCCESS: Extracted $($uniqueStrings.Count) strings to en.json"
} catch {
    Write-Host "ERROR: $_"
}
