# Event-driven pending-edit tracking. Never scan pages from the playback timer.
function script:Get-LiveSettingsDraft {
    $base=Read-Settings
    $oldStatus=$BottomStatus.Text
    $script:liveInvalidSections=@()
    $secrets=@(foreach($entry in $script:credentialFields.Values){[pscustomobject]@{Entry=$entry;Mask=$entry.Mask.Password;Plain=$entry.Plain.Text}})
    $script:globalSaving=$true
    foreach($saved in $secrets){$saved.Entry.Syncing=$true}
    try{
        foreach($group in $script:globalSaveGroups.Values){
            if($group.Key -in @('Actions','Voices')){continue}
            if(-not $group.Dirty){$script:liveValidGroups.Remove($group.Key);continue}
            $fingerprint=Get-GlobalSaveFingerprint $group
            if($script:liveValidGroups.ContainsKey($group.Key) -and $script:liveValidGroups[$group.Key].Fingerprint -eq $fingerprint){continue}
            $script:globalSaveDraft=$base|ConvertTo-Json -Depth 40|ConvertFrom-Json
            $script:globalSaveStaging=$true;$script:globalStageWrites=0
            try{
                & $group.Save
                if($script:globalStageWrites -eq 0){$script:liveInvalidSections+= $group.Key;continue}
                $values=@{}
                foreach($property in $script:globalSaveDraft.PSObject.Properties){
                    $before=$base.PSObject.Properties[$property.Name]
                    if($before -and [object]::Equals($before.Value,$property.Value)){continue}
                    if(-not $before -or $null -eq $property.Value -or $property.Value -is [string] -or $property.Value -is [ValueType] -or (ConvertTo-Json $before.Value -Depth 35 -Compress) -cne (ConvertTo-Json $property.Value -Depth 35 -Compress)){$values[$property.Name]=$property.Value}
                }
                $script:liveValidGroups[$group.Key]=@{Fingerprint=$fingerprint;Values=$values}
            }catch{$script:liveInvalidSections+= $group.Key}finally{$script:globalSaveStaging=$false;$script:globalSaveDraft=$null}
        }
        foreach($group in $script:globalSaveGroups.Values){if($script:liveValidGroups.ContainsKey($group.Key)){foreach($key in $script:liveValidGroups[$group.Key].Values.Keys){Set-JsonProperty $base $key $script:liveValidGroups[$group.Key].Values[$key]}}}
        return $base
    }finally{
        foreach($saved in $secrets){$saved.Entry.Syncing=$true;$saved.Entry.Mask.Password=$saved.Mask;$saved.Entry.Plain.Text=$saved.Plain;$saved.Entry.Syncing=$false}
        $script:globalSaveStaging=$false;$script:globalSaveDraft=$null;$script:globalSaving=$false;$BottomStatus.Text=$oldStatus
    }
}

function script:Queue-LiveSettingsApply {
    if(-not $script:liveSettingsInstalled -or $script:globalSaving -or $script:loadingSettings){return}
    $script:liveSettingsReady=$false;$script:liveSettingsDebounce.Stop();$script:liveSettingsDebounce.Start()
}

function script:Invoke-AfterLiveSettings([scriptblock]$action){
    $script:liveAfterApply=$action
    Queue-LiveSettingsApply
}

function script:New-LiveSettingsClient {return [Net.WebClient]::new()}

function script:Install-LiveSettings {
    $script:liveValidGroups=@{};$script:liveFingerprints=@{};$script:liveSettingsPending=$null
    $script:liveSettingsDebounce=[Windows.Threading.DispatcherTimer]::new();$script:liveSettingsDebounce.Interval=[TimeSpan]::FromMilliseconds(400)
    $script:liveSettingsDebounce.Add_Tick({param($sender,$e)
        $sender.Stop()
        try{
            $draft=Get-LiveSettingsDraft
            $script:liveSettingsPending=(@{settings=$draft}|ConvertTo-Json -Depth 40 -Compress)
            $script:liveSettingsPump.Start()
        }catch{$BottomStatus.Text='Changes remain unsaved; live settings could not be prepared.'}
    })
    $script:liveSettingsPump=[Windows.Threading.DispatcherTimer]::new();$script:liveSettingsPump.Interval=[TimeSpan]::FromMilliseconds(100)
    $script:liveSettingsPump.Add_Tick({param($sender,$e)
        if($script:liveSettingsTask){
            if(-not $script:liveSettingsTask.IsCompleted){return}
            try{
                $result=($script:liveSettingsTask.GetAwaiter().GetResult()|ConvertFrom-Json).result
                $script:liveSettingsReady=$true
                $BottomStatus.Text=if(@($result.restartRequired).Count){'Changes applied where supported. Save and restart for connection/recovery settings.'}elseif(@($result.saveRequired).Count){'Valid settings are active. Save to apply history retention and keep changes.'}else{'Valid settings are active. Save to keep them after restarting.'}
                if($script:liveInvalidSections.Count){$BottomStatus.Text='Needs correction: '+($script:liveInvalidSections -join ', ')+'. Last valid values remain active.'}
                elseif(-not @($script:globalSaveGroups.Values|Where-Object{$_.Dirty}).Count){$BottomStatus.Text='Saved settings are active.'}
            }catch{$script:liveSettingsReady=$false;$script:liveAfterApply=$null;$BottomStatus.Text='Live settings were not applied. Check the app connection; your edits are still available.'}
            finally{$script:liveSettingsClient.Dispose();$script:liveSettingsTask=$null}
        }
        if($script:liveSettingsPending){
            $payload=$script:liveSettingsPending;$script:liveSettingsPending=$null
            $script:liveSettingsClient=New-LiveSettingsClient;$script:liveSettingsClient.Proxy=$null;$script:liveSettingsClient.Encoding=[Text.Encoding]::UTF8;$script:liveSettingsClient.Headers['Content-Type']='application/json'
            $script:liveSettingsTask=$script:liveSettingsClient.UploadStringTaskAsync([uri]((Get-BridgeBaseUri)+'/api/settings/runtime'),'POST',$payload)
        }else{
            $sender.Stop()
            if($script:liveSettingsReady -and -not $script:liveSettingsDebounce.IsEnabled -and $script:liveAfterApply){$callback=$script:liveAfterApply;$script:liveAfterApply=$null;& $callback}
        }
    })
    $menu=[Windows.Controls.ContextMenu]::new()
    $discard=[Windows.Controls.MenuItem]::new();$discard.Header='Discard unsaved changes';$discard.Add_Click({Discard-PendingSettings});[void]$menu.Items.Add($discard);$script:globalSaveButton.ContextMenu=$menu
    $details=[Windows.Controls.MenuItem]::new();$details.Header='Last save details';$details.Add_Click({Show-SaveDetails});[void]$menu.Items.Add($details)
    $HistoryLimitBox.ToolTip='Save to apply retention changes. Lowering this value can remove older history and audio.'
    foreach($name in @('UdpBox','HttpBox','WsBox','EnableUdpCheck','PersistQueueCheck')){$control=$window.FindName($name);if($control){$control.ToolTip='Save and restart YapLoq to apply this connection/recovery setting.'}}
    $script:liveSettingsInstalled=$true
}

