param([string]$OutputImage='')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'test_yaploq_shell.ps1')
$oldWindow=$window;$window=[Windows.Window]::new();$window.Resources=$oldWindow.Resources;$window.FontFamily=$oldWindow.FontFamily
$window.ShowInTaskbar=$false;$window.ShowActivated=$false;$window.Left=-10000;$window.Show();$window.Hide()
function Invoke-BridgePost([string]$path,$body){$script:stimRequest=$body;return [pscustomobject]@{ok=$true;result=[pscustomobject]@{file='C:\sounds\fart.wav'}}}
function Show-UnsavedChangesPrompt($owner,$context,$saveAction){return 'Discard'}
function Show-AudioStimEditor([switch]$New){$script:testStimDialog=New-AudioStimEditor -New:$New}
Initialize-YapLoqFilePickers
Set-Page 'stims'
$click=[Windows.Controls.Button]::ClickEvent
if(-not $script:stimView.FindName('Edit') -or -not $script:stimSearchBox){throw 'Alias-style list toolbar missing'}
$script:stimView.FindName('Add').RaiseEvent([Windows.RoutedEventArgs]::new($click))
if(-not $script:stimDialogOpen -or -not $script:testStimDialog.Resources['AppDialogChrome']){throw 'Add must open a themed popup'}
$script:stimKeywordBox.Text='Fart';$script:stimKeywordBox.GetBindingExpression([Windows.Controls.TextBox]::TextProperty).UpdateSource()
Add-AudioStimFiles @('C:\sounds\fart.wav','C:\sounds\burp.mp3','C:\sounds\ignore.txt','C:\sounds\fart.wav')
$draft=Get-AudioStimDraft
if($draft.Fart.files.Count -ne 2 -or $script:stimLibraryGrid.SelectedItem.Files[0].FileName -ne 'fart.wav'){throw 'File library or filename display failed'}
if($script:stimColorBox -isnot [Windows.Controls.WrapPanel] -or $script:stimColorBox.Children.Count -ne 10){throw 'Alias color swatches missing'}
$iconRow=$script:stimIconBox.Parent
if($iconRow -isnot [Windows.Controls.Grid] -or $iconRow.Children[1].Content -ne 'Browse icons' -or $iconRow.ColumnDefinitions[1].Width.GridUnitType -ne 'Auto'){throw 'Browse icons must stay natural-sized beside the icon field'}
@($script:stimColorBox.Children|Where-Object Tag -eq '#87C9AF')[0].RaiseEvent([Windows.RoutedEventArgs]::new($click))
$script:stimIconBox.Text='mdi:account';$script:stimIconBox.GetBindingExpression([Windows.Controls.TextBox]::TextProperty).UpdateSource()
Update-AudioStimAppearance
foreach($pair in @(@(2,'Volume',0),@(3,'Weight',1))){
    $root=$script:stimFilesGrid.Columns[$pair[0]].CellTemplate.LoadContent();$file=$script:stimLibraryGrid.SelectedItem.Files[0];$root.DataContext=$file
    $root.Measure([Windows.Size]::new(180,48));$root.Arrange([Windows.Rect]::new(0,0,180,48));$root.UpdateLayout()
    $slider=$root.Children[0];if($slider -isnot [Windows.Controls.Slider] -or $slider.Minimum -ne $pair[2] -or $slider.Maximum -ne 100){throw 'Sound controls must be bounded sliders'}
    $slider.GetBindingExpression([Windows.Controls.Primitives.RangeBase]::ValueProperty).UpdateTarget()
    $slider.Value=25;$slider.GetBindingExpression([Windows.Controls.Primitives.RangeBase]::ValueProperty).UpdateSource()
    if($file.($pair[1]) -ne 25){throw 'Slider value did not update sound draft'}
}
if((Get-AudioStimDraft).Fart.files[0].volume -ne .25){throw 'Volume percent conversion failed'}
$script:stimModeBox.SelectedValue='pause_with_user';$script:stimPauseBox.Text='2.5';$script:stimPauseBox.GetBindingExpression([Windows.Controls.TextBox]::TextProperty).UpdateSource()
if((Get-AudioStimDraft).Fart.pause_seconds -ne 2.5){throw 'Pause settings not preserved'}
$script:stimView.FindName('Random').RaiseEvent([Windows.RoutedEventArgs]::new($click))
if($script:stimRequest.keyword -ne 'Fart' -or $script:stimRequest.library.files.Count -ne 2){throw 'Random test lost the draft library'}
$script:testStimDialog.Resources['SaveButton'].RaiseEvent([Windows.RoutedEventArgs]::new($click))
if($script:stimDialogOpen -or (Read-Settings).audio_stims.Fart.color -ne '#87C9AF'){throw 'Save popup did not persist and close'}
$original=$script:stimLibraryGrid.SelectedItem
$dialog=New-AudioStimEditor
$script:stimKeywordBox.Text='Changed';$script:stimKeywordBox.GetBindingExpression([Windows.Controls.TextBox]::TextProperty).UpdateSource()
$script:stimLibraryGrid.SelectedItem.Files[0].Volume=0
$dialog.Close()
if($script:stimLibraryGrid.SelectedItem.Keyword -ne 'Fart' -or $original.Files[0].Volume -ne 25){throw 'Discard did not restore original keyword and sound levels'}
if($script:stimView.FindName('Editor').Parent){throw 'Editor remained on the main page after close'}
$script:stimSearchBox.Text='not present';if($script:stimLibraryGrid.Items.Count){throw 'Search did not filter keywords'}
$script:stimSearchBox.Text='Fart';if($script:stimLibraryGrid.Items.Count -ne 1){throw 'Search did not restore keyword'}
$script:stimLibraryGrid.SelectedIndex=0
$dialog=New-AudioStimEditor -New;$script:stimKeywordBox.Text='Discard me';$dialog.Close()
if($script:stimLibraryGrid.ItemsSource.Count -ne 1){throw 'Cancelled new keyword was retained'}
$script:stimLibraryGrid.SelectedIndex=0
$row=[pscustomobject]@{Alias='Fart'};Add-SpeechRowAppearance $row
if($row.Accent -ne '#87C9AF' -or -not $row.IconGeometry){throw 'Keyword appearance not applied to queue'}
if($OutputImage){
    $dialog=New-AudioStimEditor
    $dialog.ShowActivated=$false;$dialog.ShowInTaskbar=$false;$dialog.WindowStartupLocation='Manual';$dialog.Left=-10000;$dialog.Top=0;$dialog.Show();$dialog.UpdateLayout()
    $dialog.Dispatcher.Invoke([action]{},[Windows.Threading.DispatcherPriority]::ApplicationIdle)
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(880,820,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($dialog)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap));$stream=[IO.File]::Create($OutputImage);try{$encoder.Save($stream)}finally{$stream.Dispose()}
    $dialog.Close()
}
$window.Close()
'PASS: alias-style sound list, themed editor, swatches, sliders, draft save/discard, search, previews and appearance'
