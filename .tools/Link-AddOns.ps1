#Requires -Version 5.1
<#
.SYNOPSIS
    Junction-links an EllesmereUI dev checkout into a WoW AddOns folder for
    in-place development.

.DESCRIPTION
    The EllesmereUI repository is laid out as one main addon at the repo root
    (EllesmereUI.toc + lua files) plus several sub-addon folders (each a folder
    containing a matching <name>.toc). This script creates a directory junction
    for each, so edits in the dev checkout are seen live by the game:

        AddOns\EllesmereUI            -> <DevPath>\                (repo root = main addon)
        AddOns\EllesmereUIActionBars  -> <DevPath>\EllesmereUIActionBars
        AddOns\EllesmereUIUnitFrames  -> <DevPath>\EllesmereUIUnitFrames
        ... (one per sub-addon)

    Non-addon folders (Libs, Locales, media, .git, etc.) are NOT linked
    individually - they live inside the main addon, which is linked as a whole.

    Libs are gitignored (pulled by the packager via .pkgmeta externals), so a
    fresh clone is missing them. When -Force replaces a *real* installed addon
    folder, this script first copies any gitignored 'Libs' subfolder out of the
    install and into the matching dev folder (if the dev folder lacks it), so the
    addon keeps working after the swap. This is skipped when the existing entry
    is already a junction (the dev tree is then the source of truth).

.PARAMETER AddOnsPath
    The WoW AddOns folder where junctions are created, e.g.
    "F:\games\World of Warcraft\_retail_\Interface\AddOns".

.PARAMETER DevPath
    The EllesmereUI dev checkout (repo root), e.g. "F:\dev\EllesmereUI".

.PARAMETER Force
    Replace existing entries in the AddOns folder. An existing junction is
    unlinked; an existing real directory is deleted (after preserving its Libs)
    and replaced. Without -Force, existing entries are skipped.

.PARAMETER PreserveSubdirs
    Subfolder names to lift from a real install into the dev folder before
    deletion. Defaults to 'Libs'.

.EXAMPLE
    .\Link-AddOns.ps1 "F:\games\World of Warcraft\_retail_\Interface\AddOns" "F:\dev\EllesmereUI" -Force -WhatIf

.EXAMPLE
    .\Link-AddOns.ps1 "F:\...\AddOns" "F:\dev\EllesmereUI" -Force

.NOTES
    Junctions need no admin rights but only target local directories.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$AddOnsPath,

    [Parameter(Mandatory, Position = 1)]
    [string]$DevPath,

    [switch]$Force,

    [string[]]$PreserveSubdirs = @('Libs')
)

# --- Resolve & validate -----------------------------------------------------
try {
    $AddOnsPath = (Resolve-Path -LiteralPath $AddOnsPath -ErrorAction Stop).Path
    $DevPath    = (Resolve-Path -LiteralPath $DevPath    -ErrorAction Stop).Path
}
catch {
    throw "Could not resolve a supplied path: $($_.Exception.Message)"
}
if (-not (Test-Path -LiteralPath $AddOnsPath -PathType Container)) {
    throw "AddOns path is not a directory: $AddOnsPath"
}
if (-not (Test-Path -LiteralPath $DevPath -PathType Container)) {
    throw "Dev path is not a directory: $DevPath"
}

# --- Determine the main addon name from the root .toc -----------------------
# (robust to the repo being cloned into a differently-named folder)
$rootToc = Get-ChildItem -LiteralPath $DevPath -Filter '*.toc' -File |
           Select-Object -First 1
if (-not $rootToc) {
    throw "No .toc file found at the repo root ($DevPath); is this an EllesmereUI checkout?"
}
$mainName = [System.IO.Path]::GetFileNameWithoutExtension($rootToc.Name)

# --- Build the list of link operations: @{ Name; Target } -------------------
$links = @()
# 1) Main addon: repo root -> AddOns\<mainName>
$links += [pscustomobject]@{ Name = $mainName; Target = $DevPath }
# 2) Sub-addons: any subfolder containing a matching <name>.toc
Get-ChildItem -LiteralPath $DevPath -Directory | ForEach-Object {
    if (Test-Path -LiteralPath (Join-Path $_.FullName "$($_.Name).toc")) {
        $links += [pscustomobject]@{ Name = $_.Name; Target = $_.FullName }
    }
}

Write-Host "Main addon : $mainName" -ForegroundColor Cyan
Write-Host "Sub-addons : $($links.Count - 1)" -ForegroundColor Cyan
Write-Host ""

$created = 0; $replaced = 0; $skipped = 0

foreach ($l in $links) {
    $target = $l.Target
    $name   = $l.Name
    $link   = Join-Path $AddOnsPath $name

    $existing = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
    if ($existing) {
        if (-not $Force) {
            Write-Warning "Skipping '$name' - already exists (use -Force to replace): $link"
            $skipped++
            continue
        }

        $isReparse = [bool]($existing.Attributes -band [System.IO.FileAttributes]::ReparsePoint)

        if (-not $isReparse) {
            # Preserve gitignored libs from the real install into the dev tree.
            foreach ($sub in $PreserveSubdirs) {
                $srcLib = Join-Path $link   $sub
                $dstLib = Join-Path $target $sub
                if ((Test-Path -LiteralPath $srcLib -PathType Container) -and
                    (-not (Test-Path -LiteralPath $dstLib))) {
                    if ($PSCmdlet.ShouldProcess($dstLib, "Preserve '$sub' from install")) {
                        try {
                            Copy-Item -LiteralPath $srcLib -Destination $dstLib -Recurse -Force -ErrorAction Stop
                            Write-Host "  Preserved: $srcLib  ->  $dstLib" -ForegroundColor DarkYellow
                        }
                        catch {
                            Write-Error "Failed to preserve '$sub' for '$name': $($_.Exception.Message)"
                            continue
                        }
                    }
                }
            }
        }

        $kind = if ($isReparse) { 'link' } else { 'real directory' }
        if ($PSCmdlet.ShouldProcess($link, "Remove existing $kind")) {
            try {
                if ($isReparse) {
                    [System.IO.Directory]::Delete($link, $false)  # unlink only, never recurse into target
                }
                else {
                    Remove-Item -LiteralPath $link -Recurse -Force -ErrorAction Stop
                }
            }
            catch {
                Write-Error "Failed to remove existing '$name': $($_.Exception.Message)"
                continue
            }
        }
        elseif (-not $WhatIfPreference) {
            # User answered No to a -Confirm prompt: skip this item entirely.
            # Under -WhatIf we fall through so the create step is also previewed.
            continue
        }
    }

    if ($PSCmdlet.ShouldProcess($link, "Create junction -> $target")) {
        try {
            New-Item -ItemType Junction -Path $link -Target $target -ErrorAction Stop | Out-Null
            Write-Host "Linked: $link  ->  $target" -ForegroundColor Green
            if ($existing) { $replaced++ } else { $created++ }
        }
        catch {
            Write-Error "Failed to link '$name': $($_.Exception.Message)"
        }
    }
}

Write-Host ""
Write-Host "Done. Created $created, replaced $replaced, skipped $skipped." -ForegroundColor Cyan
