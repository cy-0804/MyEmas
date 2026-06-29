# Full i18n script: wraps Text('...') with .tr() and builds translation JSON files
param(
    [string]$LibDir = "c:\Users\acy97\Documents\FYP\MyEmas\lib",
    [string]$TransDir = "c:\Users\acy97\Documents\FYP\MyEmas\assets\translations"
)

$utf8NoBom = New-Object System.Text.UTF8Encoding($False)
$allKeys = [System.Collections.Generic.HashSet[string]]::new()

$dartFiles = Get-ChildItem -Path $LibDir -Filter "*.dart" -Recurse

foreach ($file in $dartFiles) {
    $content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    $original = $content

    # ─── 1. Add easy_localization import if missing ───────────────────────────
    if ($content -notmatch "easy_localization") {
        # Insert after the first flutter/material import
        $content = $content -replace "(import 'package:flutter/material\.dart';)", "`$1`nimport 'package:easy_localization/easy_localization.dart';"
    }

    # ─── 2. Wrap Text('literal') with .tr() ──────────────────────────────────
    # Match Text('...') where the string has no interpolation and isn't already .tr()
    # Pattern: Text('some text') NOT followed by .tr()
    $pattern = "Text\('([^'\\${}]+?)'\)(?!\.tr\(\))"
    $matches = [regex]::Matches($content, $pattern)

    foreach ($m in $matches) {
        $key = $m.Groups[1].Value.Trim()
        # Skip strings that look like keys (icons, single chars, etc.)
        if ($key.Length -lt 2) { continue }
        $null = $allKeys.Add($key)
    }

    # Do the replacement - use regex to add .tr() 
    $content = [regex]::Replace($content, $pattern, { param($m)
        $key = $m.Groups[1].Value
        "Text('$key'.tr())"
    })

    # ─── 3. Wrap labelText: 'literal' and hintText: 'literal' ────────────────
    $inputPattern = "((?:labelText|hintText|helperText|prefixText|suffixText|counterText)\s*:\s*'([^'\\${}]+?)')(?!\s*\.tr\(\))"
    $inputMatches = [regex]::Matches($content, $inputPattern)
    foreach ($m in $inputMatches) {
        $key = $m.Groups[2].Value.Trim()
        if ($key.Length -ge 2) { $null = $allKeys.Add($key) }
    }
    $content = [regex]::Replace($content, $inputPattern, { param($m)
        $prop = $m.Groups[1].Value -replace "'([^']+)'", "'`$1'.tr()"
        $prop
    })

    # ─── 4. Write back only if changed ───────────────────────────────────────
    if ($content -ne $original) {
        [System.IO.File]::WriteAllText($file.FullName, $content, $utf8NoBom)
        Write-Host "Updated: $($file.Name)"
    } else {
        Write-Host "Skipped: $($file.Name)"
    }
}

Write-Host ""
Write-Host "=== Collected $($allKeys.Count) unique translation keys ==="

