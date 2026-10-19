param([string]$OutputDirectory='')
$ErrorActionPreference='Stop'
$voiceExportOutput=$OutputDirectory
. (Join-Path $PSScriptRoot 'test_viewers_ui.ps1') -KeepOpen
$OutputDirectory=$voiceExportOutput
$s=Read-Settings;Set-JsonProperty $s 'enable_udp' $true;Set-JsonProperty $s 'udp_port' 6670;Set-JsonProperty $s.aliases 'New export voice' ($s.aliases.EventVoice|ConvertTo-Json -Depth 20|ConvertFrom-Json);Write-Settings $s;$UdpBox.Text='6670'
$AliasSearchBox.Text='';$AliasProviderFilter.SelectedIndex=0;$FavoritesOnlyCheck.IsChecked=$false;Refresh-Grid -VoicesOnly
if($AliasGrid.SelectionMode -ne 'Extended'){throw 'Multiple voice selection is unavailable'}
$AliasGrid.SelectedItems.Clear()
if($script:voiceExportButton.IsEnabled){throw 'Export enabled with no selection'}
$rows=@($AliasGrid.ItemsSource);$AliasGrid.SelectedItems.Add($rows[0])|Out-Null;$AliasGrid.SelectedItems.Add($rows[1])|Out-Null
if($script:voiceExportButton.Content -ne 'Export voices (2)' -or -not $script:voiceExportButton.IsEnabled){throw ('Selection count is not reflected by export button: selected='+$AliasGrid.SelectedItems.Count+' label='+$script:voiceExportButton.Content)}
if($EditButton.IsEnabled -or $RemoveButton.IsEnabled){throw 'Single-voice editors can act ambiguously on a multi-selection'}
$expected=@($AliasGrid.SelectedItems|ForEach-Object Name|Sort-Object)
Refresh-Grid -VoicesOnly
if((@($AliasGrid.SelectedItems|ForEach-Object Name|Sort-Object) -join '|') -ne ($expected -join '|')){throw 'Voice refresh lost the multi-selection'}
$fixture=Join-Path $configDir 'selected-voices.sb';[IO.File]::WriteAllText($fixture,'selected-voices-code')
function Invoke-BridgePost([string]$path,$body=@{}){$script:selectedExportRequest=$body;$script:selectedExportPath=$path;[pscustomobject]@{result=[pscustomobject]@{path=$fixture}}}
$AliasGrid.ContextMenu.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.ContextMenu]::OpenedEvent))
$item=@($AliasGrid.ContextMenu.Items|Where-Object Tag -eq 'export-streamerbot')[0]
if(-not $item -or -not $item.IsEnabled){throw 'Selected voice export missing from context menu'}
$item.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
if($script:selectedExportPath -ne '/api/maintenance/streamerbot-voices' -or (@($script:selectedExportRequest.aliases|Sort-Object) -join '|') -ne ($expected -join '|') -or [Windows.Clipboard]::GetText() -ne 'selected-voices-code'){throw 'Context export did not send exactly the selected names'}
Set-Page 'voices';$window.UpdateLayout()
$selectedRow=$AliasGrid.ItemContainerGenerator.ContainerFromItem($AliasGrid.SelectedItems[0])
if($selectedRow){$args=[Windows.Input.MouseButtonEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice,0,[Windows.Input.MouseButton]::Right);$args.RoutedEvent=[Windows.UIElement]::PreviewMouseRightButtonDownEvent;$selectedRow.RaiseEvent($args)}
if($AliasGrid.SelectedItems.Count -ne 2){throw 'Right-click discarded selected voices'}
foreach($size in @(@(980,640),@(1180,760))){
    $window.Width=$size[0];$window.Height=$size[1];$window.UpdateLayout()
    if($script:voiceExportButton.ActualWidth -le 0){throw 'Export toolbar button is hidden'}
    if($OutputDirectory){[void][IO.Directory]::CreateDirectory($OutputDirectory);$bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($window);$encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap));$stream=[IO.File]::Create((Join-Path $OutputDirectory ('voice-export-'+$size[0]+'.png')));try{$encoder.Save($stream)}finally{$stream.Dispose()}}
}
$AliasGrid.SelectedItems.Clear();$AliasGrid.SelectedItems.Add($AliasGrid.ItemsSource[0])|Out-Null
$script:voiceExportButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
if(@($script:selectedExportRequest.aliases).Count -ne 1 -or -not $EditButton.IsEnabled){throw 'Single voice export/edit no longer works'}
$window.Close()
'Selected voice export UI passed: multi-select, count, refresh, context menu, single voice and responsive toolbar.'
