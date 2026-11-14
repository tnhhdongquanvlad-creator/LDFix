# LDFix v2 - Gỡ lỗi / cứu game từ tab LDPlayer 4
# Cách làm: tạo tab mới, chép data.vmdk + sdcard.vmdk từ tab lỗi sang tab mới.
# Tab cũ KHÔNG bị xoá và được sao lưu trước khi làm.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:LdDir = $null

# ================= Hàm xử lý =================
function Test-LdDir($p) {
    $p -and (Test-Path (Join-Path $p "vms")) -and
    ((Test-Path (Join-Path $p "dnplayer.exe")) -or (Test-Path (Join-Path $p "ldconsole.exe")))
}

function Find-LdDir {
    $cands = @()
    foreach ($key in "HKCU:\Software\leidian\ldplayer", "HKLM:\Software\leidian\ldplayer", "HKLM:\Software\WOW6432Node\leidian\ldplayer") {
        try { $v = (Get-ItemProperty $key -ErrorAction Stop).InstallDir; if ($v) { $cands += $v } } catch {}
    }
    foreach ($drv in (Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root })) {
        $cands += "${drv}LDPlayer\LDPlayer4.0", "${drv}LDPlayer\LDPlayer4", "${drv}LDPlayer4.0", "${drv}LDPlayer4",
                  "${drv}Program Files\LDPlayer\LDPlayer4.0", "${drv}ChangZhi\LDPlayer4.0", "${drv}ChangZhi\dnplayer2"
    }
    foreach ($c in $cands) { if (Test-LdDir $c) { return (Resolve-Path $c).Path } }
    return $null
}

function Vms     { Join-Path $script:LdDir "vms" }
function LdConsole { Join-Path $script:LdDir "ldconsole.exe" }
function HasConsole { Test-Path (LdConsole) }

function Log($msg) {
    $txtLog.AppendText("$(Get-Date -Format HH:mm:ss)  $msg`r`n")
    [System.Windows.Forms.Application]::DoEvents()
}

function Wait-Sec($s) {
    $end = (Get-Date).AddSeconds($s)
    while ((Get-Date) -lt $end) { Start-Sleep -Milliseconds 200; [System.Windows.Forms.Application]::DoEvents() }
}

function Get-Instances {
    $list = @{}
    if (HasConsole) {
        foreach ($line in (& (LdConsole) list2 2>$null)) {
            $f = $line -split ","
            if ($f.Count -ge 2 -and $f[0] -match '^\d+$') { $list[[int]$f[0]] = $f[1] }
        }
    }
    Get-ChildItem (Vms) -Directory -Filter "leidian*" -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -match '^leidian(\d+)$') { $i = [int]$Matches[1]; if (-not $list.ContainsKey($i)) { $list[$i] = "(không rõ tên)" } }
    }
    return $list
}

function Get-DataSize($idx) {
    $p = Join-Path (Vms) "leidian$idx\data.vmdk"
    if (Test-Path $p) { return (Get-Item $p).Length } else { return -1 }
}

function Stop-LD {
    Log "Đang tắt toàn bộ LDPlayer..."
    if (HasConsole) { & (LdConsole) quitall 2>$null | Out-Null; Wait-Sec 3 }
    Get-Process | Where-Object { $_.Name -match '^(dnplayer|dnmultiplayer|LdVBoxHeadless|LdBoxHeadless|LdVBoxSVC|LdBoxSVC)$' } |
        ForEach-Object { try { $_.Kill() } catch {} }
    Wait-Sec 2
}

function Refresh-List {
    $lv.Items.Clear()
    if (-not (Test-LdDir $script:LdDir)) { $lblDir.Text = "Chưa tìm thấy LDPlayer 4 — bấm 'Chọn thư mục'"; return }
    $lblDir.Text = "LDPlayer: $script:LdDir"
    $inst = Get-Instances
    foreach ($k in ($inst.Keys | Sort-Object)) {
        $size = Get-DataSize $k
        $it = New-Object System.Windows.Forms.ListViewItem([string]$k)
        [void]$it.SubItems.Add($inst[$k])
        if ($size -lt 0) { [void]$it.SubItems.Add("không có"); [void]$it.SubItems.Add("Không cứu được"); $it.ForeColor = "Red" }
        elseif ($size -lt 1MB) { [void]$it.SubItems.Add("{0:N1} MB" -f ($size/1MB)); [void]$it.SubItems.Add("data.vmdk có thể đã hỏng"); $it.ForeColor = "DarkOrange" }
        else { [void]$it.SubItems.Add("{0:N0} MB" -f ($size/1MB)); [void]$it.SubItems.Add("") }
        $it.Tag = $k
        [void]$lv.Items.Add($it)
    }
}

