function Copy-StreamerBotPack {
    try{
        $saved=Read-Settings
        if(-not $saved.enable_udp){throw 'Enable the UDP listener in Connection first.'}
        if([int]$UdpBox.Text -ne [int]$saved.udp_port){throw 'Save the UDP port and restart YapLoq before copying.'}
        $result=Invoke-BridgePost '/api/maintenance/streamerbot-pack' @{preset='complete'}
        $path=[string]$result.result.path
        $code=Get-Content -LiteralPath $path -Raw -Encoding UTF8
        [Windows.Clipboard]::SetText($code);$script:streamerPackCode.Text=$code
        $script:streamerPackStatus.Text='Copied. Paste into Streamer.Bot > Import > Import String.'
        $script:streamerPackStatus.ToolTip=$path
        $BottomStatus.Text='Import code copied'
    }catch{$script:streamerPackStatus.Text=$_.Exception.Message;$BottomStatus.Text=$_.Exception.Message}
}

function Install-StreamerBotPack {
    $page=[Windows.Controls.ScrollViewer]::new();$page.VerticalScrollBarVisibility='Auto';$page.Visibility='Collapsed';$page.Margin='0,0,8,0'
    [Windows.Controls.Grid]::SetRow($page,2);[void]$script:shellContent.Children.Add($page)
    $stack=[Windows.Controls.StackPanel]::new();$page.Content=$stack
    $card=[Windows.Controls.Border]::new();$card.BorderBrush=$window.FindResource('Border');$card.BorderThickness=1;$card.CornerRadius=12;$card.Padding=20
    $card.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#1E1A27')
    $body=[Windows.Controls.StackPanel]::new();$card.Child=$body;[void]$stack.Children.Add($card)
    foreach($spec in @(@('Import actions',20),@('One import for Twitch, YouTube and Kick.',12),@('Copy the code, then paste it into Streamer.Bot > Import.',12))){
        $text=[Windows.Controls.TextBlock]::new();$text.Text=$spec[0];$text.FontSize=$spec[1];$text.TextWrapping='Wrap';$text.Margin='0,0,0,12';[void]$body.Children.Add($text)
    }
    $button=[Windows.Controls.Button]::new();$button.Content='Copy import code';$button.Style=$window.FindResource('PrimaryButton');$button.HorizontalAlignment='Left';$button.Margin='0,4,0,12';$button.Add_Click({Copy-StreamerBotPack});$script:streamerPackCopyButton=$button;[void]$body.Children.Add($button)
    $script:streamerPackStatus=[Windows.Controls.TextBlock]::new();$script:streamerPackStatus.TextWrapping='Wrap';$script:streamerPackStatus.Foreground=$window.FindResource('Accent');[void]$body.Children.Add($script:streamerPackStatus)
    $help=[Windows.Controls.TextBlock]::new();$help.Text='Commands and permissions are included. Add chat triggers only if you want automatic chat speech.';$help.TextWrapping='Wrap';$help.Foreground=$window.FindResource('Muted');$help.Margin='0,12,0,12';[void]$body.Children.Add($help)
    $expander=[Windows.Controls.Expander]::new();$expander.Header='Import code';$expander.Style=$window.FindResource('SettingsExpander')
    $script:streamerPackCode=[Windows.Controls.TextBox]::new();$script:streamerPackCode.IsReadOnly=$true;$script:streamerPackCode.Tag='Your import code appears here after copying';$script:streamerPackCode.Height=120;$script:streamerPackCode.TextWrapping='Wrap';$script:streamerPackCode.VerticalScrollBarVisibility='Auto';$expander.Content=$script:streamerPackCode;[void]$body.Children.Add($expander)
    $script:yaploqPages['streamerPack']=$page;$script:routeOwners['streamerPack']='Integrations'
    $script:ownerSections.Integrations=@(@('Actions','streamActions','RulesNav'),@('Import pack','streamerPack','StreamerBotNav'),@('Connection','streamerbot','StreamerBotNav'))
    $old=$window.FindName('StreamerExportCard');if($old){$old.Visibility='Collapsed'}
    if($script:assignmentTemplatesCard){$script:assignmentTemplatesCard.Visibility='Collapsed'}
}

function Export-SelectedStreamerBotVoices {
    try{
        $names=@($AliasGrid.SelectedItems|ForEach-Object{[string]$_.Name}|Sort-Object -Unique)
        if(-not $names.Count){throw 'Select one or more voices first.'}
        $saved=Read-Settings
        if(-not $saved.enable_udp){throw 'Enable the UDP listener in Streamer.Bot > Connection first.'}
        if([int]$UdpBox.Text -ne [int]$saved.udp_port){throw 'Save the UDP port and restart YapLoq before exporting.'}
        $result=Invoke-BridgePost '/api/maintenance/streamerbot-voices' @{aliases=$names}
        $path=[string]$result.result.path
        [Windows.Clipboard]::SetText((Get-Content -LiteralPath $path -Raw -Encoding UTF8))
        $BottomStatus.Text='Copied '+$names.Count+' voice action(s). Paste into Streamer.Bot > Import.'
    }catch{$BottomStatus.Text=$_.Exception.Message}
}

function Update-SelectedVoiceExport {
    $count=$AliasGrid.SelectedItems.Count
    $script:voiceExportButton.IsEnabled=$count -gt 0
    $script:voiceExportButton.Content=if($count){'Export voices ('+$count+')'}else{'Export voices'}
    foreach($button in @($EditButton,$RemoveButton,$TestButton,$ToggleFavoriteButton)){if($button){$button.IsEnabled=$count -eq 1}}
}

function Install-SelectedVoiceExport {
    $AliasGrid.SelectionMode='Extended';$AliasGrid.SelectionUnit='FullRow'
    $AliasGrid.ToolTip='Ctrl-click or Shift-click to select multiple voices.'
    $toolbar=$AddButton.Parent
    if($toolbar -is [Windows.Controls.StackPanel]){
        $parent=$toolbar.Parent;$index=$parent.Children.IndexOf($toolbar)
        $wrap=[Windows.Controls.WrapPanel]::new();$wrap.Margin=$toolbar.Margin
        [Windows.Controls.Grid]::SetRow($wrap,[Windows.Controls.Grid]::GetRow($toolbar))
        while($toolbar.Children.Count){$child=$toolbar.Children[0];[void]$toolbar.Children.Remove($child);[void]$wrap.Children.Add($child)}
        [void]$parent.Children.Remove($toolbar);$parent.Children.Insert($index,$wrap);$toolbar=$wrap
    }
    $script:voiceExportButton=[Windows.Controls.Button]::new();$script:voiceExportButton.ToolTip='Export selected voices to Streamer.Bot';$script:voiceExportButton.Add_Click({Export-SelectedStreamerBotVoices})
    [void]$toolbar.Children.Add($script:voiceExportButton)
    $AliasGrid.Add_SelectionChanged({Update-SelectedVoiceExport})
    Update-SelectedVoiceExport
}
