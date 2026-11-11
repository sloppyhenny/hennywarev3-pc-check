# ==============================================================================
# HennyWare v3 - Roblox PC check toolkit
# Made by sloppyhenny
# ==============================================================================

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Windows.Forms

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$installDir = "$env:USERPROFILE\Downloads\HennyWare"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)


# ==============================================================================
# BUILT-IN ROBLOX CHECKS (read-only scans, they run in their own console window)
# ==============================================================================

$ScriptInstall = @'
$ErrorActionPreference = 'SilentlyContinue'
Write-Host "`n=== HennyWare: Roblox install + signature check ===" -ForegroundColor Magenta
$roots = @(
    "$env:LOCALAPPDATA\Roblox\Versions",
    "$env:ProgramFiles\Roblox\Versions",
    "${env:ProgramFiles(x86)}\Roblox\Versions"
) | Where-Object { Test-Path $_ }

if (-not $roots) { Write-Host 'No Roblox Versions folder found.' -ForegroundColor Yellow }

foreach ($r in $roots) {
    Write-Host "`nRoot: $r" -ForegroundColor Cyan
    foreach ($v in Get-ChildItem $r -Directory) {
        Write-Host ("  {0}  (modified {1})" -f $v.Name, $v.LastWriteTime)
        $flagged = 0
        foreach ($f in Get-ChildItem $v.FullName -Recurse -File -Include *.dll,*.exe) {
            $sig = Get-AuthenticodeSignature -LiteralPath $f.FullName
            $rel = $f.FullName.Replace($v.FullName, '.')
            if ($sig.Status -ne 'Valid') {
                $flagged++
                $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
                Write-Host ("    [{0}] {1}" -f $sig.Status, $rel) -ForegroundColor Yellow
                Write-Host ("        SHA256 {0} | modified {1}" -f $hash, $f.LastWriteTime) -ForegroundColor DarkGray
            }
            elseif ($sig.SignerCertificate.Subject -notmatch 'Roblox|Microsoft') {
                $flagged++
                Write-Host ("    [Other signer] {0}" -f $rel) -ForegroundColor Yellow
                Write-Host ("        {0}" -f $sig.SignerCertificate.Subject) -ForegroundColor DarkGray
            }
        }
        if (-not $flagged) { Write-Host '    All binaries validly signed by Roblox/Microsoft.' -ForegroundColor Green }

        $ff = Join-Path $v.FullName 'ClientSettings\ClientAppSettings.json'
        if (Test-Path $ff) {
            Write-Host '    FastFlag file present (ClientAppSettings.json):' -ForegroundColor Yellow
            Get-Content $ff -Raw | Write-Host -ForegroundColor DarkGray
        }
    }
}

Write-Host "`nAlternative bootstrappers / mod folders:" -ForegroundColor Cyan
$found = $false
foreach ($p in @("$env:LOCALAPPDATA\Bloxstrap", "$env:LOCALAPPDATA\Fishstrap", "$env:LOCALAPPDATA\Voidstrap")) {
    if (Test-Path $p) { $found = $true; Write-Host "  Present: $p (legit tools, but ask about FastFlags/mods)" -ForegroundColor Yellow }
}
if (-not $found) { Write-Host '  None found.' -ForegroundColor Green }

Write-Host "`nNote: unsigned or odd files are indicators to review, not proof of cheating." -ForegroundColor DarkGray
'@

$ScriptModules = @'
$ErrorActionPreference = 'SilentlyContinue'
Write-Host "`n=== HennyWare: modules loaded in Roblox ===" -ForegroundColor Magenta
$procs = Get-Process -Name RobloxPlayerBeta, RobloxPlayerLauncher, RobloxStudioBeta
if (-not $procs) {
    Write-Host 'Roblox is not running. Join a game first, then run this again.' -ForegroundColor Yellow
    return
}
$trusted = @("$env:windir\*", "$env:ProgramFiles\*", "${env:ProgramFiles(x86)}\*", '*\Roblox\Versions\*')
foreach ($p in $procs) {
    Write-Host ("`n{0} (PID {1}) started {2}" -f $p.ProcessName, $p.Id, $p.StartTime) -ForegroundColor Cyan
    $mods = $null
    try { $mods = $p.Modules } catch {}
    if (-not $mods) { Write-Host '  Could not read modules. Run HennyWare as Administrator.' -ForegroundColor Red; continue }
    $count = 0
    foreach ($m in $mods) {
        $path = $m.FileName
        $sig  = Get-AuthenticodeSignature -LiteralPath $path
        $ok   = $false
        foreach ($t in $trusted) { if ($path -like $t) { $ok = $true; break } }
        if ($sig.Status -ne 'Valid' -or -not $ok) {
            $count++
            Write-Host ("  [{0}] {1}" -f $sig.Status, $path) -ForegroundColor Yellow
        }
    }
    if (-not $count) { Write-Host '  Nothing unusual: all modules signed and in trusted folders.' -ForegroundColor Green }
}
'@

$ScriptLogs = @'
$ErrorActionPreference = 'SilentlyContinue'
Write-Host "`n=== HennyWare: Roblox log review ===" -ForegroundColor Magenta
$logDir = "$env:LOCALAPPDATA\Roblox\logs"
if (-not (Test-Path $logDir)) { Write-Host 'No Roblox logs folder found (logs may have been cleared).' -ForegroundColor Yellow; return }

Write-Host "`nNewest log files (check for gaps or wiped history):" -ForegroundColor Cyan
Get-ChildItem $logDir -File | Sort-Object LastWriteTime -Descending | Select-Object -First 15 Name,
    @{ n = 'Modified'; e = { $_.LastWriteTime } }, @{ n = 'KB'; e = { [int]($_.Length / 1KB) } } | Format-Table -AutoSize

Write-Host 'Suspicious keyword hits:' -ForegroundColor Cyan
$kw = '(?i)synapse|krnl|fluxus|solara|\bxeno\b|jjsploit|script-?ware|celery|sirhurt|executor|injector|exploit|autoexec'
$hits = Select-String -Path "$logDir\*" -Pattern $kw | Select-Object -First 40
if ($hits) {
    foreach ($h in $hits) {
        $line = $h.Line.Trim()
        if ($line.Length -gt 160) { $line = $line.Substring(0, 160) }
        Write-Host ("  {0}:{1}  {2}" -f $h.Filename, $h.LineNumber, $line) -ForegroundColor Yellow
    }
} else { Write-Host '  None.' -ForegroundColor Green }

