# Rotwood-UA: translation auto-updater (runs BEFORE the game starts, game files are not touched).
# Source of truth: raw uk.po on GitHub. Version marker = ETag of the raw file (ukloc_version.txt).
# -Force : download and replace uk.po even if the version marker says it is up to date.
param([switch]$Force)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$Url     = 'https://raw.githubusercontent.com/MaksymKurny/Rotwood-UA/main/ukloc/localizations/uk.po'
$Target  = Join-Path $Root 'ukloc\localizations\uk.po'
$VerFile = Join-Path $Root 'ukloc_version.txt'
$Backup  = Join-Path $Root 'ukloc_uk.po.bak'
$Log     = Join-Path $Root 'ukua_update.log'
$Tmp     = $Target + '.download'
$VerLua  = Join-Path $Root 'ukloc\scripts\uk_version.lua'
$ApiUrl  = 'https://api.github.com/repos/MaksymKurny/Rotwood-UA/commits?path=ukloc/localizations/uk.po&page=1&per_page=1&sha=main'
$UA      = 'Rotwood-UA-updater'

# uk_version.lua is read by the game (uk_boot.lua) to show "PEREKLAD VID: DD.MM" on the main screen.
function Write-VersionLua($date) {
    try {
        [IO.File]::WriteAllText($VerLua, ('return "{0}"' -f $date) + "`n", (New-Object Text.UTF8Encoding($false)))
        Write-Log "uk_version.lua = $date"
    } catch { Write-Log ("version lua failed: " + $_.Exception.Message) }
}

# Date of the last commit that touched uk.po (same source the old mod used); $null if GitHub API is unavailable.
function Get-CommitDate {
    try {
        $r = Invoke-RestMethod -Uri $ApiUrl -TimeoutSec 8 -UserAgent $UA
        $d = @($r)[0].commit.author.date
        if ($d) { return [DateTimeOffset]::Parse($d).ToLocalTime().ToString('yyyy-MM-dd') }
    } catch { Write-Log ("commit date failed: " + $_.Exception.Message) }
    return $null
}

function Write-Log($msg) {
    try { ("{0}  {1}" -f (Get-Date -Format 's'), $msg) | Out-File -FilePath $Log -Append -Encoding ASCII } catch {}
}

try {
    if ((Test-Path $Log) -and ((Get-Item $Log).Length -gt 100KB)) { Remove-Item $Log -Force }

    if (-not (Test-Path $Target)) { Write-Log "skip: $Target not found"; exit 0 }

    # Offline-safe fallback: if there is no version file yet, use the date of the local uk.po.
    if (-not (Test-Path $VerLua)) { Write-VersionLua ((Get-Item $Target).LastWriteTime.ToString('yyyy-MM-dd')) }

    $head = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -TimeoutSec 8 -UserAgent $UA
    $remote = ([string](@($head.Headers['ETag'])[0])) -replace '^W/', '' -replace '"', ''
    if (-not $remote) { Write-Log 'skip: no ETag in response'; exit 0 }

    $local = ''
    if (Test-Path $VerFile) { $local = (Get-Content $VerFile -Raw).Trim() }

    if (-not $Force) {
        if (-not $local) {
            # First run: only remember the current GitHub version, do NOT overwrite local work.
            Set-Content -Path $VerFile -Value $remote -Encoding ASCII
            Write-Log "first run: version recorded ($remote), nothing downloaded"
            $d = Get-CommitDate; if ($d) { Write-VersionLua $d }
            exit 0
        }
        if ($local -eq $remote) { Write-Log 'up to date'; exit 0 }
    }

    Write-Log "updating: $local -> $remote"
    Invoke-WebRequest -Uri $Url -OutFile $Tmp -UseBasicParsing -TimeoutSec 60 -UserAgent $UA

    $size = (Get-Item $Tmp).Length
    $text = [IO.File]::ReadAllText($Tmp, [Text.Encoding]::UTF8)
    if ($size -lt 10000 -or $text -notmatch 'msgid\s+""' -or $text -notmatch 'msgstr') {
        throw "downloaded file looks wrong (size=$size)"
    }

    Copy-Item -Path $Target -Destination $Backup -Force
    Move-Item -Path $Tmp -Destination $Target -Force
    Set-Content -Path $VerFile -Value $remote -Encoding ASCII
    $d = Get-CommitDate; if (-not $d) { $d = (Get-Date).ToString('yyyy-MM-dd') }
    Write-VersionLua $d
    Write-Log "updated OK ($size bytes, version $remote); previous file saved to ukloc_uk.po.bak"
}
catch {
    Write-Log ("ERROR: " + $_.Exception.Message)
}
finally {
    if (Test-Path $Tmp) { Remove-Item $Tmp -Force -ErrorAction SilentlyContinue }
}
exit 0
