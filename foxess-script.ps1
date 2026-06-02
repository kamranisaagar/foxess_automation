$ErrorActionPreference = "Stop"

# Use relative pathing so the script doesn't break if you move it

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path -Path $ScriptDir -ChildPath "foxess-config.json"
$LogPath = Join-Path -Path $ScriptDir -ChildPath "foxess-daypush.log"

$ScriptConfig = @{
    Location = @{ Name="Sydney, Australia"; Latitude=-33.865143; Longitude=151.2093; Timezone="Australia/Sydney"; WindowsTimezoneId="AUS Eastern Standard Time" }
    SolarAssessment = @{ StartHour=9; EndHour=16 }
    Retry = @{ MaxAttempts=4; DelaySeconds=3 }

    Testing = @{
        Enabled = $false
        SimulatedTomorrowDay = "Saturday"
        SimulatedAverageShortwave = 450.0
    }

    # Numbered templates only.
    # For FoxESS scheduler/enable, use extraParam.fdSoc + extraParam.fdPwr.
    Templates = @{
      
      # Very Poor Solar Night Template
        1 = @{ WorkMode="ForceCharge"; StartHour=0; StartMinute=1; EndHour=3; EndMinute=30; extraParam=@{ fdSoc=100; fdPwr=7500 } }
        2 = @{ WorkMode="ForceCharge"; StartHour=3; StartMinute=32; EndHour=5; EndMinute=58; extraParam=@{ fdSoc=100; fdPwr=2000 } }

      # Poor Solar Night Template
        3 = @{ WorkMode="ForceCharge"; StartHour=0; StartMinute=1; EndHour=3; EndMinute=30; extraParam=@{ fdSoc=65; fdPwr=6000 } }
        4 = @{ WorkMode="ForceCharge"; StartHour=3; StartMinute=32; EndHour=5; EndMinute=58; extraParam=@{ fdSoc=65; fdPwr=1500 } }

      # Moderate Solar Night Template
        5 = @{ WorkMode="ForceCharge"; StartHour=0; StartMinute=1; EndHour=3; EndMinute=30; extraParam=@{ fdSoc=50; fdPwr=6000 } }
        6 = @{ WorkMode="ForceCharge"; StartHour=3; StartMinute=32; EndHour=5; EndMinute=58; extraParam=@{ fdSoc=50; fdPwr=1500 } }

      # Good Solar Night Template
        7 = @{ WorkMode="ForceCharge"; StartHour=0; StartMinute=1; EndHour=3; EndMinute=30; extraParam=@{ fdSoc=35; fdPwr=6000 } }
        8 = @{ WorkMode="ForceCharge"; StartHour=3; StartMinute=32; EndHour=5; EndMinute=58; extraParam=@{ fdSoc=35; fdPwr=1500 } }

      # Strong Solar Night Template
        9 = @{ WorkMode="Backup"; StartHour=3; StartMinute=32; EndHour=5; EndMinute=58 }
     
      # Day Override
        10 = @{ WorkMode="ForceCharge"; StartHour=0; StartMinute=1; EndHour=3; EndMinute=30; extraParam=@{ fdSoc=100; fdPwr=7500 } }
        11 = @{ WorkMode="ForceCharge"; StartHour=3; StartMinute=32; EndHour=5; EndMinute=58; extraParam=@{ fdSoc=100; fdPwr=2000 } }
          
      # Weekend Schedule (Includes day free window for my power plan)
        12 = @{ WorkMode="ForceCharge"; StartHour=1; StartMinute=00; EndHour=5; EndMinute=58; extraParam=@{ fdSoc=35; fdPwr=1500 } }
        13 = @{ WorkMode="ForceCharge"; StartHour=12; StartMinute=1; EndHour=13; EndMinute=58; extraParam=@{ fdSoc=100; fdPwr=9000 } }
    }

    DayOverride = @{ Enabled=$false; Days=@("Wednesday"); ApplyTemplates=@(10,11) }
    WeekendRule = @{ Enabled=$true; Days=@("Saturday","Sunday"); ApplyTemplates=@(12,13) }

    WeatherCategories = @(
        @{ Name="Very poor"; Min=$null; Max=199.9; ApplyTemplates=@(1,2) },
        @{ Name="Poor"; Min=200.0; Max=299.9; ApplyTemplates=@(3,4) },
        @{ Name="Moderate"; Min=300.0; Max=349.9; ApplyTemplates=@(5,6) },
        @{ Name="Good"; Min=350.0; Max=400.0; ApplyTemplates=@(7,8) },
        @{ Name="Strong"; Min=400.0; Max=$null; ApplyTemplates=@(9) }
    )
}