function Ask($text) {
    [System.Windows.Forms.MessageBox]::Show($text, "LDFix", "YesNo", "Question") -eq "Yes"
}

function Repair-Tab($src) {
    $Vms = Vms
    $SrcDir = Join-Path $Vms "leidian$src"
    if (-not (Test-Path (Join-Path $SrcDir "data.vmdk"))) { Log "Tab [$src] không còn data.vmdk — không cứu được."; return }

    if (-not (Ask "Tool sẽ:`n1. Tắt LDPlayer`n2. Sao lưu tab [$src]`n3. Tạo tab mới`n4. Chép dữ liệu tab [$src] sang tab mới`n`nTab cũ được giữ nguyên. Tiếp tục?")) { return }

    Stop-LD

    # --- Sao lưu ---
    if ($chkBackup.Checked) {
        $need = (Get-ChildItem $SrcDir -File | Measure-Object Length -Sum).Sum
        $free = (Get-PSDrive ((Get-Item $script:LdDir).PSDrive.Name)).Free
        if ($free -lt ($need * 2 + 1GB)) {
            if (-not (Ask ("Ổ đĩa còn {0:N1} GB, cần khoảng {1:N1} GB để sao lưu + tạo tab mới.`nBỏ qua sao lưu và làm tiếp?" -f ($free/1GB), (($need*2+1GB)/1GB)))) { Log "Đã huỷ."; return }
        } else {
            $Backup = Join-Path $script:LdDir ("LDFix_Backup\leidian{0}_{1}" -f $src, (Get-Date -Format "yyyyMMdd_HHmmss"))
            Log "Đang sao lưu sang $Backup (có thể mất vài phút)..."
            New-Item -ItemType Directory -Force $Backup | Out-Null
            Copy-Item (Join-Path $SrcDir "*") $Backup -Recurse -Force
            $cfg = Join-Path $Vms "config\leidian$src.config"
            if (Test-Path $cfg) { Copy-Item $cfg $Backup -Force }
            Log "Sao lưu xong."
        }
    }

    # --- Tạo tab mới ---
    $dst = $null
    if (HasConsole) {
        $before = @((Get-Instances).Keys)
        Log "Đang tạo tab mới 'Fix_tab$src'..."
        & (LdConsole) add --name "Fix_tab$src" 2>$null | Out-Null
        Wait-Sec 3
        $dst = (Get-Instances).Keys | Where-Object { $before -notcontains $_ } | Sort-Object | Select-Object -Last 1
    }
    if ($null -eq $dst) {
        Log "Không tự tạo được tab mới (không có ldconsole.exe hoặc lệnh lỗi)."
        [System.Windows.Forms.MessageBox]::Show("Hãy tạo tay 1 tab mới trong LD Multi-Player, bật lên 1 lần rồi tắt.`nSau đó chọn tab lỗi và bấm 'Gỡ lỗi' lại — hoặc dùng nút 'Chép sang tab có sẵn'.", "LDFix") | Out-Null
        Refresh-List; return
    }
    Log "Tab mới: [$dst]"
    Copy-TabData $src $dst
}

function Copy-TabData($src, $dst) {
    $Vms = Vms
    $SrcDir = Join-Path $Vms "leidian$src"
    $DstDir = Join-Path $Vms "leidian$dst"

    # Tab mới chưa có file ổ đĩa -> bật lên 1 lần để LDPlayer tạo
    if (-not (Test-Path (Join-Path $DstDir "data.vmdk")) -and (HasConsole)) {
        Log "Bật tab mới 1 lần để khởi tạo (đợi tối đa 3 phút)..."
        & (LdConsole) launch --index $dst 2>$null | Out-Null
        $t = 0
        while (-not (Test-Path (Join-Path $DstDir "data.vmdk")) -and $t -lt 180) { Wait-Sec 5; $t += 5 }
        Wait-Sec 20
        Stop-LD
    }
    if (-not (Test-Path $DstDir)) { Log "Không thấy thư mục $DstDir — dừng."; return }

    foreach ($n in "data.vmdk", "sdcard.vmdk") {
        $s = Join-Path $SrcDir $n
        if (Test-Path $s) { Log "Đang chép $n ..."; Copy-Item $s (Join-Path $DstDir $n) -Force }
        else { Log "Bỏ qua $n (tab cũ không có)" }
    }
    Log "XONG! Dữ liệu tab [$src] đã sang tab [$dst]."
    Refresh-List

    if ((HasConsole) -and (Ask "Xong! Mở tab mới [$dst] ngay bây giờ?")) {
        & (LdConsole) launch --index $dst 2>$null | Out-Null
    }
    Log "Nếu tab mới vẫn lỗi: data.vmdk của tab cũ đã hỏng. Bản sao lưu nằm trong $script:LdDir\LDFix_Backup"
}

