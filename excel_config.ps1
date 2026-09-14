Set-StrictMode -Version Latest

# Workbook metadata is reused because several configurations read multiple sheets
# from the same xlsx file during a single generator run.
$script:XlsxWorkbookMetadataCache = @{}
$script:XlsxColumnIndexCache = @{}
$script:ExcelTypeDescriptorCache = @{}

function Get-XlsxZipEntryText {
    param(
        [Parameter(Mandatory = $true)][System.IO.Compression.ZipArchive]$Archive,
        [Parameter(Mandatory = $true)][string]$EntryPath
    )

    $entry = $Archive.GetEntry($EntryPath)
    if ($null -eq $entry) {
        throw "Excel 文件缺少必要条目：$EntryPath"
    }

    $stream = $entry.Open()
    $reader = [System.IO.StreamReader]::new($stream, [System.Text.UTF8Encoding]::new($false), $true)
    try {
        return $reader.ReadToEnd()
    } finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Get-XlsxTextContent {
    param(
        [AllowNull()][System.Xml.XmlNode]$Node,
        [Parameter(Mandatory = $true)][System.Xml.XmlNamespaceManager]$NamespaceManager
    )

    if ($null -eq $Node) {
        return ''
    }

    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($textNode in $Node.SelectNodes('.//main:t', $NamespaceManager)) {
        $parts.Add($textNode.InnerText)
    }
    if ($parts.Count -gt 0) {
        return [string]::Join('', $parts)
    }
    return $Node.InnerText
}

function Convert-XlsxColumnReferenceToIndex {
    param([Parameter(Mandatory = $true)][string]$CellReference)

    $columnLength = 0
    while ($columnLength -lt $CellReference.Length) {
        $characterCode = [int][char]$CellReference[$columnLength]
        if ($characterCode -lt 65 -or $characterCode -gt 90) { break }
        $columnLength++
    }
    if ($columnLength -eq 0 -or $CellReference.Substring($columnLength) -notmatch '^[1-9][0-9]*$') {
        throw "Excel 单元格引用无效：$CellReference"
    }

    $columnName = $CellReference.Substring(0, $columnLength)
    if ($script:XlsxColumnIndexCache.ContainsKey($columnName)) {
        return $script:XlsxColumnIndexCache[$columnName]
    }

    $index = 0
    foreach ($character in $columnName.ToCharArray()) {
        $index = ($index * 26) + (([int][char]$character) - ([int][char]'A') + 1)
    }
    $index--
    $script:XlsxColumnIndexCache[$columnName] = $index
    return $index
}

function Convert-XlsxColumnIndexToName {
    param([Parameter(Mandatory = $true)][int]$Index)

    $value = $Index + 1
    $name = ''
    while ($value -gt 0) {
        $remainder = [int](($value - 1) % 26)
        $name = [string][char](([int][char]'A') + $remainder) + $name
        $value = [int][math]::Floor(($value - 1) / 26)
    }
    return $name
}

function Get-XlsxWorksheetEntryPath {
    param(
        [Parameter(Mandatory = $true)][System.IO.Compression.ZipArchive]$Archive,
        [Parameter(Mandatory = $true)][string]$WorkbookPath,
        [Parameter(Mandatory = $true)][string]$SheetName
    )

    $metadata = Get-XlsxWorkbookMetadata $Archive $WorkbookPath
    if (-not $metadata.SheetPaths.ContainsKey($SheetName)) {
        throw "Excel 工作表不存在：$SheetName"
    }
    return $metadata.SheetPaths[$SheetName]
}

function Read-XlsxSharedStrings {
    param([Parameter(Mandatory = $true)][System.IO.Compression.ZipArchive]$Archive)

    if ($null -eq $Archive.GetEntry('xl/sharedStrings.xml')) {
        return ,([string[]]@())
    }

    [xml]$sharedStringsXml = Get-XlsxZipEntryText $Archive 'xl/sharedStrings.xml'
    $namespaceManager = [System.Xml.XmlNamespaceManager]::new($sharedStringsXml.NameTable)
    $namespaceManager.AddNamespace('main', 'http://schemas.openxmlformats.org/spreadsheetml/2006/main')
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($item in $sharedStringsXml.SelectNodes('/main:sst/main:si', $namespaceManager)) {
        $result.Add((Get-XlsxTextContent $item $namespaceManager))
    }
    return ,([string[]]$result.ToArray())
}

function Get-XlsxWorkbookMetadata {
    param(
        [Parameter(Mandatory = $true)][System.IO.Compression.ZipArchive]$Archive,
        [Parameter(Mandatory = $true)][string]$WorkbookPath
    )

    $archivePath = [System.IO.Path]::GetFullPath($WorkbookPath)
    if ($script:XlsxWorkbookMetadataCache.ContainsKey($archivePath)) {
        return $script:XlsxWorkbookMetadataCache[$archivePath]
    }

    [xml]$workbook = Get-XlsxZipEntryText $Archive 'xl/workbook.xml'
    [xml]$relationships = Get-XlsxZipEntryText $Archive 'xl/_rels/workbook.xml.rels'
    $namespaceManager = [System.Xml.XmlNamespaceManager]::new($workbook.NameTable)
    $namespaceManager.AddNamespace('main', 'http://schemas.openxmlformats.org/spreadsheetml/2006/main')
    $namespaceManager.AddNamespace('package', 'http://schemas.openxmlformats.org/package/2006/relationships')

    $sheetPaths = @{}
    foreach ($sheet in $workbook.SelectNodes('/main:workbook/main:sheets/main:sheet', $namespaceManager)) {
        $sheetName = $sheet.GetAttribute('name')
        $relationshipId = $sheet.GetAttribute('id', 'http://schemas.openxmlformats.org/officeDocument/2006/relationships')
        if ([string]::IsNullOrWhiteSpace($relationshipId)) {
            throw "Excel 工作表关系缺失：$archivePath / $sheetName"
        }
        $relationship = $relationships.SelectSingleNode("/package:Relationships/package:Relationship[@Id='$relationshipId']", $namespaceManager)
        if ($null -eq $relationship) {
            throw "Excel 工作表关系无效：$archivePath / $sheetName"
        }
        $target = $relationship.GetAttribute('Target')
        if ([string]::IsNullOrWhiteSpace($target)) {
            throw "Excel 工作表目标无效：$archivePath / $sheetName"
        }
        $normalizedTarget = $target.Replace('\', '/').TrimStart('/')
        if (-not $normalizedTarget.StartsWith('xl/')) {
            $normalizedTarget = 'xl/' + $normalizedTarget
        }
        $sheetPaths[$sheetName] = $normalizedTarget
    }

    $metadata = [pscustomobject]@{
        SheetPaths = $sheetPaths
        SharedStrings = Read-XlsxSharedStrings $Archive
    }
    $script:XlsxWorkbookMetadataCache[$archivePath] = $metadata
    return $metadata
}

function Read-XlsxCellRows {
    param(
        [Parameter(Mandatory = $true)][System.IO.Compression.ZipArchive]$Archive,
        [Parameter(Mandatory = $true)][string]$WorkbookPath,
        [Parameter(Mandatory = $true)][string]$SheetName
    )

    $worksheetPath = Get-XlsxWorksheetEntryPath $Archive $WorkbookPath $SheetName
    [xml]$worksheet = Get-XlsxZipEntryText $Archive $worksheetPath
    $namespaceManager = [System.Xml.XmlNamespaceManager]::new($worksheet.NameTable)
    $namespaceManager.AddNamespace('main', 'http://schemas.openxmlformats.org/spreadsheetml/2006/main')
    $sharedStrings = (Get-XlsxWorkbookMetadata $Archive $WorkbookPath).SharedStrings
    $rows = @{}
    foreach ($row in $worksheet.SelectNodes('/main:worksheet/main:sheetData/main:row', $namespaceManager)) {
        $rowIndex = 0
        if (-not [int]::TryParse($row.GetAttribute('r'), [ref]$rowIndex) -or $rowIndex -le 0) {
            throw "Excel 行号无效：$SheetName"
        }
        $cells = @{}
        foreach ($cell in $row.SelectNodes('main:c', $namespaceManager)) {
            $cellReference = $cell.GetAttribute('r')
            $columnIndex = Convert-XlsxColumnReferenceToIndex $cellReference
            $cellType = $cell.GetAttribute('t')
            if ($cellType -eq 'inlineStr') {
                $cellValue = Get-XlsxTextContent $cell $namespaceManager
            } else {
                $valueNode = $cell.SelectSingleNode('main:v', $namespaceManager)
                if ($null -eq $valueNode) {
                    $cellValue = $null
                } else {
                    $cellValue = $valueNode.InnerText
                    if ($cellType -eq 's') {
                        $sharedStringIndex = 0
                        if (-not [int]::TryParse($cellValue, [ref]$sharedStringIndex) -or $sharedStringIndex -lt 0 -or $sharedStringIndex -ge $sharedStrings.Count) {
                            throw "Excel 共享字符串索引无效：$cellValue"
                        }
                        $cellValue = $sharedStrings[$sharedStringIndex]
                    } elseif ($cellType -eq 'b') {
                        $cellValue = if ($cellValue -eq '1') { 'true' } else { 'false' }
                    }
                }
            }
            $cells[$columnIndex] = $cellValue
        }
        $rows[$rowIndex] = $cells
    }
    return $rows
}

function Get-XlsxMappedCellValue {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Rows,
        [Parameter(Mandatory = $true)][int]$Row,
        [Parameter(Mandatory = $true)][int]$Column
    )

    if (-not $Rows.ContainsKey($Row) -or -not $Rows[$Row].ContainsKey($Column)) {
        return $null
    }
    return $Rows[$Row][$Column]
}

function ConvertFrom-ExcelScalar {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][ValidateSet('string', 'int', 'real', 'bool')][string]$Type,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $trimmed = $Text.Trim()
    if ($Type -eq 'string') {
        if ($trimmed -eq '""') {
            return ''
        }
        if ($trimmed.Length -ge 2 -and $trimmed.StartsWith('"') -and $trimmed.EndsWith('"')) {
            return $trimmed.Substring(1, $trimmed.Length - 2)
        }
        return $Text
    }

    if ($Type -eq 'bool') {
        if ($trimmed -eq 'true' -or $trimmed -eq '1') { return $true }
        if ($trimmed -eq 'false' -or $trimmed -eq '0') { return $false }
        throw "$Context 需要 bool 值（true/false/0/1），实际为：$Text"
    }

    if ($Type -eq 'int') {
        $integer = 0
        if (-not [int]::TryParse($trimmed, [System.Globalization.NumberStyles]::Integer, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$integer)) {
            throw "$Context 需要 int 值，实际为：$Text"
        }
        return $integer
    }

    if ($Type -eq 'real') {
        $real = 0.0
        if ((-not [double]::TryParse($trimmed, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$real)) -or ([double]::IsNaN($real)) -or ([double]::IsInfinity($real))) {
            throw "$Context 需要 real 值，实际为：$Text"
        }
        return $real
    }

    throw "$Context 使用了未知字段类型：$Type"
}