function script:Discard-PendingSettings {
    if(-not (Show-AppConfirmation $window 'Restore saved settings and discard the current unsaved edits?' 'Discard changes')){return}
    $script:globalSaving=$true
    try{
        foreach($group in $script:globalSaveGroups.Values){foreach($grid in @($group.Inputs|Where-Object{$_ -is [Windows.Controls.DataGrid]})){[void]$grid.CancelEdit([Windows.Controls.DataGridEditingUnit]::Cell);[void]$grid.CancelEdit([Windows.Controls.DataGridEditingUnit]::Row)}}
        $script:liveValidGroups=@{}
        Refresh-Grid
        Refresh-AudioStims
        $saved=Read-Settings
        $script:assignmentDefaultPicker.SelectedItem=$null;Update-AssignmentDefaultChoices
        $script:chatVoiceTagsAllEnabled.IsChecked=($saved.chat_voice_tags_all_enabled -ne $false)
        $script:splitSpeechSentences.IsChecked=($saved.split_speech_sentences -eq $true)
        $script:viewerCommandsEnabled.IsChecked=($saved.viewer_commands_enabled -eq $true)
        $script:automationRules=@($saved.automations);Refresh-AutomationList (@($script:automationRules)[0])
        foreach($group in $script:globalSaveGroups.Values){Reset-GlobalSaveGroup $group.Key}
    }finally{$script:globalSaving=$false}
    $script:liveSettingsDebounce.Stop();$script:liveSettingsPending='{"reset":true}';$script:liveSettingsPump.Start()
    $BottomStatus.Text='Unsaved edits discarded. Restoring saved active settings.'
}

function script:Show-UnsavedChangesPrompt($owner,[string]$context,[scriptblock]$saveAction=$null){
    $prompt=[Windows.Window]::new();$prompt.Owner=$owner;$prompt.Title='Unsaved changes'
    $prompt.Width=460;$prompt.SizeToContent='Height';$prompt.ResizeMode='NoResize';$prompt.WindowStartupLocation='CenterOwner'
    $prompt.Background=$window.Background;$prompt.Foreground=$window.Foreground
    $prompt.Resources.MergedDictionaries.Add($window.Resources)
    $prompt.FontFamily=$window.FontFamily
    $panel=[Windows.Controls.StackPanel]::new();$panel.Margin=24;$prompt.Content=$panel
    $heading=[Windows.Controls.TextBlock]::new();$heading.Text='Save your changes?';$heading.FontSize=20;$heading.FontWeight='SemiBold';[void]$panel.Children.Add($heading)
    $message=[Windows.Controls.TextBlock]::new();$message.Text=$context;$message.TextWrapping='Wrap';$message.Margin='0,12,0,20';[void]$panel.Children.Add($message)
    $errorText=[Windows.Controls.TextBlock]::new();$errorText.TextWrapping='Wrap';$errorText.Margin='0,0,0,16';$errorText.Visibility='Collapsed';[void]$panel.Children.Add($errorText)
    $prompt.Resources['SaveError']=$errorText;$prompt.Resources['SaveAction']=$saveAction
    $buttons=[Windows.Controls.StackPanel]::new();$buttons.Orientation='Horizontal';$buttons.HorizontalAlignment='Right';[void]$panel.Children.Add($buttons)
    $prompt.Resources['Choice']='Cancel'
    foreach($choice in @('Cancel','Discard','Save')){
        $button=[Windows.Controls.Button]::new();$button.Content=$choice;$button.Tag=$choice;$button.Margin='6,0,0,0'
        if($choice -eq 'Save'){$button.Style=$window.FindResource('PrimaryButton');$button.IsDefault=$true}
        if($choice -eq 'Cancel'){$button.IsCancel=$true}
        $button.Add_Click({
            param($sender,$e)
            $hostWindow=[Windows.Window]::GetWindow($sender)
            try{
                if($sender.Tag -eq 'Save' -and $hostWindow.Resources['SaveAction']){& $hostWindow.Resources['SaveAction']}
                $hostWindow.Resources['Choice']=[string]$sender.Tag;$hostWindow.Close()
            }catch{
                $hostWindow.Resources['SaveError'].Text='Could not save: '+$_.Exception.Message
                $hostWindow.Resources['SaveError'].Visibility='Visible'
            }
        })
        [void]$buttons.Children.Add($button)
    }
    Apply-AppFont $prompt
    [void]$prompt.ShowDialog()
    return [string]$prompt.Resources['Choice']
}