# ─── 5. Build / merge translation JSON files ─────────────────────────────────
$langs = @{
    "en" = @{}
    "ms" = @{
        # Seeded Bahasa Melayu translations
        "Dashboard" = "Papan Pemuka"; "Medications" = "Ubat-ubatan";
        "Health Data" = "Data Kesihatan"; "Schedules" = "Jadual";
        "Emergency" = "Kecemasan"; "Settings" = "Tetapan";
        "Preference" = "Keutamaan"; "Language" = "Bahasa";
        "Font Size" = "Saiz Fon"; "Large Text" = "Teks Besar";
        "Email" = "E-mel"; "Password" = "Kata Laluan";
        "Login" = "Log Masuk"; "Log In" = "Log Masuk";
        "Sign Up" = "Daftar"; "Elderly" = "Warga Emas";
        "Caregiver" = "Penjaga"; "Welcome back" = "Selamat kembali";
        "Please select your language" = "Sila pilih bahasa anda";
        "Preferences saved!" = "Keutamaan disimpan!";
        "Next" = "Seterusnya"; "Save" = "Simpan"; "Cancel" = "Batal";
        "Delete" = "Padam"; "Edit" = "Edit"; "Add" = "Tambah";
        "Search" = "Cari"; "Profile" = "Profil"; "Home" = "Utama";
        "Name" = "Nama"; "Age" = "Umur"; "Date" = "Tarikh";
        "Time" = "Masa"; "Notes" = "Nota"; "Status" = "Status";
        "Active" = "Aktif"; "Done" = "Selesai"; "Loading..." = "Memuatkan...";
        "Error" = "Ralat"; "Success" = "Berjaya"; "Warning" = "Amaran";
        "Confirm" = "Sahkan"; "Back" = "Kembali"; "Close" = "Tutup";
        "Continue" = "Teruskan"; "Submit" = "Hantar"; "Logout" = "Log Keluar";
        "Log Out" = "Log Keluar"; "My Profile" = "Profil Saya";
        "Or" = "Atau"; "No" = "Tidak"; "Yes" = "Ya";
        "Email/Phone Number" = "E-mel/Nombor Telefon";
        "Enter your email or phone number" = "Masukkan e-mel atau nombor telefon anda";
        "Enter your email/phone number and\npassword to log in" = "Masukkan e-mel/nombor telefon dan\nkata laluan untuk log masuk";
        "Don't have an account? " = "Tiada akaun? ";
        "Continue with Google" = "Teruskan dengan Google";
        "Login with Biometrics" = "Log Masuk dengan Biometrik";
        "Medication" = "Ubat"; "Missed" = "Terlepas"; "Taken" = "Diambil";
        "Today" = "Hari ini"; "Tomorrow" = "Esok"; "Week" = "Minggu";
        "Morning" = "Pagi"; "Afternoon" = "Tengah hari"; "Evening" = "Petang"; "Night" = "Malam";
        "Blood Pressure" = "Tekanan Darah"; "Blood Sugar" = "Gula Darah";
        "Heart Rate" = "Kadar Degupan Jantung"; "Weight" = "Berat";
        "Temperature" = "Suhu"; "Oxygen" = "Oksigen";
        "No data available" = "Tiada data tersedia";
        "Add Medication" = "Tambah Ubat"; "Add Schedule" = "Tambah Jadual";
        "SOS" = "SOS"; "Call" = "Panggil"; "Message" = "Mesej";
        "Location" = "Lokasi"; "Alert" = "Amaran";
        "Notification" = "Pemberitahuan"; "Reminder" = "Peringatan";
        "Health Record" = "Rekod Kesihatan"; "Report" = "Laporan";
        "History" = "Sejarah"; "Details" = "Butiran";
        "Frequency" = "Kekerapan"; "Dosage" = "Dos";
        "Start Date" = "Tarikh Mula"; "End Date" = "Tarikh Tamat";
        "Daily" = "Setiap hari"; "Weekly" = "Setiap minggu";
        "Monthly" = "Setiap bulan";
        "Please fill in all fields" = "Sila isi semua ruangan";
        "An error occurred" = "Ralat berlaku";
        "Data saved successfully" = "Data berjaya disimpan";
    }
    "zh" = @{
        # Seeded Chinese translations
        "Dashboard" = "仪表板"; "Medications" = "药物";
        "Health Data" = "健康数据"; "Schedules" = "时间表";
        "Emergency" = "紧急情况"; "Settings" = "设置";
        "Preference" = "偏好"; "Language" = "语言";
        "Font Size" = "字体大小"; "Large Text" = "大字体";
        "Email" = "电子邮件"; "Password" = "密码";
        "Login" = "登录"; "Log In" = "登录";
        "Sign Up" = "注册"; "Elderly" = "长者";
        "Caregiver" = "护理人员"; "Welcome back" = "欢迎回来";
        "Please select your language" = "请选择您的语言";
        "Preferences saved!" = "偏好已保存！";
        "Next" = "下一步"; "Save" = "保存"; "Cancel" = "取消";
        "Delete" = "删除"; "Edit" = "编辑"; "Add" = "添加";
        "Search" = "搜索"; "Profile" = "个人资料"; "Home" = "主页";
        "Name" = "姓名"; "Age" = "年龄"; "Date" = "日期";
        "Time" = "时间"; "Notes" = "备注"; "Status" = "状态";
        "Active" = "活跃"; "Done" = "完成"; "Loading..." = "加载中...";
        "Error" = "错误"; "Success" = "成功"; "Warning" = "警告";
        "Confirm" = "确认"; "Back" = "返回"; "Close" = "关闭";
        "Continue" = "继续"; "Submit" = "提交"; "Logout" = "退出登录";
        "Log Out" = "退出登录"; "My Profile" = "我的资料";
        "Or" = "或者"; "No" = "否"; "Yes" = "是";
        "Email/Phone Number" = "电子邮件/手机号码";
        "Enter your email or phone number" = "请输入您的电子邮件或手机号码";
        "Enter your email/phone number and\npassword to log in" = "请输入电子邮件/手机号码和\n密码登录";
        "Don't have an account? " = "没有账号？";
        "Continue with Google" = "使用谷歌继续";
        "Login with Biometrics" = "使用生物识别登录";
        "Medication" = "药物"; "Missed" = "已错过"; "Taken" = "已服用";
        "Today" = "今天"; "Tomorrow" = "明天"; "Week" = "周";
        "Morning" = "早上"; "Afternoon" = "下午"; "Evening" = "傍晚"; "Night" = "晚上";
        "Blood Pressure" = "血压"; "Blood Sugar" = "血糖";
        "Heart Rate" = "心率"; "Weight" = "体重";
        "Temperature" = "体温"; "Oxygen" = "血氧";
        "No data available" = "暂无数据";
        "Add Medication" = "添加药物"; "Add Schedule" = "添加日程";
        "SOS" = "紧急求助"; "Call" = "致电"; "Message" = "消息";
        "Location" = "位置"; "Alert" = "警报";
        "Notification" = "通知"; "Reminder" = "提醒";
        "Health Record" = "健康记录"; "Report" = "报告";
        "History" = "历史"; "Details" = "详情";
        "Frequency" = "频率"; "Dosage" = "剂量";
        "Start Date" = "开始日期"; "End Date" = "结束日期";
        "Daily" = "每天"; "Weekly" = "每周";
        "Monthly" = "每月";
        "Please fill in all fields" = "请填写所有字段";
        "An error occurred" = "发生错误";
        "Data saved successfully" = "数据保存成功";
    }
}

