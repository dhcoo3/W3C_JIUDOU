param(
    [Parameter()]
    [string]$Root,
    [Parameter()]
    [string]$ExcelRoot,
    [Parameter()]
    [string]$LuaRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Join-Path $PSScriptRoot 'Build'
}
if ([string]::IsNullOrWhiteSpace($ExcelRoot)) {
    $ExcelRoot = Join-Path $PSScriptRoot 'excelCfg'
}
if ([string]::IsNullOrWhiteSpace($LuaRoot)) {
    $LuaRoot = Join-Path $Root '..\scripts\globals\config'
}

function ConvertTo-InvariantInteger {
    param([Parameter(Mandatory = $true)][string]$Value)

    $integer = 0
    if (-not [int]::TryParse($Value, [System.Globalization.NumberStyles]::Integer, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$integer)) {
        return $null
    }
    return $integer
}

function Split-LniArray {
    param([Parameter(Mandatory = $true)][string]$Value)

    $result = New-Object System.Collections.Generic.List[string]
    $buffer = New-Object System.Text.StringBuilder
    $quoted = $false

    for ($index = 0; $index -lt $Value.Length; $index = $index + 1) {
        $character = $Value[$index]
        if ($character -eq '"') {
            $quoted = -not $quoted
            [void]$buffer.Append($character)
        } elseif ($character -eq ',' -and -not $quoted) {
            $result.Add($buffer.ToString().Trim())
            [void]$buffer.Clear()
        } else {
            [void]$buffer.Append($character)
        }
    }

    if ($quoted) {
        throw "数组字符串缺少结束引号：$Value"
    }

    $result.Add($buffer.ToString().Trim())
    return $result.ToArray()
}

. (Join-Path $PSScriptRoot 'excel_config.ps1')

function Read-SimpleObjectTable {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "找不到文本配置源：$Path"
    }

    $sections = [ordered]@{}
    $currentId = $null
    $current = $null
    $lineNumber = 0
    foreach ($rawLine in [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)) {
        $lineNumber = $lineNumber + 1
        $line = $rawLine.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith(';') -or $line.StartsWith('#')) {
            continue
        }
        if ($line -match '^\[([A-Za-z0-9_]+)\]$') {
            $currentId = $Matches[1]
            if ($sections.Contains($currentId)) {
                throw "文本配置区段重复：$Path / $currentId"
            }
            $current = [ordered]@{}
            $sections[$currentId] = $current
            continue
        }
        if ($null -eq $current -or $line -notmatch '^([^=]+?)\s*=\s*(.*?)\s*$') {
            throw "文本配置行格式无效：$Path / 第 $lineNumber 行"
        }
        $field = $Matches[1].Trim()
        $value = $Matches[2].Trim()
        if ($field.Length -eq 0 -or $current.Contains($field)) {
            throw "文本配置字段无效或重复：$Path / $currentId / 第 $lineNumber 行"
        }
        if ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $current[$field] = $value
    }

    if ($sections.Count -eq 0) {
        throw "文本配置不包含数据：$Path"
    }
    return [pscustomobject]@{
        Sections = $sections
    }
}

function Read-RegionsFromJass {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "找不到区域源文件：$Path"
    }

    $regions = [ordered]@{}
    $pattern = '^\s*set\s+gg_rct_([A-Za-z0-9_]+)\s*=\s*Rect\(\s*(-?\s*\d+)(?:\.0+)?\s*,\s*(-?\s*\d+)(?:\.0+)?\s*,\s*(-?\s*\d+)(?:\.0+)?\s*,\s*(-?\s*\d+)(?:\.0+)?\s*\)'
    foreach ($line in [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)) {
        if ($line -notmatch $pattern) {
            continue
        }

        $name = $Matches[1]
        if ($regions.Contains($name)) {
            throw "区域名称重复：$name"
        }
        $minX = ConvertTo-InvariantInteger ($Matches[2] -replace '\s+', '')
        $minY = ConvertTo-InvariantInteger ($Matches[3] -replace '\s+', '')
        $maxX = ConvertTo-InvariantInteger ($Matches[4] -replace '\s+', '')
        $maxY = ConvertTo-InvariantInteger ($Matches[5] -replace '\s+', '')
        if ($null -eq $minX -or $null -eq $minY -or $null -eq $maxX -or $null -eq $maxY) {
            throw "区域坐标必须为整数：$name"
        }
        $regions[$name] = [ordered]@{
            name = $name
            minX = $minX
            minY = $minY
            maxX = $maxX
            maxY = $maxY
        }
    }

    if ($regions.Count -eq 0) {
        throw "未在区域源文件中找到 Rect 声明：$Path"
    }
    return $regions
}

function ConvertTo-LuaString {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    $escaped = $Value.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
    return '"' + $escaped + '"'
}

function ConvertTo-LuaValue {
    param([AllowNull()][object]$Value, [int]$Indent = 0)

    if ($null -eq $Value) { return 'nil' }
    if ($Value -is [string]) { return ConvertTo-LuaString $Value }
    if ($Value -is [bool]) { if ($Value) { return 'true' }; return 'false' }

    if ($Value -is [System.Collections.IDictionary]) {
        $nextIndent = $Indent + 4
        $padding = ' ' * $Indent
        $nextPadding = ' ' * $nextIndent
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add('{')
        foreach ($key in $Value.Keys) {
            $lines.Add($nextPadding + '[' + (ConvertTo-LuaString ([string]$key)) + '] = ' + (ConvertTo-LuaValue $Value[$key] $nextIndent) + ',')
        }
        $lines.Add($padding + '}')
        return [string]::Join("`n", $lines)
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        $nextIndent = $Indent + 4
        $padding = ' ' * $Indent
        $nextPadding = ' ' * $nextIndent
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add('{')
        foreach ($entry in $Value) {
            $lines.Add($nextPadding + (ConvertTo-LuaValue $entry $nextIndent) + ',')
        }
        $lines.Add($padding + '}')
        return [string]::Join("`n", $lines)
    }

    if ($Value -is [System.IFormattable]) {
        if ($Value -is [double] -or $Value -is [float] -or $Value -is [decimal]) {
            $numericValue = [double]$Value
            if ([double]::IsNaN($numericValue) -or [double]::IsInfinity($numericValue)) {
                throw "Lua 配置输出不接受非有限数字：$Value"
            }
            if ($numericValue -eq 0) {
                return '0'
            }
            return $Value.ToString('0.############################', [System.Globalization.CultureInfo]::InvariantCulture)
        }
        return $Value.ToString($null, [System.Globalization.CultureInfo]::InvariantCulture)
    }
    throw "不支持生成 Lua 的值类型：$($Value.GetType().FullName)"
}

function ConvertTo-ObjectConfig {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Sections)

    $result = [ordered]@{}
    foreach ($rawcode in $Sections.Keys) {
        $entry = [ordered]@{ rawcode = $rawcode }
        foreach ($key in $Sections[$rawcode].Keys) {
            $entry[$key] = $Sections[$rawcode][$key]
        }
        $result[$rawcode] = $entry
    }
    return $result
}

function Write-LuaModule {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Annotations,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Data,
        [Parameter(Mandatory = $true)][string]$ConfigKey
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('--- 本文件由 generate_lua_config.ps1 自动生成，请勿手工修改。')
    $lines.Add('--- 数据源来自 excelCfg 配置表；请修改 Excel 后重新执行生成工具。')
    foreach ($annotation in $Annotations) {
        $lines.Add($annotation)
    }
    $lines.Add('JiuDou = JiuDou or {}')
    $lines.Add('JiuDou.config = JiuDou.config or {}')
    $lines.Add('JiuDou.config.' + $ConfigKey + ' = ' + (ConvertTo-LuaValue $Data 0))
    $lines.Add('return JiuDou.config.' + $ConfigKey)
    $lines.Add('')
    [System.IO.File]::WriteAllText($Path, [string]::Join("`n", $lines), [System.Text.UTF8Encoding]::new($false))
}

function Write-SlkModule {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$FunctionName,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Sections,
        [Parameter(Mandatory = $true)][string]$ClassName
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('--- 本文件由 generate_lua_config.ps1 自动生成，请勿手工修改。')
    $lines.Add('--- 数据源来自 excelCfg 配置表；请修改 Excel 后重新执行生成工具。')
    $lines.Add('--- xlik SLK 类别：' + $ClassName)
    $lines.Add('')
    foreach ($rawcode in $Sections.Keys) {
        $entry = [ordered]@{
            _id_force = [string]$rawcode
        }
        foreach ($key in $Sections[$rawcode].Keys) {
            $entry[$key] = $Sections[$rawcode][$key]
        }
        $lines.Add($FunctionName + '(' + (ConvertTo-LuaValue $entry 0) + ')')
        $lines.Add('')
    }
    [System.IO.File]::WriteAllText($Path, [string]::Join([Environment]::NewLine, $lines), [System.Text.UTF8Encoding]::new($false))
}
function Normalize-MigratedAssetPaths {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([System.IO.Path]::GetExtension($Path).ToLowerInvariant() -ne '.lua') {
        return
    }
    $content = [System.IO.File]::ReadAllText($Path)
    $updated = $content.Replace('ui\\selectHero\\skills\\', 'war3mapImage\\selectHero\\skills\\')
    $updated = $updated.Replace('ui/selectHero/skills/', 'war3mapImage/selectHero/skills/')
    if ($updated -ne $content) {
        [System.IO.File]::WriteAllText($Path, $updated, [System.Text.UTF8Encoding]::new($false))
    }
}
function Get-MonsterUnitRawcodes {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Units)

    $rawcodes = New-Object System.Collections.Generic.List[string]
    for ($block = 1; $block -le 9; $block = $block + 1) {
        foreach ($suffix in @('M1', 'R1')) {
            $rawcode = "N$block$suffix"
            if (-not $Units.Contains($rawcode)) {
                throw "刷怪单位缺失：$rawcode"
            }
            $rawcodes.Add($rawcode)
        }
        foreach ($prefix in @('E', 'B')) {
            $rawcode = "$prefix$block" + 'M1'
            if (-not $Units.Contains($rawcode)) {
                throw "刷怪单位缺失：$rawcode"
            }
            $rawcodes.Add($rawcode)
        }
    }
    foreach ($rawcode in @('G0M1', 'X0M1')) {
        if (-not $Units.Contains($rawcode)) {
            throw "刷怪系统缺少特殊怪单位：$rawcode"
        }
        $rawcodes.Add($rawcode)
    }
    return $rawcodes.ToArray()
}

function Get-RequiredUnitInteger {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Unit,
        [Parameter(Mandatory = $true)][string]$Rawcode,
        [Parameter(Mandatory = $true)][string]$Field
    )

    $value = $Unit[$Field]
    if ($value -isnot [System.IConvertible]) {
        throw "刷怪单位属性缺失或不是数字：$Rawcode.$Field"
    }
    $integer = 0
    if (-not [int]::TryParse([string]$value, [System.Globalization.NumberStyles]::Integer, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$integer)) {
        throw "刷怪单位属性必须为整数：$Rawcode.$Field"
    }
    return $integer
}

function Validate-MonsterExperience {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Units)

    $baseRawcodes = @(Get-MonsterUnitRawcodes $Units)
    if ($baseRawcodes.Count -ne 38) { throw "PVE 基础怪物必须恰有 38 种，实际=$($baseRawcodes.Count)" }
    $tierNames = @{
        '一' = 1; '二' = 2; '三' = 3; '四' = 4; '五' = 5
        '六' = 6; '七' = 7; '八' = 8; '九' = 9
    }
    $tierVariantCounts = @{}
    $seen = @{}
    $variantCount = 0
    foreach ($rawcode in $Units.Keys) {
        $unit = $Units[$rawcode]
        if (-not $unit.Contains('baseUnitId')) { continue }
        $base = [string]$unit.baseUnitId
        $mode = Get-RequiredUnitInteger $unit $rawcode 'modeId'
        $level = Get-RequiredUnitInteger $unit $rawcode 'difficultyLevel'
        if ($baseRawcodes -notcontains $base -or $mode -notin @(1, 2) -or $level -lt 1 -or $level -gt 10) {
            throw "怪物变体元数据无效：$rawcode / base=$base / mode=$mode / level=$level"
        }
        if ($base -match '^[NE]') {
            $tier = Get-RequiredUnitInteger $unit $rawcode 'tier'
            $nameMatch = [regex]::Match([string]$unit.Name, '·(?<tier>[一二三四五六七八九])阶$')
            if ($tier -lt 1 -or $tier -gt 9 -or -not $nameMatch.Success -or $tierNames[$nameMatch.Groups['tier'].Value] -ne $tier) {
                throw "怪物阶数必须与名称后缀一致（一阶至九阶）：$rawcode / Name=$($unit.Name) / tier=$tier"
            }
            $tierKey = [string]$tier
            if (-not $tierVariantCounts.ContainsKey($tierKey)) { $tierVariantCounts[$tierKey] = 0 }
            $tierVariantCounts[$tierKey]++
        } elseif ($unit.Contains('tier')) {
            throw "Boss、金币怪和经验怪不应设置军团阶数：$rawcode"
        }
        $key = "$base`:$mode`:$level"
        if ($seen.ContainsKey($key)) { throw "怪物难度组合重复：$key" }
        $seen[$key] = $true
        $variantCount++

        $experience = Get-RequiredUnitInteger $unit $rawcode 'expReward'
        $gold = Get-RequiredUnitInteger $unit $rawcode 'goldRep'
        if ($base -eq 'G0M1') {
            if ($experience -ne 0 -or $gold -le 0) { throw "金币怪经验/金币奖励无效：$rawcode" }
        } elseif ($base -eq 'X0M1') {
            if ($experience -le 0 -or $gold -ne 0) { throw "经验怪经验/金币奖励无效：$rawcode" }
        } elseif ($experience -le 0 -or $gold -le 0) {
            throw "普通、精英和 Boss 变体的经验与金币奖励必须为正整数：$rawcode"
        }

        $chance = Get-RequiredUnitInteger $unit $rawcode 'dropChancePercent'
        if ($chance -lt 0 -or $chance -gt 100) { throw "装备掉落概率必须在 0~100：$rawcode" }
        if ($chance -gt 0) {
            $dropMin = Get-RequiredUnitInteger $unit $rawcode 'dropLevelMin'
            $dropMax = Get-RequiredUnitInteger $unit $rawcode 'dropLevelMax'
            $maxDrops = Get-RequiredUnitInteger $unit $rawcode 'maxDrops'
            $pool = [string]$unit.poolId
            if ([string]::IsNullOrWhiteSpace($pool) -or $dropMin -lt 1 -or $dropMax -lt $dropMin -or $dropMax -gt 5 -or $maxDrops -lt 1) {
                throw "怪物装备掉落配置无效：$rawcode"
            }
        }
    }
    if ($variantCount -ne 760 -or $seen.Count -ne 760) {
        throw "怪物变体必须恰有 38×2×10=760 行，实际=$variantCount"
    }
    for ($tier = 1; $tier -le 9; $tier = $tier + 1) {
        if ($tierVariantCounts[[string]$tier] -ne 60) {
            throw "每阶必须恰有 60 个普通怪/精英难度变体：阶数=$tier / 实际=$($tierVariantCounts[[string]$tier])"
        }
    }
    # 六个未扩展表格单位、两名召唤物和后羿的施法/视觉箭马甲与 PVE 变体并存。
    if ($Units.Count -ne 771 -or ($Units.Count - $variantCount) -ne 11 -or
        -not $Units.Contains('u0W1') -or -not $Units.Contains('u0E1') -or
        -not $Units.Contains('u0H1') -or -not $Units.Contains('u0H2') -or
        -not $Units.Contains('T0D0')) {
        throw "单位表应包含 760 个 PVE 变体、6 个未扩展表格单位、u0W1/u0E1 召唤物和 u0H1/u0H2 后羿马甲，实际单位数=$($Units.Count)"
    }
    foreach ($base in $baseRawcodes) {
        for ($mode = 1; $mode -le 2; $mode++) {
            for ($level = 1; $level -le 10; $level++) {
                if (-not $seen.ContainsKey("$base`:$mode`:$level")) { throw "怪物变体缺失：$base / mode=$mode / level=$level" }
            }
        }
    }
}

function New-GoldConfig {
    param([Parameter(Mandatory = $true)][object]$SettingsTable)

    $settings = [ordered]@{}
    foreach ($settingId in @('initialGold', 'maxGoldDropBonusPercent', 'maxGold')) {
        if (-not $SettingsTable.Sections.Contains($settingId)) {
            throw "金币配置缺少设置：gold.xlsx/settings/$settingId"
        }
        $row = $SettingsTable.Sections[$settingId]
        if (-not $row.Contains('value')) {
            throw "金币设置缺少 value：gold.xlsx/settings/$settingId"
        }
        $value = [int]$row.value
        if ($value -lt 0) {
            throw "金币设置必须为非负整数：gold.xlsx/settings/$settingId"
        }
        $settings[$settingId] = $value
    }
    if ($settings.maxGold -lt $settings.initialGold) {
        throw "金币上限不能低于初始金币：gold.xlsx/settings"
    }

    return [ordered]@{ settings = $settings }
}

