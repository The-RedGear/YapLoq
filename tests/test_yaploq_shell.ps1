param([string]$OutputDirectory = '',[switch]$KeepWindowOpen)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Xaml,System.Windows.Forms,System.Drawing,System.Security
$appRoot = Split-Path -Parent $PSScriptRoot
$resourceRoot = $appRoot
$configDir = Join-Path $appRoot ('data/ui-test-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($configDir)
$configPath = Join-Path $configDir 'settings.json'
$logPath = Join-Path $configDir 'bridge.log'
$legacyConfigDir = Join-Path $configDir 'no-legacy'
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $appRoot 'YapLoq.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach($definition in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$true)) { Invoke-Expression $definition.Extent.Text }
Initialize-RoundedChrome
$window=Load-Xaml (Join-Path $appRoot 'YapLoq.xaml')
[xml]$markup=Get-Content -LiteralPath (Join-Path $appRoot 'YapLoq.xaml') -Raw
foreach($node in $markup.SelectNodes('//*[@Name]')){Set-Variable -Name $node.GetAttribute('Name') -Value $window.FindName($node.GetAttribute('Name'))}
$script:profiles=@{}; $script:profileModels=@{}; $script:profileModelOptions=@{}; $script:servicesExpanded=$true; $script:loadingSettings=$false
Apply-AppFont $window
. (Join-Path $resourceRoot 'assets/RuleEditors.ps1')
Install-NumericEditors
Install-ProfanityEditor
Refresh-Grid
Install-ServiceGuides
$script:isPreview=$true
. (Join-Path $resourceRoot 'assets/YapLoqShell.ps1')
$window.FindName('SaveElevenLabsButton').Add_Click({Save-ElevenLabsSettings})
$window.FindName('ClearElevenLabsButton').Add_Click({Clear-ElevenLabsSecrets})
Install-YapLoqShell
$script:isPreview=$false;Set-YapLoqRuntimeControls
foreach($name in @('HttpBox','WsBox','PersistQueueCheck')){if(-not $window.FindName($name).IsEnabled){throw 'Released app retained a preview-only restriction'}}
$script:isPreview=$true;Set-YapLoqRuntimeControls
foreach($name in @('HttpBox','WsBox','PersistQueueCheck')){if($window.FindName($name).IsEnabled){throw 'Development preview lost its port/recovery isolation'}}
Update-YapLoqIntegrationStatus ([pscustomobject]@{state='listening';activePort=6670;received=30;accepted=12;rejected=18;processing=0;lastRejection='Speech queue is full (12 items)';test='passed'})
if($StreamerRequestCounts.Text -notlike '*30 received*12 accepted*18 rejected*' -or $StreamerRequestError.Visibility -ne 'Visible' -or $StreamerListenerTestResult.Text -notlike '*Local listener passed*'){throw 'Connection diagnostics lost request counts, rejection reason or local test result'}
if($script:credentialFields.Count -ne 13){throw 'Expected all service credentials and OBS password to have masking controls'}
if(@($window.FindName('SaveElevenLabsButton').Resources['YapLoqCredentialNames']) -notcontains 'ElevenLabsApiKeyBox' -or @($window.FindName('ClearPollyCredentialsButton').Resources['YapLoqCredentialNames']).Count -ne 3){throw 'Credential save/clear buttons lack masking refresh handlers'}
$credentialSettings=Read-Settings
foreach($entry in $script:credentialFields.Values){
    $fake='fixture-'+$entry.Original.Name
    Set-JsonProperty $credentialSettings $entry.Key $(if($entry.Encrypted){Protect-YapLoqSecret $fake}else{$fake})
}
Write-Settings $credentialSettings;Sync-YapLoqCredentialFields
foreach($entry in $script:credentialFields.Values){
    if($entry.Mask.Password -ne ('fixture-'+$entry.Original.Name) -or $entry.Plain.Visibility -ne 'Collapsed' -or $entry.Toggle.Content -ne 'Show'){throw 'Saved credential must load masked, not empty or revealed'}
    $entry.Toggle.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    if($entry.Plain.Text -ne $entry.Mask.Password -or $entry.Plain.Visibility -ne 'Visible'){throw 'Show credential toggle did not reveal its value'}
    $entry.Toggle.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    if($entry.Plain.Visibility -ne 'Collapsed' -or ($entry.Encrypted -and $entry.Plain.Text)){throw 'Hide credential toggle retained exposed plaintext'}
}
$eleven=$script:credentialFields['ElevenLabsApiKeyBox'];$eleven.Mask.Password='replacement-fixture'
$window.FindName('SaveElevenLabsButton').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
if((Unprotect-YapLoqSecret (Read-Settings).elevenlabs_api_key_encrypted) -ne 'replacement-fixture' -or $eleven.Mask.Password -ne 'replacement-fixture'){throw 'Saving credentials stored a mask or failed to restore masked display'}
$eleven.Toggle.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent));$eleven.Plain.Text='edited-revealed-fixture';Hide-YapLoqCredential $eleven
if($eleven.Mask.Password -ne 'edited-revealed-fixture'){throw 'Editing revealed text did not update the real credential'}
Sync-YapLoqCredentialFields @('ElevenLabsApiKeyBox') -PreserveEdits
if($eleven.Mask.Password -ne 'edited-revealed-fixture'){throw 'Failed-save synchronization discarded an unsaved credential'}
$window.FindName('ClearElevenLabsButton').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
if($eleven.Mask.Password -or (Read-Settings).elevenlabs_api_key_encrypted){throw 'Clear secrets did not clear the masked field'}
$credentialSettings=Read-Settings;Set-JsonProperty $credentialSettings 'azure_subscription_key_encrypted' 'unreadable-fixture';Write-Settings $credentialSettings
Sync-YapLoqCredentialFields @('AzureKeyBox')
$azure=$script:credentialFields['AzureKeyBox']
if($azure.Mask.Password -or $azure.Hint.Visibility -ne 'Visible' -or $azure.Toggle.IsEnabled){throw 'Unreadable credential must show a safe mask, not become an editable fake password'}
Save-AzureSettings
if((Read-Settings).azure_subscription_key_encrypted -ne 'unreadable-fixture'){throw 'Saving an unreadable credential replaced it with placeholder characters'}
if(($script:ownerSections.Queue | ForEach-Object {$_[1]}) -join ',' -ne 'queue,rules'){throw 'History still has a separate tab'}
if($script:unifiedQueueGrid.Parent.Parent -ne $QueuePage -or $script:unifiedQueueGrid.Columns.Count -ne 7){throw 'Queue needs one full-height table with shared columns and message expansion'}
if($script:unifiedQueueGrid.Items.Count -ne 0){throw 'Empty Queue should not contain section bars'}
if($PauseAfterQueueButton.Parent -ne $NowPlayingSkipButton.Parent){throw 'Pause after current must live in the media bar'}
foreach($table in @($QueueGrid,$HistoryGrid,$PlaylistGrid,$PronunciationGrid,$VoiceRulesGrid,$RoutingGrid,$script:profanityGrid,$EventTimelineGrid)){
    if(-not $table.ContextMenu -or $table.ContextMenu.Items.Count -lt 3){throw ('Missing useful context menu: '+$table.Name)}
}
$QueueGrid.SelectedItem=$null
$QueueGrid.ContextMenu.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.ContextMenu]::OpenedEvent))
if($QueueGrid.ContextMenu.Items[0].IsEnabled){throw 'Queue item commands enabled without a selected row'}
$menuProbe=New-QueueSpeechRow ([pscustomobject]@{id='menu-probe';alias='EventVoice';text='test';status='Waiting'})
$QueueGrid.ItemsSource=@($menuProbe);Update-YapLoqUnifiedQueue;$script:unifiedQueueGrid.SelectedItem=$menuProbe
$QueueUpButton.Add_Click({$script:contextAction='queue-up'})
$QueueGrid.ContextMenu.Items[1].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
if($script:contextAction -ne 'queue-up'){throw 'Queue context action did not delegate to the existing command'}
$colorVoice=[pscustomobject]@{Name='Mint voice';Provider='windows';VoiceId='test';Model='sapi';Speed=1;Volume=1;Color='#87C9AF';IconId='mdi:cat'}
Save-Alias $null $colorVoice
$PlayVoiceList.SelectedItem='Mint voice'
Update-YapLoqDashboardAppearance
if($script:dashboardEditor.BorderBrush.Color.ToString() -ne '#FF87C9AF' -or $script:dashboardVoicePicker.SelectedValue -ne 'Mint voice'){throw 'Composer tint or icon picker selection desynchronized'}
if($PlayButton.Background.GradientStops[1].Color.ToString() -ne '#FF87C9AF'){throw 'Speak button retained the global purple accent'}
if($PlaygroundText.CaretBrush.Color.ToString() -ne '#FF87C9AF'){throw 'Composer caret retained the global purple accent'}
if(([Windows.Markup.XamlWriter]::Save($script:dashboardVoicePicker.Style)) -match '(?i)B6A3FF'){throw 'Voice picker retained purple interaction states'}
if(([Windows.Markup.XamlWriter]::Save($script:dashboardVoicePicker.ItemContainerStyle)) -match '(?i)B6A3FF'){throw 'Dropdown items retained purple selection'}
if($window.FindResource('Accent').Color.ToString() -ne '#FFB6A3FF' -or $SaveVoicesButton.Background.GradientStops[1].Color.ToString() -ne '#FFB6A3FF'){throw 'Dashboard tint leaked into shared app controls'}
$AliasSearchBox.Text='no match';Filter-VoiceAliases
if($script:dashboardVoicePicker.Items.Count -ne 2){throw 'Voice search filtered the Dashboard picker'}
$AliasSearchBox.Text='';Filter-VoiceAliases
if (($script:yaploqNav.Keys | Sort-Object) -join ',' -ne 'AudioStims,Dashboard,Integrations,Queue,Services,Settings,Voices') { throw 'Expected seven navigation entries including Audio Stims' }
if ($VoicesNav.Parent) { throw 'Legacy navigation is still in the visible shell' }
if ($PlaylistGrid.Parent.Parent.Parent.Parent -eq $RulesPage.Content) { throw 'Playlist editor still belongs to message rules' }
if (-not $script:yaploqPages.playlists.Content.Children.Count) { throw 'Playlist editor was lost' }
foreach($name in @('AutoVoiceRulesExpander','RoutingExpander')){
    if($window.FindName($name).Parent.Parent -ne $script:assignmentSections.Rules.Content){throw 'Existing rules must live inside Assignments'}
}
if(-not @($script:ownerSections.Voices|Where-Object{$_[1] -eq 'assignments'}).Count -or @($script:ownerSections.Voices|Where-Object{$_[1] -in @('routing','viewers')}).Count){throw 'Assignments must replace the separate Routing and Viewers tabs'}
if($window.FindName('RoutingExpander').Header.Children[0].Tag -ne 'mdi:call-split'){throw 'Routing icon was not replaced'}
foreach($name in @('MessageModerationExpander','LimitsViewersExpander')){
    if($window.FindName($name).Parent.Parent -ne $RulesPage.Content){throw 'Filters and queue limits must remain in Queue rules'}
}
if ($PlayStopButton.Visibility -ne 'Collapsed') { throw 'Dashboard duplicates player stop' }
$setupRows=@($script:streamerQuickHelp.Child.Children | Where-Object {$_ -is [Windows.Controls.Grid]})
if($setupRows.Count -ne 3){throw 'Streamer.Bot help should contain three integration steps'}
$setupActions=@($setupRows | ForEach-Object {$_.Children[1]})
if(($setupActions.Tag -join ',') -ne 'connection,export,queue'){throw 'Streamer.Bot help points to unrelated onboarding pages'}
$setupCopy=($setupRows | ForEach-Object {$_.Children[0].Children[1].Text}) -join ' '
if($setupCopy -notlike '*Import String*' -or $setupCopy -notlike '*Test Trigger*' -or $setupCopy -notlike '*UDP*'){throw 'Streamer.Bot connection, import, or verification step missing'}
foreach($action in $setupActions){if(-not $action.Content.Children[0].Data){throw 'Streamer.Bot help action lacks an icon'}}
if ($PlayVoiceList.Items.Count -ne 2) { throw 'Dashboard lost voice selection' }
if ($HttpBox.IsEnabled -or -not $EnableUdpCheck.IsEnabled) { throw 'Preview must isolate desktop ports without blocking speech inputs' }
$orderProbe=@(
    [pscustomobject]@{Id='old-playing';Timestamp='2026-10-17T10:00:00Z';Status='Playing'},
    [pscustomobject]@{Id='new-queued';Timestamp='2026-10-17T10:00:02Z';Status='Queued'},
    [pscustomobject]@{Id='middle-finished';Timestamp='2026-10-17T10:00:01Z';Status='Finished'}
)
if((@(Sort-YapLoqSpeechRows $orderProbe).Id -join ',') -ne 'new-queued,middle-finished,old-playing'){throw 'Playing speech was promoted above newer admissions'}
$orderProbe[0].Status='Finished'
if((@(Sort-YapLoqSpeechRows $orderProbe).Id -join ',') -ne 'new-queued,middle-finished,old-playing'){throw 'Playback status changed chronological order'}
if ($window.FindName('SidebarBrandLogo').Visibility -ne 'Collapsed') { throw 'Sidebar logo is still visible' }
if ($BridgeStatusButton.Parent -ne $MinimizeButton.Parent -or $BridgeStatusButton.Parent.Children.IndexOf($BridgeStatusButton) -ne ($BridgeStatusButton.Parent.Children.IndexOf($MinimizeButton)-1)) { throw 'Status is not immediately before Minimize' }
$sample=[pscustomobject]@{queue=@([pscustomobject]@{id='one';alias='Windows';text='Test message'})}
Update-YapLoqDashboard $sample
if ($script:dashboardUpcoming.Children.Count -ne 1 -or $script:dashboardUpcoming.Children[0].Tag.Text -ne 'Test message') { throw 'Dashboard queue preview lost canonical state' }
$previewRow=$script:dashboardUpcoming.Children[0]
Update-YapLoqDashboard $sample
if(-not [object]::ReferenceEquals($previewRow,$script:dashboardUpcoming.Children[0]) -or $script:dashboardUpcoming.HasAnimatedProperties){throw 'Unchanged Dashboard queue preview was rebuilt or animated again'}
Update-YapLoqDashboard ([pscustomobject]@{queue=@()})
if ($script:dashboardUpcoming.Children[0].Text -ne 'No speech yet') { throw 'Compact empty queue hint missing' }
$script:recentHistoryItems=@([pscustomobject]@{Id='replayed';Alias='EventVoice';Text='Replay me';HasAudio=$true})
Update-YapLoqDashboard ([pscustomobject]@{queue=@()})
if ($script:dashboardUpcoming.Children[0].Tag.Id -ne 'replayed' -or $script:dashboardActivityLink.Tag -ne 'queue') { throw 'Compact preview lost recent speech or the unified Queue link' }
$recentPreview=$script:dashboardUpcoming.Children[0]
Update-YapLoqDashboard ([pscustomobject]@{queue=@()})
if(-not [object]::ReferenceEquals($recentPreview,$script:dashboardUpcoming.Children[0])){throw 'Unchanged recent preview rebuilt its rows'}
$active=[pscustomobject]@{current=[pscustomobject]@{id='active';alias='Mint voice';text='Speaking now';status='Playing'};queue=@();paused=$false}
Update-YapLoqDashboard $active
if($script:dashboardUpcoming.Children[0].Tag.Status -ne 'Playing' -or $script:dashboardUpcoming.Children[1].Tag.Id -ne 'replayed'){throw 'Dashboard preview must put active speech before recent history'}
$completed=[pscustomobject]@{id='active';timestamp='2099-01-01T00:00:00Z';alias='Mint voice';text='Speaking now';status='Playing';source='Manual';audioPath='active.wav'}
Update-YapLoqDashboard ([pscustomobject]@{current=$null;lastPlayed=$completed;queue=@();paused=$false})
if($script:dashboardUpcoming.Children[0].Tag.Id -ne 'active' -or $script:dashboardUpcoming.Children[0].Tag.Status -ne 'Finished'){throw 'Just-finished Dashboard speech disappeared while history was catching up'}
$script:recentHistoryItems=@([pscustomobject]@{Id='active';Timestamp='2099-01-01T00:00:00Z';Alias='Mint voice';Text='Speaking now';Status='Finished';HasAudio=$true},[pscustomobject]@{Id='replayed';Timestamp='2026-01-01T00:00:00Z';Alias='EventVoice';Text='Replay me';Status='Finished';HasAudio=$true})
Update-YapLoqDashboard ([pscustomobject]@{current=$null;lastPlayed=$completed;queue=@();paused=$false})
if($script:dashboardUpcoming.Children[0].Tag.Id -ne 'active' -or @($script:dashboardUpcoming.Children|Where-Object{$_.Tag.Id -eq 'active'}).Count -ne 1){throw 'History catch-up moved or duplicated the newest Dashboard speech'}
foreach($name in @('AudioSettingsExpander','LocalApiSettingsExpander','LimitsSettingsExpander','WindowSettingsExpander','DataSupportSettingsExpander')) {
    if($window.FindName($name).Header.Children[0] -isnot [Windows.Shapes.Path]){throw ('Settings section lacks icon: '+$name)}
}
$PlayVoiceList.SelectedIndex=0
Update-YapLoqDashboardAppearance
if($script:dashboardVoicePicker.SelectedValue -ne $PlayVoiceList.SelectedItem -or -not $script:dashboardVoicePicker.ItemTemplate){throw 'Dashboard icon picker lost canonical selection'}
$played=[pscustomobject]@{id='replayed';alias='EventVoice';text='Replay me'}
Update-NowPlayingBar ([pscustomobject]@{current=$null;lastPlayed=$played;paused=$false;queueLength=0}) ([pscustomobject]@{Id='newer';Alias='Other';Text='Not played'})
if($NowPlayingTitle.Text -ne 'EventVoice' -or (Get-HistoryPlaybackTarget).id -ne 'replayed'){throw 'Player snapped back from the last replay'}
function Invoke-BridgePost([string]$path,$body=@{}) { $script:recordedRequest=$path;$script:recordedBody=$body }
$script:recentHistoryItems=@(1..9|ForEach-Object{[pscustomobject]@{Id=('preview-'+$_);Alias='Mint voice';Text=('Recent speech '+$_);Status='Finished';HasAudio=$true}})
Update-YapLoqDashboard ([pscustomobject]@{queue=@()})
if($script:dashboardUpcoming.Children.Count -ne 6){throw 'Dashboard should show six preview rows when history is available'}
$previewHistory=$script:dashboardUpcoming.Children[0]
if($previewHistory.ContextMenu.Items.Count -ne 6){throw 'Dashboard history row lacks useful context actions'}
$previewReplay=@($previewHistory.Children|Where-Object{$_ -is [Windows.Controls.Button]})[0]
if(-not $previewReplay){throw 'Dashboard history row lacks a replay icon button'}
if($previewReplay.Content.Fill.Color.ToString() -ne '#FFB6A3FF'){throw 'Replay icon must use default purple, not the alias accent'}
$previewReplay.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
if($script:recordedRequest -ne '/api/history/replay' -or $script:recordedBody.speechId -ne 'preview-1'){throw 'Dashboard replay did not use its own recording ID'}
$previewHistory.ContextMenu.Items[1].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
if($script:recordedRequest -ne '/api/history/save' -or $script:recordedBody.speechId -ne 'preview-1'){throw 'Dashboard context save did not use its own recording ID'}
Update-YapLoqDashboard ([pscustomobject]@{queue=@()})
if(-not[object]::ReferenceEquals($previewHistory,$script:dashboardUpcoming.Children[0])){throw 'Expanded history preview rebuilt unchanged rows'}
$script:recentHistoryItems[3]|Add-Member NoteProperty AudioPath 'preview-four.wav' -Force
$previewOrder=($script:dashboardUpcoming.Children.Tag.Id) -join ','
foreach($status in @('Queued','Playing','Paused')){
    Update-YapLoqDashboard ([pscustomobject]@{current=[pscustomobject]@{id='dashboard-replay';alias='Mint voice';text='Recent speech 4';status=$status;source='History recording';audioPath='preview-four.wav'};queue=@()})
    if(($script:dashboardUpcoming.Children.Tag.Id -join ',') -ne $previewOrder -or $script:dashboardUpcoming.Children[3].Tag.Status -ne $status){throw 'Dashboard replay moved or duplicated the original recording instead of updating its status'}
}
Update-YapLoqDashboard ([pscustomobject]@{queue=@()})
if($script:dashboardUpcoming.Children[3].Tag.Status -ne 'Finished'){throw 'Dashboard replay did not return to Finished'}
$PauseAfterQueueButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
if($script:recordedRequest -ne '/pause-after-current'){throw 'Media-bar pause-after-current is not wired to the backend'}
$script:lastPlaybackState=[pscustomobject]@{pauseAfterCurrent=$true}
$PauseAfterQueueButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
if($script:recordedRequest -ne '/resume'){throw 'Media-bar pause-after-current cannot be turned off'}
$historyProbe=New-QueueSpeechRow ([pscustomobject]@{id='history-probe';alias='Mint voice';text='past';status='Finished'})
$historyProbe|Add-Member NoteProperty HasAudio $true
$HistoryGrid.ItemsSource=@($historyProbe);Update-YapLoqUnifiedQueue;$script:unifiedQueueGrid.SelectedItem=@($script:unifiedQueueGrid.Items|Where-Object{$_.Id -eq $historyProbe.Id})[0]
if($HistoryGrid.SelectedItem.Id -ne 'history-probe' -or $QueueGrid.SelectedItem -or $ReplayHistoryButton.Visibility -ne 'Visible' -or $RemoveQueueButton.Visibility -ne 'Collapsed'){throw 'History selection exposes queue controls or lost its audio commands'}
# Reproduce a refresh that replaces canonical row objects without changing values.
$freshHistory=$historyProbe|Select-Object *
$HistoryGrid.ItemsSource=@($freshHistory);Update-YapLoqUnifiedQueue
if(-not[object]::ReferenceEquals($HistoryGrid.SelectedItem,$freshHistory)){throw 'History selection was not resolved by ID after refresh'}
$ReplayHistoryButton.Add_Click({Replay-SelectedHistory})
$ReplayHistoryButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
if($script:recordedRequest -ne '/api/history/replay' -or $script:recordedBody.speechId -ne 'history-probe'){throw 'Replay selected did not request the visible recording after refresh'}
$script:lastPlaybackState=[pscustomobject]@{current=$null};$script:lastHistorySpeechId='history-probe'
$script:mediaSaveAudioButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
if($script:recordedRequest -ne '/api/history/save' -or $script:recordedBody.speechId -ne 'history-probe'){throw 'Media-bar save did not save the displayed recording'}
$transport=$NowPlayingSkipButton.Parent
if($transport.Children.IndexOf($script:mediaSaveAudioButton) -ne 0 -or $transport.Children.IndexOf($PauseAfterQueueButton) -ne 4 -or $transport.Children.IndexOf($NowPlayingPlayPauseButton) -ne 2){throw 'Media controls are not symmetric around Play'}
if($PauseAfterQueueButton.BorderThickness.Left -ne 0 -or $script:mediaSaveAudioButton.BorderThickness.Left -ne 0){throw 'Auxiliary transport controls still have boxes'}
if($PauseAfterQueueButton.Content.Tag -ne 'mdi:stop' -or $PauseAfterQueueButton.Content.Width -ne 12 -or $script:mediaSaveAudioButton.Content.Width -ne 12 -or $PauseAfterQueueButton.Content.Height -ne $script:mediaSaveAudioButton.Content.Height){throw 'Auxiliary transport icons must be 12px with a stop glyph for pause-after-current'}
$script:unifiedQueueGrid.ContextMenu.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.ContextMenu]::OpenedEvent))
foreach($item in $script:unifiedQueueGrid.ContextMenu.Items|Where-Object{$_.Tag.Command -in @('QueueUpButton','QueueDownButton')}){
    if($item.Visibility -ne 'Visible' -or $item.IsEnabled){throw 'History must show disabled move commands, not hide them or reorder past speech'}
}
$script:unifiedQueueGrid.SelectedItem=$menuProbe
if($QueueGrid.SelectedItem.Id -ne 'menu-probe' -or $HistoryGrid.SelectedItem -or $ReplayHistoryButton.Visibility -ne 'Collapsed' -or $RemoveQueueButton.Visibility -ne 'Visible'){throw 'Live selection exposes replay controls or lost its queue commands'}
$QueueGrid.ItemsSource=@();Update-YapLoqUnifiedQueue
$stableCollection=$script:unifiedQueueGrid.ItemsSource
if(-not @($stableCollection|Where-Object{$_.Id -eq 'menu-probe' -and $_.Status -eq 'Finished'}).Count){throw 'Live/history handoff removed the finishing row'}
Update-YapLoqUnifiedQueue
if(-not [object]::ReferenceEquals($stableCollection,$script:unifiedQueueGrid.ItemsSource)){throw 'Queue poll replaced the table collection'}
$handoffProbe=@($stableCollection|Where-Object{$_.Id -eq 'menu-probe'})[0]
if(-not $handoffProbe){throw 'Repeated polls lost a row before history caught up'}
$HistoryGrid.ItemsSource=@($freshHistory,($handoffProbe|Select-Object * -ExcludeProperty PendingHistory))
Update-YapLoqUnifiedQueue
$HistoryGrid.ItemsSource=@($freshHistory);Update-YapLoqUnifiedQueue
if($script:unifiedQueueGrid.Items.Count -ne 1 -or $script:unifiedQueueGrid.Items[0].RowKind -ne 'History'){throw 'Empty queue reserved space or hid history'}
$freshHistory.AudioPath='cache-replay.wav';$freshHistory.Source='Test'
$newer=New-QueueSpeechRow ([pscustomobject]@{id='newer-recording';alias='Mint voice';text='Newer';status='Finished'})
$HistoryGrid.ItemsSource=@($newer,$freshHistory)
foreach($status in @('Queued','Playing','Paused')){
    $replayJob=New-QueueSpeechRow ([pscustomobject]@{id='replay-job';alias='Mint voice';text='past';status=$status;source='History recording';audioPath='cache-replay.wav'})
    $QueueGrid.ItemsSource=@($replayJob);Update-YapLoqUnifiedQueue
    if($script:unifiedQueueGrid.Items.Count -ne 2 -or $script:unifiedQueueGrid.Items[1].Id -ne 'history-probe' -or $script:unifiedQueueGrid.Items[1].Status -ne $status -or $script:unifiedQueueGrid.Items[1].Source -ne 'Test'){throw 'Replay must update the original recording in place without duplicating or moving it'}
    if($freshHistory.Status -ne 'Finished'){throw 'Replay projection modified stored history status'}
}
$QueueGrid.ItemsSource=@();Update-YapLoqUnifiedQueue
if($script:unifiedQueueGrid.Items[1].Status -ne 'Finished'){throw 'Replay row did not return to Finished'}
Open-YapLoqRoute 'emergency-stop'
if ($script:recordedRequest -ne '/clear-all') { throw 'Emergency stop is not wired to the real queue endpoint' }
$script:yaploqNav.Voices.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ContextIdle)
if ($script:activePage -ne 'voices') { throw 'Sidebar click is not wired to navigation' }
$window.WindowStartupLocation='Manual';$window.Left=-20000;$window.Top=-20000
$window.ShowInTaskbar=$false;$window.ShowActivated=$false
$window.Show()
Set-Page 'acapela';$window.UpdateLayout()
$acapela=$script:credentialFields['AcapelaPasswordBox'];$acapela.Toggle.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
if($acapela.Plain.Visibility -ne 'Visible'){throw 'Show credential toggle did not reveal on a visible service page'}
Set-Page 'queue';$window.UpdateLayout()
if($acapela.Plain.Visibility -ne 'Collapsed' -or $acapela.Plain.Text){throw 'Leaving the service page must hide revealed credentials'}
Set-Page 'queue'
$generating=New-QueueSpeechRow ([pscustomobject]@{id='generating';alias='Mint voice';text='test';status='Generating'})
$QueueGrid.ItemsSource=@($generating);Update-YapLoqUnifiedQueue
$window.UpdateLayout();$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ContextIdle)
$cell=$script:unifiedQueueGrid.Columns[1].GetCellContent($generating);$cell.ApplyTemplate()|Out-Null
$spinner=$cell.ContentTemplate.FindName('GeneratingIcon',$cell)
if($spinner.Visibility -ne 'Visible' -or -not $spinner.Child.RenderTransform.HasAnimatedProperties -or $spinner.Child.Children[0].Stroke.Color.ToString() -ne '#FF87C9AF'){throw 'Generating row needs an animated alias-colored loading icon'}
$queued=New-QueueSpeechRow ([pscustomobject]@{id='queued';alias='Mint voice';text='test';status='Queued'})
$QueueGrid.ItemsSource=@($queued);Update-YapLoqUnifiedQueue
$window.UpdateLayout();$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ContextIdle)
$cell=$script:unifiedQueueGrid.Columns[1].GetCellContent($queued);$cell.ApplyTemplate()|Out-Null
if($cell.ContentTemplate.FindName('GeneratingIcon',$cell).Visibility -ne 'Collapsed' -or $cell.ContentTemplate.FindName('AliasIcon',$cell).Visibility -ne 'Visible'){throw 'Queue row did not restore its alias icon after generation'}
Set-Page 'history'
if($script:activePage -ne 'queue' -or -not $script:unifiedQueueGrid.IsVisible){throw 'History shortcut must open the shared Queue view'}
Install-UiErrorHandling
[void]$window.Dispatcher.BeginInvoke([action]{ throw [InvalidOperationException]::new('Injected UI callback failure') })
$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ContextIdle)
if (-not (Test-Path -LiteralPath (Join-Path $configDir 'ui-crashes.log'))) { throw 'UI callback failure was not recorded' }
if((Get-Content -LiteralPath (Join-Path $configDir 'ui-crashes.log') -Raw) -notlike '*Injected UI callback failure*'){throw 'Crash log omitted the callback exception'}
if (-not $window.IsVisible) { throw 'Recoverable UI callback failure closed the window' }
$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ContextIdle)
Set-Page 'services'; Set-Page 'polly'
if ([Windows.SystemParameters]::ClientAreaAnimation -and -not $script:headerControls.HasAnimatedProperties) { throw 'Persistent service menu missed the page animation' }
if (-not $script:servicePicker.Resources.Contains('YapLoqMotionInstalled')) { throw 'Service dropdown motion was not registered' }
$window.UpdateLayout();$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ContextIdle)
$script:servicePicker.IsDropDownOpen = $true
$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ContextIdle)
$popup = $script:servicePicker.Template.FindName('PART_Popup',$script:servicePicker)
if ([Windows.SystemParameters]::ClientAreaAnimation -and -not $popup.Child.HasAnimatedProperties) { throw 'Dropdown contents missed entrance animation' }
$script:servicePicker.IsDropDownOpen = $false
foreach ($width in @(980,1180,1600)) {
    $window.Width = $width
    foreach ($collapsed in @($false,$true)) {
        Set-YapLoqSidebarCollapsed $collapsed $false
        $window.UpdateLayout();$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ContextIdle)
        $grid = $NowPlayingBar.Child
        foreach ($element in @($NowPlayingProgressTrack,$NowPlayingPlayPauseButton.Parent)) {
            $center = $element.TranslatePoint([Windows.Point]::new($element.ActualWidth/2,0),$grid).X
            if ([Math]::Abs($center-$grid.ActualWidth/2) -gt 1) { throw "Player is off center at $width (collapsed=$collapsed)" }
        }
        foreach ($utility in $NowPlayingHistoryButton.Parent.Children) {
            $point=$utility.TranslatePoint([Windows.Point]::new(0,0),$grid)
            if ($point.X+$utility.ActualWidth -gt $grid.ActualWidth+1) { throw 'Player utility overflow' }
        }
    }
}
Set-YapLoqSidebarCollapsed $false $false
if ($OutputDirectory) { [void][IO.Directory]::CreateDirectory($OutputDirectory) }
foreach ($size in @(@(1180,760),@(980,640))) {
    $window.Width=$size[0];$window.Height=$size[1]
    foreach ($route in @('playground','voices','playlists','pronunciation','queue','history','rules','services','windowsService','voicestudio','polly','streamerbot','settings','activity')) {
        Set-Page $route
        $window.UpdateLayout()
        $window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ContextIdle)
        Start-Sleep -Milliseconds 220
        $window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ContextIdle)
        $expected=$script:routeOwners[$route]
        $expectedTitle=if($expected -eq 'Integrations'){'Streamer.Bot'}else{$expected}
        if ($PageTitle.Text -ne $expectedTitle) { throw "Wrong canonical owner for $route" }
        if ($route -eq 'playlists' -and -not $PlaylistGrid.IsVisible) { throw 'Playlist editor is not visible' }
        if (-not $NowPlayingBar.IsVisible) { throw "Player hidden on $route" }
        $expectedRoute=if($route -eq 'history'){'queue'}else{$route}
        if ($script:ownerLastPage[$expected] -ne $expectedRoute) { throw 'Page state not retained' }
        if ($OutputDirectory -and $route -in @('playground','voices','queue','services','streamerbot','settings')) {
            $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
            $bitmap.Render($window)
            $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
            $file=[IO.File]::Create((Join-Path $OutputDirectory ($route+'-'+$size[0]+'.png')))
            try{$encoder.Save($file)}finally{$file.Dispose()}
        }
    }
}
Set-Page 'playground'
$window.Width=980;$window.Height=640
$before=$script:shellContent.ActualWidth
$script:sidebarToggle.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
$window.UpdateLayout();$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ContextIdle)
if (-not $script:sidebarCollapsed -or $script:shellContent.ActualWidth -le $before) { throw 'Collapsing did not reclaim page space' }
foreach ($utility in $NowPlayingHistoryButton.Parent.Children) {
    $point=$utility.TranslatePoint([Windows.Point]::new(0,0),$NowPlayingBar)
    if ($point.X+$utility.ActualWidth -gt $NowPlayingBar.ActualWidth) { throw 'Player shortcuts were clipped after sidebar collapse' }
}
foreach ($button in $script:yaploqNav.Values) {
    if ($button.Content.Children[1].Visibility -ne 'Collapsed' -or -not $button.ToolTip) { throw 'Collapsed navigation lost icon-only labels/tooltips' }
}
if (-not (Get-Content -LiteralPath (Join-Path $configDir 'ui-state.json') -Raw | ConvertFrom-Json).sidebarCollapsed) { throw 'Sidebar preference was not saved' }
Show-ServiceStatusMenu $BridgeStatusButton
$window.UpdateLayout();$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ContextIdle)
Start-Sleep -Milliseconds 220
$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ContextIdle)
$window.UpdateLayout()
if ($ServiceStatusPopup.IsOpen -or $script:statusFlyout.Parent -ne $script:chromeRoot -or $script:statusFlyout.Visibility -ne 'Visible') { throw 'Status menu is not an in-app flyout' }
$position=$script:statusFlyout.TranslatePoint([Windows.Point]::new(0,0),$script:chromeRoot)
if ($position.Y -lt $AppTitleBar.ActualHeight -or $position.Y+$script:statusFlyout.ActualHeight -gt $script:chromeRoot.ActualHeight) { throw 'Status menu escaped the client area' }
if ($OutputDirectory) {
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($window)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $file=[IO.File]::Create((Join-Path $OutputDirectory 'collapsed-status-980.png'));try{$encoder.Save($file)}finally{$file.Dispose()}
}
Show-ServiceStatusMenu $BridgeStatusButton
if ($script:statusFlyout.Visibility -ne 'Collapsed') { throw 'Status button did not close the flyout' }
Set-YapLoqSidebarCollapsed $false
$window.UpdateLayout()
if ($script:sidebarColumn.Width.Value -ne 232 -or $script:yaploqNav.Dashboard.Content.Children[1].Visibility -ne 'Visible') { throw 'Expanded navigation did not restore page names' }
Set-Page 'history'; Open-YapLoqRoute 'owner:Voices'; Open-YapLoqRoute 'owner:Queue'
$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ContextIdle)
if ($script:activePage -ne 'queue') { throw 'Unified Queue view was not restored' }
Set-Page 'voiceRules'
if ($script:activePage -ne 'assignments' -or $script:assignmentSection -ne 'Rules') { throw 'Legacy voice rule shortcut did not open Assignments rules' }
Set-Page 'services'
$picker=$script:servicePicker
for ($cycle=0;$cycle -lt 12;$cycle++) {
    for ($index=1;$index -lt $picker.Items.Count;$index++) {
        $picker.SelectedIndex=$index
        $window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ContextIdle)
        if ($script:activePage -ne $picker.SelectedItem.Tag) { throw 'Dropdown navigation failed' }
        if (-not [object]::ReferenceEquals($picker,$script:servicePicker)) { throw 'Service dropdown was rebuilt during selection' }
        if ($script:serviceBack.Visibility -ne 'Visible') { throw 'Provider editor has no direct back action' }
    }
    Open-YapLoqRoute 'owner:Services'
    $window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ContextIdle)
    if ($script:activePage -ne 'services' -or $picker.SelectedIndex -ne 0) { throw 'Services did not return to setup overview' }
    foreach ($button in $script:yaploqNav.Values) {
        $enter=[Windows.Input.MouseEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice,[Environment]::TickCount);$enter.RoutedEvent=[Windows.UIElement]::MouseEnterEvent
        $button.RaiseEvent($enter)
        $button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        $leave=[Windows.Input.MouseEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice,[Environment]::TickCount);$leave.RoutedEvent=[Windows.UIElement]::MouseLeaveEvent
        $button.RaiseEvent($leave)
        $window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ContextIdle)
    }
    Set-Page 'services'
}
if (Test-Path -LiteralPath (Join-Path $configDir 'ui-errors.log')) { throw 'Navigation stress test logged an unexpected error' }
# A failed route must preserve the previous page and leave a diagnostic instead of terminating WPF.
$previous=$script:activePage
Set-Page 'unknown-test-route'
if ($script:activePage -ne $previous -or -not(Test-Path -LiteralPath (Join-Path $configDir 'ui-errors.log'))) { throw 'Failed navigation did not preserve the current page and log details' }
Set-Page 'playground'
$script:recentHistoryItems=@(1..30|ForEach-Object{[pscustomobject]@{Id=('large-preview-'+$_);Alias='Mint voice';Text=('Recent speech '+$_);Status='Finished';HasAudio=$true}})
$script:lastPlaybackState=[pscustomobject]@{queue=@()}
$window.Width=1800;$window.Height=1100;$window.Show();$window.UpdateLayout()
$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ContextIdle)
Update-DashboardPreviewSpace;Update-YapLoqDashboard $script:lastPlaybackState
if((Get-DashboardPreviewLimit 1100 350) -le 10 -or (Get-DashboardPreviewLimit 760 350) -ge (Get-DashboardPreviewLimit 1100 350)){throw 'Dashboard capacity does not expand/shrink with available space'}
# The hosted desktop may clamp an oversized window. Test rendering against its
# actual calculated capacity, not a presumed monitor resolution.
if($script:dashboardUpcoming.Children.Count -ne [Math]::Min(30,$script:dashboardPreviewLimit)){throw 'Dashboard does not render its calculated capacity'}
$script:dashboardPreviewLimit=20;Update-YapLoqDashboard $script:lastPlaybackState
if($script:dashboardUpcoming.Children.Count -ne 20){throw 'Dashboard rendering is capped below its requested capacity'}
$window.Width=1180;$window.Height=760;$window.UpdateLayout()
$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ContextIdle)
Update-DashboardPreviewSpace;Update-YapLoqDashboard $script:lastPlaybackState
if($script:dashboardUpcoming.Children.Count -ne [Math]::Min(30,$script:dashboardPreviewLimit)){throw 'Resized Dashboard does not render its calculated capacity'}
$batchStamp='2026-10-18T20:00:00Z'
$batchRows=@([pscustomobject]@{Id='second';Timestamp=$batchStamp;SegmentIndex=1},[pscustomobject]@{Id='first';Timestamp=$batchStamp;SegmentIndex=0})
if(((Sort-YapLoqSpeechRows $batchRows).Id -join ',') -ne 'second,first'){throw 'Multi-voice rows must be newest first, including saved timestamp ties'}
$mixed=@([pscustomobject]@{Id='old';Timestamp='2026-10-18T19:00:00Z';Status='Playing'},[pscustomobject]@{Id='new';Timestamp='2026-10-18T21:00:00Z';Status='Finished'})
if(((Sort-YapLoqSpeechRows $mixed).Id -join ',') -ne 'new,old'){throw 'Playback status overrode chronology'}
$mixed[0].Status='Finished';$mixed[1].Status='Playing'
if(((Sort-YapLoqSpeechRows $mixed).Id -join ',') -ne 'new,old'){throw 'Status transition changed chronology'}
$script:queueManualMoves=@();$script:unifiedQueueGrid.ItemsSource=$null;$script:unifiedQueueSignature=$null
$QueueGrid.ItemsSource=@()
$newHistory=New-QueueSpeechRow ([pscustomobject]@{id='chron-new';timestamp='2026-10-18T21:00:00Z';alias='Mint voice';text='Newest';status='Finished'})
$oldHistory=New-QueueSpeechRow ([pscustomobject]@{id='chron-old';timestamp='2026-10-18T19:00:00Z';alias='Mint voice';text='Older';status='Finished'})
$HistoryGrid.ItemsSource=@($newHistory);Update-YapLoqUnifiedQueue
$HistoryGrid.ItemsSource=@($oldHistory,$newHistory);Update-YapLoqUnifiedQueue
if(($script:unifiedQueueGrid.ItemsSource.Id -join ',') -ne 'chron-new,chron-old'){throw 'Late history snapshot promoted an older recording'}
$newHistory.Status='Playing';Update-YapLoqUnifiedQueue
if(($script:unifiedQueueGrid.ItemsSource.Id -join ',') -ne 'chron-new,chron-old'){throw 'Playing status reordered Queue'}
$script:queueSpeechSearch.Text='Older'
if(($script:unifiedQueueGrid.Items.Id -join ',') -ne 'chron-old'){throw 'Queue text search failed'}
$script:queueSpeechSearch.Text='';$script:queueSpeechStatus.SelectedItem='Finished'
if(($script:unifiedQueueGrid.Items.Id -join ',') -ne 'chron-old'){throw 'Queue status filter failed'}
$script:queueSpeechStatus.SelectedItem='All speech'
if(($script:unifiedQueueGrid.Items.Id -join ',') -ne 'chron-new,chron-old'){throw 'Clearing filters changed newest-first order'}
$detailFixture=[pscustomobject]@{Alias='Mint voice';Status='Error';Time='Today';Source='Test';User='Viewer';Text='Full untruncated message';Error='Provider fixture failure'}
$detailDialog=New-QueueMessageDetails $detailFixture
if($detailDialog.Resources['AppDialogBody'].Child.Children[1].Text -ne $detailFixture.Text -or $detailDialog.Resources['AppDialogBody'].Child.Children[2].Text -notlike '*Provider fixture failure*'){throw 'Message details lost text or failure reason'}
$detailDialog.Close()
$script:recentHistoryItems=@($newHistory,$oldHistory);Update-YapLoqDashboard ([pscustomobject]@{queue=@()})
$finishedRow=@($script:dashboardUpcoming.Children|Where-Object {$_.Tag.Id -eq 'chron-old'})[0]
if($finishedRow.Children[2].Text){throw 'Dashboard still labels completed speech Finished'}
$script:recentHistoryItems=@(1..500|ForEach-Object{[pscustomobject]@{Id=('bounded-'+$_);Timestamp=([datetimeoffset]::UtcNow.AddSeconds(-$_).ToString('o'));Alias='Mint voice';Text=('Speech '+$_);Status='Finished';HasAudio=$false}})
$script:dashboardPreviewLimit=12;$script:appearanceCalls=0
$script:originalAppearance=(Get-Item Function:\Add-SpeechRowAppearance).ScriptBlock
function Add-SpeechRowAppearance($row){$script:appearanceCalls++;& $script:originalAppearance $row}
Update-YapLoqDashboard ([pscustomobject]@{queue=@()})
if($script:appearanceCalls -gt 12){throw 'Dashboard hydrated offscreen history rows'}
$script:appearanceCalls=0
Update-YapLoqDashboard ([pscustomobject]@{queue=@()})
if($script:appearanceCalls -ne 0){throw 'Unchanged Dashboard poll repeated row styling'}
Set-Item Function:\Add-SpeechRowAppearance $script:originalAppearance
$voiceDraft=[pscustomobject]@{Id='change-fixture';Alias='Mint voice';Status='Queued';Text='Waiting fixture';Time='Today';Source='Test';User='';Error='';RowKind='Live'}
$voiceDialog=New-QueuedVoiceDialog $voiceDraft
$voicePicker=$voiceDialog.Content.Child.Children[2]
if(-not $voicePicker.ItemTemplate -or $voicePicker.SelectedItem -ne 'Mint voice'){throw 'Queued voice picker lost alias appearance or current selection'}
$voiceDialog.Close()
$script:unifiedQueueGrid.ItemsSource=@($voiceDraft);$script:unifiedQueueGrid.SelectedItem=$voiceDraft;Sync-YapLoqQueueSelection
if(-not $script:queueChangeVoiceButton.IsEnabled){throw 'Queued message voice change is unavailable'}
$voiceDraft.Status='Generating';Sync-YapLoqQueueSelection
if($script:queueChangeVoiceButton.IsEnabled){throw 'Generating message allows voice changes'}
$parts=@(0..2|ForEach-Object{
    $part=New-QueueSpeechRow ([pscustomobject]@{id=('part-'+$_);groupId='group-fixture';segmentIndex=$_;alias='Mint voice';text=@('Hello','[Fart]','Goodbye')[$_];status='Finished';timestamp=('2026-10-24T12:00:0'+$_+'Z')})
    $part|Add-Member NoteProperty HasAudio $true -Force;$part|Add-Member NoteProperty SavedPath '' -Force;$part
})
$script:unifiedQueueGrid.ItemsSource=@();$script:unifiedQueueSignature=''
$QueueGrid.ItemsSource=@();$HistoryGrid.ItemsSource=@($parts[2],$parts[1],$parts[0]);Update-YapLoqUnifiedQueue
$group=$script:unifiedQueueGrid.ItemsSource[0]
if($script:unifiedQueueGrid.Items.Count -ne 1 -or -not $group.IsGroup -or ($group.Children.Id -join ',') -ne 'part-0,part-1,part-2'){throw 'A split message must be one group with parts in playback order'}
foreach($part in $parts){$part|Add-Member NoteProperty RowKind 'History' -Force}
$parts[2].Accent='#E6A0B1';$parts[2].IconGeometry=(Resolve-VoiceIcon 'mdi:waveform').Geometry
$appearanceGroup=@(Get-YapLoqQueueGroups @($parts[2],$parts[1],$parts[0]))[0]
if($appearanceGroup.Accent -ne $parts[0].Accent -or $appearanceGroup.IconGeometry -ne $parts[0].IconGeometry){throw 'Queue folder must use the first voice, not the latest segment'}
$parts[0].IsAudioStim=$true
$appearanceGroup=@(Get-YapLoqQueueGroups @($parts[2],$parts[1],$parts[0]))[0]
if($appearanceGroup.Accent -ne $parts[1].Accent -or $appearanceGroup.IconGeometry -ne $parts[1].IconGeometry){throw 'Queue folder must skip a leading Audio Stim'}
$parts[1].IsAudioStim=$true;$parts[2].IsAudioStim=$true
$appearanceGroup=@(Get-YapLoqQueueGroups @($parts[2],$parts[1],$parts[0]))[0]
if($appearanceGroup.IconGeometry.ToString() -ne (Resolve-VoiceIcon 'mdi:folder-open').Geometry.ToString()){throw 'Sound-only groups must use a neutral folder, never a stim icon'}
foreach($part in $parts){$part.IsAudioStim=$false}
Set-Page 'queue';$window.UpdateLayout();Switch-YapLoqQueueGroup $group;$window.UpdateLayout()
$container=$script:unifiedQueueGrid.ItemContainerGenerator.ContainerFromItem($group)
if($container.DetailsVisibility -ne 'Visible'){throw 'Message group did not expand'}
$script:unifiedQueueGrid.SelectedItem=$group;Sync-YapLoqQueueSelection
if(-not $ReplayHistoryButton.IsEnabled -or $SaveHistoryAudioButton.Visibility -ne 'Collapsed'){throw 'Message group needs replay without per-file save controls'}
$parts[1].Status='Playing';Update-YapLoqUnifiedQueue;$window.UpdateLayout()
if(-not $script:expandedQueueGroups.ContainsKey('group-fixture') -or $script:unifiedQueueGrid.ItemsSource[0].Status -ne 'Playing'){throw 'Updating a part lost expansion or active group status'}
$container=$script:unifiedQueueGrid.ItemContainerGenerator.ContainerFromItem($script:unifiedQueueGrid.ItemsSource[0])
if($container.DetailsVisibility -ne 'Visible'){throw 'A status update collapsed the message group'}
$presenter=$container.Template.FindName('PART_DetailsPresenter',$container)
if(-not $presenter -or $presenter.ActualHeight -lt 40){throw 'Expanded audio parts are missing from the visible row template'}
foreach($part in $parts){$part.Status='Finished'}
$parts[1].IsAudioStim=$true
$script:recentHistoryItems=@($parts[2],$parts[1],$parts[0]);$script:dashboardPreviewLimit=1
Update-YapLoqDashboard ([pscustomobject]@{queue=@()})
$dashboardGroup=$script:dashboardUpcoming.Children[0]
if($script:dashboardUpcoming.Children.Count -ne 1 -or -not $dashboardGroup.Tag.IsGroup -or ($dashboardGroup.Tag.Children.Id -join ',') -ne 'part-0,part-1,part-2'){throw 'Dashboard must count complete message groups rather than truncate their segments'}
if($dashboardGroup.Tag.Accent -ne $parts[0].Accent){throw 'Dashboard group did not keep the first voice color'}
$dashboardGroup.Resources['GroupToggle'].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
if($dashboardGroup.Resources['GroupParts'].Visibility -ne 'Visible' -or $dashboardGroup.Resources['GroupParts'].Children.Count -ne 3){throw 'Dashboard group did not expand its ordered audio parts'}
$dashboardReplay=@($dashboardGroup.Resources['GroupHeader'].Children|Where-Object{$_ -is [Windows.Controls.Button] -and $_.Tag.IsGroup})[0]
if(-not $dashboardReplay){throw 'Dashboard message group has no full-message replay button'}
$dashboardReplay.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
if($script:recordedRequest -ne '/api/history/replay' -or $script:recordedBody.groupId -ne 'group-fixture' -or $script:recordedBody.speechId){throw 'Dashboard group replay must target the whole message'}
$parts[1].Status='Playing';Update-YapLoqDashboard ([pscustomobject]@{queue=@()})
if($script:dashboardUpcoming.Children[0].Resources['GroupParts'].Visibility -ne 'Visible'){throw 'Dashboard group collapsed during a status update'}
$script:recentHistoryItems=@()
Update-YapLoqDashboard ([pscustomobject]@{current=[pscustomobject]@{id='live-first';groupId='live-group';segmentIndex=0;alias='Mint voice';text='First';status='Playing'};queue=@([pscustomobject]@{id='live-sound';groupId='live-group';segmentIndex=1;alias='Fart';provider='audio-stim';text='[Fart]';status='Queued'},[pscustomobject]@{id='live-last';groupId='live-group';segmentIndex=2;alias='Mint voice';text='Last';status='Queued'})})
if(-not $script:dashboardUpcoming.Children[0].Tag.IsGroup -or $script:dashboardUpcoming.Children[0].Tag.PreviewKind -ne 'Live'){throw 'Active Dashboard messages must form a single group'}
if($OutputDirectory){
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($window)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap));$stream=[IO.File]::Create((Join-Path $OutputDirectory 'queue-group.png'));try{$encoder.Save($stream)}finally{$stream.Dispose()}
    Set-Page 'playground';$script:dashboardUpcoming.Children.Clear();$script:dashboardInputSignature='';$script:dashboardQueueSignature=''
    foreach($part in $parts){$part.Status='Finished'};$script:recentHistoryItems=@($parts[2],$parts[1],$parts[0]);Update-YapLoqDashboard ([pscustomobject]@{queue=@()});$window.UpdateLayout()
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($window)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap));$stream=[IO.File]::Create((Join-Path $OutputDirectory 'dashboard-groups.png'));try{$encoder.Save($stream)}finally{$stream.Dispose()}
}
if(-not $KeepWindowOpen){$window.Close()}
'YapLoq shell passed: six routes, unified rules, Dashboard state, 14 views at two sizes, 132 provider selections, repeated sidebar/hover events, direct service back navigation and failed-route recovery.'
