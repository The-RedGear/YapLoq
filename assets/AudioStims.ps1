. (Join-Path $resourceRoot 'assets/AudioStimsDesign.ps1')
. (Join-Path $resourceRoot 'assets/AudioStimDialogs.ps1')
function script:New-AudioStimRow([string]$name,$value){
    $files=[Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach($file in @($value.files)){
        if($file){$files.Add([pscustomobject]@{Path=[string]$file.path;FileName=[IO.Path]::GetFileName([string]$file.path);Volume=([Math]::Min(100,[double]$file.volume*100));Weight=([Math]::Max(1,[Math]::Min(100,[double]$file.weight)));Enabled=($file.enabled -ne $false -and [double]$file.weight -gt 0)})}
    }
    $icon=if($value.icon_id){[string]$value.icon_id}else{'mdi:waveform'};$color=Get-VoiceAccent ([string]$value.color)
    $device=if($value.output_device){[string]$value.output_device}elseif((Read-Settings).audio_stim_output_device){[string](Read-Settings).audio_stim_output_device}else{'[Same as TTS output]'}
    return [pscustomobject]@{Keyword=$name;IconId=$icon;Color=$color;Accent=$color;AccentBackground=('#33'+$color.Substring(1));OutputDevice=$device;Enabled=($value.enabled -ne $false);Files=$files;Action=[string]$value.action;ReplayActions=($value.replay_actions -eq $true);AllowWithoutUser=($value.allow_without_user -eq $true);PlaybackMode=$(if($value.playback_mode){[string]$value.playback_mode}else{'sound'});PauseSeconds=$(if($value.pause_seconds){[double]$value.pause_seconds}else{1.0});CensorWords=(@($value.censor_words) -join [Environment]::NewLine)}
}
function script:Get-AudioStimDraft {
    [void]$script:stimLibraryGrid.CommitEdit();[void]$script:stimFilesGrid.CommitEdit()
    $libraries=[ordered]@{}
    foreach($row in $script:stimLibraryGrid.ItemsSource){
        $name=$row.Keyword.Trim()
        if(-not$name){throw 'Enter a keyword for each Audio Stim.'}
        if(@($libraries.Keys | Where-Object {$_ -ieq $name}).Count){throw 'Audio Stim keywords must be unique.'}
        $files=@(foreach($file in $row.Files){
            $volume=[double]$file.Volume;$weight=[double]$file.Weight
            if([double]::IsNaN($volume) -or [double]::IsInfinity($volume) -or $volume -lt 0 -or $volume -gt 100){throw 'Volume must be between 0 and 100.'}
            if([double]::IsNaN($weight) -or [double]::IsInfinity($weight) -or $weight -lt 1 -or $weight -gt 100){throw 'Weight must be between 1 and 100.'}
            @{path=$file.Path;volume=($volume/100);weight=$weight;enabled=[bool]$file.Enabled}
        })
        $libraries[$name]=@{enabled=[bool]$row.Enabled;files=$files;output_device=[string]$row.OutputDevice;action=$row.Action.Trim();replay_actions=[bool]$row.ReplayActions;allow_without_user=[bool]$row.AllowWithoutUser;playback_mode=[string]$row.PlaybackMode;pause_seconds=[double]$row.PauseSeconds;censor_words=@($row.CensorWords -split '\r?\n' | ForEach-Object {$_.Trim()} | Where-Object {$_})}
        $libraries[$name].icon_id=[string]$row.IconId;$libraries[$name].color=[string]$row.Color
    }
    return $libraries
}
function script:Save-AudioStims {
    $libraries=Get-AudioStimDraft
    $result=Invoke-BridgePost '/api/stims/validate' @{libraries=$libraries}
    if(-not$result.ok){throw 'Audio Stim validation failed.'}
    $settings=Read-Settings
    Set-JsonProperty $settings 'audio_stims' $libraries
    Write-Settings $settings
}
function script:Add-AudioStimFiles($paths){
    $row=$script:stimLibraryGrid.SelectedItem
    if(-not$row){return}
    foreach($path in $paths){
        if([IO.Path]::GetExtension($path).ToLowerInvariant() -notin @('.wav','.mp3','.ogg','.flac')){continue}
        if(@($row.Files | Where-Object Path -eq $path).Count){continue}
        $row.Files.Add([pscustomobject]@{Path=[string]$path;FileName=[IO.Path]::GetFileName([string]$path);Volume=100.0;Weight=1.0;Enabled=$true})
    }
    if($script:globalSaveGroups){Update-GlobalSaveGroup 'Audio Stims'}
}
function script:Refresh-AudioStimOutputs([switch]$PreserveSelection){
    if(-not $script:stimOutputBox){return}
    $selected=if($script:stimLibraryGrid.SelectedItem){[string]$script:stimLibraryGrid.SelectedItem.OutputDevice}else{'[Same as TTS output]'}
    if(-not $selected){$selected='[Same as TTS output]'}
    $script:stimOutputRefreshing=$true
    try{
    $script:stimOutputBox.Items.Clear()
    foreach($name in @('[Same as TTS output]','[Default]')+@($OutputDeviceBox.Items)){
        if($name -and -not $script:stimOutputBox.Items.Contains([string]$name)){[void]$script:stimOutputBox.Items.Add([string]$name)}
    }
    if(-not $script:stimOutputBox.Items.Contains($selected)){[void]$script:stimOutputBox.Items.Add($selected)}
    $script:stimOutputBox.SelectedItem=$selected
    }finally{$script:stimOutputRefreshing=$false}
}
function script:Refresh-AudioStims {
    if(-not $script:stimLibraryGrid){return}
    $rows=[Collections.ObjectModel.ObservableCollection[object]]::new()
    $settings=Read-Settings
    Refresh-AudioStimOutputs
    if($settings.audio_stims){foreach($prop in $settings.audio_stims.PSObject.Properties){$rows.Add((New-AudioStimRow $prop.Name $prop.Value))}}
    $script:stimLibraryGrid.ItemsSource=$rows
    if($rows.Count){$script:stimLibraryGrid.SelectedIndex=0}else{$script:stimView.FindName('Editor').DataContext=$null;$script:stimView.FindName('Editor').IsEnabled=$false}
    Update-AudioStimAppearance
}
function script:Install-AudioStims {
    $panel=New-YapLoqPage 'stims'
    [xml]$xml=@'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" MinHeight="530">
 <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
 <TextBlock Text="Audio Stims" FontSize="24" FontWeight="SemiBold" Margin="0,0,0,10"/>
 <StackPanel Grid.Row="1" Margin="0,0,0,16">
  <TextBlock Text="Type [Keyword] in a message. Sounds play between spoken parts, in order." Foreground="#B9B2C2" TextWrapping="Wrap"/>
 </StackPanel>
 <Grid Grid.Row="2"><Grid.ColumnDefinitions><ColumnDefinition Width="220"/><ColumnDefinition Width="18"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
  <DockPanel><StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="0,0,0,10"><Button Name="Add" Content="Add stim"/><Button Name="Delete" Content="Delete" Margin="8,0,0,0"/></StackPanel>
   <DataGrid Name="Libraries" AutoGenerateColumns="False" CanUserAddRows="False" SelectionMode="Single" MinHeight="380"><DataGrid.Columns><DataGridTextColumn Header="Keyword" Binding="{Binding Keyword}" Width="*"/></DataGrid.Columns></DataGrid>
  </DockPanel>
  <Grid Grid.Column="2" Name="Editor"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="220"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
   <StackPanel><TextBlock Text="Keyword (without brackets)"/><TextBox Name="Keyword" Tag="e.g. Fart" Text="{Binding Keyword, UpdateSourceTrigger=PropertyChanged}" Margin="0,6,0,8"/><CheckBox Name="LibraryEnabled" Content="Enabled" IsChecked="{Binding Enabled}"/><TextBlock Text="Output for this keyword" Margin="0,12,0,6"/><ComboBox Name="StimOutput" ToolTip="Applies only to this keyword and its previews."/></StackPanel>
   <TextBlock Grid.Row="1" Text="Volume: 0 muted, 100 maximum. Weight: 1 lowest, 100 highest. Uncheck a sound to exclude it." Foreground="#B9B2C2" TextWrapping="Wrap" Margin="0,12,0,8"/>
   <WrapPanel Grid.Row="2" Margin="0,0,0,8"><Button Name="Files" Content="Add files..."/><Button Name="Folder" Content="Add folder..." Margin="8,0,0,0"/><Button Name="RemoveFile" Content="Remove" Margin="8,0,0,0"/><Button Name="Preview" Content="Preview" Margin="8,0,0,0"/><Button Name="Random" Content="Test random" Margin="8,0,0,0" ToolTip="Preview a weighted random sound. Does not run actions."/></WrapPanel>
   <DataGrid Grid.Row="3" Name="Sounds" AutoGenerateColumns="False" CanUserAddRows="False" SelectionMode="Single" ItemsSource="{Binding Files}"><DataGrid.Columns>
    <DataGridCheckBoxColumn Header="On" Binding="{Binding Enabled}" Width="64"/>
    <DataGridTextColumn Header="File" Binding="{Binding FileName}" IsReadOnly="True" Width="*"/>
    <DataGridTextColumn Header="Volume %" Binding="{Binding Volume}" Width="110"/>
    <DataGridTextColumn Header="Weight" Binding="{Binding Weight}" Width="90"/>
   </DataGrid.Columns></DataGrid>
   <StackPanel Grid.Row="4" Margin="0,14,0,0"><TextBlock Text="Streamer.bot action at playback start (optional)"/><ComboBox Name="StepActionPicker" IsEditable="True" IsTextSearchEnabled="False" DisplayMemberPath="name" MaxDropDownHeight="280" Tag="Search actions or enter an exact name or ID" Margin="0,6,0,0"/><TextBlock Name="StepSearchStatus" Foreground="#B9B2C2" TextWrapping="Wrap" Margin="0,4,0,0"/><TextBlock Name="StepStatus" Foreground="#E6A0B1" TextWrapping="Wrap"/><CheckBox Name="ReplayActions" Content="Also run this action when replaying the sound" IsChecked="{Binding ReplayActions}" Margin="0,8,0,0"/></StackPanel>
   <StackPanel Grid.Row="5" Margin="0,14,0,0"><TextBlock Text="Replace these words with this stim (optional)"/><TextBox Name="Censor" Tag="One word or phrase per line" Text="{Binding CensorWords, UpdateSourceTrigger=PropertyChanged}" AcceptsReturn="True" Height="75" Margin="0,6,0,0" VerticalScrollBarVisibility="Auto"/></StackPanel>
   <TextBlock Grid.Row="6" Text="Folders add their current audio files. Preview never runs Streamer.bot actions." Foreground="#B9B2C2" TextWrapping="Wrap" Margin="0,12,0,0"/>
   <TextBlock Grid.Row="7" Name="Status" Foreground="#E6A0B1" TextWrapping="Wrap" Margin="0,10,0,0"/>
  </Grid>
 </Grid>
</Grid>
'@
    $view=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xml));[void]$panel.Children.Add($view)
    $script:stimView=$view;$script:stimLibraryGrid=$view.FindName('Libraries');$script:stimFilesGrid=$view.FindName('Sounds')
    $script:stimKeywordBox=$view.FindName('Keyword');$script:stimActionBox=$view.FindName('StepActionPicker');$script:stimCensorBox=$view.FindName('Censor')
    $script:stimEnabledCheck=$view.FindName('LibraryEnabled');$script:stimReplayCheck=$view.FindName('ReplayActions')
    $script:stimAllowWithoutUserCheck=[Windows.Controls.CheckBox]::new();$script:stimAllowWithoutUserCheck.Content='Allow this action without viewer information';$script:stimAllowWithoutUserCheck.Margin='0,8,0,0'
    $binding=[Windows.Data.Binding]::new('AllowWithoutUser');$binding.Mode='TwoWay';[void]$script:stimAllowWithoutUserCheck.SetBinding([Windows.Controls.Primitives.ToggleButton]::IsCheckedProperty,$binding)
    [void]$script:stimReplayCheck.Parent.Children.Add($script:stimAllowWithoutUserCheck)
    $modeLabel=[Windows.Controls.TextBlock]::new();$modeLabel.Text='Playback';$modeLabel.Margin='0,12,0,6';[void]$script:stimEnabledCheck.Parent.Children.Add($modeLabel)
    $script:stimModeBox=[Windows.Controls.ComboBox]::new();$script:stimModeBox.SelectedValuePath='Tag'
    foreach($option in @(@('Play library sound','sound'),@('Pause instead of sound','pause'),@('Pause when viewer information is missing','pause_without_user'),@('Pause when viewer information is available','pause_with_user'))){$item=[Windows.Controls.ComboBoxItem]::new();$item.Content=$option[0];$item.Tag=$option[1];[void]$script:stimModeBox.Items.Add($item)}
    $modeBinding=[Windows.Data.Binding]::new('PlaybackMode');$modeBinding.Mode='TwoWay';[void]$script:stimModeBox.SetBinding([Windows.Controls.Primitives.Selector]::SelectedValueProperty,$modeBinding);[void]$script:stimEnabledCheck.Parent.Children.Add($script:stimModeBox)
    $pauseLabel=[Windows.Controls.TextBlock]::new();$pauseLabel.Text='Pause duration (seconds, 0.1-60)';$pauseLabel.Margin='0,8,0,6';[void]$script:stimEnabledCheck.Parent.Children.Add($pauseLabel)
    $script:stimPauseBox=[Windows.Controls.TextBox]::new();$pauseBinding=[Windows.Data.Binding]::new('PauseSeconds');$pauseBinding.Mode='TwoWay';$pauseBinding.UpdateSourceTrigger='PropertyChanged';[void]$script:stimPauseBox.SetBinding([Windows.Controls.TextBox]::TextProperty,$pauseBinding);[void]$script:stimEnabledCheck.Parent.Children.Add($script:stimPauseBox)
    $script:stimModeBox.Add_SelectionChanged({$script:stimPauseBox.IsEnabled=($script:stimModeBox.SelectedValue -ne 'sound')})
    $script:stimOutputBox=$view.FindName('StimOutput')
    $script:stimOutputBox.Add_SelectionChanged({if(-not $script:stimOutputRefreshing -and $script:stimLibraryGrid.SelectedItem -and $script:stimOutputBox.SelectedItem){$script:stimLibraryGrid.SelectedItem.OutputDevice=[string]$script:stimOutputBox.SelectedItem;Update-GlobalSaveGroup 'Audio Stims'}})
    foreach($grid in @($script:stimLibraryGrid,$script:stimFilesGrid)){
        foreach($column in $grid.Columns){
            if($column -is [Windows.Controls.DataGridTextColumn]){
                $column.ElementStyle=$window.FindResource('GridText')
                $editStyle=[Windows.Style]::new([Windows.Controls.TextBox],$window.FindResource([Windows.Controls.TextBox]))
                $editStyle.Setters.Add([Windows.Setter]::new([Windows.Controls.Control]::PaddingProperty,[Windows.Thickness]::new(16,0,16,0)))
                $editStyle.Setters.Add([Windows.Setter]::new([Windows.FrameworkElement]::MinWidthProperty,0.0))
                $editStyle.Setters.Add([Windows.Setter]::new([Windows.FrameworkElement]::MinHeightProperty,32.0))
                $editStyle.Setters.Add([Windows.Setter]::new([Windows.FrameworkElement]::HeightProperty,34.0))
                $editStyle.Setters.Add([Windows.Setter]::new([Windows.FrameworkElement]::MarginProperty,[Windows.Thickness]::new(4,0,4,0)))
                $editStyle.Setters.Add([Windows.Setter]::new([Windows.FrameworkElement]::HorizontalAlignmentProperty,[Windows.HorizontalAlignment]::Stretch))
                $editStyle.Setters.Add([Windows.Setter]::new([Windows.FrameworkElement]::VerticalAlignmentProperty,[Windows.VerticalAlignment]::Center))
                $column.EditingElementStyle=$editStyle
            }
        }
    }
    $fileStyle=[Windows.Style]::new([Windows.Controls.TextBlock],$window.FindResource('GridText'))
    $fileStyle.Setters.Add([Windows.Setter]::new([Windows.FrameworkElement]::ToolTipProperty,[Windows.Data.Binding]::new('Path')))
    $fileStyle.Setters.Add([Windows.Setter]::new([Windows.Controls.TextBlock]::TextTrimmingProperty,[Windows.TextTrimming]::CharacterEllipsis))
    $script:stimFilesGrid.Columns[1].ElementStyle=$fileStyle
    $checkStyle=[Windows.Style]::new([Windows.Controls.CheckBox],$window.FindResource([Windows.Controls.CheckBox]))
    $checkStyle.Setters.Add([Windows.Setter]::new([Windows.FrameworkElement]::MarginProperty,[Windows.Thickness]::new(18,0,0,0)))
    $checkStyle.Setters.Add([Windows.Setter]::new([Windows.FrameworkElement]::HorizontalAlignmentProperty,[Windows.HorizontalAlignment]::Left))
    $checkStyle.Setters.Add([Windows.Setter]::new([Windows.FrameworkElement]::VerticalAlignmentProperty,[Windows.VerticalAlignment]::Center))
    $script:stimFilesGrid.Columns[0].ElementStyle=$checkStyle;$script:stimFilesGrid.Columns[0].EditingElementStyle=$checkStyle
    $script:stimLibraryGrid.Add_SelectionChanged({$script:stimIdentityLoading=$true;try{$script:stimView.FindName('Editor').DataContext=$script:stimLibraryGrid.SelectedItem;$script:stimView.FindName('Editor').IsEnabled=($null -ne $script:stimLibraryGrid.SelectedItem);Refresh-AudioStimOutputs;Show-AudioStimAction}finally{$script:stimIdentityLoading=$false}})
    $view.FindName('Add').Add_Click({Show-AudioStimEditor -New})
    $view.FindName('Delete').Add_Click({$row=$script:stimLibraryGrid.SelectedItem;if($row){[void]$script:stimLibraryGrid.ItemsSource.Remove($row);Update-GlobalSaveGroup 'Audio Stims'}})
    $view.FindName('Files').Add_Click({$picker=[Microsoft.Win32.OpenFileDialog]::new();$picker.Multiselect=$true;$picker.Filter='Audio files|*.wav;*.mp3;*.ogg;*.flac';$owner=if($script:stimEditorWindow){$script:stimEditorWindow}else{$window};if($picker.ShowDialog($owner)){Add-AudioStimFiles $picker.FileNames}})
    $view.FindName('Folder').Add_Click({try{$folder=Select-YapLoqFolder 'Add a sound folder';if($folder){Add-AudioStimFiles @(Get-ChildItem -LiteralPath $folder -File | Select-Object -ExpandProperty FullName)}}catch{$script:stimView.FindName('Status').Text=$_.Exception.Message}})
    $view.FindName('RemoveFile').Add_Click({$row=$script:stimLibraryGrid.SelectedItem;$file=$script:stimFilesGrid.SelectedItem;if($row -and $file){[void]$row.Files.Remove($file);Update-GlobalSaveGroup 'Audio Stims'}})
    $view.FindName('Preview').Add_Click({try{$file=$script:stimFilesGrid.SelectedItem;$row=$script:stimLibraryGrid.SelectedItem;if($file -and $row){$draft=Get-AudioStimDraft;[void](Invoke-BridgePost '/api/stims/preview' @{keyword=$row.Keyword.Trim();path=$file.Path;volume=([double]$file.Volume/100);output_device=(Get-AudioStimPreviewOutput)});$script:stimView.FindName('Status').Text='Preview queued.'}}catch{$script:stimView.FindName('Status').Text=$_.Exception.Message}})
    $view.FindName('Random').Add_Click({try{$row=$script:stimLibraryGrid.SelectedItem;if($row){$draft=Get-AudioStimDraft;$result=(Invoke-BridgePost '/api/stims/preview' @{keyword=$row.Keyword.Trim();library=$draft[$row.Keyword.Trim()];output_device=(Get-AudioStimPreviewOutput)}).result;$script:stimView.FindName('Status').Text='Random preview: '+[IO.Path]::GetFileName([string]$result.file)}}catch{$script:stimView.FindName('Status').Text=$_.Exception.Message}})
    Install-AudioStimActionPicker
    Install-AudioStimContextMenus
    Install-AudioStimDesign
    Refresh-AudioStims
}

