param(
    [Parameter()]
    [string]$Root,
    [Parameter()]
    [string]$ExcelRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Join-Path $PSScriptRoot 'Build'
}
if ([string]::IsNullOrWhiteSpace($ExcelRoot)) {
    $ExcelRoot = Join-Path $PSScriptRoot 'excelCfg'
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
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Data
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('--- 本文件由 generate_lua_config.ps1 自动生成，请勿手工修改。')
    $lines.Add('--- 数据源来自 excelCfg 配置表；请修改 Excel 后重新执行生成工具。')
    foreach ($annotation in $Annotations) {
        $lines.Add($annotation)
    }
    $lines.Add('return ' + (ConvertTo-LuaValue $Data 0))
    $lines.Add('')
    [System.IO.File]::WriteAllText($Path, [string]::Join("`n", $lines), [System.Text.UTF8Encoding]::new($false))
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

    foreach ($rawcode in Get-MonsterUnitRawcodes $Units) {
        $experience = Get-RequiredUnitInteger $Units[$rawcode] $rawcode 'expReward'
        if ($rawcode -eq 'G0M1') {
            if ($experience -ne 0) {
                throw "金币怪不得配置经验奖励：$rawcode.expReward"
            }
            continue
        }
        if ($experience -le 0) {
            throw "刷怪单位经验必须为正整数：$rawcode.expReward"
        }
    }
}

function New-MonsterDifficultyProfiles {
    param([Parameter(Mandatory = $true)][object[]]$Rows)

    $requiredFields = @('modeId', 'level', 'healthMultiplier', 'attackMultiplier', 'armorBonus', 'goldMultiplierPercent', 'experienceMultiplierPercent')
    $sourceProfiles = @{}
    foreach ($sourceRow in $Rows) {
        $data = $sourceRow.Data
        foreach ($field in $requiredFields) {
            if (-not $data.Contains($field)) {
                throw "怪物难度配置缺少字段：monster_scaling.xlsx 第 $($sourceRow.Row) 行 / $field"
            }
        }

        $modeId = [int]$data.modeId
        $level = [int]$data.level
        $healthMultiplier = [int]$data.healthMultiplier
        $attackMultiplier = [int]$data.attackMultiplier
        $armorBonus = [int]$data.armorBonus
        $goldMultiplierPercent = [int]$data.goldMultiplierPercent
        $experienceMultiplierPercent = [int]$data.experienceMultiplierPercent
        if (($modeId -ne 1 -and $modeId -ne 2) -or $level -lt 1 -or $level -gt 10) {
            throw "怪物难度配置模式或等级无效：monster_scaling.xlsx 第 $($sourceRow.Row) 行"
        }
        if ($healthMultiplier -lt 10) {
            throw "怪物生命倍率必须不低于 10（代表 1 倍）：monster_scaling.xlsx 第 $($sourceRow.Row) 行"
        }
        if ($attackMultiplier -lt 10) {
            throw "怪物攻击倍率必须不低于 10（代表 1 倍）：monster_scaling.xlsx 第 $($sourceRow.Row) 行"
        }
        if ($armorBonus -lt 0) {
            throw "怪物护甲加成必须为非负整数：monster_scaling.xlsx 第 $($sourceRow.Row) 行"
        }
        if ($goldMultiplierPercent -lt 0) {
            throw "金币倍率必须为非负整数：monster_scaling.xlsx 第 $($sourceRow.Row) 行"
        }
        if ($experienceMultiplierPercent -lt 0) {
            throw "经验倍率必须为非负整数：monster_scaling.xlsx 第 $($sourceRow.Row) 行"
        }

        $key = "$modeId`:$level"
        if ($sourceProfiles.ContainsKey($key)) {
            throw "怪物难度配置重复：monster_scaling.xlsx / $key"
        }
        $sourceProfiles[$key] = [ordered]@{
            modeId = $modeId
            level = $level
            healthMultiplier = $healthMultiplier
            attackMultiplier = $attackMultiplier
            armorBonus = $armorBonus
            goldMultiplierPercent = $goldMultiplierPercent
            experienceMultiplierPercent = $experienceMultiplierPercent
        }
    }

    $profiles = [ordered]@{}
    $index = 0
    foreach ($modeId in @(1, 2)) {
        for ($level = 1; $level -le 10; $level = $level + 1) {
            $key = "$modeId`:$level"
            if (-not $sourceProfiles.ContainsKey($key)) {
                throw "怪物难度配置缺失：monster_scaling.xlsx / $key"
            }
            $index = $index + 1
            $source = $sourceProfiles[$key]
            $profiles[$key] = [ordered]@{
                modeId = $modeId
                level = $level
                multiplier = $source.healthMultiplier
                healthMultiplier = $source.healthMultiplier
                attackMultiplier = $source.attackMultiplier
                armorBonus = $source.armorBonus
                goldMultiplierPercent = $source.goldMultiplierPercent
                experienceMultiplierPercent = $source.experienceMultiplierPercent
                groupIndex = [math]::Floor(($index - 1) / 4) + 1
                abilityLevel = (($index - 1) % 4) + 1
            }
        }
    }
    if ($sourceProfiles.Count -ne 20) {
        throw "怪物难度配置必须恰有 20 行，实际为：$($sourceProfiles.Count)"
    }
    return $profiles
}

