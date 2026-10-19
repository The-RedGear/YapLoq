$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'test_yaploq_shell.ps1')
foreach($group in $script:globalSaveGroups.Values){Reset-GlobalSaveGroup $group.Key}
foreach($credential in $script:credentialFields.Values){
    $original=$credential.Mask.Password
    $credential.Syncing=$true;$credential.Mask.Password='visibility-fixture';$credential.Syncing=$false;Hide-YapLoqCredential $credential
    foreach($group in $script:globalSaveGroups.Values){Reset-GlobalSaveGroup $group.Key}
    foreach($cycle in 1..3){
        $credential.Toggle.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        foreach($group in $script:globalSaveGroups.Values){Update-GlobalSaveGroup $group.Key}
        if(@($script:globalSaveGroups.Values|Where-Object{$_.Dirty}).Count){throw 'Showing or hiding a credential marked settings dirty'}
        if($credential.Mask.Password -ne 'visibility-fixture'){throw 'Visibility toggle changed the credential value'}
    }
    Hide-YapLoqCredential $credential
    $credential.Syncing=$true;$credential.Mask.Password=$original;$credential.Syncing=$false
}
foreach($group in $script:globalSaveGroups.Values){Reset-GlobalSaveGroup $group.Key}
if($script:globalSaveGroups.Settings.Inputs.Count -lt 15){throw 'Settings tracking missed its editable controls'}
if($script:globalSaveGroups.ElevenLabs.Inputs.Count -lt 2){throw 'Credential tracking missed its masked/plain inputs'}
if($script:globalSaveGroups.Rules.Inputs.Count -lt 10 -or $script:globalSaveGroups.Actions.Inputs.Count -lt 5){throw 'Rule/action tracking missed editable controls'}
if(-not $script:globalSaveButton.IsEnabled -or $script:globalSaveButton.Effect){throw 'Clean Save should be clickable without a glow'}
$cleanBefore=[IO.File]::ReadAllText($configPath)
Save-AllPendingChanges
if($BottomStatus.Text -ne 'All changes saved.' -or [IO.File]::ReadAllText($configPath) -ne $cleanBefore){throw 'Clean Save did not acknowledge without unnecessary writes'}
if($script:globalSaveFeedback.Text -ne 'All changes saved' -or $script:globalSaveFeedback.Visibility -ne 'Visible'){throw 'Clean Save did not show title-bar feedback'}
$parent=$BridgeStatusButton.Parent
if($parent.Children.IndexOf($script:globalSaveButton) -ne $parent.Children.IndexOf($BridgeStatusButton)-1){throw 'Global Save is not left of service status'}
if($parent.Children.IndexOf($script:globalSaveFeedback) -ne $parent.Children.IndexOf($script:globalSaveButton)-1){throw 'Save feedback is not left of Save'}
$MaxQueueSettingBox.Text='44'
$ElevenLabsEnabledCheck.IsChecked=-not [bool]$ElevenLabsEnabledCheck.IsChecked
Update-GlobalSaveGroup 'Settings';Update-GlobalSaveGroup 'ElevenLabs'
if($script:globalSaveLabel.Text -ne 'Save' -or -not $script:globalSaveButton.Effect -or $script:globalSaveButton.Style -ne $window.FindResource('PrimaryButton')){throw 'Pending edits should show a purple glowing Save without an asterisk'}
Set-Page 'settings';Set-Page 'rules'
if($MaxQueueSettingBox.Text -ne '44'){throw 'Navigating away discarded a pending settings edit'}
Refresh-Grid
if($MaxQueueSettingBox.Text -ne '44' -or -not $script:globalSaveGroups.Settings.Dirty){throw 'Background refresh discarded a pending settings edit'}
if(-not $script:globalSaveGroups.Settings.Dirty -or -not $script:globalSaveGroups.ElevenLabs.Dirty){throw 'Cross-page edits were not tracked'}
Save-AllPendingChanges
$saved=Read-Settings
if($saved.max_queue -ne 44 -or $saved.elevenlabs_enabled -ne [bool]$ElevenLabsEnabledCheck.IsChecked){throw ('Global save lost edits: '+$BottomStatus.Text)}
if(-not $script:globalSaveButton.IsEnabled -or $script:globalSaveButton.Effect){throw ('Successful save should stay clickable and clear its glow: '+$script:globalSaveButton.ToolTip)}
if($script:globalSaveFeedback.Text -ne 'Saved'){throw 'Successful save did not report success'}
$before=[IO.File]::ReadAllText($configPath)
$MaxQueueSettingBox.Text='0';$ElevenLabsEnabledCheck.IsChecked=-not [bool]$ElevenLabsEnabledCheck.IsChecked
Update-GlobalSaveGroup 'Settings';Update-GlobalSaveGroup 'ElevenLabs'
Save-AllPendingChanges
if([IO.File]::ReadAllText($configPath) -ne $before){throw 'Validation failure partially wrote settings'}
if($BottomStatus.Text -notlike 'Not saved - Settings:*' -or -not $script:globalSaveButton.IsEnabled){throw 'Failed section did not stay visibly pending'}
if($script:globalSaveFeedback.Text -notlike 'Not saved - Settings:*' -or $script:globalSaveFeedback.Visibility -ne 'Visible'){throw 'Failed Save did not show its reason by the button'}
$MaxQueueSettingBox.Text='44';$ElevenLabsEnabledCheck.IsChecked=[bool]$saved.elevenlabs_enabled
Update-GlobalSaveGroup 'Settings';Update-GlobalSaveGroup 'ElevenLabs'
if(-not $script:globalSaveButton.IsEnabled -or $script:globalSaveButton.Effect){throw 'Reverting pending changes should clear the glow and stay clickable'}
$script:validationCalls=0;$script:backupCalls=0
function Invoke-BridgePost([string]$path,$body=@{}){
    if($path -eq '/api/maintenance/validate-actions'){$script:validationCalls++;if(-not $body.rules[0].name){throw 'Give every action a name'};return [pscustomobject]@{result=[pscustomobject]@{rules=@($body.rules)}}}
    if($path -eq '/api/maintenance/backup'){$script:backupCalls++;return [pscustomobject]@{result=[pscustomobject]@{path='fixture.zip'}}}
    throw 'Unexpected write during staged save'
}
$script:automationSelected=$null
foreach($group in $script:globalSaveGroups.Values){Reset-GlobalSaveGroup $group.Key}
$script:automationRules=@([pscustomobject]@{id='global-fixture';name='Global saved action';enabled=$true;triggers=@([pscustomobject]@{source='viewer';event='voiceassigned'});conditions=@();steps=@();onError='stop'})
Update-GlobalSaveGroup 'Actions';Save-AllPendingChanges
$savedActions=Read-Settings
if($savedActions.automations[0].name -ne 'Global saved action' -or -not $savedActions.automations_migrated -or $script:validationCalls -ne 1 -or $script:backupCalls -ne 1){throw ('Global action save failed validation/migration/backup: '+$BottomStatus.Text)}
$before=[IO.File]::ReadAllText($configPath)
$script:automationRules[0].name='';$MaxQueueSettingBox.Text='45'
Update-GlobalSaveGroup 'Actions';Update-GlobalSaveGroup 'Settings';Save-AllPendingChanges
if([IO.File]::ReadAllText($configPath) -ne $before -or $BottomStatus.Text -notlike 'Not saved - Actions:*'){throw 'Action validation failure partially committed other settings'}
$script:globalSaveFeedbackTimer.Interval=[TimeSpan]::FromMilliseconds(20)
Show-SaveFeedback 'Feedback timeout test'
$deadline=[DateTime]::UtcNow.AddSeconds(3)
while($script:globalSaveFeedback.Visibility -eq 'Visible' -and [DateTime]::UtcNow -lt $deadline){$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background);Start-Sleep -Milliseconds 10}
if($script:globalSaveFeedback.Visibility -ne 'Collapsed'){throw 'Save feedback did not disappear'}
'Global Save passed: title position, cross-page edits, validation atomicity, revert and clean state.'