function script:Get-AudioStimPreviewOutput {
    $device=[string]$script:stimOutputBox.SelectedItem
    if($device -eq '[Same as TTS output]'){return ''}
    return $device
}
function script:Invoke-AudioStimMenu([string]$command){
    $row=$script:stimLibraryGrid.SelectedItem;$file=$script:stimFilesGrid.SelectedItem
    switch($command){
        'toggle-file' {if($file){$file.Enabled=-not $file.Enabled;$script:stimFilesGrid.Items.Refresh();Update-GlobalSaveGroup 'Audio Stims'}}
        'reset-file' {if($file){$file.Volume=100.0;$file.Weight=1.0;$script:stimFilesGrid.Items.Refresh();Update-GlobalSaveGroup 'Audio Stims'}}
        'copy-path' {if($file){[Windows.Clipboard]::SetText([string]$file.Path)}}
        'toggle-library' {if($row){$row.Enabled=-not $row.Enabled;$script:stimEnabledCheck.IsChecked=$row.Enabled;Update-GlobalSaveGroup 'Audio Stims'}}
        'rename' {if($row){Show-AudioStimEditor}}
        default {$button=$script:stimView.FindName($command);if($button){$button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))}}
    }
}
function script:Install-AudioStimContextMenus {
    foreach($spec in @(@($script:stimLibraryGrid,'library'),@($script:stimFilesGrid,'file'))){
        $grid=$spec[0];$kind=$spec[1];$menu=[Windows.Controls.ContextMenu]::new();$menu.Tag=$kind
        $entries=if($kind -eq 'file'){@(@('Preview','Preview'),@('Test random','Random'),@('Enable / disable sound','toggle-file'),@('Reset volume and weight','reset-file'),@('Copy full path','copy-path'),@('Remove from library','RemoveFile'),@('Add files...','Files'),@('Add folder...','Folder'))}else{@(@('Add stim','Add'),@('Rename','rename'),@('Test random','Random'),@('Enable / disable stim','toggle-library'),@('Delete stim','Delete'))}
        foreach($entry in $entries){$item=[Windows.Controls.MenuItem]::new();$item.Header=$entry[0];$item.Tag=$entry[1];$item.Add_Click({param($sender,$e)Invoke-AudioStimMenu ([string]$sender.Tag)});[void]$menu.Items.Add($item)}
        $menu.Add_Opened({param($sender,$e)
            foreach($item in $sender.Items){$item.IsEnabled=if($item.Tag -eq 'Add'){$true}elseif($sender.Tag -eq 'file' -and $item.Tag -in @('Preview','toggle-file','reset-file','copy-path','RemoveFile')){$null -ne $script:stimFilesGrid.SelectedItem}else{$null -ne $script:stimLibraryGrid.SelectedItem}}
        })
        $grid.ContextMenu=$menu
        $grid.Add_PreviewMouseRightButtonDown({param($sender,$e)
            $container=[Windows.Controls.ItemsControl]::ContainerFromElement($sender,$e.OriginalSource)
            if($container -is [Windows.Controls.DataGridRow]){$sender.SelectedItem=$container.Item}else{$sender.SelectedItem=$null}
        })
    }
}

