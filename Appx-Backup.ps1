<#
.SYNOPSIS
    Backup any Windows Store (UWP/AppX) application to a signed .appx package with a self-signed certificate.

.DESCRIPTION
    This script creates an offline installation package (.appx) for a given Windows App (from %ProgramFiles%\WindowsApps).
    It uses MakeAppx.exe to pack the files, generates a self-signed certificate using .NET (no dependency on Cert: drive),
    and signs the package with SignTool.exe.

    Run with -GUI switch to open a graphical interface for easier path selection.

.PARAMETER WSAppPath
    Full path to the application folder inside C:\Program Files\WindowsApps.

.PARAMETER WSAppOutputPath
    Destination folder where the .appx and .cer files will be saved.

.PARAMETER WSTools
    Path to the Windows SDK tools folder (containing MakeAppx.exe, SignTool.exe, etc.) – x64 version.

.PARAMETER GUI
    If specified, launches the graphical user interface instead of the console mode.

.EXAMPLE
    .\Appx-Backup.ps1 -WSAppPath "C:\Program Files\WindowsApps\Microsoft.RemoteDesktop_10.2.4012.0_x64__8wekyb3d8bbwe" -WSAppOutputPath "C:\Backup" -WSTools "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64"

.EXAMPLE
    .\Appx-Backup.ps1 -GUI
#>

[CmdletBinding(DefaultParameterSetName = 'Console')]
param (
    [Parameter(ParameterSetName = 'Console', Mandatory = $false)]
    [string] $WSAppPath,

    [Parameter(ParameterSetName = 'Console', Mandatory = $false)]
    [string] $WSAppOutputPath,

    [Parameter(ParameterSetName = 'Console', Mandatory = $false)]
    [string] $WSTools,

    [Parameter(ParameterSetName = 'GUI', Mandatory = $true)]
    [switch] $GUI
)

# =============================================================================
# FUNCTIONS
# =============================================================================

function Run-Process {
    Param ($p, $a)
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $p
    $pinfo.Arguments = $a
    $pinfo.RedirectStandardError = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null
    $output = $p.StandardOutput.ReadToEnd()
    $output += $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return $output
}

function Find-WindowsSDK {
    $basePaths = @(
        "C:\Program Files (x86)\Windows Kits\10\bin",
        "C:\Program Files\Windows Kits\10\bin"
    )
    $versions = @()
    foreach ($base in $basePaths) {
        if (Test-Path $base) {
            $dirs = Get-ChildItem -Path $base -Directory | Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' }
            foreach ($d in $dirs) {
                $x64 = Join-Path $d.FullName "x64"
                if (Test-Path $x64) {
                    $versions += [PSCustomObject]@{ Path = $x64; Version = [version]$d.Name }
                }
            }
        }
    }
    if ($versions.Count -eq 0) { return $null }
    $versions = $versions | Sort-Object -Property Version -Descending
    return $versions[0].Path
}

function Load-Settings {
    $settingsPath = Join-Path $env:APPDATA "AppxBackup"
    $settingsFile = Join-Path $settingsPath "settings.xml"
    $default = @{ AppPath = "C:\Program Files\WindowsApps"; OutPath = ""; ToolsPath = "" }
    if (Test-Path $settingsFile) {
        try {
            [xml]$xml = Get-Content $settingsFile
            $app = $xml.Settings.AppPath
            $out = $xml.Settings.OutPath
            $tools = $xml.Settings.ToolsPath
            if ($app) { $default.AppPath = $app }
            if ($out) { $default.OutPath = $out }
            if ($tools) { $default.ToolsPath = $tools }
        } catch { }
    }
    return $default
}

function Save-Settings($app, $out, $tools) {
    $settingsPath = Join-Path $env:APPDATA "AppxBackup"
    if (-not (Test-Path $settingsPath)) { New-Item -ItemType Directory -Path $settingsPath -Force | Out-Null }
    $settingsFile = Join-Path $settingsPath "settings.xml"
    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<Settings>
  <AppPath>$app</AppPath>
  <OutPath>$out</OutPath>
  <ToolsPath>$tools</ToolsPath>
</Settings>
"@
    $xml | Out-File -FilePath $settingsFile -Encoding UTF8 -Force
}

