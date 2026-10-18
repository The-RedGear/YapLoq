function Get-AutomationControl([string]$name){$script:automationPage.FindName($name)}

function Set-AutomationButtonIcon([string]$name,[string]$icon,[string]$label,[bool]$withText=$false){
    $button=Get-AutomationControl $name;$button.ToolTip=$label;[Windows.Automation.AutomationProperties]::SetName($button,$label)
    $content=[Windows.Controls.StackPanel]::new();$content.Orientation='Horizontal'
    $glyph=[Windows.Shapes.Path]::new();$glyph.Data=(Resolve-VoiceIcon $icon).Geometry;$glyph.Width=14;$glyph.Height=14;$glyph.Stretch='Uniform'
    $foreground=[Windows.Data.Binding]::new('Foreground');$foreground.Source=$button
    [void]$glyph.SetBinding([Windows.Shapes.Shape]::FillProperty,$foreground)
    [void]$content.Children.Add($glyph)
    if($withText){$glyph.Margin='0,0,8,0';$text=[Windows.Controls.TextBlock]::new();$text.Text=$label;[void]$content.Children.Add($text)}
    $button.Content=$content
}

function Set-AutomationMessage([string]$message){(Get-AutomationControl 'AutomationStatus').Text=$message}

function Update-AutomationLegacyUi([bool]$migrated){
    if(-not $script:automationLegacyCard){return}
    $script:automationLegacyCard.Visibility=if($migrated){'Collapsed'}else{'Visible'}
    if($script:automationPlaybackTiming){$script:automationPlaybackTiming.Visibility=if($migrated){'Visible'}else{'Collapsed'}}
}

function Save-AutomationDraft {
    if(-not $script:automationSelected){return $true}
    try{
        $conditions=Get-AutomationControl 'AutomationConditions'
        [void]$conditions.CommitEdit([Windows.Controls.DataGridEditingUnit]::Cell,$true)
        [void]$conditions.CommitEdit([Windows.Controls.DataGridEditingUnit]::Row,$true)
        $script:automationSelected.conditions=@($conditions.ItemsSource)
        $script:automationSelected.name=(Get-AutomationControl 'AutomationName').Text
        $script:automationSelected.enabled=[bool](Get-AutomationControl 'AutomationEnabled').IsChecked
        $script:automationSelected.onError=(Get-AutomationControl 'AutomationOnError').SelectedItem.Tag
        [void](Get-AutomationControl 'AutomationSteps').CommitEdit([Windows.Controls.DataGridEditingUnit]::Cell,$true)
        [void](Get-AutomationControl 'AutomationSteps').CommitEdit([Windows.Controls.DataGridEditingUnit]::Row,$true)
        return $true
    }catch{Set-AutomationMessage $_.Exception.Message;return $false}
}

function Show-AutomationDraft($rule){
    $script:automationSelected=$rule
    (Get-AutomationControl 'AutomationEditor').IsEnabled=$true
    foreach($name in @('AutomationName','AutomationEnabled','AutomationTriggerPane','AutomationStepPane')){(Get-AutomationControl $name).IsEnabled=[bool]$rule}
    if(-not $rule){(Get-AutomationControl 'AutomationName').Text='';return}
    (Get-AutomationControl 'AutomationName').Text=$rule.name
    (Get-AutomationControl 'AutomationEnabled').IsChecked=[bool]$rule.enabled
    (Get-AutomationControl 'AutomationOnError').SelectedIndex=if($rule.onError -eq 'continue'){1}else{0}
    (Get-AutomationControl 'AutomationConditions').ItemsSource=@($rule.conditions)
    foreach($trigger in @($rule.triggers)){$match=@((Get-AutomationControl 'AutomationTriggerPicker').Items|Where-Object{$_.source -eq $trigger.source -and $_.event -eq $trigger.event})[0];$trigger|Add-Member NoteProperty caption $(if($match){$match.label}else{$trigger.event}) -Force}
    (Get-AutomationControl 'AutomationTriggers').ItemsSource=@($rule.triggers)
    foreach($step in @($rule.steps)){$summary=if($step.type -eq 'delay'){[string]$step.seconds+' seconds'}elseif($step.PSObject.Properties['label'] -and $step.label){$step.label}else{$step.action};$step|Add-Member NoteProperty Summary $summary -Force}
    (Get-AutomationControl 'AutomationSteps').ItemsSource=@($rule.steps)
}