function script:Confirm-GlobalSaveExit {
    if($script:globalSaving){return $false}
    foreach($group in $script:globalSaveGroups.Values){
        foreach($grid in @($group.Inputs|Where-Object{$_ -is [Windows.Controls.DataGrid]})){
            if(-not $grid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Cell,$true) -or -not $grid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Row,$true)){
                $BottomStatus.Text='Finish the highlighted table edit before exiting.';return $false
            }
        }
        Update-GlobalSaveGroup $group.Key
    }
    $dirty=@($script:globalSaveGroups.Values|Where-Object{$_.Dirty})
    if(-not $dirty.Count){return $true}
    $script:exitSaveCompleted=$false
    $choice=Show-UnsavedChangesPrompt $window ('Unsaved changes in '+(($dirty|ForEach-Object{$_.Key}) -join ', ')+'.') {
        Save-AllPendingChanges
        if(@($script:globalSaveGroups.Values|Where-Object{$_.Dirty}).Count){throw $BottomStatus.Text}
        $script:exitSaveCompleted=$true
    }
    if($choice -eq 'Discard'){
        if($script:liveSettingsInstalled){try{[void](Invoke-BridgePost '/api/settings/runtime' @{reset=$true})}catch{$BottomStatus.Text='Could not restore saved active settings. Check the connection before exiting.';return $false}}
        return $true
    }
    if($choice -ne 'Save'){return $false}
    if(-not $script:exitSaveCompleted){Save-AllPendingChanges}
    return -not @($script:globalSaveGroups.Values|Where-Object{$_.Dirty}).Count
}

function script:Install-MainWindowCloseGuard($target){
    $target.Add_Closing({param($sender,$e)
        if($sender.Resources['ExitApproved']){return}
        $e.Cancel=$true
        if($sender.Resources['ExitPending']){return}
        $sender.Resources['ExitPending']=$true
        # A save/prompt can change bindings and focus. Complete the original
        # Closing event first, then issue a fresh close only after success.
        [void]$sender.Dispatcher.BeginInvoke([action]{
            try{
                if(Confirm-GlobalSaveExit){$sender.Resources['ExitApproved']=$true;$script:allowClose=$true;$sender.Close()}
                else{$script:allowClose=$false}
            }catch{$script:allowClose=$false;$BottomStatus.Text='Unable to close: '+$_.Exception.Message}
            finally{$sender.Resources['ExitPending']=$false}
        }.GetNewClosure())
    })
}

function script:Get-EditorDraftFingerprint($dialog){
    $values=[Collections.Generic.List[string]]::new()
    $nodes=[Collections.Generic.Queue[object]]::new();$nodes.Enqueue($dialog)
    while($nodes.Count){
        $node=$nodes.Dequeue()
        if($node -is [Windows.FrameworkElement] -and $node.Resources['EditorDraftValue']){$values.Add('Appearance='+[string]$node.Tag)}
        if($node -is [Windows.FrameworkElement] -and $node.Name -and $node.Name -notmatch 'Search'){
            $value=$null
            if($node -is [Windows.Controls.TextBox] -and -not $node.IsReadOnly){$value=$node.Text}
            elseif($node -is [Windows.Controls.PasswordBox]){$value=$node.Password}
            elseif($node -is [Windows.Controls.ComboBox]){$value=if($node.IsEditable){$node.Text}else{[string]$node.SelectedIndex}}
            elseif($node -is [Windows.Controls.Primitives.RangeBase]){$value=[string]$node.Value}
            elseif($node -is [Windows.Controls.Primitives.ToggleButton]){$value=[string]$node.IsChecked}
            elseif($node -is [Windows.Controls.ListBox]){$value=[string]$node.SelectedIndex}
            if($null -ne $value){$values.Add($node.Name+'='+$value)}
        }
        # Playlist member checkboxes are created without names.
        if($node -is [Windows.Controls.CheckBox] -and -not $node.Name){$values.Add([string]$node.Content+'='+$node.IsChecked)}
        if($node -is [Windows.DependencyObject]){foreach($child in [Windows.LogicalTreeHelper]::GetChildren($node)){if($child -is [Windows.DependencyObject]){$nodes.Enqueue($child)}}}
    }
    $hash=[Security.Cryptography.SHA256]::Create()
    try{return [Convert]::ToBase64String($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes(($values|ConvertTo-Json -Compress))))}finally{$hash.Dispose()}
}

