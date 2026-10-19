function Get-ViewerControl([string]$name){$script:viewerPage.FindName($name)}

function Show-AssignmentSection([string]$section){
    if(-not $script:assignmentSections){return}
    foreach($key in $script:assignmentSections.Keys){
        $script:assignmentSections[$key].Visibility=if($key -eq $section){'Visible'}else{'Collapsed'}
        $script:assignmentSectionButtons[$key].Style=$window.FindResource($(if($key -eq $section){'PrimaryButton'}else{[Windows.Controls.Button]}))
    }
    $script:assignmentSection=$section
    if($script:assignmentRulesSave){$script:assignmentRulesSave.Visibility=if($section -eq 'Rules' -and -not $script:globalSaveInstalled){'Visible'}else{'Collapsed'}}
}

function Save-AssignmentRules {
    try{
        $settings=Read-Settings;$users=[ordered]@{};$roles=[ordered]@{}
        foreach($entry in @($VoiceRulesGrid.ItemsSource)){
            if(-not $entry -or -not ([string]$entry.value).Trim() -or -not ([string]$entry.alias).Trim()){continue}
            if($entry.field -eq 'role'){$roles[$entry.value]=$entry.alias}else{$users[$entry.value]=$entry.alias}
        }
        Set-JsonProperty $settings 'user_voice_rules' ([pscustomobject]$users)
        Set-JsonProperty $settings 'role_voice_rules' ([pscustomobject]$roles)
        Set-JsonProperty $settings 'routing_rules' @($RoutingGrid.ItemsSource)
        Write-Settings $settings;$BottomStatus.Text='Assignment rules saved'
    }catch{$BottomStatus.Text=$_.Exception.Message}
}

function Save-AssignmentDefault {
    try{
        $selector=[string]$script:assignmentDefaultPicker.SelectedItem
        if(-not $selector){throw 'Choose a default voice.'}
        if($selector -eq 'Automatic (first enabled voice)'){$selector=''}
        $settings=Read-Settings;Set-JsonProperty $settings 'assignment_default_voice' $selector
        Write-Settings $settings;$script:assignmentDefaultStatus.Text='Default voice saved'
    }catch{$script:assignmentDefaultStatus.Text=$_.Exception.Message}
}

function Save-ViewerCommands {
    try{
        $settings=Read-Settings
        Set-JsonProperty $settings 'viewer_commands_enabled' ([bool]$script:viewerCommandsEnabled.IsChecked)
        Write-Settings $settings
        $script:viewerCommandsStatus.Text='Viewer command setting saved.'
    }catch{$script:viewerCommandsStatus.Text=$_.Exception.Message}
}

function Copy-ViewerCommandAction {
    try{
        $settings=Read-Settings
        if(-not $settings.enable_udp){throw 'Enable the Streamer.Bot UDP listener and save its connection first.'}
        $platform=[string]$script:viewerTemplatePlatform.SelectedValue
        $result=Invoke-BridgePost '/api/maintenance/viewer-command-export' @{platform=$platform}
        [Windows.Clipboard]::SetText((Get-Content -LiteralPath ([string]$result.result.path) -Raw -Encoding UTF8))
        $script:viewerCommandsStatus.Text='Templates copied. Import in Streamer.Bot. Attach your Starts With !voice command to Viewer voice command, and a separate speech command (such as !say) to Speak using viewer assignment. Configure success/failure replies in YapLoq Actions.'
    }catch{$script:viewerCommandsStatus.Text=$_.Exception.Message}
}

function Update-AssignmentDefaultChoices {
    if(-not $script:assignmentDefaultPicker){return}
    $previous=[string]$script:assignmentDefaultPicker.SelectedItem;$settings=Read-Settings
    $choices=@('Automatic (first enabled voice)','random')+@($PlayVoiceList.Tag|Where-Object{$_ -and $_.Name}|ForEach-Object{$_.Name})+@($settings.voice_playlists.PSObject.Properties.Name|Where-Object{$_}|ForEach-Object{'playlist:'+$_})
    $saved=[string]$settings.assignment_default_voice
    if($saved -and $saved -notin $choices){$choices+= $saved}
    $script:assignmentDefaultPicker.ItemsSource=$choices
    $script:assignmentDefaultPicker.SelectedItem=if($previous -and $previous -in $choices){$previous}elseif($saved){$saved}else{'Automatic (first enabled voice)'}
}

