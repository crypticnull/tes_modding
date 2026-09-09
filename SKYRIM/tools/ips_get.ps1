#Requires -Version 5.1
<#
  ips_get.ps1 - download from Invision Community mod sites using your own
  browser session cookie. VectorPlexus and LoversLab both run IPS, so the same
  code covers both, and any other IPS site by URL.

    # one time per site, per session
    ips_get.ps1 -Url https://vectorplexis.com/files/file/283-high-poly-head/ -CookieFromClipboard

    # then
    ips_get.ps1 -Url https://vectorplexis.com/files/file/283-high-poly-head/ -List
    ips_get.ps1 -Url https://vectorplexis.com/files/file/283-high-poly-head/ -File 1 -Apply

  WHY A COOKIE AND NOT A PASSWORD

  These sites publish no API. The only way in is the session, and there are
  three ways to hold one:

    a password in a file   your whole account, never expires, and a scripted
                           login has to fetch a CSRF token and survive bot
                           checks - which reads as credential stuffing and is
                           a real way to get an account locked
    a session cookie       a short-lived token, revoked by logging out,
                           attaches to a plain GET, no login flow at all
    a live browser         no secret anywhere, but not scriptable

  This is the middle one. Nothing here can log in, change a password, or post.
  It sends a cookie you already have and reads what that session can see.

  GETTING THE COOKIE

    1. Sign in to the site in Chrome, normally, with your saved password.
    2. F12 -> Network tab -> reload the page.
    3. Click the first request (the page itself).
    4. Right pane, Request Headers, find the line starting 'cookie:'.
    5. Copy the WHOLE value after 'cookie:'. Then run this with
       -CookieFromClipboard.

  It is stored at data\.<host>.cookie in this game root, the same way the
  Nexus API key is - each root owns its own, nothing reaches into another
  game's folders. Log out of the site and it stops working, which is the
  point.

  ENUMERATING - added 2026-09-08

    ips_get.ps1 -Url '<any listing page>' -Enumerate -Pages 3 -Out X:\...\ll.txt

  Point it at ANY page that lists files - a search results page, a category, an
  author's page - and it pulls out every file entry it finds. Deliberately NOT
  a built-in search: guessing at a site's search endpoint format is how you end
  up parsing the wrong thing silently. Search in the browser, copy the URL from
  the address bar, hand it over. -Pages walks &page=2, &page=3 and so on.

  It matches on the file-page URL shape, /files/file/<id>-<slug>/, which is
  stable across IPS sites and themes. Titles come from the anchor text.

  WHAT IT DOES NOT DO

  It does not log in, and it will not try. If the cookie is stale you get told
  so and you re-copy it.

  CLOUDFLARE - LOVERSLAB IS BLOCKED, 2026-09-08, DO NOT RETRY

  www.loverslab.com sits behind a Cloudflare MANAGED CHALLENGE. A valid session
  cookie is not enough and never will be. Confirmed by the response itself:

      Server: cloudflare
      cf-mitigated: challenge
      body: <title>Just a moment...</title>

  Tried and did not help: the real Chrome User-Agent reconstructed from the
  installed chrome.exe, the full client-hint set, sec-fetch-*, Accept and
  upgrade-insecure-requests. cf_clearance is bound to the browser's whole
  fingerprint including its TLS handshake, and .NET HttpClient does not have
  Chrome's handshake, so Cloudflare re-challenges whatever headers are sent.

  Getting past it means executing the challenge, which is bypassing a CAPTCHA,
  which CLAUDE.md section 2 forbids. So this is CLOSED, not open.

  THE WORKING ROUTE FOR LOVERSLAB: Matt downloads in his browser, where he is
  already cleared, and drops the archive in SKYRIM_SE\downloads or _incoming.
  Then install_downloaded.ps1, or install_mod.ps1 -Archive <path>, takes it from
  there. Everything after the fetch - requirements, conflicts, load order,
  verification - still works normally.

  VectorPlexus is a separate matter and is MALWARE, see CLAUDE.md section 2.
#>

