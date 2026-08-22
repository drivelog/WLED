# DWD observations for 04451/Borsdorf, provided as JSON by Bright Sky.
$weatherUri = "https://api.brightsky.dev/current_weather?lat=51.35&lon=12.53333"
$forecastUri = "https://api.open-meteo.com/v1/forecast?latitude=51.35&longitude=12.53333&hourly=precipitation_probability,precipitation&timezone=Europe%2FBerlin&forecast_days=2"

try {
  $weatherResponse = Invoke-RestMethod `
    -Uri $weatherUri `
    -Method Get `
    -TimeoutSec 15 `
    -ErrorAction Stop

  $forecastResponse = Invoke-RestMethod `
    -Uri $forecastUri `
    -Method Get `
    -TimeoutSec 15 `
    -ErrorAction Stop

  if ($null -eq $weatherResponse.weather.temperature -or
      $null -eq $weatherResponse.weather.relative_humidity) {
    throw "Die Wetterstation hat keine vollstaendigen Messwerte geliefert."
  }

  $temperature = [double]$weatherResponse.weather.temperature
  $humidity = [int][math]::Round([double]$weatherResponse.weather.relative_humidity)
  $temperatureText = $temperature.ToString("0.0", [Globalization.CultureInfo]::InvariantCulture)
  $pressure = [int][math]::Round([double]$weatherResponse.weather.pressure_msl)
  $windText = ([double]$weatherResponse.weather.wind_speed_10).ToString("0.0", [Globalization.CultureInfo]::InvariantCulture)
  $gustText = ([double]$weatherResponse.weather.wind_gust_speed_10).ToString("0.0", [Globalization.CultureInfo]::InvariantCulture)
  $dewPointText = ([double]$weatherResponse.weather.dew_point).ToString("0.0", [Globalization.CultureInfo]::InvariantCulture)
  $cloudCover = [int][math]::Round([double]$weatherResponse.weather.cloud_cover)
  $visibility = [int][math]::Round(([double]$weatherResponse.weather.visibility) / 1000)
  $windDirection = [int][math]::Round([double]$weatherResponse.weather.wind_direction_10)
  $compassPoints = @("N", "NO", "O", "SO", "S", "SW", "W", "NW")
  $windCompass = $compassPoints[[int][math]::Floor((($windDirection + 22.5) % 360) / 45)]
  $rain10Text = ([double]$weatherResponse.weather.precipitation_10).ToString("0.0", [Globalization.CultureInfo]::InvariantCulture)
  $currentRainText = ([double]$weatherResponse.weather.precipitation_60).ToString("0.0", [Globalization.CultureInfo]::InvariantCulture)
  $stationName = [string]$weatherResponse.sources[0].station_name

  $tomorrow = (Get-Date).Date.AddDays(1)
  $morningProbabilities = @()
  $morningPrecipitation = @()

  for ($index = 0; $index -lt $forecastResponse.hourly.time.Count; $index++) {
    $forecastTime = [datetime]::Parse($forecastResponse.hourly.time[$index], [Globalization.CultureInfo]::InvariantCulture)
    if ($forecastTime.Date -eq $tomorrow -and $forecastTime.Hour -ge 5 -and $forecastTime.Hour -lt 11) {
      $morningProbabilities += [int]$forecastResponse.hourly.precipitation_probability[$index]
      $morningPrecipitation += [double]$forecastResponse.hourly.precipitation[$index]
    }
  }

  if ($morningProbabilities.Count -eq 0) {
    throw "Fuer morgen frueh wurden keine Prognosedaten geliefert."
  }

  $maxRainProbability = [int](($morningProbabilities | Measure-Object -Maximum).Maximum)
  $rainAmount = [double](($morningPrecipitation | Measure-Object -Sum).Sum)

  Write-Host "Wetterstation: $stationName"
  Write-Host "Temperatur: $temperatureText C, Luftfeuchte: $humidity %"
  Write-Host "Luftdruck: $pressure hPa, Wind: $windText km/h, Boeen: $gustText km/h"
  Write-Host "Regen letzte 60 Minuten: $currentRainText mm"
  Write-Host "Regen morgen 05:00-11:00 Uhr: $maxRainProbability %, $rainAmount mm"
}
catch {
  Write-Error "Wetterdaten konnten nicht geladen werden: $($_.Exception.Message)"
  exit 1
}

