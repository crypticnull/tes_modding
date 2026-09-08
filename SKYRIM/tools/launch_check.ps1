<#
.SYNOPSIS
    Launch Skyrim through MO2 + SKSE, answer the modal error boxes itself, and
    report what they said.

.DESCRIPTION
    NEXT.md section 1 ends "relaunch through SKSE and confirm no AddressLibrary
    popup". Doing that by hand means sitting in front of the screen waiting for
    a message box that may not come. This does it unattended.

    It launches through MO2, polls for Win32 dialog windows (class #32770)
    belonging to SkyrimSE / skse64_loader / ModOrganizer, reads the body text
    out of them cross-process, records it, clicks a button by policy, and
    carries on until the game reaches its main window or the timeout expires.

.TRAPS
    - GetWindowText returns EMPTY for a child control owned by another process.
      The dialog body has to be read with SendMessage WM_GETTEXT, which does
      work cross-process. That is the whole reason this is P/Invoke and not
      three lines of Get-Process | Select-Object MainWindowTitle.
    - Answering the SKSE plugin box with "Yes" (exit) is what a human does, and
      it is why skse64.log kept coming up missing: SKSE writes that log on the
      way PAST this gate, so exiting here means no log, and only the first bad
      plugin is ever named. -OnPluginError Continue clicks "No" instead, which
      is safe for a boot-to-main-menu diagnostic because no save is loaded, and
      it surfaces every failing DLL in a single run. Pass -OnPluginError Exit
      to get the cautious behaviour back.
    - It closes the game once it reaches its main window, unless -KeepGameOpen.

    Report only. It installs nothing and edits no profile.

.EXAMPLE
    & 'X:\MODDING\SKYRIM\tools\launch_check.ps1'
    & 'X:\MODDING\SKYRIM\tools\launch_check.ps1' -OnPluginError Exit
    & 'X:\MODDING\SKYRIM\tools\launch_check.ps1' -NoLaunch
#>
[CmdletBinding()]
param(
    [string] $Root = 'X:\MODDING\SKYRIM',
    [string] $MO2 = '',
    [string] $Shortcut = 'moshortcut://:SKSE',
    [int]    $TimeoutSeconds = 240,

    # Continue = click No, keep loading, get skse64.log and every bad DLL.
    # Exit     = click Yes, the cautious answer, one plugin per launch.
    [ValidateSet('Continue','Exit')]
    [string] $OnPluginError = 'Continue',

    [switch] $NoLaunch,
    [switch] $KeepGameOpen,
    [string] $Log = ''
)

$ErrorActionPreference = 'Stop'

if (-not $MO2) {
    $cand = Get-ChildItem -Path (Join-Path $Root 'MO2') -Filter 'ModOrganizer.exe' -Recurse -ErrorAction SilentlyContinue |
                Select-Object -First 1
    if ($cand) { $MO2 = $cand.FullName }
}
if (-not $Log) { $Log = Join-Path $Root 'logs\launch_check.txt' }

if (-not ('W32' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class W32 {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int m);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int m);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="SendMessageW")] public static extern IntPtr SendMessageText(IntPtr h, uint msg, IntPtr w, StringBuilder l);
    [DllImport("user32.dll", EntryPoint="SendMessageW")] public static extern IntPtr SendMessagePtr(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
}
'@
}

$WM_GETTEXT = 0x000D
$BM_CLICK   = 0x00F5

function Get-ClassOf {
    param([IntPtr]$h)
    $sb = New-Object Text.StringBuilder 256
    [void][W32]::GetClassName($h, $sb, $sb.Capacity)
    $sb.ToString()
}
function Get-TitleOf {
    param([IntPtr]$h)
    $sb = New-Object Text.StringBuilder 512
    [void][W32]::GetWindowText($h, $sb, $sb.Capacity)
    $sb.ToString()
}
# Cross-process control text. GetWindowText will NOT do this.
function Get-CtrlText {
    param([IntPtr]$h)
    $sb = New-Object Text.StringBuilder 2048
    [void][W32]::SendMessageText($h, $WM_GETTEXT, [IntPtr]$sb.Capacity, $sb)
    $sb.ToString()
}
function Get-ChildWindows {
    param([IntPtr]$parent)
    $found = New-Object Collections.ArrayList
    $cb = [W32+EnumProc]{ param($h, $l) [void]$found.Add($h); $true }
    [void][W32]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    ,$found
}
function Get-TopWindows {
    $found = New-Object Collections.ArrayList
    $cb = [W32+EnumProc]{ param($h, $l) if ([W32]::IsWindowVisible($h)) { [void]$found.Add($h) }; $true }
    [void][W32]::EnumWindows($cb, [IntPtr]::Zero)
    ,$found
}
function Get-ProcNameOf {
    param([IntPtr]$h)
    $wpid = 0
    [void][W32]::GetWindowThreadProcessId($h, [ref]$wpid)
    $p = Get-Process -Id $wpid -ErrorAction SilentlyContinue
    if ($p) { $p.ProcessName } else { '' }
}

# Which button to press. The policy lives in one place on purpose.
function Get-PreferredButtons {
    param([string]$Title, [string]$Body)
    if ($Title -match 'SKSE Plugin Loader' -or $Body -match 'DLL plugin has failed to load') {
        if ($OnPluginError -eq 'Continue') { return @('No') } else { return @('Yes') }
    }
    if ($Body -match 'waiting on an application to close') { return @('Cancel') }
    return @('OK', 'Yes', 'Close', 'Continue')
}

$ours        = @('SkyrimSE', 'skse64_loader', 'ModOrganizer')
$seen        = @{}
$dialogs     = New-Object Collections.ArrayList
$reachedGame = $false

