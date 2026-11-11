# SPDX-License-Identifier: MIT
# The printer of the trials: « Microsoft Print To PDF » on a port that is a
# file, named « Color essai » and made the default printer. Nothing reaches a
# printer of paper.   imprimante-d-essai.ps1 FILE
$ErrorActionPreference = 'Stop'
$port = $args[0]
Set-Service -Name Spooler -StartupType Manual
Start-Service -Name Spooler
# Windows would otherwise make the last printer used the default one.
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows' -Name LegacyDefaultPrinterMode -Value 1 -PropertyType DWord -Force | Out-Null
if (-not (Get-PrinterDriver -Name 'Microsoft Print To PDF' -ErrorAction SilentlyContinue)) {
  try { Add-PrinterDriver -Name 'Microsoft Print To PDF' } catch {
    Enable-WindowsOptionalFeature -Online -FeatureName Printing-PrintToPDFServices-Features -All -NoRestart | Out-Null
    Add-PrinterDriver -Name 'Microsoft Print To PDF'
  }
}
if (-not (Get-PrinterPort -Name $port -ErrorAction SilentlyContinue)) { Add-PrinterPort -Name $port }
if (-not (Get-Printer -Name 'Color essai' -ErrorAction SilentlyContinue)) {
  Add-Printer -Name 'Color essai' -DriverName 'Microsoft Print To PDF' -PortName $port
}
$printer = Get-CimInstance -ClassName Win32_Printer -Filter "Name='Color essai'"
Invoke-CimMethod -InputObject $printer -MethodName SetDefaultPrinter | Out-Null
Get-Printer | Format-Table -AutoSize Name, DriverName, PortName
Get-CimInstance -ClassName Win32_Printer | Format-Table -AutoSize Name, Default
