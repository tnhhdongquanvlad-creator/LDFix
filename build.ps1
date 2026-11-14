# Build LDFix.exe + đóng gói LDFix.zip (chạy trên GitHub Actions, windows-latest)
$ErrorActionPreference = "Stop"
Install-Module ps2exe -Scope CurrentUser -Force
Invoke-ps2exe -inputFile .\LDFix.ps1 -outputFile .\LDFix.exe -noConsole -requireAdmin -STA `
    -title "LDFix" -description "Go loi / cuu game tab LDPlayer 4" -version "3.3.0"

$seven = "$env:ProgramFiles\7-Zip"
if (-not (Test-Path "$seven\7z.exe")) { choco install 7zip -y --no-progress }
New-Item -ItemType Directory -Force dist | Out-Null
Copy-Item .\LDFix.exe, "$seven\7z.exe", "$seven\7z.dll" dist\
Copy-Item "$seven\License.txt" dist\7-Zip-License.txt
Compress-Archive dist\* LDFix.zip -Force
Get-ChildItem dist, LDFix.zip | Format-Table Name, Length
