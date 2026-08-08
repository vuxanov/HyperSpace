# Requires ffmpeg in PATH
param(
    [Parameter(Mandatory = $true)]
    [string]$InputGif,
    [string]$OutputWebm = ""
)

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Error "ffmpeg not found in PATH. Install from https://ffmpeg.org/"
    exit 1
}

if ($OutputWebm -eq "") {
    $OutputWebm = [System.IO.Path]::ChangeExtension($InputGif, ".webm")
}

ffmpeg -i $InputGif -c:v libvpx-vp9 -pix_fmt yuva420p -auto-alt-ref 0 $OutputWebm
Write-Host "Converted: $OutputWebm"
Write-Host "Reference this .webm file in show.json as a video item."
