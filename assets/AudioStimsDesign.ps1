function script:Update-AudioStimAppearance {
    if(-not $script:stimLibraryGrid){return}
    Initialize-AliasChoices
    $script:stimAppearance=@{}
    foreach($row in $script:stimLibraryGrid.ItemsSource){
        $row|Add-Member NoteProperty FileCount $row.Files.Count -Force
        $mode=switch($row.PlaybackMode){'pause'{'Pause'} 'pause_without_user'{'Pause without viewer'} 'pause_with_user'{'Pause with viewer'} default{'Library sound'}}
        $row|Add-Member NoteProperty PlaybackLabel $mode -Force
        $accent=Get-VoiceAccent ([string]$row.Color)
        $row.Accent=$accent;$row.AccentBackground='#33'+$accent.Substring(1)
        $resolved=Resolve-VoiceIcon $row.IconId -Color $accent
        $brush=if($resolved.Brush){$resolved.Brush}else{[Windows.Media.BrushConverter]::new().ConvertFromString($accent)}
        $script:stimAppearance[$row.Keyword]=[pscustomobject]@{Name=$row.Keyword;Accent=$accent;AccentBackground=$row.AccentBackground;IconGeometry=$resolved.Geometry;IconBrush=$brush}
        $choice=[YapLoqAliasChoice]::new();$choice.Label=$row.Keyword;$choice.IconGeometry=$resolved.Geometry;$choice.IconBrush=$brush
        $choice.AccentBrush=[Windows.Media.BrushConverter]::new().ConvertFromString($accent);$choice.AccentBackground=[Windows.Media.BrushConverter]::new().ConvertFromString($row.AccentBackground)
        if($row.Keyword){[YapLoqAliasChoiceConverter]::Choices[$row.Keyword]=$choice}
    }
    $selected=$script:stimLibraryGrid.SelectedItem
    if($selected -and $script:stimIdentityIcon){
        $appearance=$script:stimAppearance[$selected.Keyword]
        $script:stimIdentityIcon.Data=$appearance.IconGeometry;$script:stimIdentityIcon.Fill=$appearance.IconBrush
        $script:stimIdentityBadge.Background=[Windows.Media.BrushConverter]::new().ConvertFromString($appearance.AccentBackground)
        $script:stimIdentityBadge.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFromString($appearance.Accent)
        if($script:stimColorBox){$script:stimColorBox.Tag=$selected.Color;foreach($swatch in $script:stimColorBox.Children){$swatch.BorderThickness=if($swatch.Tag -eq $selected.Color){2}else{0};$swatch.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFromString($selected.Color)}}
    }
    $script:stimLibraryGrid.Items.Refresh()
    $script:lastQueueSignature='';$script:lastHistorySignature='';$script:playerHistoryRenderedRevision=-1
}
function script:New-AudioStimSection([string]$title,$body,[bool]$expanded=$false){
    $expander=[Windows.Controls.Expander]::new();$expander.Header=$title;$expander.IsExpanded=$expanded;$expander.Style=$window.FindResource('SettingsExpander');$expander.Content=$body
    $card=[Windows.Controls.Border]::new();$card.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#1E1A27');$card.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFromString('#50485C');$card.BorderThickness=1;$card.CornerRadius=12;$card.Padding=14;$card.Margin='0,0,0,12';$card.Child=$expander
    return $card
}
function script:Install-AudioStimDesign {
    $editor=$script:stimView.FindName('Editor');$children=@($editor.Children)
    $header=$children[0];$playback=[Windows.Controls.StackPanel]::new()
    while($header.Children.Count -gt 3){$child=$header.Children[3];[void]$header.Children.Remove($child);[void]$playback.Children.Add($child)}
    $library=[Windows.Controls.StackPanel]::new()
    $editor.Children.Clear();$editor.RowDefinitions.Clear()
    foreach($child in @($children[1],$children[2],$children[3],$children[6])){
        [Windows.Controls.Grid]::SetRow($child,0)
        if($child -eq $script:stimFilesGrid){$child.Height=240}
        [void]$library.Children.Add($child)
    }
    $appearance=[Windows.Controls.StackPanel]::new()
    $label=[Windows.Controls.TextBlock]::new();$label.Text='Icon code';[void]$appearance.Children.Add($label)
    $script:stimIconBox=[Windows.Controls.TextBox]::new();$script:stimIconBox.Tag='e.g. mdi:waveform or a custom Icones code';$script:stimIconBox.Margin='0,6,0,8'
    $binding=[Windows.Data.Binding]::new('IconId');$binding.Mode='TwoWay';$binding.UpdateSourceTrigger='PropertyChanged';[void]$script:stimIconBox.SetBinding([Windows.Controls.TextBox]::TextProperty,$binding);[void]$appearance.Children.Add($script:stimIconBox)
    $browse=[Windows.Controls.Button]::new();$browse.Content='Browse icons';$browse.HorizontalAlignment='Left';$browse.Margin='0,0,0,12';$browse.Add_Click({Open-VoxLink 'https://icones.js.org/'});[void]$appearance.Children.Add($browse)
    [void]$appearance.Children.Remove($script:stimIconBox);[void]$appearance.Children.Remove($browse)
    $iconRow=[Windows.Controls.Grid]::new();$iconRow.Margin='0,6,0,12'
    foreach($width in @('*','Auto')){$column=[Windows.Controls.ColumnDefinition]::new();$column.Width=$width;$iconRow.ColumnDefinitions.Add($column)}
    $script:stimIconBox.Margin=0;$browse.Margin='10,0,0,0';$browse.VerticalAlignment='Center'
    [Windows.Controls.Grid]::SetColumn($browse,1);[void]$iconRow.Children.Add($script:stimIconBox);[void]$iconRow.Children.Add($browse);[void]$appearance.Children.Add($iconRow)
    $script:stimColorBox=[Windows.Controls.WrapPanel]::new();$script:stimColorBox.Margin='0,0,0,14';$script:stimColorBox.Resources['EditorDraftValue']=$true
    $names=@('Rose','Peach','Gold','Lime','Mint','Teal','Blue','Indigo','Violet','Orchid');$colors=@('#E6A0B1','#E8AD91','#E4CA8B','#A9C98C','#87C9AF','#86C6CB','#91B4E4','#A4A4E8','#B6A3FF','#D3A0D5')
    for($i=0;$i -lt $colors.Count;$i++){
        $item=[Windows.Controls.Button]::new();$item.Tag=$colors[$i];$item.ToolTip=$names[$i];$item.Width=30;$item.Height=30;$item.MinWidth=30;$item.MinHeight=30;$item.Padding=4;$item.Margin='0,0,8,4'
        [Windows.Automation.AutomationProperties]::SetName($item,$names[$i]+' sound color')
        $swatch=[Windows.Shapes.Ellipse]::new();$swatch.Width=18;$swatch.Height=18;$swatch.Fill=[Windows.Media.BrushConverter]::new().ConvertFromString($colors[$i]);$item.Content=$swatch
        $item.Add_Click({param($sender,$e)$row=$script:stimLibraryGrid.SelectedItem;if($row){$row.Color=[string]$sender.Tag;Update-AudioStimAppearance;Update-GlobalSaveGroup 'Audio Stims'}})
        [void]$script:stimColorBox.Children.Add($item)
    }
    $colorLabel=[Windows.Controls.TextBlock]::new();$colorLabel.Text='Highlight color';$colorLabel.Margin='0,0,0,6';[void]$appearance.Children.Add($colorLabel)
    [void]$appearance.Children.Add($script:stimColorBox)
    $script:stimIconBox.Add_LostKeyboardFocus({$script:stimIconBox.GetBindingExpression([Windows.Controls.TextBox]::TextProperty).UpdateSource();[void](Resolve-VoiceIcon $script:stimIconBox.Text -Fetch);Update-AudioStimAppearance;Update-GlobalSaveGroup 'Audio Stims'})
    $identity=[Windows.Controls.Grid]::new();$identity.Margin='0,0,0,14'
    foreach($width in @('54','*')){$col=[Windows.Controls.ColumnDefinition]::new();$col.Width=$width;$identity.ColumnDefinitions.Add($col)}
    $script:stimIdentityIcon=[Windows.Shapes.Path]::new();$script:stimIdentityIcon.Width=24;$script:stimIdentityIcon.Height=24;$script:stimIdentityIcon.Stretch='Uniform'
    $script:stimIdentityBadge=[Windows.Controls.Border]::new();$script:stimIdentityBadge.Width=42;$script:stimIdentityBadge.Height=42;$script:stimIdentityBadge.CornerRadius=9;$script:stimIdentityBadge.BorderThickness=1;$script:stimIdentityBadge.VerticalAlignment='Top';$script:stimIdentityBadge.Margin='0,25,0,0';$script:stimIdentityBadge.Child=$script:stimIdentityIcon
    [void]$identity.Children.Add($script:stimIdentityBadge);[Windows.Controls.Grid]::SetColumn($header,1);[void]$identity.Children.Add($header)
    $sections=@($identity,(New-AudioStimSection 'Sound library' $library $true),(New-AudioStimSection 'Playback & output' $playback),(New-AudioStimSection 'Icon & color' $appearance),(New-AudioStimSection 'Streamer.bot action' $children[4]),(New-AudioStimSection 'Word replacements' $children[5]),$children[7])
    for($i=0;$i -lt $sections.Count;$i++){$row=[Windows.Controls.RowDefinition]::new();$row.Height='Auto';$editor.RowDefinitions.Add($row);[Windows.Controls.Grid]::SetRow($sections[$i],$i);[void]$editor.Children.Add($sections[$i])}
    $column=[Windows.Controls.DataGridTemplateColumn]::new();$column.Header='Keyword';$column.Width='*';$template=New-AliasChoiceTemplate 'Keyword';$template.VisualTree.SetValue([Windows.FrameworkElement]::MarginProperty,[Windows.Thickness]::new(16,0,12,0));$column.CellTemplate=$template
    $script:stimLibraryGrid.Columns.Clear();[void]$script:stimLibraryGrid.Columns.Add($column);$script:stimLibraryGrid.RowStyle=$window.FindResource('SpeechGridRow')
    $script:stimLibraryGrid.Add_SelectionChanged({Update-AudioStimAppearance})
    $script:stimKeywordBox.Add_LostKeyboardFocus({Update-AudioStimAppearance})
    Install-AudioStimDialogs
}