# ================= v2: Cứu game (đọc bên trong data.vmdk) =================
# Đọc ổ đĩa tab lỗi bằng 7-Zip (chỉ đọc), lấy APK + /data/data/<game>,
# cài vào một tab sạch đã bật Root rồi chép dữ liệu game vào.

function Get-7z {
    $cands = @()
    if ($PSScriptRoot) { $cands += Join-Path $PSScriptRoot "7z.exe" }
    $cands += (Join-Path ([AppDomain]::CurrentDomain.BaseDirectory) "7z.exe"),
              "$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
    foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return $c } }
    return $null
}

function Quote-Arg([string]$a) { if ($a -match '[\s"]' -or $a -eq '') { '"' + ($a -replace '"', '\"') + '"' } else { $a } }

# Chạy exe ẩn, không treo giao diện, trả về mã thoát + output
function Run-Exe([string]$exe, [string[]]$argList, [int]$timeoutSec = 3600) {
    $out = [IO.Path]::GetTempFileName(); $err = [IO.Path]::GetTempFileName()
    $argStr = ($argList | ForEach-Object { Quote-Arg $_ }) -join ' '
    $p = Start-Process -FilePath $exe -ArgumentList $argStr -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $out -RedirectStandardError $err
    [void]$p.Handle
    $end = (Get-Date).AddSeconds($timeoutSec)
    while (-not $p.HasExited) {
        if ((Get-Date) -gt $end) { try { $p.Kill() } catch {}; break }
        Start-Sleep -Milliseconds 200; [System.Windows.Forms.Application]::DoEvents()
    }
    $r = [pscustomobject]@{
        Code = $p.ExitCode
        Out  = [IO.File]::ReadAllText($out, [Text.Encoding]::UTF8)
        Err  = [IO.File]::ReadAllText($err, [Text.Encoding]::UTF8)
    }
    Remove-Item $out, $err -ErrorAction SilentlyContinue
    return $r
}

# Liệt kê mọi file/thư mục trong ảnh đĩa
function Get-7zEntries($img) {
    $r = Run-Exe $script:SevenZ @('l', '-slt', $img)
    $list = New-Object System.Collections.Generic.List[object]
    $cur = $null; $started = $false
    foreach ($line in ($r.Out -split "`r?`n")) {
        if ($line -eq '----------') { $started = $true; continue }
        if (-not $started) { continue }
        if ($line -like 'Path = *') {
            if ($cur) { $list.Add($cur) }
            $cur = [pscustomobject]@{ Path = $line.Substring(7); Size = [int64]0; IsDir = $false }
        } elseif ($cur -and $line -like 'Size = *') {
            $v = $line.Substring(7); if ($v -match '^\d+$') { $cur.Size = [int64]$v }
        } elseif ($cur -and ($line -eq 'Folder = +' -or $line -match '^Attributes = D')) { $cur.IsDir = $true }
    }
    if ($cur) { $list.Add($cur) }
    return $list
}