function ConvertFrom-ExcelTypedValue {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$Type,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $descriptor = $script:ExcelTypeDescriptorCache[$Type]
    if ($null -eq $descriptor) {
        $arrayType = $null
        $scalarType = $null
        foreach ($alternative in $Type.Split('|')) {
            $candidate = $alternative.Trim()
            if ($candidate.Length -eq 0) { continue }
            if ($candidate.EndsWith('[]')) {
                if ($null -eq $arrayType) { $arrayType = $candidate }
            } elseif ($null -eq $scalarType) {
                $scalarType = $candidate
            }
        }
        if ($null -eq $arrayType -and $null -eq $scalarType) {
            throw "$Context 缺少字段类型"
        }
        $descriptor = [pscustomobject]@{
            ArrayType = $arrayType
            ScalarType = $scalarType
        }
        $script:ExcelTypeDescriptorCache[$Type] = $descriptor
    }

    $trimmed = $Text.Trim()
    if ($trimmed.StartsWith('{') -or $trimmed.EndsWith('}')) {
        if (-not ($trimmed.StartsWith('{') -and $trimmed.EndsWith('}'))) {
            throw "$Context 数组格式不完整：$Text"
        }
        if ($null -eq $descriptor.ArrayType) {
            throw "$Context 不接受数组值：$Text"
        }
        $elementType = $descriptor.ArrayType.Substring(0, $descriptor.ArrayType.Length - 2)
        $inner = $trimmed.Substring(1, $trimmed.Length - 2).Trim()
        if ($inner.Length -eq 0) {
            return ,([object[]]@())
        }
        $values = New-Object System.Collections.Generic.List[object]
        foreach ($part in Split-LniArray $inner) {
            $values.Add((ConvertFrom-ExcelScalar $part $elementType $Context))
        }
        return ,($values.ToArray())
    }

    if ($null -eq $descriptor.ScalarType) {
        throw "$Context 需要数组值：$Text"
    }
    return ConvertFrom-ExcelScalar $Text $descriptor.ScalarType $Context
}