function New-GoldConfig {
    param(
        [Parameter(Mandatory = $true)][object]$RewardTable,
        [Parameter(Mandatory = $true)][object]$SettingsTable
    )

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

    $rewards = [ordered]@{
        normal = [ordered]@{}
        elite = [ordered]@{}
        boss = [ordered]@{}
    }
    foreach ($rewardId in $RewardTable.Sections.Keys) {
        $row = $RewardTable.Sections[$rewardId]
        foreach ($field in @('kind', 'level', 'baseGold')) {
            if (-not $row.Contains($field)) {
                throw "金币奖励缺少字段：gold.xlsx/rewards/$rewardId/$field"
            }
        }
        $kind = [string]$row.kind
        $level = [int]$row.level
        $baseGold = [int]$row.baseGold
        if (-not $rewards.Contains($kind) -or $level -lt 1 -or $level -gt 9 -or $baseGold -le 0) {
            throw "金币奖励类型、等级或数值无效：gold.xlsx/rewards/$rewardId"
        }
        $levelKey = [string]$level
        if ($rewards[$kind].Contains($levelKey)) {
            throw "金币奖励重复：gold.xlsx/rewards/$kind/$level"
        }
        $rewards[$kind][$levelKey] = $baseGold
    }
    foreach ($kind in @('normal', 'elite', 'boss')) {
        for ($level = 1; $level -le 9; $level = $level + 1) {
            if (-not $rewards[$kind].Contains([string]$level)) {
                throw "金币奖励缺失：gold.xlsx/rewards/$kind/$level"
            }
        }
    }
    if ($RewardTable.Sections.Count -ne 27) {
        throw "金币奖励必须恰有 27 行，实际为：$($RewardTable.Sections.Count)"
    }

    return [ordered]@{
        settings = $settings
        rewards = $rewards
    }
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

function Get-DifficultyCeiling {
    param(
        [Parameter(Mandatory = $true)][int]$Value,
        [Parameter(Mandatory = $true)][int]$Multiplier
    )

    $product = $Value * $Multiplier
    $quotient = [int][math]::Floor($product / 10)
    if ($product % 10 -ne 0) {
        return $quotient + 1
    }
    return $quotient
}

function ConvertTo-Base36Pair {
    param([Parameter(Mandatory = $true)][int]$Index)

    if ($Index -lt 0 -or $Index -ge 1296) {
        throw "技能 Rawcode 索引超出两位 Base36 范围：$Index"
    }
    $characters = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    return [string]$characters[[math]::Floor($Index / 36)] + [string]$characters[$Index % 36]
}

function New-MonsterScalingAbilitySection {
    param(
        [Parameter(Mandatory = $true)][string]$Rawcode,
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int[]]$Values
    )

    if ($Values.Count -ne 4) {
        throw "隐藏属性技能必须恰有 4 个等级：$Rawcode"
    }
    return [ordered]@{
        _parent = $Parent
        Name = $Name
        hero = 0
        item = 1
        levels = 4
        levelSkip = 0
        DataA = $Values
    }
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
        [Parameter(Mandatory = $true)][object]$DropTable,
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

    $drops = ConvertTo-ObjectConfig $DropTable.Sections
    $seenDropUnits = @{}
    foreach ($dropId in $drops.Keys) {
        $drop = $drops[$dropId]
        $unitRawcode = [string](Get-EquipmentRequiredField $drop 'unitRawcode' "drop/$dropId")
        if (-not $Units.Contains($unitRawcode)) { throw "掉落规则引用了不存在的单位：drop/$dropId/$unitRawcode" }
        if ($seenDropUnits.ContainsKey($unitRawcode)) { throw "同一怪物存在重复掉落规则：$unitRawcode" }
        $seenDropUnits[$unitRawcode] = $true
        Assert-EquipmentIntegerRange ([int](Get-EquipmentRequiredField $drop 'chance' "drop/$dropId")) 0 100 "drop/$dropId/chance"
        $levelMin = [int](Get-EquipmentRequiredField $drop 'levelMin' "drop/$dropId")
        $levelMax = [int](Get-EquipmentRequiredField $drop 'levelMax' "drop/$dropId")
        Assert-EquipmentIntegerRange $levelMin 1 5 "drop/$dropId/levelMin"
        Assert-EquipmentIntegerRange $levelMax 1 5 "drop/$dropId/levelMax"
        if ($levelMax -lt $levelMin -or [int]$drop.maxDrops -lt 1) { throw "掉落等级或最大掉落数无效：drop/$dropId" }
        if ([int]$drop.enabled -notin @(0, 1)) { throw "掉落规则启用字段必须为 0 或 1：drop/$dropId" }
    }

    return [ordered]@{
        version = 1
        levels = $levels
        templates = $templates
        autoSkills = $autoSkills
        passives = $passives
        combos = $combos
        drops = $drops
    }
}

