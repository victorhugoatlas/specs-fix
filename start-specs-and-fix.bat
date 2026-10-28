@echo off
setlocal
title SPECS AND FIX BY VH
set "SF_SELF=%~f0"
set "SF_ARGS=%*"

net session >nul 2>&1
if %errorLevel% neq 0 goto :Elevar
goto :Executar

:Elevar
echo [!] SOLICITANDO PERMISSOES DE ADMINISTRADOR...
if "%~1"=="" (
    powershell -NoProfile -Command "Start-Process -FilePath $env:SF_SELF -Verb RunAs"
) else (
    powershell -NoProfile -Command "Start-Process -FilePath $env:SF_SELF -ArgumentList $env:SF_ARGS -Verb RunAs"
)
exit /b

:Executar
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText($env:SF_SELF); $m='#PS'+'START'; $c=$t.Substring($t.LastIndexOf($m)+$m.Length); & ([ScriptBlock]::Create($c))"
echo.
pause
exit /b

#PSSTART
# ==========================================================================
#  SPECS AND FIX - by Victor Hugo
#  Arquivo unico: a parte abaixo e o script PowerShell embutido no .bat.
#  Uso:  start-specs-and-fix.bat                (menu interativo)
#        start-specs-and-fix.bat limpeza        (executa a limpeza e sai)
#        start-specs-and-fix.bat reparo         (executa o reparo e sai)
#        start-specs-and-fix.bat tudo           (limpeza + reparo e sai)
#        adicione /y para pular as confirmacoes (ex.: tudo /y)
# ==========================================================================

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
$Host.UI.RawUI.WindowTitle = 'SPECS AND FIX BY VH'

# ---------------------------- argumentos ----------------------------------
$ArgList = @()
if ($env:SF_ARGS) { $ArgList = @($env:SF_ARGS -split '\s+' | Where-Object { $_ }) }
$Auto = $ArgList -contains '/y'
$Modo = "$($ArgList | Where-Object { $_ -ne '/y' } | Select-Object -First 1)".ToLower()

# ---------------------------- verificacao de admin ------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host '[X] Este script precisa ser executado como Administrador.' -ForegroundColor Red
    exit 1
}

# ---------------------------- local do relatorio --------------------------
$ReportDir = Split-Path -Parent $env:SF_SELF
try {
    $probe = Join-Path $ReportDir '.sf_probe'
    New-Item -Path $probe -ItemType File -Force -ErrorAction Stop | Out-Null
    Remove-Item $probe -Force -ErrorAction SilentlyContinue
} catch {
    $ReportDir = [Environment]::GetFolderPath('Desktop')
    if (-not (Test-Path $ReportDir)) { $ReportDir = $env:TEMP }
}
$ReportName = "SPECS_AND_FIX_$($env:COMPUTERNAME).txt"
$ReportFile = Join-Path $ReportDir $ReportName

