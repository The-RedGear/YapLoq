param([string]$OutputImage='')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'test_yaploq_shell.ps1')
Initialize-YapLoqFilePickers
Load-ProfanityRules ([pscustomobject]@{profanity_enabled=$true;profanity_hide_words=$true;profanity_rules=@([pscustomobject]@{word='badword';variants=@();enabled=$true;match_variants=$false;action='stim';replacement='Fart'})})
Update-ProfanityDisplay
if((Get-DisplayText 'FART [Fart] badword') -ne 'FART [Fart] *******'){throw 'Stim keyword incorrectly masked as profanity'}
if(-not ('YapLoqFolderPicker' -as [type])){throw 'Modern folder picker did not compile'}
function Invoke-BridgePost([string]$path,$body){return [pscustomobject]@{ok=$true;result=$body}}
Set-Page 'stims'
if(-not $script:stimView -or -not $script:globalSaveGroups['Audio Stims']){throw 'Audio Stims page or Save group missing'}
$stimIcon=$script:yaploqNav.AudioStims.Content.Children[0]
if($stimIcon.Tag -ne 'audio-stims-waveform' -or $stimIcon.Data.ToString() -eq $script:yaploqNav.Queue.Content.Children[0].Data.ToString()){throw 'Audio Stims must have its own waveform icon'}
if(-not [Windows.Data.BindingOperations]::IsDataBound($stimIcon,[Windows.Shapes.Shape]::FillProperty)){throw 'Audio Stims icon lost navigation highlight binding'}
foreach($grid in @($script:stimLibraryGrid,$script:stimFilesGrid)){foreach($column in $grid.Columns){if($column -is [Windows.Controls.DataGridTextColumn] -and $column.ElementStyle -ne $window.FindResource('GridText') -and $column.ElementStyle.BasedOn -ne $window.FindResource('GridText')){throw 'Grid text must align with header padding'}}}
if($script:stimFilesGrid.Columns[0].Width.Value -lt 60 -or $script:stimFilesGrid.Columns[2].Width.Value -lt 90){throw 'Sound table headings will be clipped'}
$click=[Windows.Controls.Button]::ClickEvent
$script:stimView.FindName('Add').RaiseEvent([Windows.RoutedEventArgs]::new($click))
$script:stimKeywordBox.Text='Fart'
$script:stimKeywordBox.GetBindingExpression([Windows.Controls.TextBox]::TextProperty).UpdateSource()
Add-AudioStimFiles @('C:\sounds\fart.wav','C:\sounds\burp.mp3','C:\sounds\ignore.txt','C:\sounds\fart.wav')
$draft=Get-AudioStimDraft
if($draft.Fart.allow_without_user){throw 'Anonymous action opt-in must default off'}
$script:stimAllowWithoutUserCheck.IsChecked=$true
$script:stimAllowWithoutUserCheck.GetBindingExpression([Windows.Controls.Primitives.ToggleButton]::IsCheckedProperty).UpdateSource()
if(-not (Get-AudioStimDraft).Fart.allow_without_user){throw 'Anonymous action opt-in did not bind'}
$script:stimModeBox.SelectedValue='pause_without_user';$script:stimPauseBox.Text='2.5'
$script:stimPauseBox.GetBindingExpression([Windows.Controls.TextBox]::TextProperty).UpdateSource()
if((Get-AudioStimDraft).Fart.playback_mode -ne 'pause_without_user' -or (Get-AudioStimDraft).Fart.pause_seconds -ne 2.5){throw 'Pause controls did not bind'}
$script:stimModeBox.SelectedValue='sound'
if($draft.Fart.files.Count -ne 2 -or $draft.Fart.files[0].volume -ne 1){throw 'Library file selection did not serialize correctly'}
if($script:stimLibraryGrid.SelectedItem.Files[0].FileName -ne 'fart.wav' -or $script:stimFilesGrid.Columns[1].Binding.Path.Path -ne 'FileName'){throw 'Sound list must display only filenames'}
if($draft.Fart.files[0].path -ne 'C:\sounds\fart.wav'){throw 'Filename display changed saved full path'}
if(-not $script:stimFilesGrid.ContextMenu -or -not $script:stimLibraryGrid.ContextMenu){throw 'Right-click menus missing'}
$script:stimFilesGrid.SelectedIndex=0
Invoke-AudioStimMenu 'toggle-file'
if($script:stimFilesGrid.SelectedItem.Enabled){throw 'Right-click sound toggle failed'}
Invoke-AudioStimMenu 'toggle-file'
$script:stimFilesGrid.SelectedItem.Volume=.4;$script:stimFilesGrid.SelectedItem.Weight=3
Invoke-AudioStimMenu 'reset-file'
if($script:stimFilesGrid.SelectedItem.Volume -ne 100 -or $script:stimFilesGrid.SelectedItem.Weight -ne 1){throw 'Right-click reset failed'}
$script:stimFilesGrid.SelectedItem.Volume=25
if((Get-AudioStimDraft).Fart.files[0].volume -ne .25){throw 'Volume percent did not convert to playback gain'}
$script:stimFilesGrid.SelectedItem.Volume=100
Reset-GlobalSaveGroup 'Audio Stims'
$script:stimLibraryGrid.SelectedItem=$null
Update-GlobalSaveGroup 'Audio Stims'
if($script:globalSaveGroups['Audio Stims'].Dirty){throw 'Changing selection marked the library dirty'}
$script:stimLibraryGrid.SelectedIndex=0
$script:stimActionBox.Text='[CE] - Fart [Attack]'
$script:stimActionBox.RaiseEvent([Windows.Controls.TextChangedEventArgs]::new([Windows.Controls.TextBox]::TextChangedEvent,[Windows.Controls.UndoAction]::None))
Update-GlobalSaveGroup 'Audio Stims'
if(-not $script:globalSaveGroups['Audio Stims'].Dirty){throw 'Action edit did not mark the library dirty'}
Save-AudioStims
 [void]$script:stimOutputBox.Items.Add('Sound effects device')
 $script:stimOutputBox.SelectedItem='Sound effects device'
 Update-GlobalSaveGroup 'Audio Stims'
 if(-not $script:globalSaveGroups['Audio Stims'].Dirty){throw 'Output selection did not mark changes dirty'}
 Save-AudioStims