function New-MonsterScalingData {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Units,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Profiles
    )

    $orderedProfiles = @($Profiles.Values)
    $abilitySections = [ordered]@{}
    $unitMappings = [ordered]@{}
    $unitIndex = 0
    foreach ($rawcode in Get-MonsterUnitRawcodes $Units) {
        $unit = $Units[$rawcode]
        $health = Get-RequiredUnitInteger $unit $rawcode 'HP'
        $damage = Get-RequiredUnitInteger $unit $rawcode 'dmgplus1'
        $healthAbilities = New-Object System.Collections.Generic.List[string]
        $attackAbilities = New-Object System.Collections.Generic.List[string]
        for ($group = 0; $group -lt 5; $group = $group + 1) {
            $healthRawcode = 'ZH' + (ConvertTo-Base36Pair ($unitIndex * 5 + $group))
            $attackRawcode = 'ZD' + (ConvertTo-Base36Pair ($unitIndex * 5 + $group))
            $healthValues = New-Object System.Collections.Generic.List[int]
            $attackValues = New-Object System.Collections.Generic.List[int]
            for ($levelOffset = 0; $levelOffset -lt 4; $levelOffset = $levelOffset + 1) {
                $profile = $orderedProfiles[$group * 4 + $levelOffset]
                $healthValues.Add((Get-DifficultyCeiling $health $profile.healthMultiplier) - $health)
                $attackValues.Add((Get-DifficultyCeiling $damage $profile.attackMultiplier) - $damage)
            }
            $abilitySections[$healthRawcode] = New-MonsterScalingAbilitySection $healthRawcode 'AIlf' 'PVE 隐藏生命加成' $healthValues.ToArray()
            $abilitySections[$attackRawcode] = New-MonsterScalingAbilitySection $attackRawcode 'AItg' 'PVE 隐藏攻击加成' $attackValues.ToArray()
            $healthAbilities.Add($healthRawcode)
            $attackAbilities.Add($attackRawcode)
        }
        $unitMappings[$rawcode] = [ordered]@{
            healthAbilities = $healthAbilities.ToArray()
            attackAbilities = $attackAbilities.ToArray()
        }
        $unitIndex = $unitIndex + 1
    }

    $armorAbilities = New-Object System.Collections.Generic.List[string]
    for ($group = 0; $group -lt 5; $group = $group + 1) {
        $armorRawcode = 'ZA' + (ConvertTo-Base36Pair $group)
        $armorValues = New-Object System.Collections.Generic.List[int]
        for ($levelOffset = 0; $levelOffset -lt 4; $levelOffset = $levelOffset + 1) {
            $profile = $orderedProfiles[$group * 4 + $levelOffset]
            $armorValues.Add($profile.armorBonus)
        }
        $abilitySections[$armorRawcode] = New-MonsterScalingAbilitySection $armorRawcode 'AId1' 'PVE 隐藏护甲加成' $armorValues.ToArray()
        $armorAbilities.Add($armorRawcode)
    }

    if ($unitIndex -ne 38 -or $abilitySections.Count -ne 385) {
        throw "隐藏属性技能生成数量异常：单位=$unitIndex，技能=$($abilitySections.Count)"
    }
    return [ordered]@{
        luaData = [ordered]@{
            profiles = $Profiles
            units = $unitMappings
            armorAbilities = $armorAbilities.ToArray()
        }
        abilitySections = $abilitySections
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

    if ($DataAValues.Count -ne 4) {
        throw "Boss 词缀技能必须恰有 4 个等级：$Rawcode"
    }
    $section = [ordered]@{
        _parent = $Parent
        Name = "天灾词缀：$Name"
        Tip = "天灾词缀：$Name"
        Ubertip = $Description + '|n该词缀随当前 PVE 难度成长。'
        hero = 0
        item = 0
        levels = 4
        levelSkip = 0
        DataA = $DataAValues
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
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Profile,
        [Parameter()][AllowNull()][System.Collections.IDictionary]$Unit,
        [Parameter()][AllowEmptyString()][string]$UnitRawcode = ''
    )

    $kind = [string]$Definition.kind
    $baseValue = [int]$Definition.baseValue
    switch ($kind) {
        'move_speed' { return Get-DifficultyCeiling $baseValue ([int]$Profile.attackMultiplier) }
        'damage_percent' {
            $baseDamage = Get-RequiredUnitInteger $Unit $UnitRawcode 'dmgplus1'
            $scaledDamage = Get-DifficultyCeiling $baseDamage ([int]$Profile.attackMultiplier)
            return [int][math]::Floor(($scaledDamage * $baseValue + 99) / 100)
        }
        'attack_speed_percent' {
            return ([decimal]$baseValue * [decimal]$Profile.attackMultiplier) / [decimal]1000
        }
        'armor' { return Get-DifficultyCeiling $baseValue ([int]$Profile.healthMultiplier) }
        'health_percent' {
            $baseHealth = Get-RequiredUnitInteger $Unit $UnitRawcode 'HP'
            $scaledHealth = Get-DifficultyCeiling $baseHealth ([int]$Profile.healthMultiplier)
            return [int][math]::Floor(($scaledHealth * $baseValue + 99) / 100)
        }
        'life_regen' { return Get-DifficultyCeiling $baseValue ([int]$Profile.healthMultiplier) }
        'bash' { return Get-DifficultyCeiling $baseValue ([int]$Profile.attackMultiplier) }
        'frost' { return 0 }
        'feedback' { return Get-DifficultyCeiling $baseValue ([int]$Profile.attackMultiplier) }
        default { throw "不支持的 Boss 词缀类型：$kind" }
    }
}

