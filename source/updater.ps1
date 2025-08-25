function Test-InternetConnectivity {
<#
.SYNOPSIS
Tests basic internet connectivity with DNS + HTTP checks.

.DESCRIPTION
Resolves api.github.com and raw.githubusercontent.com via DNS and performs a lightweight HTTP 204 check.
Returns $true on success, otherwise $false. Does not throw on failure.

.PARAMETER TimeoutSec
Overall timeout in seconds for the test. Default: 10.
#>
    [CmdletBinding()]
    param([int]$TimeoutSec = 10)

    try { [System.Net.Dns]::GetHostEntry('api.github.com') | Out-Null } catch { return $false }
    try { [System.Net.Dns]::GetHostEntry('raw.githubusercontent.com') | Out-Null } catch { return $false }

    try {
        $resp = Invoke-WebRequest -Uri 'https://www.google.com/generate_204' -Method GET -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
        return ($resp.StatusCode -eq 204 -or $resp.StatusCode -eq 200)
    } catch {
        try {
            $resp2 = Invoke-WebRequest -Uri 'http://www.msftconnecttest.com/connecttest.txt' -Method GET -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
            return ($resp2.StatusCode -eq 200)
        } catch { return $false }
    }
}

function Wait-ForInternet {
<#
.SYNOPSIS
Waits until internet is available (or timeout elapses).

.DESCRIPTION
Polls Test-InternetConnectivity every -IntervalSec seconds until success or -TimeoutSec expires.
Returns $true on success; $false on timeout. Does not throw.
#>
    [CmdletBinding()]
    param([int]$TimeoutSec = 120, [int]$IntervalSec = 5)

    $stopAt = [DateTime]::UtcNow.AddSeconds($TimeoutSec)
    while ([DateTime]::UtcNow -lt $stopAt) {
        if (Test-InternetConnectivity) { return $true }
        Start-Sleep -Seconds $IntervalSec
    }
    return $false
}

function Test-GitHubApiHealthy {
<#
.SYNOPSIS
Checks GitHub API health and remaining rate limit.

.DESCRIPTION
Calls /rate_limit and returns an object with IsHealthy, Remaining, ResetUtc, and Reason.
If the call fails or remaining is 0, IsHealthy=$false.

.PARAMETER Token
Optional GitHub token to raise limits.

.PARAMETER ApiBaseUri
API base (default 'https://api.github.com').
#>
    [CmdletBinding()]
    param(
        [string]$Token,
        [string]$ApiBaseUri = 'https://api.github.com'
    )

    $headers = @{ 'User-Agent' = 'GitHubApiHealth/1.0 (PowerShell 5)'; 'Accept'='application/vnd.github+json' }
    if ($Token) { $headers['Authorization'] = "Bearer $Token" }

    try {
        $base = $ApiBaseUri.TrimEnd('/')
        $resp = Invoke-RestMethod -Uri "$base/rate_limit" -Headers $headers -Method GET -ErrorAction Stop
        $rem = [int]$resp.resources.core.remaining
        $resetEpoch = [int64]$resp.resources.core.reset
        $resetUtc = [DateTimeOffset]::FromUnixTimeSeconds($resetEpoch).UtcDateTime
        [pscustomobject]@{
            IsHealthy = ($rem -gt 0)
            Remaining = $rem
            ResetUtc  = $resetUtc
            Reason    = if ($rem -gt 0) { 'OK' } else { 'Rate limit exhausted' }
        }
    } catch {
        [pscustomobject]@{ IsHealthy = $false; Remaining = 0; ResetUtc = $null; Reason = "API unreachable: $($_.Exception.Message)" }
    }
}

