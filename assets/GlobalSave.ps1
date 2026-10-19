# Event-driven pending-edit tracking. Never scan pages from the playback timer.
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
        if($control -is [Windows.Controls.PasswordBox]){[string]$control.Password}
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
    $script:globalSaveButton.ToolTip=if($dirty.Count){'Save changes: '+(($dirty|ForEach-Object{$_.Key}) -join ', ')}else{'All changes saved (Ctrl+S)'}
}

function script:Update-GlobalSaveGroup([string]$key){
    if(-not $script:globalSaveInstalled -or $script:globalSaving -or $script:loadingSettings){return}
    $group=$script:globalSaveGroups[$key];if(-not $group){return}
    $group.Dirty=(Get-GlobalSaveFingerprint $group) -ne $group.Baseline
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

function script:Save-AllPendingChanges {
    if($script:globalSaving){return}
    foreach($group in $script:globalSaveGroups.Values){
        foreach($grid in @($group.Inputs|Where-Object{$_ -is [Windows.Controls.DataGrid]})){
            try{
                if(-not $grid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Cell,$true) -or -not $grid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Row,$true)){$BottomStatus.Text='Not saved - finish the highlighted table edit first.';return}
            }catch{$BottomStatus.Text='Not saved - finish the table edit first.';return}
        }
        Update-GlobalSaveGroup $group.Key
    }
    $pending=@($script:globalSaveGroups.Values|Where-Object{$_.Dirty})
    if(-not $pending.Count){$BottomStatus.Text='All changes saved.';Update-GlobalSaveButton;return}
    # Save routines may clear a password field; preserve its draft until commit succeeds.
    $secrets=@(foreach($entry in $script:credentialFields.Values){[pscustomobject]@{Entry=$entry;Mask=$entry.Mask.Password;Plain=$entry.Plain.Text}})
    $script:globalSaving=$true
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
        try{Sync-YapLoqCredentialFields}catch{}
        foreach($group in $script:globalSaveGroups.Values){Reset-GlobalSaveGroup $group.Key}
        if(@($pending|Where-Object Key -eq 'Actions').Count){Update-AutomationLegacyUi $true}
        $BottomStatus.Text='All pending changes saved. Restart after changing connection ports.'
    }catch{
        foreach($saved in $secrets){$saved.Entry.Syncing=$true;$saved.Entry.Mask.Password=$saved.Mask;$saved.Entry.Plain.Text=$saved.Plain;$saved.Entry.Syncing=$false}
        $BottomStatus.Text='Not saved - '+$section+': '+$_.Exception.Message
    }finally{
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
    Add-GlobalSaveGroup 'Viewer commands' @($script:viewerCommandsEnabled) {Save-ViewerCommands}
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
    $button.Add_Click({Save-AllPendingChanges})
    $window.Add_PreviewKeyDown({param($sender,$e)if($e.Key -eq 'S' -and [Windows.Input.Keyboard]::Modifiers -eq [Windows.Input.ModifierKeys]::Control){Save-AllPendingChanges;$e.Handled=$true}})
    $window.AddHandler([Windows.Controls.Button]::ClickEvent,[Windows.RoutedEventHandler]{param($sender,$e)
        $keys=switch($script:activePage){'streamActions'{@('Actions')};'rules'{@('Rules')};'assignments'{@('Rules','Default voice','Viewer commands')};'pronunciation'{@('Pronunciation')};default{@()}}
        foreach($key in $keys){Update-GlobalSaveGroup $key}
    },$true)
    $script:globalSaveInstalled=$true;Update-GlobalSaveButton
}