Refresh-AudioStims
if($script:stimOutputBox.SelectedItem -ne 'Sound effects device' -or (Read-Settings).audio_stims.Fart.output_device -ne 'Sound effects device'){throw 'Per-keyword output did not persist'}
Refresh-AudioStimOutputs -PreserveSelection
if($script:stimOutputBox.SelectedItem -ne 'Sound effects device'){throw 'Unavailable selected output was lost during refresh'}
if($script:stimLibraryGrid.ItemsSource[0].Action -ne '[CE] - Fart [Attack]'){throw 'Saved library did not reload'}
if($script:stimFilesGrid.Columns[0].ElementStyle.BasedOn -ne $window.FindResource([Windows.Controls.CheckBox])){throw 'Sound checkbox is not themed'}
$checkFixture=[Windows.Controls.CheckBox]::new();$checkFixture.Style=$script:stimFilesGrid.Columns[0].ElementStyle
if($checkFixture.Margin.Left -ne 18 -or $checkFixture.VerticalAlignment -ne 'Center'){throw 'Checkbox is not aligned under the On header'}
foreach($index in @(2,3)){
    $editFixture=[Windows.Controls.TextBox]::new();$editFixture.Style=$script:stimFilesGrid.Columns[$index].EditingElementStyle
    $editFixture.Measure([Windows.Size]::new($script:stimFilesGrid.Columns[$index].Width.Value,48))
    if($editFixture.MinWidth -ne 0 -or $editFixture.DesiredSize.Width -gt $script:stimFilesGrid.Columns[$index].Width.Value -or $editFixture.Height -gt 40){throw 'Numeric editor exceeds its cell bounds'}
}
$script:automationRemoteActions=@(1..250|ForEach-Object{[pscustomobject]@{id="action-$_";name="Action $_"}})+@([pscustomobject]@{id='fart-id';name='Fart attack'})
$script:stimActionBox.Text='Fart';Update-AutomationActionSearch $script:stimView
if($script:stimActionBox.Items.Count -ne 1){throw 'Action dropdown did not filter'}
$script:stimActionBox.SelectedIndex=0
if($script:stimLibraryGrid.SelectedItem.Action -ne 'fart-id'){throw 'Action selection did not store stable ID'}
function Invoke-BridgePost([string]$path,$body){$script:stimPreviewBody=$body;return [pscustomobject]@{ok=$true;result=[pscustomobject]@{file='C:\sounds\fart.wav'}}}
$script:stimView.FindName('Random').RaiseEvent([Windows.RoutedEventArgs]::new($click))
if($script:stimPreviewBody.library.files.Count -ne 2){throw 'Random test did not send the selected draft library'}
$firstLibrary=$script:stimLibraryGrid.SelectedItem
$secondLibrary=New-AudioStimRow 'Burp' @{output_device='[Same as TTS output]';files=@()}
$script:stimLibraryGrid.ItemsSource.Add($secondLibrary)
Reset-GlobalSaveGroup 'Audio Stims'
$script:stimLibraryGrid.SelectedItem=$secondLibrary
if($script:stimOutputBox.SelectedItem -ne '[Same as TTS output]'){throw 'Second keyword did not restore its own output'}
$script:stimLibraryGrid.SelectedItem=$firstLibrary
Update-GlobalSaveGroup 'Audio Stims'
if($script:stimOutputBox.SelectedItem -ne 'Sound effects device' -or $script:globalSaveGroups['Audio Stims'].Dirty){throw 'Switching keywords changed output or marked settings dirty'}
[void]$script:stimLibraryGrid.ItemsSource.Remove($secondLibrary)
if($OutputImage){
    [void]$script:stimView.Parent.Children.Remove($script:stimView)
    $previewHost=[Windows.Controls.Border]::new();$previewHost.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#18151F');$previewHost.Child=$script:stimView
    $previewHost.Resources=$window.Resources
    $previewHost.SetValue([Windows.Documents.TextElement]::ForegroundProperty,[Windows.Media.Brushes]::White)
    $script:stimView.Width=1000;$script:stimView.Height=800
    $previewHost.Measure([Windows.Size]::new(1000,800));$previewHost.Arrange([Windows.Rect]::new(0,0,1000,800));$previewHost.UpdateLayout()
    if($script:stimKeywordBox.Text -ne 'Fart' -or $script:stimFilesGrid.Items.Count -ne 2){throw 'Selected library fields were not restored'}
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(1000,800,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($previewHost)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream=[IO.File]::Create($OutputImage);try{$encoder.Save($stream)}finally{$stream.Dispose()}
}
$script:stimView.FindName('Delete').RaiseEvent([Windows.RoutedEventArgs]::new($click))
if($script:stimLibraryGrid.ItemsSource.Count){throw 'Delete did not remove library'}
Refresh-AudioStims
if($script:stimLibraryGrid.ItemsSource.Count -ne 1){throw 'Discard reload did not restore library'}
$window.Close()
'PASS: Audio Stims navigation, binding, files, save, selection, deletion and reload'
