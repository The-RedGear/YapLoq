$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'test_global_save_ui.ps1')
$script:liveValidGroups=@{}
$credential=$script:credentialFields['ElevenLabsApiKeyBox']
$credential.Mask.Password='live-visibility-fixture';Update-GlobalSaveGroup 'ElevenLabs'
Get-LiveSettingsDraft|Out-Null
if(-not $credential.Toggle.IsEnabled -or $credential.Mask.Password -ne 'live-visibility-fixture'){throw 'Live validation disabled visibility or cleared a credential'}
$credential.Toggle.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
Get-LiveSettingsDraft|Out-Null
if($credential.Toggle.Content -ne 'Hide' -or $credential.Plain.Text -ne 'live-visibility-fixture' -or -not $credential.Toggle.IsEnabled){throw 'Live validation broke a revealed credential'}
Hide-YapLoqCredential $credential
Sync-YapLoqCredentialFields @('ElevenLabsApiKeyBox')
$script:liveValidGroups=@{}
foreach($group in $script:globalSaveGroups.Values){Reset-GlobalSaveGroup $group.Key}
$before=[IO.File]::ReadAllText($configPath)
$MaxQueueSettingBox.Text='46';Update-GlobalSaveGroup 'Settings'
$draft=Get-LiveSettingsDraft
if($draft.max_queue -ne 46 -or [IO.File]::ReadAllText($configPath) -ne $before){throw 'Live validation did not stage settings without persistence'}
$MaxQueueSettingBox.Text='0';Update-GlobalSaveGroup 'Settings'
$draft=Get-LiveSettingsDraft
if($draft.max_queue -ne 46 -or $MaxQueueSettingBox.Text -ne '0'){throw 'Invalid edit lost the last valid live value or current draft'}
$script:splitSpeechSentences.IsChecked=$true;Update-GlobalSaveGroup 'Speech input'
$draft=Get-LiveSettingsDraft
if(-not $draft.split_speech_sentences){throw 'Speech settings did not apply live'}
$script:liveSettingsDebounce=[Windows.Threading.DispatcherTimer]::new()
$script:liveSettingsPump=[Windows.Threading.DispatcherTimer]::new()
function Show-AppConfirmation($owner,$message,$title){return $true}
Discard-PendingSettings
$script:liveSettingsPump.Stop()
if([IO.File]::ReadAllText($configPath) -ne $before -or $MaxQueueSettingBox.Text -ne [string](Read-Settings).max_queue -or $script:splitSpeechSentences.IsChecked -ne ((Read-Settings).split_speech_sentences -eq $true)){throw 'Discard did not restore saved UI values without persistence'}
if($script:liveSettingsPending -ne '{"reset":true}'){throw 'Discard did not schedule reset after in-flight apply'}
if(@($script:globalSaveGroups.Values|Where-Object{$_.Dirty}).Count){throw 'Discard left stale dirty markers'}
function New-LiveSettingsClient {
    $client=[pscustomobject]@{Proxy=$null;Encoding=$null;Headers=@{}}
    $client|Add-Member ScriptMethod Dispose {}
    $client|Add-Member ScriptMethod UploadStringTaskAsync {
        param($uri,$method,$payload)
        $script:liveTestPayload=$payload|ConvertFrom-Json
        $completion=[Threading.Tasks.TaskCompletionSource[string]]::new()
        $completion.SetResult('{"ok":true,"result":{"active":true,"restartRequired":[],"saveRequired":[]}}')
        return $completion.Task
    }
    return $client
}
Install-LiveSettings
$MaxQueueSettingBox.Text='47';Update-GlobalSaveGroup 'Settings'
$deadline=[DateTime]::UtcNow.AddSeconds(12)
while([DateTime]::UtcNow -lt $deadline -and -not $script:liveSettingsReady){$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background);Start-Sleep -Milliseconds 20}
if(-not $script:liveSettingsReady -or $script:liveTestPayload.settings.max_queue -ne 47 -or [IO.File]::ReadAllText($configPath) -ne $before){throw ('Debounced asynchronous live application failed: ready='+$script:liveSettingsReady+' max='+$script:liveTestPayload.settings.max_queue+' status='+$BottomStatus.Text+' debounce='+$script:liveSettingsDebounce.IsEnabled+' pump='+$script:liveSettingsPump.IsEnabled+' task='+$script:liveSettingsTask)}
Save-AllPendingChanges
$deadline=[DateTime]::UtcNow.AddSeconds(8)
while([DateTime]::UtcNow -lt $deadline -and -not $script:liveTestPayload.reset){$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background);Start-Sleep -Milliseconds 20}
if((Read-Settings).max_queue -ne 47 -or -not $script:liveTestPayload.reset){throw 'Save did not persist the active draft and serialize runtime reset'}
$script:liveSettingsDebounce.Stop();$script:liveSettingsPump.Stop();$script:liveSettingsInstalled=$false
$VoiceRuleFieldBox.SelectedIndex=0;$VoiceRuleValueBox.Text='moderator';$VoiceRuleAliasBox.SelectedItem='EventVoice'
Upsert-VoiceRule
Update-GlobalSaveGroup 'Rules'
$draft=Get-LiveSettingsDraft
if($draft.role_voice_rules.moderator -ne 'EventVoice'){throw 'Role editor did not reach the live settings draft'}
$tip=[Windows.Controls.ToolTip]::new();$tip.Content='Role rule help';$tip.Style=$window.FindResource([Windows.Controls.ToolTip]);$tip.ApplyTemplate()|Out-Null;$tip.Measure([Windows.Size]::new(360,100))
'Live settings UI passed: staged validation, invalid draft retention, sentence option and Discard.'
