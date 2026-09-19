[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Source,


    [string]$AssetStem
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptRoot
$BuildRoot = Join-Path $ProjectRoot 'Build'

$ModelRoot = Join-Path $BuildRoot 'vendor\assets\war3mapModel'
$TextureRoot = Join-Path $BuildRoot 'vendor\assets\war3mapTextures'
$ModelDeclaration = Join-Path $BuildRoot 'projects\JiuDou\assets\model.lua'
$ForbiddenResourceRoot = Join-Path $BuildRoot 'projects\JiuDou\w3x\resource'
$AuditRoot = Join-Path $ProjectRoot '.codex_tmp'

function Write-Info([string]$Message) {
    Write-Host "[info] $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "[ ok ] $Message" -ForegroundColor Green
}

function Write-Warn([string]$Message) {
    Write-Host "[warn] $Message" -ForegroundColor Yellow
}

function Fail([string]$Message) {
    throw $Message
}

function Normalize-Slashes([string]$Path) {
    return ($Path -replace '/', '\')
}

function Get-RelativePath([string]$BasePath, [string]$Path) {
    $baseFull = [IO.Path]::GetFullPath($BasePath).TrimEnd('\') + '\'
    $pathFull = [IO.Path]::GetFullPath($Path)
    $baseUri = New-Object Uri($baseFull)
    $pathUri = New-Object Uri($pathFull)
    return (Normalize-Slashes $baseUri.MakeRelativeUri($pathUri).ToString())
}

function Convert-ToAssetStem([string]$Name) {
    $value = $Name -replace '[^\p{L}\p{Nd}_-]+', '_'
    $value = $value -replace '-+', '_'
    $value = $value.Trim('_')
    if ([string]::IsNullOrWhiteSpace($value)) {
        Fail '无法从模型文件名生成资源名，请使用 -AssetStem 指定名称。'
    }
    return $value
}

function Convert-ToAlias([string]$Name) {
    $value = $Name.ToLowerInvariant() -replace '[^a-z0-9]+', '_'
    $value = $value.Trim('_')
    if ([string]::IsNullOrWhiteSpace($value)) {
        $value = 'model'
    }
    if ($value -match '^[0-9]') {
        $value = 'model_' + $value
    }
    return $value
}

function Get-BytesHash([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-FileHashValue([string]$Path) {
    return Get-BytesHash ([IO.File]::ReadAllBytes($Path))
}

function Copy-Checked([string]$SourcePath, [string]$TargetPath) {
    $targetParent = Split-Path -Parent $TargetPath
    if (-not (Test-Path -LiteralPath $targetParent)) {
        New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
    }

    if (Test-Path -LiteralPath $TargetPath) {
        $sourceHash = Get-FileHashValue $SourcePath
        $targetHash = Get-FileHashValue $TargetPath
        if ($sourceHash -ne $targetHash) {
            Fail "目标文件已存在但内容不同，已停止以避免覆盖:`n  $TargetPath"
        }
        Write-Info "复用同哈希文件: $TargetPath"
        return
    }

    Copy-Item -LiteralPath $SourcePath -Destination $TargetPath
    Write-Ok "复制: $TargetPath"
}

function Get-MdxTextureEntries([byte[]]$Bytes) {
    $entries = New-Object System.Collections.Generic.List[object]
    $texs = [byte[]](84, 69, 88, 83)

    for ($i = 0; $i -le ($Bytes.Length - 8); $i++) {
        if ($Bytes[$i] -ne $texs[0] -or $Bytes[$i + 1] -ne $texs[1] -or $Bytes[$i + 2] -ne $texs[2] -or $Bytes[$i + 3] -ne $texs[3]) {
            continue
        }

        $chunkSize = [BitConverter]::ToInt32($Bytes, $i + 4)
        $chunkStart = $i + 8
        if ($chunkSize -lt 268 -or ($chunkSize % 268) -ne 0 -or ($chunkStart + $chunkSize) -gt $Bytes.Length) {
            continue
        }

        for ($offset = 0; $offset -lt $chunkSize; $offset += 268) {
            $pathOffset = $chunkStart + $offset + 4
            $pathBytes = New-Object byte[] 260
            [Array]::Copy($Bytes, $pathOffset, $pathBytes, 0, 260)
            $path = [Text.Encoding]::ASCII.GetString($pathBytes).Split([char]0)[0]
            $entries.Add([pscustomobject]@{
                Path = $path
                PathOffset = $pathOffset
            })
        }

        $i = $chunkStart + $chunkSize - 1
    }

    return $entries
}

function Set-MdxTexturePath([byte[]]$Bytes, [int]$Offset, [string]$Path) {
    $pathBytes = [Text.Encoding]::ASCII.GetBytes($Path)
    if ($pathBytes.Length -ge 260) {
        Fail "MDX 贴图虚拟路径过长（必须小于 260 字节）: $Path"
    }
    [Array]::Clear($Bytes, $Offset, 260)
    [Array]::Copy($pathBytes, 0, $Bytes, $Offset, $pathBytes.Length)
}

function Find-TextureCandidates([string]$TextureName, [object[]]$BlpFiles) {
    return @($BlpFiles | Where-Object { $_.Name -ieq $TextureName })
}

function Get-TextureVirtualPath([string]$SourceRoot, [string]$TextureRootName, [string]$TexturePath) {
    $relative = Get-RelativePath $SourceRoot $TexturePath
    $relative = Normalize-Slashes $relative
    return (Normalize-Slashes (Join-Path 'war3mapTextures' (Join-Path $TextureRootName $relative)))
}

function Patch-MdxTexturePaths([string]$MdxPath, [string]$SourceRoot, [string]$TextureRootName, [object[]]$BlpFiles, [System.Collections.Generic.List[object]]$DependencyReport) {
    $bytes = [IO.File]::ReadAllBytes($MdxPath)
    $beforeHash = Get-BytesHash $bytes
    $entries = @(Get-MdxTextureEntries $bytes)
    $changed = 0

    foreach ($entry in $entries) {
        $reference = [string]$entry.Path
        if ([string]::IsNullOrWhiteSpace($reference)) {
            continue
        }

        $referenceNormalized = Normalize-Slashes $reference
        $textureName = Split-Path -Leaf $referenceNormalized
        $candidates = @(Find-TextureCandidates $textureName $BlpFiles)

        if ($candidates.Count -eq 1) {
            $virtualPath = Get-TextureVirtualPath $SourceRoot $TextureRootName $candidates[0].FullName
            if ($referenceNormalized -cne $virtualPath) {
                Set-MdxTexturePath $bytes $entry.PathOffset $virtualPath
                $changed++
                Write-Info "修正贴图引用: $reference -> $virtualPath"
            }
            $DependencyReport.Add([pscustomobject]@{
                Reference = $reference
                Result = 'patched'
                VirtualPath = $virtualPath
            })
            continue
        }

        if ($candidates.Count -gt 1) {
            Write-Warn "贴图文件名重复，无法自动判断: $reference"
            $DependencyReport.Add([pscustomobject]@{
                Reference = $reference
                Result = 'ambiguous'
                VirtualPath = $null
            })
            continue
        }

        if ($referenceNormalized -match '^Textures\\') {
            $result = 'game_texture_dependency'
        }
        elseif ($referenceNormalized -match '^war3mapTextures\\') {
            $result = 'project_texture_missing_from_source'
        }
        else {
            $result = 'unresolved_dependency'
        }
        Write-Warn "未找到源贴图，保留原引用: $reference"
        $DependencyReport.Add([pscustomobject]@{
            Reference = $reference
            Result = $result
            VirtualPath = $null
        })
    }

    if ($changed -gt 0) {
        [IO.File]::WriteAllBytes($MdxPath, $bytes)
        Write-Ok "已修正 $changed 条 MDX 贴图引用（文件大小保持不变）"
    }

    $afterBytes = [IO.File]::ReadAllBytes($MdxPath)
    if ($afterBytes.Length -ne $bytes.Length) {
        Fail "MDX 修改后文件大小异常: $MdxPath"
    }

    return [pscustomobject]@{
        BeforeHash = $beforeHash
        AfterHash = Get-BytesHash $afterBytes
        EntryCount = $entries.Count
        ChangedCount = $changed
    }
}

function Assert-FormalTargets([object[]]$Pairs) {
    foreach ($pair in $Pairs) {
        if (Test-Path -LiteralPath $pair.FormalTarget) {
            $sourceHash = Get-FileHashValue $pair.Source
            $targetHash = Get-FileHashValue $pair.FormalTarget
            if ($sourceHash -ne $targetHash) {
                Fail "正式目录存在同名但内容不同，已停止以避免覆盖:`n  $($pair.FormalTarget)"
            }
        }
    }
}

function Update-ModelDeclaration([string]$Path, [string]$AssetPath, [string]$Alias) {
    $text = [IO.File]::ReadAllText($Path)
    $assetLuaPath = $AssetPath.Replace('\', '/')
    $assetPattern = 'assets_model\("' + [Regex]::Escape($assetLuaPath) + '"'
    $aliasPattern = 'assets_model\([^\r\n]*,\s*"' + [Regex]::Escape($Alias) + '"\s*\)'

    if ([Regex]::IsMatch($text, $assetPattern)) {
        Write-Info "model.lua 已存在资源声明: $assetLuaPath"
        return $false
    }
    if ([Regex]::IsMatch($text, $aliasPattern)) {
        Fail "model.lua 中别名已被其他模型占用: $Alias"
    }

    $line = 'assets_model("' + $assetLuaPath + '", "' + $Alias + '")'
    if (-not $text.EndsWith("`n")) {
        $text += "`r`n"
    }
    $text += $line + "`r`n"
    [IO.File]::WriteAllText($Path, $text, [Text.UTF8Encoding]::new($false))
    Write-Ok "已登记模型别名: $line"
    return $true
}

try {
    if (-not (Test-Path -LiteralPath $BuildRoot -PathType Container)) {
        Fail "未找到 Build 目录: $BuildRoot"
    }


    $sourceItem = Get-Item -LiteralPath $Source
    if (-not $sourceItem.PSIsContainer) {
        Fail "参数必须是模型文件夹，而不是文件: $Source"
    }
    $sourceRoot = $sourceItem.FullName.TrimEnd('\')
    $forbiddenFull = [IO.Path]::GetFullPath($ForbiddenResourceRoot).TrimEnd('\')
    $sourceFull = [IO.Path]::GetFullPath($sourceRoot)
    if ($sourceFull.Equals($forbiddenFull, [StringComparison]::OrdinalIgnoreCase) -or $sourceFull.StartsWith($forbiddenFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
        Fail "禁止把 Build/projects/JiuDou/w3x/resource 作为模型源目录。请把模型放在独立文件夹后再导入。"
    }

    $mdxFiles = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File | Where-Object { $_.Extension -ieq '.mdx' })
    $blpFiles = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File | Where-Object { $_.Extension -ieq '.blp' })
    if ($mdxFiles.Count -eq 0) {
        Fail "模型文件夹内没有找到 .mdx 文件: $sourceRoot"
    }
    if ($mdxFiles.Count -gt 1) {
        Fail "一个模型文件夹只能包含一个 .mdx；当前找到 $($mdxFiles.Count) 个。请按模型分别执行 BAT。"
    }

    $mdx = $mdxFiles[0]
    if ([string]::IsNullOrWhiteSpace($AssetStem)) {
        $assetStem = Convert-ToAssetStem $mdx.BaseName
    }
    else {
        $assetStem = Convert-ToAssetStem $AssetStem
    }
    $alias = Convert-ToAlias $assetStem
    $assetPath = 'effect/' + $assetStem
    $modelRelative = Join-Path 'effect' ($assetStem + '.mdx')
    $textureRelativeRoot = Join-Path 'effect' $assetStem

    New-Item -ItemType Directory -Path $AuditRoot -Force | Out-Null
    $runId = (Get-Date).ToString('yyyyMMdd-HHmmss-fff') + '-' + $alias
    $runRoot = Join-Path $AuditRoot ('war3-model-import-' + $runId)
    New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

    $statusBefore = @(& git -C $ProjectRoot status --short 2>&1)
    [IO.File]::WriteAllLines((Join-Path $runRoot 'git-status-before.txt'), $statusBefore)

    Write-Info "源目录: $sourceRoot"
    Write-Info "模型: $($mdx.Name)"
    Write-Info "资源路径: $assetPath"
    Write-Info "别名: $alias"
    Write-Info "正式模型目录: $ModelRoot"
    Write-Info "正式贴图目录: $TextureRoot"

    $workingMdx = Join-Path $runRoot ($assetStem + '.mdx')
    Copy-Item -LiteralPath $mdx.FullName -Destination $workingMdx
    $dependencies = New-Object System.Collections.Generic.List[object]
    $patchResult = Patch-MdxTexturePaths $workingMdx $sourceRoot $textureRelativeRoot $blpFiles $dependencies

    $modelFormalPath = Join-Path $ModelRoot $modelRelative
    $assetFiles = New-Object System.Collections.Generic.List[object]
    $assetFiles.Add([pscustomobject]@{
        Source = $workingMdx
        FormalTarget = $modelFormalPath
        Type = 'mdx'
        Relative = $modelRelative
    })

    foreach ($blp in $blpFiles) {
        $relative = Get-RelativePath $sourceRoot $blp.FullName
        $formalRelative = Join-Path $textureRelativeRoot $relative
        $assetFiles.Add([pscustomobject]@{
            Source = $blp.FullName
            FormalTarget = (Join-Path $TextureRoot $formalRelative)
            Type = 'blp'
            Relative = $formalRelative
        })
    }

    Write-Info "发现 $($blpFiles.Count) 个 BLP 贴图。"
    if ($dependencies.Count -eq 0) {
        Write-Info 'MDX 未发现可解析的 TEXS 贴图引用。'
    }

    $modelLuaBackup = Join-Path $runRoot 'model.lua.before'
    Copy-Item -LiteralPath $ModelDeclaration -Destination $modelLuaBackup
    Assert-FormalTargets $assetFiles
    foreach ($assetFile in $assetFiles) {
        Copy-Checked $assetFile.Source $assetFile.FormalTarget
    }
    $declarationChanged = Update-ModelDeclaration $ModelDeclaration $assetPath $alias
    $formalImported = $true
    Write-Ok '模型与贴图已直接导入正式目录。'

    $dependencyArray = @()
    foreach ($dependency in $dependencies) {
        $dependencyArray += $dependency
    }
    $fileReports = @()
    foreach ($assetFile in $assetFiles) {
        $fileReports += [pscustomobject]@{
            Type = $assetFile.Type
            Relative = (Normalize-Slashes $assetFile.Relative)
            SourceHash = Get-FileHashValue $assetFile.Source
            TargetHash = Get-FileHashValue $assetFile.FormalTarget
            FormalTarget = (Normalize-Slashes $assetFile.FormalTarget)
        }
    }
    $report = [pscustomobject]@{
        Source = $sourceRoot
        Model = $mdx.FullName
        AssetPath = $assetPath
        Alias = $alias
        ModelRelative = (Normalize-Slashes $modelRelative)
        TextureCount = $blpFiles.Count
        Patch = $patchResult
        Dependencies = $dependencyArray
        FormalImported = $formalImported
        ModelDeclarationChanged = $declarationChanged
        Files = $fileReports
    }
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runRoot 'report.json') -Encoding UTF8

    Write-Host "完成: 已正式导入 $assetPath" -ForegroundColor Green
    Write-Host "审计报告: $runRoot\report.json" -ForegroundColor DarkGray
    exit 0
}
catch {
    Write-Host "[error] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
