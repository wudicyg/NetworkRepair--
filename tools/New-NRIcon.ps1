#requires -Version 5.1
<#
.SYNOPSIS
    生成 NetMedic 应用图标（多尺寸 ICO）。

.DESCRIPTION
    用 System.Drawing 绘制图标并手写 ICO 容器。ICO 里使用传统的 DIB（BMP）条目而不是
    PNG 条目，因为 csc.exe（ps2exe 编译 exe 时使用）对 PNG 压缩条目的兼容性没有保证。

    尺寸包含 16 / 32 / 48 / 64 / 128 / 256，全部带 alpha 通道。可用 -PreviewPath 额外输出
    一张放大的 PNG 预览，便于人工确认图标实际长什么样。

.EXAMPLE
    .\tools\New-NRIcon.ps1 -Path .\assets\NetMedic.ico -PreviewPath .\icon-preview.png
#>
[CmdletBinding()]
param(
    [string]$Path = (Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\NetMedic.ico'),
    [int[]]$Sizes = @(16, 32, 48, 64, 128, 256),
    [int]$PngCompressionFromSize = 64,
    [string]$PreviewPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Initialize-NRIconDrawing {
    # 只加载 .NET Framework 自带的 System.Drawing；System.Drawing.Common 是 .NET Core 的程序集，
    # 在 Windows PowerShell 5.1 上不存在，加了会让脚本直接失败。
    Add-Type -AssemblyName System.Drawing
}

function New-NRIconBitmap {
    param([Parameter(Mandatory)][int]$Size)

    $bitmap = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.Clear([System.Drawing.Color]::Transparent)

        $scale = [double]$Size / 64.0
        $board = New-Object System.Drawing.RectangleF(0, 0, $Size, $Size)
        $radius = [float](14 * $scale)

        # 圆角底板 + 蓝色渐变
        $boardPath = New-Object System.Drawing.Drawing2D.GraphicsPath
        $d = $radius * 2
        $boardPath.AddArc(0, 0, $d, $d, 180, 90)
        $boardPath.AddArc($Size - $d, 0, $d, $d, 270, 90)
        $boardPath.AddArc($Size - $d, $Size - $d, $d, $d, 0, 90)
        $boardPath.AddArc(0, $Size - $d, $d, $d, 90, 90)
        $boardPath.CloseFigure()

        $topColor = [System.Drawing.Color]::FromArgb(255, 32, 140, 206)
        $bottomColor = [System.Drawing.Color]::FromArgb(255, 9, 74, 128)
        $gradient = New-Object System.Drawing.Drawing2D.LinearGradientBrush($board, $topColor, $bottomColor, 90.0)
        try { $graphics.FillPath($gradient, $boardPath) } finally { $gradient.Dispose() }
        $boardPath.Dispose()

        # 网络拓扑：三个节点两两相连，构成清晰可辨的三角形
        $white = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
        $lineColor = [System.Drawing.Color]::FromArgb(225, 255, 255, 255)
        $nodeRadius = [float](5.4 * $scale)
        $nodes = @(
            @{ X = 27.0; Y = 13.0 }
            @{ X = 11.0; Y = 40.0 }
            @{ X = 43.0; Y = 40.0 }
        )

        $pen = New-Object System.Drawing.Pen($lineColor, [float](3.2 * $scale))
        $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $brush = New-Object System.Drawing.SolidBrush($white)
        try {
            for ($i = 0; $i -lt $nodes.Count; $i++) {
                $a = $nodes[$i]
                $b = $nodes[($i + 1) % $nodes.Count]
                $graphics.DrawLine($pen, [float]($a.X * $scale), [float]($a.Y * $scale), [float]($b.X * $scale), [float]($b.Y * $scale))
            }
            foreach ($node in $nodes) {
                $nx = [float]($node.X * $scale)
                $ny = [float]($node.Y * $scale)
                $graphics.FillEllipse($brush, ($nx - $nodeRadius), ($ny - $nodeRadius), ($nodeRadius * 2), ($nodeRadius * 2))
            }
        } finally {
            $pen.Dispose()
            $brush.Dispose()
        }

        # 右下角绿色对勾，表达"修复完成"；位置避开拓扑图形
        $checkPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 104, 224, 138), [float](5.2 * $scale))
        $checkPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $checkPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        try {
            $p1 = New-Object System.Drawing.PointF([float](40 * $scale), [float](47 * $scale))
            $p2 = New-Object System.Drawing.PointF([float](46 * $scale), [float](54 * $scale))
            $p3 = New-Object System.Drawing.PointF([float](60 * $scale), [float](35 * $scale))
            $graphics.DrawLines($checkPen, @($p1, $p2, $p3))
        } finally {
            $checkPen.Dispose()
        }
    } finally {
        $graphics.Dispose()
    }

    $bitmap
}

