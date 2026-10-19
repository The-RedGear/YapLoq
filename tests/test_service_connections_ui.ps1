$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'test_viewers_ui.ps1')
$script:loadingSettings=$false
$PollyEnabledCheck.IsChecked=$true
$PollyProfileBox.Text=''
$PollyRegionBox.Text='us-east-1'
$script:credentialFields.PollyAccessKeyBox.Mask.Password=''
$script:credentialFields.PollySecretKeyBox.Mask.Password=''
Update-ServiceConnectionForms
if($TestPollyButton.IsEnabled){throw 'Incomplete Polly credentials allow testing'}
$rows=Build-ServiceHealthRows $true @() @()
if(@($rows|Where-Object Id -eq 'polly')[0].State -ne 'bad'){throw 'Enabled service must appear offline'}
$script:credentialFields.PollyAccessKeyBox.Mask.Password='fixture-access'
if($TestPollyButton.IsEnabled){throw 'Polly accepts a missing secret'}
$script:credentialFields.PollySecretKeyBox.Mask.Password='fixture-secret'
if(-not $TestPollyButton.IsEnabled){throw 'Complete Polly credentials did not enable testing'}
Start-ServiceConnectionChecks
if(@((Build-ServiceHealthRows $true @() @())|Where-Object Id -eq 'polly')[0].State -ne 'warn' -or $TestPollyButton.IsEnabled){throw 'Connecting state is not yellow/busy'}
Complete-ServiceConnectionChecks @([pscustomobject]@{provider='polly'}) @()
if(@((Build-ServiceHealthRows $true @([pscustomobject]@{provider='polly'}) @())|Where-Object Id -eq 'polly')[0].State -ne 'ok'){throw 'Successful connection is not green'}
$entry=$script:credentialFields.PollySecretKeyBox
$entry.Toggle.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
if($script:serviceForms.polly.State -ne 'connected'){throw 'Show/hide reset the service connection'}
$entry.Plain.Text='changed-secret'
if($script:serviceForms.polly.State -ne 'offline'){throw 'Credential edit kept stale green status'}
Start-ServiceConnectionChecks
$entry.Plain.Text='newer-secret'
Complete-ServiceConnectionChecks @([pscustomobject]@{provider='polly'}) @()
if($script:serviceForms.polly.State -ne 'offline'){throw 'Stale connection result overwrote newer credentials'}
Start-ServiceConnectionChecks
Complete-ServiceConnectionChecks @([pscustomobject]@{provider='polly'}) @('Amazon Polly: rejected')
if($script:serviceForms.polly.State -ne 'offline'){throw 'Failed credentials appear connected'}
$beforeRows=@(Build-ServiceHealthRows $true @() @())
Complete-VoiceRefresh ([pscustomobject]@{voices=@();errors=@('Amazon Polly: connection refused')})
$afterRows=@(Build-ServiceHealthRows $true @() @('Amazon Polly: connection refused'))
if($beforeRows.Count -ne $afterRows.Count -or @($afterRows|Where-Object Id -eq 'polly').Count -ne 1){throw 'Failed test removed an enabled service from the denominator'}
$entry.Mask.Password='';Hide-YapLoqCredential $entry
if($entry.Mask.Resources['CredentialPlaceholder'].Visibility -ne 'Visible'){throw 'Empty password has no placeholder'}
$PollyProfileBox.Text='local-profile';$script:credentialFields.PollyAccessKeyBox.Mask.Password=''
if(-not $TestPollyButton.IsEnabled){throw 'AWS profile alternative is blocked'}
$GoogleEnabledCheck.IsChecked=$true;$GoogleServiceAccountBox.Text='C:\fixture\account.json';Update-ServiceConnectionForms
if(-not $TestGoogleButton.IsEnabled){throw 'Google service-account alternative is blocked'}
'Service connections passed: readiness, placeholders, offline/connecting/connected, failures, edits and stale results.'
