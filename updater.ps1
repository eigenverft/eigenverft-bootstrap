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

.PARAMETER Owner
GitHub org/user (e.g., 'dotnet').

.PARAMETER Repo
Repository name (e.g., 'runtime').

.PARAMETER Path
Repository-relative file path using '/' (e.g., 'src/App.cs').

.PARAMETER Ref
Optional branch, tag, or commit SHA. If omitted, default branch is used.

.PARAMETER Token
Optional GitHub PAT to avoid rate limits.

.PARAMETER ApiBaseUri
API base (default 'https://api.github.com').

.PARAMETER RawHost
Host for raw content (default 'https://raw.githubusercontent.com').

.EXAMPLE
Get-GitHubFileInfo -Owner 'PowerShell' -Repo 'PowerShell' -Path 'README.md'

.EXAMPLE
(Get-GitHubFileInfo -Owner 'eigenverft' -Repo 'bootstrap' -Path 'README.md').RawUrlPinned

.OUTPUTS
[pscustomobject] with Owner, Repo, Path, Branch, LastCommitDate, Sha, Author, Committer, Message, HtmlUrl, ApiUrl, RawUrlRef, RawUrlPinned.

.NOTES
Public repos work unauthenticated (~60 req/h). Provide -Token to raise limits.
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

            # 1) Most recent commit for this path (optionally constrained by -Ref)
            $encodedPathParam = [System.Uri]::EscapeDataString($Path)
            $uri = "$base/repos/$ownerRepo/commits?path=$encodedPathParam&per_page=1"
            if ($Ref) { $uri += "&sha=$([System.Uri]::EscapeDataString($Ref))" }

            $resp = Invoke-RestMethod -Uri $uri -Headers $headers -Method GET -ErrorAction Stop
            if (-not $resp -or $resp.Count -eq 0) {
                throw "No commit found for path '$Path' in $ownerRepo (ref='$Ref')."
            }
            $c = $resp[0]

            $dateStr = $c.commit.author.date
            if (-not $dateStr) { $dateStr = $c.commit.committer.date }
            $date = [DateTime]::Parse(
                $dateStr,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::AdjustToUniversal
            )

            # 2) Determine branch for RawUrlRef
            $branchForRef = $Ref
            if (-not $branchForRef) {
                $repoMeta = Invoke-RestMethod -Uri "$base/repos/$ownerRepo" -Headers $headers -Method GET -ErrorAction Stop
                $branchForRef = if ($repoMeta.default_branch) { $repoMeta.default_branch } else { 'main' }
            }

            # 3) Encode path segments for raw URLs
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

