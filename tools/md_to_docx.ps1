param(
    [Parameter(Mandatory = $true)]
    [string]$InputMarkdown,

    [Parameter(Mandatory = $true)]
    [string]$OutputDocx
)

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Escape-XmlText {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    return [System.Security.SecurityElement]::Escape($Text)
}

function New-RunXml {
    param(
        [string]$Text,
        [switch]$Code
    )

    $safe = Escape-XmlText $Text
    if ($Code) {
        return "<w:r><w:rPr><w:rFonts w:ascii=`"Consolas`" w:hAnsi=`"Consolas`" w:eastAsia=`"Consolas`"/><w:sz w:val=`"20`"/></w:rPr><w:t xml:space=`"preserve`">$safe</w:t></w:r>"
    }
    return "<w:r><w:rPr><w:rFonts w:ascii=`"Calibri`" w:hAnsi=`"Calibri`" w:eastAsia=`"宋体`"/><w:sz w:val=`"21`"/></w:rPr><w:t xml:space=`"preserve`">$safe</w:t></w:r>"
}

function New-ParagraphXml {
    param(
        [string]$Text,
        [string]$Style = "",
        [switch]$Code
    )

    $pPr = ""
    if ($Style.Length -gt 0) {
        $pPr = "<w:pPr><w:pStyle w:val=`"$Style`"/></w:pPr>"
    }
    return "<w:p>$pPr$(New-RunXml -Text $Text -Code:$Code)</w:p>"
}

function New-TableXml {
    param([string[]]$Rows)

    $xml = @()
    $xml += "<w:tbl>"
    $xml += "<w:tblPr><w:tblStyle w:val=`"TableGrid`"/><w:tblW w:w=`"0`" w:type=`"auto`"/><w:tblBorders><w:top w:val=`"single`" w:sz=`"4`" w:space=`"0`" w:color=`"auto`"/><w:left w:val=`"single`" w:sz=`"4`" w:space=`"0`" w:color=`"auto`"/><w:bottom w:val=`"single`" w:sz=`"4`" w:space=`"0`" w:color=`"auto`"/><w:right w:val=`"single`" w:sz=`"4`" w:space=`"0`" w:color=`"auto`"/><w:insideH w:val=`"single`" w:sz=`"4`" w:space=`"0`" w:color=`"auto`"/><w:insideV w:val=`"single`" w:sz=`"4`" w:space=`"0`" w:color=`"auto`"/></w:tblBorders></w:tblPr>"

    foreach ($row in $Rows) {
        if ($row -match '^\|\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$') {
            continue
        }

        $trimmed = $row.Trim()
        if ($trimmed.StartsWith("|")) { $trimmed = $trimmed.Substring(1) }
        if ($trimmed.EndsWith("|")) { $trimmed = $trimmed.Substring(0, $trimmed.Length - 1) }
        $cells = $trimmed -split '\|'

        $xml += "<w:tr>"
        foreach ($cell in $cells) {
            $text = ($cell.Trim() -replace '`', '')
            $xml += "<w:tc><w:tcPr><w:tcW w:w=`"0`" w:type=`"auto`"/></w:tcPr>$(New-ParagraphXml -Text $text)</w:tc>"
        }
        $xml += "</w:tr>"
    }
    $xml += "</w:tbl>"
    return ($xml -join "")
}

function Get-BodyXml {
    param([string[]]$Lines)

    $body = New-Object System.Collections.Generic.List[string]
    $i = 0
    $inCode = $false

    while ($i -lt $Lines.Count) {
        $line = $Lines[$i]

        if ($line -match '^```') {
            $inCode = -not $inCode
            $i++
            continue
        }

        if ($inCode) {
            $body.Add((New-ParagraphXml -Text $line -Code))
            $i++
            continue
        }

        if ($line.Trim().Length -eq 0) {
            $body.Add("<w:p/>")
            $i++
            continue
        }

        if ($line.TrimStart().StartsWith("|")) {
            $rows = New-Object System.Collections.Generic.List[string]
            while ($i -lt $Lines.Count -and $Lines[$i].TrimStart().StartsWith("|")) {
                $rows.Add($Lines[$i])
                $i++
            }
            $body.Add((New-TableXml -Rows $rows.ToArray()))
            continue
        }

        if ($line -match '^(#{1,6})\s+(.*)$') {
            $level = $Matches[1].Length
            $text = $Matches[2]
            $style = "Heading$([Math]::Min($level, 3))"
            if ($level -eq 1) {
                $body.Add((New-ParagraphXml -Text $text -Style "Title"))
            } else {
                $body.Add((New-ParagraphXml -Text $text -Style $style))
            }
            $i++
            continue
        }

        $plain = $line -replace '`', ''
        $body.Add((New-ParagraphXml -Text $plain))
        $i++
    }

    return ($body.ToArray() -join "`n")
}

function Write-ZipEntry {
    param(
        [System.IO.Compression.ZipArchive]$Zip,
        [string]$Name,
        [string]$Content
    )

    $entry = $Zip.CreateEntry($Name)
    $stream = $entry.Open()
    $writer = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::UTF8)
    $writer.Write($Content)
    $writer.Dispose()
    $stream.Dispose()
}

$inputPath = Resolve-Path -LiteralPath $InputMarkdown
$outPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputDocx))
$outDir = [System.IO.Path]::GetDirectoryName($outPath)
if (!(Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

$lines = Get-Content -LiteralPath $inputPath -Encoding UTF8
$bodyXml = Get-BodyXml -Lines $lines

$documentXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    $bodyXml
    <w:sectPr>
      <w:pgSz w:w="11906" w:h="16838"/>
      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/>
    </w:sectPr>
  </w:body>
</w:document>
"@

$contentTypes = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>
"@

$rels = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
"@

$styles = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="宋体"/><w:sz w:val="21"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:pPr><w:jc w:val="center"/><w:spacing w:after="240"/></w:pPr><w:rPr><w:b/><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="黑体"/><w:sz w:val="36"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="240" w:after="120"/></w:pPr><w:rPr><w:b/><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="黑体"/><w:sz w:val="30"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="180" w:after="100"/></w:pPr><w:rPr><w:b/><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="黑体"/><w:sz w:val="26"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="280" w:after="160"/></w:pPr><w:rPr><w:b/><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="黑体"/><w:sz w:val="32"/></w:rPr></w:style>
  <w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/><w:tblPr><w:tblBorders><w:top w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:left w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:bottom w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:right w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:insideH w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:insideV w:val="single" w:sz="4" w:space="0" w:color="auto"/></w:tblBorders></w:tblPr></w:style>
</w:styles>
"@

if (Test-Path -LiteralPath $outPath) {
    Remove-Item -LiteralPath $outPath -Force
}

$zip = [System.IO.Compression.ZipFile]::Open($outPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    Write-ZipEntry -Zip $zip -Name "[Content_Types].xml" -Content $contentTypes
    Write-ZipEntry -Zip $zip -Name "_rels/.rels" -Content $rels
    Write-ZipEntry -Zip $zip -Name "word/document.xml" -Content $documentXml
    Write-ZipEntry -Zip $zip -Name "word/styles.xml" -Content $styles
} finally {
    $zip.Dispose()
}

Write-Output "Generated $outPath"