[CmdletBinding()]
param(
    [string]$Root  = 'X:\MODDING\SKYRIM',
    [Parameter(Mandatory = $true)][string]$Url,
    [string]$Dest  = 'X:\MODDING\SKYRIM\_incoming',
    [string]$CookieFile,
    [string]$SaveCookie,
    [switch]$CookieFromClipboard,
    # Cloudflare binds cf_clearance to the exact UA that earned it. Get yours
    # from the browser console: navigator.userAgent
    [string]$UserAgent,
    [switch]$List,
    [string]$File,
    [switch]$Enumerate,
    [int]$Pages = 1,
    [string]$Out,
    [switch]$Dump,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36'

try   { $uri = [Uri]$Url }
catch { throw "not a URL: $Url" }
if ($uri.Scheme -ne 'https') { throw "https only, got '$($uri.Scheme)'" }
$host_ = $uri.Host

$DataDir = Join-Path $Root 'data'
if (-not $CookieFile) { $CookieFile = Join-Path $DataDir (".{0}.cookie" -f $host_) }
$UaFile = Join-Path $DataDir (".{0}.ua" -f $host_)
$LogDir  = Join-Path $Root 'logs'

Write-Host ""
Write-Host "=== ips_get : $host_ ===" -ForegroundColor Cyan
Write-Host ""

# ---- store the cookie ------------------------------------------------------
if ($CookieFromClipboard -or $SaveCookie) {
    $raw = if ($SaveCookie) { $SaveCookie } else { (Get-Clipboard -Raw) }
    if (-not $raw) { throw "nothing to save - clipboard empty, or -SaveCookie was blank" }
    $raw = ($raw -replace '^\s*cookie\s*:\s*','').Trim() -replace '[\r\n]+',' '
    if ($raw -notmatch 'ips4_') {
        Write-Host "  WARNING: no 'ips4_' cookie in that value. IPS sessions always have some." -ForegroundColor Yellow
        Write-Host "           Copy the whole value after 'cookie:' in Request Headers." -ForegroundColor Yellow
    }
    New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
    [IO.File]::WriteAllText($CookieFile, $raw, (New-Object Text.UTF8Encoding $false))
    # names only - never the values
    $names = @([regex]::Matches($raw, '(?:^|;)\s*([^=;\s]+)=') | ForEach-Object { $_.Groups[1].Value })
    Write-Host ("  saved    {0}" -f $CookieFile) -ForegroundColor Green
    Write-Host ("  {0} cookie(s): {1}" -f $names.Count, (($names | Select-Object -First 12) -join ', '))
    if ($raw -match 'cf_clearance' -and -not $UserAgent) {
        Write-Host ""
        Write-Host "  NOTE: this cookie carries cf_clearance, which Cloudflare binds to the EXACT" -ForegroundColor Yellow
        Write-Host "        User-Agent that earned it. Pass -UserAgent with your browser's real UA" -ForegroundColor Yellow
        Write-Host "        or every request will 403. Get it from the console: navigator.userAgent" -ForegroundColor Yellow
    }
    Write-Host ""
}

# ---- the User-Agent lives beside the cookie, because cf_clearance is bound to
# it. Storing them apart is how they drift, and a drifted pair is a 403 that
# looks exactly like an expired session.
if ($UserAgent) {
    New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
    [IO.File]::WriteAllText($UaFile, $UserAgent.Trim(), (New-Object Text.UTF8Encoding $false))
    Write-Host ("  saved    {0}" -f $UaFile) -ForegroundColor Green
    Write-Host ("  UA       {0}" -f $UserAgent.Trim())
    Write-Host ""
}
if (Test-Path -LiteralPath $UaFile) {
    $stored = (Get-Content -LiteralPath $UaFile -Raw).Trim()
    if ($stored) { $UA = $stored }
}

if (-not (Test-Path -LiteralPath $CookieFile)) {
    throw ("no cookie stored for {0}.`n  Sign in to the site in Chrome, copy the 'cookie:' request header, then re-run with -CookieFromClipboard.`n  Expected at: {1}" -f $host_, $CookieFile)
}
$cookie = (Get-Content -LiteralPath $CookieFile -Raw).Trim()
if (-not $cookie) { throw "cookie file is empty: $CookieFile" }
if ($cookie -match 'cf_clearance' -and -not (Test-Path -LiteralPath $UaFile)) {
    Write-Host "  WARNING: cf_clearance present but no stored User-Agent. Expect 403." -ForegroundColor Yellow
    Write-Host "           Re-run with -UserAgent '<navigator.userAgent from the browser>'." -ForegroundColor Yellow
    Write-Host ""
}

# ---- http ------------------------------------------------------------------
Add-Type -AssemblyName System.Net.Http | Out-Null
$handler = New-Object Net.Http.HttpClientHandler
$handler.AllowAutoRedirect = $true
$handler.AutomaticDecompression = [Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate
$client = New-Object Net.Http.HttpClient($handler)
$client.Timeout = [TimeSpan]::FromMinutes(30)
# TryAddWithoutValidation, not Add: HttpClient validates header values and a
# real browser cookie string trips its parser on characters it considers
# illegal, throwing before a single request is made.
$null = $client.DefaultRequestHeaders.TryAddWithoutValidation('User-Agent', $UA)
$null = $client.DefaultRequestHeaders.TryAddWithoutValidation('Cookie', $cookie)
$null = $client.DefaultRequestHeaders.TryAddWithoutValidation('Accept-Language', 'en-US,en;q=0.9')

# Cloudflare does not stop at the User-Agent. A cf_clearance cookie is issued to
# a whole request shape, so a bare UA plus cookie still reads as automation.
# These are the headers a real Chrome navigation sends, derived from the UA so
# the client-hint version can never disagree with it.
$chromeMajor = if ($UA -match 'Chrome/(\d+)') { $Matches[1] } else { '152' }
$null = $client.DefaultRequestHeaders.TryAddWithoutValidation('Accept',
    'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7')
$null = $client.DefaultRequestHeaders.TryAddWithoutValidation('sec-ch-ua',
    ('"Chromium";v="{0}", "Google Chrome";v="{0}", "Not?A_Brand";v="24"' -f $chromeMajor))
$null = $client.DefaultRequestHeaders.TryAddWithoutValidation('sec-ch-ua-mobile', '?0')
$null = $client.DefaultRequestHeaders.TryAddWithoutValidation('sec-ch-ua-platform', '"Windows"')
$null = $client.DefaultRequestHeaders.TryAddWithoutValidation('sec-fetch-dest', 'document')
$null = $client.DefaultRequestHeaders.TryAddWithoutValidation('sec-fetch-mode', 'navigate')
$null = $client.DefaultRequestHeaders.TryAddWithoutValidation('sec-fetch-site', 'none')
$null = $client.DefaultRequestHeaders.TryAddWithoutValidation('sec-fetch-user', '?1')
$null = $client.DefaultRequestHeaders.TryAddWithoutValidation('upgrade-insecure-requests', '1')

function Get-Page {
    param([string]$U)
    $r = $client.GetAsync($U, [Net.Http.HttpCompletionOption]::ResponseContentRead).GetAwaiter().GetResult()
    if (-not $r.IsSuccessStatusCode) { throw ("{0} returned {1} {2}" -f $U, [int]$r.StatusCode, $r.ReasonPhrase) }
    return $r.Content.ReadAsStringAsync().GetAwaiter().GetResult()
}

Write-Host ("  fetching {0}" -f $Url)
$html = Get-Page $Url

if ($Dump) {
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    $dp = Join-Path $LogDir ("ips_page_{0}.html" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    [IO.File]::WriteAllText($dp, $html, (New-Object Text.UTF8Encoding $false))
    Write-Host ("  dumped   {0}  ({1} KB)" -f $dp, [math]::Round($html.Length/1KB,1)) -ForegroundColor DarkGray
}

# ---- are we actually signed in --------------------------------------------
# IPS renders a sign-in prompt to guests and a user menu to members. Judge by
# the download links, not by the greeting, because themes change the greeting.
$signedIn = $html -match 'do=logout' -or $html -match 'ips4_member_id'
Write-Host ("  session  {0}" -f $(if ($signedIn) { 'signed in' } else { 'NOT signed in - cookie is stale or wrong site' })) `
    -ForegroundColor $(if ($signedIn) { 'Green' } else { 'Yellow' })

# ---- enumerate mode --------------------------------------------------------
# Any listing page: search results, a category, an author's files. Matches on
# the file-page URL shape rather than on theme-specific CSS classes, because
# themes change and that shape does not.
if ($Enumerate) {
    $rxFile = [regex]'(?i)href\s*=\s*"([^"]*?/files/file/(\d+)-[^"/?]*/?)"[^>]*>(?<t>[^<]{0,200})'
    $found  = New-Object System.Collections.Generic.List[object]
    $seenId = @{}

    for ($pg = 1; $pg -le [math]::Max(1,$Pages); $pg++) {
        if ($pg -eq 1) { $pageHtml = $html; $pageUrl = $Url }
        else {
            $sep = if ($Url -like '*?*') { '&' } else { '?' }
            $pageUrl = "$Url$sep" + "page=$pg"
            Write-Host ("  page {0}  {1}" -f $pg, $pageUrl) -ForegroundColor DarkGray
            try { $pageHtml = Get-Page $pageUrl } catch { Write-Host ("      failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow; break }
            Start-Sleep -Milliseconds 400
        }
        $before = $found.Count
        foreach ($mm in $rxFile.Matches($pageHtml)) {
            $u  = [Net.WebUtility]::HtmlDecode($mm.Groups[1].Value)
            $id = [int]$mm.Groups[2].Value
            if ($seenId.ContainsKey($id)) { continue }
            if ($u -notmatch '^https?://') { $u = (New-Object Uri($uri, $u)).AbsoluteUri }
            $t = ([Net.WebUtility]::HtmlDecode($mm.Groups['t'].Value)) -replace '\s+',' '
            $t = $t.Trim()
            if (-not $t) { continue }          # image-only anchors wrapping the same link
            $seenId[$id] = $true
            $found.Add([pscustomobject]@{ Id=$id; Title=$t; Url=$u })
        }
        $gained = $found.Count - $before
        if ($pg -gt 1 -and $gained -eq 0) { Write-Host "      no new entries - stopping" -ForegroundColor DarkGray; break }
    }

    if (-not $found.Count) {
        throw ("no file entries found on that page.`n  If it is definitely a listing page, re-run with -Dump and send me the HTML.`n  If the session line above says NOT signed in, re-copy the cookie first.")
    }

    Write-Host ""
    Write-Host ("  {0} file(s) found" -f $found.Count) -ForegroundColor Green
    foreach ($f in $found) { Write-Host ("      {0,-8} {1}" -f $f.Id, $f.Title) }

    if ($Out) {
        New-Item -ItemType Directory -Force -Path (Split-Path $Out -Parent) | Out-Null
        $w = New-Object System.Collections.Generic.List[string]
        $w.Add("IPS enumerate - $host_")
        $w.Add((Get-Date -Format 'yyyy-MM-dd HH:mm'))
        $w.Add("source: $Url")
        $w.Add("pages: $Pages   entries: $($found.Count)")
        $w.Add('')
        foreach ($f in $found) { $w.Add(("{0,-8} {1}" -f $f.Id, $f.Title)); $w.Add(("         {0}" -f $f.Url)) }
        [IO.File]::WriteAllLines($Out, $w, (New-Object Text.UTF8Encoding $false))
        Write-Host ("  report written: {0}" -f $Out) -ForegroundColor Green
    }
    Write-Host ""
    return
}

# ---- find the download links ----------------------------------------------
$rx = [regex]'(?is)<a\b[^>]*?href\s*=\s*"([^"]*?do=download[^"]*?)"[^>]*>(.*?)</a>'
$seen = @{}
$files = New-Object System.Collections.Generic.List[object]
foreach ($m in $rx.Matches($html)) {
    $href = [Net.WebUtility]::HtmlDecode($m.Groups[1].Value)
    if ($href -notmatch '^https?://') { $href = (New-Object Uri($uri, $href)).AbsoluteUri }
    if ($seen.ContainsKey($href)) { continue }
    $seen[$href] = $true
    $label = ([Net.WebUtility]::HtmlDecode(($m.Groups[2].Value -replace '(?s)<[^>]+>',' '))) -replace '\s+',' '
    $label = $label.Trim()
    # a bare '?do=download' with no r= is the whole-file button on a single-file entry
    $isAll = ($href -notmatch '[?&]r=')
    $files.Add([pscustomobject]@{ Url = $href; Label = $(if ($label) { $label } else { '(download)' }); All = $isAll })
}

if (-not $files.Count) {
    Write-Host ""
    if (-not $signedIn) {
        throw "no download links, and the session is not signed in. Re-copy the cookie and run with -CookieFromClipboard."
    }
    throw ("no download links found on that page. Re-run with -Dump and send me the HTML - the link pattern may have changed.`n  Page was {0} KB." -f [math]::Round($html.Length/1KB,1))
}

Write-Host ""
Write-Host ("  {0} download link(s):" -f $files.Count)
for ($i = 0; $i -lt $files.Count; $i++) {
    Write-Host ("      [{0}] {1}{2}" -f ($i+1), $files[$i].Label, $(if ($files[$i].All) { '   <- whole file / installer' } else { '' }))
}
Write-Host ""

if ($List -or (-not $File)) {
    Write-Host "  Pick one with -File <number> or -File <text from its label>, then add -Apply." -ForegroundColor Yellow
    Write-Host ""
    return
}

# ---- pick ------------------------------------------------------------------
$pick = $null
$n = 0
if ([int]::TryParse($File, [ref]$n)) {
    if ($n -lt 1 -or $n -gt $files.Count) { throw "-File $n is out of range, there are $($files.Count)" }
    $pick = $files[$n-1]
} else {
    $hits = @($files | Where-Object { $_.Label -like "*$File*" })
    if (-not $hits.Count) { throw "-File '$File' matches no label" }
    if ($hits.Count -gt 1) {
        Write-Host ("  '{0}' matches {1} links:" -f $File, $hits.Count) -ForegroundColor Yellow
        foreach ($h in $hits) { Write-Host ("      {0}" -f $h.Label) -ForegroundColor Yellow }
        throw "ambiguous - be more specific, or use the number."
    }
    $pick = $hits[0]
}

Write-Host ("  chosen   {0}" -f $pick.Label) -ForegroundColor Green

if (-not $Apply) {
    Write-Host ""
    Write-Host "  Nothing downloaded. Re-run with -Apply." -ForegroundColor Yellow
    Write-Host ""
    return
}

# ---- download --------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $Dest | Out-Null

$req = New-Object Net.Http.HttpRequestMessage([Net.Http.HttpMethod]::Get, $pick.Url)
$req.Headers.Referrer = $uri
$resp = $client.SendAsync($req, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
if (-not $resp.IsSuccessStatusCode) { throw ("download returned {0} {1}" -f [int]$resp.StatusCode, $resp.ReasonPhrase) }

$ctype = if ($resp.Content.Headers.ContentType) { $resp.Content.Headers.ContentType.MediaType } else { '' }
if ($ctype -like 'text/html*') {
    # IPS serves an HTML interstitial to sessions it does not trust, and to
    # guests waiting out a timer. Saving that as a .7z would be worse than
    # failing, because it looks like it worked.
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    $ip = Join-Path $LogDir ("ips_interstitial_{0}.html" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    [IO.File]::WriteAllText($ip, $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult(), (New-Object Text.UTF8Encoding $false))
    throw ("the server returned a web page, not a file - usually a stale session or a confirmation step.`n  Saved it to {0}" -f $ip)
}

$name = $null
if ($resp.Content.Headers.ContentDisposition -and $resp.Content.Headers.ContentDisposition.FileName) {
    $name = $resp.Content.Headers.ContentDisposition.FileName.Trim('"')
}
if (-not $name) { $name = [IO.Path]::GetFileName(([Uri]$pick.Url).LocalPath) }
if (-not $name -or $name -notmatch '\.(7z|zip|rar)$') {
    $safe = ($pick.Label -replace '[^\w\.\- ]','_').Trim()
    if (-not $safe) { $safe = 'download' }
    $name = "$safe.7z"
}
$outPath = Join-Path $Dest $name
$len = $resp.Content.Headers.ContentLength

Write-Host ("  name     {0}" -f $name)
Write-Host ("  size     {0}" -f $(if ($len) { "$([math]::Round($len/1MB,1)) MB" } else { 'unknown' }))
Write-Host ("  into     {0}" -f $outPath)
Write-Host "  downloading..."

$in  = $resp.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
$out = [IO.File]::Open($outPath, [IO.FileMode]::Create, [IO.FileAccess]::Write)
try {
    $buf = New-Object byte[] 1048576
    $total = 0L; $tick = 0
    while (($read = $in.Read($buf, 0, $buf.Length)) -gt 0) {
        $out.Write($buf, 0, $read); $total += $read; $tick++
        if ($tick % 32 -eq 0) { Write-Host ("      {0} MB" -f [math]::Round($total/1MB,0)) -NoNewline; Write-Host "`r" -NoNewline }
    }
} finally {
    $out.Dispose(); $in.Dispose()
}

$got = (Get-Item -LiteralPath $outPath).Length
Write-Host ("      {0} MB written" -f [math]::Round($got/1MB,1))

if ($len -and $got -ne $len) { throw "size mismatch: got $got bytes, server said $len" }
if ($got -lt 1024) { throw "only $got bytes - that is not a mod archive. Check the cookie." }

# an archive starts with a recognisable magic number; an error page does not
$sig = [byte[]](Get-Content -LiteralPath $outPath -Encoding Byte -TotalCount 6)
$hex = ($sig | ForEach-Object { $_.ToString('X2') }) -join ' '
$ok  = ($hex -like '37 7A BC AF 27 1C*') -or ($hex -like '50 4B*') -or ($hex -like '52 61 72 21*')
Write-Host ("  magic    {0}   {1}" -f $hex, $(if ($ok) { '7z / zip / rar - looks like an archive' } else { 'UNRECOGNISED - this may not be an archive' })) `
    -ForegroundColor $(if ($ok) { 'Green' } else { 'Yellow' })

Write-Host ""
Write-Host "  done." -ForegroundColor Green
Write-Host ("  install it with:  X:\MODDING\SKYRIM\tools\install_mod.ps1 -Archive '{0}' -FomodPlan -FomodDefaults" -f $outPath)
Write-Host ""