function Set-MessageViewerDefault($row){
    if(-not $row.Platform -or -not $row.UserId){throw 'This message has no stable viewer identity. Send platform and userId with speech requests.'}
    [void](Invoke-BridgePost '/api/viewers/set' @{platform=[string]$row.Platform;userId=[string]$row.UserId;displayName=[string]$row.DisplayName;login=[string]$row.User;voice=[string]$row.Alias})
    $BottomStatus.Text='Viewer default set to '+$row.Alias
}

function Set-ViewerSearch {
    $list=Get-ViewerControl 'ViewerList';if(-not $list.ItemsSource){return}
    $view=[Windows.Data.CollectionViewSource]::GetDefaultView($list.ItemsSource)
    $view.Filter=[Predicate[object]]{param($entry)
        $needle=(Get-ViewerControl 'ViewerSearch').Text
        return ((@($entry.displayName,$entry.login,$entry.platform,$entry.userId,$entry.voice) -join ' ').IndexOf($needle,[StringComparison]::OrdinalIgnoreCase) -ge 0)
    }
}

function Show-ViewerDraft($entry){
    foreach($spec in @(@('ViewerId','userId'),@('ViewerName','displayName'))){(Get-ViewerControl $spec[0]).Text=if($entry){[string]$entry.($spec[1])}else{''}}
    $platform=Get-ViewerControl 'ViewerPlatform'
    if($entry -and $entry.platform -notin @($platform.Items|ForEach-Object{$_.Tag})){
        $saved=[Windows.Controls.ComboBoxItem]::new();$saved.Content=[string]$entry.platform+' (saved)';$saved.Tag=[string]$entry.platform;[void]$platform.Items.Add($saved)
    }
    $platform.SelectedValue=if($entry){[string]$entry.platform}else{''}
    $platform.IsEnabled=-not [bool]$entry
    (Get-ViewerControl 'ViewerId').IsReadOnly=[bool]$entry
    (Get-ViewerControl 'ViewerReset').IsEnabled=[bool]$entry
    (Get-ViewerControl 'ViewerVoice').SelectedValue=if($entry){[string]$entry.voice}else{''}
    if($entry){(Get-ViewerControl 'ViewerStatus').Text=if($entry.warning){$entry.warning+' — choose another voice or reset.'}else{$entry.assignmentOrigin}}
}

function Apply-ViewerList($result){
    $list=Get-ViewerControl 'ViewerList';$old=$list.SelectedItem
    $choices=@([pscustomobject]@{Label='Use rules / default';Value=''})
    foreach($voice in $result.voices){$choices+=[pscustomobject]@{Label=[string]$voice;Value=[string]$voice}}
    foreach($entry in $result.viewers){
        $entry|Add-Member NoteProperty voiceLabel $(if($entry.voice){$entry.voice}else{'Default'}) -Force
        $entry|Add-Member NoteProperty status $(if(-not $entry.available){'Unavailable'}elseif($entry.voice){'Assigned'}else{'Default'}) -Force
        if($entry.voice -and $entry.voice -notin $choices.Value){$choices+=[pscustomobject]@{Label=$entry.voice+' (unavailable)';Value=$entry.voice}}
    }
    (Get-ViewerControl 'ViewerVoice').ItemsSource=$choices
    $list.ItemsSource=@($result.viewers);Set-ViewerSearch
    $selected=@($result.viewers|Where-Object{$old -and $_.platform -eq $old.platform -and $_.userId -ceq $old.userId})[0]
    $list.SelectedItem=$selected;Show-ViewerDraft $selected
    if(-not $selected){(Get-ViewerControl 'ViewerStatus').Text='Viewers with a platform and user ID appear here when they send speech. You can also add one manually.'}
}

