# DWD observations for 04451/Borsdorf, provided as JSON by Bright Sky.
$weatherUri = "https://api.brightsky.dev/current_weather?lat=51.35&lon=12.53333"
$forecastUri = "https://api.open-meteo.com/v1/forecast?latitude=51.35&longitude=12.53333&hourly=precipitation_probability,precipitation&daily=sunrise,sunset&timezone=Europe%2FBerlin&forecast_days=2"

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
  $rain30Text = ([double]$weatherResponse.weather.precipitation_30).ToString("0.0", [Globalization.CultureInfo]::InvariantCulture)
  $currentRainText = ([double]$weatherResponse.weather.precipitation_60).ToString("0.0", [Globalization.CultureInfo]::InvariantCulture)
  $stationName = [string]$weatherResponse.sources[0].station_name
  $measurementTime = ([datetimeoffset]::Parse($weatherResponse.weather.timestamp)).ToLocalTime().ToString("HH:mm")

  $conditionNames = @{
    dry = "Trocken"
    rain = "Regen"
    snow = "Schnee"
    sleet = "Schneeregen"
    fog = "Nebel"
    hail = "Hagel"
    thunderstorm = "Gewitter"
  }
  $condition = [string]$weatherResponse.weather.condition
  $conditionText = if ($conditionNames.ContainsKey($condition)) { $conditionNames[$condition] } else { $condition }

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
  $tomorrowText = $tomorrow.ToString("yyyy-MM-dd")
  $tomorrowIndex = [array]::IndexOf([array]$forecastResponse.daily.time, $tomorrowText)
  if ($tomorrowIndex -lt 0) {
    throw "Fuer morgen wurden keine Sonnenzeiten geliefert."
  }
  $sunrise = ([datetime]::Parse($forecastResponse.daily.sunrise[$tomorrowIndex])).ToString("HH:mm")
  $sunset = ([datetime]::Parse($forecastResponse.daily.sunset[$tomorrowIndex])).ToString("HH:mm")

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
    sx = 245
    ix = 128
    c1 = 0
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
  New-TextSegment 0 0 30 0 6 "Temp: $temperatureText C" @(255, 60, 0)
  New-TextSegment 1 33 63 0 6 "Feucht: $humidity %" @(0, 120, 255)
  New-TextSegment 2 66 96 0 6 "Taupkt: $dewPointText C" @(0, 220, 180)
  New-TextSegment 3 99 128 0 6 "Druck: $pressure hPa" @(180, 80, 255)

  New-TextSegment 4 0 30 6 12 "Wind: $windText km/h" @(0, 220, 220)
  New-TextSegment 5 33 63 6 12 "Boeen: $gustText km/h" @(255, 180, 0)
  New-TextSegment 6 66 96 6 12 "Richtg: $windCompass $windDirection Grad" @(255, 255, 0)
  New-TextSegment 7 99 128 6 12 "Sicht: $visibility km" @(160, 200, 255)

  New-TextSegment 8 0 30 12 18 "Reg10: $rain10Text mm" @(0, 100, 255)
  New-TextSegment 9 33 63 12 18 "Reg30: $rain30Text mm" @(0, 100, 255)
  New-TextSegment 10 66 96 12 18 "Reg60: $currentRainText mm" @(0, 100, 255)
  New-TextSegment 11 99 128 12 18 "Wolken: $cloudCover %" @(140, 140, 180)

  New-TextSegment 12 0 30 18 25 "Wetter: $conditionText" @(180, 220, 180)
  New-TextSegment 13 33 63 18 25 "MorgR: $maxRainProbability %" @($(if ($maxRainProbability -ge 20) { 0 } else { 40 }), $(if ($maxRainProbability -ge 20) { 120 } else { 255 }), $(if ($maxRainProbability -ge 20) { 255 } else { 40 }))
  New-TextSegment 14 66 96 18 25 "MorgM: $($rainAmount.ToString('0.0', [Globalization.CultureInfo]::InvariantCulture) ) mm" @(0, 120, 255)
  New-TextSegment 15 99 128 18 25 "Stand: $measurementTime Uhr" @(160, 255, 160)

  New-TextSegment 16 0 30 25 32 "S-Auf: $sunrise Uhr" @(255, 180, 0)
  New-TextSegment 17 33 63 25 32 "S-Unt: $sunset Uhr" @(255, 100, 0)
  New-TextSegment 18 66 96 25 32 "Datum: #DATE0" @(255, 255, 255)
  New-TextSegment 19 99 128 25 32 "Zeit: #HHMM0 Uhr" @(255, 255, 255)

  New-LineSegment 20 31 32 0 32
  New-LineSegment 21 64 65 0 32
  New-LineSegment 22 97 98 0 32
  @{ id = 23; stop = 0 }
  @{ id = 24; stop = 0 }
  @{ id = 25; stop = 0 }
  @{ id = 26; stop = 0 }
)

$wledUri = "http://192.168.178.214/json/state"
$segmentBatches = @(
  @($segments[0..3])
  @($segments[4..7])
  @($segments[8..11])
  @($segments[12..15])
  @($segments[16..19])
  @($segments[20..22])
  @($segments[23..26])
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

Write-Host "4x5-Anzeige mit vollstaendigen Einheiten wurde an WLED gesendet."
