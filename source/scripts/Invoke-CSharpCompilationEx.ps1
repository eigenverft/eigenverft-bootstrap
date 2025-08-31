function Invoke-CSharpCompilationEx {
<#
.SYNOPSIS
Build C# via MSBuild when a .sln/.csproj exists; otherwise compile .cs with csc.exe (classic .NET Framework toolchain only). Emits a single PSCustomObject and never writes tool output to the pipeline.

.DESCRIPTION
- Prefer MSBuild.exe from %WINDIR%\Microsoft.NET\Framework(64)\v4.0.30319 for .sln/.csproj.
- Else compile raw .cs with csc.exe from the same folder.
- -OutputPath may be a directory (recommended for projects) or a file path.
  * Directory: MSBuild OutDir = this directory; project controls the file name (or use -AssemblyName to override).
  * File path: OutDir = its directory; after build, the single produced artifact is optionally renamed to match the requested file name.
- Windows only. No Visual Studio dependency. No Roslyn/Add-Type.
- Always returns a single PSCustomObject. All MSBuild/CSC output is captured into LogLines/LogText and NEVER written to the pipeline.
  (The previous -SuppressBuildOutput/-Quiet switch is kept for compatibility but is no-op now.)

.PARAMETER Source
Paths (files/dirs; wildcards ok). Directories scanned recursively for *.cs and detects *.csproj/*.sln.

.PARAMETER OutputPath
Directory or file path. For projects, passing a directory (e.g. .\out) is typical; the project decides the artifact name unless -AssemblyName is specified.

.PARAMETER OutputType
Auto (default), Library, ConsoleApplication, or WindowsApplication. Ignored for MSBuild builds (we pick the newest .exe, then .dll). Used for csc.exe fallback to choose target.

.PARAMETER AssemblyName
Optional assembly name override. For MSBuild adds /p:AssemblyName=...; for csc.exe fallback names the output when -OutputPath is a directory.

.PARAMETER PdbType
Auto (Debug→Full, Release→PdbOnly), None, PdbOnly, or Full. Default: Auto. (Embedded not supported by CLR v4 toolchain.)

.PARAMETER References
Extra references (simple names or .dll paths) for csc.exe builds.

.PARAMETER CompilerOptions
Raw csc switches (e.g., "/unsafe+ /define:TRACE;DEBUG /optimize+"). Mapped to MSBuild properties where possible (DefineConstants, Optimize, AllowUnsafeBlocks, LangVersion, PlatformTarget).

.PARAMETER Exclude
Folder fragments to skip (e.g., "obj","bin",".git"). Default: ".git","obj","bin".

.PARAMETER Configuration
MSBuild configuration. Default: Release.

.PARAMETER SuppressBuildOutput
Deprecated; kept for compatibility. Tool output is always suppressed from the pipeline; logs are available on the return object.

.OUTPUTS
PSCustomObject with fields:
- Tool ('MSBuild'|'csc'), ToolPath (string), ToolArgs (string[]), ExitCode (int)
- IsProjectBuild (bool), Configuration (string), OutDir (string)
- Artifact (System.IO.FileInfo or $null), Renamed (bool), BuildSucceeded (bool)
- Message (string or $null)
- StartTime (DateTime), EndTime (DateTime), DurationMs (int)
- LogLines (string[]), LogText (string)
- Warnings (int?), Errors (int?)  # best-effort parsed from tool summary

.EXAMPLE
# Project build, keep project-defined name, drop into .\out
Invoke-CSharpCompilationEx2 -Source .\source\src -OutputPath .\out -Configuration Release -PdbType None

.EXAMPLE
# Project build, force assembly name (without editing csproj)
Invoke-CSharpCompilationEx2 -Source .\source\src -OutputPath .\out -AssemblyName MyApp -Configuration Release -PdbType None

.EXAMPLE
# Raw .cs → EXE via csc.exe; explicit file path
Invoke-CSharpCompilationEx2 -Source .\source\src -OutputType ConsoleApplication -OutputPath .\out\MyApp.exe -CompilerOptions "/unsafe+ /define:TRACE;DEBUG" -PdbType PdbOnly
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)]
        [string[]] $Source,

        [Parameter(Position=1)]
        [string]   $OutputPath,

        [ValidateSet('Auto','Library','ConsoleApplication','WindowsApplication')]
        [string]   $OutputType = 'Auto',

        [string]   $AssemblyName,

        [ValidateSet('Auto','None','PdbOnly','Full')]
        [string]   $PdbType = 'Auto',

        [string[]] $References,

        [string]   $CompilerOptions = '/optimize+',

        [string[]] $Exclude = @('.git','obj','bin'),

        [string]   $Configuration = 'Release',

        [Alias('Quiet')]
        [switch]   $SuppressBuildOutput
    )

    # -------- Collect inputs (.cs / .csproj / .sln)
    $allFiles = New-Object System.Collections.Generic.List[string]
    $projFiles = New-Object System.Collections.Generic.List[string]
    $slnFiles  = New-Object System.Collections.Generic.List[string]

    foreach ($s in $Source) {
        if ([string]::IsNullOrWhiteSpace($s)) { continue }
        $it = Get-Item -LiteralPath $s -ErrorAction SilentlyContinue

        if ($it -and $it.PSIsContainer) {
            $files = Get-ChildItem -LiteralPath $it.FullName -Recurse -File -ErrorAction SilentlyContinue
            foreach ($f in $files) {
                $skip = $false
                foreach ($ex in $Exclude) { if ($f.FullName -like "*$ex*") { $skip = $true; break } }
                if ($skip) { continue }
                switch -regex ($f.Extension) {
                    '^\.cs$'     { $allFiles.Add($f.FullName); break }
                    '^\.csproj$' { $projFiles.Add($f.FullName); break }
                    '^\.sln$'    { $slnFiles.Add($f.FullName); break }
                }
            }
        } else {
            $matches = @(Get-ChildItem -Path $s -File -ErrorAction SilentlyContinue)
            if (-not $matches -and $it -and -not $it.PSIsContainer) { $matches = @($it) }
            foreach ($m in $matches) {
                switch -regex ($m.Extension) {
                    '^\.cs$'     { $allFiles.Add($m.FullName); break }
                    '^\.csproj$' { $projFiles.Add($m.FullName); break }
                    '^\.sln$'    { $slnFiles.Add($m.FullName); break }
                }
            }
        }
    }

    if (($allFiles.Count -eq 0) -and ($projFiles.Count -eq 0) -and ($slnFiles.Count -eq 0)) {
        throw "No C# inputs found (no .cs, .csproj, or .sln) under -Source."
    }

    # -------- Output path classification
    function _LooksLikeDirectory([string]$p) {
        if (-not $p) { return $true }
        if (Test-Path -LiteralPath $p -PathType Container) { return $true }
        if ($p.TrimEnd() -match '[\\/]\s*$') { return $true }
        $ext = [System.IO.Path]::GetExtension($p)
        return [string]::IsNullOrEmpty($ext)
    }

    if (-not $OutputPath) { $OutputPath = Join-Path $PWD 'out' }

    $outputIsDir = _LooksLikeDirectory $OutputPath
    if ($outputIsDir) {
        if (-not (Test-Path $OutputPath)) { [void](New-Item -ItemType Directory -Path $OutputPath -Force) }
        $outDir = (Resolve-Path -LiteralPath $OutputPath).Path
        $outIsFile = $false
    } else {
        $outDir = Split-Path -Path $OutputPath -Parent
        if (-not (Test-Path $outDir)) { [void](New-Item -ItemType Directory -Path $outDir -Force) }
        $OutputPath = (Resolve-Path -LiteralPath $outDir).Path + "\" + [System.IO.Path]::GetFileName($OutputPath)
        $outIsFile = $true
    }

    # -------- Tools (Framework folder only)
    function _Find-FrameworkTool([string]$exeName) {
        $cands = @(
            (Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\$exeName"),
            (Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\$exeName")
        ) | Where-Object { Test-Path $_ }
        if ($cands) { return $cands[0] }
        return $null
    }
    $msbuild = _Find-FrameworkTool -exeName 'MSBuild.exe'
    $csc     = _Find-FrameworkTool -exeName 'csc.exe'
    if (-not $msbuild) { throw "MSBuild.exe not found in CLR v4.x folder. Install the .NET Framework 4.x Developer Pack." }
    if (-not $csc)     { throw "csc.exe not found in CLR v4.x folder. Install the .NET Framework 4.x Developer Pack." }

    # -------- Parse CompilerOptions and map to MSBuild props
    $splitOpts = @()
    if ($CompilerOptions) {
        $splitOpts = [regex]::Split($CompilerOptions, ' (?=(?:[^"]*"[^"]*")*[^"]*$)') | Where-Object { $_ -ne '' }
    }
    function _PropArg([string]$name, [string]$value) {
        if ([string]::IsNullOrWhiteSpace($value)) { return "/p:$name=" }
        if ($value -match '[; ]') { return "/p:$name=`"$value`"" }
        return "/p:$name=$value"
    }

    # PDB mapping
    $resolvedPdb = switch ($PdbType) {
        'Auto' { if ($Configuration -match '^(Debug)$') { 'Full' } else { 'PdbOnly' } }
        default { $PdbType }
    }

    $msbuildProps = @()
    foreach ($opt in $splitOpts) {
        if ($opt -match '^/define:(.+)$')      { $msbuildProps += _PropArg 'DefineConstants' $Matches[1]; continue }
        if ($opt -match '^/unsafe\+$')        { $msbuildProps += '/p:AllowUnsafeBlocks=true'; continue }
        if ($opt -match '^/unsafe\-$')        { $msbuildProps += '/p:AllowUnsafeBlocks=false'; continue }
        if ($opt -match '^/optimi[sz]e\+$')   { $msbuildProps += '/p:Optimize=true'; continue }
        if ($opt -match '^/optimi[sz]e\-$')   { $msbuildProps += '/p:Optimize=false'; continue }
        if ($opt -match '^/langversion:(.+)$') { $msbuildProps += _PropArg 'LangVersion' $Matches[1]; continue }
        if ($opt -match '^/platform:(.+)$')    { $msbuildProps += _PropArg 'PlatformTarget' $Matches[1]; continue }
    }
    if ($AssemblyName) { $msbuildProps += _PropArg 'AssemblyName' $AssemblyName }

    switch ($resolvedPdb) {
        'None'    { $msbuildProps += '/p:DebugSymbols=false'; $msbuildProps += '/p:DebugType=none' }
        'PdbOnly' { $msbuildProps += '/p:DebugSymbols=true';  $msbuildProps += '/p:DebugType=pdbonly' }
        'Full'    { $msbuildProps += '/p:DebugSymbols=true';  $msbuildProps += '/p:DebugType=full' }
    }

    # -------- Prefer MSBuild if project/solution found
    $projectOrSolution = if ($slnFiles.Count -gt 0) { $slnFiles[0] } elseif ($projFiles.Count -gt 0) { $projFiles[0] } else { $null }

    if ($projectOrSolution) {
        $outDirNorm = (Resolve-Path -LiteralPath $outDir).Path
        if ($outDirNorm[-1] -ne '\\') { $outDirNorm += '\\' }

        $hostArgs = @(
            $projectOrSolution,
            '/nologo',
            '/t:Build',
            "/p:Configuration=$Configuration",
            "/p:OutDir=$outDirNorm"
        )
        if ($msbuildProps) { $hostArgs += $msbuildProps }

        $start = Get-Date
        $msbuildOutputRaw = & $msbuild @hostArgs 2>&1
        $exit = $LASTEXITCODE
        $end = Get-Date

        $msbuildOutput = @()
        if ($msbuildOutputRaw) { $msbuildOutput = $msbuildOutputRaw | ForEach-Object { $_.ToString() } }
        # IMPORTANT: do NOT write the log to the pipeline; store on the object only.

        if ($exit -ne 0) {
            return [pscustomobject]@{
                Tool           = 'MSBuild'
                ToolPath       = $msbuild
                ToolArgs       = $hostArgs
                ExitCode       = $exit
                IsProjectBuild = $true
                Configuration  = $Configuration
                OutDir         = $outDir
                Artifact       = $null
                Renamed        = $false
                BuildSucceeded = $false
                Message        = "MSBuild failed with exit code $exit."
                StartTime      = $start
                EndTime        = $end
                DurationMs     = [int]($end - $start).TotalMilliseconds
                LogLines       = $msbuildOutput
                LogText        = ($msbuildOutput -join [Environment]::NewLine)
                Warnings       = ($msbuildOutput | ForEach-Object { if ($_ -match '^\s*(\d+)\s+Warning\(s\)') { [int]$Matches[1] } })[-1]
                Errors         = ($msbuildOutput | ForEach-Object { if ($_ -match '^\s*(\d+)\s+Error\(s\)')   { [int]$Matches[1] } })[-1]
            }
        }

        # Collect artifacts (prefer .exe, then .dll), newest first
        $exeCandidates = Get-ChildItem -Path $outDir -Recurse -Filter *.exe -File -ErrorAction SilentlyContinue
        $dllCandidates = Get-ChildItem -Path $outDir -Recurse -Filter *.dll -File -ErrorAction SilentlyContinue
        $candidates = @()
        if ($exeCandidates) { $candidates += ,$exeCandidates }
        if ($dllCandidates) { $candidates += ,$dllCandidates }
        $candidates = $candidates | Sort-Object -Property LastWriteTimeUtc -Descending

        $artifactItem = $null
        $renamed = $false
        $message = $null

        if ($candidates -and $candidates.Count -gt 0) {
            if ($outIsFile) {
                $desiredName = [System.IO.Path]::GetFileName($OutputPath)
                $exact = $candidates | Where-Object { $_.Name -ieq $desiredName } | Select-Object -First 1
                if ($exact) {
                    $artifactItem = $exact
                } elseif ($candidates.Count -eq 1) {
                    $null = Rename-Item -LiteralPath $candidates[0].FullName -NewName $desiredName -Force
                    $artifactItem = Get-Item -LiteralPath (Join-Path $outDir $desiredName)
                    $renamed = $true
                } else {
                    $message = "Multiple artifacts produced in '$outDir'. Use -AssemblyName to control the output name or pass -OutputPath as a directory."
                }
            } else {
                $artifactItem = $candidates[0]
            }
        } else {
            $message = "Build succeeded but no .exe or .dll found in '$outDir'. Verify project target type and Configuration."
        }

        return [pscustomobject]@{
            Tool           = 'MSBuild'
            ToolPath       = $msbuild
            ToolArgs       = $hostArgs
            ExitCode       = 0
            IsProjectBuild = $true
            Configuration  = $Configuration
            OutDir         = $outDir
            Artifact       = $artifactItem
            Renamed        = $renamed
            BuildSucceeded = $true
            Message        = $message
            StartTime      = $start
            EndTime        = $end
            DurationMs     = [int]($end - $start).TotalMilliseconds
            LogLines       = $msbuildOutput
            LogText        = ($msbuildOutput -join [Environment]::NewLine)
            Warnings       = ($msbuildOutput | ForEach-Object { if ($_ -match '^\s*(\d+)\s+Warning\(s\)') { [int]$Matches[1] } })[-1]
            Errors         = ($msbuildOutput | ForEach-Object { if ($_ -match '^\s*(\d+)\s+Error\(s\)')   { [int]$Matches[1] } })[-1]
        }
    }

    # -------- Fallback: compile raw .cs with csc.exe
    if ($allFiles.Count -eq 0) { throw "No .cs files found to compile (and no project/solution to build)." }

    $refs = @('System','System.Core','Microsoft.CSharp')
    if ($References) { $refs += $References }

    # Decide target/ext for CSC when OutputType=Auto (default to library)
    if ($OutputType -eq 'Auto') {
        $cscTarget = 'library'
        $extForCsc = '.dll'
    } else {
        $cscTarget = if ($OutputType -eq 'WindowsApplication') { 'winexe' } elseif ($OutputType -eq 'Library') { 'library' } else { 'exe' }
        $extForCsc = if ($cscTarget -eq 'library') { '.dll' } else { '.exe' }
    }

    # When OutputPath is a directory for csc.exe, compute file path using AssemblyName or folder name
    if ($outputIsDir) {
        $baseName  = if ($AssemblyName) { $AssemblyName } else {
            $d = Split-Path -Leaf (Split-Path -Parent $allFiles[0])
            if ([string]::IsNullOrWhiteSpace($d)) { 'build' } else { $d }
        }
        $OutputPath = Join-Path $outDir ($baseName + $extForCsc)
    }

    $pdbPath = [System.IO.Path]::ChangeExtension($OutputPath, '.pdb')

    $hostArgs2 = @('/nologo', "/target:$cscTarget", "/out:$OutputPath")
    # PDB control for csc.exe
    switch ($resolvedPdb) {
        'None'    { $hostArgs2 += '/debug-'; }
        'PdbOnly' { $hostArgs2 += '/debug:pdbonly'; $hostArgs2 += "/pdb:$pdbPath" }
        'Full'    { $hostArgs2 += '/debug:full';    $hostArgs2 += "/pdb:$pdbPath" }
    }
    if ($splitOpts) { $hostArgs2 += $splitOpts }
    foreach ($r in $refs) {
        $refPath = if ($r -match '\.dll$') { $r } else { "$r.dll" }
        $hostArgs2 += "/r:$refPath"
    }
    $hostArgs2 += $allFiles.ToArray()  # PowerShell handles quoting

    $start2 = Get-Date
    $cscOutputRaw = & $csc @hostArgs2 2>&1
    $exit2 = $LASTEXITCODE
    $end2 = Get-Date

    $cscOutput = @()
    if ($cscOutputRaw) { $cscOutput = $cscOutputRaw | ForEach-Object { $_.ToString() } }
    # IMPORTANT: do NOT write the log to the pipeline; store on the object only.

    if ($exit2 -ne 0) {
        return [pscustomobject]@{
            Tool           = 'csc'
            ToolPath       = $csc
            ToolArgs       = $hostArgs2
            ExitCode       = $exit2
            IsProjectBuild = $false
            Configuration  = $Configuration
            OutDir         = $outDir
            Artifact       = $null
            Renamed        = $false
            BuildSucceeded = $false
            Message        = "csc.exe exited with code $exit2."
            StartTime      = $start2
            EndTime        = $end2
            DurationMs     = [int]($end2 - $start2).TotalMilliseconds
            LogLines       = $cscOutput
            LogText        = ($cscOutput -join [Environment]::NewLine)
            Warnings       = ($cscOutput | ForEach-Object { if ($_ -match '^\s*(\d+)\s+Warning\(s\)') { [int]$Matches[1] } })[-1]
            Errors         = ($cscOutput | ForEach-Object { if ($_ -match '^\s*(\d+)\s+Error\(s\)')   { [int]$Matches[1] } })[-1]
        }
    }

    $artifact = if (Test-Path -LiteralPath $OutputPath) { Get-Item -LiteralPath $OutputPath } else { $null }

    return [pscustomobject]@{
        Tool           = 'csc'
        ToolPath       = $csc
        ToolArgs       = $hostArgs2
        ExitCode       = 0
        IsProjectBuild = $false
        Configuration  = $Configuration
        OutDir         = $outDir
        Artifact       = $artifact
        Renamed        = $false
        BuildSucceeded = $true
        Message        = $null
        StartTime      = $start2
        EndTime        = $end2
        DurationMs     = [int]($end2 - $start2).TotalMilliseconds
        LogLines       = $cscOutput
        LogText        = ($cscOutput -join [Environment]::NewLine)
        Warnings       = ($cscOutput | ForEach-Object { if ($_ -match '^\s*(\d+)\s+Warning\(s\)') { [int]$Matches[1] } })[-1]
        Errors         = ($cscOutput | ForEach-Object { if ($_ -match '^\s*(\d+)\s+Error\(s\)')   { [int]$Matches[1] } })[-1]
    }
}

function Set-AssemblyVersionAttributes {
<#
.SYNOPSIS
Replace AssemblyVersion and AssemblyFileVersion attributes in .cs files under a path.

.DESCRIPTION
Scans all .cs files under the given path (file or directory) and, if -Version is provided,
replaces the string literal inside:
  [assembly: AssemblyVersion("...")]            # (or AssemblyVersionAttribute)
  [assembly: AssemblyFileVersion("...")]        # (or AssemblyFileVersionAttribute)
with the provided version. If nothing matches, nothing is changed. If -Version is not
specified or empty, nothing is done.

- Compatible with Windows PowerShell 5.1 and PowerShell 7+.
- No Begin/Process/End blocks.
- Preserves each file's original text encoding (best-effort via StreamReader detection).
- Skips common build folders via -Exclude.
- Supports -WhatIf / -Confirm via SupportsShouldProcess.

.PARAMETER Path
A file or directory (wildcards allowed). Directories are scanned recursively for *.cs.

.PARAMETER Version
Semantic version string (e.g., 1.2.3.4). If not provided or empty, function is a no-op.

.PARAMETER Exclude
Directory fragments to skip (e.g., 'obj','bin','.git'). Default: '.git','obj','bin'.

.PARAMETER IncludeInformational
Additionally update [assembly: AssemblyInformationalVersion("...")].

.EXAMPLE
Set-AssemblyVersionAttributes -Path .\src -Version 1.2.3.4

.EXAMPLE
Set-AssemblyVersionAttributes -Path .\Properties\AssemblyInfo.cs -Version 2.0.0.0 -WhatIf

.OUTPUTS
PSCustomObject with summary fields:
- Version        (string)
- UpdatedCount   (int)
- UpdatedFiles   (string[])
- SkippedCount   (int)
- ScannedCount   (int)
- NoOp           (bool)
#>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Low')]
    param(
        [Parameter(Mandatory, Position=0)]
        [string[]] $Path,

        [Parameter(Position=1)]
        [string]   $Version,

        [string[]] $Exclude = @('.git','obj','bin'),

        [switch]   $IncludeInformational
    )

    # No-op if no version provided
    if ([string]::IsNullOrWhiteSpace($Version)) {
        return [pscustomobject]@{
            Version      = $null
            UpdatedCount = 0
            UpdatedFiles = @()
            SkippedCount = 0
            ScannedCount = 0
            NoOp         = $true
        }
    }

    # Helper: enumerate target .cs files
    $targets = New-Object System.Collections.Generic.List[string]
    foreach ($p in $Path) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $it = Get-Item -LiteralPath $p -ErrorAction SilentlyContinue
        if ($it -and $it.PSIsContainer) {
            $files = Get-ChildItem -LiteralPath $it.FullName -Recurse -File -Filter *.cs -ErrorAction SilentlyContinue
            foreach ($f in $files) {
                $skip = $false
                foreach ($ex in $Exclude) { if ($f.FullName -like "*${ex}*") { $skip = $true; break } }
                if (-not $skip) { $targets.Add($f.FullName) }
            }
        } else {
            $matches = @(Get-ChildItem -Path $p -File -ErrorAction SilentlyContinue)
            if (-not $matches -and $it -and -not $it.PSIsContainer) { $matches = @($it) }
            foreach ($m in $matches) {
                if ($m.Extension -ieq '.cs') {
                    $skip = $false
                    foreach ($ex in $Exclude) { if ($m.FullName -like "*${ex}*") { $skip = $true; break } }
                    if (-not $skip) { $targets.Add($m.FullName) }
                }
            }
        }
    }

    $updated = @()
    $skipped = 0

    # Regexes: match start-of-line (ignoring preceding whitespace) and avoid lines that begin with //
    $rxOptions = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Multiline
    $rxAsmVer  = New-Object System.Text.RegularExpressions.Regex '^(?!\s*//)\s*\[\s*assembly\s*:\s*AssemblyVersion(?:Attribute)?\s*\(\s*"([^"]*)"', $rxOptions
    $rxFileVer = New-Object System.Text.RegularExpressions.Regex '^(?!\s*//)\s*\[\s*assembly\s*:\s*AssemblyFileVersion(?:Attribute)?\s*\(\s*"([^"]*)"', $rxOptions
    $rxInfoVer = if ($IncludeInformational) { New-Object System.Text.RegularExpressions.Regex '^(?!\s*//)\s*\[\s*assembly\s*:\s*AssemblyInformationalVersion(?:Attribute)?\s*\(\s*"([^"]*)"', $rxOptions } else { $null }

    # Read & write with original encoding
    foreach ($file in $targets) {
        # Detect encoding using StreamReader (auto-detect BOM)
        $fs = [System.IO.File]::Open($file, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $sr = New-Object System.IO.StreamReader($fs, $true)
            $text = $sr.ReadToEnd()
            $encoding = $sr.CurrentEncoding
            $sr.Close(); $fs.Close()
        } catch {
            if ($sr) { $sr.Close() }; if ($fs) { $fs.Close() }
            $skipped++
            continue
        }

        $original = $text

        # Replace the content inside the first quoted group for each attribute
        $text = $rxAsmVer.Replace($text, { param($m) $m.Value.Substring(0, $m.Groups[1].Index - $m.Index) + $Version + $m.Value.Substring(($m.Groups[1].Index - $m.Index) + $m.Groups[1].Length) })
        $text = $rxFileVer.Replace($text, { param($m) $m.Value.Substring(0, $m.Groups[1].Index - $m.Index) + $Version + $m.Value.Substring(($m.Groups[1].Index - $m.Index) + $m.Groups[1].Length) })
        if ($rxInfoVer) {
            $text = $rxInfoVer.Replace($text, { param($m) $m.Value.Substring(0, $m.Groups[1].Index - $m.Index) + $Version + $m.Value.Substring(($m.Groups[1].Index - $m.Index) + $m.Groups[1].Length) })
        }

        if ($text -ne $original) {
            if ($PSCmdlet.ShouldProcess($file, "Set assembly version to $Version")) {
                [System.IO.File]::WriteAllText($file, $text, $encoding)
                $updated += ,$file
            }
        } else {
            $skipped++
        }
    }

    return [pscustomobject]@{
        Version      = $Version
        UpdatedCount = ($updated | Measure-Object).Count
        UpdatedFiles = $updated
        SkippedCount = $skipped
        ScannedCount = $targets.Count
        NoOp         = $false
    }
}