foreach ($key in $allKeys) {
    # English is always same as key
    $langs["en"][$key] = $key
    # MS: use seed if exists, else fallback to key
    if (-not $langs["ms"].ContainsKey($key)) { $langs["ms"][$key] = $key }
    # ZH: use seed if exists, else fallback to key
    if (-not $langs["zh"].ContainsKey($key)) { $langs["zh"][$key] = $key }
}

# Also ensure all seeded keys are in en
foreach ($key in $langs["ms"].Keys) { if (-not $langs["en"].ContainsKey($key)) { $langs["en"][$key] = $key } }
foreach ($key in $langs["zh"].Keys) { if (-not $langs["en"].ContainsKey($key)) { $langs["en"][$key] = $key } }

# Write JSON files
foreach ($lang in $langs.Keys) {
    $obj = [ordered]@{}
    foreach ($k in ($langs[$lang].Keys | Sort-Object)) { $obj[$k] = $langs[$lang][$k] }
    $json = $obj | ConvertTo-Json -Depth 3
    $outPath = Join-Path $TransDir "$lang.json"
    [System.IO.File]::WriteAllText($outPath, $json, $utf8NoBom)
    Write-Host "Written: $outPath ($($obj.Count) keys)"
}

Write-Host ""
Write-Host "=== i18n script complete! ==="
