# LDFix v3.4 - Gỡ lỗi / cứu game từ tab LDPlayer 4
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

# Đọc file kể cả khi tiến trình khác (vd adb server) còn giữ nó
function Read-Shared([string]$path) {
    try {
        $fs = New-Object IO.FileStream($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        try { $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8); return $sr.ReadToEnd() } finally { $fs.Dispose() }
    } catch { return '' }
}

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
        Out  = Read-Shared $out
        Err  = Read-Shared $err
    }
    Remove-Item $out, $err -Force -ErrorAction SilentlyContinue
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
        # Khởi động adb server KHÔNG chuyển hướng output, để server không giữ file tạm
        # (KHÔNG dùng Start-Process -Wait: nó đợi cả adb server chạy nền => treo mãi)
        try {
            $psi = New-Object Diagnostics.ProcessStartInfo($script:Adb, 'start-server')
            $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
            $sp = [Diagnostics.Process]::Start($psi)
            $end = (Get-Date).AddSeconds(30)
            while (-not $sp.HasExited -and (Get-Date) -lt $end) { Start-Sleep -Milliseconds 200; [System.Windows.Forms.Application]::DoEvents() }
        } catch {}
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

# ---------- Bộ đọc ext4 (chỉ đọc) — thay cho 7-Zip khi 7-Zip không mở được phân vùng Android ----------
$script:ExtCs = @'
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;

public class ExtEntry { public string Name; public uint Inode; public byte Type; }

public class ExtReader : IDisposable {
    FileStream fs;
    public int BlockSize;
    uint inodesPerGroup; int inodeSize; int descSize; long firstDataBlock;
    public string Info;
    public int Errors;
    Dictionary<uint, long> gd = new Dictionary<uint, long>();

