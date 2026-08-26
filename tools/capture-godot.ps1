[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Map,

    [Parameter(Mandatory = $true)]
    [string]$Shotlist,

    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'

try {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $projectRoot = Join-Path $repoRoot 'godot'
    # Prefer the executable of the currently running editor so captures use the
    # same Godot version as the project. Fall back to installed D:\Godot* builds
    # for headless/CI use instead of relying on one stale hard-coded path.
    $godotExecutable = Get-Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Path -and $_.ProcessName -match '^Godot(?:_v[0-9]|$)'
        } |
        Sort-Object StartTime |
        Select-Object -First 1 -ExpandProperty Path
    if (-not [string]::IsNullOrWhiteSpace($godotExecutable)) {
        $consoleExecutable = Join-Path (Split-Path -Parent $godotExecutable) (
            [System.IO.Path]::GetFileNameWithoutExtension($godotExecutable) + '_console.exe')
        if (Test-Path -LiteralPath $consoleExecutable -PathType Leaf) {
            $godotExecutable = $consoleExecutable
        }
    }
    if ([string]::IsNullOrWhiteSpace($godotExecutable)) {
        $godotExecutable = Get-ChildItem -Path 'D:\Godot*\Godot*.exe' -File -ErrorAction SilentlyContinue |
            Sort-Object @{ Expression = { $_.Name -match '_console\.exe$' }; Descending = $true },
                @{ Expression = { $_.LastWriteTime }; Descending = $true } |
            Select-Object -First 1 -ExpandProperty FullName
    }
    if ([string]::IsNullOrWhiteSpace($godotExecutable) -or
            -not (Test-Path -LiteralPath $godotExecutable -PathType Leaf)) {
        throw 'Godot executable not found in a running editor or D:\Godot* installation.'
    }

    if ($Shotlist.StartsWith('res://')) {
        $shotlistFile = Join-Path $projectRoot $Shotlist.Substring(6)
        $shotlistArgument = $Shotlist
    }
    else {
        $shotlistFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Shotlist)
        $shotlistArgument = $shotlistFile.Replace('\', '/')
    }

    if (-not (Test-Path -LiteralPath $shotlistFile -PathType Leaf)) {
        throw "Shotlist not found: $shotlistFile"
    }

    $shots = Get-Content -LiteralPath $shotlistFile -Raw | ConvertFrom-Json
    $shotNames = @($shots.name)
    if ($shotNames.Count -eq 0) {
        throw "Shotlist is empty: $shotlistFile"
    }

    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $OutputDirectory = Join-Path ([System.IO.Path]::GetTempPath()) (
            'shrine-capture-' + [Guid]::NewGuid().ToString('N'))
    }
    else {
        $OutputDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
            $OutputDirectory)
    }
    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

    $arguments = @(
        '--rendering-method', 'gl_compatibility',
        '--path', $projectRoot,
        '--',
        "--map=$Map",
        "--shots=$shotlistArgument",
        "--shotdir=$($OutputDirectory.Replace('\', '/'))"
    )

    $process = Start-Process -FilePath $godotExecutable -ArgumentList $arguments -PassThru -Wait
    if ($process.ExitCode -ne 0) {
        throw "Godot exited with code $($process.ExitCode)"
    }

    $pngs = foreach ($shotName in $shotNames) {
        $png = Join-Path $OutputDirectory ("$shotName.png")
        if (-not (Test-Path -LiteralPath $png -PathType Leaf)) {
            throw "Expected PNG was not created: $png"
        }
        $file = Get-Item -LiteralPath $png
        if ($file.Length -le 0) {
            throw "PNG is empty: $png"
        }
        $file
    }

    [PSCustomObject]@{
        Map = $Map
        Shotlist = $shotlistFile
        OutputDirectory = $OutputDirectory
        PngCount = @($pngs).Count
        Pngs = @($pngs).FullName
    }
}
catch {
    [Console]::Error.WriteLine("capture failed: $($_.Exception.Message)")
    exit 1
}
