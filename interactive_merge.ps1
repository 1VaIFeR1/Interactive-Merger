<#
.SYNOPSIS
    Interactive Project Merger powered by eza.
    v2.10 — Возврат к классическому UI + поле кастомного пути объединения.
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$InputPath
)

# ========================= ИНИЦИАЛИЗАЦИЯ =========================
$global:ScriptStartTime = Get-Date
$global:StepNumber = 0
$global:DebugMode = $true

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR","SUCCESS","DEBUG","STEP","DIVIDER")]
        [string]$Level = "INFO"
    )

    $timestamp = (Get-Date).ToString("HH:mm:ss.fff")
    $elapsed = ((Get-Date) - $global:ScriptStartTime).TotalSeconds
    $elapsedStr = "[{0:F1}s]" -f $elapsed

    switch ($Level) {
        "DIVIDER" {
            Write-Host ""
            Write-Host ("=" * 80) -ForegroundColor DarkGray
            Write-Host ""
        }
        "STEP" {
            $global:StepNumber++
            Write-Host ""
            Write-Host ("─" * 70) -ForegroundColor DarkCyan
            Write-Host "  ► STEP $($global:StepNumber): $Message" -ForegroundColor Cyan
            Write-Host ("─" * 70) -ForegroundColor DarkCyan
        }
        "INFO"    { Write-Host "$timestamp $elapsedStr [INFO]    $Message" -ForegroundColor Gray }
        "WARN"    { Write-Host "$timestamp $elapsedStr [WARN]    $Message" -ForegroundColor Yellow }
        "ERROR"   { Write-Host "$timestamp $elapsedStr [ERROR]   $Message" -ForegroundColor Red }
        "SUCCESS" { Write-Host "$timestamp $elapsedStr [OK]      $Message" -ForegroundColor Green }
        "DEBUG"   { if ($global:DebugMode) { Write-Host "$timestamp $elapsedStr [DEBUG]   $Message" -ForegroundColor DarkGray } }
    }
}

# --- БАННЕР ---
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║         Interactive Project Merger v2.10 (eza)              ║" -ForegroundColor Magenta
Write-Host "║         Классический UI + кастомный путь объединения       ║" -ForegroundColor Magenta
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host ""

Write-Log "Скрипт запущен: $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')" "INFO"
Write-Log "PowerShell: $($PSVersionTable.PSVersion)" "INFO"
Write-Log "Рабочий каталог: $(Get-Location)" "INFO"

# --- НАСТРОЙКИ ---
$PythonScriptPath = "C:\Programs\Scripts\MD_To_PDF\md_to_pdf.py"

$script:ActiveExcludes = [System.Collections.ArrayList]@(
    ".git", ".vs", "bin", "obj", "node_modules",
    "venv", ".venv", "env", ".idea", "__pycache__",
    ".mypy_cache", ".pytest_cache", ".tox", "dist",
    "build", ".eggs", "*.egg-info", ".sass-cache",
    ".cache", ".parcel-cache", "coverage", ".nyc_output",
    ".next", ".nuxt", ".svelte-kit", "target"
)