Write-Host "`nUser IDs seen in logs (best effort):" -ForegroundColor Cyan
$ids = Select-String -Path "$logDir\*" -Pattern '(?i)user_?id"?\s*[:=]\s*"?(\d{5,})' |
    ForEach-Object { $_.Matches[0].Groups[1].Value } | Sort-Object -Unique | Select-Object -First 10
if ($ids) { $ids | ForEach-Object { Write-Host "  https://www.roblox.com/users/$_/profile" } } else { Write-Host '  None found.' }
'@

$ScriptExecutors = @'
$ErrorActionPreference = 'SilentlyContinue'
Write-Host "`n=== HennyWare: executor / injector leftover scan ===" -ForegroundColor Magenta
Write-Host 'Searching common folders (depth 4). This can take a minute...' -ForegroundColor DarkGray
$rx = '(?i)synapse|krnl|fluxus|solara|\bxeno\b|jjsploit|script-?ware|celery|sirhurt|\bevon\b|arceus|hydrogen|vegax|valex|trigon|wearedevs|executor|injector|\bexploit'
$roots = @(
    "$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Documents",
    $env:LOCALAPPDATA, $env:APPDATA, $env:TEMP, $env:ProgramData, $env:USERPROFILE
) | Select-Object -Unique
$seen = @{}
foreach ($root in $roots) {
    if (-not (Test-Path $root)) { continue }
    Write-Host "  scanning $root" -ForegroundColor DarkGray
    Get-ChildItem -LiteralPath $root -Recurse -Depth 4 -Force | Where-Object {
        $_.Name -match $rx -and $_.FullName -notmatch '\\HennyWare\\'
    } | ForEach-Object {
        if (-not $seen.ContainsKey($_.FullName)) {
            $seen[$_.FullName] = $true
            Write-Host ("  {0}  ({1})" -f $_.FullName, $_.LastWriteTime) -ForegroundColor Yellow
        }
    }
}
if ($seen.Count -eq 0) { Write-Host "`nNothing matched." -ForegroundColor Green }
else { Write-Host ("`n{0} item(s) matched. Review each one, names can be false positives." -f $seen.Count) -ForegroundColor Cyan }
'@

