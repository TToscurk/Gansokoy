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
    $godotExecutable = 'D:\Godot\4.4.1\Godot_v4.4.1-stable_win64_console.exe'

    if (-not (Test-Path -LiteralPath $godotExecutable -PathType Leaf)) {
        throw "Godot executable not found: $godotExecutable"
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
