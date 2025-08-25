function Get-GitHubRepoFiles {
<#
.SYNOPSIS
List files/trees from a GitHub repo (optionally a subfolder) via the Trees API.

.DESCRIPTION
Resolves the ref (or default branch), optionally walks -SubPath to its subtree SHA,
then fetches that subtree with ?recursive=1. If GitHub returns "truncated", this
function returns $null (no partial results, no fallback walking). Raw URLs are
properly URL-escaped. PS5 + PS Core compatible.

.PARAMETER Owner
GitHub owner/org (e.g., 'dotnet').

.PARAMETER Repo
Repository name (e.g., 'runtime').

.PARAMETER Ref
Branch/tag/commit; if omitted, the repo's default branch is used.

.PARAMETER SubPath
Optional repo-relative subdirectory. '\' or '/' accepted.

.PARAMETER ItemType
'blob' (files), 'tree' (directories), or 'all'. Default 'blob'.

.PARAMETER Relative
If set with -SubPath, paths are relative to the subfolder; else repo root.

.PARAMETER UserAgent
User-Agent header; default: 'pwsh-public'.

.PARAMETER ApiVersion
GitHub REST API version; default: '2022-11-28'.

.PARAMETER Token
Optional PAT/GITHUB_TOKEN for private repos / higher limits.

.EXAMPLE
Get-GitHubRepoFiles -Owner eigenverft -Repo eigenverft-bootstrap -SubPath source -Relative
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()] [string]$Owner,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()] [string]$Repo,
        [string]$Ref,
        [string]$SubPath,
        [ValidateSet('blob','tree','all')] [string]$ItemType = 'blob',
        [switch]$Relative,
        [string]$UserAgent = 'pwsh-public',
        [string]$ApiVersion = '2022-11-28',
        [string]$Token
    )

    try {
        # Reviewer note: GitHub requires UA; use versioned Accept.
        $headers = @{
            'Accept'               = 'application/vnd.github+json'
            'X-GitHub-Api-Version' = $ApiVersion
        }
        if ($Token) { $headers['Authorization'] = "Bearer $Token" }

        # Resolve default branch only if needed.
        if (-not $Ref) {
            $repoInfo = Invoke-RestMethod -Uri ("https://api.github.com/repos/{0}/{1}" -f $Owner,$Repo) `
                                          -UserAgent $UserAgent -Headers $headers -ErrorAction Stop
            $Ref = $repoInfo.default_branch
        }

        # URL-escaped owner/repo/ref for raw links.
        $eOwner = [uri]::EscapeDataString($Owner)
        $eRepo  = [uri]::EscapeDataString($Repo)
        $eRef   = [uri]::EscapeDataString($Ref)

        # Resolve ref -> commit -> root tree SHA.
        $eref = [uri]::EscapeDataString($Ref)
        $commit    = Invoke-RestMethod -Uri ("https://api.github.com/repos/{0}/{1}/commits/{2}" -f $Owner,$Repo,$eref) `
                                       -UserAgent $UserAgent -Headers $headers -ErrorAction Stop
        $commitSha = $commit.sha
        $treeSha   = $commit.commit.tree.sha

        # If SubPath is set, walk level-by-level to that subtree SHA (non-recursive).
        $targetSha = $treeSha
        $prefix = $null
        if ($SubPath) {
            $normalized = ($SubPath -replace '\\','/').Trim('/').Trim()
            if ($normalized) {
                $prefix = $normalized
                foreach ($seg in ($normalized -split '/')) {
                    $treeLvl = Invoke-RestMethod -Uri ("https://api.github.com/repos/{0}/{1}/git/trees/{2}" -f $Owner,$Repo,$targetSha) `
                                                 -UserAgent $UserAgent -Headers $headers -ErrorAction Stop
                    $entry = $treeLvl.tree | Where-Object { $_.type -eq 'tree' -and $_.path -eq $seg } | Select-Object -First 1
                    if (-not $entry) { throw "SubPath '$SubPath' not found (missing segment '$seg')." }
                    $targetSha = $entry.sha
                }
            }
        }

        # Fetch subtree recursively; HARD FAIL on truncation.
        $tree = Invoke-RestMethod -Uri ("https://api.github.com/repos/{0}/{1}/git/trees/{2}?recursive=1" -f $Owner,$Repo,$targetSha) `
                                  -UserAgent $UserAgent -Headers $headers -ErrorAction Stop
        if ($tree.truncated) {
            Write-Verbose "Trees API returned truncated data for SHA $targetSha; failing per design."
            return $null
        }

        # Filter type.
        $items = $tree.tree
        switch ($ItemType) {
            'blob' { $items = $items | Where-Object { $_.type -eq 'blob' } }
            'tree' { $items = $items | Where-Object { $_.type -eq 'tree' } }
            'all'  { }
        }

        # Shape output; escape raw URLs. Keep '/' paths; provide OS-native PathDS.
        $ds = [IO.Path]::DirectorySeparatorChar
        $result = foreach ($it in $items) {
            $p = $it.path
            if (-not $Relative -and $prefix) {
                $p = ($prefix.TrimEnd('/') + '/' + $p).TrimStart('/')
            }
            $native = $p.Replace('/', $ds)

            $rawRef = $null
            $rawPinned = $null
            if ($it.type -eq 'blob') {
                # Encode each path segment, keep slashes
                $encPath = (($p -split '/') | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
                $rawRef    = "https://raw.githubusercontent.com/$eOwner/$eRepo/$eRef/$encPath"
                $rawPinned = "https://raw.githubusercontent.com/$eOwner/$eRepo/$commitSha/$encPath"
            }

            [pscustomobject]@{
                Path         = $p
                PathDS       = $native
                Sha          = $it.sha
                Size         = $it.size
                Mode         = $it.mode
                Type         = $it.type
                RawUrlRef    = $rawRef
                RawUrlPinned = $rawPinned
            }
        }

        return $result
    }
    catch {
        Write-Verbose ("Get-GitHubRepoFiles failed: {0}" -f $_.Exception.Message)
        return $null
    }
}


function Test-GitHubRepoFilesLocalMatch {
<#
.SYNOPSIS
Validates that local files match a GitHub repo file listing by existence and Git object hash.

.DESCRIPTION
Takes items from Get-GitHubRepoFiles (expects Type='blob', Path/PathDS, Sha). For each blob item:
- Builds a local path under -LocalRoot using PathDS (or Path with '/' -> OS separator).
- Verifies the file exists.
- Recomputes the Git blob object ID (SHA-1 by default; SHA-256 if 64-hex input) over "blob {size}\0{content}".
Returns $true only if all blobs exist and hashes match. Extra local files are ignored.
On any error (I/O, permissions, invalid input), returns $false.

.PARAMETER Items
Objects returned by Get-GitHubRepoFiles. Only entries with Type='blob' are validated.

.PARAMETER LocalRoot
Local directory to test against. Default: current directory.

.EXAMPLE
$files = Get-GitHubRepoFiles -Owner eigenverft -Repo eigenverft-bootstrap -SubPath updater
Test-GitHubRepoFilesLocalMatch -Items $files -LocalRoot "$env:TEMP\updater"

.OUTPUTS
System.Boolean
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [System.Collections.IEnumerable]$Items,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$LocalRoot = (Get-Location).Path
    )

    try {
        # Reviewer note: Normalize LocalRoot and ensure it exists.
        $root = [IO.Path]::GetFullPath($LocalRoot)
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { return $false }

        # Helper: compute Git blob OID (SHA-1 or SHA-256) for a given file path.
        function _Get-GitBlobOid([string]$FilePath, [string]$Algo) {
            $fi = [IO.FileInfo]::new($FilePath)
            if (-not $fi.Exists) { return $null }
            $size = $fi.Length

            $sha = if ($Algo -eq 'sha256') {
                [System.Security.Cryptography.SHA256]::Create()
            } else {
                [System.Security.Cryptography.SHA1]::Create()
            }

            $header = [System.Text.Encoding]::ASCII.GetBytes("blob $size") + @(0)
            $buffer = New-Object byte[] 81920

            # Feed header and file stream into the hasher without loading entire file into memory.
            $sha.TransformBlock($header, 0, $header.Length, $null, 0) | Out-Null
            $fs = [IO.File]::Open($fi.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            try {
                while (($read = $fs.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $sha.TransformBlock($buffer, 0, $read, $null, 0) | Out-Null
                }
            } finally {
                $fs.Dispose()
            }
            $sha.TransformFinalBlock([byte[]]::new(0), 0, 0) | Out-Null
            ($sha.Hash | ForEach-Object { $_.ToString("x2") }) -join ''
        }

        foreach ($it in $Items) {
            # Only validate blobs; ignore trees or unknown types.
            $typeProp = $it.PSObject.Properties['Type']
            if ($typeProp -and $it.Type -ne 'blob') { continue }

            # Resolve relative path from object (prefer PathDS; else Path normalized).
            $rel = $null
            if ($it.PSObject.Properties['PathDS']) {
                $rel = [string]$it.PathDS
            } elseif ($it.PSObject.Properties['Path']) {
                $rel = ([string]$it.Path) -replace '/', [IO.Path]::DirectorySeparatorChar
            } else {
                return $false  # Missing required path info.
            }

            $local = Join-Path -Path $root -ChildPath $rel

            # Must exist.
            if (-not (Test-Path -LiteralPath $local -PathType Leaf)) { return $false }

            # Determine hash algorithm by OID length (40 hex = sha1, 64 hex = sha256).
            $oid = [string]$it.Sha
            if ([string]::IsNullOrWhiteSpace($oid)) { return $false }
            $algo = if ($oid.Length -eq 64) { 'sha256' } else { 'sha1' }

            # Compute Git blob OID and compare case-insensitively.
            $calc = _Get-GitBlobOid -FilePath $local -Algo $algo
            if (-not $calc) { return $false }
            if (-not $calc.Equals($oid, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
        }

        return $true
    }
    catch {
        # Reviewer note: Per requirement, any failure yields $false rather than throwing.
        return $false
    }
}

function Save-GitHubRepoFilesToTemp {
<#
.SYNOPSIS
Download blob items (from Get-GitHubRepoFiles) to a temporary directory.

.DESCRIPTION
Downloads each item with Type='blob' to a unique temp folder. Uses RawUrlPinned when present,
else RawUrlRef. Cleans up and returns $null on any error; returns the temp folder path on success.

.PARAMETER Items
Items from Get-GitHubRepoFiles (expect Path/PathDS, Type, RawUrlPinned/RawUrlRef).

.PARAMETER RetryCount
Download retry attempts per file. Default 2.

.PARAMETER RetryDelaySec
Delay between retries. Default 2.

.OUTPUTS
System.String (temp directory path) or $null on failure.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Collections.IEnumerable]$Items,
        [int]$RetryCount = 2,
        [int]$RetryDelaySec = 2
    )
    try {
        # TLS 1.2 for PS5 web requests
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("ghdl_" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null

        $ds = [IO.Path]::DirectorySeparatorChar
        foreach ($it in $Items) {
            if (($it.PSObject.Properties['Type'] -and $it.Type -ne 'blob')) { continue }

            # Resolve relative path and source URL
            $rel = if ($it.PSObject.Properties['PathDS']) { [string]$it.PathDS } elseif ($it.PSObject.Properties['Path']) { ([string]$it.Path).Replace('/', $ds) } else { throw "Item missing Path/PathDS." }
            $url = if ($it.PSObject.Properties['RawUrlPinned'] -and $it.RawUrlPinned) { $it.RawUrlPinned }
                   elseif ($it.PSObject.Properties['RawUrlRef'] -and $it.RawUrlRef)   { $it.RawUrlRef }
                   else { throw "Item missing RawUrlPinned/RawUrlRef for '$rel'." }

            $out = Join-Path $tmp $rel
            $dir = Split-Path -Parent $out
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

            $ok = $false
            for ($i=0; $i -le $RetryCount; $i++) {
                try {
                    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $out -ErrorAction Stop
                    $ok = $true; break
                } catch {
                    if ($i -lt $RetryCount) { Start-Sleep -Seconds $RetryDelaySec } else { throw }
                }
            }
            if (-not $ok) { throw "Failed to download '$url'." }
        }
        return $tmp
    }
    catch {
        if ($tmp -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
        return $null
    }
}

function Publish-GitHubRepoFilesFromTemp {
<#
.SYNOPSIS
Publish files from a prepared temp tree into FinalRoot without directory renames, all-or-nothing.

.DESCRIPTION
Precondition: TempRoot was created by Save-GitHubRepoFilesToTemp and verified with Test-GitHubRepoFilesLocalMatch.
This function copies each blob from TempRoot to a *temp file* under FinalRoot, then commits per-file:
- If target exists: [System.IO.File]::Replace(temp, target, backup, $true) (atomic on the same volume).
- If target does not exist: [System.IO.File]::Move(temp, target).
If any commit fails, already-committed files are restored from backups and created files are removed.
On success, backups are deleted. Extra files in FinalRoot (not in Items) are left as-is.

.PARAMETER Items
Objects from Get-GitHubRepoFiles (Type='blob', Path/PathDS required).

.PARAMETER TempRoot
Directory containing the downloaded files (verified against Items).

.PARAMETER FinalRoot
Directory to receive/contain the files.

.OUTPUTS
System.Boolean  # $true on complete success; $false and no changes otherwise.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Collections.IEnumerable]$Items,
        [Parameter(Mandatory=$true)][string]$TempRoot,
        [Parameter(Mandatory=$true)][string]$FinalRoot
    )

    # Reviewer note: No directory renames, no robocopy; per-file temp + atomic replace/move with rollback.

    try {
        # 0) Basic guards
        if (-not (Test-Path -LiteralPath $TempRoot -PathType Container)) { return $false }
        if (-not (Test-GitHubRepoFilesLocalMatch -Items $Items -LocalRoot $TempRoot)) { return $false }

        # Ensure FinalRoot exists
        if (-not (Test-Path -LiteralPath $FinalRoot -PathType Container)) {
            New-Item -ItemType Directory -Path $FinalRoot -Force | Out-Null
        }

        $sep = [IO.Path]::DirectorySeparatorChar
        $plan = @()   # each entry: @{ Src=..; Dst=..; Tmp=..; Bak=.. }

        # 1) Build the plan and stage temp files under FinalRoot
        foreach ($it in $Items) {
            if ($it.PSObject.Properties['Type'] -and $it.Type -ne 'blob') { continue }

            # Resolve relative path
            $rel = if ($it.PSObject.Properties['PathDS']) { [string]$it.PathDS }
                   elseif ($it.PSObject.Properties['Path']) { ([string]$it.Path).Replace('/', $sep) }
                   else { return $false }

            $src = Join-Path $TempRoot $rel
            if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { return $false }

            $dst = Join-Path $FinalRoot $rel
            $dstDir = Split-Path -Parent $dst
            if (-not (Test-Path -LiteralPath $dstDir -PathType Container)) {
                New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
            }

            # Unique temp & backup names next to the destination
            $guid = [Guid]::NewGuid().ToString('N')
            $tmp = $dst + ".__new__" + $guid
            $bak = $dst + ".__bak__" + $guid

            # Stage: copy source -> temp (keep source for potential reattempts)
            [IO.File]::Copy($src, $tmp, $false)

            # Optional belt-and-suspenders: since TempRoot was already verified, we skip re-hashing $tmp.

            $plan += @{ Src=$src; Dst=$dst; Tmp=$tmp; Bak=$bak }
        }

        # 2) Commit phase: per-file atomic replace/move
        $committed = New-Object System.Collections.Generic.List[object]  # entries: @{Dst=..; Bak=..; Created=$true/$false}
        foreach ($step in $plan) {
            $dstExists = Test-Path -LiteralPath $step.Dst -PathType Leaf
            try {
                if ($dstExists) {
                    # Atomic replace; creates $step.Bak and deletes $step.Tmp on success
                    [IO.File]::Replace($step.Tmp, $step.Dst, $step.Bak, $true)
                    $committed.Add([pscustomobject]@{ Dst=$step.Dst; Bak=$step.Bak; Created=$false })
                } else {
                    # No existing target: Move temp into place (atomic rename on same volume)
                    [IO.File]::Move($step.Tmp, $step.Dst)
                    $committed.Add([pscustomobject]@{ Dst=$step.Dst; Bak=$null; Created=$true })
                }
            }
            catch {
                # 3) Roll back everything done so far; leave FinalRoot unchanged
                foreach ($c in [Enumerable]::Reverse($committed)) {
                    try {
                        if ($c.Created -eq $true) {
                            if (Test-Path -LiteralPath $c.Dst -PathType Leaf) { Remove-Item -LiteralPath $c.Dst -Force }
                        } else {
                            if ((Test-Path -LiteralPath $c.Bak -PathType Leaf) -and (Test-Path -LiteralPath $c.Dst -PathType Leaf)) {
                                # Restore original content
                                [IO.File]::Replace($c.Bak, $c.Dst, $null, $true)
                            } elseif (Test-Path -LiteralPath $c.Bak -PathType Leaf) {
                                # If somehow target disappeared, move backup back
                                [IO.File]::Move($c.Bak, $c.Dst)
                            }
                        }
                    } catch { }
                }
                # Clean any remaining temp files that weren’t committed
                foreach ($s in $plan) {
                    if (Test-Path -LiteralPath $s.Tmp -PathType Leaf) {
                        Remove-Item -LiteralPath $s.Tmp -Force -ErrorAction SilentlyContinue
                    }
                }
                return $false
            }
        }

        # 4) Success: remove backups and any stray temps (Replace should have deleted temps)
        foreach ($c in $committed) {
            if ($c.Bak -and (Test-Path -LiteralPath $c.Bak -PathType Leaf)) {
                Remove-Item -LiteralPath $c.Bak -Force -ErrorAction SilentlyContinue
            }
        }
        foreach ($s in $plan) {
            if (Test-Path -LiteralPath $s.Tmp -PathType Leaf) {
                Remove-Item -LiteralPath $s.Tmp -Force -ErrorAction SilentlyContinue
            }
        }

        return $true
    }
    catch {
        # Defensive cleanup of any temps if something failed early
        try {
            foreach ($s in $plan) {
                if ($s -and $s.Tmp -and (Test-Path -LiteralPath $s.Tmp -PathType Leaf)) {
                    Remove-Item -LiteralPath $s.Tmp -Force -ErrorAction SilentlyContinue
                }
            }
        } catch {}
        return $false
    }
}

Write-Host 'Starting Eigenverft updater...'

$files = Get-GitHubRepoFiles -Owner "eigenverft" -Repo "eigenverft-bootstrap" -SubPath "source"

if ($files) {
    $final = "$env:LOCALAPPDATA\Programs\eigenverft\eigenverft-bootstrap"

    $testResult = Test-GitHubRepoFilesLocalMatch -Items $files -LocalRoot $final
    if (-not $testResult) {
        Write-Host "Local files are missing or outdated; proceeding with update..."
        $tmp = Save-GitHubRepoFilesToTemp -Items $files
        if (-not $tmp)
        {
            Write-Host "Download failed.; local directory unchanged.";
        }

        if (Publish-GitHubRepoFilesFromTemp -Items $files -TempRoot $tmp -FinalRoot $final) {
            Write-Host "Update installed atomically."
        } else {
            Write-Host "Update failed; local directory unchanged."
        }
    }
}


# Dot-source launcher.ps1 if it exists; otherwise, warn the user.
$p = Join-Path $PSScriptRoot 'launcher.ps1'
if (Test-Path -LiteralPath $p -PathType Leaf) {
    try { . $p } catch { Write-Host "Dot-source failed: $($_.Exception.Message)" -ForegroundColor Red }
} else {
    Write-Host "launcher.ps1 not found: $p" -ForegroundColor Yellow
}