function New-ExperienceConfig {
    param(
        [Parameter(Mandatory = $true)][object]$SettingsTable,
        [Parameter(Mandatory = $true)][object]$LevelTable
    )

    if ($SettingsTable.Sections.Count -ne 1 -or -not $SettingsTable.Sections.Contains('DEFAULT')) {
        throw 'experience.xlsx/settings 必须恰有一行 settingId=DEFAULT'
    }
    $settingsSource = $SettingsTable.Sections['DEFAULT']
    foreach ($field in @('maxLevel', 'initialExpBonusPercent', 'maxExpBonusPercent')) {
        if (-not $settingsSource.Contains($field)) {
            throw "经验配置缺少字段：experience.xlsx/settings/DEFAULT/$field"
        }
    }
    $settings = [ordered]@{
        maxLevel = [int]$settingsSource.maxLevel
        initialExpBonusPercent = [int]$settingsSource.initialExpBonusPercent
        maxExpBonusPercent = [int]$settingsSource.maxExpBonusPercent
    }
    if (($settings.maxLevel -ne 25) -or ($settings.initialExpBonusPercent -lt 0) -or ($settings.maxExpBonusPercent -lt $settings.initialExpBonusPercent)) {
        throw '经验配置设置无效：最大等级必须为 25，经验加成上限不能低于初始值'
    }

    $levels = [ordered]@{}
    foreach ($levelId in $LevelTable.Sections.Keys) {
        $row = $LevelTable.Sections[$levelId]
        foreach ($field in @('level', 'requiredExp')) {
            if (-not $row.Contains($field)) {
                throw "经验等级配置缺少字段：experience.xlsx/levels/$levelId/$field"
            }
        }
        $level = [int]$row.level
        $requiredExp = [int]$row.requiredExp
        if ($level -lt 1 -or $level -gt $settings.maxLevel -or $requiredExp -lt 0) {
            throw "经验等级配置数值无效：experience.xlsx/levels/$levelId"
        }
        $levelKey = [string]$level
        if ($levels.Contains($levelKey)) {
            throw "经验等级配置重复：experience.xlsx/levels/$level"
        }
        if ($level -lt $settings.maxLevel -and $requiredExp -le 0) {
            throw "非满级等级的升级经验必须为正整数：experience.xlsx/levels/$level"
        }
        if ($level -eq $settings.maxLevel -and $requiredExp -ne 0) {
            throw "满级等级的升级经验必须为 0：experience.xlsx/levels/$level"
        }
        $levels[$levelKey] = [ordered]@{
            levelId = $levelId
            level = $level
            requiredExp = $requiredExp
        }
    }
    if ($levels.Count -ne $settings.maxLevel) {
        throw "经验等级配置必须恰有 $($settings.maxLevel) 行，实际为：$($levels.Count)"
    }
    for ($level = 1; $level -le $settings.maxLevel; $level = $level + 1) {
        if (-not $levels.Contains([string]$level)) {
            throw "经验等级配置缺失：experience.xlsx/levels/$level"
        }
    }

    $lni = [ordered]@{
        settings = $settings
    }
    foreach ($levelKey in $levels.Keys) {
        $lni["level_$levelKey"] = $levels[$levelKey]
    }

    return [ordered]@{
        luaData = [ordered]@{
            version = 1
            settings = $settings
            levels = $levels
        }
        lni = $lni
    }
}

function New-MysteryShopConfig {
    param(
        [Parameter(Mandatory = $true)][object]$ShopTable,
        [Parameter(Mandatory = $true)][object]$StockTable,
        [Parameter(Mandatory = $true)][object]$ConsumableTable,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Units,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Items,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Abilities
    )

    $requiredShopFields = @('blockId', 'sourcePoint', 'unitRawcode', 'x', 'y', 'facing', 'enabled')
    $requiredStockFields = @('shopId', 'itemRawcode', 'boxLevel', 'price', 'initialStock', 'maxStock', 'enabled')
    $requiredBlocks = @(2, 4, 6, 8)
    $shops = [ordered]@{}
    $shopBlocks = @{}

    foreach ($shopId in $ShopTable.Sections.Keys) {
        $row = $ShopTable.Sections[$shopId]
        foreach ($field in $requiredShopFields) {
            if (-not $row.Contains($field)) {
                throw "神秘商店配置缺少字段：mystery_shop.xlsx/shops/$shopId/$field"
            }
        }

        $blockId = [int]$row.blockId
        $x = [int]$row.x
        $y = [int]$row.y
        $facing = [int]$row.facing
        $enabled = [int]$row.enabled
        $sourcePoint = [string]$row.sourcePoint
        $unitRawcode = [string]$row.unitRawcode
        if ($requiredBlocks -notcontains $blockId) {
            throw "神秘商店区域必须为 2、4、6、8：mystery_shop.xlsx/shops/$shopId"
        }
        if ($shopBlocks.ContainsKey($blockId)) {
            throw "神秘商店区域重复：mystery_shop.xlsx/shops/$shopId/$blockId"
        }
        if ([string]::IsNullOrWhiteSpace($sourcePoint) -or $sourcePoint -ne "MonsterPoint_${blockId}_1") {
            throw "神秘商店参考刷怪点必须为 MonsterPoint_${blockId}_1：mystery_shop.xlsx/shops/$shopId"
        }
        if (-not $Units.Contains($unitRawcode)) {
            throw "神秘商店单位 Rawcode 不存在：mystery_shop.xlsx/shops/$shopId/$unitRawcode"
        }
        if ($enabled -ne 0 -and $enabled -ne 1) {
            throw "神秘商店启用状态必须为 0 或 1：mystery_shop.xlsx/shops/$shopId"
        }
        if ($facing -lt 0 -or $facing -ge 360) {
            throw "神秘商店朝向必须在 0 到 359：mystery_shop.xlsx/shops/$shopId"
        }

        $shopBlocks[$blockId] = $shopId
        $shops[$shopId] = [ordered]@{
            shopId = [string]$shopId
            blockId = $blockId
            sourcePoint = $sourcePoint
            unitRawcode = $unitRawcode
            x = $x
            y = $y
            facing = $facing
            enabled = $enabled
        }
    }

    if ($shops.Count -ne 4) {
        throw "神秘商店必须恰有 4 个配置，实际为：$($shops.Count)"
    }
    foreach ($blockId in $requiredBlocks) {
        if (-not $shopBlocks.ContainsKey($blockId)) {
            throw "神秘商店缺少区域：$blockId"
        }
    }

    $stock = [ordered]@{}
    $boxByRawcode = [ordered]@{}
    $consumableByRawcode = [ordered]@{}
    $boxPriceByRawcode = @{}
    $stockByShopAndLevel = @{}
    foreach ($stockId in $StockTable.Sections.Keys) {
        $row = $StockTable.Sections[$stockId]
        foreach ($field in $requiredStockFields) {
            if (-not $row.Contains($field)) {
                throw "神秘商店库存配置缺少字段：mystery_shop.xlsx/stock/$stockId/$field"
            }
        }

        $shopId = [string]$row.shopId
        $itemRawcode = [string]$row.itemRawcode
        $boxLevel = [int]$row.boxLevel
        $price = [int]$row.price
        $configuredInitialStock = [int]$row.initialStock
        $configuredMaxStock = [int]$row.maxStock
        $enabled = [int]$row.enabled
        if (-not $shops.Contains($shopId)) {
            throw "神秘商店库存引用了不存在的商店：mystery_shop.xlsx/stock/$stockId/$shopId"
        }
        if ($itemRawcode -notmatch '^I0K[123]$' -or $boxLevel -lt 1 -or $boxLevel -gt 3 -or $itemRawcode -ne "I0K$boxLevel") {
            throw "神秘商店装备箱 Rawcode 或等级无效：mystery_shop.xlsx/stock/$stockId"
        }
        if ($price -le 0 -or $configuredInitialStock -lt 0 -or $configuredMaxStock -lt $configuredInitialStock) {
            throw "神秘商店价格或库存无效：mystery_shop.xlsx/stock/$stockId"
        }
        if ($enabled -ne 0 -and $enabled -ne 1) {
            throw "神秘商店库存启用状态必须为 0 或 1：mystery_shop.xlsx/stock/$stockId"
        }
        if (-not $Items.Contains($itemRawcode)) {
            throw "神秘商店装备箱物品 Rawcode 不存在：mystery_shop.xlsx/stock/$stockId/$itemRawcode"
        }

        $item = $Items[$itemRawcode]
        foreach ($field in @('isEquipment', 'equipLevel', 'mergeable')) {
            if (-not $item.Contains($field)) {
                throw "装备箱物品缺少非装备标记字段：item.xlsx/item/$itemRawcode/$field"
            }
        }
        if ([int]$item.isEquipment -ne 0 -or [int]$item.equipLevel -ne 0 -or [int]$item.mergeable -ne 0) {
            throw "装备箱必须标记为非装备、非合成物品：item.xlsx/item/$itemRawcode"
        }

        $shopLevelKey = "$shopId`:$boxLevel"
        if ($stockByShopAndLevel.ContainsKey($shopLevelKey)) {
            throw "神秘商店库存等级重复：mystery_shop.xlsx/stock/$shopId/$boxLevel"
        }
        $stockByShopAndLevel[$shopLevelKey] = $stockId
        if ($boxPriceByRawcode.ContainsKey($itemRawcode) -and $boxPriceByRawcode[$itemRawcode] -ne $price) {
            throw "同一装备箱必须使用统一价格：mystery_shop.xlsx/stock/$itemRawcode"
        }
        $boxPriceByRawcode[$itemRawcode] = $price
        $item.goldcost = $price
        $item.stockMax = 1
        $item.stockStart = 0
        # w3x2lni/Warcraft III 的物编字段名是 stockRegen，
        # 对应 Object Editor 的“Stock Replenish Interval”。
        $item.stockRegen = 1
        [void]$item.Remove('stockReplenish')
        $boxByRawcode[$itemRawcode] = $boxLevel
        $initialStock = 1
        $maxStock = 1
        $stock[$stockId] = [ordered]@{
            stockId = [string]$stockId
            shopId = $shopId
            itemRawcode = $itemRawcode
            productKind = 'box'
            boxLevel = $boxLevel
            price = $price
            initialStock = $initialStock
            maxStock = $maxStock
            stockRegen = 1
            enabled = $enabled
        }
    }

    if ($stock.Count -ne 12) {
        throw "mystery_shop.xlsx/stock 必须恰有 12 条装备箱库存，实际为：$($stock.Count)"
    }
    foreach ($shopId in $shops.Keys) {
        foreach ($boxLevel in @(1, 2, 3)) {
            if (-not $stockByShopAndLevel.ContainsKey("$shopId`:$boxLevel")) {
                throw "神秘商店缺少等级库存：mystery_shop.xlsx/stock/$shopId/$boxLevel"
            }
        }
    }
    if ($boxByRawcode.Count -ne 3) {
        throw "神秘商店装备箱必须恰有 3 个 Rawcode，实际为：$($boxByRawcode.Count)"
    }

    $requiredConsumableFields = @(
        'itemRawcode', 'abilityRawcode', 'parent', 'kind', 'name', 'description',
        'tip', 'ubertip', 'price', 'initialStock', 'maxStock', 'stockRegen',
        'healPercent', 'manaPercent', 'enabled'
    )
    $seenConsumableKinds = @{}
    foreach ($consumableId in $ConsumableTable.Sections.Keys) {
        $row = $ConsumableTable.Sections[$consumableId]
        foreach ($field in $requiredConsumableFields) {
            if (-not $row.Contains($field)) {
                throw "神秘商店消耗品配置缺少字段：mystery_shop_consumables.ini/$consumableId/$field"
            }
        }

        $itemRawcode = [string]$row.itemRawcode
        $abilityRawcode = [string]$row.abilityRawcode
        $parent = [string]$row.parent
        $kind = [string]$row.kind
        $price = [int]$row.price
        $initialStock = [int]$row.initialStock
        $maxStock = [int]$row.maxStock
        $stockRegen = [int]$row.stockRegen
        $healPercent = [int]$row.healPercent
        $manaPercent = [int]$row.manaPercent
        $enabled = [int]$row.enabled
        if ($itemRawcode -notmatch '^I0P[12]$' -or $abilityRawcode -notmatch '^A0P[12]$') {
            throw "神秘商店消耗品 Rawcode 无效：mystery_shop_consumables.ini/$consumableId"
        }
        if ($Items.Contains($itemRawcode) -or $Abilities.Contains($abilityRawcode)) {
            throw "神秘商店消耗品 Rawcode 与现有物编冲突：$consumableId"
        }
        if ($kind -ne 'health' -and $kind -ne 'mana') {
            throw "神秘商店消耗品类型必须为 health 或 mana：mystery_shop_consumables.ini/$consumableId"
        }
        if ($seenConsumableKinds.ContainsKey($kind)) {
            throw "神秘商店消耗品类型重复：$kind"
        }
        if ([string]::IsNullOrWhiteSpace($parent)) {
            throw "神秘商店消耗品必须配置物品父对象：$consumableId"
        }
        if ($price -le 0 -or $initialStock -lt 0 -or $maxStock -lt $initialStock -or $stockRegen -le 0) {
            throw "神秘商店消耗品价格或库存无效：mystery_shop_consumables.ini/$consumableId"
        }
        if ($healPercent -lt 0 -or $manaPercent -lt 0 -or ($enabled -ne 0 -and $enabled -ne 1)) {
            throw "神秘商店消耗品恢复比例或启用状态无效：mystery_shop_consumables.ini/$consumableId"
        }
        if ($kind -eq 'health' -and ($healPercent -le 0 -or $manaPercent -ne 0)) {
            throw "生命药必须只配置正数 healPercent：mystery_shop_consumables.ini/$consumableId"
        }
        if ($kind -eq 'mana' -and ($manaPercent -le 0 -or $healPercent -ne 0)) {
            throw "魔法药必须只配置正数 manaPercent：mystery_shop_consumables.ini/$consumableId"
        }

        # 生命药与魔法药分别使用对应的原生可用性检查；实际恢复数值仍由
        # EVENT_PLAYER_UNIT_USE_ITEM 回调按 A0P1/A0P2 的配置百分比结算。
        $abilityParent = if ($kind -eq 'health') { 'AIh1' } else { 'AIm1' }
        $Items[$itemRawcode] = [ordered]@{
            _parent = $parent
            Name = [string]$row.name
            Description = [string]$row.description
            Tip = [string]$row.tip
            Ubertip = [string]$row.ubertip
            abilList = $abilityRawcode
            class = 'Purchasable'
            Level = 1
            goldcost = $price
            lumbercost = 0
            drop = 0
            droppable = 1
            sellable = 0
            pawnable = 0
            perishable = 1
            powerup = 0
            uses = 1
            usable = 1
            isEquipment = 0
            equipLevel = 0
            mergeable = 0
            stockMax = $maxStock
            stockStart = $initialStock
            stockRegen = $stockRegen
        }
        $Abilities[$abilityRawcode] = [ordered]@{
            _parent = $abilityParent
            Name = [string]$row.name
            Ubertip = '由 Lua 按百分比结算恢复效果。'
            hero = 0
            item = 1
            levels = 1
            reqLevel = 0
            levelSkip = 0
            Cool = 0
            Cost = 0
            Rng = 100
            DataA = 0
        }
        $seenConsumableKinds[$kind] = $itemRawcode
        $consumableByRawcode[$itemRawcode] = [ordered]@{
            rawcode = $itemRawcode
            kind = $kind
            abilityRawcode = $abilityRawcode
            healPercent = $healPercent
            manaPercent = $manaPercent
            price = $price
            stockRegen = $stockRegen
            enabled = $enabled
        }

        foreach ($shopId in $shops.Keys) {
            $stockId = "STOCK_${shopId}_$($kind.ToUpperInvariant())"
            if ($stock.Contains($stockId)) {
                throw "神秘商店库存 ID 重复：$stockId"
            }
            $stock[$stockId] = [ordered]@{
                stockId = $stockId
                shopId = $shopId
                itemRawcode = $itemRawcode
                productKind = $kind
                boxLevel = 0
                price = $price
                initialStock = $initialStock
                maxStock = $maxStock
                stockRegen = $stockRegen
                enabled = $enabled
            }
        }
    }
    if (($ConsumableTable.Sections.Count -ne 2) -or ($seenConsumableKinds.Count -ne 2) -or (-not $seenConsumableKinds.ContainsKey('health')) -or (-not $seenConsumableKinds.ContainsKey('mana'))) {
        throw "神秘商店消耗品必须恰有 health 和 mana 两种配置"
    }
    if ($stock.Count -ne 20) {
        throw "神秘商店最终库存必须恰有 20 条（12 条装备箱、8 条消耗品），实际为：$($stock.Count)"
    }

    return [ordered]@{
        version = 1
        refillIntervalSeconds = 1
        consumableRefillIntervalSeconds = 5
        shops = $shops
        stock = $stock
        boxByRawcode = $boxByRawcode
        consumableByRawcode = $consumableByRawcode
    }
}

function ConvertTo-Base36Pair {
    param([Parameter(Mandatory = $true)][int]$Index)

    if ($Index -lt 0 -or $Index -ge 1296) {
        throw "技能 Rawcode 索引超出两位 Base36 范围：$Index"
    }
    $characters = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    return [string]$characters[[math]::Floor($Index / 36)] + [string]$characters[$Index % 36]
}

function Get-EquipmentRequiredField {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Row,
        [Parameter(Mandatory = $true)][string]$Field,
        [Parameter(Mandatory = $true)][string]$Context
    )

    if (-not $Row.Contains($Field) -or $null -eq $Row[$Field]) {
        throw "装备配置缺少字段：$Context / $Field"
    }
    return $Row[$Field]
}

function Assert-EquipmentIntegerRange {
    param(
        [Parameter(Mandatory = $true)][int]$Value,
        [Parameter(Mandatory = $true)][int]$Minimum,
        [Parameter(Mandatory = $true)][int]$Maximum,
        [Parameter(Mandatory = $true)][string]$Context
    )

    if ($Value -lt $Minimum -or $Value -gt $Maximum) {
        throw "装备配置数值超出范围：$Context，实际=$Value，允许=$Minimum..$Maximum"
    }
}

function New-EquipmentStatAbilitySection {
    param(
        [Parameter(Mandatory = $true)][string]$Rawcode,
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][object[]]$Values,
        [bool]$ItemAbility = $true
    )

    if ($Values.Count -ne 10) {
        throw "装备隐藏属性技能必须恰有 10 个等级：$Rawcode"
    }
    return [ordered]@{
        _parent = $Parent
        Name = $Name
        hero = 0
        item = if ($ItemAbility) { 1 } else { 0 }
        levels = 10
        levelSkip = 0
        DataA = $Values
    }
}

function New-ScaledDigitValues {
    param(
        [Parameter(Mandatory = $true)][double]$Scale,
        [Parameter(Mandatory = $true)][bool]$Negative
    )

    $sign = if ($Negative) { -1.0 } else { 1.0 }
    return @(for ($index = 0; $index -lt 10; $index = $index + 1) {
        [math]::Round($index * $Scale * $sign, 4)
    })
}