    public ExtReader(string path) {
        fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite, 1 << 20);
        byte[] sb = ReadAt(1024, 1024);
        ushort magic = BitConverter.ToUInt16(sb, 56);
        if (magic != 0xEF53) {
            throw new Exception("khong phai ext4 (magic=" + magic.ToString("X4") + ", 16 byte dau=" + BitConverter.ToString(ReadAt(0, 16)) + ", byte 1024=" + BitConverter.ToString(ReadAt(1024, 16)) + ")");
        }
        BlockSize = 1024 << (int)BitConverter.ToUInt32(sb, 24);
        firstDataBlock = BitConverter.ToUInt32(sb, 20);
        inodesPerGroup = BitConverter.ToUInt32(sb, 40);
        inodeSize = BitConverter.ToUInt16(sb, 88); if (inodeSize == 0) inodeSize = 128;
        uint incompat = BitConverter.ToUInt32(sb, 96);
        descSize = ((incompat & 0x80) != 0) ? BitConverter.ToUInt16(sb, 254) : 32;
        if (descSize < 32) descSize = 32;
        Info = "ext4 block=" + BlockSize + " inode=" + inodeSize + " incompat=0x" + incompat.ToString("X") +
               " ro_compat=0x" + BitConverter.ToUInt32(sb, 100).ToString("X");
    }

    byte[] ReadAt(long off, int len) {
        byte[] b = new byte[len]; fs.Position = off; int r = 0;
        while (r < len) { int n = fs.Read(b, r, len - r); if (n <= 0) break; r += n; }
        return b;
    }

    long InodeTable(uint g) {
        long v; if (gd.TryGetValue(g, out v)) return v;
        byte[] d = ReadAt((firstDataBlock + 1) * BlockSize + (long)g * descSize, descSize);
        long t = BitConverter.ToUInt32(d, 8);
        if (descSize >= 64) t |= ((long)BitConverter.ToUInt32(d, 0x28)) << 32;
        gd[g] = t; return t;
    }

    public byte[] ReadInode(uint ino) {
        uint g = (ino - 1) / inodesPerGroup, i = (ino - 1) % inodesPerGroup;
        return ReadAt(InodeTable(g) * BlockSize + (long)i * inodeSize, inodeSize);
    }

    public static long Size(byte[] n) { return (long)BitConverter.ToUInt32(n, 4) | ((long)BitConverter.ToUInt32(n, 108) << 32); }
    public static int Mode(byte[] n) { return BitConverter.ToUInt16(n, 0); }
    static bool Inline(byte[] n) { return (BitConverter.ToUInt32(n, 32) & 0x10000000) != 0; }

    // {block logic, block vat ly (-1 = toan so 0), so block}
    public List<long[]> Extents(byte[] n) {
        List<long[]> res = new List<long[]>();
        byte[] ib = new byte[60]; Array.Copy(n, 40, ib, 0, 60);
        if ((BitConverter.ToUInt32(n, 32) & 0x80000) != 0) Walk(ib, res); else BlockMap(ib, res);
        return res;
    }

    void Walk(byte[] node, List<long[]> res) {
        if (BitConverter.ToUInt16(node, 0) != 0xF30A) throw new Exception("extent hong");
        int cnt = BitConverter.ToUInt16(node, 2), depth = BitConverter.ToUInt16(node, 6);
        for (int i = 0; i < cnt; i++) {
            int o = 12 + i * 12;
            if (depth == 0) {
                long lb = BitConverter.ToUInt32(node, o);
                int len = BitConverter.ToUInt16(node, o + 4);
                long st = ((long)BitConverter.ToUInt16(node, o + 6) << 32) | BitConverter.ToUInt32(node, o + 8);
                if (len > 32768) res.Add(new long[] { lb, -1, len - 32768 }); else res.Add(new long[] { lb, st, len });
            } else {
                long leaf = BitConverter.ToUInt32(node, o + 4) | ((long)BitConverter.ToUInt16(node, o + 8) << 32);
                Walk(ReadAt(leaf * BlockSize, BlockSize), res);
            }
        }
    }

    void BlockMap(byte[] ib, List<long[]> res) {
        for (int i = 0; i < 12; i++) { uint b = BitConverter.ToUInt32(ib, i * 4); if (b != 0) res.Add(new long[] { i, b, 1 }); }
        long per = BlockSize / 4, l = 12;
        uint a = BitConverter.ToUInt32(ib, 48); if (a != 0) Indirect(a, 1, ref l, res); else l += per;
        uint b2 = BitConverter.ToUInt32(ib, 52); if (b2 != 0) Indirect(b2, 2, ref l, res); else l += per * per;
        uint c = BitConverter.ToUInt32(ib, 56); if (c != 0) Indirect(c, 3, ref l, res);
    }

    void Indirect(uint blk, int level, ref long l, List<long[]> res) {
        byte[] d = ReadAt((long)blk * BlockSize, BlockSize); int per = BlockSize / 4;
        long span = 1; for (int k = 1; k < level; k++) span *= per;
        for (int i = 0; i < per; i++) {
            uint b = BitConverter.ToUInt32(d, i * 4);
            if (level == 1) { if (b != 0) res.Add(new long[] { l, b, 1 }); l++; }
            else if (b != 0) Indirect(b, level - 1, ref l, res); else l += span;
        }
    }

    byte[] ReadAll(byte[] n) {
        long size = Size(n);
        if (size > 256L * 1024 * 1024) throw new Exception("thu muc qua lon");
        byte[] buf = new byte[size];
        if (Inline(n)) { Array.Copy(n, 40, buf, 0, (int)Math.Min(size, 60)); return buf; }
        foreach (long[] e in Extents(n)) {
            if (e[1] < 0) continue;
            long off = e[0] * BlockSize; if (off >= size) continue;
            int len = (int)Math.Min(e[2] * BlockSize, size - off);
            Array.Copy(ReadAt(e[1] * BlockSize, len), 0, buf, off, len);
        }
        return buf;
    }

    public List<ExtEntry> ListDir(uint ino) {
        byte[] d = ReadAll(ReadInode(ino));
        List<ExtEntry> list = new List<ExtEntry>(); int p = 0;
        while (p + 8 <= d.Length) {
            uint inode = BitConverter.ToUInt32(d, p); int rec = BitConverter.ToUInt16(d, p + 4);
            int nl = d[p + 6];
            if (rec < 8) break;
            if (inode != 0 && nl > 0 && p + 8 + nl <= d.Length) {
                string name = Encoding.UTF8.GetString(d, p + 8, nl);
                if (name != "." && name != "..") { ExtEntry e = new ExtEntry(); e.Name = name; e.Inode = inode; e.Type = d[p + 7]; list.Add(e); }
            }
            p += rec;
        }
        return list;
    }

    public uint Lookup(string path) {
        uint cur = 2;
        foreach (string part in path.Split(new char[] { '/' }, StringSplitOptions.RemoveEmptyEntries)) {
            uint next = 0;
            foreach (ExtEntry e in ListDir(cur)) if (e.Name == part) { next = e.Inode; break; }
            if (next == 0) return 0;
            cur = next;
        }
        return cur;
    }

    public long FileSize(uint ino) { return Size(ReadInode(ino)); }
    public bool IsDir(uint ino) { return (Mode(ReadInode(ino)) & 0xF000) == 0x4000; }

    public void ExtractFile(uint ino, string dest) {
        byte[] n = ReadInode(ino); long size = Size(n);
        using (FileStream o = new FileStream(dest, FileMode.Create, FileAccess.Write)) {
            if (Inline(n)) { o.Write(n, 40, (int)Math.Min(size, 60)); return; }
            o.SetLength(size);
            byte[] buf = new byte[1 << 20];
            foreach (long[] e in Extents(n)) {
                if (e[1] < 0) continue;
                long off = e[0] * BlockSize; if (off >= size) continue;
                long len = Math.Min(e[2] * BlockSize, size - off);
                fs.Position = e[1] * BlockSize; o.Position = off;
                while (len > 0) { int r = fs.Read(buf, 0, (int)Math.Min(buf.Length, len)); if (r <= 0) break; o.Write(buf, 0, r); len -= r; }
            }
        }
    }

    static string Safe(string name) {
        foreach (char c in Path.GetInvalidFileNameChars()) name = name.Replace(c, '_');
        return name;
    }

    public int ExtractTree(uint ino, string dest, string[] skipTop) {
        Directory.CreateDirectory(dest); int count = 0;
        foreach (ExtEntry e in ListDir(ino)) {
            if (skipTop != null && Array.IndexOf(skipTop, e.Name) >= 0) continue;
            try {
                byte[] n = ReadInode(e.Inode); int fmt = Mode(n) & 0xF000;
                string p = Path.Combine(dest, Safe(e.Name));
                if (fmt == 0x4000) count += ExtractTree(e.Inode, p, null);
                else if (fmt == 0x8000) { ExtractFile(e.Inode, p); count++; }
            } catch { Errors++; }
        }
        return count;
    }

    public void Dispose() { fs.Dispose(); }
}
'@