$ScriptBam = @'
$ErrorActionPreference = 'SilentlyContinue'
Write-Host "`n=== HennyWare: recent executions (BAM) ===" -ForegroundColor Magenta
$base = 'HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings'
if (-not (Test-Path $base)) { $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\bam\UserSettings' }
$rows = foreach ($sid in Get-ChildItem $base) {
    $key = Get-Item $sid.PSPath
    foreach ($n in $key.GetValueNames()) {
        $v = $key.GetValue($n)
        if ($v -is [byte[]] -and $v.Length -ge 8) {
            $t = $null
            try { $t = [DateTime]::FromFileTimeUtc([BitConverter]::ToInt64($v, 0)).ToLocalTime() } catch { continue }
            [pscustomobject]@{ Time = $t; Path = $n }
        }
    }
}
if (-not $rows) { Write-Host 'No BAM entries readable. Run HennyWare as Administrator.' -ForegroundColor Red; return }
$rows | Sort-Object Time -Descending | Select-Object -First 80 | Format-Table -AutoSize -Wrap
'@


# ==============================================================================
# TOOL DATA
# Types: GitHub (latest release), Web (direct file or page), Link (opens browser),
#        Cmd (runs a remote script in a new window), Local (built-in check)
# Cli = command-line tool, opens a PowerShell prompt in its folder instead
# ==============================================================================

function New-Tool {
    param($Name, $Desc, $Category, $Type, $Source, [switch]$Cli)
    $t = @{ Name = $Name; Desc = $Desc; Category = $Category; Type = $Type; Cli = [bool]$Cli; Url = $null; Command = $null }
    if ($Type -in 'Cmd', 'Local') { $t.Command = $Source } else { $t.Url = $Source }
    return $t
}

$ToolData = @(
    # Roblox Checks (built in)
    (New-Tool "Install + Signatures"   "Checks Roblox files for unsigned or odd DLLs"   "Roblox Checks" "Local" $ScriptInstall),
    (New-Tool "Loaded Modules"         "Lists unusual modules inside running Roblox"    "Roblox Checks" "Local" $ScriptModules),
    (New-Tool "Roblox Log Review"      "Log timeline, keyword hits, user IDs seen"      "Roblox Checks" "Local" $ScriptLogs),
    (New-Tool "Executor Leftovers"     "Scans common folders for executor/injector names" "Roblox Checks" "Local" $ScriptExecutors),
    (New-Tool "Recent Executions"      "Last programs run, read from the BAM registry"  "Roblox Checks" "Local" $ScriptBam),
    (New-Tool "MacroDetector"          "Detects macro / clicker software traces"        "Roblox Checks" "Cmd" "Invoke-Expression (Invoke-RestMethod 'https://raw.githubusercontent.com/NiccBlahh/MacroDetector/refs/heads/main/MacroDetector.ps1')"),
    (New-Tool "Hotspot Logs"           "Checks hotspot / tethering history"             "Roblox Checks" "Cmd" "iwr https://raw.githubusercontent.com/praiselily/WeHateFakers/refs/heads/main/HotspotLogs.ps1 | iex"),

    # Orbdiff
    (New-Tool "PrefetchView"      "Parses prefetch, extracts file info"        "Orbdiff" "GitHub" "https://github.com/Orbdiff/PrefetchView/releases/latest"),
    (New-Tool "BAMReveal"         "Parses BAM forensic artefact"               "Orbdiff" "GitHub" "https://github.com/Orbdiff/BAMReveal/releases/latest"),
    (New-Tool "StringsParser"     "Strings + YARA + signatures scanner"        "Orbdiff" "GitHub" "https://github.com/Orbdiff/StringsParser/releases/latest"),
    (New-Tool "Fileless"          "Detects fileless via eventlog + memdump"    "Orbdiff" "GitHub" "https://github.com/Orbdiff/Fileless/releases/latest"),
    (New-Tool "DPS-Analyzer"      "Analyzes DPS memory"                        "Orbdiff" "GitHub" "https://github.com/Orbdiff/DPS-Analyzer/releases/latest"),
    (New-Tool "UserAssistView"    "Parses UserAssist registry artifact"        "Orbdiff" "GitHub" "https://github.com/Orbdiff/UserAssistView/releases/latest"),
    (New-Tool "JournalParser"     "Parses NTFS USN journal entries"            "Orbdiff" "GitHub" "https://github.com/Orbdiff/JournalParser/releases/latest"),
    (New-Tool "USBDetector"       "Detects USB device history"                 "Orbdiff" "GitHub" "https://github.com/Orbdiff/USBDetector/releases/latest"),
    (New-Tool "PFTrace"           "Rundll32/Regsvr32 prefetch analysis"        "Orbdiff" "GitHub" "https://github.com/Orbdiff/PFTrace/releases/latest"),
    (New-Tool "CheckDeletedUSN"   "Compares USN timestamp vs boot time"        "Orbdiff" "GitHub" "https://github.com/Orbdiff/CheckDeletedUSN/releases/latest"),

    # Spokwn
    (New-Tool "BAM-parser"        "Parses BAM entries for execution history"   "Spokwn" "GitHub" "https://github.com/spokwn/BAM-parser/releases/latest"),
    (New-Tool "PathsParser"       "Extracts and analyzes executable paths"     "Spokwn" "GitHub" "https://github.com/spokwn/PathsParser/releases/latest"),
    (New-Tool "JournalTrace"      "Traces file activity via USN journal"       "Spokwn" "GitHub" "https://github.com/spokwn/JournalTrace/releases/latest"),
    (New-Tool "KernelLiveDumpTool" "Captures live kernel memory dump"          "Spokwn" "GitHub" "https://github.com/spokwn/KernelLiveDumpTool/releases/latest"),
    (New-Tool "BamDeletedKeys"    "Finds deleted BAM registry keys"            "Spokwn" "GitHub" "https://github.com/spokwn/BamDeletedKeys/releases/latest"),
    (New-Tool "Espouken Tool"     "All-in-one SS forensics toolkit"            "Spokwn" "GitHub" "https://github.com/spokwn/Tool/releases/latest"),
    (New-Tool "pcasvc-executed"   "Extracts PCA service execution records"     "Spokwn" "GitHub" "https://github.com/spokwn/pcasvc-executed/releases/latest"),
    (New-Tool "process-parser"    "Parses process execution artefacts"         "Spokwn" "GitHub" "https://github.com/spokwn/process-parser/releases/latest"),
    (New-Tool "prefetch-parser"   "Parses Windows prefetch files"              "Spokwn" "GitHub" "https://github.com/spokwn/prefetch-parser/releases/latest"),
    (New-Tool "ActivitiesCache"   "Parses ActivitiesCache execution history"   "Spokwn" "GitHub" "https://github.com/spokwn/ActivitiesCache-execution/releases/latest"),

    # Praiselily
    (New-Tool "PSHunter"            "Hunts suspicious PowerShell activity"        "Praiselily" "GitHub" "https://github.com/praiselily/PSHunter/releases/latest"),
    (New-Tool "CommonDirectories"   "Lists files in common suspicious dirs"       "Praiselily" "Cmd" "Invoke-Expression (Invoke-RestMethod 'https://raw.githubusercontent.com/praiselily/lilith-ps/refs/heads/main/CommonDirectories.ps1')"),
    (New-Tool "HarddiskConverter"   "Converts harddisk identifiers for review"    "Praiselily" "Cmd" "Invoke-Expression (Invoke-RestMethod 'https://raw.githubusercontent.com/praiselily/lilith-ps/refs/heads/main/HarddiskConverter.ps1')"),
    (New-Tool "Services"            "Lists and analyzes running services"         "Praiselily" "Cmd" "Invoke-Expression (Invoke-RestMethod 'https://raw.githubusercontent.com/praiselily/lilith-ps/refs/heads/main/Services.ps1')"),
    (New-Tool "SignedScheduledTasks" "Finds unsigned / suspicious scheduled tasks" "Praiselily" "Cmd" "Invoke-Expression (Invoke-RestMethod 'https://raw.githubusercontent.com/praiselily/lilith-ps/refs/heads/main/Signed-Scheduled-Tasks.ps1')"),

    # Zimmerman
    (New-Tool "bstrings"              "Searches strings with regex + YARA"       "Zimmerman" "Web" "https://download.ericzimmermanstools.com/net9/bstrings.zip" -Cli),
    (New-Tool "JLECmd"                "Parses Jump List files (CLI)"             "Zimmerman" "Web" "https://download.ericzimmermanstools.com/net9/JLECmd.zip" -Cli),
    (New-Tool "JumpListExplorer"      "GUI explorer for Jump List artefacts"     "Zimmerman" "Web" "https://download.ericzimmermanstools.com/net9/JumpListExplorer.zip"),
    (New-Tool "MFTECmd"               "Parses MFT, UsnJrnl, LogFile, Boot"       "Zimmerman" "Web" "https://download.ericzimmermanstools.com/net9/MFTECmd.zip" -Cli),
    (New-Tool "PECmd"                 "Parses Windows prefetch files (CLI)"      "Zimmerman" "Web" "https://download.ericzimmermanstools.com/net9/PECmd.zip" -Cli),
    (New-Tool "RecentFileCacheParser" "Parses RecentFileCache.bcf artefact"      "Zimmerman" "Web" "https://download.ericzimmermanstools.com/net9/RecentFileCacheParser.zip" -Cli),
    (New-Tool "RegistryExplorer"      "GUI explorer for registry hives"          "Zimmerman" "Web" "https://download.ericzimmermanstools.com/net9/RegistryExplorer.zip"),
    (New-Tool "ShellBagsExplorer"     "GUI explorer for ShellBags artefacts"     "Zimmerman" "Web" "https://download.ericzimmermanstools.com/net9/ShellBagsExplorer.zip"),
    (New-Tool "SrumECmd"              "Parses SRUM database for usage data"      "Zimmerman" "Web" "https://download.ericzimmermanstools.com/net9/SrumECmd.zip" -Cli),
    (New-Tool "TimelineExplorer"      "GUI viewer for CSV timeline output"       "Zimmerman" "Web" "https://download.ericzimmermanstools.com/net9/TimelineExplorer.zip"),
    (New-Tool "AmcacheParser"         "Parses AMCache with YARA + signatures"    "Zimmerman" "Web" "https://download.ericzimmermanstools.com/net9/AmcacheParser.zip" -Cli),

    # NirSoft
    (New-Tool "FullEventLogView"     "Views all Windows event log entries"       "NirSoft" "Web" "https://www.nirsoft.net/utils/fulleventlogview.zip"),
    (New-Tool "NetworkUsageView"     "Shows network usage per process"           "NirSoft" "Web" "https://www.nirsoft.net/utils/networkusageview.zip"),
    (New-Tool "BrowserDownloadsView" "Lists all browser download history"        "NirSoft" "Web" "https://www.nirsoft.net/utils/browserdownloadsview.zip"),
    (New-Tool "AlternateStreamView"  "Reveals hidden NTFS alternate streams"     "NirSoft" "Web" "https://www.nirsoft.net/utils/alternatestreamview.zip"),
    (New-Tool "USBDeview"            "Lists all USB devices ever connected"      "NirSoft" "Web" "https://www.nirsoft.net/utils/usbdeview.zip"),
    (New-Tool "OpenSaveFilesView"    "Shows files opened/saved via dialogs"      "NirSoft" "Web" "https://www.nirsoft.net/utils/opensavefilesview.zip"),
    (New-Tool "ExecutedProgramsList" "Lists programs run from various sources"   "NirSoft" "Web" "https://www.nirsoft.net/utils/executedprogramslist.zip"),
    (New-Tool "TaskSchedulerView"    "Views all scheduled tasks and history"     "NirSoft" "Web" "https://www.nirsoft.net/utils/taskschedulerview.zip"),
    (New-Tool "JumpListsView"        "Views Jump List recent/frequent files"     "NirSoft" "Web" "https://www.nirsoft.net/utils/jumplistsview.zip"),
    (New-Tool "WinPrefetchView"      "Views Windows prefetch file details"       "NirSoft" "Web" "https://www.nirsoft.net/utils/winprefetchview.zip"),
    (New-Tool "RegScanner"           "Scans registry for values / patterns"      "NirSoft" "Web" "https://www.nirsoft.net/utils/regscanner.zip"),
    (New-Tool "ShellBagsView"        "Views ShellBags folder access history"     "NirSoft" "Web" "https://www.nirsoft.net/utils/shellbagsview.zip"),

    # Others
    (New-Tool "MeowImportsChecker"   "Checks PE imports for suspicious DLLs"     "Others" "GitHub" "https://github.com/MeowTonynoh/MeowImportsChecker/releases/latest"),
    (New-Tool "MeowResolver"         "Resolves obfuscated strings in binaries"   "Others" "GitHub" "https://github.com/MeowTonynoh/MeowResolver/releases/latest"),
    (New-Tool "ComputerActivityView" "Timeline of computer activity events"      "Others" "Link"   "https://www.nirsoft.net/utils/computer_activity_view.html"),
    (New-Tool "SystemInformer"       "Advanced process and kernel inspector"     "Others" "Link"   "https://www.systeminformer.com/canary"),
    (New-Tool "DIE-engine"           "Detects file type, packer, compiler"       "Others" "Link"   "https://github.com/horsicq/DIE-engine/releases"),
    (New-Tool "VMAware"              "Advanced VM detection tool"                "Others" "GitHub" "https://github.com/kernelwernel/VMAware/releases/latest"),
    (New-Tool "Velociraptor"         "Endpoint DFIR and threat hunting agent"    "Others" "GitHub" "https://github.com/Velocidex/velociraptor/releases/latest" -Cli),
    (New-Tool "NTFS Parser"          "NTFS forensics: MFT, Bitlocker, USN"       "Others" "GitHub" "https://github.com/thewhiteninja/ntfstool/releases/latest" -Cli),
    (New-Tool "Hayabusa"             "Fast event log timeline generator"         "Others" "GitHub" "https://github.com/Yamato-Security/hayabusa/releases/latest" -Cli),
    (New-Tool "Everything"           "Instant filename search for Windows"       "Others" "Link"   "https://www.voidtools.com/downloads/"),
    (New-Tool "HxD"                  "Hex editor with disk and RAM editing"      "Others" "Link"   "https://mh-nexus.de/en/hxd/"),

    # Dependencies
    (New-Tool ".NET 9 Desktop Runtime" "Needed by the Zimmerman GUI tools"       "Dependencies" "Web" "https://aka.ms/dotnet/9.0/windowsdesktop-runtime-win-x64.exe"),
    (New-Tool "VC++ Redistributable"   "Visual C++ runtime (x64)"                "Dependencies" "Web" "https://aka.ms/vs/17/release/vc_redist.x64.exe")
)


# ==============================================================================
# UI
# ==============================================================================

[xml]$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="HennyWare v3"
    Width="1200" Height="760"
    MinWidth="1200" MinHeight="760"
    WindowStartupLocation="CenterScreen"
    ResizeMode="NoResize"
    WindowStyle="None"
    AllowsTransparency="True"
    Background="Transparent"
    FontFamily="Segoe UI">

    <Window.Resources>
        <SolidColorBrush x:Key="MainBg"    Color="#0B0612"/>
        <SolidColorBrush x:Key="SidebarBg" Color="#140A20"/>
        <SolidColorBrush x:Key="CardBg"    Color="#1C1030"/>
        <SolidColorBrush x:Key="Accent"    Color="#FF4FA3"/>
        <SolidColorBrush x:Key="Cyan"      Color="#5CE1E6"/>
        <SolidColorBrush x:Key="TextMain"  Color="#F6E8FF"/>
        <SolidColorBrush x:Key="TextMuted" Color="#8A6FA8"/>
        <SolidColorBrush x:Key="ConsoleBg" Color="#05020A"/>

        <Style x:Key="SideBtn" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="{StaticResource TextMain}"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Height" Value="38"/>
            <Setter Property="Margin" Value="0,0,0,4"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="4">
                            <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center" Margin="14,0"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#2A1545"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="TitleBtn" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="{StaticResource TextMuted}"/>
            <Setter Property="Width" Value="40"/>
            <Setter Property="Height" Value="36"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#33FF4FA3"/>
                                <Setter Property="Foreground" Value="#FF4FA3"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="ToolBtn" TargetType="Button">
            <Setter Property="Width" Value="210"/>
            <Setter Property="Height" Value="80"/>
            <Setter Property="Margin" Value="6"/>
            <Setter Property="Background" Value="#140A20"/>
            <Setter Property="Foreground" Value="#F6E8FF"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="#44FF4FA3"
                                BorderThickness="1" CornerRadius="6" RenderTransformOrigin="0.5,0.5">
                            <Border.RenderTransform>
                                <ScaleTransform x:Name="Sc" ScaleX="1" ScaleY="1"/>
                            </Border.RenderTransform>
                            <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center" Margin="12,8"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#FF4FA3"/>
                                <Setter Property="Foreground" Value="#0B0612"/>
                                <Trigger.EnterActions>
                                    <BeginStoryboard>
                                        <Storyboard>
                                            <DoubleAnimation Storyboard.TargetName="Sc" Storyboard.TargetProperty="ScaleX" To="1.05" Duration="0:0:0.12"/>
                                            <DoubleAnimation Storyboard.TargetName="Sc" Storyboard.TargetProperty="ScaleY" To="1.05" Duration="0:0:0.12"/>
                                        </Storyboard>
                                    </BeginStoryboard>
                                </Trigger.EnterActions>
                                <Trigger.ExitActions>
                                    <BeginStoryboard>
                                        <Storyboard>
                                            <DoubleAnimation Storyboard.TargetName="Sc" Storyboard.TargetProperty="ScaleX" To="1" Duration="0:0:0.15"/>
                                            <DoubleAnimation Storyboard.TargetName="Sc" Storyboard.TargetProperty="ScaleY" To="1" Duration="0:0:0.15"/>
                                        </Storyboard>
                                    </BeginStoryboard>
                                </Trigger.ExitActions>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.8"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Border Background="{StaticResource MainBg}" BorderBrush="#3A1F5C" BorderThickness="1" CornerRadius="8">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="42"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <!-- Title bar -->
            <Border Grid.Row="0" Background="{StaticResource SidebarBg}" CornerRadius="8,8,0,0">
                <Grid Margin="16,0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <TextBlock Text=">(o)__" FontSize="14" FontWeight="Bold" Foreground="{StaticResource Accent}" FontFamily="Consolas"/>
                        <TextBlock Text="  HennyWare v3" FontSize="14" FontWeight="SemiBold" Foreground="{StaticResource TextMain}"/>
                        <TextBlock Text="  -  by sloppyhenny" FontSize="11" Foreground="{StaticResource TextMuted}" VerticalAlignment="Center" Margin="4,0,0,0"/>
                    </StackPanel>
                    <StackPanel Grid.Column="1" Orientation="Horizontal">
                        <Button x:Name="MinBtn"   Style="{StaticResource TitleBtn}" Content="_"/>
                        <Button x:Name="CloseBtn" Style="{StaticResource TitleBtn}" Content="X"/>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- Body -->
            <Grid Grid.Row="1">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="210"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <!-- Sidebar -->
                <Border Grid.Column="0" Background="{StaticResource SidebarBg}" BorderBrush="#3A1F5C" BorderThickness="0,0,1,0">
                    <StackPanel Margin="10,14,10,14">

                        <Border Background="#07030D" CornerRadius="6" Margin="0,0,0,14" Padding="0,12">
                            <TextBlock x:Name="HenBlock" FontFamily="Consolas" FontSize="11"
                                Foreground="{StaticResource Accent}" HorizontalAlignment="Center" TextAlignment="Left"/>
                        </Border>

                        <TextBlock Text="ACTIONS" FontSize="9" FontWeight="Bold" Foreground="{StaticResource TextMuted}" Margin="4,0,0,6"/>
                        <Button x:Name="OpenFolderBtn" Content="  Open Install Folder"    Style="{StaticResource SideBtn}"/>
                        <Button x:Name="OpenRobloxBtn" Content="  Open Roblox Folder"     Style="{StaticResource SideBtn}"/>
                        <Button x:Name="OpenLogsBtn"   Content="  Open Roblox Logs"      Style="{StaticResource SideBtn}"/>
                        <Button x:Name="ClearCacheBtn" Content="  Clear Downloaded Files" Style="{StaticResource SideBtn}"/>
                        <Button x:Name="OpenCmdBtn"    Content="  Open CMD"               Style="{StaticResource SideBtn}"/>

                        <Separator Background="#3A1F5C" Margin="0,10,0,10"/>

                        <TextBlock Text="CREDITS" FontSize="9" FontWeight="Bold" Foreground="{StaticResource TextMuted}" Margin="4,0,0,6"/>
                        <TextBlock Text="Made by sloppyhenny" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextMain}" Margin="4,2,0,4"/>
                        <TextBlock Text="HennyWare v3" FontSize="10" Foreground="{StaticResource TextMuted}" Margin="4,1,0,0"/>

                        <Separator Background="#3A1F5C" Margin="0,10,0,10"/>
                        <TextBlock x:Name="AdminBlock"    FontSize="10" FontWeight="SemiBold" Margin="4,0,0,4"/>
                        <TextBlock x:Name="InstPathBlock" FontSize="9" Foreground="#5C4380" TextWrapping="Wrap" Margin="4,0"/>
                    </StackPanel>
                </Border>

                <!-- Main panel -->
                <Grid Grid.Column="1" Margin="16,14,16,14">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="10"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="10"/>
                        <RowDefinition Height="160"/>
                    </Grid.RowDefinitions>

                    <Border Grid.Row="0" Background="{StaticResource CardBg}" CornerRadius="6" Padding="16,10">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel>
                                <TextBlock x:Name="StatusTitle" Text="Ready" FontSize="20" FontWeight="SemiBold" Foreground="{StaticResource TextMain}"/>
                                <TextBlock x:Name="StatusSub" Text="Select a tool to launch or download it." FontSize="11" Foreground="{StaticResource TextMuted}"/>
                            </StackPanel>
                            <Border Grid.Column="1" Background="#2A1245" CornerRadius="4" Padding="10,4" VerticalAlignment="Center">
                                <TextBlock x:Name="StatusBadge" Text="IDLE" FontSize="12" FontWeight="Bold" Foreground="{StaticResource Cyan}"/>
                            </Border>
                        </Grid>
                    </Border>

                    <Border Grid.Row="2" Background="{StaticResource CardBg}" CornerRadius="6">
                        <TabControl x:Name="ToolsTab" Background="Transparent" BorderThickness="0" Padding="0">
                            <TabControl.Resources>
                                <Style TargetType="TabItem">
                                    <Setter Property="Foreground" Value="{StaticResource TextMuted}"/>
                                    <Setter Property="FontSize" Value="11"/>
                                    <Setter Property="Cursor" Value="Hand"/>
                                    <Setter Property="Template">
                                        <Setter.Value>
                                            <ControlTemplate TargetType="TabItem">
                                                <Border x:Name="TabBorder" Background="Transparent" CornerRadius="4" Margin="3,4,3,0" Padding="12,5">
                                                    <ContentPresenter ContentSource="Header" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                                </Border>
                                                <ControlTemplate.Triggers>
                                                    <Trigger Property="IsSelected" Value="True">
                                                        <Setter TargetName="TabBorder" Property="Background" Value="{StaticResource Accent}"/>
                                                        <Setter Property="Foreground" Value="#0B0612"/>
                                                    </Trigger>
                                                    <MultiTrigger>
                                                        <MultiTrigger.Conditions>
                                                            <Condition Property="IsMouseOver" Value="True"/>
                                                            <Condition Property="IsSelected" Value="False"/>
                                                        </MultiTrigger.Conditions>
                                                        <Setter TargetName="TabBorder" Property="Background" Value="#2A1545"/>
                                                        <Setter Property="Foreground" Value="{StaticResource TextMain}"/>
                                                    </MultiTrigger>
                                                </ControlTemplate.Triggers>
                                            </ControlTemplate>
                                        </Setter.Value>
                                    </Setter>
                                </Style>
                            </TabControl.Resources>
                        </TabControl>
                    </Border>

                    <Border Grid.Row="4" Background="{StaticResource ConsoleBg}" CornerRadius="6" Padding="12,8">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>
                            <TextBlock Text="ACTIVITY CONSOLE" FontSize="9" FontWeight="Bold" Foreground="#5C4380" FontFamily="Consolas" Margin="0,0,0,4"/>
                            <TextBox x:Name="LogBox" Grid.Row="1" Background="Transparent" Foreground="{StaticResource Cyan}"
                                BorderThickness="0" FontFamily="Consolas" FontSize="11" IsReadOnly="True"
                                VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"/>
                        </Grid>
                    </Border>
                </Grid>
            </Grid>
        </Grid>
    </Border>