function New-EquipmentStatAbilities {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$ExistingAbilities)

    $abilitySections = [ordered]@{}
    $units = @(0..9)
    $tens = @(for ($index = 0; $index -lt 10; $index = $index + 1) { $index * 10 })
    $hundreds = @(for ($index = 0; $index -lt 10; $index = $index + 1) { $index * 100 })
    $thousands = @(for ($index = 0; $index -lt 10; $index = $index + 1) { $index * 1000 })
    $tenThousands = @(for ($index = 0; $index -lt 10; $index = $index + 1) { $index * 10000 })
    $hundredThousands = @(for ($index = 0; $index -lt 10; $index = $index + 1) { $index * 100000 })
    $millions = @(for ($index = 0; $index -lt 10; $index = $index + 1) { $index * 1000000 })
    $negativeUnits = @(for ($index = 0; $index -lt 10; $index = $index + 1) { -$index })
    $negativeTens = @(for ($index = 0; $index -lt 10; $index = $index + 1) { -$index * 10 })
    $negativeHundreds = @(for ($index = 0; $index -lt 10; $index = $index + 1) { -$index * 100 })
    $negativeThousands = @(for ($index = 0; $index -lt 10; $index = $index + 1) { -$index * 1000 })
    $negativeTenThousands = @(for ($index = 0; $index -lt 10; $index = $index + 1) { -$index * 10000 })
    $negativeHundredThousands = @(for ($index = 0; $index -lt 10; $index = $index + 1) { -$index * 100000 })
    $negativeMillions = @(for ($index = 0; $index -lt 10; $index = $index + 1) { -$index * 1000000 })
    $armorTenthUnits = New-ScaledDigitValues 0.1 $false
    $armorTenthTens = New-ScaledDigitValues 1.0 $false
    $armorTenthHundreds = New-ScaledDigitValues 10.0 $false
    $armorTenthThousands = New-ScaledDigitValues 100.0 $false
    $armorTenthNegativeUnits = New-ScaledDigitValues 0.1 $true
    $armorTenthNegativeTens = New-ScaledDigitValues 1.0 $true
    $armorTenthNegativeHundreds = New-ScaledDigitValues 10.0 $true
    $armorTenthNegativeThousands = New-ScaledDigitValues 100.0 $true
    $regenHundredthUnits = New-ScaledDigitValues 0.01 $false
    $regenHundredthTens = New-ScaledDigitValues 0.1 $false
    $regenHundredthHundreds = New-ScaledDigitValues 1.0 $false
    $regenHundredthThousands = New-ScaledDigitValues 10.0 $false
    $regenHundredthNegativeUnits = New-ScaledDigitValues 0.01 $true
    $regenHundredthNegativeTens = New-ScaledDigitValues 0.1 $true
    $regenHundredthNegativeHundreds = New-ScaledDigitValues 1.0 $true
    $regenHundredthNegativeThousands = New-ScaledDigitValues 10.0 $true
    $speedTenthUnits = New-ScaledDigitValues 0.1 $false
    $speedTenthTens = New-ScaledDigitValues 1.0 $false
    $speedTenthHundreds = New-ScaledDigitValues 10.0 $false
    $speedTenthThousands = New-ScaledDigitValues 100.0 $false
    $speedTenthNegativeUnits = New-ScaledDigitValues 0.1 $true
    $speedTenthNegativeTens = New-ScaledDigitValues 1.0 $true
    $speedTenthNegativeHundreds = New-ScaledDigitValues 10.0 $true
    $speedTenthNegativeThousands = New-ScaledDigitValues 100.0 $true
    $definitions = @(
        # AIlf 采用 UnitMaxState 兼容写法：临时添加反向生命值、设置等级、移除后写入目标差额。
        @{ Rawcode = 'EH00'; Parent = 'AIlf'; Name = '英雄生命状态增加个位'; Values = $negativeUnits },
        @{ Rawcode = 'EH01'; Parent = 'AIlf'; Name = '英雄生命状态增加十位'; Values = $negativeTens },
        @{ Rawcode = 'EH02'; Parent = 'AIlf'; Name = '英雄生命状态增加百位'; Values = $negativeHundreds },
        @{ Rawcode = 'EH03'; Parent = 'AIlf'; Name = '英雄生命状态增加千位'; Values = $negativeThousands },
        @{ Rawcode = 'EH04'; Parent = 'AIlf'; Name = '英雄生命状态增加万位'; Values = $negativeTenThousands },
        @{ Rawcode = 'EH05'; Parent = 'AIlf'; Name = '英雄生命状态增加十万位'; Values = $negativeHundredThousands },
        @{ Rawcode = 'EH06'; Parent = 'AIlf'; Name = '英雄生命状态增加百万位'; Values = $negativeMillions },
        @{ Rawcode = 'EHN0'; Parent = 'AIlf'; Name = '英雄生命状态减少个位'; Values = $units },
        @{ Rawcode = 'EHN1'; Parent = 'AIlf'; Name = '英雄生命状态减少十位'; Values = $tens },
        @{ Rawcode = 'EHN2'; Parent = 'AIlf'; Name = '英雄生命状态减少百位'; Values = $hundreds },
        @{ Rawcode = 'EHN3'; Parent = 'AIlf'; Name = '英雄生命状态减少千位'; Values = $thousands },
        @{ Rawcode = 'EHN4'; Parent = 'AIlf'; Name = '英雄生命状态减少万位'; Values = $tenThousands },
        @{ Rawcode = 'EHN5'; Parent = 'AIlf'; Name = '英雄生命状态减少十万位'; Values = $hundredThousands },
        @{ Rawcode = 'EHN6'; Parent = 'AIlf'; Name = '英雄生命状态减少百万位'; Values = $millions },
        @{ Rawcode = 'ED00'; Parent = 'AItg'; Name = '装备隐藏攻击个位'; Values = $units },
        @{ Rawcode = 'ED01'; Parent = 'AItg'; Name = '装备隐藏攻击十位'; Values = $tens },
        @{ Rawcode = 'ED02'; Parent = 'AItg'; Name = '装备隐藏攻击百位'; Values = $hundreds },
        @{ Rawcode = 'ED03'; Parent = 'AItg'; Name = '装备隐藏攻击千位'; Values = $thousands },
        @{ Rawcode = 'EDN0'; Parent = 'AItg'; Name = '装备隐藏攻击减少个位'; Values = $negativeUnits },
        @{ Rawcode = 'EDN1'; Parent = 'AItg'; Name = '装备隐藏攻击减少十位'; Values = $negativeTens },
        @{ Rawcode = 'EDN2'; Parent = 'AItg'; Name = '装备隐藏攻击减少百位'; Values = $negativeHundreds },
        @{ Rawcode = 'EDN3'; Parent = 'AItg'; Name = '装备隐藏攻击减少千位'; Values = $negativeThousands },
        @{ Rawcode = 'EA00'; Parent = 'AId1'; Name = '装备隐藏护甲十分位'; Values = $armorTenthUnits },
        @{ Rawcode = 'EA01'; Parent = 'AId1'; Name = '装备隐藏护甲个位'; Values = $armorTenthTens },
        @{ Rawcode = 'EA02'; Parent = 'AId1'; Name = '装备隐藏护甲十位'; Values = $armorTenthHundreds },
        @{ Rawcode = 'EA03'; Parent = 'AId1'; Name = '装备隐藏护甲百位'; Values = $armorTenthThousands },
        @{ Rawcode = 'EAN0'; Parent = 'AId1'; Name = '装备隐藏护甲减少十分位'; Values = $armorTenthNegativeUnits },
        @{ Rawcode = 'EAN1'; Parent = 'AId1'; Name = '装备隐藏护甲减少个位'; Values = $armorTenthNegativeTens },
        @{ Rawcode = 'EAN2'; Parent = 'AId1'; Name = '装备隐藏护甲减少十位'; Values = $armorTenthNegativeHundreds },
        @{ Rawcode = 'EAN3'; Parent = 'AId1'; Name = '装备隐藏护甲减少百位'; Values = $armorTenthNegativeThousands },
        @{ Rawcode = 'EM00'; Parent = 'AImb'; Name = '装备隐藏法力正个位'; Values = $units },
        @{ Rawcode = 'EM01'; Parent = 'AImb'; Name = '装备隐藏法力正十位'; Values = $tens },
        @{ Rawcode = 'EM02'; Parent = 'AImb'; Name = '装备隐藏法力正百位'; Values = $hundreds },
        @{ Rawcode = 'EM03'; Parent = 'AImb'; Name = '装备隐藏法力正千位'; Values = $thousands },
        @{ Rawcode = 'EMN0'; Parent = 'AImb'; Name = '装备隐藏法力负个位'; Values = $negativeUnits },
        @{ Rawcode = 'EMN1'; Parent = 'AImb'; Name = '装备隐藏法力负十位'; Values = $negativeTens },
        @{ Rawcode = 'EMN2'; Parent = 'AImb'; Name = '装备隐藏法力负百位'; Values = $negativeHundreds },
        @{ Rawcode = 'EMN3'; Parent = 'AImb'; Name = '装备隐藏法力负千位'; Values = $negativeThousands },
        @{ Rawcode = 'ER00'; Parent = 'Arel'; Name = '装备隐藏生命回复正百分位'; Values = $regenHundredthUnits },
        @{ Rawcode = 'ER01'; Parent = 'Arel'; Name = '装备隐藏生命回复正十分位'; Values = $regenHundredthTens },
        @{ Rawcode = 'ER02'; Parent = 'Arel'; Name = '装备隐藏生命回复正个位'; Values = $regenHundredthHundreds },
        @{ Rawcode = 'ER03'; Parent = 'Arel'; Name = '装备隐藏生命回复正十位'; Values = $regenHundredthThousands },
        @{ Rawcode = 'ERN0'; Parent = 'Arel'; Name = '装备隐藏生命回复负百分位'; Values = $regenHundredthNegativeUnits },
        @{ Rawcode = 'ERN1'; Parent = 'Arel'; Name = '装备隐藏生命回复负十分位'; Values = $regenHundredthNegativeTens },
        @{ Rawcode = 'ERN2'; Parent = 'Arel'; Name = '装备隐藏生命回复负个位'; Values = $regenHundredthNegativeHundreds },
        @{ Rawcode = 'ERN3'; Parent = 'Arel'; Name = '装备隐藏生命回复负十位'; Values = $regenHundredthNegativeThousands },
        @{ Rawcode = 'ES00'; Parent = 'AIrm'; Name = '装备隐藏法力回复正百分位'; Values = $regenHundredthUnits },
        @{ Rawcode = 'ES01'; Parent = 'AIrm'; Name = '装备隐藏法力回复正十分位'; Values = $regenHundredthTens },
        @{ Rawcode = 'ES02'; Parent = 'AIrm'; Name = '装备隐藏法力回复正个位'; Values = $regenHundredthHundreds },
        @{ Rawcode = 'ES03'; Parent = 'AIrm'; Name = '装备隐藏法力回复正十位'; Values = $regenHundredthThousands },
        @{ Rawcode = 'ESN0'; Parent = 'AIrm'; Name = '装备隐藏法力回复负百分位'; Values = $regenHundredthNegativeUnits },
        @{ Rawcode = 'ESN1'; Parent = 'AIrm'; Name = '装备隐藏法力回复负十分位'; Values = $regenHundredthNegativeTens },
        @{ Rawcode = 'ESN2'; Parent = 'AIrm'; Name = '装备隐藏法力回复负个位'; Values = $regenHundredthNegativeHundreds },
        @{ Rawcode = 'ESN3'; Parent = 'AIrm'; Name = '装备隐藏法力回复负十位'; Values = $regenHundredthNegativeThousands },
        @{ Rawcode = 'ET00'; Parent = 'AIsx'; Name = '装备隐藏攻速正十分位'; Values = $speedTenthUnits },
        @{ Rawcode = 'ET01'; Parent = 'AIsx'; Name = '装备隐藏攻速正个位'; Values = $speedTenthTens },
        @{ Rawcode = 'ET02'; Parent = 'AIsx'; Name = '装备隐藏攻速正十位'; Values = $speedTenthHundreds },
        @{ Rawcode = 'ET03'; Parent = 'AIsx'; Name = '装备隐藏攻速正百位'; Values = $speedTenthThousands },
        @{ Rawcode = 'ETN0'; Parent = 'AIsx'; Name = '装备隐藏攻速负十分位'; Values = $speedTenthNegativeUnits },
        @{ Rawcode = 'ETN1'; Parent = 'AIsx'; Name = '装备隐藏攻速负个位'; Values = $speedTenthNegativeTens },
        @{ Rawcode = 'ETN2'; Parent = 'AIsx'; Name = '装备隐藏攻速负十位'; Values = $speedTenthNegativeHundreds },
        @{ Rawcode = 'ETN3'; Parent = 'AIsx'; Name = '装备隐藏攻速负百位'; Values = $speedTenthNegativeThousands }
    )
    foreach ($definition in $definitions) {
        if ($ExistingAbilities.Contains($definition.Rawcode)) {
            throw "装备隐藏属性技能 Rawcode 冲突：$($definition.Rawcode)"
        }
        $itemAbility = if ($definition.ContainsKey('ItemAbility')) { [bool]$definition.ItemAbility } else { $true }
        $abilitySections[$definition.Rawcode] = New-EquipmentStatAbilitySection $definition.Rawcode $definition.Parent $definition.Name $definition.Values $itemAbility
    }
    return [pscustomobject]@{
        abilitySections = $abilitySections
        luaData = [ordered]@{
            healthDecrease = @('EHN0', 'EHN1', 'EHN2', 'EHN3', 'EHN4', 'EHN5', 'EHN6')
            healthIncrease = @('EH00', 'EH01', 'EH02', 'EH03', 'EH04', 'EH05', 'EH06')
            attack = @('ED00', 'ED01', 'ED02', 'ED03')
            attackDecrease = @('EDN0', 'EDN1', 'EDN2', 'EDN3')
            armor = @('EA00', 'EA01', 'EA02', 'EA03')
            armorDecrease = @('EAN0', 'EAN1', 'EAN2', 'EAN3')
            manaPositive = @('EM00', 'EM01', 'EM02', 'EM03')
            manaNegative = @('EMN0', 'EMN1', 'EMN2', 'EMN3')
            manaRegenPositive = @('ES00', 'ES01', 'ES02', 'ES03')
            manaRegenNegative = @('ESN0', 'ESN1', 'ESN2', 'ESN3')
            lifeRegenPositive = @('ER00', 'ER01', 'ER02', 'ER03')
            lifeRegenNegative = @('ERN0', 'ERN1', 'ERN2', 'ERN3')
            attackSpeedPositive = @('ET00', 'ET01', 'ET02', 'ET03')
            attackSpeedNegative = @('ETN0', 'ETN1', 'ETN2', 'ETN3')
        }
    }
}

function Get-DamageAttributeLabel {
    param([Parameter(Mandatory = $true)][string]$AttributeId)

    $labels = @{ strength = '力量'; agility = '敏捷'; intelligence = '智力'; primary = '持有者主属性' }
    if (-not $labels.ContainsKey($AttributeId)) { throw "伤害属性 ID 无效：$AttributeId" }
    return $labels[$AttributeId]
}

function Format-TenthMultiplier {
    param([Parameter(Mandatory = $true)][int]$Value)

    if ($Value -le 0) { throw "伤害倍率必须为正整数十倍定点：$Value" }
    $whole = [math]::Floor($Value / 10)
    $fraction = $Value % 10
    if ($fraction -eq 0) { return [string]$whole }
    return "$whole.$fraction"
}

function Get-EquipmentDamageFormulaText {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Row, [Parameter(Mandatory = $true)][string]$Context)

    $attribute = [string](Get-EquipmentRequiredField $Row 'damageAttribute' $Context)
    $base = [int](Get-EquipmentRequiredField $Row 'damageMultiplierBaseTenth' $Context)
    $perLevel = [int](Get-EquipmentRequiredField $Row 'damageMultiplierPerLevelTenth' $Context)
    if ($attribute -notin @('primary', 'strength', 'agility', 'intelligence') -or $base -le 0 -or $perLevel -lt 0) {
        throw "装备伤害公式无效：$Context"
    }
    $baseText = Format-TenthMultiplier $base
    $attributeText = Get-DamageAttributeLabel $attribute
    if ($perLevel -eq 0) { return "$baseText×$attributeText" }
    return "（$baseText+装备等级×$(Format-TenthMultiplier $perLevel)）×$attributeText"
}