function Load-ExtReader { if (-not ('ExtReader' -as [type])) { Add-Type -TypeDefinition $script:ExtCs -Language CSharp } }

function Err-Text($ex) { if ($ex.InnerException) { $ex.InnerException.Message } else { $ex.Message } }

# Bung từng phân vùng trong vmdk bằng 7-Zip rồi mở bằng bộ đọc ext4.
# $want: đường dẫn phải có trong phân vùng (vd '/app'); rỗng = nhận phân vùng ext4 đầu tiên lớn nhất.
function Open-ExtFromVmdk($vmdk, $work, $tag, [string[]]$want) {
    Load-ExtReader
    $parts = @(Get-7zEntries $vmdk | Where-Object { -not $_.IsDir } | Sort-Object Size -Descending)
    if ($parts.Count -eq 0) { throw "7-Zip không đọc được $vmdk" }
    Log ("  Trong {0} có: {1}" -f (Split-Path $vmdk -Leaf), (($parts | ForEach-Object { "{0} ({1:N1} GB)" -f $_.Path, ($_.Size / 1GB) }) -join ', '))
    foreach ($p in $parts) {
        $free = Get-FreeBytes $work
        if ($p.Size -gt ($free - 2GB)) { Log ("  Bỏ qua {0}: cần {1:N1} GB, ổ còn {2:N1} GB" -f $p.Path, ($p.Size / 1GB), ($free / 1GB)); continue }
        $dir = Join-Path $work $tag
        Log ("  Đang bung {0} ({1:N1} GB)..." -f $p.Path, ($p.Size / 1GB))
        $r7 = Run-Exe $script:SevenZ @('x', $vmdk, "-o$dir", '-y', $p.Path) 7200
        $img = Join-Path $dir $p.Path
        if (-not (Test-Path $img)) { Log "  Không bung được $($p.Path) (mã $($r7.Code))"; continue }
        try {
            $rd = New-Object ExtReader($img)
            Log "  $($p.Path): $($rd.Info)"
            $ok = (-not $want)
            foreach ($w in $want) { if ($rd.Lookup($w) -ne 0) { $ok = $true; break } }
            if ($ok) { $script:Readers += $rd; return $rd }
            Log "  $($p.Path) không chứa $($want -join ' / ')"
            $rd.Dispose()
        } catch { Log "  $($p.Path): $(Err-Text $_.Exception)" }
        Remove-Item $img -Force -ErrorAction SilentlyContinue
    }
    return $null
}