</Window>
'@


# ==============================================================================
# DISCLAIMER
# ==============================================================================

[xml]$disclaimerXaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="HennyWare v3"
    Width="560" Height="600"
    WindowStartupLocation="CenterScreen"
    ResizeMode="NoResize"
    WindowStyle="None"
    AllowsTransparency="True"
    Background="Transparent"
    FontFamily="Segoe UI">
    <Border Background="#0B0612" BorderBrush="#3A1F5C" BorderThickness="1" CornerRadius="8" Padding="24">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="*"/>
                <RowDefinition Height="56"/>
            </Grid.RowDefinitions>
            <StackPanel Grid.Row="0">
                <TextBlock Text="HennyWare v3" FontSize="20" FontWeight="Bold" Foreground="#FF4FA3" Margin="0,0,0,12"/>
                <TextBlock TextWrapping="Wrap" Foreground="#F6E8FF" FontSize="13" Margin="0,0,0,12"
                           Text="Tools are downloaded from their authors' official GitHub releases or websites into one folder. Some entries run scripts straight from public GitHub repositories. HennyWare does not collect or send any of your information."/>
                <TextBlock TextWrapping="Wrap" Foreground="#F6E8FF" FontSize="13" Margin="0,0,0,12"
                           Text="Each tool is made and maintained by its own author. Flagged files and odd results are things to review, they are not proof of cheating on their own."/>
                <TextBlock TextWrapping="Wrap" Foreground="#F6E8FF" FontSize="13" Margin="0,0,0,16"
                           Text="Only run a PC check on a computer you own or where the owner has agreed to it."/>
                <TextBlock TextWrapping="Wrap" Foreground="#F6E8FF" FontSize="13" FontWeight="SemiBold"
                           Text="To continue, you must agree with everything stated above."/>
            </StackPanel>
            <Grid Grid.Row="1" VerticalAlignment="Bottom">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="12"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Button x:Name="CancelBtn" Grid.Column="0" Content="Cancel" Height="40"
                        Background="Transparent" Foreground="#F6E8FF" BorderBrush="#3A1F5C" BorderThickness="1"
                        Cursor="Hand" FontSize="13"/>
                <Button x:Name="AcceptBtn" Grid.Column="2" Content="Accept &amp; Continue" Height="40"
                        Background="#1C1030" Foreground="#FF4FA3" BorderBrush="#FF4FA3" BorderThickness="1"
                        Cursor="Hand" FontSize="13" FontWeight="SemiBold"/>
            </Grid>
        </Grid>
    </Border>