function New-TextSegment {
  param(
    [int]$Id,
    [int]$Start,
    [int]$Stop,
    [int]$StartY,
    [int]$StopY,
    [string]$Text,
    [int[]]$Color
  )

  return @{
    id = $Id
    start = $Start
    stop = $Stop
    startY = $StartY
    stopY = $StopY
    fx = 122
    n = $Text
    sx = 220
    ix = 128
    c2 = 0
    pal = 0
    col = @(
      ,$Color
      ,@(0, 0, 0)
      ,@(0, 0, 0)
    )
  }
}

function New-LineSegment {
  param(
    [int]$Id,
    [int]$Start,
    [int]$Stop,
    [int]$StartY,
    [int]$StopY
  )

  return @{
    id = $Id
    start = $Start
    stop = $Stop
    startY = $StartY
    stopY = $StopY
    fx = 0
    pal = 0
    col = @(
      ,@(48, 48, 48)
      ,@(0, 0, 0)
      ,@(0, 0, 0)
    )
  }
}

$segments = @(
  New-TextSegment 0 0 31 0 7 "${temperatureText}C" @(255, 60, 0)
  New-TextSegment 1 32 63 0 7 "$humidity%" @(0, 120, 255)
  New-TextSegment 2 64 95 0 7 "TP$dewPointText" @(0, 220, 180)
  New-TextSegment 3 96 128 0 7 "${pressure}h" @(180, 80, 255)

  New-TextSegment 4 0 31 8 15 "W$windText" @(0, 220, 220)
  New-TextSegment 5 32 63 8 15 "B$gustText" @(255, 180, 0)
  New-TextSegment 6 64 95 8 15 "$windCompass $windDirection" @(255, 255, 0)
  New-TextSegment 7 96 128 8 15 "${visibility}km" @(160, 200, 255)

  New-TextSegment 8 0 31 16 23 "R10 $rain10Text" @(0, 100, 255)
  New-TextSegment 9 32 63 16 23 "R60 $currentRainText" @(0, 100, 255)
  New-TextSegment 10 64 95 16 23 "WK$cloudCover%" @(140, 140, 180)
  New-TextSegment 11 96 128 16 23 "$($weatherResponse.weather.condition)" @(180, 220, 180)

  New-TextSegment 12 0 31 24 32 "M$maxRainProbability%" @($(if ($maxRainProbability -ge 20) { 0 } else { 40 }), $(if ($maxRainProbability -ge 20) { 120 } else { 255 }), $(if ($maxRainProbability -ge 20) { 255 } else { 40 }))
  New-TextSegment 13 32 63 24 32 "M$($rainAmount.ToString('0.0', [Globalization.CultureInfo]::InvariantCulture))mm" @(0, 120, 255)
  New-TextSegment 14 64 95 24 32 "#DDMM0" @(255, 255, 255)
  New-TextSegment 15 96 128 24 32 "#HHMM0" @(255, 255, 255)

  New-LineSegment 16 31 32 0 32
  New-LineSegment 17 63 64 0 32
  New-LineSegment 18 95 96 0 32
  New-LineSegment 19 0 128 7 8
  New-LineSegment 20 0 128 15 16
  New-LineSegment 21 0 128 23 24
)

$wledUri = "http://192.168.178.214/json/state"
$segmentBatches = @(
  @($segments[0..3])
  @($segments[4..7])
  @($segments[8..11])
  @($segments[12..15])
  @($segments[16..21])
)

for ($batchIndex = 0; $batchIndex -lt $segmentBatches.Count; $batchIndex++) {
  $request = @{
    transition = 0
    seg = $segmentBatches[$batchIndex]
  }
  if ($batchIndex -eq 0) {
    $request.on = $true
  }

  $body = $request | ConvertTo-Json -Depth 7 -Compress
  Invoke-RestMethod `
    -Uri $wledUri `
    -Method Post `
    -ContentType "application/json" `
    -Body $body `
    -ErrorAction Stop | Out-Null
}

Write-Host "4x4-Anzeige wurde an WLED gesendet."