# Mở tới tận hệ thống file ext4 bên trong vmdk (có thể phải bóc 1-2 lớp ảnh đĩa)
function Open-Disk($vmdk, $work) {
    $img = $vmdk
    for ($lvl = 0; $lvl -lt 3; $lvl++) {
        $entries = Get-7zEntries $img
        if ($entries.Count -gt 20) { return [pscustomobject]@{ Img = $img; Entries = $entries } }
        if ($entries.Count -eq 0) { throw "7-Zip không đọc được $img" }
        $inner = $entries | Where-Object { -not $_.IsDir } | Sort-Object Size -Descending | Select-Object -First 1
        $free = (Get-PSDrive ((Get-Item $work).PSDrive.Name)).Free
        if ($inner.Size -gt ($free - 2GB)) { throw ("Cần {0:N1} GB trống để mở ổ đĩa, ổ hiện còn {1:N1} GB" -f ($inner.Size/1GB), ($free/1GB)) }
        Log ("Đang bóc lớp ảnh đĩa '{0}' ({1:N1} GB), có thể mất vài phút..." -f $inner.Path, ($inner.Size/1GB))
        $dir = Join-Path $work "lvl$lvl"
        [void](Run-Exe $script:SevenZ @('x', $img, "-o$dir", '-y', $inner.Path))
        $img = Join-Path $dir $inner.Path
        if (-not (Test-Path $img)) { throw "Không bóc được $($inner.Path)" }
    }
    throw "Không tìm thấy hệ thống file trong $vmdk"
}

# Tìm game/app đã cài: app\<package>-N\base.apk
function Find-Apps($entries) {
    $apps = @()
    foreach ($e in $entries) {
        if ($e.Path -match '^(?<pre>(.*\\)?)app\\(?<dir>(?<pkg>[A-Za-z0-9_.]+)-[^\\]+)\\base\.apk$') {
            $apps += [pscustomobject]@{ Pkg = $Matches.pkg; Pre = $Matches.pre; Dir = $Matches.dir; Size = $e.Size }
        }
    }
    return $apps | Sort-Object Size -Descending
}

function Pick-Apps($apps) {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = "Chọn game cần cứu"; $f.Size = "520,420"; $f.StartPosition = "CenterParent"
    $f.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = "Các app/game tìm thấy trong tab lỗi (tick game cần cứu):"; $l.Location = "12,10"; $l.Size = "480,22"
    $c = New-Object System.Windows.Forms.CheckedListBox
    $c.Location = "12,36"; $c.Size = "480,260"; $c.CheckOnClick = $true
    foreach ($a in $apps) { [void]$c.Items.Add(("{0}   ({1:N0} MB)" -f $a.Pkg, ($a.Size/1MB))) }
    $sd = New-Object System.Windows.Forms.CheckBox
    $sd.Text = "Chép cả dữ liệu tải thêm của game (Android/data, obb)"; $sd.Checked = $true
    $sd.Location = "12,302"; $sd.Size = "480,24"
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = "Cứu game đã chọn"; $ok.Location = "332,332"; $ok.Size = "160,34"; $ok.DialogResult = "OK"
    $f.Controls.AddRange(@($l, $c, $sd, $ok)); $f.AcceptButton = $ok
    if ($f.ShowDialog() -ne "OK") { return $null }
    $sel = @(); foreach ($i in $c.CheckedIndices) { $sel += $apps[$i] }
    return [pscustomobject]@{ Apps = $sel; WithSd = $sd.Checked }
}

function Adb([string[]]$a, [int]$t = 600) { Run-Exe $script:Adb (@('-s', $script:Serial) + $a) $t }

function Start-Target($idx) {
    Log "Bật Root cho tab [$idx]..."
    & (LdConsole) modify --index $idx --root 1 2>$null | Out-Null
    Log "Đang bật tab [$idx] và đợi Android khởi động (tối đa 4 phút)..."
    & (LdConsole) launch --index $idx 2>$null | Out-Null
    $script:Serial = "emulator-{0}" -f (5554 + 2 * $idx)
    $end = (Get-Date).AddMinutes(4)
    while ((Get-Date) -lt $end) {
        Wait-Sec 5
        $dev = (Run-Exe $script:Adb @('devices') 30).Out
        if ($dev -notmatch [regex]::Escape($script:Serial) + '\s+device') {
            $tcp = "127.0.0.1:{0}" -f (5555 + 2 * $idx)
            [void](Run-Exe $script:Adb @('connect', $tcp) 15)
            if ((Run-Exe $script:Adb @('devices') 30).Out -match [regex]::Escape($tcp) + '\s+device') { $script:Serial = $tcp } else { continue }
        }
        if ((Adb @('shell', 'getprop sys.boot_completed') 20).Out.Trim() -eq '1') { Wait-Sec 10; Log "Tab [$idx] đã khởi động xong."; return $true }
    }
    return $false
}