function Start-ViewerLoad {
    if($script:viewerLoadTask){return}
    $script:viewerLoadClient=[Net.WebClient]::new();$script:viewerLoadClient.Proxy=$null
    $script:viewerLoadTask=$script:viewerLoadClient.DownloadStringTaskAsync([uri]((Get-BridgeBaseUri)+'/api/viewers'))
    $timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[TimeSpan]::FromMilliseconds(100)
    $timer.Add_Tick({param($sender,$e)
        if(-not $script:viewerLoadTask.IsCompleted){return};$sender.Stop()
        try{Apply-ViewerList (($script:viewerLoadTask.GetAwaiter().GetResult()|ConvertFrom-Json).result)}catch{(Get-ViewerControl 'ViewerStatus').Text='Could not load viewers. Check the playback connection, then press Refresh.'}
        finally{$script:viewerLoadClient.Dispose();$script:viewerLoadTask=$null}
    });$timer.Start()
}

function Save-ViewerAssignment([bool]$reset=$false){
    try{
        $platform=[string](Get-ViewerControl 'ViewerPlatform').SelectedValue
        if(-not $platform){throw 'Choose a platform from the dropdown.'}
        $body=@{platform=$platform;userId=(Get-ViewerControl 'ViewerId').Text;displayName=(Get-ViewerControl 'ViewerName').Text;voice=$(if($reset){''}else{(Get-ViewerControl 'ViewerVoice').SelectedValue})}
        [void](Invoke-BridgePost '/api/viewers/set' $body)
        (Get-ViewerControl 'ViewerStatus').Text='Viewer assignment saved in the app data folder.'
        Start-ViewerLoad
    }catch{(Get-ViewerControl 'ViewerStatus').Text=$_.Exception.Message}
}