function script:Install-EditorCloseGuard($dialog){
    if($dialog.Resources['DraftGuardInstalled']){return}
    $save=$dialog.FindName('Save');if(-not $save){$save=$dialog.FindName('StepSave')}
    if(-not $save){return}
    $dialog.Resources['DraftGuardInstalled']=$true;$dialog.Resources['DraftSaveButton']=$save
    $dialog.Add_Loaded({param($sender,$e)$sender.Resources['DraftBaseline']=Get-EditorDraftFingerprint $sender})
    $dialog.Add_Closing({param($sender,$e)
        if($sender.DialogResult -eq $true -or $sender.Resources['DraftGuardSaving'] -or -not $sender.Resources['DraftBaseline']){return}
        if((Get-EditorDraftFingerprint $sender) -eq $sender.Resources['DraftBaseline']){return}
        $choice=Show-UnsavedChangesPrompt $sender 'This editor has unsaved changes.'
        if($choice -eq 'Discard'){return}
        $e.Cancel=$true
        if($choice -eq 'Save'){
            # Defer the existing Save handler until this Closing event has unwound.
            [void]$sender.Dispatcher.BeginInvoke([action]{
                $sender.Resources['DraftGuardSaving']=$true
                try{$sender.Resources['DraftSaveButton'].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))}
                finally{$sender.Resources['DraftGuardSaving']=$false}
            }.GetNewClosure())
        }
    })
}

function script:Get-GlobalPendingSnapshots {
    if(-not $script:globalSaveInstalled -or $script:globalSaving){return @()}
    foreach($group in $script:globalSaveGroups.Values){
        Update-GlobalSaveGroup $group.Key
        if(-not $group.Dirty){continue}
        foreach($control in $group.Inputs){
            $kind='';$value=$null
            if($control -eq $AliasGrid){$kind='Voices';$value=@{};foreach($row in $control.ItemsSource){$value[[string]$row.Name]=[bool]$row.Enabled}}
            elseif($control -is [Windows.Controls.DataGrid]){$kind='ItemsSource';$value=$control.ItemsSource}
            elseif($control -is [Windows.Controls.PasswordBox]){$kind='Password';$value=$control.Password}
            elseif($control -is [Windows.Controls.TextBox]){$kind='Text';$value=$control.Text}
            elseif($control -is [Windows.Controls.Primitives.ToggleButton]){$kind='IsChecked';$value=$control.IsChecked}
            elseif($control -is [Windows.Controls.Primitives.RangeBase]){$kind='Value';$value=$control.Value}
            elseif($control -is [Windows.Controls.ComboBox]){if($control.IsEditable){$kind='Text';$value=$control.Text}else{$kind='SelectedItem';$value=$control.SelectedItem}}
            if($kind){[pscustomobject]@{Control=$control;Kind=$kind;Value=$value}}
        }
    }
}

function script:Restore-GlobalPendingSnapshots($snapshots){
    $loading=$script:loadingSettings;$script:loadingSettings=$true
    try{
        foreach($snapshot in $snapshots){
            if($snapshot.Kind -eq 'Voices'){
                foreach($row in $AliasGrid.ItemsSource){if($snapshot.Value.ContainsKey([string]$row.Name)){$row.Enabled=$snapshot.Value[[string]$row.Name]}}
                $AliasGrid.Items.Refresh()
            }else{$snapshot.Control.($snapshot.Kind)=$snapshot.Value}
        }
    }finally{$script:loadingSettings=$loading}
    foreach($group in $script:globalSaveGroups.Values){Update-GlobalSaveGroup $group.Key}
}

function script:Get-GlobalSaveInputs([string[]]$functions){
    $inputs=[Collections.Generic.List[object]]::new()
    foreach($name in $functions){
        $command=Get-Command $name -ErrorAction SilentlyContinue
        if(-not $command.ScriptBlock){continue}
        foreach($node in $command.ScriptBlock.Ast.FindAll({param($n)$n -is [Management.Automation.Language.VariableExpressionAst]},$true)){
            $variable=$node.VariablePath.UserPath -replace '^script:',''
            $control=Get-Variable -Name $variable -ValueOnly -ErrorAction SilentlyContinue
            if($control -is [Windows.Controls.TextBox] -or $control -is [Windows.Controls.PasswordBox] -or $control -is [Windows.Controls.Primitives.ToggleButton] -or $control -is [Windows.Controls.Primitives.RangeBase] -or $control -is [Windows.Controls.ComboBox] -or $control -is [Windows.Controls.DataGrid]){
                if(-not $inputs.Contains($control)){[void]$inputs.Add($control)}
                $credential=$control.Resources['YapLoqCredential']
                if($credential){foreach($field in @($credential.Mask,$credential.Plain)){if(-not $inputs.Contains($field)){[void]$inputs.Add($field)}}}
            }
        }
    }
    return $inputs.ToArray()
}

function script:Get-GlobalSaveFingerprint($group){
    $values=@(foreach($control in $group.Inputs){
        $credential=$control.Resources['YapLoqCredential']
        # Mask/Plain are two views of one value. Revealing or clearing the
        # temporary plaintext display must never mark credentials as edited.
        if($credential){[string]$credential.Mask.Password}
        elseif($control -is [Windows.Controls.PasswordBox]){[string]$control.Password}
        elseif($control -is [Windows.Controls.TextBox]){[string]$control.Text}
        elseif($control -is [Windows.Controls.Primitives.ToggleButton]){[string]$control.IsChecked}
        elseif($control -is [Windows.Controls.Primitives.RangeBase]){[string]$control.Value}
        elseif($control -is [Windows.Controls.ComboBox]){[string]$control.SelectedItem+'|'+$control.Text}
        elseif($control -is [Windows.Controls.DataGrid]){
            if($control -eq $AliasGrid){@($control.ItemsSource|Select-Object Name,Enabled)|ConvertTo-Json -Depth 8 -Compress}
            else{@($control.ItemsSource)|ConvertTo-Json -Depth 24 -Compress}
        }
    })
    if($group.Key -eq 'Actions'){$values+=(@($script:automationRules)|ConvertTo-Json -Depth 30 -Compress)}
    if($group.Key -eq 'Audio Stims'){$values=@(@($script:stimLibraryGrid.ItemsSource)|ConvertTo-Json -Depth 30 -Compress)}
    $serialized='['+[string]($values|ConvertTo-Json -Depth 32 -Compress)+']'
    $bytes=[Text.Encoding]::UTF8.GetBytes($serialized)
    $hash=[Security.Cryptography.SHA256]::Create()
    try{return [Convert]::ToBase64String($hash.ComputeHash($bytes))}finally{$hash.Dispose()}
}

