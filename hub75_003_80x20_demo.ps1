param(
  [string]$WledUri = "http://192.168.178.218/json/state",
  [int]$PageSeconds = 8,
  [int]$Cycles = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Format-Decimal {
  param([double]$Value)

  return $Value.ToString("0.0", [Globalization.CultureInfo]::InvariantCulture)
}

function New-TextSegment {
  param(
    [int]$Id,
    [string]$Text,
    [int[]]$Color
  )

  return @{
    id = $Id
    start = 0
    stop = 80
    startY = 0
    stopY = 20
    fx = 122
    n = $Text
    sx = 210
    ix = 128
    c1 = 0
    c2 = 128
    pal = 0
    col = @(
      ,$Color
      ,@(0, 0, 0)
      ,@(0, 0, 0)
    )
  }
}

function Send-Page {
  param(
    [string]$Text,
    [int[]]$Color
  )

  $body = @{
    on = $true
    bri = 72
    transition = 0
    mainseg = 0
    seg = @(
      (New-TextSegment 0 $Text $Color)
      @{ id = 1; stop = 0 }
      @{ id = 2; stop = 0 }
    )
  } | ConvertTo-Json -Depth 7 -Compress

  Invoke-RestMethod `
    -Uri $WledUri `
    -Method Post `
    -ContentType "application/json" `
    -Body $body | Out-Null
}

# Simulated MQTT/Home Assistant values for the visual demonstration.
$pvPower = (Get-Random -Minimum 400 -Maximum 5801) / 1000.0
$housePower = (Get-Random -Minimum 250 -Maximum 2401) / 1000.0
$batteryPercent = Get-Random -Minimum 38 -Maximum 96
$gridPower = Get-Random -Minimum -900 -Maximum 1201
$outsideTemperature = (Get-Random -Minimum 80 -Maximum 281) / 10.0
$insideTemperature = (Get-Random -Minimum 195 -Maximum 241) / 10.0
$doorOpen = (Get-Random -Minimum 0 -Maximum 8) -eq 0

$gridText = if ($gridPower -lt 0) {
  "NETZ: $([math]::Abs($gridPower)) W EIN"
}
else {
  "NETZ: $gridPower W BEZ"
}
$gridColor = if ($gridPower -lt 0) { @(0, 220, 80) } else { @(255, 170, 0) }
$doorText = if ($doorOpen) { "TUER: OFFEN" } else { "TUER: ZU" }
$doorColor = if ($doorOpen) { @(255, 20, 0) } else { @(0, 220, 80) }

$pages = @(
  @{
    Text = "#HHMM0"
    Color = @(255, 255, 255)
  }
  @{
    Text = "#DATE0"
    Color = @(100, 160, 255)
  }
  @{
    Text = "PV: $(Format-Decimal $pvPower) kW"
    Color = @(255, 190, 0)
  }
  @{
    Text = "HAUS: $(Format-Decimal $housePower) kW"
    Color = @(0, 190, 255)
  }
  @{
    Text = "AKKU: $batteryPercent %"
    Color = @(0, 220, 80)
  }
  @{
    Text = $gridText
    Color = $gridColor
  }
  @{
    Text = "AUSSEN: $(Format-Decimal $outsideTemperature) C"
    Color = @(0, 150, 255)
  }
  @{
    Text = "INNEN: $(Format-Decimal $insideTemperature) C"
    Color = @(255, 100, 20)
  }
  @{
    Text = $doorText
    Color = $doorColor
  }
)

Write-Host "80x20-Demo: $($pages.Count) Seiten, je $PageSeconds Sekunden"
if ($Cycles -eq 0) { Write-Host "Dauerlauf aktiv; Abbruch mit Strg+C." }
else { Write-Host "$Cycles Durchlaeufe konfiguriert." }
Write-Host "PV $(Format-Decimal $pvPower) kW | Haus $(Format-Decimal $housePower) kW | Akku $batteryPercent %"

$cycle = 0
while ($Cycles -eq 0 -or $cycle -lt $Cycles) {
  foreach ($page in $pages) {
    Send-Page $page.Text $page.Color
    Start-Sleep -Seconds $PageSeconds
  }
  $cycle++
}

Write-Host "Demo beendet; die letzte Seite bleibt auf dem Display stehen."