function Get-GitHubFileInfo {
<#
.SYNOPSIS
Gets metadata for a file in a public GitHub repo, including last commit date and raw URLs.

.DESCRIPTION
Queries /repos/{owner}/{repo}/commits?path=...&per_page=1 (optionally constrained by -Ref).
If -Ref is omitted, the repo's default branch is resolved via /repos/{owner}/{repo}.
Builds two raw URLs:
- RawUrlRef: branch/tag view (mutable)
- RawUrlPinned: exact commit SHA (immutable)
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Owner,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Repo,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path,
        [Parameter(Mandatory = $false)][string]$Ref,
        [Parameter(Mandatory = $false)][string]$Token,
        [Parameter(Mandatory = $false)][ValidateNotNullOrEmpty()][string]$ApiBaseUri = 'https://api.github.com',
        [Parameter(Mandatory = $false)][ValidateNotNullOrEmpty()][string]$RawHost    = 'https://raw.githubusercontent.com'
    )

    begin {
        $headers = @{
            'User-Agent' = 'Get-GitHubFileInfo/1.0 (PowerShell 5)'
            'Accept'     = 'application/vnd.github+json'
        }
        if ($Token) { $headers['Authorization'] = "Bearer $Token" }
    }

    process {
        try {
            $base = $ApiBaseUri.TrimEnd('/')
            $ownerRepo = "$Owner/$Repo"

            $encodedPathParam = [System.Uri]::EscapeDataString($Path)
            $uri = "$base/repos/$ownerRepo/commits?path=$encodedPathParam&per_page=1"
            if ($Ref) { $uri += "&sha=$([System.Uri]::EscapeDataString($Ref))" }

            $resp = Invoke-RestMethod -Uri $uri -Headers $headers -Method GET -ErrorAction Stop
            if (-not $resp -or $resp.Count -eq 0) { throw "No commit found for path '$Path' in $ownerRepo (ref='$Ref')." }
            $c = $resp[0]

            $dateStr = $c.commit.author.date; if (-not $dateStr) { $dateStr = $c.commit.committer.date }
            $date = [DateTime]::Parse($dateStr,[System.Globalization.CultureInfo]::InvariantCulture,[System.Globalization.DateTimeStyles]::AdjustToUniversal)

            $branchForRef = $Ref
            if (-not $branchForRef) {
                $repoMeta = Invoke-RestMethod -Uri "$base/repos/$ownerRepo" -Headers $headers -Method GET -ErrorAction Stop
                $branchForRef = if ($repoMeta.default_branch) { $repoMeta.default_branch } else { 'main' }
            }

            $pathNorm = ($Path -replace '\\','/').TrimStart('/')
            $segments = $pathNorm -split '/' | ForEach-Object { [System.Uri]::EscapeDataString($_) }
            $pathEncoded = ($segments -join '/')
            $rawBase = $RawHost.TrimEnd('/')

            $rawUrlRef    = "$rawBase/$Owner/$Repo/$branchForRef/$pathEncoded"
            $rawUrlPinned = "$rawBase/$Owner/$Repo/$($c.sha)/$pathEncoded"

            [PSCustomObject]@{
                Owner          = $Owner
                Repo           = $Repo
                Path           = $Path
                Branch         = $branchForRef
                LastCommitDate = $date
                Sha            = $c.sha
                Author         = $c.commit.author.name
                Committer      = $c.commit.committer.name
                Message        = $c.commit.message
                HtmlUrl        = $c.html_url
                ApiUrl         = $c.url
                RawUrlRef      = $rawUrlRef
                RawUrlPinned   = $rawUrlPinned
            }
        }
        catch {
            $msg = $_.Exception.Message
            if ($_.Exception.Response) {
                $code = $_.Exception.Response.StatusCode.Value__
                if ($code -eq 403) { throw "GitHub API 403 (rate limit likely). Provide -Token. Details: $msg" }
                if ($code -eq 404) { throw "GitHub API 404 (bad Owner/Repo/Path/Ref). Details: $msg" }
            }
            throw $_
        }
    }
}

function Try-Get-GitHubFileInfo {
<#
.SYNOPSIS
Safe wrapper around Get-GitHubFileInfo that returns $null on failure.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Owner,
        [Parameter(Mandatory=$true)][string]$Repo,
        [Parameter(Mandatory=$true)][string]$Path,
        [string]$Ref,
        [string]$Token,
        [string]$ApiBaseUri = 'https://api.github.com',
        [string]$RawHost    = 'https://raw.githubusercontent.com',
        [switch]$Quiet
    )

    if (-not (Test-InternetConnectivity)) {
        if (-not $Quiet) { Write-Warning 'Internet connectivity is unavailable; skipping Get-GitHubFileInfo.' }
        return $null
    }

    try {
        return Get-GitHubFileInfo -Owner $Owner -Repo $Repo -Path $Path -Ref $Ref -Token $Token -ApiBaseUri $ApiBaseUri -RawHost $RawHost -ErrorAction Stop
    } catch {
        if (-not $Quiet) { Write-Warning ("Get-GitHubFileInfo failed: {0}" -f $_.Exception.Message) }
        return $null
    }
}