function Refresh-AutomationList($select){
    $script:automationSelecting=$true
    try{(Get-AutomationControl 'AutomationList').ItemsSource=@($script:automationRules);Set-AutomationSearch;(Get-AutomationControl 'AutomationList').SelectedItem=$select;Show-AutomationDraft $select;(Get-AutomationControl 'AutomationEmpty').Visibility=if(@($script:automationRules).Count){'Collapsed'}else{'Visible'}}finally{$script:automationSelecting=$false}
}

function Set-AutomationSearch {
    $list=Get-AutomationControl 'AutomationList'
    if(-not $list.ItemsSource){return}
    $view=[Windows.Data.CollectionViewSource]::GetDefaultView($list.ItemsSource)
    $view.Filter=[Predicate[object]]{param($item)$search=(Get-AutomationControl 'AutomationSearch').Text;return ([string]$item.name).IndexOf($search,[StringComparison]::OrdinalIgnoreCase) -ge 0}
}

function Start-AutomationLoad {
    if($script:automationLoaded -or $script:automationLoadTask){return}
    $script:automationLoadClient=[Net.WebClient]::new()
    $script:automationLoadClient.Proxy=$null
    $script:automationLoadTask=$script:automationLoadClient.DownloadStringTaskAsync([uri]((Get-BridgeBaseUri)+'/api/automations'))
    Set-AutomationMessage 'Loading actions...'
    $timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[TimeSpan]::FromMilliseconds(100)
    $timer.Add_Tick({param($sender,$e)
        if(-not $script:automationLoadTask.IsCompleted){return}
        $sender.Stop()
        try{
            $result=($script:automationLoadTask.GetAwaiter().GetResult()|ConvertFrom-Json).result
            $script:automationRules=@($result.rules)
            (Get-AutomationControl 'AutomationTriggerPicker').ItemsSource=@($result.events)
            (Get-AutomationControl 'AutomationTriggerPicker').SelectedIndex=0
            $script:automationLoaded=$true
            Update-AutomationLegacyUi ([bool]$result.migrated)
            (Get-AutomationControl 'AutomationSave').IsEnabled=$true
            Refresh-AutomationList (@($script:automationRules)[0])
            Set-AutomationMessage 'Runs are queued. Steps dispatch in saved order. Save actions to apply edits and migrate existing playback hooks.'
            if($script:automationCreateAfterLoad){$script:automationCreateAfterLoad=$false;(Get-AutomationControl 'AutomationNew').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))}
        }catch{$script:automationLoaded=$false;Set-AutomationMessage ('Could not load actions. Click Add action to retry. '+$_.Exception.Message)}
        finally{$script:automationLoadClient.Dispose();$script:automationLoadTask=$null}
    });$timer.Start()
}

function Move-AutomationItem([string]$kind,[int]$direction){
    if(-not(Save-AutomationDraft)){return}
    $control=Get-AutomationControl $(if($kind -eq 'rule'){'AutomationList'}else{'AutomationSteps'})
    $item=$control.SelectedItem;if(-not $item){return}
    $items=New-Object System.Collections.ArrayList
    foreach($entry in $(if($kind -eq 'rule'){@($script:automationRules)}else{@($script:automationSelected.steps)})){[void]$items.Add($entry)}
    $index=$items.IndexOf($item);$target=$index+$direction;if($target -lt 0 -or $target -ge $items.Count){return}
    $items.RemoveAt($index);$items.Insert($target,$item)
    if($kind -eq 'rule'){$script:automationRules=@($items);Refresh-AutomationList $item}else{$script:automationSelected.steps=@($items);Show-AutomationDraft $script:automationSelected;$control.SelectedItem=$item}
}