# ---------------------------- funcoes auxiliares --------------------------
function Write-Log {
    param([string]$Msg)
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg
    try { Add-Content -Path $ReportFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}

function Wait-Enter {
    Read-Host 'Pressione ENTER para continuar' | Out-Null
}

function Confirm-Action {
    param([string]$Msg, [bool]$Default = $false)
    if ($Auto) { return $Default }
    $suffix = if ($Default) { '[S/n]' } else { '[s/N]' }
    while ($true) {
        $r = "$(Read-Host "$Msg $suffix")".Trim().ToLower()
        if ($r -eq '') { return $Default }
        if (@('s', 'sim', 'y', 'yes') -contains $r) { return $true }
        if (@('n', 'nao', 'no') -contains $r) { return $false }
    }
}

function Format-Row {
    param([string]$Label, $Value)
    $out = @()
    $first = $true
    foreach ($v in @($Value)) {
        $l = if ($first) { $Label } else { '' }
        $out += ('{0,-22} | {1}' -f $l, $v)
        $first = $false
    }
    return $out
}

function Get-FreeBytes {
    return ([IO.DriveInfo]($env:SystemDrive + '\')).AvailableFreeSpace
}

function Clear-PathContent {
    param([string]$Path)
    Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

function Test-PendingReboot {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )
    foreach ($k in $keys) { if (Test-Path $k) { return $true } }
    $v = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    return [bool]$v
}

# ---------------------------- diagnostico ---------------------------------
function Get-SpecsReport {
    $sep = '=' * 62
    $nd  = 'N/D'

    $os   = Get-CimInstance Win32_OperatingSystem
    $cs   = Get-CimInstance Win32_ComputerSystem
    $cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
    $bb   = Get-CimInstance Win32_BaseBoard
    $bios = Get-CimInstance Win32_BIOS

    # Chipset (nem sempre exposto pelo Windows)
    $chipset = Get-CimInstance Win32_PnPEntity -Filter "Name LIKE '%Chipset%' OR Name LIKE '%LPC Controller%'" |
        Select-Object -First 1
    $chipsetName = if ($chipset -and $chipset.Name) { $chipset.Name } else { $nd }

    # Uptime
    $up = (Get-Date) - $os.LastBootUpTime
    $uptime = '{0}d {1}h {2}min' -f $up.Days, $up.Hours, $up.Minutes

    # Ativacao
    $lic = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND ApplicationId='55c92734-d682-4d71-983e-d6ec3f16059f'" |
        Select-Object -First 1
    $ativacao = if ($lic -and $lic.LicenseStatus -eq 1) { 'ATIVADO' } elseif ($lic) { 'NAO ATIVADO' } else { $nd }

    # RAM
    $mods = @(Get-CimInstance Win32_PhysicalMemory)
    if ($mods.Count -gt 0) {
        $ramTotal = [math]::Round((($mods | Measure-Object Capacity -Sum).Sum) / 1GB)
        $typeMap = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 34 = 'DDR5'; 27 = 'LPDDR'; 28 = 'LPDDR2'; 29 = 'LPDDR3'; 30 = 'LPDDR4'; 35 = 'LPDDR5' }
        $groups = $mods | Group-Object {
            $spd = if ($_.ConfiguredClockSpeed) { $_.ConfiguredClockSpeed } else { $_.Speed }
            '{0}|{1}|{2}' -f $_.Capacity, $spd, $_.SMBIOSMemoryType
        }
        $ramDet = ($groups | ForEach-Object {
            $p = $_.Name -split '\|'
            $t = $typeMap[[int]$p[2]]
            if (-not $t) { $t = 'RAM' }
            '{0} x {1}GB {2} {3}MHz' -f $_.Count, [math]::Round([double]$p[0] / 1GB), $t, $p[1]
        }) -join ' + '
        $slotsTotal = (Get-CimInstance Win32_PhysicalMemoryArray | Measure-Object MemoryDevices -Sum).Sum
        $ramSlots = '{0} de {1} slots ocupados' -f $mods.Count, $slotsTotal
    } else {
        $ramTotal = [math]::Round($cs.TotalPhysicalMemory / 1GB)
        $ramDet = $nd
        $ramSlots = $nd
    }

    # Discos
    $sysDisk = $null
    try {
        $letter = $env:SystemDrive.TrimEnd(':')
        $sysDisk = (Get-Partition -DriveLetter $letter -ErrorAction Stop | Get-Disk -ErrorAction Stop).Number
    } catch { }
    $diskLines = @()
    foreach ($pd in @(Get-PhysicalDisk | Sort-Object { [int]$_.DeviceID })) {
        $size = [math]::Round($pd.Size / 1GB)
        $wear = $null
        try { $wear = ($pd | Get-StorageReliabilityCounter -ErrorAction Stop).Wear } catch { }
        $saude = "Status: $($pd.HealthStatus)"
        if ($null -ne $wear) { $saude += " | Vida util restante: $(100 - $wear)%" }
        $tag = if ($null -ne $sysDisk -and "$($pd.DeviceID)" -eq "$sysDisk") { ' [SISTEMA]' } else { '' }
        $diskLines += '{0} {1} {2} ({3} GB){4} - {5}' -f $pd.BusType, $pd.MediaType, $pd.FriendlyName, $size, $tag, $saude
    }
    if ($diskLines.Count -eq 0) { $diskLines = @($nd) }

    # Volumes
    $volLines = @(Get-Volume -ErrorAction SilentlyContinue |
        Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter } |
        ForEach-Object { '{0}: {1} GB livres de {2} GB' -f $_.DriveLetter, [math]::Round($_.SizeRemaining / 1GB, 1), [math]::Round($_.Size / 1GB, 1) })
    if ($volLines.Count -eq 0) { $volLines = @($nd) }

    # GPU (ignora adaptadores virtuais)
    $allGpu = @(Get-CimInstance Win32_VideoController)
    $realGpu = @($allGpu | Where-Object { $_.Name -notmatch 'Basic|Remote|Virtual|Hyper-V|Mirror|Meta|Parsec|Citrix' })
    if ($realGpu.Count -eq 0) { $realGpu = $allGpu }
    $gpuNames = (($realGpu | ForEach-Object { $_.Name }) -join ' / ')
    if (-not $gpuNames) { $gpuNames = $nd }

    # Tipo (notebook / desktop / virtual)
    $ch = @((Get-CimInstance Win32_SystemEnclosure).ChassisTypes)
    $portable = @(8, 9, 10, 14, 30, 31, 32)
    $hasBat = [bool](Get-CimInstance Win32_Battery)
    $isPortable = $false
    foreach ($c in $ch) { if ($portable -contains [int]$c) { $isPortable = $true } }
    $unknownChassis = ($ch -contains 1) -or ($ch -contains 2)
    if ("$($cs.Model) $($cs.Manufacturer)" -match 'Virtual|VMware|VirtualBox|KVM|QEMU|Hyper-V') {
        $tipo = 'MAQUINA VIRTUAL'
    } elseif ($isPortable -or ($hasBat -and $unknownChassis)) {
        $tipo = 'NOTEBOOK'
    } else {
        $tipo = 'DESKTOP'
    }

    $lines = @()
    $lines += $sep
    $lines += Format-Row 'HOSTNAME' $env:COMPUTERNAME
    $lines += Format-Row 'FABRICANTE / MODELO' ('{0} / {1}' -f $cs.Manufacturer, $cs.Model)
    $lines += Format-Row 'SISTEMA OPERACIONAL' ('{0} (build {1}) - {2}' -f $os.Caption, $os.BuildNumber, $ativacao)
    $lines += Format-Row 'UPTIME' $uptime
    $lines += Format-Row 'PROCESSADOR' ('{0} ({1} nucleos / {2} threads)' -f $cpu.Name.Trim(), $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors)
    $lines += Format-Row 'PLACA-MAE' ('{0} {1}' -f $bb.Manufacturer, $bb.Product)
    $lines += Format-Row 'CHIPSET' $chipsetName
    $lines += Format-Row 'BIOS' ('{0} ({1})' -f $bios.SMBIOSBIOSVersion, $bios.Manufacturer)
    $lines += Format-Row 'RAM TOTAL' ('{0} GB - {1}' -f $ramTotal, $ramSlots)
    $lines += Format-Row 'RAM DETALHES' $ramDet
    $lines += Format-Row 'DISCOS E SAUDE' $diskLines
    $lines += Format-Row 'ESPACO EM DISCO' $volLines
    $lines += Format-Row 'PLACA DE VIDEO' $gpuNames
    $lines += Format-Row 'TIPO' $tipo
    $lines += $sep
    return $lines
}

# ---------------------------- modulo 1: limpeza ---------------------------
function Invoke-Limpeza {
    Write-Host "`n[>>>] MODULO 1: LIMPEZA DE TEMPORARIOS" -ForegroundColor Yellow
    Write-Log 'LIMPEZA: iniciada'

    $running = @(Get-Process -Name chrome, msedge, firefox -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        Write-Host '[!] Ha navegadores abertos; arquivos em uso nao podem ser apagados.' -ForegroundColor DarkYellow
        if (Confirm-Action 'Fechar os navegadores agora para limpar o cache por completo?' $false) {
            $running | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
    }
    $prefetch = Confirm-Action 'Limpar tambem o Prefetch? (pode deixar o proximo boot um pouco mais lento)' $false

    $targets = @("$env:SystemRoot\Temp\*", "$env:TEMP\*")
    if ($prefetch) { $targets += "$env:SystemRoot\Prefetch\*" }

    # Chrome e Edge: todos os perfis
    $roots = @("$env:LOCALAPPDATA\Google\Chrome\User Data", "$env:LOCALAPPDATA\Microsoft\Edge\User Data")
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        $profiles = @(Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })
        foreach ($pf in $profiles) {
            foreach ($sub in @('Cache', 'Code Cache', 'GPUCache')) {
                $targets += "$($pf.FullName)\$sub\*"
            }
        }
    }

    # Firefox (o cache fica em LocalAppData)
    $targets += "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2\*"

    # Relatorios de erro do Windows
    $targets += "$env:ProgramData\Microsoft\Windows\WER\ReportQueue\*"
    $targets += "$env:ProgramData\Microsoft\Windows\WER\ReportArchive\*"

    # Cache de download do Windows Update
    $wu = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    $wuRunning = ($null -ne $wu) -and ($wu.Status -eq 'Running')
    if ($wuRunning) { Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue }
    $targets += "$env:SystemRoot\SoftwareDistribution\Download\*"

    $before = Get-FreeBytes
    $i = 0
    foreach ($t in ($targets | Select-Object -Unique)) {
        $i++
        Write-Host ("[-] ({0}) {1}" -f $i, $t) -ForegroundColor DarkGray
        Clear-PathContent -Path $t
    }
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue

    if ($wuRunning) { Start-Service -Name wuauserv -ErrorAction SilentlyContinue }

    $freed = (Get-FreeBytes) - $before
    if ($freed -lt 0) { $freed = 0 }
    $msg = 'Limpeza concluida. Espaco liberado: {0:N2} GB' -f ($freed / 1GB)
    Write-Host "[+] $msg" -ForegroundColor Green
    Write-Log "LIMPEZA: $msg"
}