function ConvertTo-NRIconDib {
    <#
        把 32bpp 位图转成 ICO 条目使用的 DIB：BITMAPINFOHEADER + 自下而上的 BGRA 像素 + AND 掩码。
        AND 掩码在 32bpp 下仍需存在（全部置 0，表示完全由 alpha 决定）。
    #>
    param([Parameter(Mandatory)][System.Drawing.Bitmap]$Bitmap)

    $width = $Bitmap.Width
    $height = $Bitmap.Height
    $stride = $width * 4
    $maskStride = [int](([math]::Floor(($width + 31) / 32)) * 4)

    $pixels = New-Object byte[] ($stride * $height)
    $rect = New-Object System.Drawing.Rectangle(0, 0, $width, $height)
    $data = $Bitmap.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        for ($y = 0; $y -lt $height; $y++) {
            $sourceOffset = $data.Stride * $y
            $targetOffset = $stride * ($height - 1 - $y)
            [Runtime.InteropServices.Marshal]::Copy([IntPtr]::Add($data.Scan0, $sourceOffset), $pixels, $targetOffset, $stride)
        }
    } finally {
        $Bitmap.UnlockBits($data)
    }

    $stream = New-Object System.IO.MemoryStream
    $writer = New-Object System.IO.BinaryWriter($stream)
    try {
        $writer.Write([uint32]40)                       # biSize
        $writer.Write([int32]$width)                    # biWidth
        $writer.Write([int32]($height * 2))             # biHeight（XOR + AND）
        $writer.Write([uint16]1)                        # biPlanes
        $writer.Write([uint16]32)                       # biBitCount
        $writer.Write([uint32]0)                        # biCompression
        $writer.Write([uint32]($stride * $height))      # biSizeImage
        $writer.Write([int32]0); $writer.Write([int32]0)
        $writer.Write([uint32]0); $writer.Write([uint32]0)
        $writer.Write($pixels)
        $writer.Write((New-Object byte[] ($maskStride * $height)))
        $writer.Flush()
        # 必须 -NoEnumerate：否则 PowerShell 会把 byte[] 摊平成 Object[]，写出来的 ICO 只有目录没有图像数据。
        Write-Output -NoEnumerate $stream.ToArray()
    } finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

Initialize-NRIconDrawing

if (-not (Test-Path -LiteralPath (Split-Path -Parent $Path))) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
}

$images = @()
foreach ($size in ($Sizes | Sort-Object)) {
    $bitmap = New-NRIconBitmap -Size $size
    try {
        if ($PngCompressionFromSize -gt 0 -and $size -ge $PngCompressionFromSize) {
            # 大尺寸用 PNG 条目：体积显著更小（Vista 及以上都支持）。小尺寸保留传统 DIB 条目。
            $buffer = New-Object System.IO.MemoryStream
            try {
                $bitmap.Save($buffer, [System.Drawing.Imaging.ImageFormat]::Png)
                $images += [pscustomobject]@{
                    Size = $size
                    Data = [byte[]]$buffer.ToArray()
                    Format = 'PNG'
                }
            } finally {
                $buffer.Dispose()
            }
        } else {
            $images += [pscustomobject]@{
                Size = $size
                Data = [byte[]](ConvertTo-NRIconDib -Bitmap $bitmap)
                Format = 'DIB'
            }
        }
    } finally {
        $bitmap.Dispose()
    }
}

# ICONDIR + ICONDIRENTRY 列表 + 图像数据
$stream = New-Object System.IO.MemoryStream
$writer = New-Object System.IO.BinaryWriter($stream)
try {
    $writer.Write([uint16]0)                  # reserved
    $writer.Write([uint16]1)                  # type = icon
    $writer.Write([uint16]$images.Count)

    $offset = 6 + (16 * $images.Count)
    foreach ($image in $images) {
        $dimension = $image.Size
        if ($dimension -ge 256) { $dimension = 0 }   # 256 在 ICO 目录里写 0
        $writer.Write([byte]$dimension)              # width
        $writer.Write([byte]$dimension)              # height
        $writer.Write([byte]0)                       # 调色板颜色数
        $writer.Write([byte]0)                       # reserved
        $writer.Write([uint16]1)                     # planes
        $writer.Write([uint16]32)                    # bitCount
        $writer.Write([uint32]$image.Data.Length)    # bytesInRes
        $writer.Write([uint32]$offset)               # imageOffset
        $offset += $image.Data.Length
    }
    foreach ($image in $images) { $writer.Write($image.Data) }
    $writer.Flush()
    [IO.File]::WriteAllBytes($Path, $stream.ToArray())
} finally {
    $writer.Dispose()
    $stream.Dispose()
}

# 回读校验：能解析出来才算写对
$icon = New-Object System.Drawing.Icon($Path)
$iconSize = '{0}x{1}' -f $icon.Width, $icon.Height
$icon.Dispose()

if ($PreviewPath) {
    $preview = New-NRIconBitmap -Size 256
    try {
        if (-not (Test-Path -LiteralPath (Split-Path -Parent $PreviewPath))) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $PreviewPath) -Force | Out-Null
        }
        $preview.Save($PreviewPath, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $preview.Dispose()
    }
}

[pscustomobject]@{
    Success      = $true
    Path         = (Resolve-Path -LiteralPath $Path).Path
    Bytes        = (Get-Item -LiteralPath $Path).Length
    Sizes        = @($images | ForEach-Object { $_.Size })
    ParsedSize   = $iconSize
    PreviewPath  = $PreviewPath
} | ConvertTo-Json -Depth 5
