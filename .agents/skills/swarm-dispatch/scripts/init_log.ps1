param (
    [Parameter(Mandatory=$true)]
    [string]$TaskSlug,

    [Parameter(Mandatory=$true)]
    [string]$TaskTitle,

    [Parameter(Mandatory=$false)]
    [string]$AgentName = "lead-architect"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$today = Get-Date -Format "yyyy-MM-dd"
$now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$logFileName = "${today}_${TaskSlug}.md"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path

# Target docs\logs directory
$resolvedLogDir = Join-Path -Path $repoRoot -ChildPath "docs\logs"

if (-not (Test-Path $resolvedLogDir)) {
    New-Item -ItemType Directory -Path $resolvedLogDir -Force | Out-Null
}

$logFilePath = Join-Path -Path $resolvedLogDir -ChildPath $logFileName
$indexFilePath = Join-Path -Path $resolvedLogDir -ChildPath "README.md"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if (Test-Path $logFilePath) {
    Write-Host "Log file already exists: $logFilePath"
} else {
    $template = @"
# 📋 Nhật Ký Thực Thi: $TaskTitle

- **Ngày thực hiện**: $now
- **Agent phụ trách**: `$AgentName`
- **Yêu cầu gốc**: $TaskTitle
- **Trạng thái**: 🔄 Đang tiến hành

---

## 1. Phân Tích & Kế Hoạch (Analysis & Planning)
- Bối cảnh & Mục tiêu kỹ thuật:
- Các thành phần/module liên quan (Child Agent / Backend / Parent App):
- Phân chia nhiệm vụ cho các Agent:

## 2. Chi Tiết Các Bước Thực Hiện (Execution Steps)
- **Bước 1**: 
- **Bước 2**: 

## 3. Danh Sách Tệp Thay Đổi (Impacted Files)
- ``[Created]`` ``path/to/file`` - Mô tả
- ``[Modified]`` ``path/to/file`` - Mô tả

## 4. Kiểm Thử & Đánh Giá Bảo Mật (Verification & Security Audit)
- Kiểm tra build / tests.
- Rà soát nguy cơ bypass (Safe mode, Force stop, Time change, Re-enable).
- Đánh giá ảnh hưởng tới pin và bộ nhớ.

## 5. Kết Luận & Hướng Dẫn Tiếp Theo (Conclusion & Next Steps)
- Tóm tắt kết quả.
- Đề xuất các bước tiếp theo trong lộ trình Epic.
"@
    [System.IO.File]::WriteAllText($logFilePath, $template, $utf8NoBom)
    Write-Host "Created log file: $logFilePath"
}

# Ensure index README.md exists
if (-not (Test-Path $indexFilePath)) {
    $indexHeader = @"
# 📑 Nhật Ký Thực Thi Dự Án MDM Parental Control (Audit & Execution Logs)

Tài liệu này lưu trữ danh mục toàn bộ các bước triển khai, sửa lỗi, cấu hình và kiểm thử của hệ thống Swarm Agent trong dự án **MDM Parental Control**.

| Ngày | Tệp Nhật Ký | Nội Dung Nhiệm Vụ | Agent Phụ Trách | Trạng Thái |
| :--- | :--- | :--- | :--- | :--- |
"@
    [System.IO.File]::WriteAllText($indexFilePath, $indexHeader, $utf8NoBom)
}

# Add to README.md index if not already present
$content = [System.IO.File]::ReadAllText($indexFilePath, [System.Text.Encoding]::UTF8)
if ($content -notmatch [regex]::Escape($logFileName)) {
    $newRow = "| {0} | [``{1}``](./{1}) | {2} | ``{3}`` | 🔄 Đang tiến hành |`r`n" -f $today, $logFileName, $TaskTitle, $AgentName
    $pattern = "(\| :--- \| :--- \| :--- \| :--- \| :--- \|\r?\n)"
    if ($content -match $pattern) {
        $updatedContent = $content -replace $pattern, "`$1$newRow"
        [System.IO.File]::WriteAllText($indexFilePath, $updatedContent, $utf8NoBom)
        Write-Host "Updated index in $indexFilePath"
    } else {
        [System.IO.File]::AppendAllText($indexFilePath, $newRow, $utf8NoBom)
        Write-Host "Appended index to $indexFilePath"
    }
}