# ---------------------------- modulo 2: reparo ----------------------------
function Invoke-Reparo {
    Write-Host "`n[>>>] MODULO 2: REPARO DO SISTEMA" -ForegroundColor Yellow
    Write-Log 'REPARO: iniciado'
    $drive = $env:SystemDrive

    Write-Host '[*] Criando ponto de restauracao...' -ForegroundColor Cyan
    try {
        Checkpoint-Computer -Description 'Specs and Fix' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        Write-Host '[+] Ponto de restauracao criado.' -ForegroundColor Green
        Write-Log 'REPARO: ponto de restauracao criado'
    } catch {
        Write-Host "[!] Nao foi possivel criar o ponto de restauracao: $($_.Exception.Message)" -ForegroundColor DarkYellow
        Write-Log 'REPARO: ponto de restauracao NAO criado'
    }

    Write-Host "`n[1/3] DISM /Online /Cleanup-Image /RestoreHealth" -ForegroundColor Cyan
    & DISM.exe /Online /Cleanup-Image /RestoreHealth
    $dism = $LASTEXITCODE
    if ($dism -eq 0) {
        Write-Host '[+] DISM concluido sem erros.' -ForegroundColor Green
        Write-Log 'REPARO: DISM OK'
    } else {
        Write-Host "[!] DISM terminou com codigo $dism. Veja C:\Windows\Logs\DISM\dism.log" -ForegroundColor Red
        Write-Log "REPARO: DISM FALHOU (codigo $dism)"
    }

    Write-Host "`n[2/3] SFC /SCANNOW" -ForegroundColor Cyan
    & sfc.exe /scannow
    $sfc = $LASTEXITCODE
    if ($sfc -eq 0) {
        Write-Host '[+] SFC concluido sem pendencias.' -ForegroundColor Green
        Write-Log 'REPARO: SFC OK'
    } else {
        Write-Host "[!] SFC terminou com codigo $sfc. Veja C:\Windows\Logs\CBS\CBS.log" -ForegroundColor Red
        Write-Log "REPARO: SFC com pendencias (codigo $sfc)"
    }

    Write-Host "`n[3/3] CHKDSK $drive /scan (verificacao online)" -ForegroundColor Cyan
    & chkdsk.exe $drive /scan
    $chk = $LASTEXITCODE
    if ($chk -eq 0) {
        Write-Host '[+] CHKDSK nao encontrou erros.' -ForegroundColor Green
        Write-Log 'REPARO: CHKDSK /scan OK'
    } elseif ($chk -le 2) {
        Write-Host "[+] CHKDSK encontrou e/ou corrigiu itens (codigo $chk)." -ForegroundColor Yellow
        Write-Log "REPARO: CHKDSK /scan corrigiu itens (codigo $chk)"
    } else {
        Write-Host "[!] CHKDSK nao conseguiu concluir/corrigir (codigo $chk)." -ForegroundColor Red
        Write-Log "REPARO: CHKDSK /scan com problemas (codigo $chk)"
    }

    if (Confirm-Action "Agendar verificacao profunda ($drive /f /r) para o proximo reinicio? (demorada)" $false) {
        # Responde S (pt-BR) e Y (outros idiomas) ao pedido de agendamento
        @('S', 'Y') | & chkdsk.exe $drive /f /r
        Write-Host '[!] A verificacao profunda sera feita no proximo reinicio do computador.' -ForegroundColor Yellow
        Write-Log "REPARO: CHKDSK $drive /f /r agendado para o proximo boot"
    }

    Write-Host '[+] Rotinas de reparo finalizadas!' -ForegroundColor Green
    Write-Log 'REPARO: finalizado'
}