function script:Update-GlobalSaveButton {
    if(-not $script:globalSaveButton){return}
    $dirty=@($script:globalSaveGroups.Values|Where-Object{$_.Dirty})
    $script:globalSaveButton.IsEnabled=-not $script:globalSaving
    $script:globalSaveLabel.Text='Save'
    $hasChanges=$dirty.Count -gt 0
    if($script:globalSaveVisualDirty -ne $hasChanges){
        $script:globalSaveVisualDirty=$hasChanges
        if($hasChanges){
            $script:globalSaveButton.Style=$window.FindResource('PrimaryButton')
            $glow=[Windows.Media.Effects.DropShadowEffect]::new()
            $glow.Color=[Windows.Media.ColorConverter]::ConvertFromString('#B6A3FF')
            $glow.BlurRadius=12;$glow.ShadowDepth=0;$glow.Opacity=0.45
            $glow.Freeze()
            $script:globalSaveButton.Effect=$glow
        }else{
            $script:globalSaveButton.Style=$window.FindResource([Windows.Controls.Button])
            $script:globalSaveButton.Effect=$null
        }
    }
    $script:globalSaveButton.ToolTip=if($dirty.Count){'Save changes: '+(($dirty|ForEach-Object{$_.Key}) -join ', ')+$(if($script:liveSettingsInstalled){'. Valid settings apply live. Right-click to discard unsaved edits.'}else{''})}else{'All changes saved (Ctrl+S)'}
}

function script:Update-GlobalSaveGroup([string]$key){
    if(-not $script:globalSaveInstalled -or $script:globalSaving -or $script:loadingSettings){return}
    $group=$script:globalSaveGroups[$key];if(-not $group){return}
    $group.Dirty=(Get-GlobalSaveFingerprint $group) -ne $group.Baseline
    if($script:liveSettingsInstalled){$fingerprint=Get-GlobalSaveFingerprint $group;if($script:liveFingerprints[$key] -ne $fingerprint){$script:liveFingerprints[$key]=$fingerprint;Queue-LiveSettingsApply}}
    Update-GlobalSaveButton
}

function script:Reset-GlobalSaveGroup([string]$key){
    if(-not $script:globalSaveGroups){return}
    $group=$script:globalSaveGroups[$key];if(-not $group){return}
    $group.Baseline=Get-GlobalSaveFingerprint $group;$group.Dirty=$false
    Update-GlobalSaveButton
}

function script:Queue-GlobalSaveTracking($sender){
    if($script:globalSaving -or $script:loadingSettings){return}
    $credential=$sender.Resources['YapLoqCredential'];if($credential -and $credential.Syncing){return}
    $keys=@($sender.Resources['GlobalSaveGroups'])
    foreach($key in $keys){
        $group=$script:globalSaveGroups[$key]
        if(-not $group -or $group.Tracking){continue}
        $group.Tracking=$true
        [void]$window.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background,[action]{
            foreach($entry in $script:globalSaveGroups.Values|Where-Object{$_.Tracking}){$entry.Tracking=$false;Update-GlobalSaveGroup $entry.Key}
        })
    }
}

function script:Add-GlobalSaveGroup([string]$key,$inputs,[scriptblock]$save){
    $group=[pscustomobject]@{Key=$key;Inputs=@($inputs|Where-Object{$_});Save=$save;Dirty=$false;Baseline='';Tracking=$false}
    $script:globalSaveGroups[$key]=$group
    foreach($control in $group.Inputs){
        $existing=@($control.Resources['GlobalSaveGroups'])
        $control.Resources['GlobalSaveGroups']=@($existing|Where-Object{$_})+@($key)
        if($control.Resources['GlobalSaveTracked']){continue}
        $control.Resources['GlobalSaveTracked']=$true
        if($control -is [Windows.Controls.TextBox]){$control.Add_TextChanged({param($s,$e)Queue-GlobalSaveTracking $s})}
        elseif($control -is [Windows.Controls.PasswordBox]){$control.Add_PasswordChanged({param($s,$e)Queue-GlobalSaveTracking $s})}
        elseif($control -is [Windows.Controls.Primitives.ToggleButton]){$control.Add_Checked({param($s,$e)Queue-GlobalSaveTracking $s});$control.Add_Unchecked({param($s,$e)Queue-GlobalSaveTracking $s})}
        elseif($control -is [Windows.Controls.Primitives.RangeBase]){$control.Add_ValueChanged({param($s,$e)Queue-GlobalSaveTracking $s})}
        elseif($control -is [Windows.Controls.ComboBox]){$control.Add_SelectionChanged({param($s,$e)Queue-GlobalSaveTracking $s});$control.AddHandler([Windows.Controls.TextBox]::TextChangedEvent,[Windows.RoutedEventHandler]{param($s,$e)Queue-GlobalSaveTracking $s},$true)}
        elseif($control -is [Windows.Controls.DataGrid]){
            $control.Add_CellEditEnding({param($s,$e)Queue-GlobalSaveTracking $s})
            $control.AddHandler([Windows.Controls.Primitives.ToggleButton]::CheckedEvent,[Windows.RoutedEventHandler]{param($s,$e)Queue-GlobalSaveTracking $s},$true)
            $control.AddHandler([Windows.Controls.Primitives.ToggleButton]::UncheckedEvent,[Windows.RoutedEventHandler]{param($s,$e)Queue-GlobalSaveTracking $s},$true)
        }
    }
    Reset-GlobalSaveGroup $key
}

