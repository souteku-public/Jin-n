# JPG画像を2MB以下に圧縮するスクリプト
# 使い方: このスクリプトを画像フォルダに置いて実行するか、$sourceFolderを変更してください

param(
    [string]$sourceFolder = ".",       # 画像が入っているフォルダ（デフォルト: スクリプトと同じ場所）
    [string]$outputFolder = "compressed", # 出力先フォルダ名
    [long]$maxSizeBytes = 2MB           # 上限サイズ（デフォルト: 2MB）
)

Add-Type -AssemblyName System.Drawing

$sourcePath = Resolve-Path $sourceFolder
$outputPath = Join-Path $sourcePath $outputFolder

# 出力フォルダを作成
if (-not (Test-Path $outputPath)) {
    New-Item -ItemType Directory -Path $outputPath | Out-Null
}

# JPGファイルを取得
$images = Get-ChildItem -Path $sourcePath -Include "*.jpg","*.jpeg","*.JPG","*.JPEG" -File

if ($images.Count -eq 0) {
    Write-Host "JPG画像が見つかりませんでした。フォルダを確認してください: $sourcePath"
    exit
}

Write-Host "対象画像: $($images.Count) 枚"
Write-Host "出力先: $outputPath"
Write-Host ""

$success = 0
$skipped = 0

foreach ($img in $images) {
    $destPath = Join-Path $outputPath $img.Name

    # すでに2MB以下なら品質90でコピー（ほぼ劣化なし）
    if ($img.Length -le $maxSizeBytes) {
        Copy-Item $img.FullName $destPath
        Write-Host "[スキップ] $($img.Name) - すでに2MB以下 ($([math]::Round($img.Length/1MB,2)) MB)"
        $skipped++
        continue
    }

    # 圧縮品質を段階的に下げて2MB以下を目指す
    $bitmap = $null
    $compressed = $false

    try {
        $bitmap = New-Object System.Drawing.Bitmap($img.FullName)
        $encoder = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" }
        $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)

        foreach ($quality in @(85, 75, 65, 55, 45, 35, 25)) {
            $encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
                [System.Drawing.Imaging.Encoder]::Quality, [long]$quality
            )

            $memStream = New-Object System.IO.MemoryStream
            $bitmap.Save($memStream, $encoder, $encoderParams)
            $size = $memStream.Length

            if ($size -le $maxSizeBytes) {
                $fileStream = [System.IO.File]::OpenWrite($destPath)
                $memStream.WriteTo($fileStream)
                $fileStream.Close()
                $memStream.Close()
                Write-Host "[圧縮] $($img.Name) - $([math]::Round($img.Length/1MB,2)) MB → $([math]::Round($size/1MB,2)) MB (品質: $quality%)"
                $compressed = $true
                $success++
                break
            }
            $memStream.Close()
        }

        if (-not $compressed) {
            # 品質25でも超える場合はリサイズ
            $ratio = [math]::Sqrt($maxSizeBytes / $img.Length) * 0.9
            $newWidth  = [int]($bitmap.Width  * $ratio)
            $newHeight = [int]($bitmap.Height * $ratio)
            $resized = New-Object System.Drawing.Bitmap($bitmap, $newWidth, $newHeight)

            $encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
                [System.Drawing.Imaging.Encoder]::Quality, [long]50
            )
            $resized.Save($destPath, $encoder, $encoderParams)
            $resized.Dispose()

            $finalSize = (Get-Item $destPath).Length
            Write-Host "[リサイズ+圧縮] $($img.Name) - $([math]::Round($img.Length/1MB,2)) MB → $([math]::Round($finalSize/1MB,2)) MB"
            $success++
        }
    }
    catch {
        Write-Host "[エラー] $($img.Name): $($_.Exception.Message)"
    }
    finally {
        if ($bitmap) { $bitmap.Dispose() }
    }
}

Write-Host ""
Write-Host "完了: 圧縮 $success 枚 / スキップ $skipped 枚 / 合計 $($images.Count) 枚"