function Invoke-Modulo {
    param([string]$Nome)
    switch ($Nome) {
        'limpeza' {
            if (Confirm-Action 'A limpeza apaga arquivos temporarios de forma definitiva. Continuar?' $true) { Invoke-Limpeza }
        }
        'reparo' {
            if (Confirm-Action 'O reparo pode levar varios minutos. Salve seus arquivos abertos. Continuar?' $true) { Invoke-Reparo }
        }
        'tudo' {
            if (Confirm-Action 'Executar limpeza + reparo? Salve seus arquivos abertos antes de continuar.' $true) {
                Invoke-Limpeza
                Invoke-Reparo
            }
        }
    }
}

# ---------------------------- relatorio inicial ---------------------------
Write-Host 'Coletando informacoes do hardware, aguarde...' -ForegroundColor DarkGray
$reportLines = Get-SpecsReport
$report = $reportLines -join "`r`n"

$header = @(
    'SPECS AND FIX - RELATORIO',
    ('Gerado em: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
    ''
) -join "`r`n"
try {
    ($header + "`r`n" + $report + "`r`n`r`nREGISTRO DE MANUTENCAO`r`n----------------------") |
        Out-File -FilePath $ReportFile -Encoding UTF8 -ErrorAction Stop
} catch {
    Write-Host "[!] Nao foi possivel gravar o relatorio em: $ReportFile" -ForegroundColor DarkYellow
}

# ---------------------------- modo nao interativo -------------------------
if (@('limpeza', 'reparo', 'tudo') -contains $Modo) {
    Write-Host $report -ForegroundColor Cyan
    Invoke-Modulo $Modo
    Write-Host "`nRelatorio salvo em: $ReportFile" -ForegroundColor Magenta
    exit 0
}

# ---------------------------- menu interativo -----------------------------
$pending = Test-PendingReboot
do {
    Clear-Host
    Write-Host $report -ForegroundColor Cyan
    if ($pending) {
        Write-Host '[!] Ha uma reinicializacao pendente no Windows.' -ForegroundColor DarkYellow
    }
    Write-Host '              MENU DE MANUTENCAO - BY VICTOR HUGO' -ForegroundColor Yellow
    Write-Host ('=' * 62)
    Write-Host '[1] Limpeza de Temporarios'
    Write-Host '[2] Reparo do Sistema (DISM + SFC + CHKDSK)'
    Write-Host '[3] Executar Tudo (Limpeza + Reparo)'
    Write-Host '[0] Sair'
    Write-Host ('=' * 62)

    $opt = "$(Read-Host 'Digite a opcao')".Trim()

    switch ($opt) {
        '1' { Invoke-Modulo 'limpeza'; Wait-Enter }
        '2' { Invoke-Modulo 'reparo';  Wait-Enter }
        '3' { Invoke-Modulo 'tudo';    Wait-Enter }
        '0' {
            Write-Host "Saindo... Relatorio salvo em: $ReportFile" -ForegroundColor Magenta
            exit 0
        }
        default {
            Write-Host 'Opcao invalida!' -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
} while ($true)
