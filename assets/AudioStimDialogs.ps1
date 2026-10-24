function script:New-AudioStimSliderColumn([string]$label,[string]$path,[int]$minimum){
    $column=[Windows.Controls.DataGridTemplateColumn]::new();$column.Header=$label;$column.Width=180
    $column.CellTemplate=[Windows.Markup.XamlReader]::Parse(@"
<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><Grid Margin="12,0"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="36"/></Grid.ColumnDefinitions><Slider Minimum="$minimum" Maximum="100" TickFrequency="1" IsSnapToTickEnabled="True" Value="{Binding $path,Mode=TwoWay,UpdateSourceTrigger=PropertyChanged}" VerticalAlignment="Center" ToolTip="$label"/><TextBlock Grid.Column="1" Text="{Binding $path,StringFormat=F0}" VerticalAlignment="Center" TextAlignment="Right"/></Grid></DataTemplate>
"@)
    return $column
}
function script:Install-AudioStimDialogs {
    $editor=$script:stimView.FindName('Editor');$main=$editor.Parent;$oldList=$main.Children[0];$toolbar=$oldList.Children[0]
    $sections=@($editor.Children);$identity=$sections[0];$appearance=$sections[3].Child.Content
    $sections[3].Child.Content=$null
    [void]$appearance.Children.Remove($script:stimColorBox)
    $oldLabel=@($appearance.Children|Where-Object{$_ -is [Windows.Controls.TextBlock] -and $_.Text -eq 'Highlight color'})[0];if($oldLabel){[void]$appearance.Children.Remove($oldLabel)}
    [void]$script:stimEnabledCheck.Parent.Children.Remove($script:stimEnabledCheck)
    $col=[Windows.Controls.ColumnDefinition]::new();$col.Width='Auto';$identity.ColumnDefinitions.Add($col)
    [Windows.Controls.Grid]::SetColumn($script:stimEnabledCheck,2);$script:stimEnabledCheck.Margin='12,20,0,0';$script:stimEnabledCheck.VerticalAlignment='Center';[void]$identity.Children.Add($script:stimEnabledCheck)
    $editor.Children.Clear();$editor.RowDefinitions.Clear()
    $parts=@($identity,$script:stimColorBox,$appearance,$sections[1],$sections[2],$sections[4],$sections[5],$sections[6])
    for($i=0;$i -lt $parts.Count;$i++){$row=[Windows.Controls.RowDefinition]::new();$row.Height='Auto';$editor.RowDefinitions.Add($row);[Windows.Controls.Grid]::SetRow($parts[$i],$i);[void]$editor.Children.Add($parts[$i])}
    $script:stimFilesGrid.Columns.RemoveAt(3);$script:stimFilesGrid.Columns.RemoveAt(2)
    [void]$script:stimFilesGrid.Columns.Add((New-AudioStimSliderColumn 'Volume %' 'Volume' 0));[void]$script:stimFilesGrid.Columns.Add((New-AudioStimSliderColumn 'Weight' 'Weight' 1))
    [void]$main.Children.Remove($editor);[void]$oldList.Children.Remove($toolbar);[void]$oldList.Children.Remove($script:stimLibraryGrid)
    $main.Children.Clear();$main.ColumnDefinitions.Clear()
    $workspace=[Windows.Controls.DockPanel]::new();[void]$main.Children.Add($workspace)
    [Windows.Controls.DockPanel]::SetDock($toolbar,'Top');[void]$workspace.Children.Add($toolbar)
    $script:stimView.FindName('Add').Style=$window.FindResource('PrimaryButton')
    $edit=[Windows.Controls.Button]::new();$edit.Content='Edit';$edit.Margin='8,0,0,0';$edit.Add_Click({Show-AudioStimEditor});$script:stimView.RegisterName('Edit',$edit);$toolbar.Children.Insert(1,$edit)
    $test=[Windows.Controls.Button]::new();$test.Content='Test random';$test.Margin='8,0,0,0';$test.Add_Click({Invoke-AudioStimMenu 'Random'});[void]$toolbar.Children.Add($test)
    $script:stimSearchBox=[Windows.Controls.TextBox]::new();$script:stimSearchBox.Tag='Search sounds...';$script:stimSearchBox.Margin='0,0,0,12';[Windows.Controls.DockPanel]::SetDock($script:stimSearchBox,'Top');[void]$workspace.Children.Add($script:stimSearchBox)
    [void]$workspace.Children.Add($script:stimLibraryGrid);$script:stimLibraryGrid.MinHeight=200
    $on=[Windows.Controls.DataGridCheckBoxColumn]::new();$on.Header='On';$on.Width=64;$on.Binding=[Windows.Data.Binding]::new('Enabled');$on.Binding.Mode='TwoWay';$on.ElementStyle=$script:stimFilesGrid.Columns[0].ElementStyle;$on.EditingElementStyle=$on.ElementStyle;$script:stimLibraryGrid.Columns.Insert(0,$on)
    foreach($spec in @(@('Sounds','FileCount',80),@('Playback','PlaybackLabel',180),@('Output','OutputDevice','*'))){$column=[Windows.Controls.DataGridTextColumn]::new();$column.Header=$spec[0];$column.Binding=[Windows.Data.Binding]::new($spec[1]);$column.IsReadOnly=$true;$column.Width=$spec[2];$column.ElementStyle=$window.FindResource('GridText');[void]$script:stimLibraryGrid.Columns.Add($column)}
    $script:stimSearchBox.Add_TextChanged({Filter-AudioStimLibraries})
    $script:stimLibraryGrid.Add_MouseDoubleClick({param($sender,$e)$cell=[Windows.Controls.ItemsControl]::ContainerFromElement($sender,$e.OriginalSource);if($cell -is [Windows.Controls.DataGridRow] -and $sender.SelectedItem -and $sender.CurrentCell.Column.DisplayIndex -ne 0){Show-AudioStimEditor}})
    $script:stimView.MinHeight=0
    $script:yaploqPages.stims.Content=$null
    if($script:stimView.Parent){[void]$script:stimView.Parent.Children.Remove($script:stimView)}
    $script:yaploqPages.stims.Content=$script:stimView;$script:yaploqPages.stims.VerticalScrollBarVisibility='Disabled'
}
function script:Filter-AudioStimLibraries {
    $view=[Windows.Data.CollectionViewSource]::GetDefaultView($script:stimLibraryGrid.ItemsSource)
    if($view){$view.Filter=[Predicate[object]]{param($row) $script:stimDialogOpen -or -not $script:stimSearchBox.Text.Trim() -or $row.Keyword.IndexOf($script:stimSearchBox.Text.Trim(),[StringComparison]::OrdinalIgnoreCase) -ge 0}}
}
function script:New-AudioStimEditor([switch]$New){
    if($script:stimDialogOpen){throw 'A sound editor is already open.'}
    $original=if($New){$null}else{$script:stimLibraryGrid.SelectedItem};if(-not $New -and -not $original){return $null}
    $script:stimDialogOpen=$true
    if($New){$row=New-AudioStimRow '' @{};$index=$script:stimLibraryGrid.ItemsSource.Count;$script:stimLibraryGrid.ItemsSource.Add($row)}else{
        $index=$script:stimLibraryGrid.ItemsSource.IndexOf($original);$row=$original.PSObject.Copy();$row.Files=[Collections.ObjectModel.ObservableCollection[object]]::new();foreach($file in $original.Files){$row.Files.Add($file.PSObject.Copy())};$script:stimLibraryGrid.ItemsSource[$index]=$row
    }
    Filter-AudioStimLibraries;$script:stimLibraryGrid.SelectedItem=$row
    $dialog=[Windows.Window]::new();$dialog.Title='Audio Stim';$dialog.Width=880;$dialog.Height=820;$dialog.MinWidth=720;$dialog.MinHeight=500;$dialog.MaxHeight=[Windows.SystemParameters]::WorkArea.Height-24;$dialog.WindowStartupLocation='CenterOwner';$dialog.ResizeMode='CanResize';$dialog.Owner=$window
    $dialog.Resources.MergedDictionaries.Add($window.Resources)
    $dialog.Resources['Original']=$original;$dialog.Resources['Index']=$index;$dialog.Resources['Row']=$row;$dialog.Resources['Baseline']=($row|ConvertTo-Json -Depth 24 -Compress)
    $script:stimEditorWindow=$dialog
    $layout=[Windows.Controls.Grid]::new();foreach($height in @('*','Auto')){$def=[Windows.Controls.RowDefinition]::new();$def.Height=$height;$layout.RowDefinitions.Add($def)}
    $scroll=[Windows.Controls.ScrollViewer]::new();$scroll.VerticalScrollBarVisibility='Auto';$scroll.Margin='20,18,20,0';$scroll.Content=$script:stimView.FindName('Editor');[void]$layout.Children.Add($scroll);$dialog.Resources['EditorScroll']=$scroll
    $footer=[Windows.Controls.StackPanel]::new();$footer.Orientation='Horizontal';$footer.HorizontalAlignment='Right';$footer.Margin=16;[Windows.Controls.Grid]::SetRow($footer,1);[void]$layout.Children.Add($footer)
    $cancel=[Windows.Controls.Button]::new();$cancel.Content='Cancel';$cancel.Margin='0,0,10,0';$cancel.Add_Click({$script:stimEditorWindow.Close()});[void]$footer.Children.Add($cancel)
    $save=[Windows.Controls.Button]::new();$save.Content='Save stim';$save.Style=$window.FindResource('PrimaryButton');$save.Add_Click({try{Save-AudioStims;$script:stimEditorWindow.Resources['Accepted']=$true;$script:stimEditorWindow.Close()}catch{$script:stimView.FindName('Status').Text=$_.Exception.Message;$script:stimView.FindName('Status').BringIntoView()}});[void]$footer.Children.Add($save);$dialog.Resources['SaveButton']=$save
    $dialog.Content=$layout;Apply-AppFont $dialog;Set-AppDialogChrome $dialog
    $dialog.Add_Closing({param($sender,$e)
        if($sender.Resources['Accepted']){return}
        $row=$sender.Resources['Row'];$script:stimFilesGrid.CommitEdit()|Out-Null
        if(($row|ConvertTo-Json -Depth 24 -Compress) -cne $sender.Resources['Baseline']){
            $choice=Show-UnsavedChangesPrompt $sender 'This sound has unsaved changes.' {Save-AudioStims;$script:stimEditorWindow.Resources['Accepted']=$true}
            if($choice -eq 'Cancel'){$e.Cancel=$true}
        }
    })
    $dialog.Add_Closed({param($sender,$e)
        $sender.Resources['EditorScroll'].Content=$null
        $index=[int]$sender.Resources['Index'];$original=$sender.Resources['Original']
        if(-not $sender.Resources['Accepted']){if($original){$script:stimLibraryGrid.ItemsSource[$index]=$original;$script:stimLibraryGrid.SelectedItem=$original}else{$script:stimLibraryGrid.ItemsSource.RemoveAt($index)}}
        $script:stimDialogOpen=$false;$script:stimEditorWindow=$null;Update-AudioStimAppearance;Filter-AudioStimLibraries
        if($sender.Resources['Accepted']){Reset-GlobalSaveGroup 'Audio Stims'}else{Update-GlobalSaveGroup 'Audio Stims'}
    })
    return $dialog
}
function script:Show-AudioStimEditor([switch]$New){
    $dialog=New-AudioStimEditor -New:$New
    if($dialog){[void]$dialog.ShowDialog()}
}
