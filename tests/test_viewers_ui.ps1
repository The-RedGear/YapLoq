param([string]$OutputDirectory='')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Xaml,System.Windows.Forms,System.Drawing,System.Security
$appRoot=Split-Path -Parent $PSScriptRoot;$resourceRoot=$appRoot
$configDir=Join-Path $appRoot ('data/ui-test-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($configDir)
$configPath=Join-Path $configDir 'settings.json';$logPath=Join-Path $configDir 'bridge.log';$legacyConfigDir=Join-Path $configDir 'no-legacy'
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $appRoot 'YapLoq.ps1'),[ref]$tokens,[ref]$errors)
foreach($definition in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)){Invoke-Expression $definition.Extent.Text}
Initialize-RoundedChrome;$window=Load-Xaml (Join-Path $appRoot 'YapLoq.xaml')
[xml]$markup=Get-Content -LiteralPath (Join-Path $appRoot 'YapLoq.xaml') -Raw
foreach($node in $markup.SelectNodes('//*[@Name]')){Set-Variable -Name $node.GetAttribute('Name') -Value $window.FindName($node.GetAttribute('Name'))}
$script:profiles=@{};$script:profileModels=@{};$script:profileModelOptions=@{};$script:servicesExpanded=$true;$script:loadingSettings=$false;$script:isPreview=$true
Apply-AppFont $window
. (Join-Path $resourceRoot 'assets/RuleEditors.ps1');Install-NumericEditors;Install-ProfanityEditor;Refresh-Grid;Install-ServiceGuides
. (Join-Path $resourceRoot 'assets/YapLoqShell.ps1')
# Production installs the shell before the first settings refresh.
$VoiceRulesGrid.ItemsSource=$null
Install-YapLoqShell
Refresh-Grid
function Start-ViewerLoad {}
$entry=[pscustomobject]@{platform='twitch';userId='123';displayName='Example viewer';login='viewer';voice='EventVoice';available=$true;warning='';assignmentOrigin='Viewer preference'}
Apply-ViewerList ([pscustomobject]@{viewers=@($entry);voices=@('EventVoice','playlist:Characters')})
Apply-ViewerList ([pscustomobject]@{viewers=@($entry,[pscustomobject]@{platform='twitch';userId='789';displayName='Default viewer';voice='';available=$true});voices=@('EventVoice','playlist:Characters')})
if((Get-ViewerControl 'ViewerList').Items.Count -ne 1){throw 'Default viewer appeared in Assignments'}
(Get-ViewerControl 'ViewerList').SelectedIndex=0
if((Get-ViewerControl 'ViewerPlatform') -isnot [Windows.Controls.ComboBox] -or (Get-ViewerControl 'ViewerPlatform').IsEditable){throw 'Platform must be a noneditable dropdown'}
if((Get-ViewerControl 'ViewerPlatform').SelectedValue -ne 'twitch' -or (Get-ViewerControl 'ViewerPlatform').IsEnabled){throw 'Saved platform identity was not restored and protected'}
foreach($platform in @('twitch','youtube','kick','discord','tiktok','facebook','trovo')){if($platform -notin @((Get-ViewerControl 'ViewerPlatform').Items|ForEach-Object{$_.Tag})){throw "Missing platform: $platform"}}
if((Get-ViewerControl 'ViewerVoice').SelectedValue -ne 'EventVoice' -or -not (Get-ViewerControl 'ViewerId').IsReadOnly){throw 'Viewer selection did not restore or protect identity'}
if($script:assignmentSectionButtons.Count -ne 2 -or $script:assignmentSectionButtons.ContainsKey('Default voice') -or $script:assignmentSectionButtons.ContainsKey('Viewer commands')){throw 'Assignments retained unnecessary tabs'}
if($script:assignmentDefaultPicker.Parent -ne $script:assignmentSectionButtons.Viewers.Parent){throw 'Fallback voice is not inline with Assignments controls'}
if('user' -in @($VoiceRuleFieldBox.Items|ForEach-Object{$_.Tag})){throw 'Name defaults are still offered'}
if($script:speechInputExpander.IsExpanded -or $script:speechInputExpander.Style -ne $window.FindResource('SettingsExpander') -or $script:speechInputCard.CornerRadius.TopLeft -ne 12){throw 'Speech input is not a matching collapsed settings card'}
$settingsStack=$window.FindName('SettingsStack')
if($settingsStack.Children.IndexOf($script:speechInputCard) -ge $settingsStack.Children.IndexOf($window.FindName('WindowSettingsExpander').Parent)){throw 'Speech input is below the general/about settings'}
if($script:assignmentTemplatesCard.Parent -ne $StreamerBotPage.Content -or $script:viewerTemplatePlatform.Parent.Parent -ne $script:assignmentTemplatesExpander.Content){throw 'Integration templates were not moved to Streamer.Bot Connection'}
(Get-ViewerControl 'ViewerSearch').Text='not found'
if((Get-ViewerControl 'ViewerList').Items.Count -ne 0){throw 'Viewer search failed'}
(Get-ViewerControl 'ViewerSearch').Text='123'
if((Get-ViewerControl 'ViewerList').Items.Count -ne 1){throw 'Viewer ID search failed'}
(Get-ViewerControl 'ViewerList').SelectedIndex=0
function Invoke-BridgePost([string]$path,$body=@{}){$script:viewerSaved=$body;[pscustomobject]@{result=$body}}
$click=[Windows.Controls.Button]::ClickEvent
(Get-ViewerControl 'ViewerVoice').SelectedValue='playlist:Characters'
(Get-ViewerControl 'ViewerSave').RaiseEvent([Windows.RoutedEventArgs]::new($click))
if($script:viewerSaved.voice -ne 'playlist:Characters' -or $script:viewerSaved.userId -ne '123'){throw 'Assignment save failed'}
(Get-ViewerControl 'ViewerReset').RaiseEvent([Windows.RoutedEventArgs]::new($click))
if($script:viewerSaved.voice -ne ''){throw 'Reset did not clear the assignment'}
function Show-AppConfirmation($owner,$message,$title){return $true}
(Get-ViewerControl 'ViewerDelete').RaiseEvent([Windows.RoutedEventArgs]::new($click))
if($script:viewerSaved.userId -ne '123' -or $script:viewerSaved.platform -ne 'twitch'){throw 'Delete did not target selected viewer'}
(Get-ViewerControl 'ViewerEdit').RaiseEvent([Windows.RoutedEventArgs]::new($click))
if((Get-ViewerControl 'ViewerId').IsReadOnly -or -not (Get-ViewerControl 'ViewerPlatform').IsEnabled){throw 'Edit viewer did not unlock identity correction'}
(Get-ViewerControl 'ViewerId').Text='456'
(Get-ViewerControl 'ViewerSave').RaiseEvent([Windows.RoutedEventArgs]::new($click))
if($script:viewerSaved.userId -ne '456' -or $script:viewerSaved.originalIdentity.userId -ne '123'){throw 'Identity correction lost the original record key'}
$savedRequest=$script:viewerSaved
(Get-ViewerControl 'ViewerId').Text='username-not-id'
(Get-ViewerControl 'ViewerSave').RaiseEvent([Windows.RoutedEventArgs]::new($click))
if($script:viewerSaved -ne $savedRequest -or (Get-ViewerControl 'ViewerStatus').Text -notlike '*numeric user ID*'){throw 'Twitch username was accepted as a stable ID'}
Set-MessageViewerDefault ([pscustomobject]@{Platform='youtube';UserId='AbC';DisplayName='Viewer';User='viewer';Alias='EventVoice'})
if($script:viewerSaved.platform -ne 'youtube' -or $script:viewerSaved.userId -cne 'AbC'){throw 'Message context assignment lost stable identity'}
$window.WindowStartupLocation='Manual';$window.Left=-20000;$window.Top=-20000;$window.ShowInTaskbar=$false;$window.Show()
$script:assignmentDefaultPicker.SelectedItem='EventVoice';Save-AssignmentDefault
if((Read-Settings).assignment_default_voice -ne 'EventVoice'){throw 'Default assignment was not persisted'}
$beforeSettings=Read-Settings;Set-JsonProperty $beforeSettings 'global_cooldown' 37;Write-Settings $beforeSettings
$RoutingGrid.ItemsSource.Add([pscustomobject]@{field='source';value='chat';alias='';priority=25;enabled=$true})
Save-AssignmentRules
if((Read-Settings).routing_rules[0].priority -ne 25 -or (Read-Settings).global_cooldown -ne 37){throw 'Assignment save lost priority-only rules or changed unrelated queue settings'}
$voice=@($PlayVoiceList.Tag|Where-Object Name -eq 'EventVoice')[0]
$voice.Accent='#87C9AF';$voice.AccentBackground='#3387C9AF';$voice.IconBrush=[Windows.Media.BrushConverter]::new().ConvertFromString('#87C9AF')
Update-AliasChoiceAppearance
$choice=[YapLoqAliasChoiceConverter]::new().Convert('EventVoice',[object],$null,[Globalization.CultureInfo]::InvariantCulture)
if($choice.AccentBrush.ToString() -ne '#FF87C9AF' -or $choice.IconGeometry -ne $voice.IconGeometry){throw 'Alias picker did not use the saved icon and color'}
foreach($name in @('PronunciationVoiceList','RouteAliasBox','VoiceRuleAliasBox','ExportVoiceAliasBox')){if(-not $window.FindName($name).Resources.Contains('AliasChoicePath')){throw "Unstyled alias selector: $name"}}
foreach($size in @(@(980,640),@(1180,760),@(1462,800))){
    $width=$size[0];$window.Width=$width;$window.Height=$size[1];Set-Page 'viewers';$window.UpdateLayout()
    if($script:activePage -ne 'assignments' -or -not @($script:sectionNav.Children|Where-Object Tag -eq 'assignments').Count){throw 'Assignments tab missing from Voices'}
    if($OutputDirectory){[void][IO.Directory]::CreateDirectory($OutputDirectory);$bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($window);$encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap));$stream=[IO.File]::Create((Join-Path $OutputDirectory ('viewers-'+$width+'.png')));try{$encoder.Save($stream)}finally{$stream.Dispose()}}
    foreach($section in @('Rules','Default voice')){
        Show-AssignmentSection $section;$window.UpdateLayout()
        if($OutputDirectory){$bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($window);$encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap));$stream=[IO.File]::Create((Join-Path $OutputDirectory ($section.Replace(' ','-')+'-'+$width+'.png')));try{$encoder.Save($stream)}finally{$stream.Dispose()}}
    }
    Show-AssignmentSection 'Viewers'
}
$picker=Get-ViewerControl 'ViewerVoice';$picker.SelectedValue='EventVoice';$picker.IsDropDownOpen=$true;$window.UpdateLayout()
$popup=$picker.Template.FindName('PART_Popup',$picker);$popup.Child.UpdateLayout()
$selected=$picker.ItemContainerGenerator.ContainerFromIndex($picker.SelectedIndex)
if($selected.Tag.AccentBrush.ToString() -ne '#FF87C9AF'){throw 'Selected alias dropdown row did not receive its own accent'}
$selected.ApplyTemplate()|Out-Null
$border=$selected.Template.FindName('Choice',$selected)
if($border.BorderBrush.ToString() -ne '#FF87C9AF'){throw 'Selected alias highlight is not the alias color'}
if($OutputDirectory -and $popup.Child.ActualWidth -gt 0){
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int][Math]::Ceiling($popup.Child.ActualWidth),[int][Math]::Ceiling($popup.Child.ActualHeight),96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($popup.Child)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap));$stream=[IO.File]::Create((Join-Path $OutputDirectory 'alias-dropdown.png'));try{$encoder.Save($stream)}finally{$stream.Dispose()}
}
$picker.IsDropDownOpen=$false
Update-AliasChoiceAppearance
if($picker.SelectedValue -ne 'EventVoice'){throw 'Appearance refresh changed the saved selector value'}
(Get-ViewerControl 'ViewerNew').RaiseEvent([Windows.RoutedEventArgs]::new($click))
if((Get-ViewerControl 'ViewerId').IsReadOnly -or (Get-ViewerControl 'ViewerId').Text){throw 'Add viewer did not create an editable blank identity'}
(Get-ViewerControl 'ViewerPlatform').SelectedValue='kick'
(Get-ViewerControl 'ViewerId').Text='kick-user-id'
(Get-ViewerControl 'ViewerSave').RaiseEvent([Windows.RoutedEventArgs]::new($click))
if($script:viewerSaved.platform -ne 'kick'){throw 'Platform dropdown did not save canonical Kick identity'}
Show-ViewerDraft ([pscustomobject]@{platform='custom-network';userId='id';displayName='Saved viewer';voice='';warning='';assignmentOrigin='Default'})
if((Get-ViewerControl 'ViewerPlatform').SelectedValue -ne 'custom-network'){throw 'Existing unlisted platform assignment was lost'}
$window.Close()
'Viewer UI passed: route, stable identity, search, assignment, reset, message context and three sizes.'