function Get-BossAffixDurationValue {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Definition,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Profile
    )

    if ([string]$Definition.kind -ne 'frost') {
        return [int]$Definition.duration
    }
    $scaledDuration = Get-DifficultyCeiling ([int]$Definition.duration) ([int]$Profile.attackMultiplier)
    return [math]::Min(3, $scaledDuration)
}

function New-BossAffixData {
    param(
        [Parameter(Mandatory = $true)][object]$AffixTable,
        [Parameter(Mandatory = $true)][object]$BuffTable,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Units,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Profiles,
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

    $orderedProfiles = @($Profiles.Values)
    if ($orderedProfiles.Count -ne 20) {
        throw "Boss 词缀需要 20 档难度配置，实际为：$($orderedProfiles.Count)"
    }
    $minionRawcodes = New-Object System.Collections.Generic.List[string]
    for ($block = 1; $block -le 9; $block = $block + 1) {
        foreach ($rawcode in @("N${block}M1", "N${block}R1", "E${block}M1")) {
            if (-not $Units.Contains($rawcode)) {
                throw "Boss 词缀引用的小怪单位不存在：$rawcode"
            }
            $minionRawcodes.Add($rawcode)
        }
    }
    foreach ($rawcode in @('G0M1', 'X0M1')) {
        if (-not $Units.Contains($rawcode)) {
            throw "Boss 词缀引用的特殊怪单位不存在：$rawcode"
        }
        $minionRawcodes.Add($rawcode)
    }
    $specialMinionRawcodes = @('G0M1', 'X0M1')
    $legacyMinionRawcodeCount = $minionRawcodes.Count - $specialMinionRawcodes.Count
    $legacyGeneratedCount = 0
    $specialGeneratedCount = 0
    foreach ($plannedAffixId in $expectedKinds.Keys) {
        if (-not $AffixTable.Sections.Contains($plannedAffixId)) {
            throw "Boss 词缀配置缺失：$plannedAffixId"
        }
        $plannedKind = [string]$AffixTable.Sections[$plannedAffixId].kind
        $plannedUnitSpecific = ($plannedKind -eq 'damage_percent' -or $plannedKind -eq 'health_percent')
        if ($plannedUnitSpecific) {
            $legacyGeneratedCount = $legacyGeneratedCount + ($legacyMinionRawcodeCount * 5)
            $specialGeneratedCount = $specialGeneratedCount + ($specialMinionRawcodes.Count * 5)
        } else {
            $legacyGeneratedCount = $legacyGeneratedCount + 5
        }
    }

    $abilitySections = [ordered]@{}
    $affixes = [ordered]@{}
    $rawcodeIndex = 0
    $specialRawcodeIndex = 0
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

        $targets = if ($isUnitSpecific) { $minionRawcodes.ToArray() } else { @('__GLOBAL__') }
        $targetAbilityMappings = [ordered]@{}
        foreach ($targetRawcode in $targets) {
            $abilityRawcodes = New-Object System.Collections.Generic.List[string]
            for ($group = 0; $group -lt 5; $group = $group + 1) {
                $dataAValues = New-Object System.Collections.Generic.List[object]
                $durationValues = New-Object System.Collections.Generic.List[int]
                for ($levelOffset = 0; $levelOffset -lt 4; $levelOffset = $levelOffset + 1) {
                    $profile = $orderedProfiles[$group * 4 + $levelOffset]
                    $unit = if ($isUnitSpecific) { $Units[$targetRawcode] } else { $null }
                    $dataAValues.Add((Get-BossAffixDataAValue $definition $profile $unit $targetRawcode))
                    $durationValues.Add((Get-BossAffixDurationValue $definition $profile))
                }
                if ($targetRawcode -in $specialMinionRawcodes) {
                    $generatedRawcodeIndex = $legacyGeneratedCount + $specialRawcodeIndex
                    $specialRawcodeIndex = $specialRawcodeIndex + 1
                } else {
                    $generatedRawcodeIndex = $rawcodeIndex
                    $rawcodeIndex = $rawcodeIndex + 1
                }
                $rawcode = 'ZB' + (ConvertTo-Base36Pair $generatedRawcodeIndex)
                if ($ExistingAbilities.Contains($rawcode) -or $abilitySections.Contains($rawcode)) {
                    throw "Boss 词缀技能 Rawcode 冲突：$rawcode"
                }
                $extraFields = [ordered]@{}
                switch ([string]$definition.kind) {
                    'life_regen' {
                        $extraFields.DataB = @(0, 0, 0, 0)
                        $extraFields.Area = @(0, 0, 0, 0)
                        $extraFields.targs = 'self'
                    }
                    'bash' {
                        $extraFields.DataB = @(0, 0, 0, 0)
                        $extraFields.DataC = @(0, 0, 0, 0)
                        $extraFields.Dur = @([int]$definition.duration, [int]$definition.duration, [int]$definition.duration, [int]$definition.duration)
                        $extraFields.HeroDur = @([int]$definition.duration, [int]$definition.duration, [int]$definition.duration, [int]$definition.duration)
                    }
                    'frost' {
                        $extraFields.Dur = $durationValues.ToArray()
                        $extraFields.HeroDur = $durationValues.ToArray()
                    }
                    'feedback' {
                        $extraFields.DataB = @([int]$definition.secondaryValue, [int]$definition.secondaryValue, [int]$definition.secondaryValue, [int]$definition.secondaryValue)
                        $extraFields.DataC = $dataAValues.ToArray()
                        $extraFields.DataD = @([int]$definition.secondaryValue, [int]$definition.secondaryValue, [int]$definition.secondaryValue, [int]$definition.secondaryValue)
                    }
                }
                $abilitySection = New-BossAffixAbilitySection `
                    $rawcode `
                    (Get-BossAffixParent ([string]$definition.kind)) `
                    ([string]$definition.name) `
                    ([string]$definition.description) `
                    $dataAValues.ToArray() `
                    $extraFields
                # Afra carries required built-in slow data.  Do not overwrite it
                # with zero values merely because the affix itself has no DataA.
                if ([string]$definition.kind -eq 'frost') {
                    [void]$abilitySection.Remove('DataA')
                }
                $abilitySections[$rawcode] = $abilitySection
                $abilityRawcodes.Add($rawcode)
            }
            $targetAbilityMappings[$targetRawcode] = $abilityRawcodes.ToArray()
        }
        if ($isUnitSpecific) {
            $affixEntry.unitAbilities = $targetAbilityMappings
        } else {
            $affixEntry.globalAbilities = $targetAbilityMappings['__GLOBAL__']
        }
        $abilitySections[$indicatorAbilityRawcode] = New-BossAffixIndicatorAbilitySection `
            $indicatorAbilityRawcode `
            $indicatorBuffRawcode `
            ([string]$definition.name) `
            ([string]$definition.description)
        $affixes[$affixId] = $affixEntry
    }

    $expectedLegacyGeneratedCount = ($unitSpecificAffixCount * $legacyMinionRawcodeCount + $globalAffixCount) * 5
    $expectedSpecialGeneratedCount = $unitSpecificAffixCount * $specialMinionRawcodes.Count * 5
    $expectedGeneratedCount = $expectedLegacyGeneratedCount + $expectedSpecialGeneratedCount
    $expectedAbilityCount = $expectedGeneratedCount + $expectedKinds.Count
    if ($abilitySections.Count -ne $expectedAbilityCount -or $rawcodeIndex -ne $expectedLegacyGeneratedCount -or $specialRawcodeIndex -ne $expectedSpecialGeneratedCount) {
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
            $rawcode -eq 'u0W1' -or
            $rawcode -in @('G0M1', 'X0M1') -or
            $rawcode -match '^H[0-9A-Z]{3}$' -or
            $rawcode -match '^[NEB][0-9A-Z]{3}$'
        )
        if (-not $isCombatUnit) { continue }
        $UnitTable.Sections[$rawcode]['atktype1'] = 'hero'
        $UnitTable.Sections[$rawcode]['defType'] = 'hero'
    }
}