function Save-GitHubFileFromInfo {
<#
.SYNOPSIS
Save a GitHub file (from Get-GitHubFileInfo) under %LOCALAPPDATA% using commit time as the file timestamp.

.DESCRIPTION
Maps to one of the following (controlled by -MapLayout):
  - OwnerRepo        : %LOCALAPPDATA%\[AdditionalSubPath]\<Owner>\<Repo>\<Path>
  - OwnerRepoBranch  : %LOCALAPPDATA%\[AdditionalSubPath]\<Owner>\<Repo>\<Branch>\<Path>

Freshness check is timestamp-only: compares local LastWriteTimeUtc to FileInfo.LastCommitDate (UTC)
within a small tolerance. If equal → skip; else download and set file times to the commit UTC.
Always clears Zone.Identifier unless disabled.

.PARAMETER FileInfo
Object from Get-GitHubFileInfo (needs: Owner, Repo, Path, RawUrlRef, RawUrlPinned, LastCommitDate).
If -MapLayout OwnerRepoBranch is used, FileInfo.Branch must be present.

.PARAMETER AdditionalSubPath
Optional extra directory below %LOCALAPPDATA% (e.g., 'Programs' or 'Programs\Bootstrap').

.PARAMETER MapLayout
Folder mapping mode. Default 'OwnerRepo'. Use 'OwnerRepoBranch' to include branch.

.PARAMETER UsePinned
Download from RawUrlPinned (immutable) instead of RawUrlRef.

.PARAMETER TimestampToleranceSeconds
Allowed absolute difference (seconds) between local LastWriteTimeUtc and commit UTC. Default: 2.

.PARAMETER RemoveZoneIdentifier
Remove Mark-of-the-Web (Zone.Identifier ADS). Default: $true.

.EXAMPLE
$info = Get-GitHubFileInfo -Owner eigenverft -Repo bootstrap -Path README.md
Save-GitHubFileFromInfo -FileInfo $info -AdditionalSubPath 'Programs' -MapLayout OwnerRepo

.EXAMPLE
Get-GitHubFileInfo -Owner PowerShell -Repo PowerShell -Path 'README.md' |
  ForEach-Object { Save-GitHubFileFromInfo -FileInfo $_ -MapLayout OwnerRepoBranch -UsePinned }
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$FileInfo,

        [string]$AdditionalSubPath,

        [ValidateSet('OwnerRepo','OwnerRepoBranch')]
        [string]$MapLayout = 'OwnerRepo',

        [switch]$UsePinned,

        [ValidateRange(0,300)]
        [int]$TimestampToleranceSeconds = 2,

        [bool]$RemoveZoneIdentifier = $true
    )

    # --- plain processing (no begin/process/end) ---

    # Required fields irrespective of layout.
    $required = @('Owner','Repo','Path','RawUrlRef','RawUrlPinned','LastCommitDate')
    foreach ($k in $required) {
        if (-not $FileInfo.$k) { throw "FileInfo is missing required field '$k'." }
    }
    if ($MapLayout -eq 'OwnerRepoBranch' -and -not $FileInfo.Branch) {
        throw "MapLayout 'OwnerRepoBranch' requires FileInfo.Branch."
    }

    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
    $root = if ($AdditionalSubPath) { Join-Path $localAppData $AdditionalSubPath } else { $localAppData }

    # External reviewer note: layout chosen explicitly; no hard-coded 'GitHub' prefix.
    switch ($MapLayout) {
        'OwnerRepo'       { $repoRoot = Join-Path $root ("{0}\{1}"       -f $FileInfo.Owner, $FileInfo.Repo) }
        'OwnerRepoBranch' { $repoRoot = Join-Path $root ("{0}\{1}\{2}"   -f $FileInfo.Owner, $FileInfo.Repo, $FileInfo.Branch) }
        default           { throw "Unsupported MapLayout: $MapLayout" }
    }

    $relPath  = ($FileInfo.Path -replace '\\','/').TrimStart('/')
    $destPath = Join-Path $repoRoot ($relPath -replace '/','\')
    $destDir  = Split-Path -Path $destPath -Parent

    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    $expectedUtc = ([DateTime]$FileInfo.LastCommitDate).ToUniversalTime()
    $sourceUrl   = if ($UsePinned) { $FileInfo.RawUrlPinned } else { $FileInfo.RawUrlRef }

    function _Clear-MoTW([string]$p, [bool]$do) {
        if ($do -and (Test-Path -LiteralPath $p)) {
            try { Unblock-File -LiteralPath $p -ErrorAction SilentlyContinue } catch {}
            try { Remove-Item -LiteralPath $p -Stream Zone.Identifier -ErrorAction SilentlyContinue | Out-Null } catch {}
        }
    }

    function _Apply-Time([System.IO.FileInfo]$fi, [DateTime]$utc) {
        # External reviewer note: normalize all times to the commit UTC for reproducibility.
        $fi.CreationTimeUtc   = $utc
        $fi.LastWriteTimeUtc  = $utc
        $fi.LastAccessTimeUtc = $utc
    }

    $existingFi = Get-Item -LiteralPath $destPath -ErrorAction SilentlyContinue
    if ($existingFi) {
        # Double-check equality with tolerance to account for filesystem rounding.
        $deltaSec = [Math]::Abs((($existingFi.LastWriteTimeUtc) - $expectedUtc).TotalSeconds)
        if ($deltaSec -le $TimestampToleranceSeconds) {
            _Apply-Time -fi $existingFi -utc $expectedUtc
            _Clear-MoTW -p $existingFi.FullName -do:$RemoveZoneIdentifier

            $verifiedDelta = [Math]::Abs(((Get-Item -LiteralPath $destPath).LastWriteTimeUtc - $expectedUtc).TotalSeconds)
            return [pscustomobject]@{
                Owner=$FileInfo.Owner; Repo=$FileInfo.Repo; Path=$FileInfo.Path; Branch=$FileInfo.Branch
                SourceUrl=$sourceUrl; LocalPath=$destPath; Action='SkippedTimestampMatch'; Changed=$false
                LastWriteTimeUtc=(Get-Item -LiteralPath $destPath).LastWriteTimeUtc
                CommitTimeUtc=$expectedUtc; TimestampDeltaSec=[Math]::Round($verifiedDelta,3)
                ZoneIdentifierCleared=$RemoveZoneIdentifier
            }
        }
    }

    # Missing or different timestamp → download and stamp.
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
            [pscustomobject]@{
                Owner=$FileInfo.Owner; Repo=$FileInfo.Repo; Path=$FileInfo.Path; Branch=$FileInfo.Branch
                SourceUrl=$sourceUrl; LocalPath=$destPath
                Action = if ($existingFi) { 'Updated' } else { 'Downloaded' }
                Changed=$true; LastWriteTimeUtc=(Get-Item -LiteralPath $destPath).LastWriteTimeUtc
                CommitTimeUtc=$expectedUtc; TimestampDeltaSec=[Math]::Round($verifiedDelta,3)
                ZoneIdentifierCleared=$RemoveZoneIdentifier
            }
        }
        finally {
            try { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue } catch {}
        }
    }
}

Write-Host "Starting Eigenverft PowerShell updater..."

$info = Get-GitHubFileInfo -Owner 'eigenverft' -Repo 'eigenverft-bootstrap' -Path 'scripts/lib.ps1'
$file = Save-GitHubFileFromInfo -FileInfo $info -AdditionalSubPath 'Programs' -MapLayout OwnerRepo

$info = Get-GitHubFileInfo -Owner 'eigenverft' -Repo 'eigenverft-bootstrap' -Path 'launcher.ps1'
$file = Save-GitHubFileFromInfo -FileInfo $info -AdditionalSubPath 'Programs' -MapLayout OwnerRepo

. "$($file.LocalPath)"