function Read-ExcelObjectTable {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$SheetName,
        [Parameter(Mandatory = $true)][string]$IdField
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "找不到 Excel 配置源：$Path"
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $rows = Read-XlsxCellRows $archive $Path $SheetName
        if (-not $rows.ContainsKey(3)) {
            throw "Excel 缺少第 3 行字段属性：$Path / $SheetName"
        }

        $fieldColumns = @($rows[3].Keys | Sort-Object)
        $fields = New-Object System.Collections.Generic.List[object]
        $fieldNames = @{}
        foreach ($column in $fieldColumns) {
            $fieldName = Get-XlsxMappedCellValue $rows 3 $column
            if ($null -eq $fieldName -or ([string]$fieldName).Length -eq 0) {
                continue
            }
            $fieldName = [string]$fieldName
            if ($fieldNames.ContainsKey($fieldName)) {
                throw "Excel 字段属性重复：$Path / $SheetName / $(Convert-XlsxColumnIndexToName $column)3 / $fieldName"
            }
            $fieldType = Get-XlsxMappedCellValue $rows 2 $column
            if ($null -eq $fieldType -or [string]::IsNullOrWhiteSpace([string]$fieldType)) {
                throw "Excel 字段类型为空：$Path / $SheetName / $(Convert-XlsxColumnIndexToName $column)2"
            }
            $fields.Add([pscustomobject]@{
                Column = $column
                ColumnName = Convert-XlsxColumnIndexToName $column
                Name = $fieldName
                Type = [string]$fieldType
            })
            $fieldNames[$fieldName] = $true
        }

        if ($fields.Count -eq 0 -or $fields[0].Name -ne $IdField) {
            throw "Excel 首列字段属性必须为 $IdField：$Path / $SheetName"
        }
        if ($fields[0].Type -ne 'string') {
            throw "Excel ID 字段类型必须为 string：$Path / $SheetName / $IdField"
        }

        $dataFields = @($fields.ToArray() | Select-Object -Skip 1)
        $idColumn = $fields[0].Column
        $sections = [ordered]@{}
        $maxRow = @($rows.Keys | Measure-Object -Maximum).Maximum
        for ($row = 4; $row -le $maxRow; $row = $row + 1) {
            $rowCells = $rows[$row]
            $idCell = $null
            if ($null -ne $rowCells -and $rowCells.ContainsKey($idColumn)) {
                $idCell = $rowCells[$idColumn]
            }
            $idText = if ($null -eq $idCell) { '' } else { [string]$idCell }
            if ($idText.Length -eq 0) {
                $hasOtherValues = $false
                foreach ($field in $dataFields) {
                    if ($null -ne $rowCells -and $rowCells.ContainsKey($field.Column)) {
                        $cell = $rowCells[$field.Column]
                        if ($null -ne $cell -and ([string]$cell).Length -gt 0) {
                            $hasOtherValues = $true
                            break
                        }
                    }
                }
                if ($hasOtherValues) {
                    throw "Excel 数据行缺少 ID：$Path / $SheetName / A$row"
                }
                continue
            }
            if ($idText.Trim() -eq '""') {
                throw "Excel ID 不能为显式空字符串：$Path / $SheetName / A$row"
            }
            if ($sections.Contains($idText)) {
                throw "Excel ID 重复：$Path / $SheetName / A$row / $idText"
            }

            $entry = [ordered]@{}
            foreach ($field in $dataFields) {
                if ($null -eq $rowCells -or -not $rowCells.ContainsKey($field.Column)) { continue }
                $cell = $rowCells[$field.Column]
                if ($null -eq $cell -or ([string]$cell).Length -eq 0) {
                    continue
                }
                $cellName = $field.ColumnName + $row
                $entry[$field.Name] = ConvertFrom-ExcelTypedValue ([string]$cell) $field.Type "$Path / $SheetName / $cellName"
            }
            $sections[$idText] = $entry
        }

        if ($sections.Count -eq 0) {
            throw "Excel 配置表不包含数据：$Path / $SheetName"
        }
        return [pscustomobject]@{
            Fields = $fields.ToArray()
            Sections = $sections
        }
    } finally {
        $archive.Dispose()
    }
}

