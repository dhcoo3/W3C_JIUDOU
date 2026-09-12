<#!
.SYNOPSIS
将 PNG 源图导出为 Warcraft III 1.27 DzFrame 可用、保留 Alpha 通道的调色板 BLP1 贴图。

.DESCRIPTION
输出结构与 Warcraft III BLP1 直接色内容保持一致：256 色调色板、每像素 8 位
Alpha、完整 mipmap 链、1180 字节头部和调色板区域。PNG 的真实透明像素会作为
Alpha 数据写入每一级 mipmap，不能以不透明深色或棋盘格代替。

此脚本暂时采用固定 3-3-2 调色板，换取稳定且无需外部 Python 依赖的 BLP1 导出。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 4096)]
    [int]$Width,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 4096)]
    [int]$Height
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

function New-ScaledBitmap {
    param(
        [Parameter(Mandatory = $true)]
        [System.Drawing.Image]$Source,

        [Parameter(Mandatory = $true)]
        [int]$TargetWidth,

        [Parameter(Mandatory = $true)]
        [int]$TargetHeight
    )

    $bitmap = [System.Drawing.Bitmap]::new(
        $TargetWidth,
        $TargetHeight,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $targetRectangle = [System.Drawing.Rectangle]::new(0, 0, $TargetWidth, $TargetHeight)
        $graphics.DrawImage(
            $Source,
            $targetRectangle,
            0,
            0,
            $Source.Width,
            $Source.Height,
            [System.Drawing.GraphicsUnit]::Pixel
        )
    }
    finally {
        $graphics.Dispose()
    }
    return $bitmap
}

function Convert-BitmapToBlpPixels {
    param(
        [Parameter(Mandatory = $true)]
        [System.Drawing.Bitmap]$Bitmap
    )

    $colorIndices = [byte[]]::new($Bitmap.Width * $Bitmap.Height)
    $alphaValues = [byte[]]::new($Bitmap.Width * $Bitmap.Height)
    $pixelIndex = 0
    for ($y = 0; $y -lt $Bitmap.Height; $y++) {
        for ($x = 0; $x -lt $Bitmap.Width; $x++) {
            $color = $Bitmap.GetPixel($x, $y)
            $red = ([int]$color.R) -shr 5
            $green = ([int]$color.G) -shr 5
            $blue = ([int]$color.B) -shr 6
            $colorIndices[$pixelIndex] = [byte](($red -shl 5) -bor ($green -shl 2) -bor $blue)
            $alphaValues[$pixelIndex] = $color.A
            $pixelIndex++
        }
    }
    return [PSCustomObject]@{
        ColorIndices = $colorIndices
        AlphaValues = $alphaValues
    }
}

if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    throw "找不到 PNG 源图：$InputPath"
}

$resolvedInput = (Resolve-Path -LiteralPath $InputPath).Path
$outputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$source = [System.Drawing.Image]::FromFile($resolvedInput)
$mipmaps = [System.Collections.Generic.List[object]]::new()
$mipmapOffsets = [System.Collections.Generic.List[uint32]]::new()
$mipmapSizes = [System.Collections.Generic.List[uint32]]::new()

try {
    $mipWidth = $Width
    $mipHeight = $Height
    while ($true) {
        $mipBitmap = New-ScaledBitmap -Source $source -TargetWidth $mipWidth -TargetHeight $mipHeight
        try {
            $mipmaps.Add((Convert-BitmapToBlpPixels -Bitmap $mipBitmap))
        }
        finally {
            $mipBitmap.Dispose()
        }

        if ($mipWidth -eq 1 -and $mipHeight -eq 1) {
            break
        }
        if ($mipmaps.Count -ge 16) {
            throw 'BLP1 最多支持 16 级 mipmap。'
        }
        $mipWidth = [Math]::Max(1, [int]($mipWidth / 2))
        $mipHeight = [Math]::Max(1, [int]($mipHeight / 2))
    }
}
finally {
    $source.Dispose()
}

$stream = [System.IO.File]::Open($OutputPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::ReadWrite)
$writer = [System.IO.BinaryWriter]::new($stream)
try {
    # 28 字节固定头：BLP1、直接调色板内容、8 位 Alpha、尺寸、extra=5、完整 mipmap。
    $writer.Write([System.Text.Encoding]::ASCII.GetBytes('BLP1'))
    $writer.Write([uint32]1)
    $writer.Write([uint32]8)
    $writer.Write([uint32]$Width)
    $writer.Write([uint32]$Height)
    $writer.Write([uint32]5)
    $writer.Write([uint32]1)

    # 16 个 offset 和 16 个 size，占用 128 字节；先以 0 占位。
    for ($index = 0; $index -lt 32; $index++) {
        $writer.Write([uint32]0)
    }

    # 固定 3-3-2 BGRA 调色板，0～255 索引与 Convert-BitmapToPaletteIndices 保持一致。
    for ($red = 0; $red -lt 8; $red++) {
        for ($green = 0; $green -lt 8; $green++) {
            for ($blue = 0; $blue -lt 4; $blue++) {
                $writer.Write([byte]($blue * 85))
                $writer.Write([byte][Math]::Round($green * 255 / 7))
                $writer.Write([byte][Math]::Round($red * 255 / 7))
                $writer.Write([byte]255)
            }
        }
    }

    foreach ($mipmap in $mipmaps) {
        $mipmapOffsets.Add([uint32]$stream.Position)
        $mipmapSizes.Add([uint32]($mipmap.ColorIndices.Length + $mipmap.AlphaValues.Length))
        $writer.Write($mipmap.ColorIndices)
        $writer.Write($mipmap.AlphaValues)
    }

    # 回填 locator 表；第一个 mipmap 从 1180 字节标准头部开始。
    $stream.Position = 28
    for ($index = 0; $index -lt 16; $index++) {
        if ($index -lt $mipmapOffsets.Count) {
            $writer.Write($mipmapOffsets[$index])
        }
        else {
            $writer.Write([uint32]0)
        }
    }
    for ($index = 0; $index -lt 16; $index++) {
        if ($index -lt $mipmapSizes.Count) {
            $writer.Write($mipmapSizes[$index])
        }
        else {
            $writer.Write([uint32]0)
        }
    }
}
finally {
    $writer.Dispose()
    $stream.Dispose()
}

Write-Output ("已导出 BLP1：{0}（{1}×{2}，{3} 级 mipmap，保留 8 位 Alpha）" -f $OutputPath, $Width, $Height, $mipmaps.Count)