function Invoke-BuildIfRequired {
<#
.SYNOPSIS
Minimal version-aware build wrapper that skips rebuilding when an existing EXE already has the requested version.

.DESCRIPTION
- Resolves <OutPath>\<AssemblyName>.exe as the expected artifact when OutPath is a directory; if OutPath is a file path, uses that.
- If the exe exists and its FileVersion equals -ThisVersion (when specified), skips build and returns the executable.
- Otherwise, optionally updates AssemblyVersion/AssemblyFileVersion in source via Set-AssemblyVersionAttributes (if available) and builds via **Invoke-CSharpCompilationEx** (fixed).
- Works on PS5 and PS7. Emits a single PSCustomObject; no extra pipeline noise.

.PARAMETER SourceDir
Root folder with C# sources (and/or .csproj/.sln).

.PARAMETER AssemblyName
Base name used for expected EXE when OutPath is a directory.

.PARAMETER ThisVersion
Desired version string (e.g., 1.2.3.4). If empty/null, version update is skipped and the version check is disabled.

.PARAMETER OutPath
Directory or file path for compiler output. Defaults to .\out.

# Passthrough parameters forwarded to Invoke-CSharpCompilationEx
.PARAMETER OutputType
Default WindowsApplication.

.PARAMETER Configuration
Default Release.

.PARAMETER PdbType
Default None.

.PARAMETER CompilerOptions
Default '/optimize+'.

.PARAMETER References
Additional references for the compiler.

.PARAMETER SuppressBuildOutput
Alias: -Quiet. Suppresses compiler console output.

.EXAMPLE
Invoke-BuildSimple -SourceDir .\source\src -AssemblyName MyApp -ThisVersion 1.2.3.5 -OutPath .\out -Quiet

.EXAMPLE
Invoke-BuildSimple -SourceDir .\source\src -AssemblyName MyApp -OutPath .\out\MyApp.exe -OutputType WindowsApplication -Configuration Release

.OUTPUTS
PSCustomObject with fields: Skipped, Reason, Executable (FileInfo), Result (compiler result or $null on skip).
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)] [string] $SourceDir,
        [Parameter(Mandatory, Position=1)] [string] $AssemblyName,
        [Parameter(Position=2)]               [string] $ThisVersion,
        [Parameter(Position=3)]               [string] $OutPath = '.\\out',

        # Passthrough to Invoke-CSharpCompilationEx
        [ValidateSet('Auto','Library','ConsoleApplication','WindowsApplication')]
        [string] $OutputType = 'WindowsApplication',
        [string] $Configuration = 'Release',
        [ValidateSet('Auto','None','PdbOnly','Full')]
        [string] $PdbType = 'None',
        [string] $CompilerOptions = '/optimize+',
        [string[]] $References,
        [Alias('Quiet')]
        [switch] $SuppressBuildOutput
    )

    # Ensure OutPath exists appropriately
    function _LooksLikeDirectory([string]$p) {
        if (-not $p) { return $true }
        if (Test-Path -LiteralPath $p -PathType Container) { return $true }
        if ($p.TrimEnd() -match '[\\/]\s*$') { return $true }
        $ext = [System.IO.Path]::GetExtension($p)
        return [string]::IsNullOrEmpty($ext)
    }

    if (-not (Test-Path -LiteralPath $OutPath)) {
        $parent = Split-Path -Path $OutPath -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) { $parent = '.' }
        if (-not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
        if (_LooksLikeDirectory $OutPath) { [void](New-Item -ItemType Directory -Path $OutPath -Force) }
    }

    $expectedExe = if (_LooksLikeDirectory $OutPath) {
        $dir = (Resolve-Path -LiteralPath $OutPath).Path
        Join-Path $dir ("{0}.exe" -f $AssemblyName)
    } else {
        $p = (Resolve-Path -LiteralPath $OutPath).Path
        if ([System.IO.Path]::GetExtension($p) -ne '.exe') { $p += '.exe' }
        $p
    }

    # Decide whether to build
    $needBuild = $true
    if (Test-Path -LiteralPath $expectedExe -PathType Leaf) {
        try {
            if (-not [string]::IsNullOrWhiteSpace($ThisVersion)) {
                $existingVer = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($expectedExe).FileVersion
                if ($existingVer -eq $ThisVersion) { $needBuild = $false }
            } else {
                $needBuild = $false
            }
        } catch { $needBuild = $true }
    }

    # Update versions in source (only when building AND a version is provided)
    if ($needBuild -and -not [string]::IsNullOrWhiteSpace($ThisVersion)) {
        if (Get-Command -Name Set-AssemblyVersionAttributes -ErrorAction SilentlyContinue) {
            $null = Set-AssemblyVersionAttributes -Path $SourceDir -Version $ThisVersion -IncludeInformational
        }
    }

    # Always use Invoke-CSharpCompilationEx
    if (-not (Get-Command -Name Invoke-CSharpCompilationEx -ErrorAction SilentlyContinue)) {
        throw "Compiler function 'Invoke-CSharpCompilationEx' not found in the current session."
    }

    if ($needBuild) {
        $result = Invoke-CSharpCompilationEx -Source $SourceDir -OutputType $OutputType -AssemblyName $AssemblyName -OutputPath $OutPath -Configuration $Configuration -PdbType $PdbType -CompilerOptions $CompilerOptions -References $References -SuppressBuildOutput:$SuppressBuildOutput
        $exe = if ($result -and $result.Artifact) { $result.Artifact } else { $null }
        if (-not $exe) { throw "Build did not produce an artifact." }
        return [pscustomobject]@{ Skipped=$false; Reason='Built'; Executable=$exe; Result=$result }
    }

    return [pscustomobject]@{ Skipped=$true; Reason='Existing executable matches requested version'; Executable=(Get-Item -LiteralPath $expectedExe); Result=$null }
}

# Example:
# Invoke-BuildSimple -SourceDir .\source\src -AssemblyName MyApp -ThisVersion 1.2.3.5 -OutPath .\out -Quiet
