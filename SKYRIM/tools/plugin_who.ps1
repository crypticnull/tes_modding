#Requires -Version 5.1
<#
  plugin_who.ps1 - which plugins edit this record, and which one wins.

    plugin_who.ps1 -Name Ysolda
    plugin_who.ps1 -Name Ysolda -Type NPC_
    plugin_who.ps1 -Name 'Whiterun' -Type CELL -Max 40

  WHY THIS EXISTS

  mo2_conflicts.ps1 answers the FILE half of a conflict. This is the other
  half. A black face, a wrong outfit, a missing spell - those are two plugins
  editing the same RECORD, and the last one in load order wins. That is the
  question xEdit exists to answer, and it is also a question that can be
  answered by reading the files, which is what this does.

  HOW A PLUGIN IS LAID OUT

  A TES4 file is a TES4 header record followed by GRUP blocks. A GRUP is a
  24-byte header - 'GRUP', total size INCLUDING the header, label, type,
  stamps - then its contents, which are records or more GRUPs. A record is a
  24-byte header - signature, data size EXCLUDING the header, flags, FormID,
  stamps - then its data, which is a run of subrecords: 4-byte signature,
  2-byte size, data.

  Two things trip up a naive scan, and both are handled here:

    compressed records   flag 0x00040000 means the data is a uint32 of the
                         uncompressed size followed by a zlib stream. Mod
                         authors' NPC records are very often compressed, so
                         grepping a plugin for 'Ysolda' finds nothing and you
                         wrongly conclude nothing edits her. .NET has no zlib
                         reader, but a zlib stream is a 2-byte header plus raw
                         deflate, so skipping two bytes and using
                         DeflateStream is correct.

    XXXX subrecords      a subrecord larger than 65535 stores its real size in
                         a preceding XXXX subrecord and sets its own size to 0.

  MATCHING

  On EDID, the editor id, because that is stable across overrides - an override
  of Ysolda in another plugin keeps the EDID 'Ysolda' even though its raw
  FormID is renumbered against that plugin's own master list. FormIDs are
  reported but not matched on, for exactly that reason.

  Reads only.
#>

[CmdletBinding()]
param(
    [string]$Root = 'X:\MODDING\SKYRIM',
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Type,
    [int]$Max = 200,
    [switch]$Exact
)

$ErrorActionPreference = 'Stop'

$Instance = Join-Path $Root 'SKYRIM_SE'
$ModsDir  = Join-Path $Instance 'mods'
$ProfileD = Join-Path $Instance 'profiles\Default'
$MlPath   = Join-Path $ProfileD 'modlist.txt'
$PlPath   = Join-Path $ProfileD 'plugins.txt'
$DataDir  = Join-Path $Root 'STOCK GAME\Data'

foreach ($p in @($ModsDir, $MlPath, $PlPath)) { if (-not (Test-Path -LiteralPath $p)) { throw "not found: $p" } }

# mod order: first line of modlist = highest priority, so search it in order
$enabled = @(Get-Content -LiteralPath $MlPath |
             Where-Object { $_ -match '^\+(.+)$' } |
             ForEach-Object { $Matches[1].TrimEnd() })

# plugins.txt: '*' prefix means active. Order in this file IS the load order.
$active = @(Get-Content -LiteralPath $PlPath |
            Where-Object { $_ -match '^\*(.+)$' } |
            ForEach-Object { $Matches[1].Trim() })

function Resolve-Plugin {
    param([string]$File)
    foreach ($m in $enabled) {
        $c = Join-Path (Join-Path $ModsDir $m) $File
        if (Test-Path -LiteralPath $c) { return [pscustomobject]@{ Path = $c; Owner = $m } }
    }
    $c = Join-Path $DataDir $File
    if (Test-Path -LiteralPath $c) { return [pscustomobject]@{ Path = $c; Owner = '<STOCK GAME\Data>' } }
    return $null
}

function Expand-Zlib {
    param([byte[]]$Bytes, [int]$Offset, [int]$Count)
    # A compressed record's data is: uint32 uncompressed size, THEN the zlib
    # stream. So skip 4 for that size and 2 more for the zlib header - .NET's
    # DeflateStream reads raw deflate and chokes on the zlib header. Skipping
    # only the 2 silently produced nothing, and every compressed NPC record
    # looked like it did not exist.
    $skip = 4 + 2
    if ($Count -le $skip) { return @() }
    $len = $Count - $skip
    # Range indexing a byte[] yields Object[], which the MemoryStream ctor
    # rejects - copy into a real byte[].
    $buf = New-Object byte[] $len
    [Array]::Copy($Bytes, $Offset + $skip, $buf, 0, $len)
    $ms  = New-Object IO.MemoryStream(,$buf)
    $ds  = New-Object IO.Compression.DeflateStream($ms, [IO.Compression.CompressionMode]::Decompress)
    $out = New-Object IO.MemoryStream
    try { $ds.CopyTo($out) } catch { } finally { $ds.Dispose(); $ms.Dispose() }
    return $out.ToArray()
}