function Save-GitHubFileFromInfo {
<#
.SYNOPSIS
Save a GitHub file (from Get-GitHubFileInfo) under %LOCALAPPDATA% using commit time as the file timestamp.
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)] [pscustomobject]$FileInfo,
        [string]$AdditionalSubPath,
        [ValidateSet('OwnerRepo','OwnerRepoBranch')] [string]$MapLayout = 'OwnerRepo',
        [switch]$UsePinned,
        [ValidateRange(0,300)] [int]$TimestampToleranceSeconds = 2,
        [bool]$RemoveZoneIdentifier = $true
    )

    if ($null -eq $FileInfo) { return $null }

    $required = @('Owner','Repo','Path','RawUrlRef','RawUrlPinned','LastCommitDate')
    foreach ($k in $required) { if (-not $FileInfo.$k) { throw "FileInfo is missing required field '$k'." } }
    if ($MapLayout -eq 'OwnerRepoBranch' -and -not $FileInfo.Branch) { throw "MapLayout 'OwnerRepoBranch' requires FileInfo.Branch." }

    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
    $root = if ($AdditionalSubPath) { Join-Path $localAppData $AdditionalSubPath } else { $localAppData }

    switch ($MapLayout) {
        'OwnerRepo'       { $repoRoot = Join-Path $root ("{0}\{1}"     -f $FileInfo.Owner, $FileInfo.Repo) }
        'OwnerRepoBranch' { $repoRoot = Join-Path $root ("{0}\{1}\{2}" -f $FileInfo.Owner, $FileInfo.Repo, $FileInfo.Branch) }
    }

    $relPath  = ($FileInfo.Path -replace '\\','/').TrimStart('/')
    $destPath = Join-Path $repoRoot ($relPath -replace '/','\')
    $destDir  = Split-Path -Path $destPath -Parent
    if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

    $expectedUtc = ([DateTime]$FileInfo.LastCommitDate).ToUniversalTime()
    $sourceUrl   = if ($UsePinned) { $FileInfo.RawUrlPinned } else { $FileInfo.RawUrlRef }

    function _Clear-MoTW([string]$p, [bool]$do) {
        if ($do -and (Test-Path -LiteralPath $p)) {
            try { Unblock-File -LiteralPath $p -ErrorAction SilentlyContinue } catch {}
            try { Remove-Item -LiteralPath $p -Stream Zone.Identifier -ErrorAction SilentlyContinue | Out-Null } catch {}
        }
    }
    function _Apply-Time([System.IO.FileInfo]$fi, [DateTime]$utc) {
        $fi.CreationTimeUtc=$utc; $fi.LastWriteTimeUtc=$utc; $fi.LastAccessTimeUtc=$utc
    }

    $existingFi = Get-Item -LiteralPath $destPath -ErrorAction SilentlyContinue
    if ($existingFi) {
        $deltaSec = [Math]::Abs((($existingFi.LastWriteTimeUtc) - $expectedUtc).TotalSeconds)
        if ($deltaSec -le $TimestampToleranceSeconds) {
            _Apply-Time -fi $existingFi -utc $expectedUtc
            _Clear-MoTW -p $existingFi.FullName -do:$RemoveZoneIdentifier
            $verifiedDelta = [Math]::Abs(((Get-Item -LiteralPath $destPath).LastWriteTimeUtc - $expectedUtc).TotalSeconds)
            return [pscustomobject]@{ Owner=$FileInfo.Owner; Repo=$FileInfo.Repo; Path=$FileInfo.Path; Branch=$FileInfo.Branch; SourceUrl=$sourceUrl; LocalPath=$destPath; Action='SkippedTimestampMatch'; Changed=$false; LastWriteTimeUtc=(Get-Item -LiteralPath $destPath).LastWriteTimeUtc; CommitTimeUtc=$expectedUtc; TimestampDeltaSec=[Math]::Round($verifiedDelta,3); ZoneIdentifierCleared=$RemoveZoneIdentifier }
        }
    }

    if ($PSCmdlet.ShouldProcess($destPath, "Download $sourceUrl")) {
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            Invoke-WebRequest -Uri $sourceUrl -OutFile $tmp -UseBasicParsing -ErrorAction Stop
            _Clear-MoTW -p $tmp -do:$RemoveZoneIdentifier
            Copy-Item -LiteralPath $tmp -Destination $destPath -Force
            $fi = Get-Item -LiteralPath $destPath -ErrorAction Stop
            _Apply-Time -fi $fi -utc $expectedUtc
            _Clear-MoTW -p $fi.FullName -do:$RemoveZoneIdentifier
            $verifiedDelta = [Math]::Abs(((Get-Item -LiteralPath $destPath).LastWriteTimeUtc - $expectedUtc).TotalSeconds)
            [pscustomobject]@{ Owner=$FileInfo.Owner; Repo=$FileInfo.Repo; Path=$FileInfo.Path; Branch=$FileInfo.Branch; SourceUrl=$sourceUrl; LocalPath=$destPath; Action = if ($existingFi) { 'Updated' } else { 'Downloaded' }; Changed=$true; LastWriteTimeUtc=(Get-Item -LiteralPath $destPath).LastWriteTimeUtc; CommitTimeUtc=$expectedUtc; TimestampDeltaSec=[Math]::Round($verifiedDelta,3); ZoneIdentifierCleared=$RemoveZoneIdentifier }
        } finally { try { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue } catch {} }
    }
}