</Window>
'@

$disclaimerWindow = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $disclaimerXaml))
$disclaimerWindow.Add_MouseLeftButtonDown({ try { $disclaimerWindow.DragMove() } catch {} })
$script:disclaimerAccepted = $false
$disclaimerWindow.FindName("AcceptBtn").Add_Click({ $script:disclaimerAccepted = $true; $disclaimerWindow.Close() })
$disclaimerWindow.FindName("CancelBtn").Add_Click({ $disclaimerWindow.Close() })
$disclaimerWindow.ShowDialog() | Out-Null
if (-not $script:disclaimerAccepted) { return }


# ==============================================================================
# LOAD MAIN WINDOW
# ==============================================================================

$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))

$MinBtn        = $window.FindName("MinBtn")
$CloseBtn      = $window.FindName("CloseBtn")
$StatusTitle   = $window.FindName("StatusTitle")
$StatusSub     = $window.FindName("StatusSub")
$StatusBadge   = $window.FindName("StatusBadge")
$LogBox        = $window.FindName("LogBox")
$ToolsTab      = $window.FindName("ToolsTab")
$OpenFolderBtn = $window.FindName("OpenFolderBtn")
$OpenRobloxBtn = $window.FindName("OpenRobloxBtn")
$OpenLogsBtn   = $window.FindName("OpenLogsBtn")
$ClearCacheBtn = $window.FindName("ClearCacheBtn")
$OpenCmdBtn    = $window.FindName("OpenCmdBtn")
$HenBlock      = $window.FindName("HenBlock")
$AdminBlock    = $window.FindName("AdminBlock")
$InstPathBlock = $window.FindName("InstPathBlock")