function script:New-SaveDetailsDialog {
    $dialog=[Windows.Window]::new();$dialog.Title='Save details';if($window.IsVisible){$dialog.Owner=$window};$dialog.Width=560;$dialog.Height=340;$dialog.MinWidth=420;$dialog.MinHeight=260;$dialog.WindowStartupLocation='CenterOwner'
    $dialog.Resources.MergedDictionaries.Add($window.Resources)
    $body=[Windows.Controls.Grid]::new();$body.Margin=20;$dialog.Content=$body
    foreach($height in @('*','Auto')){$row=[Windows.Controls.RowDefinition]::new();$row.Height=$height;[void]$body.RowDefinitions.Add($row)}
    $scroll=[Windows.Controls.ScrollViewer]::new();$scroll.VerticalScrollBarVisibility='Auto';[void]$body.Children.Add($scroll)
    $text=[Windows.Controls.TextBlock]::new();$text.Text=[string]$script:lastSaveMessage;$text.TextWrapping='Wrap';$scroll.Content=$text;$dialog.Resources['SaveDetailsText']=$text
    $buttons=[Windows.Controls.StackPanel]::new();$buttons.Orientation='Horizontal';$buttons.HorizontalAlignment='Right';$buttons.Margin='0,16,0,0';[Windows.Controls.Grid]::SetRow($buttons,1);[void]$body.Children.Add($buttons)
    $copy=[Windows.Controls.Button]::new();$copy.Content='Copy details';$copy.Margin='0,0,8,0';$copy.Add_Click({param($sender,$e)$d=[Windows.Window]::GetWindow($sender);[Windows.Clipboard]::SetText($d.Resources['SaveDetailsText'].Text);$sender.Content='Copied'});[void]$buttons.Children.Add($copy);$dialog.Resources['CopyDetailsButton']=$copy
    $close=[Windows.Controls.Button]::new();$close.Content='Close';$close.Add_Click({param($sender,$e)[Windows.Window]::GetWindow($sender).Close()});[void]$buttons.Children.Add($close)
    Apply-AppFont $dialog
    return $dialog
}

function script:Show-SaveDetails {
    if(-not $script:lastSaveMessage){return}
    $dialog=New-SaveDetailsDialog;[void]$dialog.ShowDialog()
}

function script:Show-SaveFeedback([string]$message,[bool]$failed=$false){
    if(-not $script:globalSaveFeedback){return}
    $script:globalSaveFeedbackTimer.Stop()
    $script:lastSaveMessage=$message
    $script:globalSaveFeedback.BeginAnimation([Windows.UIElement]::OpacityProperty,$null);$script:globalSaveFeedback.Opacity=1
    $script:globalSaveFeedback.Text=if($failed){'Not saved — click for details'}else{$message};$script:globalSaveFeedback.ToolTip='View or copy the full save result'
    $script:globalSaveFeedback.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString($(if($failed){'#E5B96F'}else{'#86C5AE'}))
    $script:globalSaveFeedback.Visibility='Visible'
    $flash=[Windows.Media.Animation.DoubleAnimation]::new();$flash.From=1;$flash.To=0.4;$flash.Duration=[TimeSpan]::FromMilliseconds(180);$flash.AutoReverse=$true;$flash.RepeatBehavior=[Windows.Media.Animation.RepeatBehavior]::new(2);$flash.FillBehavior='Stop'
    $script:globalSaveFeedback.BeginAnimation([Windows.UIElement]::OpacityProperty,$flash)
    $script:globalSaveFeedbackTimer.Start()
}