function Resolve-LocalPathFromItem {
<#
.SYNOPSIS
Computes the expected local file path for an item without calling the GitHub API.

.DESCRIPTION
Supports MapLayout OwnerRepo (no branch needed) and OwnerRepoBranch (requires Branch on the item, or uses unique subdir if exactly one exists).
Returns $null if it cannot resolve unambiguously.

.PARAMETER Item
Hashtable or PSCustomObject with Owner, Repo, Path, and optional Branch.

.PARAMETER AdditionalSubPath
Local subdir under %LOCALAPPDATA%.

.PARAMETER MapLayout
OwnerRepo (default) or OwnerRepoBranch.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [object]$Item,
        [string]$AdditionalSubPath,
        [ValidateSet('OwnerRepo','OwnerRepoBranch')] [string]$MapLayout='OwnerRepo'
    )

    foreach ($k in 'Owner','Repo','Path') { if (-not $Item.$k) { return $null } }

    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
    $root = if ($AdditionalSubPath) { Join-Path $localAppData $AdditionalSubPath } else { $localAppData }

    $relPath  = ($Item.Path -replace '\\','/').TrimStart('/') -replace '/','\'

    switch ($MapLayout) {
        'OwnerRepo' {
            $repoRoot = Join-Path $root ("{0}\{1}" -f $Item.Owner, $Item.Repo)
            return Join-Path $repoRoot $relPath
        }
        'OwnerRepoBranch' {
            $repoRoot = Join-Path $root ("{0}\{1}" -f $Item.Owner, $Item.Repo)
            $branch = $Item.Branch
            if (-not $branch) {
                if (Test-Path -LiteralPath $repoRoot) {
                    $dirs = Get-ChildItem -LiteralPath $repoRoot -Directory -ErrorAction SilentlyContinue
                    if ($dirs -and $dirs.Count -eq 1) { $branch = $dirs[0].Name } else { return $null }
                } else { return $null }
            }
            return Join-Path (Join-Path $repoRoot $branch) $relPath
        }
    }
}

function Test-LocalSetComplete {
<#
.SYNOPSIS
Checks whether a list of items is fully present locally according to mapping rules.

.OUTPUTS
[pscustomobject] with Complete ([bool]) and Paths ([string[]]).
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [object[]]$Items,
        [string]$AdditionalSubPath,
        [ValidateSet('OwnerRepo','OwnerRepoBranch')] [string]$MapLayout='OwnerRepo'
    )

    $paths = @()
    foreach ($it in $Items) {
        $p = Resolve-LocalPathFromItem -Item $it -AdditionalSubPath $AdditionalSubPath -MapLayout $MapLayout
        if (-not $p) { return [pscustomobject]@{ Complete=$false; Paths=$paths } }
        $paths += $p
        if (-not (Test-Path -LiteralPath $p)) { return [pscustomobject]@{ Complete=$false; Paths=$paths } }
    }
    [pscustomobject]@{ Complete=$true; Paths=$paths }
}

function Invoke-GitHubBatchUpdate {
<#
.SYNOPSIS
Preflights rate limit, gets *all* file infos first, then saves them – with a local-only fallback
that allows safely invoking a launcher if everything is already present locally.

.DESCRIPTION
1) Waits for internet. 2) Checks /rate_limit once and ensures remaining calls are sufficient for the whole batch.
3) Resolves *all* Get-GitHubFileInfo objects first; if any fail → abort downloads.
4) If preflight/info resolution fails but -AllowLocalRunOnPreflightFail is set and the local set is complete,
   returns Mode=LocalRun and (optionally) dot-sources the launcher.