function Read-ExcelTypedRows {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$SheetName
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "找不到 Excel 配置源：$Path"
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $rows = Read-XlsxCellRows $archive $Path $SheetName
        if (-not $rows.ContainsKey(3)) {
            throw "Excel 缺少第 3 行字段属性：$Path / $SheetName"
        }

        $fieldColumns = @($rows[3].Keys | Sort-Object)
        $fields = New-Object System.Collections.Generic.List[object]
        $fieldNames = @{}
        foreach ($column in $fieldColumns) {
            $fieldName = Get-XlsxMappedCellValue $rows 3 $column
            if ($null -eq $fieldName -or ([string]$fieldName).Length -eq 0) {
                continue
            }
            $fieldName = [string]$fieldName
            if ($fieldNames.ContainsKey($fieldName)) {
                throw "Excel 字段属性重复：$Path / $SheetName / $(Convert-XlsxColumnIndexToName $column)3 / $fieldName"
            }
            $fieldType = Get-XlsxMappedCellValue $rows 2 $column
            if ($null -eq $fieldType -or [string]::IsNullOrWhiteSpace([string]$fieldType)) {
                throw "Excel 字段类型为空：$Path / $SheetName / $(Convert-XlsxColumnIndexToName $column)2"
            }
            $fields.Add([pscustomobject]@{
                Column = $column
                ColumnName = Convert-XlsxColumnIndexToName $column
                Name = $fieldName
                Type = [string]$fieldType
            })
            $fieldNames[$fieldName] = $true
        }
        if ($fields.Count -eq 0) {
            throw "Excel 不包含字段属性：$Path / $SheetName"
        }

        $typedRows = New-Object System.Collections.Generic.List[object]
        $maxRow = @($rows.Keys | Measure-Object -Maximum).Maximum
        for ($row = 4; $row -le $maxRow; $row = $row + 1) {
            $rowCells = $rows[$row]
            $entry = [ordered]@{}
            foreach ($field in $fields) {
                if ($null -eq $rowCells -or -not $rowCells.ContainsKey($field.Column)) { continue }
                $cell = $rowCells[$field.Column]
                if ($null -eq $cell -or ([string]$cell).Length -eq 0) {
                    continue
                }
                $cellName = $field.ColumnName + $row
                $entry[$field.Name] = ConvertFrom-ExcelTypedValue ([string]$cell) $field.Type "$Path / $SheetName / $cellName"
            }
            if ($entry.Count -gt 0) {
                $typedRows.Add([pscustomobject]@{
                    Row = $row
                    Data = $entry
                })
            }
        }
        return [pscustomobject]@{
            Fields = $fields.ToArray()
            Rows = $typedRows.ToArray()
        }
    } finally {
        $archive.Dispose()
    }
}