function Update-AutomationActionSearch($d){
    if(-not $d -or $d.Resources['FilteringActions']){return}
    $picker=$d.FindName('StepActionPicker');$typed=$picker.Text
    $needle=$typed.Trim();$matches=New-Object System.Collections.ArrayList;$count=0
    foreach($entry in $script:automationRemoteActions){
        if(-not $needle -or ([string]$entry.name).IndexOf($needle,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or ([string]$entry.id).IndexOf($needle,[StringComparison]::OrdinalIgnoreCase) -ge 0){
            $count++;if($matches.Count -lt 100){[void]$matches.Add($entry)}
        }
    }
    $d.Resources['FilteringActions']=$true
    try{
        $picker.ApplyTemplate()|Out-Null;$editor=$picker.Template.FindName('PART_EditableTextBox',$picker)
        $caret=if($editor){$editor.CaretIndex}else{$typed.Length}
        $picker.ItemsSource=@($matches);$picker.Text=$typed
        if($editor){$editor.CaretIndex=[Math]::Min($caret,$typed.Length);$editor.SelectionLength=0}
        $d.FindName('StepSearchStatus').Text=if($count -gt 100){"Showing 100 of $count matches. Keep typing to narrow the list."}elseif($count){"$count matching actions"}else{'No matching actions. You can still enter an exact name or ID.'}
    }finally{$d.Resources['FilteringActions']=$false}
}

function Start-AutomationActionLoad($d){
    if($d.Resources['RemoteTask']){return}
    $client=[Net.WebClient]::new();$client.Proxy=$null;$d.Resources['RemoteClient']=$client
    $d.Resources['RemoteTask']=$client.DownloadStringTaskAsync([uri]((Get-BridgeBaseUri)+'/api/automations/actions'))
    $d.FindName('StepStatus').Text='Refreshing Streamer.Bot actions...'
    $timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[TimeSpan]::FromMilliseconds(100);$d.Resources['RemoteTimer']=$timer
    $timer.Add_Tick({param($sender,$e)
        $d=$script:automationStepDialog;if(-not $d){$sender.Stop();return}
        $task=$d.Resources['RemoteTask'];if(-not $task.IsCompleted){return};$sender.Stop()
        try{
            $script:automationRemoteActions=@(($task.GetAwaiter().GetResult()|ConvertFrom-Json).result)
            Update-AutomationActionSearch $d
            $cachePath=Join-Path $configDir 'streamerbot-actions-cache.json'
            $json=ConvertTo-Json -InputObject @($script:automationRemoteActions) -Depth 5
            $tempPath=$cachePath+'.tmp';[IO.File]::WriteAllText($tempPath,$json)
            if([IO.File]::Exists($cachePath)){[IO.File]::Replace($tempPath,$cachePath,$null)}else{[IO.File]::Move($tempPath,$cachePath)}
            $d.FindName('StepStatus').Text=''
        }catch{$d.FindName('StepStatus').Text='Could not refresh actions. Using saved actions if available; you can still type an exact name or ID. Check Connection to reconnect.'}
        finally{$d.Resources['RemoteClient'].Dispose();$d.Resources.Remove('RemoteTask')}
    });$timer.Start()
}

function Show-AutomationStep($existing){
    $dialog=Load-Xaml (Join-Path $resourceRoot 'assets\AutomationStep.xaml')
    $dialog.Owner=$window;$dialog.Resources.MergedDictionaries.Add($window.Resources);Apply-AppFont $dialog
    $dialog.FindName('StepSave').Style=$window.FindResource('PrimaryButton')
    $script:automationStepDialog=$dialog;$script:automationStepResult=$null
    $dialog.FindName('StepType').SelectedIndex=if($existing -and $existing.type -eq 'delay'){1}else{0}
    if($existing){$dialog.FindName('StepArguments').Text=if($existing.args){ConvertTo-Json $existing.args -Depth 10}else{'{}'};$dialog.FindName('StepDelay').Text=if($null -ne $existing.seconds){[string]$existing.seconds}else{'1'}}
    $dialog.FindName('StepActionFields').Visibility=if($dialog.FindName('StepType').SelectedIndex -eq 0){'Visible'}else{'Collapsed'}
    $dialog.FindName('StepDelayFields').Visibility=if($dialog.FindName('StepType').SelectedIndex -eq 1){'Visible'}else{'Collapsed'}
    $dialog.FindName('StepType').Add_SelectionChanged({$d=$script:automationStepDialog;$d.FindName('StepActionFields').Visibility=if($d.FindName('StepType').SelectedIndex -eq 0){'Visible'}else{'Collapsed'};$d.FindName('StepDelayFields').Visibility=if($d.FindName('StepType').SelectedIndex -eq 1){'Visible'}else{'Collapsed'}})
    $dialog.FindName('StepTitleDrag').Add_MouseLeftButtonDown({$script:automationStepDialog.DragMove()})
    $dialog.FindName('StepClose').Add_Click({$script:automationStepDialog.Close()})
    $dialog.Add_KeyDown({param($sender,$e)if($e.Key -eq 'Escape'){$sender.Close()}})
    if(-not $script:automationRemoteActions.Count){try{$script:automationRemoteActions=@([IO.File]::ReadAllText((Join-Path $configDir 'streamerbot-actions-cache.json'))|ConvertFrom-Json)}catch{}}
    Update-AutomationActionSearch $dialog
    if($existing){
        $match=@($script:automationRemoteActions|Where-Object{$_.id -eq $existing.action})[0]
        $dialog.FindName('StepActionPicker').Text=if($match){$match.name}else{[string]$existing.action}
        Update-AutomationActionSearch $dialog
    }
    $searchTimer=[Windows.Threading.DispatcherTimer]::new();$searchTimer.Interval=[TimeSpan]::FromMilliseconds(140);$dialog.Resources['SearchTimer']=$searchTimer
    $searchTimer.Add_Tick({param($sender,$e)$sender.Stop();$d=$script:automationStepDialog;if($d){Update-AutomationActionSearch $d;$picker=$d.FindName('StepActionPicker');if($picker.IsKeyboardFocusWithin){$picker.IsDropDownOpen=$true}}})
    $dialog.FindName('StepActionPicker').AddHandler([Windows.Controls.TextBox]::TextChangedEvent,[Windows.Controls.TextChangedEventHandler]{param($sender,$e)
        $d=$script:automationStepDialog;if(-not $d -or $d.Resources['FilteringActions']){return}
        $timer=$d.Resources['SearchTimer'];$timer.Stop();$timer.Start()
    })
    $dialog.Add_Loaded({param($sender,$e)Start-AutomationActionLoad $sender})
    $dialog.FindName('StepSave').Add_Click({
        $d=$script:automationStepDialog
        try{
            if($d.FindName('StepType').SelectedIndex -eq 1){$seconds=0.0;if(-not [double]::TryParse($d.FindName('StepDelay').Text,[ref]$seconds) -or [double]::IsNaN($seconds) -or [double]::IsInfinity($seconds) -or $seconds -lt 0 -or $seconds -gt 86400){throw 'Enter a delay between 0 and 86400 seconds.'};$script:automationStepResult=[pscustomobject]@{type='delay';seconds=$seconds;enabled=$true}}
            else{
                $typed=$d.FindName('StepActionPicker').Text.Trim();if(-not $typed){throw 'Type an action name or choose one from the dropdown.'}
                $matches=@($script:automationRemoteActions|Where-Object{$_.id -eq $typed -or $_.name -eq $typed})
                $selected=$d.FindName('StepActionPicker').SelectedItem
                if(-not $selected -or ($selected.name -ne $typed -and $selected.id -ne $typed)){$selected=if($matches.Count -eq 1){$matches[0]}else{$null}}
                if(-not $selected -and $matches.Count -gt 1){throw 'More than one action has that name. Choose the exact action from the dropdown.'}
                $action=if($selected){$selected.id}else{$typed}
                $json=$d.FindName('StepArguments').Text;if(-not $json.Trim()){$json='{}'}
                $arguments=ConvertFrom-Json $json;if($arguments -isnot [pscustomobject]){throw 'Arguments must be a JSON object.'}
                $script:automationStepResult=[pscustomobject]@{type='action';action=$action;args=$arguments;enabled=$true;label=$(if($selected){$selected.name}else{$typed})}
            }
            $d.DialogResult=$true
        }catch{$d.FindName('StepStatus').Text=$_.Exception.Message}
    })
    $dialog.Add_Closed({param($sender,$e)if($sender.Resources['SearchTimer']){$sender.Resources['SearchTimer'].Stop()};if($sender.Resources['RemoteTimer']){$sender.Resources['RemoteTimer'].Stop()};if($sender.Resources['RemoteClient']){$sender.Resources['RemoteClient'].Dispose()};$script:automationStepDialog=$null})
    [void]$dialog.ShowDialog()
    return $script:automationStepResult
}

function Install-YapLoqAutomations {
    $page=Load-Xaml (Join-Path $resourceRoot 'assets\Automations.xaml')
    $script:automationPage=$page;$script:automationRules=@();$script:automationRemoteActions=@()
    $page.Visibility='Collapsed';[Windows.Controls.Grid]::SetRow($page,2);[void]$script:shellContent.Children.Add($page)
    $script:yaploqPages['streamActions']=$page;$script:routeOwners['streamActions']='Integrations'
    $script:ownerLastPage.Integrations='streamActions'
    $script:ownerSections.Integrations=@(@('Actions','streamActions','RulesNav'),@('Connection','streamerbot','StreamerBotNav'))
    $card=$EnableStreamerBotActionsCheck
    while($card -and $card -isnot [Windows.Controls.Border]){$card=$card.Parent}
    $script:automationLegacyCard=$card
    $timing=$StreamerBotPlaybackDelaySlider
    while($timing -and $timing -isnot [Windows.Controls.Border]){$timing=$timing.Parent}
    if($timing -and $timing.Parent -is [Windows.Controls.Panel]){
        [void]$timing.Parent.Children.Remove($timing)
        $script:automationPlaybackTiming=$timing
        $timing.Visibility='Collapsed'
        [void]$StreamerBotPage.Content.Children.Add($timing)
    }
    (Get-AutomationControl 'AutomationSave').Style=$window.FindResource('PrimaryButton');(Get-AutomationControl 'AutomationSave').IsEnabled=$false
    Show-AutomationDraft $null
    (Get-AutomationControl 'AutomationNew').Content='Add action'
    (Get-AutomationControl 'AutomationEmptyAdd').Style=$window.FindResource('PrimaryButton')
    (Get-AutomationControl 'AutomationEmptyAdd').Add_Click({(Get-AutomationControl 'AutomationNew').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))})
    $picker=Get-AutomationControl 'AutomationTriggerPicker';$picker.DisplayMemberPath='';$picker.ItemTemplate=[Windows.Markup.XamlReader]::Parse('<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><TextBlock Text="{Binding label}" TextTrimming="CharacterEllipsis"/></DataTemplate>')
    foreach($spec in @(@('AutomationNew','mdi:plus','Add action',$false),@('AutomationDuplicate','mdi:content-copy','Duplicate action',$false),@('AutomationDelete','mdi:delete','Remove action',$false),@('AutomationSave','mdi:content-save','Save actions',$true),@('AutomationUp','mdi:arrow-up','Move action up',$false),@('AutomationDown','mdi:arrow-down','Move action down',$false),@('AutomationTriggerAdd','mdi:plus','Add trigger',$false),@('AutomationTriggerRemove','mdi:delete','Remove trigger',$false),@('AutomationStepAdd','mdi:plus','Add',$true),@('AutomationStepEdit','mdi:pencil','Edit sub-action',$false),@('AutomationStepRemove','mdi:delete','Remove sub-action',$false),@('AutomationStepUp','mdi:arrow-up','Move sub-action up',$false),@('AutomationStepDown','mdi:arrow-down','Move sub-action down',$false))){Set-AutomationButtonIcon $spec[0] $spec[1] $spec[2] $spec[3]}
    Set-AutomationButtonIcon 'AutomationNew' 'mdi:plus' 'Add action' $true
    (Get-AutomationControl 'AutomationSearch').Add_TextChanged({Set-AutomationSearch})
    foreach($column in (Get-AutomationControl 'AutomationSteps').Columns){if($column -is [Windows.Controls.DataGridTextColumn]){$column.ElementStyle=$window.FindResource('GridText')}}
    (Get-AutomationControl 'AutomationSteps').Columns[0].Width=55
    (Get-AutomationControl 'AutomationSteps').RowHeight=34
    (Get-AutomationControl 'AutomationSteps').Columns[2].MinWidth=120
    (Get-AutomationControl 'AutomationSteps').Add_SizeChanged({param($sender,$e)if($sender.ActualWidth -gt 0){$sender.Columns[2].Width=[Windows.Controls.DataGridLength]::new([Math]::Max(120,$sender.ActualWidth-150))}})
    (Get-AutomationControl 'AutomationConditions').Columns[0].ItemsSource=@('alias','source','user','voiceName','engineName','id','text','integration')
    (Get-AutomationControl 'AutomationConditions').Columns[1].ItemsSource=@('equals','contains','notEquals')
    (Get-AutomationControl 'AutomationConditionAdd').Add_Click({if(-not(Save-AutomationDraft) -or -not $script:automationSelected){return};$script:automationSelected.conditions+=[pscustomobject]@{field='alias';op='equals';value=''};Show-AutomationDraft $script:automationSelected})
    (Get-AutomationControl 'AutomationConditionRemove').Add_Click({if(-not(Save-AutomationDraft)){return};$selected=(Get-AutomationControl 'AutomationConditions').SelectedItem;$script:automationSelected.conditions=@($script:automationSelected.conditions|Where-Object{$_ -ne $selected});Show-AutomationDraft $script:automationSelected})
    foreach($spec in @(@('AutomationList',@(@('Add action','AutomationNew'),@('Duplicate','AutomationDuplicate'),@('Move up','AutomationUp'),@('Move down','AutomationDown'),@('Remove','AutomationDelete'))),@('AutomationTriggers',@(@('Add selected trigger','AutomationTriggerAdd'),@('Remove','AutomationTriggerRemove'))),@('AutomationSteps',@(@('Add sub-action','AutomationStepAdd'),@('Edit','AutomationStepEdit'),@('Move up','AutomationStepUp'),@('Move down','AutomationStepDown'),@('Remove','AutomationStepRemove'))))){
        $control=Get-AutomationControl $spec[0];$menu=[Windows.Controls.ContextMenu]::new()
        foreach($entry in $spec[1]){$item=[Windows.Controls.MenuItem]::new();$item.Header=$entry[0];$item.Tag=$entry[1];$item.Add_Click({param($sender,$e)$button=Get-AutomationControl $sender.Tag;if($button.IsEnabled){$button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))}});[void]$menu.Items.Add($item)}
        $control.Add_PreviewMouseRightButtonDown({param($sender,$e)
            $container=[Windows.Controls.ItemsControl]::ContainerFromElement($sender,$e.OriginalSource)
            if($container){$sender.SelectedItem=$sender.ItemContainerGenerator.ItemFromContainer($container)}
        })
        $menu.Add_Opened({param($sender,$e)
            $list=$sender.PlacementTarget
            foreach($item in $sender.Items){
                $button=Get-AutomationControl $item.Tag
                $item.IsEnabled=$button.IsEnabled -and ($item.Tag -in @('AutomationNew','AutomationTriggerAdd','AutomationStepAdd') -or $null -ne $list.SelectedItem)
                if($item.Tag -match '(Up|Down)$'){$index=$list.SelectedIndex;$item.IsEnabled=$item.IsEnabled -and $(if($item.Tag -match 'Up$'){$index -gt 0}else{$index -lt $list.Items.Count-1})}
            }
        })
        $control.ContextMenu=$menu
    }
    (Get-AutomationControl 'AutomationList').Add_SelectionChanged({
        if($script:automationSelecting){return}
        if(-not(Save-AutomationDraft)){$script:automationSelecting=$true;(Get-AutomationControl 'AutomationList').SelectedItem=$script:automationSelected;$script:automationSelecting=$false;return}
        Show-AutomationDraft (Get-AutomationControl 'AutomationList').SelectedItem
    })
    (Get-AutomationControl 'AutomationNew').Add_Click({if(-not $script:automationLoaded){$script:automationCreateAfterLoad=$true;Start-AutomationLoad;return};if(-not(Save-AutomationDraft)){return};(Get-AutomationControl 'AutomationSearch').Text='';$rule=[pscustomobject]@{id=[guid]::NewGuid().ToString();name='New action';enabled=$true;triggers=@();steps=@();conditions=@();onError='stop'};$script:automationRules+= $rule;Refresh-AutomationList $rule;(Get-AutomationControl 'AutomationName').Focus()|Out-Null})
    (Get-AutomationControl 'AutomationDuplicate').Add_Click({if(-not(Save-AutomationDraft) -or -not $script:automationSelected){return};$copy=$script:automationSelected|ConvertTo-Json -Depth 30|ConvertFrom-Json;$copy.id=[guid]::NewGuid().ToString();$copy.name+=' copy';$script:automationRules+=$copy;Refresh-AutomationList $copy})
    (Get-AutomationControl 'AutomationDelete').Add_Click({$id=$script:automationSelected.id;$script:automationRules=@($script:automationRules|Where-Object{$_.id -ne $id});Refresh-AutomationList (@($script:automationRules)[0])})
    (Get-AutomationControl 'AutomationUp').Add_Click({Move-AutomationItem 'rule' -1});(Get-AutomationControl 'AutomationDown').Add_Click({Move-AutomationItem 'rule' 1})
    (Get-AutomationControl 'AutomationTriggerAdd').Add_Click({if(-not(Save-AutomationDraft) -or -not $script:automationSelected){return};$trigger=(Get-AutomationControl 'AutomationTriggerPicker').SelectedItem;if($trigger){$script:automationSelected.triggers+= [pscustomobject]@{source=$trigger.source;event=$trigger.event};Show-AutomationDraft $script:automationSelected}})
    (Get-AutomationControl 'AutomationTriggerRemove').Add_Click({if(-not(Save-AutomationDraft)){return};$selected=(Get-AutomationControl 'AutomationTriggers').SelectedItem;$script:automationSelected.triggers=@($script:automationSelected.triggers|Where-Object{$_ -ne $selected});Show-AutomationDraft $script:automationSelected})
    (Get-AutomationControl 'AutomationStepAdd').Add_Click({if(-not(Save-AutomationDraft) -or -not $script:automationSelected){return};$step=Show-AutomationStep $null;if($step){$script:automationSelected.steps+=$step;Show-AutomationDraft $script:automationSelected}})
    (Get-AutomationControl 'AutomationStepEdit').Add_Click({if(-not(Save-AutomationDraft)){return};$control=Get-AutomationControl 'AutomationSteps';$old=$control.SelectedItem;if(-not $old){return};$step=Show-AutomationStep $old;if($step){$step.enabled=$old.enabled;$script:automationSelected.steps=@($script:automationSelected.steps|ForEach-Object{if($_ -eq $old){$step}else{$_}});Show-AutomationDraft $script:automationSelected}})
    (Get-AutomationControl 'AutomationSteps').Add_MouseDoubleClick({(Get-AutomationControl 'AutomationStepEdit').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))})
    (Get-AutomationControl 'AutomationStepRemove').Add_Click({if(-not(Save-AutomationDraft)){return};$selected=(Get-AutomationControl 'AutomationSteps').SelectedItem;$script:automationSelected.steps=@($script:automationSelected.steps|Where-Object{$_ -ne $selected});Show-AutomationDraft $script:automationSelected})
    (Get-AutomationControl 'AutomationStepUp').Add_Click({Move-AutomationItem 'step' -1});(Get-AutomationControl 'AutomationStepDown').Add_Click({Move-AutomationItem 'step' 1})
    (Get-AutomationControl 'AutomationSave').Add_Click({
        if(-not(Save-AutomationDraft)){return}
        try{$result=(Invoke-BridgePost '/api/automations/save' @{rules=@($script:automationRules)}).result;$id=$script:automationSelected.id;$script:automationRules=@($result.rules);Refresh-AutomationList (@($script:automationRules|Where-Object{$_.id -eq $id})[0]);Update-AutomationLegacyUi $true;Set-AutomationMessage 'Actions saved. Existing playback hooks are now managed here. Runs are queued in saved order.'}
        catch{Set-AutomationMessage $_.Exception.Message}
    })
}