function New-EquipmentConfig {
    param(
        [Parameter(Mandatory = $true)][object]$LevelTable,
        [Parameter(Mandatory = $true)][object]$TemplateTable,
        [Parameter(Mandatory = $true)][object]$AutoTable,
        [Parameter(Mandatory = $true)][object]$PassiveTable,
        [Parameter(Mandatory = $true)][object]$ComboTable,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Items,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Units
    )

    if ($LevelTable.Sections.Count -ne 5) {
        throw "装备等级配置必须恰有 5 行，实际为：$($LevelTable.Sections.Count)"
    }
    $levels = ConvertTo-ObjectConfig $LevelTable.Sections
    foreach ($levelId in $levels.Keys) {
        $level = [int](Get-EquipmentRequiredField $levels[$levelId] 'level' "level/$levelId")
        Assert-EquipmentIntegerRange $level 1 5 "level/$levelId/level"
        Assert-EquipmentIntegerRange ([int](Get-EquipmentRequiredField $levels[$levelId] 'statMultiplierPercent' "level/$levelId")) 1 100000 "level/$levelId/statMultiplierPercent"
        Assert-EquipmentIntegerRange ([int](Get-EquipmentRequiredField $levels[$levelId] 'skillPowerMultiplierPercent' "level/$levelId")) 1 100000 "level/$levelId/skillPowerMultiplierPercent"
        foreach ($chanceField in @('autoSkillChance', 'comboChance')) {
            Assert-EquipmentIntegerRange ([int](Get-EquipmentRequiredField $levels[$levelId] $chanceField "level/$levelId")) 0 100 "level/$levelId/$chanceField"
        }
        $passiveMin = [int](Get-EquipmentRequiredField $levels[$levelId] 'passiveMin' "level/$levelId")
        $passiveMax = [int](Get-EquipmentRequiredField $levels[$levelId] 'passiveMax' "level/$levelId")
        if ($passiveMin -lt 0 -or $passiveMax -lt $passiveMin -or $passiveMax -gt 2) {
            throw "装备被动数量范围无效：level/$levelId"
        }
    }

    $templates = ConvertTo-ObjectConfig $TemplateTable.Sections
    foreach ($templateId in $templates.Keys) {
        $template = $templates[$templateId]
        # 百分比属性是装备来源字段；旧工作簿缺少时按 0 兼容，不改变现有装备平衡。
        foreach ($optionalField in @('basicAttackBonusPercent', 'healthAmplificationPercent')) {
            if (-not $template.Contains($optionalField) -or $null -eq $template[$optionalField]) {
                $template[$optionalField] = 0
            }
            Assert-EquipmentIntegerRange ([int]$template[$optionalField]) -100000 100000 "template/$templateId/$optionalField"
        }
        $rawcode = [string](Get-EquipmentRequiredField $template 'rawcode' "template/$templateId")
        if (-not $Items.Contains($rawcode)) {
            throw "装备模板引用了不存在的道具：template/$templateId/$rawcode"
        }
        $item = $Items[$rawcode]
        if (-not $item.Contains('isEquipment') -or [int]$item.isEquipment -ne 1) {
            throw "装备模板引用的道具未标记为装备：template/$templateId/$rawcode"
        }
        $level = [int](Get-EquipmentRequiredField $template 'level' "template/$templateId")
        Assert-EquipmentIntegerRange $level 1 5 "template/$templateId/level"
        if ([int]$item.equipLevel -ne $level) {
            throw "装备模板等级与 item.xlsx 不一致：template/$templateId/$rawcode"
        }
        foreach ($range in @(@('baseAttackMin', 'baseAttackMax'), @('baseHealthMin', 'baseHealthMax'), @('baseArmorMin', 'baseArmorMax'))) {
            $minimum = [int](Get-EquipmentRequiredField $template $range[0] "template/$templateId")
            $maximum = [int](Get-EquipmentRequiredField $template $range[1] "template/$templateId")
            if ($minimum -lt 0 -or $maximum -lt $minimum) {
                throw "装备模板数值范围无效：template/$templateId/$($range[0])"
            }
        }
        if ([int](Get-EquipmentRequiredField $template 'weight' "template/$templateId") -le 0) {
            throw "装备模板权重必须大于 0：template/$templateId"
        }
    }

    $allowedAutoEvents = @('on_interval', 'on_attack', 'on_attack_hit', 'on_kill')
    $allowedAutoHandlers = @('area_damage', 'single_damage', 'heal_percent', 'heal_primary')
    $autoSkills = ConvertTo-ObjectConfig $AutoTable.Sections
    foreach ($autoId in $autoSkills.Keys) {
        $auto = $autoSkills[$autoId]
        $eventType = [string](Get-EquipmentRequiredField $auto 'eventType' "auto/$autoId")
        $handler = [string](Get-EquipmentRequiredField $auto 'handler' "auto/$autoId")
        if ($allowedAutoEvents -notcontains $eventType -or $allowedAutoHandlers -notcontains $handler) {
            throw "自动技能触发类型或执行器无效：auto/$autoId"
        }
        foreach ($field in @('chance', 'weight')) {
            Assert-EquipmentIntegerRange ([int](Get-EquipmentRequiredField $auto $field "auto/$autoId")) 0 100 "auto/$autoId/$field"
        }
        if ([int]$auto.weight -le 0 -or [int]$auto.interval -lt 0 -or [int]$auto.internalCooldown -lt 0) {
            throw "自动技能周期、冷却或权重无效：auto/$autoId"
        }
        if ($handler -in @('area_damage', 'single_damage')) {
            $formula = Get-EquipmentDamageFormulaText $auto "auto/$autoId"
            if ($handler -eq 'area_damage') {
                $auto.description = "每$([int]$auto.interval)秒自动对周围敌人造成$($formula)的魔法伤害。"
            } elseif ([int]$auto.chance -ge 100) {
                $auto.description = "攻击时对目标造成$($formula)的魔法伤害。"
            } else {
                $auto.description = "攻击时有$([int]$auto.chance)%概率对目标造成$($formula)的魔法伤害。"
            }
        }
    }

    $allowedPassiveEvents = @('none', 'on_interval', 'on_attack', 'on_attack_hit', 'on_kill')
    $allowedPassiveHandlers = @(
        'stat_attack', 'stat_health', 'stat_armor',
        'stat_basic_attack_bonus_percent', 'stat_health_amplification_percent',
        'auto_damage_bonus', 'heal_percent', 'heal_primary', 'single_damage'
    )
    $passives = ConvertTo-ObjectConfig $PassiveTable.Sections
    foreach ($passiveId in $passives.Keys) {
        $passive = $passives[$passiveId]
        $eventType = [string](Get-EquipmentRequiredField $passive 'eventType' "passive/$passiveId")
        $handler = [string](Get-EquipmentRequiredField $passive 'handler' "passive/$passiveId")
        if ($allowedPassiveEvents -notcontains $eventType -or $allowedPassiveHandlers -notcontains $handler) {
            throw "被动触发类型或执行器无效：passive/$passiveId"
        }
        Assert-EquipmentIntegerRange ([int](Get-EquipmentRequiredField $passive 'chance' "passive/$passiveId")) 0 100 "passive/$passiveId/chance"
        if ([int]$passive.weight -le 0 -or [int]$passive.interval -lt 0 -or [int]$passive.internalCooldown -lt 0) {
            throw "被动周期、冷却或权重无效：passive/$passiveId"
        }
        if ($handler -eq 'single_damage') {
            $formula = Get-EquipmentDamageFormulaText $passive "passive/$passiveId"
            $passive.description = "攻击时有$([int]$passive.chance)%概率造成$($formula)的额外魔法伤害。"
        }
    }

    $allowedComboHandlers = @(
        'stat_attack', 'stat_health', 'stat_armor',
        'stat_basic_attack_bonus_percent', 'stat_health_amplification_percent',
        'auto_damage_bonus', 'heal_percent', 'heal_primary', 'single_damage'
    )
    $combos = ConvertTo-ObjectConfig $ComboTable.Sections
    $comboSets = @{}
    foreach ($pieceId in $combos.Keys) {
        $piece = $combos[$pieceId]
        $setId = [string](Get-EquipmentRequiredField $piece 'setId' "combo/$pieceId")
        $pieceIndex = [int](Get-EquipmentRequiredField $piece 'pieceIndex' "combo/$pieceId")
        Assert-EquipmentIntegerRange $pieceIndex 1 3 "combo/$pieceId/pieceIndex"
        foreach ($handlerField in @('need2Handler', 'need3Handler')) {
            if ($allowedComboHandlers -notcontains ([string](Get-EquipmentRequiredField $piece $handlerField "combo/$pieceId"))) {
                throw "组合词条执行器无效：combo/$pieceId/$handlerField"
            }
        }
        if (-not $comboSets.ContainsKey($setId)) { $comboSets[$setId] = @{} }
        if ($comboSets[$setId].ContainsKey($pieceIndex)) { throw "组合词条部件序号重复：combo/$setId/$pieceIndex" }
        $comboSets[$setId][$pieceIndex] = $true
    }
    foreach ($setId in $comboSets.Keys) {
        if ($comboSets[$setId].Count -lt 2 -or $comboSets[$setId].Count -gt 3) {
            throw "组合套装必须包含 2 至 3 个不同部件：$setId"
        }
    }

    $poolIds = @{}
    foreach ($templateId in $templates.Keys) {
        $poolId = [string]$templates[$templateId].poolId
        if (-not [string]::IsNullOrWhiteSpace($poolId)) { $poolIds[$poolId] = $true }
    }
    foreach ($unitRawcode in $Units.Keys) {
        $unit = $Units[$unitRawcode]
        if (-not $unit.Contains('baseUnitId')) { continue }
        $chance = [int](Get-EquipmentRequiredField $unit 'dropChancePercent' "unit/$unitRawcode")
        Assert-EquipmentIntegerRange $chance 0 100 "unit/$unitRawcode/dropChancePercent"
        if ($chance -eq 0) { continue }
        $poolId = [string](Get-EquipmentRequiredField $unit 'poolId' "unit/$unitRawcode")
        $levelMin = [int](Get-EquipmentRequiredField $unit 'dropLevelMin' "unit/$unitRawcode")
        $levelMax = [int](Get-EquipmentRequiredField $unit 'dropLevelMax' "unit/$unitRawcode")
        $maxDrops = [int](Get-EquipmentRequiredField $unit 'maxDrops' "unit/$unitRawcode")
        Assert-EquipmentIntegerRange $levelMin 1 5 "unit/$unitRawcode/dropLevelMin"
        Assert-EquipmentIntegerRange $levelMax 1 5 "unit/$unitRawcode/dropLevelMax"
        if ($levelMax -lt $levelMin -or $maxDrops -lt 1 -or -not $poolIds.ContainsKey($poolId)) {
            throw "单位表中的掉落等级、装备池或最大掉落数无效：$unitRawcode"
        }
    }

    return [ordered]@{
        version = 1
        levels = $levels
        templates = $templates
        autoSkills = $autoSkills
        passives = $passives
        combos = $combos
    }
}

function Get-BossAffixRequiredInteger {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Row,
        [Parameter(Mandatory = $true)][string]$Field,
        [Parameter(Mandatory = $true)][string]$Context
    )

    if (-not $Row.Contains($Field) -or $Row[$Field] -isnot [System.IConvertible]) {
        throw "Boss 词缀配置缺少整数：$Context/$Field"
    }
    $value = 0
    if (-not [int]::TryParse([string]$Row[$Field], [System.Globalization.NumberStyles]::Integer, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$value)) {
        throw "Boss 词缀配置必须为整数：$Context/$Field"
    }
    return $value
}

function New-BossAffixAbilitySection {
    param(
        [Parameter(Mandatory = $true)][string]$Rawcode,
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Description,
        [Parameter(Mandatory = $true)][object[]]$DataAValues,
        [Parameter()][System.Collections.IDictionary]$ExtraFields = @{}
    )

    if ($DataAValues.Count -ne 1 -and $DataAValues.Count -ne 20) {
        throw "Boss 词缀技能必须为 1 级常量或 20 级单位变体：$Rawcode"
    }
    $dataA = if ($DataAValues.Count -eq 1) { $DataAValues[0] } else { $DataAValues }
    $section = [ordered]@{
        _parent = $Parent
        Name = "天灾词缀：$Name"
        Tip = "天灾词缀：$Name"
        Ubertip = $Description
        hero = 0
        item = 0
        levels = $DataAValues.Count
        levelSkip = 0
        DataA = $dataA
    }
    foreach ($field in $ExtraFields.Keys) {
        $section[$field] = $ExtraFields[$field]
    }
    return $section
}

function Get-BossAffixParent {
    param([Parameter(Mandatory = $true)][string]$Kind)

    switch ($Kind) {
        'move_speed' { return 'AIms' }
        'damage_percent' { return 'AItg' }
        'attack_speed_percent' { return 'AIsx' }
        'armor' { return 'AId1' }
        'health_percent' { return 'AIlf' }
        'life_regen' { return 'ACnr' }
        'bash' { return 'AIbx' }
        'frost' { return 'Afra' }
        'feedback' { return 'Afbk' }
        default { throw "不支持的 Boss 词缀类型：$Kind" }
    }
}

function New-BossAffixIndicatorAbilitySection {
    param(
        [Parameter(Mandatory = $true)][string]$Rawcode,
        [Parameter(Mandatory = $true)][string]$BuffRawcode,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Description
    )

    # ACua 会持续将 BuffID 施加给自身。所有数值为零，故这个辅助光环只
    # 负责让 1.27 的状态栏显示词缀图标，不改变词缀的实际属性结算。
    return [ordered]@{
        _parent = 'ACua'
        Name = "天灾词缀·$Name"
        Tip = "天灾词缀·$Name"
        Ubertip = $Description
        hero = 0
        item = 1
        levels = 1
        reqLevel = 1
        levelSkip = 0
        Cool = 0
        Cost = 0
        Rng = 0
        Area = 1
        DataA = 0
        DataB = 0
        DataC = 0
        BuffID = $BuffRawcode
        targs = 'self'
    }
}

function Get-BossAffixDataAValue {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Definition,
        [Parameter()][AllowNull()][System.Collections.IDictionary]$Unit,
        [Parameter()][AllowEmptyString()][string]$UnitRawcode = ''
    )

    $kind = [string]$Definition.kind
    $baseValue = [int]$Definition.baseValue
    switch ($kind) {
        'damage_percent' {
            $damage = Get-RequiredUnitInteger $Unit $UnitRawcode 'dmgplus1'
            return [int][math]::Floor(($damage * $baseValue + 99) / 100)
        }
        'health_percent' {
            $health = Get-RequiredUnitInteger $Unit $UnitRawcode 'HP'
            return [int][math]::Floor(($health * $baseValue + 99) / 100)
        }
        'frost' { return 0 }
        { $_ -in @('move_speed', 'attack_speed_percent', 'armor', 'life_regen', 'bash', 'feedback') } {
            return $baseValue
        }
        default { throw "不支持的 Boss 词缀类型：$kind" }
    }
}