function New-SelfSignedCertificateDotNet {
    param(
        [string]$Subject,
        [int]$KeyLength = 2048,
        [datetime]$NotBefore = (Get-Date).AddDays(-1),
        [datetime]$NotAfter = (Get-Date).AddYears(10)
    )
    Add-Type -AssemblyName System.Security
    $dn = New-Object System.Security.Cryptography.X509Certificates.X500DistinguishedName($Subject)
    $algo = [System.Security.Cryptography.RSA]::Create($KeyLength)
    $req = New-Object System.Security.Cryptography.X509Certificates.CertificateRequest($dn, $algo, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $req.CertificateExtensions.Add(
        (New-Object System.Security.Cryptography.X509Certificates.X509KeyUsageExtension(
            [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature,
            $true))
    )
    $oidCollection = New-Object System.Security.Cryptography.OidCollection
    $oidCollection.Add((New-Object System.Security.Cryptography.Oid("1.3.6.1.5.5.7.3.3"))) | Out-Null
    $req.CertificateExtensions.Add(
        (New-Object System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension(
            $oidCollection,
            $true))
    )
    $cert = $req.CreateSelfSigned($NotBefore, $NotAfter)
    return $cert
}

function Export-CertificateDotNet {
    param([System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert, [string]$FilePath)
    $bytes = $Cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
    [System.IO.File]::WriteAllBytes($FilePath, $bytes)
}

function Export-PfxDotNet {
    param([System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert, [string]$FilePath, [string]$Password)
    $bytes = $Cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $Password)
    [System.IO.File]::WriteAllBytes($FilePath, $bytes)
}

# =============================================================================
# CONSOLE MODE
# =============================================================================
if (-not $GUI) {
    $ErrorActionPreference = "Stop"
    if (-not $WSAppPath) { $WSAppPath = Read-Host "WSAppPath" }
    if (-not $WSAppOutputPath) { $WSAppOutputPath = Read-Host "WSAppOutputPath" }
    if (-not $WSTools) { $WSTools = Read-Host "WSTools" }

    if (-not (Test-Path "$WSTools\MakeAppx.exe")) {
        Write-Output "ERROR: MakeAppx.exe not found in WSTools path."
        Exit 1
    }
    if (-not (Test-Path "$WSTools\SignTool.exe")) {
        Write-Output "ERROR: SignTool.exe not found in WSTools path."
        Exit 1
    }

    $WSAppXmlFile = "AppxManifest.xml"
    Write-Output "Reading ""$WSAppPath\$WSAppXmlFile"""
    if (-not (Test-Path "$WSAppPath\$WSAppXmlFile")) {
        Write-Output "ERROR: Windows Store manifest not found."
        Exit 1
    }
    [xml]$manifest = Get-Content "$WSAppPath\$WSAppXmlFile"
    $WSAppName = $manifest.Package.Identity.Name
    $WSAppPublisher = $manifest.Package.Identity.Publisher
    Write-Output "  App Name : $WSAppName"
    Write-Output "  Publisher: $WSAppPublisher"

    $WSAppFileName = (Get-Item $WSAppPath).BaseName

    Write-Output "Creating ""$WSAppOutputPath\$WSAppFileName.appx""."
    if (Test-Path "$WSAppOutputPath\$WSAppFileName.appx") { Remove-Item "$WSAppOutputPath\$WSAppFileName.appx" }
    $proc = "$WSTools\MakeAppx.exe"
    $args = "pack /d ""$WSAppPath"" /p ""$WSAppOutputPath\$WSAppFileName.appx"" /l"
    $output = Run-Process $proc $args
    if ($output -inotlike "*succeeded*") {
        Write-Output "  ERROR: Appx creation failed!"
        Write-Output "  proc = $proc"
        Write-Output "  args = $args"
        Write-Output ("  " + $output)
        Exit 1
    }
    Write-Output "  Done."

    Write-Output "Creating self-signed certificate via .NET."
    if (Test-Path "$WSAppOutputPath\$WSAppFileName.pvk") { Remove-Item "$WSAppOutputPath\$WSAppFileName.pvk" -Force }
    if (Test-Path "$WSAppOutputPath\$WSAppFileName.cer") { Remove-Item "$WSAppOutputPath\$WSAppFileName.cer" -Force }
    if (Test-Path "$WSAppOutputPath\$WSAppFileName.pfx") { Remove-Item "$WSAppOutputPath\$WSAppFileName.pfx" -Force }

    try {
        $cert = New-SelfSignedCertificateDotNet -Subject "$WSAppPublisher" -KeyLength 2048
    } catch {
        Write-Output "  ERROR: Certificate creation failed."
        Write-Output $_.Exception.Message
        Exit 1
    }
    if (-not $cert) {
        Write-Output "  ERROR: Certificate creation returned null."
        Exit 1
    }

    Export-CertificateDotNet -Cert $cert -FilePath "$WSAppOutputPath\$WSAppFileName.cer"
    Export-PfxDotNet -Cert $cert -FilePath "$WSAppOutputPath\$WSAppFileName.pfx" -Password "password"
    Write-Output "  Done."

    Write-Output "Signing the package."
    $proc = "$WSTools\SignTool.exe"
    $args = "sign -fd SHA256 -a -f ""$WSAppOutputPath\$WSAppFileName.pfx"" -p password ""$WSAppOutputPath\$WSAppFileName.appx"""
    $output = Run-Process $proc $args
    if ($output -inotlike "*successfully signed*") {
        Write-Output "ERROR: Package signing failed!"
        Write-Output "proc = $proc"
        Write-Output "args = $args"
        Write-Output ("  " + $output)
        Exit 1
    }
    Write-Output "  Done."

    Remove-Item "$WSAppOutputPath\$WSAppFileName.pfx" -Force -ErrorAction SilentlyContinue
    Write-Output "Success!"
    Write-Output "  App Package: ""$WSAppOutputPath\$WSAppFileName.appx"""
    Write-Output "  Certificate: ""$WSAppOutputPath\$WSAppFileName.cer"""
    Write-Output "Install the '.cer' file to [Local Computer\Trusted Root Certification Authorities] before you install the App Package."
    Exit 0
}

# =============================================================================
# GUI MODE
# =============================================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    [System.Windows.Forms.MessageBox]::Show(
        "Administrator rights are required.`nPlease restart PowerShell as Administrator.",
        "Insufficient privileges",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    exit 1
}

$settings = Load-Settings

$form = New-Object System.Windows.Forms.Form
$form.Text = "Appx Backup – GUI"
$form.Size = New-Object System.Drawing.Size(800, 620)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$font = New-Object System.Drawing.Font("Segoe UI", 9)

# ---- Application path ----
$labelApp = New-Object System.Windows.Forms.Label
$labelApp.Text = "Path to application (WindowsApps):"
$labelApp.Location = New-Object System.Drawing.Point(10, 10)
$labelApp.Size = New-Object System.Drawing.Size(250, 20)
$labelApp.Font = $font
$textApp = New-Object System.Windows.Forms.TextBox
$textApp.Location = New-Object System.Drawing.Point(10, 32)
$textApp.Size = New-Object System.Drawing.Size(550, 20)
$textApp.Font = $font
$textApp.Text = $settings.AppPath
$btnApp = New-Object System.Windows.Forms.Button
$btnApp.Text = "Browse..."
$btnApp.Location = New-Object System.Drawing.Point(570, 30)
$btnApp.Size = New-Object System.Drawing.Size(80, 25)
$btnApp.Font = $font
$btnApp.Add_Click({
    $folder = New-Object System.Windows.Forms.FolderBrowserDialog
    $folder.SelectedPath = $textApp.Text
    if ($folder.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textApp.Text = $folder.SelectedPath
    }
})

# ---- Output folder ----
$labelOut = New-Object System.Windows.Forms.Label
$labelOut.Text = "Destination folder (.appx, .cer):"
$labelOut.Location = New-Object System.Drawing.Point(10, 70)
$labelOut.Size = New-Object System.Drawing.Size(250, 20)
$labelOut.Font = $font
$textOut = New-Object System.Windows.Forms.TextBox
$textOut.Location = New-Object System.Drawing.Point(10, 92)
$textOut.Size = New-Object System.Drawing.Size(550, 20)
$textOut.Font = $font
$textOut.Text = $settings.OutPath
$btnOut = New-Object System.Windows.Forms.Button
$btnOut.Text = "Browse..."
$btnOut.Location = New-Object System.Drawing.Point(570, 90)
$btnOut.Size = New-Object System.Drawing.Size(80, 25)
$btnOut.Font = $font
$btnOut.Add_Click({
    $folder = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($folder.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textOut.Text = $folder.SelectedPath
    }
})

# ---- Tools path ----
$labelTools = New-Object System.Windows.Forms.Label
$labelTools.Text = "Windows SDK tools folder (x64):"
$labelTools.Location = New-Object System.Drawing.Point(10, 130)
$labelTools.Size = New-Object System.Drawing.Size(250, 20)
$labelTools.Font = $font
$textTools = New-Object System.Windows.Forms.TextBox
$textTools.Location = New-Object System.Drawing.Point(10, 152)
$textTools.Size = New-Object System.Drawing.Size(550, 20)
$textTools.Font = $font
if ($settings.ToolsPath -and (Test-Path $settings.ToolsPath)) {
    $textTools.Text = $settings.ToolsPath
} else {
    $found = Find-WindowsSDK
    if ($found) { $textTools.Text = $found } else { $textTools.Text = "Not found" }
}
$btnTools = New-Object System.Windows.Forms.Button
$btnTools.Text = "Browse..."
$btnTools.Location = New-Object System.Drawing.Point(570, 150)
$btnTools.Size = New-Object System.Drawing.Size(80, 25)
$btnTools.Font = $font
$btnTools.Add_Click({
    $folder = New-Object System.Windows.Forms.FolderBrowserDialog
    $folder.SelectedPath = "C:\Program Files (x86)\Windows Kits\10\bin"
    if ($folder.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textTools.Text = $folder.SelectedPath
    }
})

# ---- Run button ----
$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "Create Backup"
$btnRun.Location = New-Object System.Drawing.Point(10, 190)
$btnRun.Size = New-Object System.Drawing.Size(150, 30)
$btnRun.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnRun.BackColor = [System.Drawing.Color]::LightGreen
$btnRun.Add_Click({
    Save-Settings $textApp.Text $textOut.Text $textTools.Text

    if ($PSScriptRoot -and (Test-Path $PSScriptRoot)) {
        $scriptFolder = $PSScriptRoot
    } else {
        $scriptFolder = (Get-Location).Path
    }
    $scriptPath = Join-Path $scriptFolder "Appx-Backup.ps1"
    if (-not (Test-Path $scriptPath)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Script file not found at: $scriptFolder",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return
    }
    if (-not (Test-Path $textApp.Text) -or -not (Test-Path $textOut.Text) -or -not (Test-Path $textTools.Text)) {
        [System.Windows.Forms.MessageBox]::Show(
            "One or more paths are invalid. Please check that all folders exist.",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }

    $btnRun.Enabled = $false
    $btnRun.BackColor = [System.Drawing.Color]::LightGray
    $btnRun.Text = "Running..."
    $logBox.Text = ""
    $logBox.AppendText("Starting backup process...`r`n")
    $logBox.AppendText("----------------------------------------`r`n")

    $progressBar.Style = "Marquee"
    $progressBar.MarqueeAnimationSpeed = 30
    $progressBar.Visible = $true

    $args = "-WSAppPath `"$($textApp.Text)`" -WSAppOutputPath `"$($textOut.Text)`" -WSTools `"$($textTools.Text)`""
    $logBox.AppendText("Command: powershell -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $args`r`n")
    $logBox.AppendText("----------------------------------------`r`n")
    $logBox.ScrollToCaret()

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "powershell.exe"
    $pinfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $args"
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null

    while (-not $p.StandardOutput.EndOfStream) {
        $line = $p.StandardOutput.ReadLine()
        $logBox.AppendText("$line`r`n")
        $logBox.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }
    while (-not $p.StandardError.EndOfStream) {
        $line = $p.StandardError.ReadLine()
        $logBox.AppendText("ERR: $line`r`n")
        $logBox.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }
    $p.WaitForExit()
    $logBox.AppendText("----------------------------------------`r`n")
    $logBox.AppendText("Process finished with exit code $($p.ExitCode).`r`n")
    if ($p.ExitCode -eq 0) {
        $logBox.AppendText("Success! Files saved to $($textOut.Text).`r`n")
        $progressBar.Value = 100
        $progressBar.Style = "Blocks"
        $progressBar.MarqueeAnimationSpeed = 0
    } else {
        $logBox.AppendText("An error occurred (exit code $($p.ExitCode)). Check the log above.`r`n")
        $progressBar.Value = 0
        $progressBar.Style = "Blocks"
        $progressBar.MarqueeAnimationSpeed = 0
    }

    # ---- Исправленный таймер с проверками ----
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 2000
    $timer.Add_Tick({
        # Проверяем, что progressBar существует и не уничтожен
        if ($progressBar -and (-not $progressBar.IsDisposed)) {
            $progressBar.Visible = $false
        }
        # Проверяем, что тайнер ещё существует
        if ($timer -ne $null) {
            $timer.Stop()
            $timer.Dispose()
        }
    })
    $timer.Start()

    $btnRun.Enabled = $true
    $btnRun.BackColor = [System.Drawing.Color]::LightGreen
    $btnRun.Text = "Create Backup"
    $logBox.ScrollToCaret()
})

# ---- Progress bar ----
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(180, 195)
$progressBar.Size = New-Object System.Drawing.Size(590, 20)
$progressBar.Style = "Blocks"
$progressBar.Visible = $false
$progressBar.Minimum = 0
$progressBar.Maximum = 100

# ---- Log ----
$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(10, 230)
$logBox.Size = New-Object System.Drawing.Size(760, 340)
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$logBox.BackColor = [System.Drawing.Color]::Black
$logBox.ForeColor = [System.Drawing.Color]::White

$form.Controls.AddRange(@($labelApp, $textApp, $btnApp,
                          $labelOut, $textOut, $btnOut,
                          $labelTools, $textTools, $btnTools,
                          $btnRun, $progressBar, $logBox))

$form.ShowDialog() | Out-Null