$InstPathBlock.Text = "Install path:`n$installDir"
if ($isAdmin) {
    $AdminBlock.Text = "Admin: YES"
    $AdminBlock.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#5CE1E6")
} else {
    $AdminBlock.Text = "Admin: NO (some checks need it)"
    $AdminBlock.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#FF4FA3")
}


# ==============================================================================
# HELPERS
# ==============================================================================

function Write-Log {
    param([string]$msg)
    $time = Get-Date -Format "HH:mm:ss"
    $LogBox.Dispatcher.Invoke([Action]{
        $LogBox.AppendText("[$time] $msg`r`n")
        $LogBox.ScrollToEnd()
    })
}

function Set-Status {
    param($title, $sub, $badge = "BUSY")
    $window.Dispatcher.Invoke([Action]{
        $StatusTitle.Text = $title
        $StatusSub.Text   = $sub
        $StatusBadge.Text = $badge
    })
}

function Start-ScriptWindow {
    param([Parameter(Mandatory = $true)][string]$Code)
    $tmp = Join-Path $env:TEMP ("hennyware_{0}.ps1" -f [guid]::NewGuid().ToString("N"))
    Set-Content -LiteralPath $tmp -Value $Code -Encoding UTF8 -Force
    Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoExit", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$tmp`"")
}