function New-BossAffixData {
    param(
        [Parameter(Mandatory = $true)][object]$AffixTable,
        [Parameter(Mandatory = $true)][object]$BuffTable,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Units,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$ExistingAbilities
    )

    $expectedKinds = [ordered]@{
        B1 = 'move_speed'
        B2 = 'damage_percent'
        B3 = 'attack_speed_percent'
        B4 = 'armor'
        B5 = 'health_percent'
        B6 = 'life_regen'
        B7 = 'bash'
        B8 = 'frost'
        B9 = 'feedback'
    }
    if ($AffixTable.Sections.Count -ne $expectedKinds.Count) {
        throw "Boss 词缀必须恰有 9 条，实际为：$($AffixTable.Sections.Count)"
    }

    $baseRawcodes = @(Get-MonsterUnitRawcodes $Units)
    $variants = @{}
    foreach ($rawcode in $Units.Keys) {
        $unit = $Units[$rawcode]
        if (-not $unit.Contains('baseUnitId')) { continue }
        $key = "$($unit.baseUnitId):$([int]$unit.modeId):$([int]$unit.difficultyLevel)"
        $variants[$key] = $unit
    }
    if ($variants.Count -ne 760) { throw "Boss 词缀变体索引必须包含 760 行，实际=$($variants.Count)" }
    $abilitySections = [ordered]@{}
    $affixes = [ordered]@{}
    $rawcodeIndex = 0
    $unitSpecificAffixCount = 0
    $globalAffixCount = 0
    foreach ($affixId in $expectedKinds.Keys) {
        if (-not $AffixTable.Sections.Contains($affixId)) {
            throw "Boss 词缀配置缺失：$affixId"
        }
        $definition = $AffixTable.Sections[$affixId]
        foreach ($field in @('bossRawcode', 'name', 'kind', 'description', 'baseValue', 'secondaryValue', 'duration')) {
            if (-not $definition.Contains($field) -or $null -eq $definition[$field]) {
                throw "Boss 词缀配置缺少字段：boss_affix.xlsx/affix/$affixId/$field"
            }
        }
        $expectedBossRawcode = "$affixId" + 'M1'
        if ([string]$definition.bossRawcode -ne $expectedBossRawcode) {
            throw "Boss 词缀 Boss Rawcode 无效：$affixId，期望=$expectedBossRawcode"
        }
        if (-not $Units.Contains($expectedBossRawcode)) {
            throw "Boss 词缀引用的 Boss 单位不存在：$expectedBossRawcode"
        }
        if ([string]$definition.kind -ne $expectedKinds[$affixId]) {
            throw "Boss 词缀类型无效：$affixId，期望=$($expectedKinds[$affixId])"
        }
        $affixIndex = [int]$affixId.Substring(1)
        $indicatorBuffRawcode = "BZ0$affixIndex"
        $indicatorAbilityRawcode = "ZC0$affixIndex"
        if (-not $BuffTable.Sections.Contains($indicatorBuffRawcode)) {
            throw "Boss 词缀状态栏 Buff 缺失：buff.xlsx/buff/$indicatorBuffRawcode"
        }
        if ($ExistingAbilities.Contains($indicatorAbilityRawcode) -or $abilitySections.Contains($indicatorAbilityRawcode)) {
            throw "Boss 词缀状态栏技能 Rawcode 冲突：$indicatorAbilityRawcode"
        }
        foreach ($field in @('baseValue', 'secondaryValue', 'duration')) {
            if ((Get-BossAffixRequiredInteger $definition $field "boss_affix.xlsx/affix/$affixId") -lt 0) {
                throw "Boss 词缀数值不能为负数：$affixId/$field"
            }
        }

        $isUnitSpecific = ([string]$definition.kind -eq 'damage_percent' -or [string]$definition.kind -eq 'health_percent')
        if ($isUnitSpecific) { $unitSpecificAffixCount = $unitSpecificAffixCount + 1 }
        else { $globalAffixCount = $globalAffixCount + 1 }
        $affixEntry = [ordered]@{
            affixId = $affixId
            bossRawcode = [string]$definition.bossRawcode
            name = [string]$definition.name
            description = [string]$definition.description
            kind = [string]$definition.kind
            baseValue = [int]$definition.baseValue
            secondaryValue = [int]$definition.secondaryValue
            duration = [int]$definition.duration
            refillLife = ([string]$definition.kind -eq 'health_percent')
            indicatorAbilityRawcode = $indicatorAbilityRawcode
            indicatorBuffRawcode = $indicatorBuffRawcode
        }

        if ($isUnitSpecific) {
            $targetAbilityMappings = [ordered]@{}
            foreach ($baseRawcode in $baseRawcodes) {
                $dataAValues = New-Object System.Collections.Generic.List[object]
                for ($modeId = 1; $modeId -le 2; $modeId++) {
                    for ($level = 1; $level -le 10; $level++) {
                        $variantKey = "$baseRawcode`:$modeId`:$level"
                        if (-not $variants.ContainsKey($variantKey)) { throw "Boss 词缀缺少单位变体：$variantKey" }
                        $variantUnit = $variants[$variantKey]
                        $variantRawcode = [string]$variantUnit.rawcode
                        $dataAValues.Add((Get-BossAffixDataAValue $definition $variantUnit $variantRawcode))
                    }
                }
                $rawcode = 'ZB' + (ConvertTo-Base36Pair $rawcodeIndex)
                $rawcodeIndex++
                if ($ExistingAbilities.Contains($rawcode) -or $abilitySections.Contains($rawcode)) {
                    throw "Boss 词缀技能 Rawcode 冲突：$rawcode"
                }
                $abilitySections[$rawcode] = New-BossAffixAbilitySection `
                    $rawcode `
                    (Get-BossAffixParent ([string]$definition.kind)) `
                    ([string]$definition.name) `
                    ([string]$definition.description) `
                    $dataAValues.ToArray()
                $targetAbilityMappings[$baseRawcode] = $rawcode
            }
            $affixEntry.unitAbilities = $targetAbilityMappings
        } else {
            $dataA = Get-BossAffixDataAValue $definition $null ''
            $extraFields = [ordered]@{}
            switch ([string]$definition.kind) {
                'life_regen' { $extraFields.DataB = 0; $extraFields.Area = 0; $extraFields.targs = 'self' }
                'bash' {
                    $extraFields.DataB = 0
                    $extraFields.DataC = 0
                    $extraFields.Dur = [int]$definition.duration
                    $extraFields.HeroDur = [int]$definition.duration
                }
                'frost' {
                    $extraFields.Dur = [int]$definition.duration
                    $extraFields.HeroDur = [int]$definition.duration
                }
                'feedback' {
                    $extraFields.DataB = [int]$definition.secondaryValue
                    $extraFields.DataC = [int]$definition.baseValue
                    $extraFields.DataD = [int]$definition.secondaryValue
                }
            }
            $rawcode = 'ZB' + (ConvertTo-Base36Pair $rawcodeIndex)
            $rawcodeIndex++
            if ($ExistingAbilities.Contains($rawcode) -or $abilitySections.Contains($rawcode)) {
                throw "Boss 词缀技能 Rawcode 冲突：$rawcode"
            }
            $abilitySection = New-BossAffixAbilitySection `
                $rawcode `
                (Get-BossAffixParent ([string]$definition.kind)) `
                ([string]$definition.name) `
                ([string]$definition.description) `
                @([object]$dataA) `
                $extraFields
            if ([string]$definition.kind -eq 'frost') { [void]$abilitySection.Remove('DataA') }
            $abilitySections[$rawcode] = $abilitySection
            $affixEntry.globalAbilities = $rawcode
        }
        $abilitySections[$indicatorAbilityRawcode] = New-BossAffixIndicatorAbilitySection `
            $indicatorAbilityRawcode `
            $indicatorBuffRawcode `
            ([string]$definition.name) `
            ([string]$definition.description)
        $affixes[$affixId] = $affixEntry
    }

    $expectedGeneratedCount = ($unitSpecificAffixCount * $baseRawcodes.Count) + $globalAffixCount
    $expectedAbilityCount = $expectedGeneratedCount + $expectedKinds.Count
    if ($abilitySections.Count -ne $expectedAbilityCount -or $rawcodeIndex -ne $expectedGeneratedCount -or $expectedGeneratedCount -ne 83) {
        throw "Boss 词缀技能生成数量异常：技能=$($abilitySections.Count)，索引=$rawcodeIndex"
    }
    return [ordered]@{
        luaData = [ordered]@{
            version = 1
            affixes = $affixes
        }
        abilitySections = $abilitySections
    }
}

function Apply-CombatUnitTypeOverrides {
    param([Parameter(Mandatory = $true)][object]$UnitTable)

    # 项目统一使用英雄攻击/英雄护甲，避免原生普通、穿刺、攻城与轻/中/重甲克制表改变数值平衡。
    # 注意：atktype1 才是攻击类型；weapTp1 是武器表现类型，不能写成 hero。
    # S0M1 等商店单位不属于战斗单位，保留其模板类型；u0W1 是战斗召唤物，纳入统一规则。
    foreach ($rawcode in $UnitTable.Sections.Keys) {
        $isCombatUnit = (
            $rawcode -in @('u0W1', 'u0E1') -or
            $rawcode -in @('G0M1', 'X0M1') -or
            $rawcode -eq 'T0D0' -or
            $UnitTable.Sections[$rawcode].Contains('baseUnitId') -or
            $rawcode -match '^H[0-9A-Z]{3}$' -or
            $rawcode -match '^[NEB][0-9A-Z]{3}$'
        )
        if (-not $isCombatUnit) { continue }
        $UnitTable.Sections[$rawcode]['atktype1'] = 'hero'
        $UnitTable.Sections[$rawcode]['defType'] = 'hero'
        if ($UnitTable.Sections[$rawcode].Contains('baseUnitId')) {
            # 奖励和装备由 Lua 从最终变体行结算，关闭物编原生经验、赏金和掉落，避免重复发放。
            foreach ($field in @('points', 'bountydice', 'bountysides', 'bountyplus', 'dropItems')) {
                $UnitTable.Sections[$rawcode][$field] = 0
            }
        }
    }
}

function Assert-CombatUnitTypes {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Units)

    foreach ($rawcode in $Units.Keys) {
        $isCombatUnit = (
            $rawcode -in @('u0W1', 'u0E1') -or
            $rawcode -in @('G0M1', 'X0M1') -or
            $rawcode -eq 'T0D0' -or
            $Units[$rawcode].Contains('baseUnitId') -or
            $rawcode -match '^H[0-9A-Z]{3}$' -or
            $rawcode -match '^[NEB][0-9A-Z]{3}$'
        )
        if (-not $isCombatUnit) { continue }
        if (-not $Units[$rawcode].Contains('atktype1') -or
            -not $Units[$rawcode].Contains('defType') -or
            [string]$Units[$rawcode]['atktype1'] -ne 'hero' -or
            [string]$Units[$rawcode]['defType'] -ne 'hero') {
            throw "战斗单位攻击/护甲类型必须为 hero：$rawcode"
        }
    }
}

function Apply-RoguelikeObjectOverrides {
    param(
        [Parameter(Mandatory = $true)][object]$UnitTable,
        [Parameter(Mandatory = $true)][object]$AbilityTable
    )

    # 肉鸽 Excel 写入依赖由 Codex 工作区提供；当前运行时缺少 @oai/artifact-tool。
    # 先在生成器中集中声明首版必须的物编壳，保证 generate_lua_config.bat 不会
    # 覆盖掉 Lua 技能运行时依赖。依赖恢复后由 roguelike.xlsx 生成同一结构。
    foreach ($rawcode in @('A0W1', 'A0W2', 'A0W3')) {
        if (-not $AbilityTable.Sections.Contains($rawcode)) {
            throw "肉鸽技能物编缺失：$rawcode"
        }
    }

    $AbilityTable.Sections['A0W1']['DataA'] = @(0, 0, 0)

    $blink = $AbilityTable.Sections['A0W2']
    $blink['_parent'] = 'ANcl'
    $blink['Rng'] = @(1000, 1000, 1000)
    $blink['DataA'] = @(0, 0, 0)
    $blink['DataB'] = @(2, 2, 2)
    $blink['DataC'] = @(0, 0, 0)
    $blink['DataD'] = @(0, 0, 0)
    $blink['DataE'] = @(0, 0, 0)
    $blink['DataF'] = @('blink', 'blink', 'blink')

    $AbilityTable.Sections['A0W3']['DataA'] = @(0, 0)
    $AbilityTable.Sections['A0W3']['DataB'] = @(0, 0)
    $AbilityTable.Sections['A0W3']['Ubertip'] = '攻击时叠加齐天战意并提高暴击概率。层数、持续时间与暴击伤害由 Lua 结算。'
    $AbilityTable.Sections['A0W3']['Researchubertip'] = '攻击时叠加齐天战意并提高暴击概率。层数、持续时间与暴击伤害由 Lua 结算。'

    foreach ($rawcode in @('A0N1', 'A0N2', 'A0B1', 'A0E1')) {
        if (-not $AbilityTable.Sections.Contains($rawcode)) { throw "伤害技能物编缺失：$rawcode" }
        $AbilityTable.Sections[$rawcode]['DataA'] = @(0, 0, 0)
    }
    foreach ($rawcode in @('A0B4')) {
        if (-not $AbilityTable.Sections.Contains($rawcode)) { throw "被动伤害技能物编缺失：$rawcode" }
        $AbilityTable.Sections[$rawcode]['DataA'] = @(0, 0)
        $AbilityTable.Sections[$rawcode]['DataB'] = @(0, 0)
        if ($AbilityTable.Sections[$rawcode].Contains('DataC')) { $AbilityTable.Sections[$rawcode]['DataC'] = @(0, 0) }
    }
    foreach ($rawcode in @('A0N1', 'A0N2', 'A0N3', 'A0N4')) {
        if (-not $AbilityTable.Sections.Contains($rawcode)) { throw "后羿技能物编缺失：$rawcode" }
    }
    $AbilityTable.Sections['A0N1']['_parent'] = 'AOsh'
    # AOsh inherits ShockwaveMissile.mdl. Q only uses its point-target cast shell;
    # its visible projectile is the Lua-driven u0H2 ExplosiveBolt.
    $AbilityTable.Sections['A0N1']['Missileart'] = ''
    $AbilityTable.Sections['A0N1']['DataA'] = @(0, 0, 0)
    $AbilityTable.Sections['A0N2']['_parent'] = 'ANcl'
    foreach ($field in @('DataA', 'DataD', 'DataE')) { $AbilityTable.Sections['A0N2'][$field] = @(0, 0, 0) }
    $AbilityTable.Sections['A0N2']['DataF'] = @('deathcoil', 'deathcoil', 'deathcoil')
    $AbilityTable.Sections['A0N2']['Order'] = 'deathcoil'
    $AbilityTable.Sections['A0N3']['_parent'] = 'AOcr'
    foreach ($field in @('DataA', 'DataB', 'DataC')) { $AbilityTable.Sections['A0N3'][$field] = @(0, 0, 0) }
    $AbilityTable.Sections['A0N4']['_parent'] = 'ANcl'
    foreach ($field in @('DataA', 'DataD', 'DataE')) { $AbilityTable.Sections['A0N4'][$field] = @(0, 0, 0) }
    $AbilityTable.Sections['A0N4']['DataF'] = @('carrionswarm', 'carrionswarm', 'carrionswarm')
    $AbilityTable.Sections['A0N4']['Order'] = 'carrionswarm'
    foreach ($rawcode in @('A0E3', 'A0E4')) {
        if (-not $AbilityTable.Sections.Contains($rawcode)) { throw "阿尔萨斯技能物编缺失：$rawcode" }
    }
    $AbilityTable.Sections['A0E3']['DataA'] = @(0, 0, 0)
    $AbilityTable.Sections['A0E4']['DataA'] = @(0, 0)
    $AbilityTable.Sections['A0E4']['Ubertip'] = '指定区域召唤食尸鬼协战。冷却：<A0E4,Cool1> / <A0E4,Cool2> 秒；耗魔：<A0E4,Cost1> / <A0E4,Cost2>。军团存在时再次按 R 可献祭最近的一只食尸鬼并恢复生命；献祭治疗受本次召唤的总量上限约束。'
    $AbilityTable.Sections['A0E4']['Researchubertip'] = '指定区域召唤食尸鬼协战。冷却：<A0E4,Cool1> / <A0E4,Cool2> 秒；耗魔：<A0E4,Cost1> / <A0E4,Cost2>。军团存在时再次按 R 可献祭最近的一只食尸鬼并恢复生命。'
    # A0E2 and A0E4 are both point-target Channel spells. They must not share
    # the same base order ID or Warcraft may dispatch the click to the other spell.
    $AbilityTable.Sections['A0E4']['DataF'] = @('carrionswarm', 'carrionswarm')
    $AbilityTable.Sections['A0E4']['Order'] = 'carrionswarm'

    # Frostmourne is resolved by Lua as a passive attack proc. Use Warcraft's
    # hero passive base so the learned skill keeps a command-card button, while
    # zeroing its native critical-strike data and overriding all visible text.
    $AbilityTable.Sections['A0E3']['_parent'] = 'AOcr'
    $AbilityTable.Sections['A0E3']['DataA'] = @(0, 0, 0)
    $AbilityTable.Sections['A0E3']['DataB'] = @(0, 0, 0)
    $AbilityTable.Sections['A0E3']['DataC'] = @(0, 0, 0)
    $AbilityTable.Sections['A0E3']['Name'] = '霜之哀伤·饥渴'
    $AbilityTable.Sections['A0E3']['Tip'] = '霜之哀伤·饥渴(|cffffcc00E|r)'
    $AbilityTable.Sections['A0E3']['Ubertip'] = '普通攻击积攒魂魄，最多 5 层；6 秒未攻击则消退。满层后的下一次攻击触发强化斩击。当前层数显示在技能图标旁，并可在 Buff 栏看到状态图标。'
    $AbilityTable.Sections['A0E3']['Researchtip'] = '学习霜之哀伤·饥渴(|cffffcc00E|r) - [等级 %d]'
    $AbilityTable.Sections['A0E3']['Researchubertip'] = '普通攻击积攒魂魄，最多 5 层；6 秒未攻击则消退。满层后的下一次攻击触发强化斩击。'
    $AbilityTable.Sections['A0E3']['Art'] = 'war3mapImage\selectHero\skills\a0e3.blp'
    $AbilityTable.Sections['A0E3']['ResearchArt'] = 'war3mapImage\selectHero\skills\a0e3.blp'
    $AbilityTable.Sections['R0W3'] = [ordered]@{
        _parent = 'AOae'
        Name = '齐天战意状态'
        hero = 0
        item = 1
        levels = 1
        Buttonpos_1 = 0
        Buttonpos_2 = -11
        DataA = @(0)
        DataB = @(0)
        Area = @(1)
        BuffID = @('B0W1')
    }
    $AbilityTable.Sections['R0E3'] = [ordered]@{
        _parent = 'AOae'
        Name = '霜之哀伤魂魄状态'
        hero = 0
        item = 1
        levels = 1
        Buttonpos_1 = 0
        Buttonpos_2 = -11
        DataA = @(0)
        DataB = @(0)
        Area = @(1)
        BuffID = @('B0E3')
    }
    $AbilityTable.Sections['R0E4'] = [ordered]@{
        _parent = 'ANcl'
        Name = '亡灵大军·血肉献祭'
        Tip = '血肉献祭(|cffffcc00R|r)'
        Ubertip = '献祭离阿尔萨斯最近的一只食尸鬼，恢复生命。冷却：<R0E4,Cool1> 秒。'
        Researchtip = '学习亡灵大军(|cffffcc00R|r) - [等级 %d]'
        Researchubertip = '献祭离阿尔萨斯最近的一只食尸鬼，恢复生命。'
        Hotkey = 'R'
        Researchhotkey = 'R'
        Buttonpos_1 = 3
        Buttonpos_2 = 2
        Researchbuttonpos_1 = 3
        Researchbuttonpos_2 = 2
        hero = 0
        item = 0
        levels = 2
        reqLevel = 4
        levelSkip = 4
        Cool = @(1, 1)
        Cost = @(0, 0)
        Rng = @(0, 0)
        Area = @(0, 0)
        DataA = @(0, 0)
        DataB = @(0, 0)
        DataC = @(0, 0)
        DataD = @(0, 0)
        DataE = @(0, 0)
        DataF = @('roar', 'roar')
        Order = 'roar'
        Art = 'war3mapImage\selectHero\skills\a0e4.blp'
    }
    $AbilityTable.Sections['R0H1'] = [ordered]@{
        _parent = 'ACcr'
        Name = '日灼迟滞'
        Tip = '日灼迟滞'
        Ubertip = '金乌灼痕爆发造成的短暂减速。'
        hero = 0
        item = 0
        levels = 1
        Cool = @(0)
        Cost = @(0)
        Rng = @(99999)
        Area = @(0)
        DataA = @(0)
        DataB = @(0)
        DataC = @(20)
        DataD = @(0)
        DataE = @(0)
        BuffID = @('B0N1')
        Dur = @(1)
        HeroDur = @(1)
        Order = 'cripple'
    }

    $UnitTable.Sections['u0W1'] = [ordered]@{
        _parent = 'ogru'
        Name = '猴兵'
        Tip = '猴兵'
        Ubertip = '由孙悟空的毫毛化身召唤，持续协助战斗。'
        file = 'units\orc\HeroBladeMaster\HeroBladeMaster'
        modelScale = 1
        HP = 400
        def = 2
        spd = 290
        collision = 16
        goldcost = 0
        lumbercost = 0
        abilList = ''
        cool1 = 2
        rangeN1 = 100
        weapsOn = 1
        dice1 = 0
        sides1 = 0
        dmgplus1 = 0
        bountydice = 0
        bountysides = 0
        bountyplus = 0
        goldRep = 0
        points = 0
        dropItems = 0
    }
    $UnitTable.Sections['u0H1'] = [ordered]@{
        _parent = 'hfoo'
        Name = '日灼施法马甲'
        Tip = '日灼施法马甲'
        Ubertip = '后羿金乌灼痕使用的隐藏减速施法单位。'
        HP = 1
        mana0 = 1000
        manaN = 1000
        def = 0
        spd = 0
        collision = 0
        goldcost = 0
        lumbercost = 0
        abilList = 'Aloc,R0H1'
        cool1 = 1
        rangeN1 = 0
        weapsOn = 0
        dice1 = 0
        sides1 = 0
        dmgplus1 = 0
        bountydice = 0
        bountysides = 0
        bountyplus = 0
        goldRep = 0
        points = 0
        dropItems = 0
        hideHeroBar = 1
        modelScale = 0.01
    }
    $UnitTable.Sections['u0H2'] = [ordered]@{
        _parent = 'hfoo'
        Name = '贯日箭视觉马甲'
        Tip = '贯日箭视觉马甲'
        Ubertip = '后羿贯日箭的移动特效载体。'
        file = 'war3mapModel\houyi_q_arrow.mdx'
        HP = 1
        mana0 = 0
        manaN = 0
        def = 0
        spd = 0
        collision = 0
        goldcost = 0
        lumbercost = 0
        abilList = 'Aloc'
        cool1 = 1
        rangeN1 = 0
        weapsOn = 0
        dice1 = 0
        sides1 = 0
        dmgplus1 = 0
        bountydice = 0
        bountysides = 0
        bountyplus = 0
        goldRep = 0
        points = 0
        dropItems = 0
        hideHeroBar = 1
        modelScale = 1
    }
}

function Format-SkillDamageLines {
    param(
        [Parameter(Mandatory = $true)][string]$AttributeId,
        [Parameter(Mandatory = $true)][object[]]$Multipliers,
        [Parameter(Mandatory = $true)][string]$Prefix
    )

    $attributeText = Get-DamageAttributeLabel $AttributeId
    $lines = New-Object System.Collections.Generic.List[string]
    for ($index = 0; $index -lt $Multipliers.Count; $index = $index + 1) {
        $lines.Add("$($index + 1)级造成 $(Format-TenthMultiplier ([int]$Multipliers[$index]))×${attributeText}的魔法伤害")
    }
    return "$Prefix：" + [string]::Join('；', $lines.ToArray()) + '。'
}

function Format-HundredthMultiplier {
    param([Parameter(Mandatory = $true)][int]$Value)
    return '{0}.{1:D2}' -f [math]::Floor($Value / 100), [math]::Abs($Value % 100)
}

function Format-TickDamageLines {
    param(
        [Parameter(Mandatory = $true)][string]$AttributeId,
        [Parameter(Mandatory = $true)][object[]]$Multipliers,
        [Parameter(Mandatory = $true)][int]$TickIntervalHundredths,
        [Parameter(Mandatory = $true)][int]$DurationHundredths
    )

    if ($TickIntervalHundredths -le 0 -or $DurationHundredths -le 0 -or $DurationHundredths % $TickIntervalHundredths -ne 0) {
        throw '持续伤害的间隔或持续时间无效'
    }
    $values = New-Object System.Collections.Generic.List[string]
    foreach ($multiplier in $Multipliers) {
        if ([int]$multiplier -le 0) { throw '持续伤害倍率必须为正整数百分位' }
        $values.Add((Format-HundredthMultiplier ([int]$multiplier)))
    }
    $levels = 1..$Multipliers.Count | ForEach-Object { [string]$_ }
    $interval = ([decimal]$TickIntervalHundredths / 100).ToString('0.##', [System.Globalization.CultureInfo]::InvariantCulture)
    $ticks = [int]($DurationHundredths / $TickIntervalHundredths)
    return "持续伤害：每 $interval 秒造成 $([string]::Join(' / ', $values.ToArray()))×$(Get-DamageAttributeLabel $AttributeId)的魔法伤害（对应 $([string]::Join(' / ', $levels)) 级），共 $ticks 次。"
}

function Apply-SkillFormulaTooltips {
    param(
        [Parameter(Mandatory = $true)][object]$RoguelikeData,
        [Parameter(Mandatory = $true)][object]$AbilityTable
    )

    $runtimeByHero = $RoguelikeData.lua.skillRuntime
    foreach ($hero in $runtimeByHero.Keys) {
        foreach ($skill in $runtimeByHero[$hero].Keys) {
            if (-not $AbilityTable.Sections.Contains($skill)) { continue }
            $runtime = $runtimeByHero[$hero][$skill]
            $formula = $null
            $attributeKey = $null
            $multiplierKey = $null
            $prefix = '伤害'
            if ($runtime.Contains('damageAttribute') -and $runtime.Contains('tickDamageMultiplierHundredth') -and $runtime.Contains('tickIntervalHundredths') -and $runtime.Contains('durationHundredths')) {
                $formula = Format-TickDamageLines ([string]$runtime['damageAttribute']) @($runtime['tickDamageMultiplierHundredth']) ([int]$runtime['tickIntervalHundredths']) ([int]$runtime['durationHundredths'])
            } elseif ($runtime.Contains('damageAttribute') -and $runtime.Contains('damageMultiplierTenth')) {
                $attributeKey = 'damageAttribute'
                $multiplierKey = 'damageMultiplierTenth'
            } elseif ($runtime.Contains('procDamageAttribute') -and $runtime.Contains('procDamageMultiplierTenth')) {
                $attributeKey = 'procDamageAttribute'
                $multiplierKey = 'procDamageMultiplierTenth'
                $prefix = '额外伤害'
            }
            if ($null -ne $formula) {
                $formula = [string]$formula
            } elseif ($null -ne $attributeKey) {
                $formula = Format-SkillDamageLines ([string]$runtime[$attributeKey]) @($runtime[$multiplierKey]) $prefix
                if ($hero -eq 'H0N0' -and $skill -eq 'A0N4' -and $runtime.Contains('finalDamageMultiplierTenth')) {
                    $formula += '|n第九箭：' + (Format-SkillDamageLines ([string]$runtime[$attributeKey]) @($runtime['finalDamageMultiplierTenth']) '中心坠日伤害')
                }
            } elseif ($runtime.Contains('summonDamageAttribute') -and $runtime.Contains('summonDamageMultiplierTenth')) {
                $formula = "猴兵每次攻击造成 $(Format-TenthMultiplier ([int]$runtime['summonDamageMultiplierTenth']))×$(Get-DamageAttributeLabel ([string]$runtime['summonDamageAttribute']))的物理伤害。"
            } elseif ($runtime.Contains('summonDamageAttribute') -and $runtime.Contains('summonDamageMultiplierHundredth')) {
                $formula = "食尸鬼每次攻击造成 $(Format-HundredthMultiplier ([int]$runtime['summonDamageMultiplierHundredth']))×$(Get-DamageAttributeLabel ([string]$runtime['summonDamageAttribute']))的物理伤害。"
            } else {
                continue
            }
            foreach ($field in @('Ubertip', 'Researchubertip')) {
                $original = [string]$AbilityTable.Sections[$skill][$field]
                $AbilityTable.Sections[$skill][$field] = $original + '|n' + $formula
            }
        }
    }
}
function Get-RoguelikeRequiredField {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Row,
        [Parameter(Mandatory = $true)][string]$Field,
        [Parameter(Mandatory = $true)][string]$Context
    )
    if (-not $Row.Contains($Field) -or $null -eq $Row[$Field]) {
        throw "肉鸽配置缺少字段：$Context / $Field"
    }
    return $Row[$Field]
}

function New-RoguelikeConfig {
    param(
        [Parameter(Mandatory = $true)][object]$SettingsTable,
        [Parameter(Mandatory = $true)][object]$EffectsTable,
        [Parameter(Mandatory = $true)][object]$RuntimeTable,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Units,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Abilities
    )

    if ($SettingsTable.Sections.Count -ne 1 -or -not $SettingsTable.Sections.Contains('DEFAULT')) {
        throw 'roguelike.xlsx/settings 必须恰有一行 settingId=DEFAULT'
    }
    $settingsSource = $SettingsTable.Sections['DEFAULT']
    $settings = [ordered]@{}
    foreach ($field in @('hostPlayerId', 'maxPlayerCount', 'firstRewardLevel', 'rewardLevelInterval', 'choiceCount', 'durationSeconds', 'freeRefreshPerOffer', 'maxEffectLevel')) {
        $settings[$field] = [int](Get-RoguelikeRequiredField $settingsSource $field 'settings/DEFAULT')
    }
    if ($settings.firstRewardLevel -lt 1 -or $settings.rewardLevelInterval -lt 1 -or $settings.choiceCount -ne 3 -or $settings.maxEffectLevel -ne 3 -or $settings.durationSeconds -lt 1 -or $settings.freeRefreshPerOffer -lt 0) {
        throw 'roguelike.xlsx/settings 数值无效'
    }

    $effects = [ordered]@{}
    $skillIdsByHero = [ordered]@{}
    $commonIds = New-Object System.Collections.Generic.List[string]
    $skillCounts = @{}
    foreach ($effectId in $EffectsTable.Sections.Keys) {
        $source = $EffectsTable.Sections[$effectId]
        if ($source.Contains('enabled') -and [int]$source.enabled -eq 0) { continue }
        $type = [string](Get-RoguelikeRequiredField $source 'type' "effects/$effectId")
        $values = @(
            [int](Get-RoguelikeRequiredField $source 'value1' "effects/$effectId"),
            [int](Get-RoguelikeRequiredField $source 'value2' "effects/$effectId"),
            [int](Get-RoguelikeRequiredField $source 'value3' "effects/$effectId")
        )
        $effect = [ordered]@{
            effectId = $effectId
            type = $type
            name = [string](Get-RoguelikeRequiredField $source 'name' "effects/$effectId")
            description = [string](Get-RoguelikeRequiredField $source 'description' "effects/$effectId")
            icon = [string](Get-RoguelikeRequiredField $source 'icon' "effects/$effectId")
            modifierKey = [string](Get-RoguelikeRequiredField $source 'modifierKey' "effects/$effectId")
            operation = [string](Get-RoguelikeRequiredField $source 'operation' "effects/$effectId")
            values = $values
            maxLevel = [int](Get-RoguelikeRequiredField $source 'maxLevel' "effects/$effectId")
            weight = [int](Get-RoguelikeRequiredField $source 'weight' "effects/$effectId")
        }
        if ($effect.maxLevel -lt 1 -or $effect.maxLevel -gt 3 -or $effect.weight -le 0) {
            throw "肉鸽效果等级或权重无效：$effectId"
        }
        if ($type -eq 'Skill') {
            $hero = [string](Get-RoguelikeRequiredField $source 'hero' "effects/$effectId")
            $skill = [string](Get-RoguelikeRequiredField $source 'skill' "effects/$effectId")
            if (-not $Units.Contains($hero) -or -not $Abilities.Contains($skill)) {
                throw "肉鸽效果引用不存在的英雄或技能：$effectId"
            }
            $effect.hero = $hero
            $effect.skill = $skill
            if (-not $skillIdsByHero.Contains($hero)) {
                $skillIdsByHero[$hero] = New-Object System.Collections.Generic.List[string]
            }
            $skillIdsByHero[$hero].Add($effectId)
            $countKey = "$hero`:$skill"
            if ($skillCounts.ContainsKey($countKey)) {
                $skillCounts[$countKey] = [int]$skillCounts[$countKey] + 1
            } else {
                $skillCounts[$countKey] = 1
            }
        } elseif ($type -eq 'Common') {
            $commonIds.Add($effectId)
        } else {
            throw "肉鸽效果类型无效：$effectId"
        }
        if ($source.Contains('prerequisiteId') -and -not [string]::IsNullOrWhiteSpace([string]$source.prerequisiteId)) {
            $effect.prerequisiteId = [string]$source.prerequisiteId
        }
        if ($source.Contains('exclusiveGroup') -and -not [string]::IsNullOrWhiteSpace([string]$source.exclusiveGroup)) {
            $effect.exclusiveGroup = [string]$source.exclusiveGroup
        }
        $effects[$effectId] = $effect
    }
    foreach ($skill in @('A0W1', 'A0W2', 'A0W3', 'A0W4')) {
        if ([int]$skillCounts["H0W0`:$skill"] -ne 2) {
            throw "孙悟空每个技能必须恰有两个肉鸽效果：$skill"
        }
    }
    foreach ($skill in @('A0E1', 'A0E2', 'A0E3', 'A0E4')) {
        if ([int]$skillCounts["H0E0`:$skill"] -ne 2) {
            throw "阿尔萨斯每个技能必须恰有两个肉鸽效果：$skill"
        }
    }
    foreach ($skill in @('A0N1', 'A0N2', 'A0N3', 'A0N4')) {
        if ([int]$skillCounts["H0N0`:$skill"] -ne 2) {
            throw "后羿每个技能必须恰有两个肉鸽效果：$skill"
        }
    }
    $houyiQProjectileEffect = $effects['R_H_Q_TARGET']
    if ($null -eq $houyiQProjectileEffect -or $houyiQProjectileEffect.modifierKey -ne 'projectile_count_add' -or $houyiQProjectileEffect.maxLevel -ne 3 -or ((@($houyiQProjectileEffect.values) -join ',') -ne '1,2,3')) {
        throw '后羿 Q 分光箭肉鸽配置无效'
    }
    $houyiQRepeatEffect = $effects['R_H_Q_DAMAGE']
    if ($null -eq $houyiQRepeatEffect -or $houyiQRepeatEffect.modifierKey -ne 'repeat_count_add' -or $houyiQRepeatEffect.maxLevel -ne 2 -or ((@($houyiQRepeatEffect.values) -join ',') -ne '1,2,2')) {
        throw '后羿 Q 余晖复射肉鸽配置无效'
    }
    if ($commonIds.Count -ne 8) { throw "首版通用肉鸽必须恰有 8 个，实际=$($commonIds.Count)" }

    $skillRuntime = [ordered]@{}
    foreach ($runtimeId in $RuntimeTable.Sections.Keys) {
        $source = $RuntimeTable.Sections[$runtimeId]
        $hero = [string](Get-RoguelikeRequiredField $source 'heroRawcode' "skill_runtime/$runtimeId")
        $skill = [string](Get-RoguelikeRequiredField $source 'skillRawcode' "skill_runtime/$runtimeId")
        $key = [string](Get-RoguelikeRequiredField $source 'valueKey' "skill_runtime/$runtimeId")
        if (-not $skillRuntime.Contains($hero)) { $skillRuntime[$hero] = [ordered]@{} }
        if (-not $skillRuntime[$hero].Contains($skill)) { $skillRuntime[$hero][$skill] = [ordered]@{} }
        $hasText = $source.Contains('textValue') -and -not [string]::IsNullOrWhiteSpace([string]$source.textValue)
        $hasArray = $source.Contains('value1') -and $null -ne $source.value1
        if ($hasText) {
            $skillRuntime[$hero][$skill][$key] = [string]$source.textValue
        } elseif ($hasArray) {
            $values = New-Object System.Collections.Generic.List[int]
            foreach ($field in @('value1', 'value2', 'value3')) {
                if ($source.Contains($field) -and $null -ne $source[$field]) { $values.Add([int]$source[$field]) }
            }
            $skillRuntime[$hero][$skill][$key] = $values.ToArray()
        } else {
            $skillRuntime[$hero][$skill][$key] = [int](Get-RoguelikeRequiredField $source 'scalarValue' "skill_runtime/$runtimeId")
        }
    }

    # Q's visible arrow is Lua-driven. Keep its flight distance synchronized with
    # the three native casting ranges in ability.xlsx, which is the sole authoring surface.
    $houyiQNativeRanges = @($Abilities['A0N1']['Rng'])
    $houyiQLevelCount = [int]$Abilities['A0N1']['levels']
    if ($houyiQNativeRanges.Count -ne $houyiQLevelCount -or $houyiQLevelCount -ne 3) {
        throw '后羿 Q 原生射程等级数无效：H0N0/A0N1'
    }
    foreach ($range in $houyiQNativeRanges) {
        if ([int]$range -lt 1) { throw '后羿 Q 原生射程必须为正整数：H0N0/A0N1' }
    }
    $skillRuntime['H0N0']['A0N1']['range'] = @($houyiQNativeRanges | ForEach-Object { [int]$_ })

    $damageAttributes = @('primary')
    $formulaRequirements = @(
        @{ hero = 'H0W0'; skill = 'A0W1'; prefix = '' }, @{ hero = 'H0W0'; skill = 'A0W2'; prefix = '' },
        @{ hero = 'H0W0'; skill = 'A0W3'; prefix = 'proc' }, @{ hero = 'H0W0'; skill = 'A0W4'; prefix = 'summon' },
        @{ hero = 'H0N0'; skill = 'A0N1'; prefix = '' }, @{ hero = 'H0N0'; skill = 'A0N2'; prefix = '' },
        @{ hero = 'H0N0'; skill = 'A0N3'; prefix = 'proc' }, @{ hero = 'H0N0'; skill = 'A0N4'; prefix = '' },
        @{ hero = 'H0B0'; skill = 'A0B1'; prefix = '' },
        @{ hero = 'H0B0'; skill = 'A0B4'; prefix = 'proc' }, @{ hero = 'H0E0'; skill = 'A0E1'; prefix = '' },
        @{ hero = 'H0E0'; skill = 'A0E2'; prefix = ''; multiplierKey = 'tickDamageMultiplierHundredth'; tickDamage = $true }, @{ hero = 'H0E0'; skill = 'A0E3'; prefix = 'proc' },
        @{ hero = 'H0E0'; skill = 'A0E4'; prefix = 'summon'; multiplierKey = 'summonDamageMultiplierHundredth'; multiplierScale = 100 }
    )
    foreach ($requirement in $formulaRequirements) {
        $hero = $requirement.hero
        $skill = $requirement.skill
        if (-not $skillRuntime.Contains($hero) -or -not $skillRuntime[$hero].Contains($skill)) {
            throw "技能伤害公式缺失：$hero/$skill"
        }
        $runtime = $skillRuntime[$hero][$skill]
        if ($requirement.ContainsKey('tickDamage')) {
            foreach ($key in @('damageAttribute', 'tickDamageMultiplierHundredth', 'durationHundredths', 'tickIntervalHundredths', 'area', 'range', 'extraTornadoRingRadius', 'boltRange', 'boltSpeed', 'boltCollisionRadius', 'boltDamageAttribute', 'boltDamageMultiplierTenth')) {
                if (-not $runtime.Contains($key)) { throw "冰龙卷运行时字段缺失：$hero/$skill/$key" }
            }
            if ([string]$runtime['damageAttribute'] -ne 'primary' -or [string]$runtime['boltDamageAttribute'] -ne 'primary') {
                throw "冰龙卷伤害属性必须为主属性：$hero/$skill"
            }
            $multipliers = @($runtime['tickDamageMultiplierHundredth'])
            $levelCount = [int]$Abilities[$skill].levels
            if ($multipliers.Count -ne $levelCount) { throw "冰龙卷每跳伤害等级数无效：$hero/$skill" }
            foreach ($multiplier in $multipliers) {
                if ([int]$multiplier -le 0) { throw "冰龙卷每跳伤害必须为正整数百分位：$hero/$skill" }
            }
            $duration = [int]$runtime['durationHundredths']
            $interval = [int]$runtime['tickIntervalHundredths']
            if ($duration -le 0 -or $interval -le 0 -or $duration % $interval -ne 0 -or [int]($duration / $interval) -ne 6) {
                throw "冰龙卷持续伤害必须为 0.5 秒一次、共 6 次：$hero/$skill"
            }
            foreach ($key in @('area', 'range', 'extraTornadoRingRadius', 'boltRange', 'boltSpeed', 'boltCollisionRadius', 'boltDamageMultiplierTenth')) {
                if ([int]$runtime[$key] -le 0) { throw "冰龙卷运行时字段必须为正整数：$hero/$skill/$key" }
            }
            continue
        }
        if ($runtime.Contains('damage')) { throw "技能结算禁止保留固定 damage 数组：$hero/$skill" }
        $attributeKey = $requirement.prefix + 'DamageAttribute'
        $multiplierKey = $requirement.prefix + 'DamageMultiplierTenth'
        if ($requirement.ContainsKey('multiplierKey')) { $multiplierKey = [string]$requirement.multiplierKey }
        if ($requirement.prefix -eq '') {
            $attributeKey = 'damageAttribute'
            $multiplierKey = 'damageMultiplierTenth'
        }
        if (-not $runtime.Contains($attributeKey) -or -not $runtime.Contains($multiplierKey)) {
            throw "技能伤害公式字段缺失：$hero/$skill"
        }
        $configuredAttribute = [string]$runtime[$attributeKey]
        if ($configuredAttribute -in @('strength', 'agility', 'intelligence')) {
            # 兼容当前尚未补齐 Excel 的旧行：生成阶段规范化为 primary，后续 Excel
            # 维护必须直接填写 primary，禁止再引入固定三维作为英雄技能伤害来源。
            Write-Warning "旧技能伤害属性将规范化为 primary：$hero/$skill/$attributeKey/$configuredAttribute"
            $runtime[$attributeKey] = 'primary'
            $configuredAttribute = 'primary'
        }
        if ($damageAttributes -notcontains $configuredAttribute) {
            throw "技能伤害属性 ID 无效：$hero/$skill/$attributeKey"
        }
        $multipliers = $runtime[$multiplierKey]
        $hundredthMultiplier = $requirement.ContainsKey('multiplierScale') -and [int]$requirement.multiplierScale -eq 100
        if ($requirement.prefix -eq 'summon' -and -not $hundredthMultiplier) {
            if ($multipliers -is [System.Collections.IEnumerable] -or [int]$multipliers -le 0) {
                throw "召唤伤害倍率必须为正整数十倍定点：$hero/$skill"
            }
            continue
        }
        if ($hundredthMultiplier) {
            if ($multipliers -is [System.Collections.IEnumerable] -or [int]$multipliers -le 0) {
                throw "食尸鬼伤害倍率必须为正整数百分位：$hero/$skill"
            }
            continue
        }
        $levelCount = [int]$Abilities[$skill].levels
        if ($multipliers -isnot [System.Collections.IEnumerable] -or @($multipliers).Count -ne $levelCount) {
            throw "技能伤害倍率等级数无效：$hero/$skill"
        }
        foreach ($multiplier in @($multipliers)) {
            if ([int]$multiplier -le 0) { throw "技能伤害倍率必须为正整数十倍定点：$hero/$skill" }
        }
    }
    $houyiRuntime = $skillRuntime['H0N0']
    foreach ($requirement in @(
        @{ skill = 'A0N1'; keys = @('range', 'damageRadius', 'projectileSpeed') },
        @{ skill = 'A0N2'; keys = @('range', 'projectileCount', 'projectileIntervalHundredths', 'bounceRange', 'bounceCount') },
        @{ skill = 'A0N3'; keys = @('maxStacks', 'duration', 'procArea', 'slowPercent', 'slowDurationHundredths', 'itemProcDamagePercent', 'itemProcAreaAdd') },
        @{ skill = 'A0N4'; keys = @('finalDamageMultiplierTenth', 'area', 'outerRadius', 'projectileCount', 'normalArea', 'finalArea', 'durationHundredths') }
    )) {
        if ($null -eq $houyiRuntime -or -not $houyiRuntime.Contains($requirement.skill)) {
            throw "后羿技能运行时配置缺失：H0N0/$($requirement.skill)"
        }
        foreach ($key in $requirement.keys) {
            if (-not $houyiRuntime[$requirement.skill].Contains($key)) {
                throw "后羿技能运行时字段缺失：H0N0/$($requirement.skill)/$key"
            }
        }
    }
    $houyiFinalMultipliers = $houyiRuntime['A0N4']['finalDamageMultiplierTenth']
    $houyiFinalCount = @($houyiFinalMultipliers).Count
    $houyiLevelCount = [int]$Abilities['A0N4']['levels']
    if ($houyiFinalMultipliers -isnot [System.Collections.IEnumerable] -or $houyiFinalCount -ne $houyiLevelCount) {
        throw '后羿第九箭伤害倍率等级数无效：H0N0/A0N4'
    }
    foreach ($multiplier in @($houyiFinalMultipliers)) {
        if ([int]$multiplier -le 0) { throw '后羿第九箭伤害倍率必须为正整数十倍定点：H0N0/A0N4' }
    }
    foreach ($hero in @($skillIdsByHero.Keys)) { $skillIdsByHero[$hero] = $skillIdsByHero[$hero].ToArray() }

    $lni = [ordered]@{ settings = $settings }
    foreach ($effectId in $effects.Keys) { $lni[$effectId] = $effects[$effectId] }
    return [pscustomobject]@{
        lni = $lni
        lua = [ordered]@{
            version = 1
            settings = $settings
            effects = $effects
            skillIdsByHero = $skillIdsByHero
            commonIds = $commonIds.ToArray()
            skillRuntime = $skillRuntime
        }
    }
}

function New-AttributeConfig {
    param([Parameter(Mandatory = $true)][object]$AttributeTable)

    $expectedProjections = [ordered]@{
        strength = 'hero_strength'
        agility = 'hero_agility'
        intelligence = 'hero_intelligence'
        attack = 'hidden_attack'
        health = 'hidden_health'
        armor = 'hidden_armor'
        moveSpeed = 'native_move_speed'
        attack_speed_percent = 'derived_attack_speed_percent'
        basic_attack_bonus_percent = 'derived_basic_attack_bonus_percent'
        health_amplification_percent = 'derived_health_amplification_percent'
    }
    $defaults = [ordered]@{
        attack_speed_percent = [ordered]@{
            displayOrder = 125; displayFormat = 'percent'; projection = 'derived_attack_speed_percent'; group = '战斗属性'; name = '攻击速度'
        }
        basic_attack_bonus_percent = [ordered]@{
            displayOrder = 135; displayFormat = 'percent'; projection = 'derived_basic_attack_bonus_percent'; group = '战斗属性'; name = '普攻加成'
        }
        health_amplification_percent = [ordered]@{
            displayOrder = 140; displayFormat = 'percent'; projection = 'derived_health_amplification_percent'; group = '战斗属性'; name = '生命增幅'
        }
    }
    foreach ($attributeId in $defaults.Keys) {
        if (-not $AttributeTable.Sections.Contains($attributeId)) {
            # 旧 Excel 缺少新增行时输出零值定义，确保生成器可重复执行；新工作簿应补齐同名行。
            $AttributeTable.Sections[$attributeId] = $defaults[$attributeId]
        }
    }
    if ($AttributeTable.Sections.Count -ne $expectedProjections.Count) {
        throw "roguelike.xlsx/attributes 必须恰有 $($expectedProjections.Count) 项，实际=$($AttributeTable.Sections.Count)"
    }

    $attributes = [ordered]@{}
    $seenOrders = @{}
    foreach ($attributeId in $AttributeTable.Sections.Keys) {
        if (-not $expectedProjections.Contains($attributeId)) {
            throw "roguelike.xlsx/attributes 包含首版未支持的属性：$attributeId"
        }
        $source = $AttributeTable.Sections[$attributeId]
        $displayOrder = [int](Get-RoguelikeRequiredField $source 'displayOrder' "attributes/$attributeId")
        $displayFormat = [string](Get-RoguelikeRequiredField $source 'displayFormat' "attributes/$attributeId")
        $projection = [string](Get-RoguelikeRequiredField $source 'projection' "attributes/$attributeId")
        $group = [string](Get-RoguelikeRequiredField $source 'group' "attributes/$attributeId")
        $name = [string](Get-RoguelikeRequiredField $source 'name' "attributes/$attributeId")
        if ([string]::IsNullOrWhiteSpace($group) -or [string]::IsNullOrWhiteSpace($name)) {
            throw "roguelike.xlsx/attributes 缺少显示分组或名称：$attributeId"
        }
        if ($displayOrder -le 0 -or $seenOrders.ContainsKey($displayOrder)) {
            throw "roguelike.xlsx/attributes 显示排序必须为不重复正整数：$attributeId"
        }
        if ($displayFormat -notin @('integer', 'percent')) {
            throw "roguelike.xlsx/attributes 显示格式无效：$attributeId"
        }
        if ($projection -ne $expectedProjections[$attributeId]) {
            throw "roguelike.xlsx/attributes 投影类型无效：$attributeId / $projection"
        }
        $seenOrders[$displayOrder] = $true
        $attributes[$attributeId] = [ordered]@{
            attributeId = $attributeId
            group = $group
            name = $name
            displayOrder = $displayOrder
            displayFormat = $displayFormat
            projection = $projection
        }
    }
    foreach ($attributeId in $expectedProjections.Keys) {
        if (-not $attributes.Contains($attributeId)) {
            throw "roguelike.xlsx/attributes 缺少首版属性：$attributeId"
        }
    }
    return [ordered]@{
        version = 1
        attributes = $attributes
    }
}

try {
    $projectRoot = [System.IO.Path]::GetFullPath($Root)
    $excelDirectory = [System.IO.Path]::GetFullPath($ExcelRoot)
    $tableDirectory = Join-Path $projectRoot 'table'
    $mapDirectory = Join-Path $projectRoot 'map'
    $projectDirectory = Split-Path -Parent $projectRoot
    $slkDirectory = Join-Path $projectDirectory 'slk'
    $configDirectory = [System.IO.Path]::GetFullPath($LuaRoot)

    if (-not (Test-Path -LiteralPath $projectRoot -PathType Container)) {
        throw "找不到 w2l 项目根目录：$projectRoot"
    }
    if (-not (Test-Path -LiteralPath $excelDirectory -PathType Container)) {
        throw "找不到 Excel 配置目录：$excelDirectory"
    }
    $embeddedExcelDirectory = Join-Path $projectRoot 'excelCfg'
    if (Test-Path -LiteralPath $embeddedExcelDirectory) {
        throw "excelCfg 必须位于项目根目录，不能放入 w2l Build 目录：$embeddedExcelDirectory"
    }

    $unitTable = Read-ExcelObjectTable (Join-Path $excelDirectory 'unit.xlsx') 'unit' 'unitId'
    $abilityTable = Read-ExcelObjectTable (Join-Path $excelDirectory 'ability.xlsx') 'ability' 'abilityId'
    $itemTable = Read-ExcelObjectTable (Join-Path $excelDirectory 'item.xlsx') 'item' 'itemId'
    $buffTable = Read-ExcelObjectTable (Join-Path $excelDirectory 'buff.xlsx') 'buff' 'buffId'
    $bossAffixTable = Read-ExcelObjectTable (Join-Path $excelDirectory 'boss_affix.xlsx') 'affix' 'affixId'
    $experiencePath = Join-Path $excelDirectory 'experience.xlsx'
    $experienceSettingsTable = Read-ExcelObjectTable $experiencePath 'settings' 'settingId'
    $experienceLevelTable = Read-ExcelObjectTable $experiencePath 'levels' 'levelId'
    $goldTablePath = Join-Path $excelDirectory 'gold.xlsx'
    $goldSettingsTable = Read-ExcelObjectTable $goldTablePath 'settings' 'settingId'
    $mysteryShopPath = Join-Path $excelDirectory 'mystery_shop.xlsx'
    $mysteryShopLocationsTable = Read-ExcelObjectTable $mysteryShopPath 'shops' 'shopId'
    $mysteryShopStockTable = Read-ExcelObjectTable $mysteryShopPath 'stock' 'stockId'
    $mysteryShopConsumablePath = Join-Path $excelDirectory 'mystery_shop_consumables.ini'
    $mysteryShopConsumableTable = Read-SimpleObjectTable $mysteryShopConsumablePath
    $equipmentPath = Join-Path $excelDirectory 'equipment.xlsx'
    $equipmentLevelTable = Read-ExcelObjectTable $equipmentPath 'level' 'levelId'
    $equipmentTemplateTable = Read-ExcelObjectTable $equipmentPath 'template' 'templateId'
    $equipmentAutoTable = Read-ExcelObjectTable $equipmentPath 'auto' 'autoSkillId'
    $equipmentPassiveTable = Read-ExcelObjectTable $equipmentPath 'passive' 'passiveId'
    $equipmentComboTable = Read-ExcelObjectTable $equipmentPath 'combo' 'comboPieceId'

    Apply-RoguelikeObjectOverrides $unitTable $abilityTable
    # 肉鸽覆盖会追加 u0W1 召唤物，因此必须在所有单位覆盖完成后统一写入战斗类型。
    Apply-CombatUnitTypeOverrides $unitTable
    Validate-MonsterExperience $unitTable.Sections

    # slotType 是旧版“装备部位”字段。Warcraft 原生物品栏没有部位限制，
    # 装备类型由模板 ID 与套装部件 ID 表达；兼容保留旧 Excel 列时也不得输出该字段。
    foreach ($rawcode in @($itemTable.Sections.Keys)) {
        [void]$itemTable.Sections[$rawcode].Remove('slotType')
    }
    foreach ($templateId in @($equipmentTemplateTable.Sections.Keys)) {
        [void]$equipmentTemplateTable.Sections[$templateId].Remove('slotType')
    }
    foreach ($comboPieceId in @($equipmentComboTable.Sections.Keys)) {
        [void]$equipmentComboTable.Sections[$comboPieceId].Remove('slotType')
    }

    $mysteryShopData = New-MysteryShopConfig $mysteryShopLocationsTable $mysteryShopStockTable $mysteryShopConsumableTable $unitTable.Sections $itemTable.Sections $abilityTable.Sections
    $units = ConvertTo-ObjectConfig $unitTable.Sections
    Assert-CombatUnitTypes $units
    foreach ($rawcode in @($units.Keys)) {
        $unit = $units[$rawcode]
        if (-not $unit.Contains('Primary')) { continue }
        if (-not $unit.Contains('initialAttackSpeedPercent')) {
            throw "英雄缺少初始攻速配置：$rawcode.initialAttackSpeedPercent"
        }
        $initialAttackSpeedPercent = [int]$unit.initialAttackSpeedPercent
        if ($initialAttackSpeedPercent -lt 1 -or $initialAttackSpeedPercent -gt 999) {
            throw "英雄初始攻速必须在 1~999%：$rawcode.initialAttackSpeedPercent"
        }
        foreach ($field in @('dmgpt1', 'backsw1')) {
            if (-not $unit.Contains($field)) {
                throw "英雄缺少攻击动作配置：$rawcode.$field"
            }
            $value = [double]$unit[$field]
        if (([double]::IsNaN($value)) -or ([double]::IsInfinity($value)) -or $value -lt 0) {
                throw "英雄攻击动作必须为非负实数：$rawcode.$field"
            }
        }
        $cooldown = [double]$unit.cool1
        $attackPoint = [double]$unit.dmgpt1
        $backswing = [double]$unit.backsw1
        if ($cooldown -le 0 -or ($attackPoint + $backswing) -gt $cooldown) {
            throw "英雄攻击前摇和后摇之和不得大于攻击间隔：$rawcode"
        }
    }
    # 初始攻速是项目运行时配置，不属于 Warcraft 单位物编字段。
    foreach ($rawcode in @($unitTable.Sections.Keys)) {
        [void]$unitTable.Sections[$rawcode].Remove('initialAttackSpeedPercent')
        foreach ($field in @('baseUnitId', 'modeId', 'difficultyLevel', 'tier', 'poolId', 'dropLevelMin', 'dropLevelMax', 'dropChancePercent', 'maxDrops', 'goldRep', 'expReward')) {
            [void]$unitTable.Sections[$rawcode].Remove($field)
        }
    }
    $items = ConvertTo-ObjectConfig $itemTable.Sections
    $experienceData = New-ExperienceConfig $experienceSettingsTable $experienceLevelTable
    $goldData = New-GoldConfig $goldSettingsTable
    $equipmentData = New-EquipmentConfig $equipmentLevelTable $equipmentTemplateTable $equipmentAutoTable $equipmentPassiveTable $equipmentComboTable $items $units
    $roguelikeData = $null
    $attributeData = $null
    $roguelikePath = Join-Path $excelDirectory 'roguelike.xlsx'
    if (Test-Path -LiteralPath $roguelikePath -PathType Leaf) {
        $roguelikeSettingsTable = Read-ExcelObjectTable $roguelikePath 'settings' 'settingId'
        $roguelikeEffectsTable = Read-ExcelObjectTable $roguelikePath 'effects' 'effectId'
        $roguelikeRuntimeTable = Read-ExcelObjectTable $roguelikePath 'skill_runtime' 'runtimeId'
        $attributeTable = Read-ExcelObjectTable $roguelikePath 'attributes' 'attributeId'
        $roguelikeData = New-RoguelikeConfig $roguelikeSettingsTable $roguelikeEffectsTable $roguelikeRuntimeTable $units (ConvertTo-ObjectConfig $abilityTable.Sections)
        Apply-SkillFormulaTooltips $roguelikeData $abilityTable
        # AOcr stores its normal button text and extended tooltip per level.
        # A scalar only replaces rank 1, leaving inherited Critical Strike text
        # visible after the passive is upgraded.
        $frostmourneTip = [string]$abilityTable.Sections['A0E3']['Tip']
        $frostmourneUbertip = [string]$abilityTable.Sections['A0E3']['Ubertip']
        $abilityTable.Sections['A0E3']['Tip'] = @($frostmourneTip, $frostmourneTip, $frostmourneTip)
        $abilityTable.Sections['A0E3']['Ubertip'] = @($frostmourneUbertip, $frostmourneUbertip, $frostmourneUbertip)
        $armyRuntime = $roguelikeData.lua.skillRuntime['H0E0']['A0E4']
        if ($null -eq $armyRuntime -or -not $armyRuntime.Contains('summonCooldown') -or -not $armyRuntime.Contains('summonManaCost')) {
            throw '阿尔萨斯亡灵大军缺少原生冷却或法力消耗配置：H0E0/A0E4'
        }
        $armyCooldowns = @($armyRuntime['summonCooldown'])
        $armyManaCosts = @($armyRuntime['summonManaCost'])
        $armyLevelCount = [int]$abilityTable.Sections['A0E4']['levels']
        if ($armyCooldowns.Count -ne $armyLevelCount -or $armyManaCosts.Count -ne $armyLevelCount) {
            throw "亡灵大军冷却和法力消耗配置必须与技能等级数一致：等级=$armyLevelCount / 冷却=$($armyCooldowns.Count) / 法力=$($armyManaCosts.Count)"
        }
        foreach ($value in $armyCooldowns) { if ([int]$value -lt 0) { throw '亡灵大军冷却不能为负数。' } }
        foreach ($value in $armyManaCosts) { if ([int]$value -lt 0) { throw '亡灵大军法力消耗不能为负数。' } }
        # Native fields control actual mana/cooldown; tooltip placeholders above
        # read those same fields so future balance edits cannot desync the text.
        $abilityTable.Sections['A0E4']['Cool'] = @($armyCooldowns)
        $abilityTable.Sections['A0E4']['Cost'] = @($armyManaCosts)
        $attributeData = New-AttributeConfig $attributeTable
    } else {
        Write-Warning '缺少 excelCfg/roguelike.xlsx；保留当前已检入的 roguelike.lua。'
    }
    $abilitySections = [ordered]@{}
    foreach ($rawcode in $abilityTable.Sections.Keys) {
        if ($rawcode -match '^(?:ZB|ZC)[0-9A-Z]{2}$') {
            throw "Boss 词缀技能 Rawcode 由生成器分配，不能写入 ability.xlsx：$rawcode"
        }
        $abilitySections[$rawcode] = $abilityTable.Sections[$rawcode]
    }
    $equipmentStatAbilities = New-EquipmentStatAbilities $abilitySections
    foreach ($rawcode in $equipmentStatAbilities.abilitySections.Keys) {
        if ($abilitySections.Contains($rawcode)) {
            throw "装备隐藏属性技能 Rawcode 冲突：$rawcode"
        }
        $abilitySections[$rawcode] = $equipmentStatAbilities.abilitySections[$rawcode]
    }
    $bossAffixData = New-BossAffixData $bossAffixTable $buffTable $units $abilitySections
    foreach ($rawcode in $bossAffixData.abilitySections.Keys) {
        if ($abilitySections.Contains($rawcode)) {
            throw "Boss 词缀技能 Rawcode 冲突：$rawcode"
        }
        $abilitySections[$rawcode] = $bossAffixData.abilitySections[$rawcode]
    }

    $abilities = ConvertTo-ObjectConfig $abilitySections
    $buffs = ConvertTo-ObjectConfig $buffTable.Sections
    $regions = Read-RegionsFromJass (Join-Path $mapDirectory 'war3map.j')
    $equipmentData.statAbilities = $equipmentStatAbilities.luaData

    $lniDefinitions = @()
    $slkDefinitions = @(
        @{ Name = 'generated_unit.lua'; FunctionName = 'slk_unit'; ClassName = 'unit'; Sections = $unitTable.Sections },
        @{ Name = 'generated_ability.lua'; FunctionName = 'slk_ability'; ClassName = 'ability'; Sections = $abilitySections },
        @{ Name = 'generated_item.lua'; FunctionName = 'slk_item'; ClassName = 'item'; Sections = $itemTable.Sections },
        @{ Name = 'generated_buff.lua'; FunctionName = 'slk_buff'; ClassName = 'buff'; Sections = $buffTable.Sections }
    )
    $luaDefinitions = @(
        @{ Name = 'units.lua'; Annotations = @('---@class GeneratedUnitConfig', '---@field rawcode string 单位 Rawcode', '---@field _parent string|nil 原始单位模板', '---@field Name string|nil 单位名称', '---@field Ubertip string|nil 单位说明', '---@field heroAbilList string|nil 英雄技能 Rawcode 列表', '---@field cool1 number|nil 基础攻击间隔（秒）', '---@field dmgpt1 number|nil 攻击前摇（秒）；英雄由 unit.xlsx 配置并写入物编', '---@field backsw1 number|nil 攻击后摇（秒）；英雄由 unit.xlsx 配置并写入物编', '---@field initialAttackSpeedPercent integer|nil 英雄初始总攻速百分比；100%=标准，500%=5 倍；改表后须重新生成地图并重新开局', '---@field baseUnitId string|nil PVE 难度变体对应的基础怪物 ID', '---@field modeId integer|nil PVE 模式编号：1 普通，2 困难', '---@field difficultyLevel integer|nil PVE 难度等级 1–10', '---@field tier integer|nil 普通怪与精英的军团阶数（名称后缀“一阶”至“九阶”）', '---@field goldRep integer|nil 该物编变体的最终金币奖励', '---@field expReward integer|nil 该物编变体的最终经验奖励', '---@field poolId string|nil 装备掉落池 ID', '---@field dropLevelMin integer|nil 装备最低掉落等级', '---@field dropLevelMax integer|nil 装备最高掉落等级', '---@field dropChancePercent integer|nil 装备掉落概率；0 表示不掉落', '---@field maxDrops integer|nil 最大掉落数'); Data = $units },
        @{ Name = 'abilities.lua'; Annotations = @('---@class GeneratedAbilityConfig', '---@field rawcode string 技能 Rawcode', '---@field _parent string|nil 原始技能模板', '---@field Name string|nil 技能名称', '---@field Ubertip string|nil 技能说明', '---@field Cool integer|integer[]|nil 冷却时间', '---@field Rng integer|integer[]|nil 施法距离', '---@field Area integer|integer[]|nil 影响范围'); Data = $abilities },
        @{ Name = 'items.lua'; Annotations = @('---@class GeneratedItemConfig', '---@field rawcode string 道具 Rawcode', '---@field _parent string|nil 原始道具模板', '---@field Name string|nil 道具名称', '---@field Ubertip string|nil 道具说明'); Data = $items },
        @{ Name = 'buffs.lua'; Annotations = @('---@class GeneratedBuffConfig', '---@field rawcode string Buff Rawcode', '---@field _parent string|nil 原始 Buff 模板', '---@field Bufftip string|nil Buff 名称', '---@field Buffubertip string|nil Buff 说明'); Data = $buffs },
        @{ Name = 'regions.lua'; Annotations = @('---@class GeneratedRegionConfig', '---@field name string 区域名称', '---@field minX number 左边界', '---@field minY number 下边界', '---@field maxX number 右边界', '---@field maxY number 上边界'); Data = $regions },
        @{ Name = 'boss_affixes.lua'; Annotations = @('---@class BossAffixConfig', '---@field affixId string 词缀编号', '---@field bossRawcode string 对应 Boss Rawcode', '---@field name string 词缀显示名称', '---@field description string 词缀说明', '---@field kind string 原生物编词缀类型', '---@field baseValue integer 基础数值', '---@field secondaryValue integer 次级数值', '---@field duration integer 基础持续时间', '---@field refillLife boolean 添加后是否回满生命', '---@field indicatorAbilityRawcode string 状态栏图标辅助光环 Rawcode', '---@field indicatorBuffRawcode string 状态栏图标 Buff Rawcode', '---@field globalAbilities string|nil 各难度恒定强度的全局技能 Rawcode', '---@field unitAbilities table<string, string>|nil 基础怪物 ID 到其 20 级变体技能的映射'); Data = $bossAffixData.luaData },
        @{ Name = 'gold.lua'; Annotations = @('---@class GoldSettings', '---@field initialGold integer 本局初始金币', '---@field maxGoldDropBonusPercent integer 金币掉落加成上限', '---@field maxGold integer 原生金币上限', '---@class GoldConfig', '---@field settings GoldSettings 怪物金币奖励已写入 units.lua 的 goldRep 字段'); Data = $goldData },
        @{ Name = 'experience.lua'; Annotations = @('---@class ExperienceSettings', '---@field maxLevel integer 英雄最大等级', '---@field initialExpBonusPercent integer 初始经验加成百分比', '---@field maxExpBonusPercent integer 经验加成上限百分比', '---@class ExperienceLevelConfig', '---@field levelId string 等级配置 ID', '---@field level integer 英雄等级', '---@field requiredExp integer 升到下一级所需经验', '---@class ExperienceConfig', '---@field version integer 配置版本', '---@field settings ExperienceSettings', '---@field levels table<string, ExperienceLevelConfig> 等级配置'); Data = $experienceData.luaData }
        @{ Name = 'mystery_shop.lua'; Annotations = @('---@class MysteryShopLocation', '---@field shopId string 商店 ID', '---@field blockId integer 地图区域编号', '---@field sourcePoint string 参考刷怪点', '---@field unitRawcode string 商店单位 Rawcode', '---@field x integer 世界坐标 X', '---@field y integer 世界坐标 Y', '---@field facing integer 朝向', '---@field enabled integer 启用状态', '---@class MysteryShopStock', '---@field stockId string 库存 ID', '---@field shopId string 商店 ID', '---@field itemRawcode string 商品 Rawcode', '---@field productKind string 商品类型：box/health/mana', '---@field boxLevel integer 装备箱等级；消耗品为 0', '---@field price integer 金币价格', '---@field initialStock integer 初始库存', '---@field maxStock integer 最大库存', '---@field stockRegen integer 补货间隔秒数', '---@field enabled integer 启用状态', '---@class MysteryShopConsumable', '---@field rawcode string 消耗品 Rawcode', '---@field kind string 恢复类型：health/mana', '---@field abilityRawcode string 物品技能 Rawcode', '---@field healPercent integer 最大生命恢复百分比', '---@field manaPercent integer 最大法力恢复百分比', '---@field price integer 金币价格', '---@field stockRegen integer 补货间隔秒数', '---@field enabled integer 启用状态', '---@class MysteryShopConfig', '---@field version integer 配置版本', '---@field refillIntervalSeconds integer 装备箱补货间隔秒数', '---@field consumableRefillIntervalSeconds integer 消耗品补货间隔秒数', '---@field shops table<string, MysteryShopLocation>', '---@field stock table<string, MysteryShopStock>', '---@field boxByRawcode table<string, integer>', '---@field consumableByRawcode table<string, MysteryShopConsumable>'); Data = $mysteryShopData }
        ,@{ Name = 'equipment.lua'; Annotations = @(
            '---@class EquipmentLevelConfig',
            '---@field levelId string 等级配置 ID',
            '---@field level integer 装备等级',
            '---@field statMultiplierPercent integer 基础属性倍率百分比',
            '---@field autoSkillChance integer 自动技能概率',
            '---@field passiveMin integer 被动最少数量',
            '---@field passiveMax integer 被动最多数量',
            '---@field comboChance integer 组合词条概率',
            '---@field skillPowerMultiplierPercent integer 技能参数倍率百分比',
            '---@class EquipmentTemplateConfig',
            '---@field templateId string 模板 ID',
            '---@field rawcode string 基础物品 Rawcode',
            '---@field level integer 装备等级',
            '---@field baseAttackMin integer 基础攻击最小值',
            '---@field baseAttackMax integer 基础攻击最大值',
            '---@field baseHealthMin integer 基础生命最小值',
            '---@field baseHealthMax integer 基础生命最大值',
            '---@field baseArmorMin integer 基础护甲最小值',
            '---@field baseArmorMax integer 基础护甲最大值',
            '---@field basicAttackBonusPercent integer 普攻加成百分比，缺省为 0',
            '---@field healthAmplificationPercent integer 生命增幅百分比，缺省为 0',
            '---@class EquipmentAutoSkillConfig',
            '---@field autoSkillId string 自动技能 ID',
            '---@field eventType string 触发事件',
            '---@field chance integer 触发概率',
            '---@field internalCooldown integer 内部冷却',
            '---@field handler string 效果执行器',
            '---@field damageAttribute string|nil 伤害属性；primary 表示持有者主属性',
            '---@field damageMultiplierBaseTenth integer|nil 基础十倍定点倍率',
            '---@field damageMultiplierPerLevelTenth integer|nil 每装备等级十倍定点倍率',
            '---@class EquipmentPassiveConfig',
            '---@field passiveId string 被动 ID',
            '---@field eventType string 触发事件',
            '---@field chance integer 触发概率',
            '---@field handler string 效果执行器',
            '---@class EquipmentComboConfig',
            '---@field comboPieceId string 套装部件 ID',
            '---@field setId string 套装 ID',
            '---@field pieceIndex integer 部件序号',
            '---@class EquipmentStatAbilityConfig',
            '---@field healthDecrease string[] 生命减少个位/十位/百位/千位/万位/十万位/百万位技能 Rawcode',
            '---@field healthIncrease string[] 生命增加个位/十位/百位/千位/万位/十万位/百万位技能 Rawcode',
            '---@field attack string[] 攻击个位/十位/百位/千位技能 Rawcode',
            '---@field attackDecrease string[] 攻击减少个位/十位/百位/千位技能 Rawcode',
            '---@field armor string[] 护甲十分位/个位/十位/百位技能 Rawcode',
            '---@field armorDecrease string[] 护甲减少十分位/个位/十位/百位技能 Rawcode',
            '---@field manaPositive string[] 法力正向投影技能 Rawcode',
            '---@field manaNegative string[] 法力负向投影技能 Rawcode',
            '---@field manaRegenPositive string[] 法力回复正向投影技能 Rawcode',
            '---@field manaRegenNegative string[] 法力回复负向投影技能 Rawcode',
            '---@field lifeRegenPositive string[] 生命回复正向投影技能 Rawcode',
            '---@field lifeRegenNegative string[] 生命回复负向投影技能 Rawcode',
            '---@field attackSpeedPositive string[] 攻速正向投影技能 Rawcode',
            '---@field attackSpeedNegative string[] 攻速负向投影技能 Rawcode'
        ); Data = $equipmentData }
    )
    if ($null -ne $roguelikeData) {
        $luaDefinitions += @{ Name = 'roguelike.lua'; Annotations = @(
            '---@class RoguelikeEffectConfig',
            '---@field effectId string 唯一效果 ID',
            '---@field type string Skill 或 Common',
            '---@field modifierKey string 运行时修正键',
            '---@field values integer[] 三级累计最终值',
            '---@field maxLevel integer 最大等级',
            '---@field weight integer 抽取权重'
        ); Data = $roguelikeData.lua }
    }
    if ($null -ne $attributeData) {
        $luaDefinitions += @{ Name = 'attributes.lua'; Annotations = @(
            '---@class AttributeDefinition',
            '---@field attributeId string 属性 ID',
            '---@field group string 面板分组',
            '---@field name string 显示名称',
            '---@field displayOrder integer 显示排序',
            '---@field displayFormat string 显示格式',
            '---@field projection string 引擎投影类型；百分比派生属性统一使用 canonical ID'
        ); Data = $attributeData }
    }

    New-Item -ItemType Directory -Force -Path $tableDirectory, $configDirectory, $slkDirectory | Out-Null
    $stagingDirectory = Join-Path $configDirectory ('.generate-staging-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stagingDirectory | Out-Null
    try {
        $stagedOutputs = New-Object System.Collections.Generic.List[object]
        foreach ($definition in $lniDefinitions) {
            $sourcePath = Join-Path $stagingDirectory $definition.Name
            [System.IO.File]::WriteAllText($sourcePath, (ConvertTo-LniText $definition.Data), [System.Text.UTF8Encoding]::new($false))
            $stagedOutputs.Add([pscustomobject]@{ Source = $sourcePath; Destination = Join-Path $tableDirectory $definition.Name })
        }
        foreach ($definition in $luaDefinitions) {
            $sourcePath = Join-Path $stagingDirectory $definition.Name
            $configKey = [System.IO.Path]::GetFileNameWithoutExtension($definition.Name)
            Write-LuaModule $sourcePath $definition.Annotations $definition.Data $configKey
            $stagedOutputs.Add([pscustomobject]@{ Source = $sourcePath; Destination = Join-Path $configDirectory $definition.Name })
        }
        foreach ($definition in $slkDefinitions) {
            $sourcePath = Join-Path $stagingDirectory $definition.Name
            Write-SlkModule $sourcePath $definition.FunctionName $definition.Sections $definition.ClassName
            $stagedOutputs.Add([pscustomobject]@{ Source = $sourcePath; Destination = Join-Path $slkDirectory $definition.Name })
        }
        foreach ($output in $stagedOutputs) {

            Normalize-MigratedAssetPaths $output.Source
            if (Test-Path -LiteralPath $output.Destination) {
                $backupPath = Join-Path $stagingDirectory (([System.IO.Path]::GetFileName($output.Destination)) + '.' + [guid]::NewGuid().ToString('N') + '.backup')
                [System.IO.File]::Replace($output.Source, $output.Destination, $backupPath)
            } else {
                [System.IO.File]::Move($output.Source, $output.Destination)
            }
        }
    } finally {
        if (Test-Path -LiteralPath $stagingDirectory) {
            Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
        }
    }

    Write-Host "[ok] Excel 配置、SLK 源与 Lua 表已生成：$slkDirectory / $configDirectory"
    exit 0
} catch {
    Write-Error "配置生成失败：$($_.Exception.Message)"
    exit 1
}