$BlockedExts = @(
    ".exe", ".dll", ".png", ".jpg", ".jpeg", ".gif", ".bmp",
    ".zip", ".rar", ".7z", ".tar", ".gz", ".pdf", ".pyc",
    ".class", ".so", ".lib", ".bin", ".obj", ".iso",
    ".mp4", ".mp3", ".wav", ".ogg", ".ico", ".ttf",
    ".woff", ".woff2", ".eot", ".pdb", ".cache",
    ".sqlite", ".db", ".lock", ".sum"
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Write-Log "WinForms загружены" "DEBUG"

# ========================= ОПРЕДЕЛЕНИЕ ПАПКИ =========================
Write-Log "Определение рабочей директории" "STEP"

if ($InputPath.Count -gt 0) {
    Write-Log "Входные параметры: $($InputPath -join ', ')" "INFO"
    if ($InputPath.Count -eq 1 -and (Test-Path $InputPath[0] -PathType Container)) {
        $baseDir = $InputPath[0]
    } else {
        $baseDir = Split-Path -Parent $InputPath[0]
    }
} else {
    $baseDir = Get-Location
    Write-Log "Параметры не переданы — текущая директория" "WARN"
}

$baseDir = (Resolve-Path $baseDir).Path.TrimEnd('\')
Write-Log "Базовая директория: $baseDir" "SUCCESS"

if (-not (Test-Path $baseDir)) {
    Write-Log "Директория не существует!" "ERROR"
    exit 1
}

# ========================= ФУНКЦИИ =========================
function Test-IsExcludedPath {
    param([string]$FilePath, [string[]]$ExcludeNames, [string]$BaseDir)
    try {
        $relativePath = $FilePath.Substring($BaseDir.Length).TrimStart("\")
        $segments = $relativePath.Split("\")
        foreach ($segment in $segments) {
            foreach ($excl in $ExcludeNames) {
                if ($excl.Contains("*")) {
                    if ($segment -like $excl) { return $true }
                } else {
                    if ($segment -eq $excl) { return $true }
                }
            }
        }
    } catch { Write-Log "Ошибка в Test-IsExcludedPath: $_" "DEBUG" }
    return $false
}

function Test-IsTextFile {
    param([string]$FilePath)
    try {
        if (-not (Test-Path $FilePath -PathType Leaf)) { 
            Write-Log "Test-IsTextFile: файл не найден '$FilePath'" "DEBUG"
            return $false 
        }
        
        $fileInfo = New-Object System.IO.FileInfo($FilePath)
        if ($fileInfo.Length -eq 0) { return $true }
        if ($fileInfo.Length -gt 10MB) {
            Write-Log "SKIP (>10MB): $($fileInfo.Name)" "DEBUG"
            return $false
        }

        $stream = [System.IO.File]::OpenRead($FilePath)
        try {
            $bufferSize = [Math]::Min(8192, $fileInfo.Length)
            $bytes = New-Object byte[] $bufferSize
            $bytesRead = $stream.Read($bytes, 0, $bufferSize)
            if ($bytesRead -eq 0) { return $true }

            if ($bytesRead -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { return $true }
            if ($bytesRead -ge 2 -and (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF))) { return $true }

            for ($i = 0; $i -lt $bytesRead; $i++) { if ($bytes[$i] -eq 0) { return $false } }
            return $true
        } finally { $stream.Close() }
    } catch { 
        Write-Log "Test-IsTextFile ошибка: $_" "DEBUG"
        return $false 
    }
}

# ========================= GUI =========================
Write-Log "Построение GUI" "STEP"

$form = New-Object System.Windows.Forms.Form
$form.Text = "Project Merger v2.10 — $baseDir"
$form.Size = New-Object System.Drawing.Size(950, 1000)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.KeyPreview = $true

$StateTags = @("[ OO ]", "[ OX ]", "[ XO ]", "[ XX ]")
$global:TreeData = @()

# --- Инструкция ---
$lblHelp = New-Object System.Windows.Forms.Label
$lblHelp.Location = New-Object System.Drawing.Point(15, 10)
$lblHelp.Size = New-Object System.Drawing.Size(910, 50)
$lblHelp.Font = New-Object System.Drawing.Font("Consolas", 9)
$lblHelp.Text = "[ OO ] В дереве ДА, слияние ДА  |  [ OX ] В дереве ДА, слияние НЕТ  |  [ XO ] В дереве НЕТ, слияние ДА  |  [ XX ] В дереве НЕТ, слияние НЕТ`nCtrl + ЛКМ — выделить несколько. Пробел — переключить все выделенные (выделение сохранится).`nДвойной клик — один элемент. На папке — каскад для вложенных."
$form.Controls.Add($lblHelp)

# --- ПОЛЕ ПУТИ ОБЪЕДИНЕНИЯ (НОВОЕ) ---
$grpPath = New-Object System.Windows.Forms.GroupBox
$grpPath.Text = "Путь объединения"
$grpPath.Location = New-Object System.Drawing.Point(15, 65)
$grpPath.Size = New-Object System.Drawing.Size(910, 55)
$form.Controls.Add($grpPath)

$txtCustomPath = New-Object System.Windows.Forms.TextBox
$txtCustomPath.Location = New-Object System.Drawing.Point(10, 22)
$txtCustomPath.Size = New-Object System.Drawing.Size(760, 22)
$txtCustomPath.Text = $baseDir
$txtCustomPath.Font = New-Object System.Drawing.Font("Consolas", 9)
$grpPath.Controls.Add($txtCustomPath)

$btnApplyPath = New-Object System.Windows.Forms.Button
$btnApplyPath.Location = New-Object System.Drawing.Point(780, 20)
$btnApplyPath.Size = New-Object System.Drawing.Size(120, 26)
$btnApplyPath.Text = "✓ Применить"
$btnApplyPath.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnApplyPath.Add_Click({
    $newPath = $txtCustomPath.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($newPath)) { return }
    
    try {
        if (-not (Test-Path $newPath -PathType Container)) {
            [System.Windows.Forms.MessageBox]::Show("Указанный путь не существует или не является папкой!", "Ошибка", 0, 16)
            return
        }
        $resolved = (Resolve-Path $newPath).Path.TrimEnd('\')
        $script:baseDir = $resolved
        $baseDir = $resolved
        $form.Text = "Project Merger v2.10 — $baseDir"
        Write-Log "Путь изменён на: $baseDir" "INFO"
        Reload-TreeData
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Ошибка применения пути: $_", "Ошибка", 0, 16)
    }
})
$grpPath.Controls.Add($btnApplyPath)

# --- ПАНЕЛЬ ИСКЛЮЧЕНИЙ ---
$grpExcludes = New-Object System.Windows.Forms.GroupBox
$grpExcludes.Text = "Исключения (нажмите × чтобы удалить, или добавьте новое)"
$grpExcludes.Location = New-Object System.Drawing.Point(15, 128)
$grpExcludes.Size = New-Object System.Drawing.Size(910, 140)
$form.Controls.Add($grpExcludes)

$flowExcludes = New-Object System.Windows.Forms.FlowLayoutPanel
$flowExcludes.Location = New-Object System.Drawing.Point(10, 20)
$flowExcludes.Size = New-Object System.Drawing.Size(890, 80)
$flowExcludes.AutoScroll = $true
$flowExcludes.WrapContents = $true
$flowExcludes.FlowDirection = "LeftToRight"
$grpExcludes.Controls.Add($flowExcludes)

$txtNewExclude = New-Object System.Windows.Forms.TextBox
$txtNewExclude.Location = New-Object System.Drawing.Point(10, 105)
$txtNewExclude.Size = New-Object System.Drawing.Size(250, 22)
$txtNewExclude.PlaceholderText = "Новое исключение (например: .tmp)"
$grpExcludes.Controls.Add($txtNewExclude)

$btnAddExclude = New-Object System.Windows.Forms.Button
$btnAddExclude.Location = New-Object System.Drawing.Point(270, 104)
$btnAddExclude.Size = New-Object System.Drawing.Size(90, 25)
$btnAddExclude.Text = "Добавить"
$btnAddExclude.Add_Click({
    $newEx = $txtNewExclude.Text.Trim()
    if (-not [string]::IsNullOrWhiteSpace($newEx)) {
        if (-not $script:ActiveExcludes.Contains($newEx)) {
            [void]$script:ActiveExcludes.Add($newEx)
            Refresh-ExcludesPanel
            $txtNewExclude.Clear()
            Write-Log "Добавлено исключение: $newEx" "INFO"
        }
    }
})
$grpExcludes.Controls.Add($btnAddExclude)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Location = New-Object System.Drawing.Point(370, 104)
$btnRefresh.Size = New-Object System.Drawing.Size(120, 25)
$btnRefresh.Text = "🔄 Обновить"
$btnRefresh.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$btnRefresh.Add_Click({
    Reload-TreeData
})
$grpExcludes.Controls.Add($btnRefresh)

function Refresh-ExcludesPanel {
    $flowExcludes.Controls.Clear()
    foreach ($ex in $script:ActiveExcludes) {
        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = "$ex  ×"
        $btn.AutoSize = $true
        $btn.Height = 26
        $btn.Margin = New-Object System.Windows.Forms.Padding(4)
        $btn.Tag = $ex
        $btn.BackColor = [System.Drawing.Color]::SteelBlue
        $btn.ForeColor = [System.Drawing.Color]::White
        $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $btn.FlatAppearance.BorderSize = 0
        $btn.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $btn.Add_Click({
            $toRemove = $this.Tag
            [void]$script:ActiveExcludes.Remove($toRemove)
            Refresh-ExcludesPanel
            Write-Log "Удалено исключение: $toRemove" "INFO"
        })
        $flowExcludes.Controls.Add($btn)
    }
}

# --- КНОПКИ УПРАВЛЕНИЯ ---
$btnAuto = New-Object System.Windows.Forms.Button
$btnAuto.Location = New-Object System.Drawing.Point(15, 278)
$btnAuto.Size = New-Object System.Drawing.Size(180, 30)
$btnAuto.Text = "🔍 Автоопределение"
$btnAuto.Add_Click({
    Run-AutoDetect
})
$form.Controls.Add($btnAuto)

$btnReset = New-Object System.Windows.Forms.Button
$btnReset.Location = New-Object System.Drawing.Point(205, 278)
$btnReset.Size = New-Object System.Drawing.Size(140, 30)
$btnReset.Text = "↺ Сброс в OO"
$btnReset.Add_Click({
    $lstTree.BeginUpdate()
    for ($i = 0; $i -lt $global:TreeData.Count; $i++) {
        $global:TreeData[$i].State = 0
        Update-ListItem $i
    }
    $lstTree.EndUpdate()
    Update-StatusBar
    Write-Log "Все состояния сброшены в OO" "INFO"
})
$form.Controls.Add($btnReset)

# Статус
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object System.Drawing.Point(360, 284)
$lblStatus.Size = New-Object System.Drawing.Size(565, 25)
$lblStatus.Font = New-Object System.Drawing.Font("Consolas", 9)
$lblStatus.TextAlign = "MiddleRight"
function Update-StatusBar {
    $c = @{0=0;1=0;2=0;3=0}
    $global:TreeData | Where-Object { -not $_.IsDir } | ForEach-Object { $c[$_.State]++ }
    $lblStatus.Text = "OO(merge)=$($c[0]) OX(tree)=$($c[1]) XO(hidden)=$($c[2]) XX(skip)=$($c[3]) | Всего: $($global:TreeData.Count)"
}
$form.Controls.Add($lblStatus)

# --- СПИСОК ДЕРЕВА (MULTI-SELECT) ---
$lstTree = New-Object System.Windows.Forms.ListBox
$lstTree.Location = New-Object System.Drawing.Point(15, 320)
$lstTree.Size = New-Object System.Drawing.Size(910, 400)
$lstTree.Font = New-Object System.Drawing.Font("Consolas", 10)
$lstTree.HorizontalScrollbar = $true
$lstTree.SelectionMode = [System.Windows.Forms.SelectionMode]::MultiExtended
$form.Controls.Add($lstTree)

function Update-ListItem {
    param([int]$idx)
    if ($idx -lt 0 -or $idx -ge $global:TreeData.Count) { return }
    $item = $global:TreeData[$idx]
    $dirMark = if ($item.IsDir) { " [DIR]" } else { "" }
    $lstTree.Items[$idx] = "{0}{1}{2} {3}" -f $item.Prefix, $StateTags[$item.State], $dirMark, $item.Name
}

function Set-ChildrenState {
    param([int]$parentIdx, [int]$newState)
    if ($parentIdx -lt 0 -or $parentIdx -ge $global:TreeData.Count) { return }
    
    $parentPath = $global:TreeData[$parentIdx].FullPath
    $parentLen = $parentPath.Length
    $changed = 0
    
    for ($i = $parentIdx + 1; $i -lt $global:TreeData.Count; $i++) {
        $childPath = $global:TreeData[$i].FullPath
        if ($childPath.Length -gt $parentLen -and 
            $childPath.Substring(0, $parentLen) -eq $parentPath -and
            $childPath[$parentLen] -eq '\') {
            
            $global:TreeData[$i].State = $newState
            Update-ListItem $i
            $changed++
        }
    }
    
    Write-Log "Каскад: $changed элементов -> $($StateTags[$newState])" "DEBUG"
}

function Toggle-ItemState {
    param([int]$idx)
    if ($idx -lt 0 -or $idx -ge $global:TreeData.Count) { return }
    
    $item = $global:TreeData[$idx]
    $item.State = ($item.State + 1) % 4
    Update-ListItem $idx
    
    if ($item.IsDir) { 
        Set-ChildrenState $idx $item.State 
    }
    Update-StatusBar
}

function Toggle-SelectedItems {
    $savedIndices = @($lstTree.SelectedIndices | Sort-Object)
    $savedTop = $lstTree.TopIndex
    
    if ($savedIndices.Count -eq 0) { return }
    
    Write-Log "Multi-toggle: $($savedIndices.Count) элементов" "DEBUG"
    
    $lstTree.BeginUpdate()
    try {
        foreach ($idx in $savedIndices) {
            if ($idx -lt 0 -or $idx -ge $global:TreeData.Count) { continue }
            $item = $global:TreeData[$idx]
            $item.State = ($item.State + 1) % 4
            Update-ListItem $idx
        }
        
        foreach ($idx in $savedIndices) {
            if ($idx -lt 0 -or $idx -ge $global:TreeData.Count) { continue }
            if ($global:TreeData[$idx].IsDir) {
                Set-ChildrenState $idx $global:TreeData[$idx].State
            }
        }
    } finally {
        $lstTree.ClearSelected()
        foreach ($idx in $savedIndices) {
            if ($idx -ge 0 -and $idx -lt $lstTree.Items.Count) {
                $lstTree.SetSelected($idx, $true)
            }
        }
        if ($savedTop -ge 0 -and $savedTop -lt $lstTree.Items.Count) {
            $lstTree.TopIndex = $savedTop
        }
        $lstTree.EndUpdate()
    }
    
    Update-StatusBar
}

function Run-AutoDetect {
    Write-Log "Запуск автоопределения..." "INFO"
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $oo = 0; $ox = 0
    
    $lstTree.BeginUpdate()
    for ($i = 0; $i -lt $global:TreeData.Count; $i++) {
        $item = $global:TreeData[$i]
        if ($item.IsDir) { continue }
        
        $ext = [System.IO.Path]::GetExtension($item.FullPath).ToLower()
        $isText = if ($BlockedExts -contains $ext) { $false } else { Test-IsTextFile $item.FullPath }
        
        if ($isText) { $item.State = 0; $oo++ } else { $item.State = 1; $ox++ }
        Update-ListItem $i
    }
    $lstTree.EndUpdate()
    
    Update-StatusBar
    $timer.Stop()
    Write-Log "Автоопределение: OO=$oo, OX=$ox ($($timer.ElapsedMilliseconds) мс)" "SUCCESS"
    [System.Windows.Forms.MessageBox]::Show("Текстовые (OO): $oo`nНетекстовые (OX): $ox", "Автоопределение завершено", 0, 64)
}

function Reload-TreeData {
    Write-Log "Перезагрузка дерева..." "STEP"
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        $ezaCmd = Get-Command "eza" -ErrorAction SilentlyContinue
        if (-not $ezaCmd) { throw "eza не найдена в PATH" }
        
        $ignoreArg = $script:ActiveExcludes -join "|"
        Write-Log "eza -T --absolute=on -I `"$ignoreArg`"" "DEBUG"
        
        $ezaOutput = eza -T --absolute=on -a --color=never --icons=never -I $ignoreArg $baseDir 2>$null
        Write-Log "eza вернула $($ezaOutput.Count) строк" "INFO"
        
        $global:TreeData = @()
        foreach ($line in $ezaOutput) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            
            if ($line -match "^([│├└─\s]*)(.+)$") {
                $prefix = $matches[1]
                $pathPart = $matches[2].Trim()
                $pathPart = $pathPart -replace '^["'']|["'']$'
                $pathPart = $pathPart -replace '/', '\'
                
                if (-not (Test-Path $pathPart)) { continue }
                
                $name = Split-Path $pathPart -Leaf
                if ([string]::IsNullOrEmpty($name)) { $name = $pathPart }
                
                $isDir = Test-Path $pathPart -PathType Container
                
                $global:TreeData += New-Object PSObject -Property @{
                    Prefix   = $prefix
                    Name     = $name
                    FullPath = $pathPart
                    State    = 0
                    IsDir    = $isDir
                }
            }
        }
        
        $lstTree.Items.Clear()
        foreach ($item in $global:TreeData) {
            $dirMark = if ($item.IsDir) { " [DIR]" } else { "" }
            $display = "{0}{1}{2} {3}" -f $item.Prefix, $StateTags[$item.State], $dirMark, $item.Name
            [void]$lstTree.Items.Add($display)
        }
        
        Update-StatusBar
        $timer.Stop()
        Write-Log "Дерево загружено: $($global:TreeData.Count) элементов ($($timer.ElapsedMilliseconds) мс)" "SUCCESS"
        
    } catch {
        Write-Log "Ошибка загрузки дерева: $_" "ERROR"
        [System.Windows.Forms.MessageBox]::Show("Ошибка: $_", "Ошибка", 0, 16)
    }
}

# --- Обработчики ---
$lstTree.Add_DoubleClick({ Toggle-ItemState $lstTree.SelectedIndex })

$form.Add_KeyDown({
    param($s, $e)
    if ($e.KeyCode -eq 'Space' -and $lstTree.Focused) {
        Toggle-SelectedItems
        $e.Handled = $true
        $e.SuppressKeyPress = $true
    }
})

# --- НАСТРОЙКИ ВЫВОДА ---
$grpSettings = New-Object System.Windows.Forms.GroupBox
$grpSettings.Location = New-Object System.Drawing.Point(15, 730)
$grpSettings.Size = New-Object System.Drawing.Size(910, 150)
$grpSettings.Text = "Настройки результата"
$form.Controls.Add($grpSettings)

$lblOut = New-Object System.Windows.Forms.Label
$lblOut.Location = New-Object System.Drawing.Point(15, 25)
$lblOut.Size = New-Object System.Drawing.Size(80, 20)
$lblOut.Text = "Имя файла:"
$grpSettings.Controls.Add($lblOut)

$txtName = New-Object System.Windows.Forms.TextBox
$txtName.Location = New-Object System.Drawing.Point(100, 22)
$txtName.Size = New-Object System.Drawing.Size(400, 20)
$txtName.Text = "Merged_Project"
$grpSettings.Controls.Add($txtName)

$radioMD = New-Object System.Windows.Forms.RadioButton
$radioMD.Text = "Markdown (.md)"
$radioMD.Location = New-Object System.Drawing.Point(520, 22)
$radioMD.Size = New-Object System.Drawing.Size(130, 20)
$radioMD.Checked = $true
$grpSettings.Controls.Add($radioMD)

$radioTXT = New-Object System.Windows.Forms.RadioButton
$radioTXT.Text = "Текст (.txt)"
$radioTXT.Location = New-Object System.Drawing.Point(660, 22)
$radioTXT.Size = New-Object System.Drawing.Size(100, 20)
$grpSettings.Controls.Add($radioTXT)

$radioPDF = New-Object System.Windows.Forms.RadioButton
$radioPDF.Text = "PDF (Python)"
$radioPDF.Location = New-Object System.Drawing.Point(760, 22)
$radioPDF.Size = New-Object System.Drawing.Size(110, 20)
$grpSettings.Controls.Add($radioPDF)

$chkIncludeTree = New-Object System.Windows.Forms.CheckBox
$chkIncludeTree.Text = "Добавлять дерево папок в выходной файл"
$chkIncludeTree.Location = New-Object System.Drawing.Point(15, 55)
$chkIncludeTree.Size = New-Object System.Drawing.Size(400, 20)
$chkIncludeTree.Checked = $true
$grpSettings.Controls.Add($chkIncludeTree)

$chkGroupDirs = New-Object System.Windows.Forms.CheckBox
$chkGroupDirs.Text = "Группировать папки первыми (--group-directories-first)"
$chkGroupDirs.Location = New-Object System.Drawing.Point(15, 80)
$chkGroupDirs.Size = New-Object System.Drawing.Size(400, 20)
$chkGroupDirs.Checked = $true
$grpSettings.Controls.Add($chkGroupDirs)

# --- Кнопки финальные ---
$btnOK = New-Object System.Windows.Forms.Button
$btnOK.Location = New-Object System.Drawing.Point(730, 890)
$btnOK.Size = New-Object System.Drawing.Size(90, 35)
$btnOK.Text = "▶ Собрать"
$btnOK.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnOK.DialogResult = [System.Windows.Forms.DialogResult]::OK
$form.Controls.Add($btnOK)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Location = New-Object System.Drawing.Point(835, 890)
$btnCancel.Size = New-Object System.Drawing.Size(90, 35)
$btnCancel.Text = "Отмена"
$btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$form.Controls.Add($btnCancel)

# --- Инициализация ---
Refresh-ExcludesPanel
Reload-TreeData

Write-Log "GUI готов, ожидание действий..." "INFO"
Write-Log "" "DIVIDER"

$result = $form.ShowDialog()

if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Log "Отмена пользователем" "WARN"
    exit
}

# ========================= ФАЗА ВЫПОЛНЕНИЯ =========================
Write-Log "Начинаю генерацию..." "STEP"

$outName = $txtName.Text
if ([string]::IsNullOrWhiteSpace($outName)) { $outName = "Merged_Result" }
$isMarkdown = $radioMD.Checked -or $radioPDF.Checked
$ext = if ($radioTXT.Checked) { ".txt" } else { ".md" }
$outputFile = Join-Path $baseDir "$outName$ext"

Write-Log "Выходной файл: $outputFile" "INFO"

# Правила
$Rules = @{}
foreach ($item in $global:TreeData) { $Rules[$item.FullPath] = $item.State }

function Get-RuleState {
    param([string]$path)
    if ($Rules.ContainsKey($path)) { return $Rules[$path] }
    $curr = Split-Path $path -Parent
    $depth = 0
    while ($curr -and $curr.Length -gt $baseDir.Length -and $depth -lt 50) {
        if ($Rules.ContainsKey($curr)) { return $Rules[$curr] }
        $next = Split-Path $curr -Parent
        if ($next -eq $curr) { break }
        $curr = $next
        $depth++
    }
    return 0
}

$outLines = New-Object System.Collections.Generic.List[string]

# --- ДЕРЕВО (С ФИЛЬТРАЦИЕЙ STATE 2 И 3) ---
if ($chkIncludeTree.Checked) {
    Write-Log "Генерация дерева (с учётом State 2/3)..." "STEP"
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    
    $excludedTreePaths = $global:TreeData | Where-Object { $_.State -eq 2 -or $_.State -eq 3 } | Select-Object -ExpandProperty FullPath
    Write-Log "Исключено папок/веток из дерева: $($excludedTreePaths.Count)" "INFO"
    
    $treeLines = @()
    $skippedLines = 0
    
    foreach ($item in $global:TreeData) {
        $isExcluded = $false
        foreach ($exPath in $excludedTreePaths) {
            if ($item.FullPath -eq $exPath -or $item.FullPath.StartsWith($exPath + "\")) {
                $isExcluded = $true
                $skippedLines++
                break
            }
        }
        
        if ($isExcluded) { 
            Write-Log "Скрыто из дерева: $($item.FullPath)" "DEBUG"
            continue 
        }
        
        $line = $item.Prefix + $item.Name
        $treeLines += $line
    }
    
    $timer.Stop()
    Write-Log "Строк дерева после фильтрации: $($treeLines.Count) (пропущено: $skippedLines)" "SUCCESS"
    
    if ($isMarkdown) {
        $outLines.Add("# Project Dump: $outName")
        $outLines.Add("> Generated: $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')")
        $outLines.Add("")
        $outLines.Add("### Directory Tree")
        $outLines.Add("``````text")
        $treeLines | ForEach-Object { $outLines.Add($_) }
        $outLines.Add("``````")
        $outLines.Add("")
        $outLines.Add("---")
        $outLines.Add("")
    } else {
        $outLines.Add("=" * 80)
        $outLines.Add("PROJECT DUMP: $outName")
        $outLines.Add("Generated: $(Get-Date)")
        $outLines.Add("=" * 80)
        $outLines.Add("")
        $outLines.Add("DIRECTORY TREE:")
        $outLines.Add("")
        $treeLines | ForEach-Object { $outLines.Add($_) }
        $outLines.Add("")
        $outLines.Add("=" * 80)
        $outLines.Add("")
    }
}

# --- СБОР ФАЙЛОВ ---
Write-Log "Сбор файлов..." "STEP"
$timer = [System.Diagnostics.Stopwatch]::StartNew()

$allFiles = Get-ChildItem -Path $baseDir -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { 
    -not (Test-IsExcludedPath -FilePath $_.FullName -ExcludeNames $script:ActiveExcludes -BaseDir $baseDir)
}

Write-Log "Найдено файлов (после глобальной фильтрации): $($allFiles.Count)" "INFO"

$merged = 0
$skippedState = 0
$skippedBinary = 0
$failed = @()
$totalBytes = 0
$fileNum = 0

foreach ($file in $allFiles) {
    $fileNum++
    if ($fileNum % 50 -eq 0) {
        Write-Progress -Activity "Сбор файлов" -Status "$fileNum / $($allFiles.Count)" -PercentComplete (($fileNum/$allFiles.Count)*100)
    }
    
    if ($file.FullName -eq $outputFile) { continue }
    
    $state = Get-RuleState $file.FullName
    if ($state -eq 1 -or $state -eq 3) {
        $skippedState++
        continue
    }
    
    if (-not (Test-IsTextFile $file.FullName)) {
        $skippedBinary++
        continue
    }
    
    try {
        try {
            $content = Get-Content $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop
        } catch {
            $content = Get-Content $file.FullName -Raw -Encoding Default -ErrorAction Stop
        }
        
        $relPath = $file.FullName.Substring($baseDir.Length).TrimStart('\')
        $totalBytes += $file.Length
        
        if ($isMarkdown) {
            $outLines.Add("### File: $relPath")
            
            $ext = $file.Extension.TrimStart('.').ToLower()
            $langMap = @{
                'h'='cpp'; 'hpp'='cpp'; 'c'='c'; 'cpp'='cpp'; 'cs'='csharp'
                'js'='javascript'; 'jsx'='javascript'; 'ts'='typescript'; 'tsx'='typescript'; 'mjs'='javascript'
                'py'='python'; 'rb'='ruby'; 'rs'='rust'; 'go'='go'; 'java'='java'
                'php'='php'; 'swift'='swift'; 'kt'='kotlin'
                'html'='html'; 'css'='css'; 'scss'='scss'; 'sass'='sass'; 'less'='less'
                'json'='json'; 'xml'='xml'; 'yaml'='yaml'; 'yml'='yaml'
                'sql'='sql'; 'sh'='bash'; 'bash'='bash'; 'ps1'='powershell'; 'psm1'='powershell'
                'bat'='batch'; 'cmd'='batch'
                'md'='markdown'; 'dockerfile'='dockerfile'
            }
            $lang = if ($langMap.ContainsKey($ext)) { $langMap[$ext] } else { "" }
            
            $outLines.Add("``````$lang")
            $outLines.Add($content)
            $outLines.Add("``````")
            $outLines.Add("")
            $outLines.Add("---")
            $outLines.Add("")
        } else {
            $outLines.Add("=" * 80)
            $outLines.Add("FILE: $relPath")
            $outLines.Add("=" * 80)
            $outLines.Add($content)
            $outLines.Add("")
        }
        $merged++
        
    } catch {
        $failed += $file.FullName
        Write-Log "Ошибка чтения $($file.Name): $_" "WARN"
    }
}

Write-Progress -Activity "Сбор файлов" -Completed
$timer.Stop()

Write-Log "Сбор завершён ($($timer.ElapsedMilliseconds) мс):" "SUCCESS"
Write-Log "  Добавлено: $merged" "INFO"
Write-Log "  Пропущено (State 1/3): $skippedState" "INFO"
Write-Log "  Пропущено (Binary): $skippedBinary" "INFO"
Write-Log "  Ошибок чтения: $($failed.Count)" "INFO"

if ($failed.Count -gt 0) {
    if ($isMarkdown) {
        $outLines.Add("### Errors during processing")
        $failed | ForEach-Object {
            $rel = $_.Substring($baseDir.Length).TrimStart('\')
            $outLines.Add("- ``$rel``")
        }
    } else {
        $outLines.Add("ERRORS:")
        $failed | ForEach-Object { $outLines.Add($_) }
    }
}

# --- СОХРАНЕНИЕ ---
Write-Log "Сохранение..." "STEP"
$finalText = [string]::Join([Environment]::NewLine, $outLines)
[System.IO.File]::WriteAllText($outputFile, $finalText, [System.Text.Encoding]::UTF8)
$fileSize = (Get-Item $outputFile).Length
Write-Log "Сохранено: $outputFile ($([math]::Round($fileSize/1KB, 1)) KB)" "SUCCESS"

# --- PDF ---
if ($radioPDF.Checked) {
    if (Test-Path $PythonScriptPath) {
        Write-Log "Конвертация в PDF..." "STEP"
        $proc = Start-Process "py.exe" -ArgumentList "-3.11 `"$PythonScriptPath`" `"$outputFile`"" -Wait -PassThru
        if ($proc.ExitCode -eq 0 -and (Test-Path ([IO.Path]::ChangeExtension($outputFile, ".pdf")))) {
            Remove-Item $outputFile -Force
            Write-Log "PDF создан успешно" "SUCCESS"
        } else {
            Write-Log "Ошибка создания PDF" "ERROR"
        }
    } else {
        Write-Log "Python-скрипт не найден: $PythonScriptPath" "ERROR"
    }
}

# --- ИТОГ ---
$totalTime = ((Get-Date) - $global:ScriptStartTime).TotalSeconds
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host ("║  ГОТОВО  |  Файлов: $merged  |  Размер: $([math]::Round($fileSize/1KB,1)) KB  |  Время: {0:F1}s" -f $totalTime).PadRight(63) + "║" -ForegroundColor Green
Write-Host ("║  $([IO.Path]::GetFileName($outputFile))").PadRight(63) + "║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""