# Downloads run in a background runspace so the window never freezes.
$Worker = {
    param($tool, $installDir, $window, $LogBox, $StatusTitle, $StatusSub, $StatusBadge, $btn)

    function BgLog($m) {
        $window.Dispatcher.Invoke([Action]{
            $LogBox.AppendText("[$(Get-Date -Format 'HH:mm:ss')] $m`r`n")
            $LogBox.ScrollToEnd()
        })
    }
    function BgStatus($t, $s, $b) {
        $window.Dispatcher.Invoke([Action]{
            $StatusTitle.Text = $t
            $StatusSub.Text   = $s
            $StatusBadge.Text = $b
        })
    }

    $name = $tool.Name
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $dir = Join-Path (Join-Path $installDir $tool.Category) $name
        New-Item -ItemType Directory -Path $dir -Force | Out-Null

        if ($tool.Type -eq "GitHub") {
            $parts = ($tool.Url -replace "https://github.com/", "") -split "/"
            $api   = "https://api.github.com/repos/$($parts[0])/$($parts[1])/releases/latest"
            BgLog "Looking up latest release for $name..."
            $rel = Invoke-RestMethod -Uri $api -Headers @{ "User-Agent" = "HennyWare" } -ErrorAction Stop
            $asset = @($rel.assets | Where-Object {
                $_.name -match '\.(exe|zip)$' -and $_.name -notmatch '(?i)linux|lin-|darwin|macos|mac-|arm64|aarch|musl|i386|win32|x86\.'
            }) | Sort-Object @{ Expression = { if ($_.name -match '(?i)win') { 0 } else { 1 } } },
                             @{ Expression = { if ($_.name -match '\.exe$') { 0 } else { 1 } } } |
                 Select-Object -First 1
            if (-not $asset) { throw "No Windows .exe or .zip in the latest release." }
            $dl = $asset.browser_download_url
            $file = $asset.name
        } else {
            $dl = $tool.Url
            $file = ($tool.Url -split "/")[-1]
        }

        $dest = Join-Path $dir $file
        if (Test-Path -LiteralPath $dest) {
            BgLog "Cached: $file"
        } else {
            BgLog "Downloading $file..."
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent", "HennyWare")
            try {
                $wc.DownloadFile($dl, "$dest.part")
                Move-Item -LiteralPath "$dest.part" -Destination $dest -Force
            } finally {
                $wc.Dispose()
                if (Test-Path -LiteralPath "$dest.part") { Remove-Item -LiteralPath "$dest.part" -Force -ErrorAction SilentlyContinue }
            }
            BgLog "Download complete: $file"
        }

        if ($file -match '\.zip$') {
            BgLog "Extracting $file..."
            Expand-Archive -LiteralPath $dest -DestinationPath $dir -Force -ErrorAction Stop
            $target = Get-ChildItem -Path $dir -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -match '^\.(exe|bat|cmd)$' } |
                Sort-Object @{ Expression = { if ($_.Extension -eq '.exe') { 0 } else { 1 } } }, FullName |
                Select-Object -First 1
        } else {
            $target = Get-Item -LiteralPath $dest
        }

        if (-not $target) {
            BgLog "No launchable file found - opening folder."
            Start-Process explorer.exe -ArgumentList "`"$dir`""
        }
        elseif ($tool.Cli) {
            BgLog "$name is a command-line tool - opening a prompt in its folder."
            $safe = $target.DirectoryName.Replace("'", "''")
            $msg  = "HennyWare: run .\$($target.Name) -h to see options"
            Start-Process powershell.exe -ArgumentList @("-NoExit", "-NoProfile", "-Command", "Set-Location -LiteralPath '$safe'; Write-Host '$msg' -ForegroundColor Magenta")
        }
        elseif ($target.Extension -match '^\.(bat|cmd)$') {
            BgLog "Launching $($target.Name)"
            Start-Process cmd.exe -ArgumentList "/k", "`"$($target.FullName)`"" -WorkingDirectory $target.DirectoryName
        }
        else {
            BgLog "Launching $($target.Name)"
            Start-Process -FilePath $target.FullName -WorkingDirectory $target.DirectoryName
        }
        BgStatus "Ready" "$name launched." "IDLE"
    }
    catch {
        BgLog "Error with ${name}: $($_.Exception.Message)"
        BgStatus "Error" "Something went wrong with $name." "ERR"
        if ($tool.Url -match "^https://github.com") {
            BgLog "Opening the release page so you can grab it manually."
            Start-Process $tool.Url
        }
    }

    $window.Dispatcher.Invoke([Action]{ $btn.IsEnabled = $true })
}