function Assert-CombatUnitTypes {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Units)

    foreach ($rawcode in $Units.Keys) {
        $isCombatUnit = (
            $rawcode -eq 'u0W1' -or
            $rawcode -in @('G0M1', 'X0M1') -or
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
    foreach ($rawcode in @('A0N4', 'A0B4', 'A0E4')) {
        if (-not $AbilityTable.Sections.Contains($rawcode)) { throw "被动伤害技能物编缺失：$rawcode" }
        $AbilityTable.Sections[$rawcode]['DataA'] = @(0, 0)
        $AbilityTable.Sections[$rawcode]['DataB'] = @(0, 0)
        if ($AbilityTable.Sections[$rawcode].Contains('DataC')) { $AbilityTable.Sections[$rawcode]['DataC'] = @(0, 0) }
    }
    $AbilityTable.Sections['R0W3'] = [ordered]@{
        _parent = 'AOae'
        Name = '齐天战意状态'
        hero = 0
        item = 1
        levels = 1
        DataA = @(0)
        DataB = @(0)
        Area = @(1)
        BuffID = @('B0W1')
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
            $attributeKey = $null
            $multiplierKey = $null
            $prefix = '伤害'
            if ($runtime.Contains('damageAttribute') -and $runtime.Contains('damageMultiplierTenth')) {
                $attributeKey = 'damageAttribute'
                $multiplierKey = 'damageMultiplierTenth'
            } elseif ($runtime.Contains('procDamageAttribute') -and $runtime.Contains('procDamageMultiplierTenth')) {
                $attributeKey = 'procDamageAttribute'
                $multiplierKey = 'procDamageMultiplierTenth'
                $prefix = '额外伤害'
            }
            if ($null -ne $attributeKey) {
                $formula = Format-SkillDamageLines ([string]$runtime[$attributeKey]) @($runtime[$multiplierKey]) $prefix
            } elseif ($runtime.Contains('summonDamageAttribute') -and $runtime.Contains('summonDamageMultiplierTenth')) {
                $formula = "猴兵每次攻击造成 $(Format-TenthMultiplier ([int]$runtime['summonDamageMultiplierTenth']))×$(Get-DamageAttributeLabel ([string]$runtime['summonDamageAttribute']))的物理伤害。"
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
    foreach ($field in @('hostPlayerId', 'maxPlayerCount', 'firstRewardLevel', 'choiceCount', 'durationSeconds', 'freeRefreshPerOffer', 'maxEffectLevel')) {
        $settings[$field] = [int](Get-RoguelikeRequiredField $settingsSource $field 'settings/DEFAULT')
    }
    if ($settings.choiceCount -ne 3 -or $settings.maxEffectLevel -ne 3 -or $settings.durationSeconds -lt 1 -or $settings.freeRefreshPerOffer -lt 0) {
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
        if ($effect.maxLevel -ne 3 -or $effect.weight -le 0) {
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

    $damageAttributes = @('primary')
    $formulaRequirements = @(
        @{ hero = 'H0W0'; skill = 'A0W1'; prefix = '' }, @{ hero = 'H0W0'; skill = 'A0W2'; prefix = '' },
        @{ hero = 'H0W0'; skill = 'A0W3'; prefix = 'proc' }, @{ hero = 'H0W0'; skill = 'A0W4'; prefix = 'summon' },
        @{ hero = 'H0N0'; skill = 'A0N1'; prefix = '' }, @{ hero = 'H0N0'; skill = 'A0N2'; prefix = '' },
        @{ hero = 'H0N0'; skill = 'A0N4'; prefix = 'proc' }, @{ hero = 'H0B0'; skill = 'A0B1'; prefix = '' },
        @{ hero = 'H0B0'; skill = 'A0B4'; prefix = 'proc' }, @{ hero = 'H0E0'; skill = 'A0E1'; prefix = '' },
        @{ hero = 'H0E0'; skill = 'A0E4'; prefix = 'proc' }
    )
    foreach ($requirement in $formulaRequirements) {
        $hero = $requirement.hero
        $skill = $requirement.skill
        if (-not $skillRuntime.Contains($hero) -or -not $skillRuntime[$hero].Contains($skill)) {
            throw "技能伤害公式缺失：$hero/$skill"
        }
        $runtime = $skillRuntime[$hero][$skill]
        if ($runtime.Contains('damage')) { throw "技能结算禁止保留固定 damage 数组：$hero/$skill" }
        $attributeKey = $requirement.prefix + 'DamageAttribute'
        $multiplierKey = $requirement.prefix + 'DamageMultiplierTenth'
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
        if ($requirement.prefix -eq 'summon') {
            if ($multipliers -is [System.Collections.IEnumerable] -or [int]$multipliers -le 0) {
                throw "召唤伤害倍率必须为正整数十倍定点：$hero/$skill"
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
    $configDirectory = Join-Path $mapDirectory 'Lua\config'

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
    $scalingTable = Read-ExcelTypedRows (Join-Path $excelDirectory 'monster_scaling.xlsx') 'monster_scaling'
    $bossAffixTable = Read-ExcelObjectTable (Join-Path $excelDirectory 'boss_affix.xlsx') 'affix' 'affixId'
    $experiencePath = Join-Path $excelDirectory 'experience.xlsx'
    $experienceSettingsTable = Read-ExcelObjectTable $experiencePath 'settings' 'settingId'
    $experienceLevelTable = Read-ExcelObjectTable $experiencePath 'levels' 'levelId'
    $goldTablePath = Join-Path $excelDirectory 'gold.xlsx'
    $goldRewardTable = Read-ExcelObjectTable $goldTablePath 'rewards' 'rewardId'
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
    $equipmentDropTable = Read-ExcelObjectTable $equipmentPath 'drop' 'dropId'

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
    }
    $items = ConvertTo-ObjectConfig $itemTable.Sections
    $profiles = New-MonsterDifficultyProfiles $scalingTable.Rows
    $experienceData = New-ExperienceConfig $experienceSettingsTable $experienceLevelTable
    $goldData = New-GoldConfig $goldRewardTable $goldSettingsTable
    $scalingData = New-MonsterScalingData $units $profiles
    $equipmentData = New-EquipmentConfig $equipmentLevelTable $equipmentTemplateTable $equipmentAutoTable $equipmentPassiveTable $equipmentComboTable $equipmentDropTable $items $units
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
        $attributeData = New-AttributeConfig $attributeTable
    } else {
        Write-Warning '缺少 excelCfg/roguelike.xlsx；保留当前已检入的 roguelike.ini 与 roguelike.lua。'
    }
    $abilitySections = [ordered]@{}
    foreach ($rawcode in $abilityTable.Sections.Keys) {
        if ($rawcode -match '^(?:ZH|ZD|ZA|ZB|ZC)[0-9A-Z]{2}$') {
            throw "怪物难度或 Boss 词缀技能 Rawcode 由 Excel 配置自动生成，不能写入 ability.xlsx：$rawcode"
        }
        $abilitySections[$rawcode] = $abilityTable.Sections[$rawcode]
    }
    foreach ($rawcode in $scalingData.abilitySections.Keys) {
        if ($abilitySections.Contains($rawcode)) {
            throw "成长技能 Rawcode 冲突：$rawcode"
        }
        $abilitySections[$rawcode] = $scalingData.abilitySections[$rawcode]
    }
    $equipmentStatAbilities = New-EquipmentStatAbilities $abilitySections
    foreach ($rawcode in $equipmentStatAbilities.abilitySections.Keys) {
        if ($abilitySections.Contains($rawcode)) {
            throw "装备隐藏属性技能 Rawcode 冲突：$rawcode"
        }
        $abilitySections[$rawcode] = $equipmentStatAbilities.abilitySections[$rawcode]
    }
    $bossAffixData = New-BossAffixData $bossAffixTable $buffTable $units $profiles $abilitySections
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

    $lniDefinitions = @(
        @{ Name = 'unit.ini'; Data = $unitTable.Sections },
        @{ Name = 'ability.ini'; Data = $abilitySections },
        @{ Name = 'item.ini'; Data = $itemTable.Sections },
        @{ Name = 'buff.ini'; Data = $buffTable.Sections },
        @{ Name = 'experience.ini'; Data = $experienceData.lni }
    )
    if ($null -ne $roguelikeData) {
        $lniDefinitions += @{ Name = 'roguelike.ini'; Data = $roguelikeData.lni }
    }
    $luaDefinitions = @(
        @{ Name = 'units.lua'; Annotations = @('---@class GeneratedUnitConfig', '---@field rawcode string 单位 Rawcode', '---@field _parent string|nil 原始单位模板', '---@field Name string|nil 单位名称', '---@field Ubertip string|nil 单位说明', '---@field heroAbilList string|nil 英雄技能 Rawcode 列表', '---@field cool1 number|nil 基础攻击间隔（秒）', '---@field dmgpt1 number|nil 攻击前摇（秒）；英雄由 unit.xlsx 配置并写入物编', '---@field backsw1 number|nil 攻击后摇（秒）；英雄由 unit.xlsx 配置并写入物编', '---@field initialAttackSpeedPercent integer|nil 英雄初始总攻速百分比；100%=标准，500%=5 倍；改表后须重新生成地图并重新开局', '---@field expReward integer|nil 单位死亡产生的基础经验'); Data = $units },
        @{ Name = 'abilities.lua'; Annotations = @('---@class GeneratedAbilityConfig', '---@field rawcode string 技能 Rawcode', '---@field _parent string|nil 原始技能模板', '---@field Name string|nil 技能名称', '---@field Ubertip string|nil 技能说明', '---@field Cool integer|integer[]|nil 冷却时间', '---@field Rng integer|integer[]|nil 施法距离', '---@field Area integer|integer[]|nil 影响范围'); Data = $abilities },
        @{ Name = 'items.lua'; Annotations = @('---@class GeneratedItemConfig', '---@field rawcode string 道具 Rawcode', '---@field _parent string|nil 原始道具模板', '---@field Name string|nil 道具名称', '---@field Ubertip string|nil 道具说明'); Data = $items },
        @{ Name = 'buffs.lua'; Annotations = @('---@class GeneratedBuffConfig', '---@field rawcode string Buff Rawcode', '---@field _parent string|nil 原始 Buff 模板', '---@field Bufftip string|nil Buff 名称', '---@field Buffubertip string|nil Buff 说明'); Data = $buffs },
        @{ Name = 'regions.lua'; Annotations = @('---@class GeneratedRegionConfig', '---@field name string 区域名称', '---@field minX number 左边界', '---@field minY number 下边界', '---@field maxX number 右边界', '---@field maxY number 上边界'); Data = $regions },
        @{ Name = 'monster_scaling.lua'; Annotations = @('---@class MonsterScalingProfile', '---@field modeId integer PVE 模式编号', '---@field level integer 难度等级', '---@field multiplier integer 十倍定点倍率，10 代表 1 倍', '---@field healthMultiplier integer 十倍定点生命倍率', '---@field attackMultiplier integer 十倍定点攻击倍率', '---@field armorBonus integer 护甲加成', '---@field goldMultiplierPercent integer 金币倍率百分比', '---@field experienceMultiplierPercent integer 经验倍率百分比', '---@field groupIndex integer 隐藏属性技能组下标', '---@field abilityLevel integer 隐藏属性技能等级', '---@class MonsterScalingUnitAbilities', '---@field healthAbilities string[] 生命加成技能组', '---@field attackAbilities string[] 攻击加成技能组'); Data = $scalingData.luaData },
        @{ Name = 'boss_affixes.lua'; Annotations = @('---@class BossAffixConfig', '---@field affixId string 词缀编号', '---@field bossRawcode string 对应 Boss Rawcode', '---@field name string 词缀显示名称', '---@field description string 词缀说明', '---@field kind string 原生物编词缀类型', '---@field baseValue integer 基础数值', '---@field secondaryValue integer 次级数值', '---@field duration integer 基础持续时间', '---@field refillLife boolean 添加后是否回满生命', '---@field indicatorAbilityRawcode string 状态栏图标辅助光环 Rawcode', '---@field indicatorBuffRawcode string 状态栏图标 Buff Rawcode', '---@field globalAbilities string[]|nil 五个难度技能组 Rawcode', '---@field unitAbilities table<string, string[]>|nil 按小怪 Rawcode 生成的五个难度技能组'); Data = $bossAffixData.luaData },
        @{ Name = 'gold.lua'; Annotations = @('---@class GoldSettings', '---@field initialGold integer 本局初始金币', '---@field maxGoldDropBonusPercent integer 金币掉落加成上限', '---@field maxGold integer 原生金币上限', '---@class GoldConfig', '---@field settings GoldSettings', '---@field rewards table<string, table<string, integer>> 怪物金币奖励'); Data = $goldData },
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
            '---@class EquipmentDropConfig',
            '---@field dropId string 掉落规则 ID',
            '---@field unitRawcode string 怪物 Rawcode',
            '---@field chance integer 掉落概率',
            '---@field levelMin integer 最低等级',
            '---@field levelMax integer 最高等级',
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

    New-Item -ItemType Directory -Force -Path $tableDirectory, $configDirectory | Out-Null
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
            Write-LuaModule $sourcePath $definition.Annotations $definition.Data
            $stagedOutputs.Add([pscustomobject]@{ Source = $sourcePath; Destination = Join-Path $configDirectory $definition.Name })
        }
        foreach ($output in $stagedOutputs) {
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

    Write-Host "[ok] Excel 配置、LNI 表与 Lua 表已生成：$configDirectory"
    exit 0
} catch {
    Write-Error "配置生成失败：$($_.Exception.Message)"
    exit 1
}