function script:Show-AudioStimAction {
    $d=$script:stimView;$row=$script:stimLibraryGrid.SelectedItem
    $d.Resources['FilteringActions']=$true
    try{
        $d.Resources.Remove('ActionTargetId');$d.Resources['ActionMissing']=$false
        $value=if($row){[string]$row.Action}else{''}
        $match=@($script:automationRemoteActions|Where-Object {$_.id -eq $value})[0]
        if($match){$d.Resources['ActionTargetId']=$match.id;$value=$match.name}
        $script:stimActionBox.Text=$value;$d.Resources['ActionTargetText']=$value
    }finally{$d.Resources['FilteringActions']=$false}
    Update-AutomationActionSearch $d
}
function script:Install-AudioStimActionPicker {
    $d=$script:stimView
    $cache=Join-Path $configDir 'streamerbot-actions-cache.json'
    if(-not $script:automationRemoteActions -and (Test-Path -LiteralPath $cache)){try{$script:automationRemoteActions=@(ConvertTo-AutomationActionList (Get-Content -LiteralPath $cache -Raw|ConvertFrom-Json))}catch{}}
    $script:stimActionSearchTimer=[Windows.Threading.DispatcherTimer]::new();$script:stimActionSearchTimer.Interval=[TimeSpan]::FromMilliseconds(140)
    $script:stimActionSearchTimer.Add_Tick({param($sender,$e)$sender.Stop();Update-AutomationActionSearch $script:stimView;if($script:stimActionBox.IsKeyboardFocusWithin){$script:stimActionBox.IsDropDownOpen=$true}})
    $script:stimActionBox.AddHandler([Windows.Controls.TextBox]::TextChangedEvent,[Windows.Controls.TextChangedEventHandler]{
        $d=$script:stimView;if($d.Resources['FilteringActions']){return};$row=$script:stimLibraryGrid.SelectedItem;if(-not $row){return}
        if($script:stimActionBox.Text -ne $d.Resources['ActionTargetText']){$d.Resources.Remove('ActionTargetId');$d.Resources['ActionMissing']=$false;$row.Action=$script:stimActionBox.Text.Trim();Update-GlobalSaveGroup 'Audio Stims'}
        $script:stimActionSearchTimer.Stop();$script:stimActionSearchTimer.Start()
    })
    $script:stimActionBox.Add_SelectionChanged({param($sender,$e)
        $d=$script:stimView;$row=$script:stimLibraryGrid.SelectedItem;if($d.Resources['FilteringActions'] -or -not $sender.SelectedItem -or -not $row){return}
        $d.Resources['ActionTargetId']=[string]$sender.SelectedItem.id;$d.Resources['ActionTargetText']=[string]$sender.SelectedItem.name;$row.Action=[string]$sender.SelectedItem.id;Update-GlobalSaveGroup 'Audio Stims'
    })
    $script:stimActionBox.Add_DropDownOpened({Start-AudioStimActionLoad})
    $script:yaploqPages.stims.Add_IsVisibleChanged({param($sender,$e)if($sender.IsVisible){Start-AudioStimActionLoad}})
}
function script:Start-AudioStimActionLoad {
    $d=$script:stimView;if($d.Resources['RemoteTask']){return}
    $client=[Net.WebClient]::new();$client.Proxy=$null;$d.Resources['RemoteClient']=$client
    $d.Resources['RemoteTask']=$client.DownloadStringTaskAsync([uri]((Get-BridgeBaseUri)+'/api/automations/actions'))
    $timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[TimeSpan]::FromMilliseconds(100);$d.Resources['RemoteTimer']=$timer
    $timer.Add_Tick({param($sender,$e)$d=$script:stimView;$task=$d.Resources['RemoteTask'];if(-not $task.IsCompleted){return};$sender.Stop()
        try{$script:automationRemoteActions=@(ConvertTo-AutomationActionList (($task.GetAwaiter().GetResult()|ConvertFrom-Json).result));Show-AudioStimAction;$d.FindName('StepStatus').Text=''}catch{$d.FindName('StepStatus').Text='Could not refresh actions. Saved choices and exact names or IDs still work.'}finally{$d.Resources['RemoteClient'].Dispose();$d.Resources.Remove('RemoteTask')}
    });$timer.Start()
}