function Start-Worker {
    param($tool, $btn)
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = "STA"
    $rs.ThreadOptions  = "ReuseThread"
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($Worker).AddArgument($tool).AddArgument($installDir).AddArgument($window).AddArgument($LogBox).AddArgument($StatusTitle).AddArgument($StatusSub).AddArgument($StatusBadge).AddArgument($btn)
    [void]$ps.BeginInvoke()
}


# ==============================================================================
# TABS + TOOL BUTTONS
# ==============================================================================

$Categories = @("Roblox Checks", "Orbdiff", "Spokwn", "Praiselily", "Zimmerman", "NirSoft", "Others", "Dependencies")
$toolStyle = $window.FindResource("ToolBtn")

foreach ($cat in $Categories) {
    $tab = New-Object System.Windows.Controls.TabItem
    $tab.Header = $cat

    $scroll = New-Object System.Windows.Controls.ScrollViewer
    $scroll.VerticalScrollBarVisibility   = "Auto"
    $scroll.HorizontalScrollBarVisibility = "Disabled"

    $wrap = New-Object System.Windows.Controls.WrapPanel
    $wrap.Margin = "8"

    foreach ($tool in ($ToolData | Where-Object { $_.Category -eq $cat })) {
        $btn = New-Object System.Windows.Controls.Button
        $btn.Style = $toolStyle
        $btn.Tag   = $tool

        $stack = New-Object System.Windows.Controls.StackPanel
        $nameBlock = New-Object System.Windows.Controls.TextBlock
        $nameBlock.Text = $tool.Name
        $nameBlock.FontSize = 12
        $nameBlock.FontWeight = "SemiBold"
        $nameBlock.TextWrapping = "Wrap"
        $descBlock = New-Object System.Windows.Controls.TextBlock
        $descBlock.Text = $tool.Desc
        $descBlock.FontSize = 10
        $descBlock.Opacity = 0.65
        $descBlock.TextWrapping = "Wrap"
        $descBlock.Margin = "0,3,0,0"
        [void]$stack.Children.Add($nameBlock)
        [void]$stack.Children.Add($descBlock)
        $btn.Content = $stack

        $btn.Add_Click({
            param($sender, $e)
            $t = $sender.Tag
            switch ($t.Type) {
                "Link" {
                    Start-Process $t.Url
                    Write-Log "Opened $($t.Name) in browser."
                    Set-Status "Ready" "Opened $($t.Name) in browser." "IDLE"
                }
                "Cmd" {
                    Start-ScriptWindow $t.Command
                    Write-Log "Launched script: $($t.Name)"
                    Set-Status "Ready" "$($t.Name) opened in a new window." "IDLE"
                }
                "Local" {
                    Start-ScriptWindow $t.Command
                    Write-Log "Launched check: $($t.Name)"
                    Set-Status "Ready" "$($t.Name) opened in a new window." "IDLE"
                }
                default {
                    $sender.IsEnabled = $false
                    Set-Status "Working" "Fetching $($t.Name)..." "BUSY"
                    Write-Log "Starting: $($t.Name)"
                    Start-Worker $t $sender
                }
            }
        })

        [void]$wrap.Children.Add($btn)
    }

    $scroll.Content = $wrap
    $tab.Content    = $scroll
    [void]$ToolsTab.Items.Add($tab)
}


# ==============================================================================
# HEN ANIMATION
# ==============================================================================

function New-HenFrame { param($eye, $feet) return (@('   __      ', " >($eye )___  ", '  (  ._> /  ', $feet) -join "`n") }
$feetA = '   `---''   '
$feetB = '   /| |\    '
$henFrames = @(
    (New-HenFrame 'o' $feetA),
    (New-HenFrame '-' $feetA),
    (New-HenFrame 'o' $feetB),
    (New-HenFrame '^' $feetA)
)
$HenBlock.Text = $henFrames[0]
$script:henIdx = 0
$henTimer = New-Object System.Windows.Threading.DispatcherTimer
$henTimer.Interval = [TimeSpan]::FromMilliseconds(900)
$henTimer.Add_Tick({
    $script:henIdx = ($script:henIdx + 1) % $henFrames.Count
    $HenBlock.Text = $henFrames[$script:henIdx]
})
$henTimer.Start()


# ==============================================================================
# EVENTS
# ==============================================================================

$window.Add_MouseLeftButtonDown({ try { $window.DragMove() } catch {} })
$CloseBtn.Add_Click({ $henTimer.Stop(); $window.Close() })
$MinBtn.Add_Click({ $window.WindowState = "Minimized" })

$OpenFolderBtn.Add_Click({
    if (-not (Test-Path $installDir)) { New-Item -ItemType Directory -Path $installDir -Force | Out-Null }
    Start-Process explorer.exe $installDir
    Write-Log "Opened install folder."
})

$OpenRobloxBtn.Add_Click({
    $p = "$env:LOCALAPPDATA\Roblox"
    if (Test-Path $p) { Start-Process explorer.exe $p; Write-Log "Opened Roblox folder." }
    else { Write-Log "Roblox folder not found at $p" }
})

$OpenLogsBtn.Add_Click({
    $p = "$env:LOCALAPPDATA\Roblox\logs"
    if (Test-Path $p) { Start-Process explorer.exe $p; Write-Log "Opened Roblox logs." }
    else { Write-Log "No Roblox logs folder found (may have been cleared)." }
})

$ClearCacheBtn.Add_Click({
    if (-not (Test-Path $installDir)) { Write-Log "Nothing to clear - install folder does not exist yet."; return }
    $answer = [System.Windows.MessageBox]::Show("Delete everything in:`n$installDir ?", "HennyWare", "YesNo", "Warning")
    if ($answer -ne "Yes") { return }
    $items = Get-ChildItem -Path $installDir -Force -ErrorAction SilentlyContinue
    $count = @($items).Count
    $items | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "Cleared $count item(s) from install folder."
    Set-Status "Clean" "Removed downloaded files and folders." "IDLE"
})

$OpenCmdBtn.Add_Click({
    Start-Process -FilePath "cmd.exe"
    Write-Log "Opened CMD."
})

Write-Log "HennyWare v3 loaded with $(@($ToolData).Count) tools."
Write-Log "Files saved to: $installDir"
if (-not $isAdmin) { Write-Log "Not running as admin. BAM, prefetch and memory tools need it - relaunch PowerShell as Administrator." }
Set-Status "Ready" "Select a tool to launch or download it." "IDLE"

$window.ShowDialog() | Out-Null