function script:Save-AllPendingChanges {
    if($script:globalSaving){Show-SaveFeedback 'Save is in progress…';return}
    foreach($group in $script:globalSaveGroups.Values){
        foreach($grid in @($group.Inputs|Where-Object{$_ -is [Windows.Controls.DataGrid]})){
            try{
                if(-not $grid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Cell,$true) -or -not $grid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Row,$true)){$BottomStatus.Text='Not saved - finish the highlighted table edit first.';Show-SaveFeedback $BottomStatus.Text $true;return}
            }catch{$BottomStatus.Text='Not saved - finish the table edit first.';Show-SaveFeedback $BottomStatus.Text $true;return}
        }
        Update-GlobalSaveGroup $group.Key
    }
    $pending=@($script:globalSaveGroups.Values|Where-Object{$_.Dirty})
    if(-not $pending.Count){$BottomStatus.Text='All changes saved.';Show-SaveFeedback 'All changes saved';Update-GlobalSaveButton;return}
    # Save routines may clear a password field; preserve its draft until commit succeeds.
    $secrets=@(foreach($entry in $script:credentialFields.Values){[pscustomobject]@{Entry=$entry;Mask=$entry.Mask.Password;Plain=$entry.Plain.Text}})
    $script:globalSaving=$true
    foreach($saved in $secrets){$saved.Entry.Syncing=$true}
    $section='Settings'
    try{
        $script:globalSaveDraft=Read-Settings;$script:globalSaveStaging=$true
        foreach($group in $pending){
            $section=$group.Key;$script:globalStageWrites=0
            $BottomStatus.Text=''
            & $group.Save
            if($script:globalStageWrites -eq 0){
                $message=if($BottomStatus.Text){$BottomStatus.Text}elseif($section -eq 'Default voice'){$script:assignmentDefaultStatus.Text}elseif($section -eq 'Viewer commands'){$script:viewerCommandsStatus.Text}else{'Changes could not be validated.'}
                throw $message
            }
        }
        $draft=$script:globalSaveDraft
        if(@($pending|Where-Object Key -eq 'Actions').Count){[void](Invoke-BridgePost '/api/maintenance/backup' @{})}
        $script:globalSaveStaging=$false
        Write-Settings $draft
        if($script:liveSettingsInstalled){$script:liveValidGroups=@{};$script:liveSettingsDebounce.Stop();$script:liveSettingsPending='{"reset":true}';$script:liveSettingsPump.Start()}
        try{Sync-YapLoqCredentialFields}catch{}
        foreach($group in $script:globalSaveGroups.Values){Reset-GlobalSaveGroup $group.Key}
        if(@($pending|Where-Object Key -eq 'Actions').Count){Update-AutomationLegacyUi $true}
        $BottomStatus.Text='All pending changes saved. Restart after changing connection ports.'
        Show-SaveFeedback 'Saved'
    }catch{
        foreach($saved in $secrets){$saved.Entry.Syncing=$true;$saved.Entry.Mask.Password=$saved.Mask;$saved.Entry.Plain.Text=$saved.Plain;$saved.Entry.Syncing=$false}
        $BottomStatus.Text='Not saved - '+$section+': '+$_.Exception.Message
        Show-SaveFeedback $BottomStatus.Text $true
    }finally{
        foreach($saved in $secrets){$saved.Entry.Syncing=$false}
        $script:globalSaveStaging=$false;$script:globalSaveDraft=$null;$script:globalSaving=$false
        foreach($group in $script:globalSaveGroups.Values){Update-GlobalSaveGroup $group.Key}
        Update-GlobalSaveButton
    }
}