# ============================================================
# Decision block (read this first)
# ============================================================
# 1) If WeekendRule.Enabled = true AND tomorrow is in WeekendRule.Days:
#       apply WeekendRule.ApplyTemplates and skip weather/day override for scheduling
# 2) Else if DayOverride.Enabled = true AND tomorrow day matches DayOverride.Days:
#       apply DayOverride.ApplyTemplates
# 3) Else: evaluate weather category by average shortwave and apply its templates
# 4) Push only these templates (existing schedules are replaced)

if (!(Test-Path $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
$ApiKey = ([string]$config.ApiKey).Trim(); $DeviceSN = ([string]$config.DeviceSN).Trim(); $BaseUrl = ([string]$config.BaseUrl).TrimEnd("/"); $LogPath = ([string]$config.LogPath).Trim()
$NtfyUrl = ([string]$config.NtfyUrl).Trim()
$NtfyTitle = ([string]$config.NtfyTitle).Trim()
if ([string]::IsNullOrWhiteSpace($ApiKey)) { throw "ApiKey missing in config file." }
if ([string]::IsNullOrWhiteSpace($DeviceSN)) { throw "DeviceSN missing in config file." }
if ([string]::IsNullOrWhiteSpace($BaseUrl)) { throw "BaseUrl missing in config file." }
if ([string]::IsNullOrWhiteSpace($NtfyTitle)) { $NtfyTitle = "FoxESS CutoffOnly" }

function Send-NtfyNotification {
 param([string]$Message)

 if([string]::IsNullOrWhiteSpace($NtfyUrl)){ return }

 try {
   Invoke-RestMethod -Method Post -Uri $NtfyUrl -Headers @{ Title=$NtfyTitle } -ContentType 'text/plain; charset=utf-8' -Body $Message | Out-Null
 } catch {
   Write-Host "ntfy notification failed: $($_.Exception.Message)"
 }
}
$DecisionLogLines = New-Object System.Collections.Generic.List[string]

function Write-DecisionLog {
 param([string]$Message)

 $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $Message"
 Add-Content -Path $LogPath -Value $line
 $DecisionLogLines.Add($line)
}
function Send-DecisionLogNotification {
 if($DecisionLogLines.Count -eq 0){ return }

 Send-NtfyNotification -Message ($DecisionLogLines -join [Environment]::NewLine)
}
function Write-Both { param([string]$Message) Write-Host $Message; Write-DecisionLog $Message }
function Get-Md5Lower { param([string]$Text) $md5=[System.Security.Cryptography.MD5]::Create(); $hash=$md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)); -join ($hash|%{$_.ToString('x2')}) }
function Assert-FoxSuccess { param($Response,[string]$StepName) if($null -eq $Response.errno){throw "$StepName failed. No errno returned."}; if([int]$Response.errno -ne 0){throw "$StepName failed. errno=$($Response.errno), msg=$($Response.msg)"} }
function Invoke-WithRetry { param([scriptblock]$Action,[string]$ActionName,[hashtable]$RetryConfig) for($i=1;$i -le [int]$RetryConfig.MaxAttempts;$i++){ try{ return & $Action } catch { if($i -ge [int]$RetryConfig.MaxAttempts){ throw "$ActionName failed after $i attempt(s). Last error: $($_.Exception.Message)" }; Write-Both "$ActionName attempt $i/$($RetryConfig.MaxAttempts) failed. Retrying in $($RetryConfig.DelaySeconds)s"; Start-Sleep -Seconds [int]$RetryConfig.DelaySeconds } } }
function Invoke-FoxPost { param([string]$Path,[hashtable]$Body) $ts=[string][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); $sig=Get-Md5Lower -Text ($Path+'\r\n'+$ApiKey+'\r\n'+$ts); $headers=@{token=$ApiKey;timestamp=$ts;signature=$sig;lang='en';'User-Agent'='Mozilla/5.0 (WindowsPowerShell-FoxESS-TemplateOnly)'}; Invoke-RestMethod -Method Post -Uri "$BaseUrl$Path" -Headers $headers -ContentType 'application/json' -Body ($Body|ConvertTo-Json -Depth 100 -Compress) }
function Get-TomorrowInfo { param([string]$WindowsTimezoneId) $z=[System.TimeZoneInfo]::FindSystemTimeZoneById($WindowsTimezoneId); $now=[System.TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow,$z); $t=$now.Date.AddDays(1); @{LocalNow=$now;TomorrowDate=$t.ToString('yyyy-MM-dd');TomorrowDay=$t.DayOfWeek.ToString()} }
function Get-SolarData { param([hashtable]$Config,[hashtable]$TomorrowInfo)
 if($Config.Testing.Enabled){ return @{ Date=$TomorrowInfo.TomorrowDate; Average=[double]$Config.Testing.SimulatedAverageShortwave; IsSimulated=$true } }
 $tz=[System.Uri]::EscapeDataString([string]$Config.Location.Timezone)
 $url="https://api.open-meteo.com/v1/forecast?latitude=$($Config.Location.Latitude)&longitude=$($Config.Location.Longitude)&hourly=shortwave_radiation&timezone=$tz&start_date=$($TomorrowInfo.TomorrowDate)&end_date=$($TomorrowInfo.TomorrowDate)"
 $w=Invoke-WithRetry -Action { Invoke-RestMethod -Method Get -Uri $url } -ActionName 'Open-Meteo fetch' -RetryConfig $Config.Retry
 $vals=@(); for($i=0;$i -lt $w.hourly.time.Count;$i++){ $dt=[datetime]::Parse([string]$w.hourly.time[$i]); if($dt.Hour -ge [int]$Config.SolarAssessment.StartHour -and $dt.Hour -le [int]$Config.SolarAssessment.EndHour){ $vals += [double]$w.hourly.shortwave_radiation[$i] } }
 if($vals.Count -eq 0){ throw 'No shortwave_radiation values found in configured window.' }
 @{ Date=$TomorrowInfo.TomorrowDate; Average=[math]::Round((($vals|Measure-Object -Average).Average),1); Values=$vals; IsSimulated=$false }
}
function Get-WeatherCategory { param([double]$Average,[array]$Categories) foreach($c in $Categories){ if((($null -eq $c.Min) -or $Average -ge [double]$c.Min) -and (($null -eq $c.Max) -or $Average -le [double]$c.Max)){ return $c } }; throw "No weather category for $Average" }
function Get-ApplyTemplates {
 param(
   [hashtable]$Config,
   [hashtable]$Tomorrow,
   [hashtable]$Solar
 )

 $isWeekend = [bool]$Config.WeekendRule.Enabled -and ($Config.WeekendRule.Days -contains $Tomorrow.TomorrowDay)
 $isDayMatch = $Config.DayOverride.Days -contains $Tomorrow.TomorrowDay

 # Enabled weekend schedule overrides everything. Day override/weather still run on weekends when disabled.
 if($isWeekend){
   $weekendTemplates = @($Config.WeekendRule.ApplyTemplates)

   return @{
     NightTemplates=@()
     AdditionalTemplates=@()
     ApplyTemplates=$weekendTemplates
     Source='WeekendRule'
     WeatherCategory='Skipped'
     IsWeekend=$true
   }
 }

 # Weekday day override
 if($Config.DayOverride.Enabled -and $isDayMatch){
   $nightly=@($Config.DayOverride.ApplyTemplates)
   $source='DayOverride'
   $weather='Skipped'
 } else {
   $cat=Get-WeatherCategory -Average $Solar.Average -Categories $Config.WeatherCategories
   $nightly=@($cat.ApplyTemplates)
   $source='Weather'
   $weather=[string]$cat.Name
 }

 return @{
   NightTemplates=$nightly
   AdditionalTemplates=@()
   ApplyTemplates=$nightly
   Source=$source
   WeatherCategory=$weather
   IsWeekend=$false
 }
}

