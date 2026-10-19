param([string]$OutputDirectory='')
$ErrorActionPreference='Stop'
$packOutput=$OutputDirectory
. (Join-Path $PSScriptRoot 'test_viewers_ui.ps1') -KeepOpen
$OutputDirectory=$packOutput
if('streamerPack' -notin @($script:ownerSections.Integrations|ForEach-Object{$_[1]})){throw 'Import pack is not a Streamer.Bot subtab'}
if($script:streamerPackPlatform -or $script:streamerPackPreset){throw 'Universal setup still asks for a platform or pack'}
if($window.FindName('StreamerExportCard').Visibility -ne 'Collapsed' -or $script:assignmentTemplatesCard.Visibility -ne 'Collapsed'){throw 'Old partial export entry points remain visible'}
$fixture=Join-Path $configDir 'pack.sb';[IO.File]::WriteAllText($fixture,'fixture-import-code')
$s=Read-Settings;Set-JsonProperty $s 'enable_udp' $true;Set-JsonProperty $s 'udp_port' 6670;Write-Settings $s;$UdpBox.Text='6670'
function Invoke-BridgePost([string]$path,$body=@{}){$script:packRequest=$body;$script:packPath=$path;[pscustomobject]@{result=[pscustomobject]@{path=$fixture}}}
$script:streamerPackCopyButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
if($script:packPath -ne '/api/maintenance/streamerbot-pack' -or $script:packRequest.preset -ne 'complete' -or $script:packRequest.ContainsKey('platform') -or [Windows.Clipboard]::GetText() -ne 'fixture-import-code'){throw 'One-click universal pack failed'}
$window.Show();Set-Page 'streamerPack'
foreach($size in @(@(980,640),@(1180,760),@(1462,800))){
    $window.Width=$size[0];$window.Height=$size[1];$window.UpdateLayout()
    if($script:yaploqPages.streamerPack.Visibility -ne 'Visible' -or $script:streamerPackCopyButton.ActualWidth -le 0){throw 'Import pack is not visible'}
    if($OutputDirectory){[void][IO.Directory]::CreateDirectory($OutputDirectory);$bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($window);$encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap));$stream=[IO.File]::Create((Join-Path $OutputDirectory ('pack-'+$size[0]+'.png')));try{$encoder.Save($stream)}finally{$stream.Dispose()}}
}
$window.Close()
'Streamer.Bot pack UI passed: one universal import, no selectors, clipboard export and three sizes.'
