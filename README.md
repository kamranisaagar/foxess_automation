# FoxESS Smart Scheduler User Manual

## What This Script Does

This PowerShell script automatically updates your FoxESS inverter battery schedule each day.

Instead of manually deciding how much to charge your battery overnight, the script checks:

- Tomorrow's day of the week
- Tomorrow's solar forecast
- Your weekend rule
- Your day override rule
- Your weather-based charging templates

It then sends the selected charging schedule to your FoxESS inverter and sends a notification to your phone using ntfy.

## Important: Do Not Copy the Templates Blindly

The included templates are customized for a specific setup.

The example values include:

- Charge power up to 7500 W and 9000 W
- Battery targets such as 35%, 50%, 65%, and 100%
- A large 42 kWh LFP battery bank
- Heavy overnight EV charging
- A specific household usage pattern

You must adjust these values for your own system.

A 35% battery target on a 42 kWh battery may run a house for hours. On a 5 kWh or 10 kWh battery, 35% may not last long at all.

Before running the script, check that your inverter, battery, wiring, and electricity plan can safely support the charging power values you enter.

## How the Script Decides What to Do

The script runs once per day and builds tomorrow's schedule using this priority order:

### 1. WeekendRule

If `WeekendRule.Enabled` is set to `$true` and tomorrow is listed in `WeekendRule.Days`, the script applies the weekend templates.

When this happens, weather and day override scheduling are skipped.

### 2. DayOverride

If the weekend rule does not apply, and `DayOverride.Enabled` is set to `$true`, and tomorrow is listed in `DayOverride.Days`, the script applies the day override templates.

### 3. WeatherCategories

If neither the weekend rule nor day override applies, the script checks tomorrow's average shortwave radiation from Open-Meteo.

It then chooses the matching weather category:

- Very poor
- Poor
- Moderate
- Good
- Strong

### 4. Push to FoxESS

The script sends only the selected templates to FoxESS.

Important: the active FoxESS scheduler is replaced with the selected templates. Old schedule groups are not kept.

### 5. Read-back Check

After pushing the schedule, the script reads the scheduler back from FoxESS and logs the group count.

### 6. Notification

The script sends the decision log to ntfy so you can see what schedule was applied.

## Files You Need

You need two files in the same folder:

```text
foxess-script.ps1
foxess-config.json
```

The script automatically looks for `foxess-config.json` in the same folder as the PowerShell script.

## Create the Config File

Create a file named:

```text
foxess-config.json
```

Put it in the same folder as the script.

Example:

```json
{
  "ApiKey": "YOUR_FOXESS_API_KEY",
  "DeviceSN": "YOUR_INVERTER_SERIAL_NUMBER",
  "BaseUrl": "https://www.foxesscloud.com",
  "LogPath": "C:\\Path\\To\\Your\\foxess-daypush.log",
  "NtfyUrl": "https://ntfy.sh/YourUniqueTopicName",
  "NtfyTitle": "FoxESS Battery Update"
}
```

### Config File Fields

#### ApiKey

Your FoxESS API key.

#### DeviceSN

Your inverter serial number.

#### BaseUrl

Usually:

```text
https://www.foxesscloud.com
```

#### LogPath

Where the script writes its daily decision log.

Example:

```text
C:\FoxESS\foxess-daypush.log
```

Make sure the folder exists and Windows has permission to write to it.

#### NtfyUrl

Your ntfy topic URL.

Example:

```text
https://ntfy.sh/MyHouseFoxESS_123
```

Leave this blank only if you do not want phone notifications.

#### NtfyTitle

The title shown on your ntfy notification.

## Set Up ntfy Notifications

ntfy lets the script send a push notification to your phone.

1. Install the ntfy app on your phone.
2. Subscribe to a unique topic name.
3. Put the matching topic URL into `NtfyUrl` in `foxess-config.json`.

Example:

```json
"NtfyUrl": "https://ntfy.sh/MyHouseFoxESS_123"
```

Use a unique topic name so other people do not accidentally subscribe to the same topic.

## Edit the Script Configuration

Open the script and find this section:

```powershell
$ScriptConfig = @{
```

Update these values.

### Location

```powershell
Location = @{ Name="Canberra, Australia"; Latitude=-35.2809; Longitude=149.1300; Timezone="Australia/Sydney"; WindowsTimezoneId="AUS Eastern Standard Time" }
```

Change:

- `Name`
- `Latitude`
- `Longitude`
- `Timezone`
- `WindowsTimezoneId`

The latitude and longitude are used for the solar forecast.

The Windows timezone ID is used to calculate tomorrow correctly on the computer running the script.

### SolarAssessment

```powershell
SolarAssessment = @{ StartHour=9; EndHour=16 }
```

This is the time window used to calculate average solar radiation.

The script includes hours where:

```powershell
Hour >= StartHour
Hour <= EndHour
```

Example:

```powershell
StartHour=9; EndHour=16
```

This checks forecast values from 9:00 through 16:00.

Adjust this to match when your panels actually receive useful sunlight.

### Retry

```powershell
Retry = @{ MaxAttempts=4; DelaySeconds=3 }
```

This controls retry behaviour if Open-Meteo or FoxESS does not respond.

## Testing Mode

The script includes a testing mode:

```powershell
Testing = @{
    Enabled = $false
    SimulatedTomorrowDay = "Saturday"
    SimulatedAverageShortwave = 450.0
}
```

For normal use, keep:

```powershell
Enabled = $false
```

To test decisions without relying on the real forecast, set:

```powershell
Enabled = $true
```

Then adjust:

```powershell
SimulatedTomorrowDay = "Saturday"
SimulatedAverageShortwave = 450.0
```

Important: testing mode still allows the script to push a schedule to FoxESS. Only enable it when you are intentionally testing.

## Understanding Templates

Templates are the schedule blocks sent to FoxESS.

Example:

```powershell
1 = @{ WorkMode="ForceCharge"; StartHour=0; StartMinute=1; EndHour=3; EndMinute=30; extraParam=@{ fdSoc=100; fdPwr=7500 } }
```

### Template Fields

#### WorkMode

The inverter mode.

Common examples in this script:

```text
ForceCharge
Backup
```

#### StartHour and StartMinute

The time the schedule block starts.

Example:

```powershell
StartHour=0; StartMinute=1
```

This means 12:01 AM.

#### EndHour and EndMinute

The time the schedule block ends.

Example:

```powershell
EndHour=3; EndMinute=30
```

This means 3:30 AM.

#### fdSoc

Target battery state of charge.

Example:

```powershell
fdSoc=65
```

This targets 65%.

#### fdPwr

Charging power in watts.

Example:

```powershell
fdPwr=6000
```

This limits grid charging to 6000 W.

#### extraParam

Used when the template needs `fdSoc` and `fdPwr`.

The script only adds `extraParam` if it exists in the template.

## Editing Templates

To change a template, edit the matching numbered entry inside:

```powershell
Templates = @{
```

Example:

```powershell
7 = @{ WorkMode="ForceCharge"; StartHour=0; StartMinute=1; EndHour=3; EndMinute=30; extraParam=@{ fdSoc=35; fdPwr=6000 } }
```

You can change:

- Start time
- End time
- WorkMode
- Target charge percentage
- Charge power

## Adding a New Template

1. Pick a new unused number.

Example:

```powershell
14 = @{ WorkMode="ForceCharge"; StartHour=2; StartMinute=0; EndHour=4; EndMinute=0; extraParam=@{ fdSoc=80; fdPwr=3000 } }
```

2. Add the new template inside the `Templates` block.

3. Link the new template number to a rule.

Example:

```powershell
WeekendRule = @{ Enabled=$true; Days=@("Saturday","Sunday"); ApplyTemplates=@(12,13,14) }
```

## Weekend Rule

Example:

```powershell
WeekendRule = @{ Enabled=$true; Days=@("Saturday","Sunday"); ApplyTemplates=@(12,13) }
```

If enabled, and tomorrow is Saturday or Sunday, templates 12 and 13 are applied.

WeekendRule has the highest priority.

## Day Override

Example:

```powershell
DayOverride = @{ Enabled=$false; Days=@("Wednesday"); ApplyTemplates=@(10,11) }
```

If enabled, and tomorrow matches one of the listed days, the script applies the selected templates.

This is useful if you always want a certain battery schedule on a specific day.

## Weather Categories

Example:

```powershell
WeatherCategories = @(
    @{ Name="Very poor"; Min=$null; Max=199.9; ApplyTemplates=@(1,2) },
    @{ Name="Poor"; Min=200.0; Max=299.9; ApplyTemplates=@(3,4) },
    @{ Name="Moderate"; Min=300.0; Max=349.9; ApplyTemplates=@(5,6) },
    @{ Name="Good"; Min=350.0; Max=400.0; ApplyTemplates=@(7,8) },
    @{ Name="Strong"; Min=400.0; Max=$null; ApplyTemplates=@(9) }
)
```

The script calculates tomorrow's average shortwave radiation during your configured solar assessment window.

It then applies the first matching category.

You can adjust the thresholds and template numbers to suit your location, solar array, battery size, and energy use.

## Automating the Script with Windows Task Scheduler

1. Open the Windows Start menu.
2. Search for `Task Scheduler`.
3. Click `Create Basic Task`.
4. Name it:

```text
FoxESS Daily Update
```

5. Set the trigger to `Daily`.
6. Choose a time in the evening, such as:

```text
8:00 PM
```

7. Set the action to `Start a program`.
8. In `Program/script`, enter:

```text
powershell.exe
```

9. In `Add arguments`, enter:

```text
-ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Your\Folder\foxess-script.ps1"
```

10. Replace the path with the real location of your script.
11. Finish the task.

## Checking That It Worked

After the script runs, check:

1. The log file set in `LogPath`
2. Your ntfy notification
3. The FoxESS scheduler in the app or portal

The log should show:

- Tomorrow's date and day
- Decision source
- Weather category
- Solar average
- Templates applied
- Group count sent
- Read-back group count

## Common Problems

### Config file not found

Make sure `foxess-config.json` is in the same folder as the script.

### Log file does not write

Make sure the folder in `LogPath` exists.

Also make sure the Windows account running Task Scheduler has permission to write to that folder.

### No notification received

Check that `NtfyUrl` is correct.

Make sure your phone is subscribed to the same ntfy topic.

### Weather category looks wrong

Check:

- Latitude
- Longitude
- Timezone
- SolarAssessment start and end hours

### FoxESS push fails

Check:

- API key
- Device serial number
- BaseUrl
- Internet connection
- FoxESS cloud availability

### Schedule looks different than expected

Remember that the script replaces the active scheduler with only the templates selected for that day. Old schedule groups are not preserved.
