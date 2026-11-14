# LDFix v3.1 - Gỡ lỗi / cứu game từ tab LDPlayer 4
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

# ================= v3: Cứu game =================
# Cách 1 (ưu tiên): bật tab lỗi lên (đứng 94% nhưng Android vẫn chạy), bật Root,
#                   lấy APK + /data/data/<game> qua ADB. Không cần ổ trống lớn.
# Cách 2 (dự phòng): đọc bên trong data.vmdk bằng 7-Zip, làm việc trên ổ còn trống nhiều nhất.
# Sau đó: tạo tab sạch, bật Root, cài game, chép dữ liệu game vào.

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

# Thư mục tạm trên ổ cứng còn trống nhiều nhất (C:, D:, ...)
function Get-WorkDir {
    $best = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Sort-Object FreeSpace -Descending | Select-Object -First 1
    $dir = Join-Path ($best.DeviceID + "\") "LDFix_Work"
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force $dir | Out-Null
    Log ("Thư mục tạm: {0} (ổ {1} còn {2:N1} GB)" -f $dir, $best.DeviceID, ($best.FreeSpace / 1GB))
    return $dir
}

function Get-FreeBytes($path) {
    $drv = (Get-Item $path).PSDrive.Name + ":"
    return (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$drv'").FreeSpace
}

# ---------- ADB ----------
function Adb([string[]]$a, [int]$t = 600) { Run-Exe $script:Adb (@('-s', $script:Serial) + $a) $t }

function RootSh([string]$cmd, [int]$t = 600) {
    if ($script:IsRoot) { Adb @('shell', $cmd) $t } else { Adb @('shell', "su -c '$cmd'") $t }
}

# Chạy 1 đoạn script shell trên máy ảo với quyền root
function Run-RootScript([string[]]$lines, [string]$work, [int]$t = 1800) {
    $shFile = Join-Path $work "ldfix.sh"
    [IO.File]::WriteAllText($shFile, (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
    [void](Adb @('push', $shFile, '/data/local/tmp/ldfix.sh') 30)
    return RootSh 'sh /data/local/tmp/ldfix.sh' $t
}

# Kết nối ADB tới tab $idx. $needBoot = phải đợi Android khởi động xong
function Connect-Adb($idx, [bool]$needBoot, [int]$minutes) {
    if (-not $script:AdbRestarted) {
        Get-Process | Where-Object { $_.Name -eq 'adb' } | ForEach-Object { try { $_.Kill() } catch {} }
        [void](Run-Exe $script:Adb @('start-server') 60)
        $script:AdbRestarted = $true
    }
    $emu = "emulator-{0}" -f (5554 + 2 * $idx)
    $tcp = "127.0.0.1:{0}" -f (5555 + 2 * $idx)
    $end = (Get-Date).AddMinutes($minutes)
    while ((Get-Date) -lt $end) {
        Wait-Sec 5
        $dev = (Run-Exe $script:Adb @('devices') 30).Out
        if ($dev -match ([regex]::Escape($emu) + '\s+device')) { $script:Serial = $emu }
        else {
            [void](Run-Exe $script:Adb @('connect', $tcp) 15)
            if ((Run-Exe $script:Adb @('devices') 30).Out -match ([regex]::Escape($tcp) + '\s+device')) { $script:Serial = $tcp } else { continue }
        }
        if (-not $needBoot) { return $true }
        if ((Adb @('shell', 'getprop sys.boot_completed') 20).Out.Trim() -eq '1') { Wait-Sec 10; return $true }
    }
    $dev = Run-Exe $script:Adb @('devices', '-l') 30
    Log ("  [chẩn đoán] adb devices: " + ((($dev.Out + $dev.Err) -split "`r?`n" | Where-Object { $_ -match '\S' }) -join ' | '))
    $lst = (& (LdConsole) list2 2>$null) | Where-Object { $_ -match "^$idx," }
    Log "  [chẩn đoán] ldconsole list2: $lst"
    Log "  [chẩn đoán] đã thử: $emu và $tcp"
    return $false
}

function Start-Tab($idx, [bool]$needBoot, [int]$minutes) {
    Log "Bật Root cho tab [$idx]..."
    & (LdConsole) modify --index $idx --root 1 2>$null | Out-Null
    Log "Đang mở tab [$idx]..."
    & (LdConsole) launch --index $idx 2>$null | Out-Null
    if (-not (Connect-Adb $idx $needBoot $minutes)) { return $false }
    $script:IsRoot = (Adb @('shell', 'id') 20).Out -match 'uid=0'
    return $true
}

# ---------- Chọn game ----------
function Pick-Apps($apps) {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = "Chọn game cần cứu"; $f.Size = "520,420"; $f.StartPosition = "CenterParent"
    $f.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = "Các app/game tìm thấy trong tab lỗi (tick game cần cứu):"; $l.Location = "12,10"; $l.Size = "480,22"
    $c = New-Object System.Windows.Forms.CheckedListBox
    $c.Location = "12,36"; $c.Size = "480,260"; $c.CheckOnClick = $true
    foreach ($a in $apps) {
        $txt = if ($a.Size -gt 0) { "{0}   ({1:N0} MB)" -f $a.Pkg, ($a.Size / 1MB) } else { $a.Pkg }
        [void]$c.Items.Add($txt)
    }
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

# ---------- Cách 1: lấy game qua ADB từ tab lỗi ----------
function Extract-ViaAdb($src, $work) {
    Log "CÁCH 1: mở tab lỗi [$src] để lấy game qua ADB (không cần ổ trống lớn)..."
    if (-not (Start-Tab $src $false 4)) { Log "  Không kết nối được ADB tới tab lỗi."; return $null }
    Log "  Đã kết nối ADB. Đợi Android gắn ổ dữ liệu..."
    $apps = @()
    for ($try = 0; $try -lt 12 -and $apps.Count -eq 0; $try++) {
        Wait-Sec 5
        foreach ($l in ((RootSh 'ls /data/app' 30).Out -split "`r?`n")) {
            $n = $l.Trim()
            if ($n -match '^(?<pkg>[A-Za-z0-9_.]+)-[^/\s]+$') { $apps += [pscustomobject]@{ Pkg = $Matches.pkg; Dir = $n; Size = [int64]0 } }
        }
    }
    if ($apps.Count -eq 0) { Log "  Không đọc được danh sách game qua ADB."; return $null }
    foreach ($l in ((RootSh 'du -sk /data/app/*' 60).Out -split "`r?`n")) {
        if ($l -match '^(\d+)\s+/data/app/(.+?)\s*$') {
            $k = [int64]$Matches[1]; $d = $Matches[2]
            foreach ($a in $apps) { if ($a.Dir -eq $d) { $a.Size = $k * 1KB } }
        }
    }
    $apps = @($apps | Sort-Object Size -Descending)
    Log "  Tìm thấy $($apps.Count) app/game."
    $pick = Pick-Apps $apps
    if (-not $pick -or $pick.Apps.Count -eq 0) { return [pscustomobject]@{ Cancel = $true } }

    foreach ($a in $pick.Apps) {
        Log "  Đang gom file của $($a.Pkg) trên máy ảo..."
        $withSd = if ($pick.WithSd) { 1 } else { 0 }
        $r = Run-RootScript @(
            "PKG=$($a.Pkg)", "DIR=$($a.Dir)", "WITHSD=$withSd", 'S=/data/local/tmp/ldfix_out',
            'rm -rf $S; mkdir -p $S/app $S/data $S/sd_data $S/sd_obb',
            'cp -r /data/app/$DIR $S/app/',
            'rm -rf $S/app/$DIR/lib $S/app/$DIR/oat',
            'cp -r /data/data/$PKG $S/data/',
            'rm -rf $S/data/$PKG/lib $S/data/$PKG/cache $S/data/$PKG/code_cache',
            'if [ "$WITHSD" = 1 ]; then',
            '  for p in /data/media/0 /storage/emulated/0 /sdcard /mnt/sdcard /storage/sdcard0; do',
            '    if [ -d $p/Android/data/$PKG ] || [ -d $p/Android/obb/$PKG ]; then',
            '      [ -d $p/Android/data/$PKG ] && cp -r $p/Android/data/$PKG $S/sd_data/',
            '      [ -d $p/Android/obb/$PKG ] && cp -r $p/Android/obb/$PKG $S/sd_obb/',
            '      echo SDROOT=$p; break',
            '    fi',
            '  done',
            'fi',
            'chmod -R 777 $S',
            'echo LDFIX_OK') $work 3600
        if ($r.Out -notmatch 'LDFIX_OK') { Log "  Gom file lỗi: $(($r.Out + $r.Err).Trim())"; continue }
        if ($r.Out -match 'SDROOT=(\S+)') { Log "  Có dữ liệu tải thêm ở $($Matches[1])" }

        $dst = Join-Path $work ("adb_" + $a.Pkg)
        Log "  Đang kéo file về máy tính..."
        [void](Adb @('pull', '/data/local/tmp/ldfix_out', $dst) 3600)
        $base = if (Test-Path (Join-Path $dst "ldfix_out")) { Join-Path $dst "ldfix_out" } else { $dst }
        $a | Add-Member -Force AppDir  (Join-Path $base "app\$($a.Dir)")
        $a | Add-Member -Force DataDir (Join-Path $base "data\$($a.Pkg)")
        $a | Add-Member -Force Sd_data (Join-Path $base "sd_data\$($a.Pkg)")
        $a | Add-Member -Force Sd_obb  (Join-Path $base "sd_obb\$($a.Pkg)")
        [void](RootSh 'rm -rf /data/local/tmp/ldfix_out /data/local/tmp/ldfix.sh' 120)
    }
    return $pick
}

# ---------- Cách 2: đọc bên trong data.vmdk bằng 7-Zip ----------
function Get-7zEntries($img, [string]$type = '') {
    $a = @('l', '-slt', $img); if ($type) { $a += "-t$type" }
    $r = Run-Exe $script:SevenZ $a
    $script:Last7z = $r
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

function Open-Disk($vmdk, $work) {
    $img = $vmdk
    for ($lvl = 0; $lvl -lt 3; $lvl++) {
        $entries = Get-7zEntries $img
        if ($entries.Count -le 20 -and $lvl -gt 0) {
            $e2 = Get-7zEntries $img 'Ext'
            if ($e2.Count -gt $entries.Count) { $entries = $e2 }
        }
        if ($entries.Count -gt 20) { return [pscustomobject]@{ Img = $img; Entries = $entries } }
        if ($entries.Count -eq 0) {
            $msg = (($script:Last7z.Err + "`n" + $script:Last7z.Out) -split "`r?`n" | Where-Object { $_ -match '\S' } | Select-Object -Last 4) -join ' | '
            throw "7-Zip không đọc được $img — chi tiết: $msg"
        }
        Log ("  Trong {0} có: {1}" -f (Split-Path $img -Leaf), (($entries | ForEach-Object { "{0} ({1:N1} GB)" -f $_.Path, ($_.Size / 1GB) }) -join ', '))
        $inner = $entries | Where-Object { -not $_.IsDir } | Sort-Object Size -Descending | Select-Object -First 1
        $free = Get-FreeBytes $work
        if ($inner.Size -gt ($free - 2GB)) {
            throw ("Cách 2 cần bung ổ ảo {0:N1} GB nhưng ổ trống nhất chỉ còn {1:N1} GB" -f ($inner.Size / 1GB), ($free / 1GB))
        }
        Log ("Đang bung ổ ảo '{0}' ({1:N1} GB), có thể mất 10-30 phút..." -f $inner.Path, ($inner.Size / 1GB))
        $dir = Join-Path $work "lvl$lvl"
        $t0 = Get-Date
        $r = Run-Exe $script:SevenZ @('x', $img, "-o$dir", '-y', $inner.Path) 7200
        $img = Join-Path $dir $inner.Path
        $got = if (Test-Path $img) { (Get-Item $img).Length } else { 0 }
        Log ("  7-Zip xong sau {0:N0} giây, mã {1}, file thật {2:N1} GB" -f ((Get-Date) - $t0).TotalSeconds, $r.Code, ($got / 1GB))
        if ($r.Code -ne 0) {
            $msg = (($r.Err + "`n" + $r.Out) -split "`r?`n" | Where-Object { $_ -match '\S' } | Select-Object -Last 4) -join ' | '
            Log "  Lỗi 7-Zip: $msg"
        }
        if ($got -eq 0) { throw "Không bung được $($inner.Path)" }
    }
    throw "Không tìm thấy hệ thống file trong $vmdk"
}

function Extract-Via7z($src, $work) {
    Log "CÁCH 2: đọc trực tiếp ổ đĩa ảo của tab [$src] bằng 7-Zip..."
    $script:SevenZ = Get-7z
    if (-not $script:SevenZ) { Log "  Không thấy 7z.exe cạnh LDFix.exe."; return $null }
    $SrcDir = Join-Path (Vms) "leidian$src"
    $disk = Open-Disk (Join-Path $SrcDir "data.vmdk") $work
    $apps = @()
    foreach ($e in $disk.Entries) {
        if ($e.Path -match '^(?<pre>(.*\\)?)app\\(?<dir>(?<pkg>[A-Za-z0-9_.]+)-[^\\]+)\\base\.apk$') {
            $apps += [pscustomobject]@{ Pkg = $Matches.pkg; Pre = $Matches.pre; Dir = $Matches.dir; Size = $e.Size }
        }
    }
    if ($apps.Count -eq 0) { Log "  Không tìm thấy game nào trong ổ đĩa."; return $null }
    $apps = @($apps | Sort-Object Size -Descending)
    $pick = Pick-Apps $apps
    if (-not $pick -or $pick.Apps.Count -eq 0) { return [pscustomobject]@{ Cancel = $true } }

    $out = Join-Path $work "out"
    foreach ($a in $pick.Apps) {
        Log "  Đang lấy file của $($a.Pkg)..."
        $d = "$($a.Pre)data\$($a.Pkg)"
        [void](Run-Exe $script:SevenZ @('x', $disk.Img, "-o$out", '-y', "$($a.Pre)app\$($a.Dir)", $d,
                                        "-x!$d\lib", "-x!$d\cache", "-x!$d\code_cache"))
        $a | Add-Member -Force AppDir  (Join-Path $out "$($a.Pre)app\$($a.Dir)")
        $a | Add-Member -Force DataDir (Join-Path $out $d)
    }
    if ($pick.WithSd -and (Test-Path (Join-Path $SrcDir "sdcard.vmdk"))) {
        try {
            $sdDisk = Open-Disk (Join-Path $SrcDir "sdcard.vmdk") (New-Item -ItemType Directory -Force (Join-Path $work "sdimg")).FullName
            $sdOut = Join-Path $work "sd"
            foreach ($a in $pick.Apps) {
                foreach ($h in ($sdDisk.Entries | Where-Object { $_.IsDir -and $_.Path -match ('(^|\\)Android\\(data|obb)\\' + [regex]::Escape($a.Pkg) + '$') })) {
                    [void](Run-Exe $script:SevenZ @('x', $sdDisk.Img, "-o$sdOut", '-y', $h.Path))
                    $kind = $h.Path -replace '.*Android\\(data|obb)\\.*', '$1'
                    $a | Add-Member -Force ("Sd_" + $kind) (Join-Path $sdOut $h.Path)
                }
            }
        } catch { Log "  Bỏ qua sdcard: $($_.Exception.Message)" }
    }
    return $pick
}

# ---------- Cài vào tab sạch ----------
function Restore-ToCleanTab($src, $pick, $work) {
    $before = @((Get-Instances).Keys)
    Log "Đang tạo tab sạch 'Game_tab$src'..."
    & (LdConsole) add --name "Game_tab$src" 2>$null | Out-Null
    Wait-Sec 3
    $dst = (Get-Instances).Keys | Where-Object { $before -notcontains $_ } | Sort-Object | Select-Object -Last 1
    if ($null -eq $dst) { Log "Không tạo được tab mới."; return }
    Log "Đợi tab sạch [$dst] khởi động (tối đa 5 phút)..."
    if (-not (Start-Tab $dst $true 5)) { Log "Tab sạch không khởi động được — dừng."; return }

    foreach ($a in $pick.Apps) {
        $apks = @(Get-ChildItem $a.AppDir -Filter *.apk -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        if ($apks.Count -eq 0) { Log "Không có file cài của $($a.Pkg) — bỏ qua."; continue }
        Log "Đang cài $($a.Pkg)..."
        $r = if ($apks.Count -eq 1) { Adb (@('install', '-r', '-d') + $apks) 900 } else { Adb (@('install-multiple', '-r', '-d') + $apks) 900 }
        if ($r.Out -notmatch 'Success') { Log "  Cài thất bại: $(($r.Out + $r.Err).Trim())"; continue }

        if (Test-Path $a.DataDir) {
            Log "  Đang chép dữ liệu game..."
            [void](RootSh 'rm -rf /data/local/tmp/ldfix; mkdir -p /data/local/tmp/ldfix; chmod 777 /data/local/tmp/ldfix' 30)
            [void](Adb @('push', $a.DataDir, "/data/local/tmp/ldfix/$($a.Pkg)") 1800)
            $r = Run-RootScript @(
                "PKG=$($a.Pkg)", 'D=/data/data/$PKG', 'S=/data/local/tmp/ldfix/$PKG',
                'am force-stop $PKG',
                'O=$(stat -c %U $D); G=$(stat -c %G $D)',
                'if [ -z "$O" ]; then echo LDFIX_NODIR; exit 1; fi',
                'for f in $S/* $S/.[!.]*; do',
                '  [ -e "$f" ] || continue; n=$(basename "$f")',
                '  case "$n" in lib|cache|code_cache) continue;; esac',
                '  rm -rf "$D/$n"; cp -r "$f" "$D/"; chown -R $O:$G "$D/$n"; chmod -R u+rwX,g+rwX "$D/$n"',
                'done',
                'restorecon -R $D >/dev/null 2>&1',
                'rm -rf /data/local/tmp/ldfix /data/local/tmp/ldfix.sh',
                'echo LDFIX_OK') $work 900
            if ($r.Out -match 'LDFIX_OK') { Log "  Đã chép dữ liệu game." } else { Log "  Chép dữ liệu lỗi: $(($r.Out + $r.Err).Trim())" }
        } else { Log "  Tab cũ không có dữ liệu riêng của game." }

        foreach ($kind in 'data', 'obb') {
            $p = $a.PSObject.Properties["Sd_$kind"]
            if ($p -and $p.Value -and (Test-Path $p.Value) -and (Get-ChildItem $p.Value -Force | Select-Object -First 1)) {
                Log "  Đang chép Android/$kind/$($a.Pkg) (có thể lâu)..."
                [void](Adb @('push', $p.Value, "/sdcard/Android/$kind/$($a.Pkg)") 7200)
            }
        }
        Log "Mở game $($a.Pkg)..."
        [void](Adb @('shell', "monkey -p $($a.Pkg) -c android.intent.category.LAUNCHER 1") 30)
    }
    Log "XONG! Game đã được cứu sang tab [$dst] 'Game_tab$src'."
    Refresh-List
}

function Rescue-Game($src) {
    $script:Adb = Join-Path $script:LdDir "adb.exe"
    if (-not (Test-Path $script:Adb)) { Log "Không thấy adb.exe trong thư mục LDPlayer."; return }
    if (-not (HasConsole)) { Log "Không thấy ldconsole.exe trong thư mục LDPlayer."; return }

    $work = Get-WorkDir
    try {
        Stop-LD
        $pick = $null
        try { $pick = Extract-ViaAdb $src $work } catch { Log "  Cách 1 lỗi: $($_.Exception.Message)" }
        Stop-LD
        if ($pick -and $pick.Cancel) { Log "Đã huỷ."; return }
        if (-not $pick) {
            Log "Cách 1 không được, chuyển sang cách 2..."
            try { $pick = Extract-Via7z $src $work } catch { Log "  Cách 2 lỗi: $($_.Exception.Message)" }
            if ($pick -and $pick.Cancel) { Log "Đã huỷ."; return }
        }
        if (-not $pick) { Log "Không lấy được game từ tab [$src]. Gửi ảnh log này để được hỗ trợ."; return }
        Restore-ToCleanTab $src $pick $work
    } finally {
        Log "Dọn file tạm..."
        Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ================= Giao diện =================
$form = New-Object System.Windows.Forms.Form
$form.Text = "LDFix v3.1 — Gỡ lỗi tab LDPlayer 4"
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
    if (-not (Ask "Tool sẽ:`n1. Tắt LDPlayer`n2. Mở tab lỗi [$i] (tự bật Root) để lấy game ra, cho bạn chọn game cần cứu`n3. Tạo tab sạch mới, tự bật Root`n4. Cài game + chép dữ liệu game sang tab mới`n`nTab cũ giữ nguyên. Tiếp tục?")) { return }
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