Write-Host ""
Write-Host "launch_check  policy OnPluginError=$OnPluginError  timeout ${TimeoutSeconds}s"
if (-not $NoLaunch) {
    if (-not $MO2 -or -not (Test-Path -LiteralPath $MO2)) { throw "ModOrganizer.exe not found. Pass -MO2." }
    Start-Process -FilePath $MO2 -ArgumentList ('"' + $Shortcut + '"')
    Write-Host "launched: $MO2 $Shortcut"
} else {
    Write-Host "watching an already-running launch"
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 700

    foreach ($h in (Get-TopWindows)) {
        $pn = Get-ProcNameOf $h
        if ($ours -notcontains $pn) { continue }
        $cls = Get-ClassOf $h

        if ($cls -ne '#32770') {
            if ($pn -eq 'SkyrimSE') { $reachedGame = $true }
            continue
        }
        $key = "$h"
        if ($seen.ContainsKey($key)) { continue }

        $title   = Get-TitleOf $h
        $lines   = @()
        $buttons = @()
        foreach ($c in (Get-ChildWindows $h)) {
            $ccls = Get-ClassOf $c
            $txt  = (Get-CtrlText $c).Trim()
            if (-not $txt) { continue }
            if ($ccls -eq 'Button') {
                $buttons += [pscustomobject]@{ H = $c; Text = ($txt -replace '&', '') }
            } elseif ($ccls -match 'Static|Edit') {
                $lines += $txt
            }
        }
        $body = ($lines -join ' | ')
        $seen[$key] = $true

        $want = Get-PreferredButtons -Title $title -Body $body
        $hit  = $null
        foreach ($w in $want) {
            $hit = $buttons | Where-Object { $_.Text -eq $w } | Select-Object -First 1
            if ($hit) { break }
        }
        if (-not $hit) { $hit = $buttons | Select-Object -First 1 }

        [void]$dialogs.Add([pscustomobject]@{
            Proc    = $pn
            Title   = $title
            Body    = $body
            Buttons = (($buttons | ForEach-Object { $_.Text }) -join ' / ')
            Clicked = $(if ($hit) { $hit.Text } else { '(none found)' })
        })

        Write-Host ""
        Write-Host ("  DIALOG [" + $pn + "] " + $title) -ForegroundColor Yellow
        foreach ($l in $lines) { Write-Host ("    " + $l) }
        if ($hit) {
            Write-Host ("    -> clicking '" + $hit.Text + "'") -ForegroundColor Cyan
            [void][W32]::SendMessagePtr($hit.H, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
        } else {
            Write-Host "    -> no button found, leaving it" -ForegroundColor Red
        }
    }

    $skRunning  = [bool](Get-Process -Name 'SkyrimSE' -ErrorAction SilentlyContinue)
    $mo2Running = [bool](Get-Process -Name 'ModOrganizer' -ErrorAction SilentlyContinue)
    if ($reachedGame -and $skRunning) { Start-Sleep -Seconds 5; break }
    if (-not $skRunning -and -not $mo2Running -and $dialogs.Count -gt 0) { break }
}

$sk = Get-Process -Name 'SkyrimSE' -ErrorAction SilentlyContinue
if ($sk -and -not $KeepGameOpen) {
    Write-Host ""
    Write-Host "  game reached its window - closing it" -ForegroundColor Cyan
    $sk | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
}

# ---- skse64.log only exists if we got PAST the plugin gate
$logHits = @(Get-ChildItem -Path "$env:USERPROFILE\Documents\My Games" -Recurse -Filter 'skse64.log' -ErrorAction SilentlyContinue) +
           @(Get-ChildItem -Path (Join-Path $Root 'SKYRIM_SE\overwrite') -Recurse -Filter 'skse64.log' -ErrorAction SilentlyContinue)

$addrHits = @()
$loadFail = @()
foreach ($lh in $logHits) {
    $addrHits += @(Select-String -Path $lh.FullName -Pattern 'AddressLibrary|Identifier not found' | ForEach-Object { $_.Line })
    $loadFail += @(Select-String -Path $lh.FullName -Pattern 'failed|disabled|incompatible|unable to' | ForEach-Object { $_.Line })
}
foreach ($d in $dialogs) {
    if ($d.Body -match 'AddressLibrary|Identifier not found') { $addrHits += ('[dialog] ' + $d.Body) }
}

Write-Host ""
Write-Host "SUMMARY"
Write-Host ("  dialogs answered     " + $dialogs.Count)
Write-Host ("  reached game window  " + $reachedGame)
Write-Host ("  skse64.log           " + $(if ($logHits) { $logHits[0].FullName } else { 'not written' }))
Write-Host ""
if ($addrHits.Count -gt 0) {
    Write-Host "  ADDRESSLIBRARY ERRORS - a wrong-runtime SKSE plugin is still present" -ForegroundColor Red
    $addrHits | Select-Object -Unique | ForEach-Object { Write-Host ("    " + $_) }
} else {
    Write-Host "  no AddressLibrary error" -ForegroundColor Green
}
$otherFails = @($dialogs | Where-Object { $_.Body -match 'failed to load|incompatible' -and $_.Body -notmatch 'AddressLibrary' })
if ($otherFails.Count -gt 0 -or $loadFail.Count -gt 0) {
    Write-Host ""
    Write-Host "  OTHER PLUGIN LOAD FAILURES" -ForegroundColor Yellow
    foreach ($o in $otherFails) { Write-Host ("    [dialog] " + $o.Body) }
    $loadFail | Select-Object -Unique | Select-Object -First 20 | ForEach-Object { Write-Host ("    [log] " + $_) }
}

$dir = Split-Path -Parent $Log
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$dialogs | Format-List | Out-File -FilePath $Log -Encoding utf8
Write-Host ""
Write-Host "  detail written to $Log"