function Rescue-Game($src) {
    $script:SevenZ = Get-7z
    if (-not $script:SevenZ) { [System.Windows.Forms.MessageBox]::Show("Không thấy 7z.exe. Hãy giải nén đủ bộ LDFix.zip (LDFix.exe + 7z.exe + 7z.dll) vào cùng 1 thư mục, hoặc cài 7-Zip.", "LDFix") | Out-Null; return }
    $script:Adb = Join-Path $script:LdDir "adb.exe"
    if (-not (Test-Path $script:Adb)) { Log "Không thấy adb.exe trong thư mục LDPlayer."; return }
    if (-not (HasConsole)) { Log "Không thấy ldconsole.exe trong thư mục LDPlayer."; return }

    $SrcDir = Join-Path (Vms) "leidian$src"
    $work = Join-Path $script:LdDir "LDFix_Work"
    if (Test-Path $work) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force $work | Out-Null

    try {
        Stop-LD
        Log "Đang đọc ổ đĩa tab [$src] (chỉ đọc, không sửa tab cũ)..."
        $disk = Open-Disk (Join-Path $SrcDir "data.vmdk") $work
        $apps = @(Find-Apps $disk.Entries)
        if ($apps.Count -eq 0) { Log "Không tìm thấy app/game nào trong tab [$src]."; return }
        Log "Tìm thấy $($apps.Count) app/game."
        $pick = Pick-Apps $apps
        if (-not $pick -or $pick.Apps.Count -eq 0) { Log "Đã huỷ."; return }

        # --- Lấy file game ra ---
        $out = Join-Path $work "out"
        foreach ($a in $pick.Apps) {
            Log "Đang lấy file cài + dữ liệu của $($a.Pkg)..."
            $d = "$($a.Pre)data\$($a.Pkg)"
            $r = Run-Exe $script:SevenZ @('x', $disk.Img, "-o$out", '-y', "$($a.Pre)app\$($a.Dir)", $d,
                                         "-x!$d\lib", "-x!$d\cache", "-x!$d\code_cache")
            if ($r.Code -gt 1) { Log "  Cảnh báo 7-Zip: $($r.Err.Trim())" }
        }
        $sdOut = Join-Path $work "sd"
        if ($pick.WithSd -and (Test-Path (Join-Path $SrcDir "sdcard.vmdk"))) {
            try {
                Log "Đang đọc sdcard của tab [$src]..."
                $sdDisk = Open-Disk (Join-Path $SrcDir "sdcard.vmdk") (New-Item -ItemType Directory -Force (Join-Path $work "sdimg")).FullName
                foreach ($a in $pick.Apps) {
                    $hits = $sdDisk.Entries | Where-Object { $_.IsDir -and $_.Path -match ('(^|\\)Android\\(data|obb)\\' + [regex]::Escape($a.Pkg) + '$') }
                    foreach ($h in $hits) {
                        Log "  Lấy $($h.Path)..."
                        [void](Run-Exe $script:SevenZ @('x', $sdDisk.Img, "-o$sdOut", '-y', $h.Path))
                        $a | Add-Member -NotePropertyName ("Sd_" + ($h.Path -replace '.*Android\\(data|obb)\\.*', '$1')) -NotePropertyValue (Join-Path $sdOut $h.Path) -Force
                    }
                }
            } catch { Log "  Không đọc được sdcard ($($_.Exception.Message)) — bỏ qua phần này." }
        }

        # --- Tạo tab sạch, bật Root, khởi động ---
        $before = @((Get-Instances).Keys)
        Log "Đang tạo tab sạch 'Game_tab$src'..."
        & (LdConsole) add --name "Game_tab$src" 2>$null | Out-Null
        Wait-Sec 3
        $dst = (Get-Instances).Keys | Where-Object { $before -notcontains $_ } | Sort-Object | Select-Object -Last 1
        if ($null -eq $dst) { Log "Không tạo được tab mới."; return }
        if (-not (Start-Target $dst)) { Log "Tab mới không khởi động được trong 4 phút — dừng."; return }

        $isRoot = (Adb @('shell', 'id') 20).Out -match 'uid=0'
        foreach ($a in $pick.Apps) {
            $appDir = Join-Path $out "$($a.Pre)app\$($a.Dir)"
            $dataDir = Join-Path $out "$($a.Pre)data\$($a.Pkg)"
            $apks = @(Get-ChildItem $appDir -Filter *.apk -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
            if ($apks.Count -eq 0) { Log "Không lấy được file cài của $($a.Pkg) — bỏ qua."; continue }

            Log "Đang cài $($a.Pkg)..."
            $r = if ($apks.Count -eq 1) { Adb (@('install', '-r', '-d') + $apks) 900 } else { Adb (@('install-multiple', '-r', '-d') + $apks) 900 }
            if ($r.Out -notmatch 'Success') { Log "  Cài thất bại: $(($r.Out + $r.Err).Trim())"; continue }

            if (Test-Path $dataDir) {
                Log "Đang chép dữ liệu game vào máy..."
                [void](Adb @('shell', 'rm -rf /data/local/tmp/ldfix; mkdir -p /data/local/tmp/ldfix') 30)
                [void](Adb @('push', $dataDir, "/data/local/tmp/ldfix/$($a.Pkg)") 1800)
                $sh = @(
                    "PKG=$($a.Pkg)", 'D=/data/data/$PKG', 'S=/data/local/tmp/ldfix/$PKG',
                    'am force-stop $PKG',
                    'O=$(stat -c %U $D); G=$(stat -c %G $D)',
                    'if [ -z "$O" ]; then echo LDFIX_NODIR; exit 1; fi',
                    'for f in $S/* $S/.[!.]*; do',
                    '  [ -e "$f" ] || continue; n=$(basename "$f")',
                    '  case "$n" in lib|cache|code_cache) continue;; esac',
                    '  rm -rf "$D/$n"; cp -r "$f" "$D/"; chown -R $O:$G "$D/$n"',
                    'done',
                    'restorecon -R $D >/dev/null 2>&1',
                    'rm -rf /data/local/tmp/ldfix',
                    'echo LDFIX_OK') -join "`n"
                $shFile = Join-Path $work "ldfix.sh"
                [IO.File]::WriteAllText($shFile, $sh + "`n", (New-Object Text.UTF8Encoding($false)))
                [void](Adb @('push', $shFile, '/data/local/tmp/ldfix.sh') 30)
                $cmd = if ($isRoot) { 'sh /data/local/tmp/ldfix.sh' } else { "su -c 'sh /data/local/tmp/ldfix.sh'" }
                $r = Adb @('shell', $cmd) 600
                if ($r.Out -match 'LDFIX_OK') { Log "  Đã chép dữ liệu game." }
                else { Log "  Chép dữ liệu lỗi (có thể chưa có Root): $(($r.Out + $r.Err).Trim())" }
            } else { Log "  Không có dữ liệu riêng của game trong tab cũ." }

            foreach ($kind in 'data', 'obb') {
                $p = $a.PSObject.Properties["Sd_$kind"]
                if ($p -and (Test-Path $p.Value)) {
                    Log "  Đang chép Android/$kind/$($a.Pkg)..."
                    [void](Adb @('push', $p.Value, "/sdcard/Android/$kind/$($a.Pkg)") 3600)
                }
            }
            Log "Mở game $($a.Pkg)..."
            [void](Adb @('shell', "monkey -p $($a.Pkg) -c android.intent.category.LAUNCHER 1") 30)
        }
        Log "XONG! Game đã được cứu sang tab [$dst] 'Game_tab$src'."
        Refresh-List
    } finally {
        Log "Dọn file tạm..."
        Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ================= Giao diện =================
$form = New-Object System.Windows.Forms.Form
$form.Text = "LDFix v2 — Gỡ lỗi tab LDPlayer 4"
$form.Size = New-Object System.Drawing.Size(680, 610)
$form.StartPosition = "CenterScreen"
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)

$lblDir = New-Object System.Windows.Forms.Label
$lblDir.Location = "12,12"; $lblDir.Size = "520,22"
$form.Controls.Add($lblDir)

$btnDir = New-Object System.Windows.Forms.Button
$btnDir.Text = "Chọn thư mục"; $btnDir.Location = "540,8"; $btnDir.Size = "112,28"
$form.Controls.Add($btnDir)

$lv = New-Object System.Windows.Forms.ListView
$lv.Location = "12,42"; $lv.Size = "640,230"
$lv.View = "Details"; $lv.FullRowSelect = $true; $lv.MultiSelect = $false; $lv.HideSelection = $false
[void]$lv.Columns.Add("Số", 50); [void]$lv.Columns.Add("Tên tab", 230)
[void]$lv.Columns.Add("data.vmdk", 110); [void]$lv.Columns.Add("Ghi chú", 220)
$form.Controls.Add($lv)

$chkBackup = New-Object System.Windows.Forms.CheckBox
$chkBackup.Text = "Sao lưu tab lỗi trước khi sửa (khuyên dùng)"; $chkBackup.Checked = $true
$chkBackup.Location = "12,282"; $chkBackup.Size = "330,24"
$form.Controls.Add($chkBackup)

$btnRescue = New-Object System.Windows.Forms.Button
$btnRescue.Text = "CỨU GAME TỪ TAB LỖI"; $btnRescue.Location = "12,312"; $btnRescue.Size = "640,44"
$btnRescue.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$btnRescue.BackColor = "#2E7D32"; $btnRescue.ForeColor = "White"
$form.Controls.Add($btnRescue)

$btnFix = New-Object System.Windows.Forms.Button
$btnFix.Text = "Chép nguyên tab (cách cũ)"; $btnFix.Location = "12,362"; $btnFix.Size = "250,40"
$form.Controls.Add($btnFix)

$btnCopy = New-Object System.Windows.Forms.Button
$btnCopy.Text = "Chép sang tab có sẵn..."; $btnCopy.Location = "272,362"; $btnCopy.Size = "180,40"
$form.Controls.Add($btnCopy)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "Làm mới"; $btnRefresh.Location = "462,362"; $btnRefresh.Size = "90,40"
$form.Controls.Add($btnRefresh)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = "12,412"; $txtLog.Size = "640,145"
$txtLog.Multiline = $true; $txtLog.ScrollBars = "Vertical"; $txtLog.ReadOnly = $true
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$form.Controls.Add($txtLog)

function Selected-Index {
    if ($lv.SelectedItems.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show("Hãy chọn 1 tab trong danh sách trước.", "LDFix") | Out-Null; return $null }
    return [int]$lv.SelectedItems[0].Tag
}

function Set-Busy($b) { foreach ($c in $btnRescue, $btnFix, $btnCopy, $btnRefresh, $btnDir, $lv) { $c.Enabled = -not $b } }

$btnDir.Add_Click({
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = "Chọn thư mục LDPlayer 4 (chứa dnplayer.exe)"
    if ($d.ShowDialog() -eq "OK") {
        if (Test-LdDir $d.SelectedPath) { $script:LdDir = $d.SelectedPath; Refresh-List }
        else { [System.Windows.Forms.MessageBox]::Show("Thư mục này không phải LDPlayer 4 (không thấy dnplayer.exe và thư mục vms).", "LDFix") | Out-Null }
    }
})

$btnRefresh.Add_Click({ Refresh-List })

$btnRescue.Add_Click({
    $i = Selected-Index; if ($null -eq $i) { return }
    if (-not (Ask "Tool sẽ:`n1. Tắt LDPlayer`n2. Đọc ổ đĩa tab [$i] (chỉ đọc), cho bạn chọn game cần cứu`n3. Tạo tab sạch mới, tự bật Root`n4. Cài game + chép dữ liệu game sang tab mới`n`nTab cũ giữ nguyên. Tiếp tục?")) { return }
    Set-Busy $true
    try { Rescue-Game $i } catch { Log "LỖI: $($_.Exception.Message)" } finally { Set-Busy $false }
})

$btnFix.Add_Click({
    $i = Selected-Index; if ($null -eq $i) { return }
    Set-Busy $true
    try { Repair-Tab $i } catch { Log "LỖI: $($_.Exception.Message)" } finally { Set-Busy $false }
})

$btnCopy.Add_Click({
    $i = Selected-Index; if ($null -eq $i) { return }
    $dst = [Microsoft.VisualBasic.Interaction]::InputBox("Nhập SỐ của tab đích (tab mới, đã bật 1 lần):", "LDFix", "")
    if ($dst -notmatch '^\d+$' -or [int]$dst -eq $i) { return }
    if (-not (Ask "Dữ liệu trong tab [$dst] sẽ bị GHI ĐÈ bằng dữ liệu tab [$i]. Tiếp tục?")) { return }
    Set-Busy $true
    try { Stop-LD; Copy-TabData $i ([int]$dst) } catch { Log "LỖI: $($_.Exception.Message)" } finally { Set-Busy $false }
})
Add-Type -AssemblyName Microsoft.VisualBasic

$form.Add_Shown({
    $script:LdDir = Find-LdDir
    Refresh-List
    Log "Chọn tab bị lỗi rồi bấm 'CỨU GAME TỪ TAB LỖI'."
})

[void]$form.ShowDialog()