function Build-Groups {
 param([hashtable]$Templates,[array]$Ids)

 $groups=@()

 foreach($id in $Ids){
   if(!$Templates.ContainsKey($id)){
     throw "Template $id missing"
   }

   $t=$Templates[$id]

   $g=@{
     enable=1
     startHour=[int]$t.StartHour
     startMinute=[int]$t.StartMinute
     endHour=[int]$t.EndHour
     endMinute=[int]$t.EndMinute
     workMode=[string]$t.WorkMode
   }

   if($t.ContainsKey('extraParam')){
     $g['extraParam']=@{} + $t.extraParam
   }

   $groups += $g
 }

 $groups
}

try {
 $tom=Get-TomorrowInfo -WindowsTimezoneId $ScriptConfig.Location.WindowsTimezoneId
 if($ScriptConfig.Testing.Enabled){ $tom['TomorrowDay']=$ScriptConfig.Testing.SimulatedTomorrowDay; Write-Both 'TESTING MODE: ON' }
 $solar=Get-SolarData -Config $ScriptConfig -TomorrowInfo $tom
 $decision=Get-ApplyTemplates -Config $ScriptConfig -Tomorrow $tom -Solar $solar
 $groups=Build-Groups -Templates $ScriptConfig.Templates -Ids $decision.ApplyTemplates

 Write-Both "Tomorrow: $($tom.TomorrowDate) $($tom.TomorrowDay)"
 Write-Both "Decision source: $($decision.Source) | Weather category: $($decision.WeatherCategory)"
 if($decision.IsWeekend){
   Write-Both "Solar avg: $($solar.Average) W/mÂ² (Skipped)"
 } else {
   Write-Both "Solar avg: $($solar.Average) W/mÂ²"
 }
 Write-Both "Apply templates: $($decision.ApplyTemplates -join ', ')"
 Write-Both "Group count to send: $(@($groups).Count)"

 $push = Invoke-WithRetry -Action { Invoke-FoxPost -Path '/op/v3/device/scheduler/enable' -Body @{deviceSN=$DeviceSN;isDefault=$true;groups=@($groups)} } -ActionName 'FoxESS push scheduler' -RetryConfig $ScriptConfig.Retry
 Assert-FoxSuccess -Response $push -StepName 'Push scheduler'
 $after=Invoke-WithRetry -Action { Invoke-FoxPost -Path '/op/v3/device/scheduler/get' -Body @{deviceSN=$DeviceSN} } -ActionName 'FoxESS read scheduler' -RetryConfig $ScriptConfig.Retry
 Assert-FoxSuccess -Response $after -StepName 'Read scheduler'
 Write-Both "Read-back group count: $(@($after.result.groups).Count)"
 Send-DecisionLogNotification
 exit 0
}
catch {
 Write-DecisionLog "Failure reason: $($_.Exception.Message)"
 Write-Host "FAILED: $($_.Exception.Message)"
 Send-DecisionLogNotification
 exit 1
}