function script:Install-GlobalSave {
    $script:globalSaveGroups=[ordered]@{}
    foreach($spec in @(
        @('Settings','Save-AppSettings','SaveButton'),@('Rules','Save-Rules','SaveRulesButton'),
        @('Pronunciation','Save-Pronunciations',''),@('Voices','Save-VoiceToggles','SaveVoicesButton'),
        @('Connection','Save-StreamerBotSettings','SaveStreamerBotButton'),
        @('VoiceStudio','Save-VoiceStudioSettings','SaveVoiceStudioButton'),@('Polly','Save-PollySettings','SavePollyButton'),
        @('ElevenLabs','Save-ElevenLabsSettings','SaveElevenLabsButton'),@('Azure','Save-AzureSettings','SaveAzureButton'),
        @('Google','Save-GoogleSettings','SaveGoogleButton'),@('Watson','Save-WatsonSettings','SaveWatsonButton'),
        @('UberDuck','Save-UberDuckSettings','SaveUberDuckButton'),@('TTS.Monster','Save-TtsMonsterSettings','SaveTtsMonsterButton'),
        @('Acapela','Save-AcapelaSettings','SaveAcapelaButton'),@('CereProc','Save-CereProcSettings','SaveCereProcButton')
    )){
        $functions=@($spec[1]);if($spec[0] -eq 'Settings'){$functions+='Set-ObsSettings'}
        if($spec[0] -eq 'Rules'){$functions+='Get-ProfanityRules'}
        $functionName=[string]$spec[1]
        Add-GlobalSaveGroup $spec[0] (Get-GlobalSaveInputs $functions) ([scriptblock]::Create($functionName))
        if($spec[2]){$button=$window.FindName($spec[2]);if($button){$button.Visibility='Collapsed'}}
    }
    Add-GlobalSaveGroup 'Default voice' @($script:assignmentDefaultPicker) {Save-AssignmentDefault}
    if($script:stimLibraryGrid){Add-GlobalSaveGroup 'Audio Stims' @($script:stimLibraryGrid,$script:stimFilesGrid,$script:stimKeywordBox,$script:stimActionBox,$script:stimCensorBox,$script:stimEnabledCheck,$script:stimReplayCheck,$script:stimAllowWithoutUserCheck,$script:stimModeBox,$script:stimPauseBox,$script:stimOutputBox) {Save-AudioStims}}
    Add-GlobalSaveGroup 'Speech input' @($script:viewerCommandsEnabled,$script:chatVoiceTagsAllEnabled,$script:splitSpeechSentences) {Save-ViewerCommands}
    $actionInputs=@('AutomationName','AutomationEnabled','AutomationOnError','AutomationConditions','AutomationSteps'|ForEach-Object{Get-AutomationControl $_})
    Add-GlobalSaveGroup 'Actions' $actionInputs {
        if(-not(Save-AutomationDraft)){throw 'Finish editing the action first.'}
        $result=(Invoke-BridgePost '/api/maintenance/validate-actions' @{rules=@($script:automationRules)}).result
        if($null -eq $result -or -not $result.PSObject.Properties['rules']){throw 'Action validation did not return a valid result. Check the app connection.'}
        Set-JsonProperty $script:globalSaveDraft 'automations' @($result.rules)
        Set-JsonProperty $script:globalSaveDraft 'automations_migrated' $true
        $script:globalStageWrites++
    }
    (Get-AutomationControl 'AutomationSave').Visibility='Collapsed'
    $script:assignmentRulesSave.Visibility='Collapsed'
    if($script:profanitySaveButton){$script:profanitySaveButton.Visibility='Collapsed'}
    foreach($section in $script:assignmentSections.Values){
        if($section -is [Windows.Controls.StackPanel]){
            foreach($child in $section.Children){
                if($child -is [Windows.Controls.Button] -and $child.Content -eq 'Save default'){$child.Visibility='Collapsed'}
                if($child -is [Windows.Controls.WrapPanel]){foreach($button in $child.Children|Where-Object{$_ -is [Windows.Controls.Button] -and $_.Content -eq 'Save commands'}){$button.Visibility='Collapsed'}}
            }
        }
    }
    foreach($name in @('SavePageButton','SaveStreamerConnectionButton','SaveObsSettingsButton','SaveObsButton')){$button=$window.FindName($name);if($button){$button.Visibility='Collapsed'}}
    (Get-ViewerControl 'ViewerSave').Content='Apply assignment'
    foreach($label in @($SaveProfileButton.Content.Children|Where-Object{$_ -is [Windows.Controls.TextBlock]})){$label.Text='Create profile'}
    $script:globalSaveButton=[Windows.Controls.Button]::new();$button=$script:globalSaveButton
    $button.Height=30;$button.MinHeight=30;$button.Padding='10,3';$button.Margin='0,4,8,4'
    $content=[Windows.Controls.StackPanel]::new();$content.Orientation='Horizontal'
    $icon=[Windows.Shapes.Path]::new();$icon.Data=(Resolve-VoiceIcon 'mdi:content-save').Geometry;$icon.Width=14;$icon.Height=14;$icon.Stretch='Uniform';$icon.Margin='0,0,7,0'
    $binding=[Windows.Data.Binding]::new('Foreground');$binding.Source=$button;[void]$icon.SetBinding([Windows.Shapes.Shape]::FillProperty,$binding);[void]$content.Children.Add($icon)
    $script:globalSaveLabel=[Windows.Controls.TextBlock]::new();$script:globalSaveLabel.Text='Save';[void]$content.Children.Add($script:globalSaveLabel);$button.Content=$content
    [Windows.Automation.AutomationProperties]::SetName($button,'Save all pending changes')
    $parent=$BridgeStatusButton.Parent;$parent.Children.Insert($parent.Children.IndexOf($BridgeStatusButton),$button)
    $script:globalSaveFeedback=[Windows.Controls.TextBlock]::new();$notice=$script:globalSaveFeedback
    $notice.VerticalAlignment='Center';$notice.MaxWidth=260;$notice.Margin='0,0,10,0';$notice.TextTrimming='CharacterEllipsis';$notice.Visibility='Collapsed'
    $notice.Cursor=[Windows.Input.Cursors]::Hand;$notice.Focusable=$true
    $notice.Add_MouseLeftButtonUp({Show-SaveDetails});$notice.Add_KeyDown({param($sender,$e)if($e.Key -in @('Enter','Space')){$e.Handled=$true;Show-SaveDetails}})
    [Windows.Automation.AutomationProperties]::SetName($notice,'Save result')
    $parent.Children.Insert($parent.Children.IndexOf($button),$notice)
    $script:globalSaveFeedbackTimer=[Windows.Threading.DispatcherTimer]::new();$script:globalSaveFeedbackTimer.Interval=[TimeSpan]::FromSeconds(6)
    $script:globalSaveFeedbackTimer.Add_Tick({param($sender,$e)
        $sender.Stop();$fade=[Windows.Media.Animation.DoubleAnimation]::new();$fade.From=1;$fade.To=0;$fade.Duration=[TimeSpan]::FromMilliseconds(250)
        $fade.Add_Completed({if(-not $script:globalSaveFeedbackTimer.IsEnabled){$script:globalSaveFeedback.Visibility='Collapsed'}})
        $script:globalSaveFeedback.BeginAnimation([Windows.UIElement]::OpacityProperty,$fade)
    })
    $window.Add_Closed({if($script:globalSaveFeedbackTimer){$script:globalSaveFeedbackTimer.Stop()}})
    $button.Add_Click({Save-AllPendingChanges})
    $window.Add_PreviewKeyDown({param($sender,$e)if($e.Key -eq 'S' -and [Windows.Input.Keyboard]::Modifiers -eq [Windows.Input.ModifierKeys]::Control){Save-AllPendingChanges;$e.Handled=$true}})
    $window.AddHandler([Windows.Controls.Button]::ClickEvent,[Windows.RoutedEventHandler]{param($sender,$e)
        $keys=switch($script:activePage){'streamActions'{@('Actions')};'rules'{@('Rules')};'assignments'{@('Rules','Default voice','Viewer commands')};'pronunciation'{@('Pronunciation')};default{@()}}
        foreach($key in $keys){Update-GlobalSaveGroup $key}
    },$true)
    $script:globalSaveInstalled=$true;Update-GlobalSaveButton
}
