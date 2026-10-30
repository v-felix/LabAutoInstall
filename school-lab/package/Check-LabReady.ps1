#requires -Version 5.1
<# Read-only check for the teacher, run in the Windows account used in class. #>
[CmdletBinding()]
param([string]$PackageRoot = '')
$ErrorActionPreference = 'Stop'
if (-not $PackageRoot) { $PackageRoot = $PSScriptRoot }
try {
    $lock = Get-Content -LiteralPath (Join-Path $PackageRoot 'package-lock.json') -Raw | ConvertFrom-Json
    $machineLogRoot = Join-Path $env:ProgramData "SchoolLab\Logs\$env:COMPUTERNAME"
    $matches = @()
    if (Test-Path -LiteralPath $machineLogRoot) {
        foreach ($directory in Get-ChildItem -LiteralPath $machineLogRoot -Directory) {
            $path = Join-Path $directory.FullName 'result.json'
            if (Test-Path -LiteralPath $path) {
                try {
                    $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
                    if ($data.PackageId -eq $lock.PackageId) {
                        $matches += [pscustomobject]@{ Path = $path; Data = $data; Modified = (Get-Item -LiteralPath $path).LastWriteTimeUtc }
                    }
                } catch { Write-Verbose "Cannot read report ${path}: $_" }
            }
        }
    }
    $latest = $matches | Sort-Object Modified -Descending | Select-Object -First 1
    if (-not $latest) {
        Write-Host 'CHUA SAN SANG: Chua co ket qua cai dat cua bo cai nay tren may.' -ForegroundColor Yellow
        Write-Host 'Giao vien chay Install-Lab.cmd bang quyen Administrator truoc.'
        exit 2
    }
    $machine = $latest.Data
    if ($machine.Status -eq 'DeferredReboot') {
        Write-Host 'CAN KHOI DONG LAI: Sau do chay lai Install-Lab.cmd.' -ForegroundColor Yellow
        Write-Host "Log: $($latest.Path)"
        exit 3010
    }
    # Chrome can be retried independently after the base applications passed.
    if (($machine.ExitCode -notin @(0,3010) -or $machine.Status -notin @('MachinePassed_UserLogonRequired','MachinePassed_UserReady')) -and
        $machine.Status -ne 'MachinePassed_ChromeSetupFailed') {
        Write-Host 'CHUA SAN SANG: Buoc cai dat may chua thanh cong.' -ForegroundColor Red
        Write-Host "Chi tiet: $($machine.Error)"
        Write-Host "Log: $($latest.Path)"
        exit 1
    }
    if ($machine.RebootRequired) {
        $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        if ($boot.ToUniversalTime() -le ([datetimeoffset]::Parse($machine.FinishedAt)).UtcDateTime) {
            Write-Host 'CAN KHOI DONG LAI: Cai dat da xong, hay Restart va dang nhap lai tai khoan dung trong lop.' -ForegroundColor Yellow
            exit 3010
        }
    }
    $userPath = Join-Path $env:LOCALAPPDATA 'SchoolLab\result.json'
    if (-not (Test-Path -LiteralPath $userPath)) {
        Write-Host 'DANG CHO TAI KHOAN: Giao vien Restart va dang nhap lai dung tai khoan dung trong lop.' -ForegroundColor Yellow
        Write-Host 'Neu vua dang nhap, doi vai phut roi bam Check-LabReady.cmd lai.'
        exit 2
    }
    $user = Get-Content -LiteralPath $userPath -Raw | ConvertFrom-Json
    if ($user.Status -ne 'Passed') {
        Write-Host 'CHUA SAN SANG: Khoi tao tai khoan chua thanh cong.' -ForegroundColor Red
        Write-Host "Chi tiet: $($user.Error)"
        Write-Host "Log: $userPath"
        exit 1
    }
    if ($user.PackageId -ne $lock.PackageId) {
        Write-Host 'DANG CHO TAI KHOAN: Ket qua tai khoan thuoc bo cai cu.' -ForegroundColor Yellow
        Write-Host 'Giao vien dang xuat/dang nhap lai, doi vai phut roi kiem tra lai.'
        exit 2
    }
    $shortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'SchoolLab C++.lnk'
    if (-not (Test-Path -LiteralPath $shortcut) -or -not (Test-Path -LiteralPath $user.Workspace)) {
        Write-Host 'CHUA SAN SANG: Thieu shortcut hoac thu muc bai tap.' -ForegroundColor Yellow
        Write-Host 'Giao vien dang xuat/dang nhap lai de thu khoi tao lai.'
        exit 2
    }
    foreach ($language in @('Java','Python')) {
        if (-not (Test-Path -LiteralPath (Join-Path ([Environment]::GetFolderPath('Desktop')) "SchoolLab $language.lnk"))) {
            Write-Host "CHUA SAN SANG: Thieu shortcut SchoolLab $language." -ForegroundColor Yellow
            exit 2
        }
    }
    $config = Import-PowerShellDataFile (Join-Path $PackageRoot 'LabConfig.psd1')
    if ($config.EnableChromeExtension) {
        $chromeRoot = Join-Path $env:LOCALAPPDATA 'SchoolLab\Chrome'
        $chrome = Get-Content -LiteralPath (Join-Path $chromeRoot 'result.json') -Raw | ConvertFrom-Json
        $heartbeat = Get-Content -LiteralPath (Join-Path $chromeRoot 'heartbeat.json') -Raw | ConvertFrom-Json
        $expected = Get-Content -LiteralPath (Join-Path $chromeRoot 'expected.json') -Raw | ConvertFrom-Json
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $actualHash = (Get-FileHash -LiteralPath (Join-Path $expected.extensionDirectory 'config.js') -Algorithm SHA256).Hash
        $sourceHash = (Get-FileHash -LiteralPath (Join-Path $PackageRoot 'Files\ChromeExtension\config.js') -Algorithm SHA256).Hash
        if ($chrome.Status -ne 'Passed' -or $chrome.PackageId -ne $lock.PackageId -or $chrome.UserSid -ne $sid -or
            $chrome.ConfigSha256 -ine $lock.ChromeExtension.configSha256 -or $actualHash -ine $lock.ChromeExtension.configSha256 -or $sourceHash -ine $lock.ChromeExtension.configSha256 -or
            $heartbeat.token -ne $expected.token -or $heartbeat.packageId -ne $lock.PackageId -or $heartbeat.userSid -ne $sid -or
            $heartbeat.phase -notin @('WAITING','ACTIVE','ENDED','DISABLED')) {
            throw 'SFIT chua xac nhan dung goi/lich/tai khoan. Chay Install-ChromeExtension.cmd de cau hinh OLBDB.'
        }
        Write-Host "SFIT: Da xac nhan profile $($chrome.ProfileDirectory) luc $($chrome.At). Lich: $($lock.ChromeExtension.startAt) -> $($lock.ChromeExtension.endAt)."
        Write-Host 'Day la ket qua cai dat; mo SFIT Tracker > Kiem tra lai de xac nhan hoat dong hien tai.'
        Import-Module (Join-Path $PackageRoot 'Chrome.Profile.psm1') -Force
        $profile = Get-Content -LiteralPath (Join-Path $chromeRoot 'profile-state.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($profile.Schema -ne 4 -or $profile.Status -ne 'Ready' -or $profile.UserSid -ne $sid -or
            $profile.UserDataDirectory -ine (Get-SfitChromeDataPath $env:LOCALAPPDATA) -or $profile.ProfileLayout -ne 'DedicatedOLBDB' -or
            $profile.ProfileName -ne 'OLBDB' -or -not $profile.Unpinned -or $chrome.ProfileDirectory -ne $profile.ProfileDirectory) { throw 'Dedicated OLBDB profile verification is missing.' }
        $selected = Get-SfitChromeProfileSelection $env:LOCALAPPDATA $profile.ProfilePath
        if ($selected.ProfileDirectory -ne $profile.ProfileDirectory -or -not (Test-Path -LiteralPath $selected.ProfilePath -PathType Container)) { throw 'The selected Chrome profile is missing.' }
        $exam = Get-Content -LiteralPath (Join-Path $chromeRoot 'olbdb-profile.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $owner = Get-Content -LiteralPath (Join-Path $selected.ProfilePath 'SchoolLab.Profile.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($exam.UserSid -ne $sid -or $exam.ProfileDirectory -ne $profile.ProfileDirectory -or $owner.ProfileToken -cne $exam.ProfileToken -or $owner.UserSid -ne $sid) { throw 'OLBDB profile ownership mismatch.' }
        if (-not (Test-Path -LiteralPath $profile.Shortcut -PathType Leaf)) { throw 'Missing OLBDB desktop shortcut.' }
        $wsh = New-Object -ComObject WScript.Shell; $link = $wsh.CreateShortcut($profile.Shortcut)
        $arguments = '--profile-directory="{0}" --new-window "{1}"' -f $profile.ProfileDirectory,$lock.ChromeExtension.examUrl
        if ($link.TargetPath -ine $expected.chromeExecutable -or $link.Arguments -cne $arguments) { throw 'OLBDB shortcut no longer opens the configured exam profile/site.' }
        Write-Host "Chrome: giu nguyen profile cu; mo shortcut OLBDB de vao $($lock.ChromeExtension.examUrl) dung profile thi."
    }
    Write-Host 'SAN SANG: Cai dat may va kiem tra tu dong trong tai khoan nay da dat.' -ForegroundColor Green
    Write-Host "May: $env:COMPUTERNAME | Tai khoan: $env:USERNAME"
    Write-Host "Thu muc bai tap: $($user.Workspace)"
    Write-Host 'Desktop: SchoolLab C++, SchoolLab Java, SchoolLab Python. Giao vien mo bai mau va thu F5 truoc khi ban giao.'
    Write-Host "Log may: $($latest.Path)"
    Write-Host "Log tai khoan: $userPath"
    exit 0
} catch {
    Write-Host 'KHONG DOC DUOC KET QUA: Hay chay kiem tra tu thu muc bo cai day du.' -ForegroundColor Red
    Write-Host "Chi tiet: $_"
    exit 1
}