function Get-Edid {
    param([byte[]]$Data)
    $i = 0; $n = $Data.Length
    while ($i + 6 -le $n) {
        $sig = [Text.Encoding]::ASCII.GetString($Data, $i, 4)
        $len = [BitConverter]::ToUInt16($Data, $i + 4)
        $i += 6
        if ($sig -eq 'XXXX') {
            if ($i + 4 -gt $n) { break }
            $big = [BitConverter]::ToUInt32($Data, $i)
            $i += $len
            if ($i + 6 -gt $n) { break }
            $i += 6 + $big      # skip the oversized subrecord that follows
            continue
        }
        if ($sig -eq 'EDID') {
            if ($i + $len -gt $n) { break }
            $s = [Text.Encoding]::ASCII.GetString($Data, $i, $len)
            return $s.TrimEnd([char]0)
        }
        $i += $len
        if ($len -eq 0 -and $sig -notmatch '^[A-Z0-9_]{4}$') { break }
    }
    return $null
}

$hits = New-Object System.Collections.Generic.List[object]
$read = 0; $skipped = New-Object System.Collections.Generic.List[string]

for ($idx = 0; $idx -lt $active.Count; $idx++) {
    $pl = $active[$idx]
    $res = Resolve-Plugin $pl
    if (-not $res) { $skipped.Add("$pl (file not found)"); continue }

    try { $bytes = [IO.File]::ReadAllBytes($res.Path) } catch { $skipped.Add("$pl (unreadable)"); continue }
    $read++
    $n = $bytes.Length
    $pos = 0
    $found = 0

    while ($pos + 24 -le $n) {
        $sig = [Text.Encoding]::ASCII.GetString($bytes, $pos, 4)
        $size = [BitConverter]::ToUInt32($bytes, $pos + 4)

        if ($sig -eq 'GRUP') {
            # group size INCLUDES its own 24-byte header, so step into it
            if ($size -lt 24) { break }
            $pos += 24
            continue
        }

        $flags  = [BitConverter]::ToUInt32($bytes, $pos + 8)
        $formId = [BitConverter]::ToUInt32($bytes, $pos + 12)
        $dataAt = $pos + 24
        if ($dataAt + $size -gt $n) { break }

        $want = (-not $Type) -or ($sig -eq $Type)
        if ($want -and $size -gt 0) {
            $data = if ($flags -band 0x00040000) {
                        if ($size -gt 4) { Expand-Zlib $bytes $dataAt $size } else { @() }
                    } else {
                        $b = New-Object byte[] $size
                        [Array]::Copy($bytes, $dataAt, $b, 0, $size)
                        $b
                    }
            if ($data.Length) {
                $edid = Get-Edid $data
                if ($edid) {
                    $ok = if ($Exact) { $edid -eq $Name } else { $edid -like "*$Name*" }
                    if ($ok) {
                        $hits.Add([pscustomobject]@{
                            Order = $idx; Plugin = $pl; Owner = $res.Owner
                            Sig = $sig; FormID = ('{0:X8}' -f $formId); Edid = $edid
                        })
                        $found++
                        if ($hits.Count -ge $Max) { break }
                    }
                }
            }
        }
        $pos = $dataAt + $size
    }
    if ($hits.Count -ge $Max) { break }
}

Write-Host ""
Write-Host ("=== '{0}'{1} across {2} active plugin(s) ===" -f `
    $Name, $(if ($Type) { " type $Type" } else { '' }), $read) -ForegroundColor Cyan
Write-Host ""

if (-not $hits.Count) {
    Write-Host "  no active plugin defines or overrides a record with that editor id." -ForegroundColor Yellow
    Write-Host "  try without -Type, or a shorter -Name." -ForegroundColor DarkGray
} else {
    $byEdid = @($hits | Group-Object Edid | Sort-Object Name)
    foreach ($g in $byEdid) {
        Write-Host ("  {0}" -f $g.Name) -ForegroundColor White
        $ordered = @($g.Group | Sort-Object Order)
        for ($i = 0; $i -lt $ordered.Count; $i++) {
            $h = $ordered[$i]
            $last = ($i -eq $ordered.Count - 1)
            $tag = if ($last) { 'WINS  ' } else { 'losing' }
            $col = if ($last) { 'Green' } else { 'DarkGray' }
            Write-Host ("    {0}  [{1,3}] {2,-46} {3}  {4}" -f `
                        $tag, $h.Order, $h.Plugin, $h.Sig, $h.FormID) -ForegroundColor $col
        }
        if ($ordered.Count -gt 1) {
            Write-Host ("           {0} plugin(s) touch this record - the last one supplies what the game uses" -f $ordered.Count) -ForegroundColor DarkGray
        }
        Write-Host ""
    }
}
if ($skipped.Count) {
    Write-Host ("  {0} plugin(s) skipped:" -f $skipped.Count) -ForegroundColor DarkGray
    foreach ($s in @($skipped | Select-Object -First 8)) { Write-Host ("      {0}" -f $s) -ForegroundColor DarkGray }
}
Write-Host ""