function Extract-Via7z($src, $work) {
    Log "CÁCH 2: đọc trực tiếp ổ đĩa ảo của tab [$src]..."
    $script:SevenZ = Get-7z
    if (-not $script:SevenZ) { Log "  Không thấy 7z.exe cạnh LDFix.exe."; return $null }
    $SrcDir = Join-Path (Vms) "leidian$src"
    $rd = Open-ExtFromVmdk (Join-Path $SrcDir "data.vmdk") $work 'data' @('/app')
    if (-not $rd) { Log "  Không tìm thấy phân vùng dữ liệu Android."; return $null }

    $apps = @()
    foreach ($e in $rd.ListDir($rd.Lookup('/app'))) {
        if ($e.Name -match '^(?<pkg>[A-Za-z0-9_.]+)-[^/]+$') {
            $b = $rd.Lookup("/app/$($e.Name)/base.apk")
            $size = if ($b -ne 0) { $rd.FileSize($b) } else { 0 }
            $apps += [pscustomobject]@{ Pkg = $Matches.pkg; Dir = $e.Name; Size = [int64]$size }
        }
    }
    if ($apps.Count -eq 0) { Log "  Không tìm thấy game nào trong /app."; return $null }
    $apps = @($apps | Sort-Object Size -Descending)
    Log "  Tìm thấy $($apps.Count) app/game."
    $pick = Pick-Apps $apps
    if (-not $pick -or $pick.Apps.Count -eq 0) { return [pscustomobject]@{ Cancel = $true } }

    $out = Join-Path $work "out"
    foreach ($a in $pick.Apps) {
        Log "  Đang lấy file cài của $($a.Pkg)..."
        $appDir = Join-Path $out "app\$($a.Dir)"
        New-Item -ItemType Directory -Force $appDir | Out-Null
        foreach ($f in $rd.ListDir($rd.Lookup("/app/$($a.Dir)"))) {
            if ($f.Name -like '*.apk') { $rd.ExtractFile($f.Inode, (Join-Path $appDir $f.Name)); [System.Windows.Forms.Application]::DoEvents() }
        }
        $dataDir = Join-Path $out "data\$($a.Pkg)"
        $di = $rd.Lookup("/data/$($a.Pkg)")
        if ($di -ne 0) {
            Log "  Đang lấy dữ liệu game..."
            $n = $rd.ExtractTree($di, $dataDir, [string[]]@('lib', 'cache', 'code_cache'))
            Log "  Lấy được $n file dữ liệu (lỗi: $($rd.Errors))."
        } else { Log "  Không có /data/$($a.Pkg) trong tab cũ." }
        $a | Add-Member -Force AppDir $appDir
        $a | Add-Member -Force DataDir $dataDir
    }

    if ($pick.WithSd -and (Test-Path (Join-Path $SrcDir "sdcard.vmdk"))) {
        try {
            $bases = @('/Android', '/media/0/Android', '/0/Android', '/data/media/0/Android', '/emulated/0/Android')
            $sd = Open-ExtFromVmdk (Join-Path $SrcDir "sdcard.vmdk") $work 'sd' $bases
            $base = $null
            if ($sd) { foreach ($b in $bases) { if ($sd.Lookup($b) -ne 0) { $base = $b; break } } }
            # Android/data trong phân vùng data (khi sdcard nằm chung ổ data)
            if (-not $base) { foreach ($b in '/media/0/Android') { if ($rd.Lookup($b) -ne 0) { $sd = $rd; $base = $b; break } } }
            if ($base) {
                foreach ($a in $pick.Apps) {
                    foreach ($kind in 'data', 'obb') {
                        $ino = $sd.Lookup("$base/$kind/$($a.Pkg)")
                        if ($ino -ne 0) {
                            Log "  Đang lấy Android/$kind/$($a.Pkg) (có thể lâu)..."
                            $dst = Join-Path $work "sdout\$kind\$($a.Pkg)"
                            [void]$sd.ExtractTree($ino, $dst, $null)
                            $a | Add-Member -Force ("Sd_" + $kind) $dst
                        }
                    }
                }
            } else { Log "  Không thấy thư mục Android trên sdcard — bỏ qua." }
        } catch { Log "  Bỏ qua sdcard: $(Err-Text $_.Exception)" }
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
    $script:Readers = @()
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
        foreach ($r in $script:Readers) { try { $r.Dispose() } catch {} }
        $script:Readers = @()
        Log "Dọn file tạm..."
        Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ================= Giao diện =================
$form = New-Object System.Windows.Forms.Form
$form.Text = "LDFix v3.4 — Gỡ lỗi tab LDPlayer 4"
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
