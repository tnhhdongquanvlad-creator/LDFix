# LDFix - Gỡ lỗi tab LDPlayer 4
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

# ================= Giao diện =================
$form = New-Object System.Windows.Forms.Form
$form.Text = "LDFix — Gỡ lỗi tab LDPlayer 4"
$form.Size = New-Object System.Drawing.Size(680, 560)
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

$btnFix = New-Object System.Windows.Forms.Button
$btnFix.Text = "GỠ LỖI TAB ĐÃ CHỌN"; $btnFix.Location = "12,312"; $btnFix.Size = "250,40"
$btnFix.Font = New-Object System.Drawing.Font("Segoe UI", 10.5, [System.Drawing.FontStyle]::Bold)
$btnFix.BackColor = "#2E7D32"; $btnFix.ForeColor = "White"
$form.Controls.Add($btnFix)

$btnCopy = New-Object System.Windows.Forms.Button
$btnCopy.Text = "Chép sang tab có sẵn..."; $btnCopy.Location = "272,312"; $btnCopy.Size = "180,40"
$form.Controls.Add($btnCopy)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "Làm mới"; $btnRefresh.Location = "462,312"; $btnRefresh.Size = "90,40"
$form.Controls.Add($btnRefresh)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = "12,362"; $txtLog.Size = "640,145"
$txtLog.Multiline = $true; $txtLog.ScrollBars = "Vertical"; $txtLog.ReadOnly = $true
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$form.Controls.Add($txtLog)

function Selected-Index {
    if ($lv.SelectedItems.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show("Hãy chọn 1 tab trong danh sách trước.", "LDFix") | Out-Null; return $null }
    return [int]$lv.SelectedItems[0].Tag
}

function Set-Busy($b) { foreach ($c in $btnFix, $btnCopy, $btnRefresh, $btnDir, $lv) { $c.Enabled = -not $b } }

$btnDir.Add_Click({
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = "Chọn thư mục LDPlayer 4 (chứa dnplayer.exe)"
    if ($d.ShowDialog() -eq "OK") {
        if (Test-LdDir $d.SelectedPath) { $script:LdDir = $d.SelectedPath; Refresh-List }
        else { [System.Windows.Forms.MessageBox]::Show("Thư mục này không phải LDPlayer 4 (không thấy dnplayer.exe và thư mục vms).", "LDFix") | Out-Null }
    }
})

$btnRefresh.Add_Click({ Refresh-List })

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
    Log "Chọn tab bị lỗi rồi bấm 'GỠ LỖI TAB ĐÃ CHỌN'."
})

[void]$form.ShowDialog()