5) Otherwise saves each file using Save-GitHubFileFromInfo.

.PARAMETER Items
Array of hashtables/objects with at least Owner, Repo, Path, and optional Ref, Branch.

.PARAMETER Token
Optional GitHub token.

.PARAMETER AdditionalSubPath
Local subdir under %LOCALAPPDATA%.

.PARAMETER MapLayout
OwnerRepo (default) or OwnerRepoBranch.

.PARAMETER UsePinned
Download pinned URLs.

.PARAMETER AllowLocalRunOnPreflightFail
If set, allows running the launcher based on existing local files when preflight fails.

.PARAMETER LauncherRelativePath
Relative path of the launcher within the mapped repo (e.g., 'launcher.ps1'). Required to auto-invoke.

.PARAMETER AutoInvokeLauncher
If set, dot-sources the resolved launcher path when Mode is Updated or LocalRun.

.OUTPUTS
[pscustomobject] with Mode ('Updated'|'LocalRun'|'Aborted'), Results (array), LauncherLocalPath, Invoked ([bool]), Reason.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [Object[]]$Items,
        [string]$Token,
        [string]$AdditionalSubPath,
        [ValidateSet('OwnerRepo','OwnerRepoBranch')] [string]$MapLayout='OwnerRepo',
        [switch]$UsePinned,
        [string]$ApiBaseUri='https://api.github.com',
        [string]$RawHost='https://raw.githubusercontent.com',
        [switch]$AllowLocalRunOnPreflightFail,
        [string]$LauncherRelativePath,
        [switch]$AutoInvokeLauncher
    )

    if (-not (Wait-ForInternet -TimeoutSec 180 -IntervalSec 5)) {
        $reason = 'No internet; aborting batch.'
        if ($AllowLocalRunOnPreflightFail) {
            $local = Test-LocalSetComplete -Items $Items -AdditionalSubPath $AdditionalSubPath -MapLayout $MapLayout
            if ($local.Complete) {
                $launcherPath = if ($LauncherRelativePath) { Join-Path (Split-Path -Path $local.Paths[0] -Parent) $LauncherRelativePath } else { $null }
                $invoked = $false
                if ($AutoInvokeLauncher -and $launcherPath -and (Test-Path -LiteralPath $launcherPath)) { . $launcherPath; $invoked = $true }
                return [pscustomobject]@{ Mode='LocalRun'; Results=@(); LauncherLocalPath=$launcherPath; Invoked=$invoked; Reason=$reason }
            }
        }
        return [pscustomobject]@{ Mode='Aborted'; Results=@(); LauncherLocalPath=$null; Invoked=$false; Reason=$reason }
    }

    $status = Test-GitHubApiHealthy -Token $Token -ApiBaseUri $ApiBaseUri
    if (-not $status.IsHealthy) {
        $reason = "GitHub API unhealthy: $($status.Reason) (remaining=$($status.Remaining), reset=$($status.ResetUtc))"
        if ($AllowLocalRunOnPreflightFail) {
            $local = Test-LocalSetComplete -Items $Items -AdditionalSubPath $AdditionalSubPath -MapLayout $MapLayout
            if ($local.Complete) {
                $launcherPath = if ($LauncherRelativePath) { Join-Path (Split-Path -Path $local.Paths[0] -Parent) $LauncherRelativePath } else { $null }
                $invoked = $false
                if ($AutoInvokeLauncher -and $launcherPath -and (Test-Path -LiteralPath $launcherPath)) { . $launcherPath; $invoked = $true }
                return [pscustomobject]@{ Mode='LocalRun'; Results=@(); LauncherLocalPath=$launcherPath; Invoked=$invoked; Reason=$reason }
            }
        }
        return [pscustomobject]@{ Mode='Aborted'; Results=@(); LauncherLocalPath=$null; Invoked=$false; Reason=$reason }
    }

    # Estimate required API calls: for each item 1 commit call + (1 repo call if Ref omitted)
    $needed = 1 # we've already done one /rate_limit call
    foreach ($it in $Items) { $needed += 1 + ( [string]::IsNullOrEmpty($it.Ref) ? 1 : 0 ) }

    if ($status.Remaining -lt $needed) {
        $reason = "Insufficient GitHub API budget. Needed=$needed, Remaining=$($status.Remaining)."
        if ($AllowLocalRunOnPreflightFail) {
            $local = Test-LocalSetComplete -Items $Items -AdditionalSubPath $AdditionalSubPath -MapLayout $MapLayout
            if ($local.Complete) {
                $launcherPath = if ($LauncherRelativePath) { Join-Path (Split-Path -Path $local.Paths[0] -Parent) $LauncherRelativePath } else { $null }
                $invoked = $false
                if ($AutoInvokeLauncher -and $launcherPath -and (Test-Path -LiteralPath $launcherPath)) { . $launcherPath; $invoked = $true }
                return [pscustomobject]@{ Mode='LocalRun'; Results=@(); LauncherLocalPath=$launcherPath; Invoked=$invoked; Reason=$reason }
            }
        }
        return [pscustomobject]@{ Mode='Aborted'; Results=@(); LauncherLocalPath=$null; Invoked=$false; Reason=$reason }
    }

    # Resolve ALL infos first
    $infos = @()
    foreach ($it in $Items) {
        $info = Try-Get-GitHubFileInfo -Owner $it.Owner -Repo $it.Repo -Path $it.Path -Ref $it.Ref -Token $Token -ApiBaseUri $ApiBaseUri -RawHost $RawHost -Quiet
        if ($null -eq $info) {
            $reason = "Info resolution failed for $($it.Owner)/$($it.Repo):$($it.Path)"
            if ($AllowLocalRunOnPreflightFail) {
                $local = Test-LocalSetComplete -Items $Items -AdditionalSubPath $AdditionalSubPath -MapLayout $MapLayout
                if ($local.Complete) {
                    $launcherPath = if ($LauncherRelativePath) { Join-Path (Split-Path -Path $local.Paths[0] -Parent) $LauncherRelativePath } else { $null }
                    $invoked = $false
                    if ($AutoInvokeLauncher -and $launcherPath -and (Test-Path -LiteralPath $launcherPath)) { . $launcherPath; $invoked = $true }
                    return [pscustomobject]@{ Mode='LocalRun'; Results=@(); LauncherLocalPath=$launcherPath; Invoked=$invoked; Reason=$reason }
                }
            }
            return [pscustomobject]@{ Mode='Aborted'; Results=@(); LauncherLocalPath=$null; Invoked=$false; Reason=$reason }
        }
        $infos += $info
    }

    # Perform saves
    $results = @()
    foreach ($info in $infos) {
        $res = Save-GitHubFileFromInfo -FileInfo $info -AdditionalSubPath $AdditionalSubPath -MapLayout $MapLayout -UsePinned:$UsePinned
        $results += $res
    }

    # Resolve launcher path and optionally invoke
    $launcherPath = $null
    if ($LauncherRelativePath) {
        $firstItem = $Items[0]
        $baseForLauncher = Resolve-LocalPathFromItem -Item $firstItem -AdditionalSubPath $AdditionalSubPath -MapLayout $MapLayout
        if ($baseForLauncher) { $launcherPath = Join-Path (Split-Path -Path $baseForLauncher -Parent) $LauncherRelativePath }
    }

    $invoked = $false
    if ($AutoInvokeLauncher -and $launcherPath -and (Test-Path -LiteralPath $launcherPath)) { . $launcherPath; $invoked = $true }

    [pscustomobject]@{ Mode='Updated'; Results=$results; LauncherLocalPath=$launcherPath; Invoked=$invoked; Reason='OK' }
}

# ===== Example usage =====
Write-Host 'Starting Eigenverft PowerShell updater (atomic with local fallback)...'
Read-Host 'Press Enter to continue or Ctrl-C to abort.'

$items = @(
    @{ Owner='eigenverft'; Repo='eigenverft-bootstrap'; Path='scripts/lib.ps1' },
    @{ Owner='eigenverft'; Repo='eigenverft-bootstrap'; Path='launcher.ps1' }
)

$batch = Invoke-GitHubBatchUpdate -Items $items -AdditionalSubPath 'Programs' -MapLayout OwnerRepo -AllowLocalRunOnPreflightFail -LauncherRelativePath 'launcher.ps1' -AutoInvokeLauncher

switch ($batch.Mode) {
    'Updated'  { Write-Host 'Batch updated files and (optionally) invoked launcher.' }
    'LocalRun' { Write-Host 'Preflight failed, but local set was complete; launcher invoked from local cache.' }
    'Aborted'  { Write-Warning "Batch aborted: $($batch.Reason)" }
}
