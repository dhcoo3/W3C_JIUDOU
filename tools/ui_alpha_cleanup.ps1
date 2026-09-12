<#
.SYNOPSIS
将 AI 生成的假棋盘格背景清理为真实 PNG Alpha。

.DESCRIPTION
仅用于源 PNG 已被模型错误填入灰白棋盘格时。脚本先移除高亮、低饱和的中性格子，
再可选地清空英雄选中态叠层的内容窗口。它不会处理本来就具备真实 Alpha 的资源。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath,

    [switch]$HeroCardOverlay,

    [ValidateRange(0, 255)]
    [int]$NeutralTolerance = 24,

    [ValidateRange(0, 255)]
    [int]$NeutralBrightness = 110
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

if (-not ('JiuDou.UiAlphaCleanup' -as [type])) {
    $drawingDirectory = Split-Path -Parent ([System.Drawing.Bitmap].Assembly.Location)
    $drawingReferences = @(
        (Join-Path $drawingDirectory 'System.Drawing.Common.dll'),
        (Join-Path $drawingDirectory 'System.Drawing.Primitives.dll'),
        (Join-Path $drawingDirectory 'System.Private.Windows.GdiPlus.dll'),
        (Join-Path $drawingDirectory 'System.Private.Windows.Core.dll')
    )
    Add-Type -ReferencedAssemblies $drawingReferences -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace JiuDou {
    public static class UiAlphaCleanup {
        private static bool IsHeroCardContentWindow(int x, int y, int width, int height) {
            bool portrait = x >= (int)(width * 0.20) && x <= (int)(width * 0.80)
                && y >= (int)(height * 0.13) && y <= (int)(height * 0.54);
            bool stats = x >= (int)(width * 0.18) && x <= (int)(width * 0.82)
                && y >= (int)(height * 0.68) && y <= (int)(height * 0.89);
            bool skill = false;
            if (y >= (int)(height * 0.565) && y <= (int)(height * 0.645)) {
                double[,] ranges = {{0.20, 0.30}, {0.355, 0.465}, {0.535, 0.645}, {0.700, 0.810}};
                for (int i = 0; i < ranges.GetLength(0); i++) {
                    if (x >= (int)(width * ranges[i, 0]) && x <= (int)(width * ranges[i, 1])) {
                        skill = true;
                        break;
                    }
                }
            }
            return portrait || stats || skill;
        }

        public static int Clean(string inputPath, string outputPath, bool heroCardOverlay, int tolerance, int brightness) {
            using (var source = new Bitmap(inputPath))
            using (var output = new Bitmap(source.Width, source.Height, PixelFormat.Format32bppArgb)) {
                using (var graphics = Graphics.FromImage(output)) {
                    graphics.Clear(Color.Transparent);
                    graphics.CompositingMode = CompositingMode.SourceCopy;
                    graphics.DrawImage(source, new Rectangle(0, 0, output.Width, output.Height));
                }

                var rectangle = new Rectangle(0, 0, output.Width, output.Height);
                var bitmapData = output.LockBits(rectangle, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
                try {
                    int byteCount = Math.Abs(bitmapData.Stride) * output.Height;
                    byte[] pixels = new byte[byteCount];
                    Marshal.Copy(bitmapData.Scan0, pixels, 0, byteCount);
                    int removed = 0;
                    for (int y = 0; y < output.Height; y++) {
                        for (int x = 0; x < output.Width; x++) {
                            int offset = y * bitmapData.Stride + x * 4;
                            int blue = pixels[offset];
                            int green = pixels[offset + 1];
                            int red = pixels[offset + 2];
                            int maximum = Math.Max(red, Math.Max(green, blue));
                            int minimum = Math.Min(red, Math.Min(green, blue));
                            bool neutralChecker = maximum >= brightness && maximum - minimum <= tolerance;
                            bool clearContent = heroCardOverlay && IsHeroCardContentWindow(x, y, output.Width, output.Height);
                            if (neutralChecker || clearContent) {
                                pixels[offset + 3] = 0;
                                removed++;
                            }
                        }
                    }
                    Marshal.Copy(pixels, 0, bitmapData.Scan0, byteCount);
                    output.Save(outputPath, ImageFormat.Png);
                    return removed;
                }
                finally {
                    output.UnlockBits(bitmapData);
                }
            }
        }
    }
}
'@
}

if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    throw "找不到 PNG 源图：$InputPath"
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$resolvedInput = (Resolve-Path -LiteralPath $InputPath).Path
$removedPixels = [JiuDou.UiAlphaCleanup]::Clean(
    $resolvedInput,
    $OutputPath,
    [bool]$HeroCardOverlay,
    $NeutralTolerance,
    $NeutralBrightness
)

Write-Output ("已清理假棋盘格：{0}（移除 {1} 个像素，输出 {2}）" -f $InputPath, $removedPixels, $OutputPath)