function ConvertTo-LniValue {
    param([Parameter(Mandatory = $true)][AllowNull()][object]$Value)

    if ($Value -is [string]) {
        $escaped = $Value.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
        return '"' + $escaped + '"'
    }
    if ($Value -is [bool]) {
        return if ($Value) { 'true' } else { 'false' }
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($entry in $Value) {
            $parts.Add((ConvertTo-LniValue $entry))
        }
        return '{ ' + ([string]::Join(', ', $parts)) + ' }'
    }
    if ($Value -is [System.IFormattable]) {
        if ($Value -is [double] -or $Value -is [float] -or $Value -is [decimal]) {
            $numericValue = [double]$Value
            if ([double]::IsNaN($numericValue) -or [double]::IsInfinity($numericValue)) {
                throw "配置输出不接受非有限数字：$Value"
            }
            if ($numericValue -eq 0) {
                return '0'
            }
            return $Value.ToString('0.############################', [System.Globalization.CultureInfo]::InvariantCulture)
        }
        return $Value.ToString($null, [System.Globalization.CultureInfo]::InvariantCulture)
    }
    throw "不支持生成 LNI 的值类型：$($Value.GetType().FullName)"
}

function ConvertTo-LniText {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Sections)

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($rawcode in $Sections.Keys) {
        $lines.Add("[$rawcode]")
        foreach ($field in $Sections[$rawcode].Keys) {
            $lines.Add("$field = $(ConvertTo-LniValue $Sections[$rawcode][$field])")
        }
        $lines.Add('')
    }
    return ([string]::Join("`n", $lines)).TrimEnd() + "`n"
}