function Install-YapLoqViewers {
    $script:viewerPage=Load-Xaml (Join-Path $resourceRoot 'assets\Viewers.xaml')
    $page=[Windows.Controls.Grid]::new();$page.Visibility='Collapsed'
    $headerRow=[Windows.Controls.RowDefinition]::new();$headerRow.Height='Auto';[void]$page.RowDefinitions.Add($headerRow);[void]$page.RowDefinitions.Add([Windows.Controls.RowDefinition]::new())
    [Windows.Controls.Grid]::SetRow($page,2);[void]$script:shellContent.Children.Add($page)
    $header=[Windows.Controls.WrapPanel]::new();$header.Margin='0,0,0,12';[void]$page.Children.Add($header)
    $rules=$script:yaploqPages['routing'];[void]$script:shellContent.Children.Remove($rules);[void]$script:yaploqPages.Remove('routing')
    foreach($oldSave in @($rules.Content.Children|Where-Object{$_ -is [Windows.Controls.Button]})){[void]$rules.Content.Children.Remove($oldSave)}
    $defaults=[Windows.Controls.StackPanel]::new();$defaults.Margin='0,0,8,0'
    $label=[Windows.Controls.TextBlock]::new();$label.Text='Default voice';$label.FontWeight='SemiBold';$label.Margin='0,0,0,8';[void]$defaults.Children.Add($label)
    $script:assignmentDefaultPicker=[Windows.Controls.ComboBox]::new();$script:assignmentDefaultPicker.Margin='0,0,0,12';[void]$defaults.Children.Add($script:assignmentDefaultPicker)
    $save=[Windows.Controls.Button]::new();$save.Content='Save default';$save.Style=$window.FindResource('PrimaryButton');$save.HorizontalAlignment='Left';$save.Add_Click({Save-AssignmentDefault});[void]$defaults.Children.Add($save)
    $script:assignmentDefaultStatus=[Windows.Controls.TextBlock]::new();$script:assignmentDefaultStatus.Text='Used when no explicit voice, viewer preference or rule chooses a voice. Unavailable assignments fall back to the first enabled voice.';$script:assignmentDefaultStatus.TextWrapping='Wrap';$script:assignmentDefaultStatus.Margin='0,12,0,0';[void]$defaults.Children.Add($script:assignmentDefaultStatus)
    $commands=[Windows.Controls.StackPanel]::new();$commands.Margin='0,0,8,0'
    $script:viewerCommandsEnabled=[Windows.Controls.CheckBox]::new();$script:viewerCommandsEnabled.Content='Allow viewer !voice commands';$script:viewerCommandsEnabled.IsChecked=((Read-Settings).viewer_commands_enabled -eq $true);$script:viewerCommandsEnabled.Margin='0,0,0,16';[void]$commands.Children.Add($script:viewerCommandsEnabled)
    $help=[Windows.Controls.TextBlock]::new();$help.Text='Viewers can use !voice to list public voices, !voice name to choose, !voice random, or !voice reset. Make voices public and choose their audience in the voice editor. Private voices remain available to your own actions.';$help.TextWrapping='Wrap';$help.Margin='0,0,0,16';[void]$commands.Children.Add($help)
    $commandButtons=[Windows.Controls.WrapPanel]::new();[void]$commands.Children.Add($commandButtons)
    $saveCommands=[Windows.Controls.Button]::new();$saveCommands.Content='Save commands';$saveCommands.Style=$window.FindResource('PrimaryButton');$saveCommands.Margin='0,0,8,0';$saveCommands.Add_Click({Save-ViewerCommands});[void]$commandButtons.Children.Add($saveCommands)
    $script:viewerTemplatePlatform=[Windows.Controls.ComboBox]::new();$script:viewerTemplatePlatform.SelectedValuePath='Tag';$script:viewerTemplatePlatform.MinWidth=150;$script:viewerTemplatePlatform.Margin='0,0,8,0'
    foreach($spec in @(@('Twitch','twitch'),@('YouTube','youtube'),@('Kick','kick'),@('Event platform',''))){$option=[Windows.Controls.ComboBoxItem]::new();$option.Content=$spec[0];$option.Tag=$spec[1];[void]$script:viewerTemplatePlatform.Items.Add($option)}
    $script:viewerTemplatePlatform.SelectedIndex=0;[void]$commandButtons.Children.Add($script:viewerTemplatePlatform)
    $copyCommands=[Windows.Controls.Button]::new();$copyCommands.Content='Copy Streamer.Bot templates';$copyCommands.Margin='0,0,8,0';$copyCommands.Add_Click({Copy-ViewerCommandAction});[void]$commandButtons.Children.Add($copyCommands)
    $openActions=[Windows.Controls.Button]::new();$openActions.Content='Set up result actions';$openActions.Add_Click({Set-Page 'streamActions'});[void]$commandButtons.Children.Add($openActions)
    $script:viewerCommandsStatus=[Windows.Controls.TextBlock]::new();$script:viewerCommandsStatus.Text='Templates forward platform, user ID, name and audience flags from the event. Use Viewer voice set successfully, Viewer voice command failed, reset or list events in Streamer.Bot > Actions. Pass {ttsReply}, {ttsPlatform} and {ttsUserId} to your reply action. Import does not create triggers or send chat replies automatically.';$script:viewerCommandsStatus.TextWrapping='Wrap';$script:viewerCommandsStatus.Margin='0,16,0,0';[void]$commands.Children.Add($script:viewerCommandsStatus)
    $script:assignmentSections=@{Viewers=$script:viewerPage;Rules=$rules;'Default voice'=$defaults;'Viewer commands'=$commands};$script:assignmentSectionButtons=@{}
    foreach($name in @('Viewers','Rules','Default voice','Viewer commands')){
        $body=$script:assignmentSections[$name];[Windows.Controls.Grid]::SetRow($body,1);[void]$page.Children.Add($body)
        $button=[Windows.Controls.Button]::new();$button.Content=$name;$button.Tag=$name;$button.Margin='0,0,8,0';$button.Add_Click({param($sender,$e)Show-AssignmentSection $sender.Tag});$script:assignmentSectionButtons[$name]=$button;[void]$header.Children.Add($button)
    }
    $script:assignmentRulesSave=[Windows.Controls.Button]::new();$script:assignmentRulesSave.Content='Save assignment rules';$script:assignmentRulesSave.Style=$window.FindResource('PrimaryButton');$script:assignmentRulesSave.Margin='12,0,0,0';$script:assignmentRulesSave.Add_Click({Save-AssignmentRules});[void]$header.Children.Add($script:assignmentRulesSave)
    foreach($grid in @($RoutingGrid,$VoiceRulesGrid)){
        $grid.Add_SizeChanged({param($sender,$e)
            if($sender.ActualWidth -gt 0){$fixed=0;for($i=0;$i -lt $sender.Columns.Count;$i++){if($i -notin @(1,2)){$fixed+=$sender.Columns[$i].Width.Value}}
                $space=[Math]::Max(240,$sender.ActualWidth-$fixed-40);$sender.Columns[1].Width=[Windows.Controls.DataGridLength]::new($space*0.45);$sender.Columns[2].Width=[Windows.Controls.DataGridLength]::new($space*0.55)
            }
        })
    }
    $script:yaploqPages['assignments']=$page;$script:routeOwners['assignments']='Voices'
    $sections=@($script:ownerSections.Voices|Where-Object{$_[1] -ne 'routing'});$script:ownerSections.Voices=@($sections[0],@('Assignments','assignments','VoicesNav'))+@($sections|Select-Object -Skip 1)
    $routingLabel=$window.FindName('RoutingExpander').Header.Children[1];$routingLabel.Text='Conditional rules'
    $window.FindName('RoutingExpander').IsExpanded=$true
    $window.FindName('AutoVoiceRulesExpander').Header.Children[1].Text='Name and role defaults'
    Update-AssignmentDefaultChoices
    Show-AssignmentSection 'Viewers'
    (Get-ViewerControl 'ViewerSave').Style=$window.FindResource('PrimaryButton')
    $picker=Get-ViewerControl 'ViewerVoice';$picker.DisplayMemberPath=''
    $picker.ItemTemplate=[Windows.Markup.XamlReader]::Parse('<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><TextBlock Text="{Binding Label}" TextTrimming="CharacterEllipsis"/></DataTemplate>')
    (Get-ViewerControl 'ViewerList').Add_SizeChanged({param($sender,$e)
        if($sender.ActualWidth -gt 0){$space=[Math]::Max(260,$sender.ActualWidth-355);$sender.Columns[0].Width=[Windows.Controls.DataGridLength]::new($space*0.45);$sender.Columns[3].Width=[Windows.Controls.DataGridLength]::new($space*0.55)}
    })
    foreach($column in (Get-ViewerControl 'ViewerList').Columns){$column.ElementStyle=$window.FindResource('GridText')}
    (Get-ViewerControl 'ViewerSearch').Add_TextChanged({Set-ViewerSearch})
    (Get-ViewerControl 'ViewerList').Add_SelectionChanged({Show-ViewerDraft (Get-ViewerControl 'ViewerList').SelectedItem})
    (Get-ViewerControl 'ViewerNew').Add_Click({(Get-ViewerControl 'ViewerList').SelectedItem=$null;Show-ViewerDraft $null;(Get-ViewerControl 'ViewerPlatform').Focus()|Out-Null})
    (Get-ViewerControl 'ViewerSave').Add_Click({Save-ViewerAssignment})
    (Get-ViewerControl 'ViewerReset').Add_Click({Save-ViewerAssignment $true})
    $RefreshButton.Add_Click({if($script:activePage -eq 'assignments'){Start-ViewerLoad}})
    Install-YapLoqItemMenu (Get-ViewerControl 'ViewerList') @(@('Add viewer',(Get-ViewerControl 'ViewerNew'),'global'),@('Reset assignment',(Get-ViewerControl 'ViewerReset')), @('Copy user ID','copy:userId'))
    Show-ViewerDraft $null
}
