param([string]$OutputDirectory='', [switch]$LiveLoad)
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
. (Join-Path $resourceRoot 'assets/YapLoqShell.ps1');Install-YapLoqShell
if($LiveLoad){
    $script:httpPort=17582
    (Get-AutomationControl 'AutomationEmptyAdd').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    $deadline=[DateTime]::UtcNow.AddSeconds(8)
    while($script:automationLoadTask -and [DateTime]::UtcNow -lt $deadline){
        $frame=[Windows.Threading.DispatcherFrame]::new()
        $window.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background,[action]{$frame.Continue=$false})|Out-Null
        [Windows.Threading.Dispatcher]::PushFrame($frame)
        Start-Sleep -Milliseconds 20
    }
    if(-not $script:automationLoaded){throw ('Real startup load failed: '+(Get-AutomationControl 'AutomationStatus').Text)}
    if($script:automationRules.Count -ne 1 -or -not (Get-AutomationControl 'AutomationName').IsEnabled){throw 'Click during startup did not create and enable the first action'}
    $script:automationRules=@();Refresh-AutomationList $null
}
$script:automationLoaded=$true
(Get-AutomationControl 'AutomationSave').IsEnabled=$true
$script:automationEventCatalog=@([pscustomobject]@{source='texttospeech';event='playing';label='Playback started'},[pscustomobject]@{source='viewer';event='voiceassigned';label='Viewer voice set successfully'})
$click=[Windows.Controls.Button]::ClickEvent
# Start from the actual empty-library state, not a preselected draft.
Refresh-AutomationList $null
(Get-AutomationControl 'AutomationNew').RaiseEvent([Windows.RoutedEventArgs]::new($click))
if($script:automationRules.Count -ne 1 -or -not (Get-AutomationControl 'AutomationName').IsEnabled){throw 'Empty library cannot create its first action'}
$script:automationRules=@();Refresh-AutomationList $null
$newMenu=(Get-AutomationControl 'AutomationList').ContextMenu.Items[0]
if($newMenu.Tag -ne 'AutomationNew'){throw 'Empty action list has no right-click Add action option'}
$newMenu.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
if($script:automationRules.Count -ne 1){throw 'Right-click Add action did not create a draft'}
(Get-AutomationControl 'AutomationName').Text='Avatar sequence'
$window.Show();Set-Page 'streamActions';$window.UpdateLayout()
(Get-AutomationControl 'AutomationTriggerAdd').RaiseEvent([Windows.RoutedEventArgs]::new($click))
$browse=(Get-AutomationControl 'AutomationTriggerAdd').ContextMenu
$browse.UpdateLayout()
if(($browse.Items.Header -join ',') -ne 'Playback,Viewers'){throw 'Trigger categories missing or incorrectly grouped'}
$browse.Items[0].IsSubmenuOpen=$true
if(-not $browse.Items[0].IsSubmenuOpen -or $browse.Items[0].Items[0].Header -ne 'Playback started'){throw 'Category submenu did not open'}
$browse.Items[0].Items[0].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
$browse.IsOpen=$false
if($script:automationSelected.name -ne 'Avatar sequence' -or $script:automationSelected.triggers.Count -ne 1){throw 'Action edit or trigger selection failed'}
$triggerMenu=(Get-AutomationControl 'AutomationTriggers').ContextMenu
$triggerMenu.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.ContextMenu]::OpenedEvent))
if($triggerMenu.Items.Count -ne 2){throw 'Trigger context menu missing'}
(Get-AutomationControl 'AutomationTriggers').SelectedIndex=0
$triggerMenu.Items[1].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
if($script:automationSelected.triggers.Count -ne 0){throw 'Right-click Remove trigger failed'}
$triggerMenu.Items[0].Items[0].Items[0].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
Add-AutomationTrigger $script:automationEventCatalog[0]
if($script:automationSelected.triggers.Count -ne 1){throw 'Duplicate trigger was added'}
$script:automationSelected.steps=@([pscustomobject]@{type='action';action='Show avatar';enabled=$true;args=[pscustomobject]@{}},[pscustomobject]@{type='delay';seconds=2;enabled=$true})
Show-AutomationDraft $script:automationSelected
(Get-AutomationControl 'AutomationSteps').SelectedIndex=1
Move-AutomationItem 'step' -1
if($script:automationSelected.steps[0].type -ne 'delay'){throw 'Sub-action ordering failed'}
$stepMenu=(Get-AutomationControl 'AutomationSteps').ContextMenu
($stepMenu.Items|Where-Object Tag -eq 'AutomationStepDown').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
if($script:automationSelected.steps[1].type -ne 'delay'){throw 'Right-click Move down failed'}
Move-AutomationItem 'step' -1
(Get-AutomationControl 'AutomationDuplicate').RaiseEvent([Windows.RoutedEventArgs]::new($click))
if($script:automationRules.Count -ne 2 -or $script:automationRules[0].id -eq $script:automationRules[1].id){throw 'Action duplication failed'}
Move-AutomationItem 'rule' -1
if($script:automationRules[0].name -notlike '*copy'){throw 'Action-list ordering failed'}
function Invoke-BridgePost([string]$path,$body=@{}){$script:automationSaved=$body;[pscustomobject]@{result=[pscustomobject]@{rules=@($body.rules)}}}
(Get-AutomationControl 'AutomationSave').RaiseEvent([Windows.RoutedEventArgs]::new($click))
if($script:automationSaved.rules.Count -ne 2){throw 'Save did not include the ordered automation definitions'}
$window.WindowStartupLocation='Manual';$window.Left=-20000;$window.Top=-20000;$window.ShowInTaskbar=$false;$window.Show()
$window.Dispatcher.BeginInvoke([action]{
    $d=$script:automationStepDialog;$d.FindName('StepType').SelectedIndex=1;$d.FindName('StepDelay').Text='1.5';$d.FindName('StepSave').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
})|Out-Null
$delay=Show-AutomationStep $null
if($delay.type -ne 'delay' -or $delay.seconds -ne 1.5){throw 'Delay editor did not return its saved value'}
$window.Dispatcher.BeginInvoke([action]{
    $d=$script:automationStepDialog;$d.FindName('StepActionPicker').Text='Existing avatar';$d.FindName('StepArguments').Text='{"message":"{ttsText}"}';$d.FindName('StepSave').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
})|Out-Null
$action=Show-AutomationStep $null
if($action.action -ne 'Existing avatar' -or $action.args.message -ne '{ttsText}'){throw 'Action editor lost the target or event argument'}
$script:automationRemoteActions=@([pscustomobject]@{id='avatar-id';name='Show avatar'})
$window.Dispatcher.BeginInvoke([action]{
    $d=$script:automationStepDialog
    if($OutputDirectory){
        [void][IO.Directory]::CreateDirectory($OutputDirectory);$d.UpdateLayout()
        $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$d.ActualWidth,[int]$d.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($d)
        $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap));$stream=[IO.File]::Create((Join-Path $OutputDirectory 'sub-action.png'));try{$encoder.Save($stream)}finally{$stream.Dispose()}
    }
    $d.FindName('StepActionPicker').SelectedIndex=0;$d.FindName('StepArguments').Text='';$d.FindName('StepSave').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
})|Out-Null
$picked=Show-AutomationStep $null
if($picked.action -ne 'avatar-id' -or $picked.label -ne 'Show avatar'){throw 'Dropdown selection did not preserve the action ID and name'}
$window.Dispatcher.BeginInvoke([action]{
    $d=$script:automationStepDialog;$d.FindName('StepActionPicker').Text='Show avatar';$d.FindName('StepSave').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
})|Out-Null
$typed=Show-AutomationStep $null
if($typed.action -ne 'avatar-id'){throw 'Typed loaded action name did not resolve to its ID'}
$script:automationRemoteActions=@(1..5000|ForEach-Object{[pscustomobject]@{id=('id-'+$_);name=('Action '+$_.ToString('00000'))}})
$window.Dispatcher.BeginInvoke([action]{
    $d=$script:automationStepDialog;$picker=$d.FindName('StepActionPicker')
    if($picker.Items.Count -ne 100){throw 'Large action catalogue was not bounded to 100 visible results'}
    $picker.Text='Action 04999'
    if(-not $d.Resources['SearchTimer'].IsEnabled){throw 'Typing did not schedule dropdown filtering'}
    Update-AutomationActionSearch $d
    if($picker.Items.Count -ne 1 -or $picker.Items[0].id -ne 'id-4999' -or $picker.Text -ne 'Action 04999'){throw 'Large catalogue filtering lost typed input or returned wrong actions'}
    $picker.Text='no such action';Update-AutomationActionSearch $d
    if($picker.Items.Count -ne 0){throw 'Nonmatching actions were not filtered out'}
    $picker.Text='Action 04999';Update-AutomationActionSearch $d
    $d.FindName('StepSave').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
})|Out-Null
$filtered=Show-AutomationStep $null
if($filtered.action -ne 'id-4999'){throw 'Filtered action did not save its stable ID'}
$window.WindowStartupLocation='Manual';$window.Left=-20000;$window.Top=-20000;$window.ShowInTaskbar=$false;$window.Show()
foreach($size in @(@(980,640),@(1180,760),@(1462,800))){
    $width=$size[0];$window.Width=$width;$window.Height=$size[1];Set-Page 'streamActions';$window.UpdateLayout()
    $button=Get-AutomationControl 'AutomationNew'
    $point=$button.TranslatePoint([Windows.Point]::new($button.ActualWidth/2,$button.ActualHeight/2),$window)
    $hit=$window.InputHitTest($point)
    while($hit -and $hit -ne $button){$hit=[Windows.Media.VisualTreeHelper]::GetParent($hit)}
    if($hit -ne $button){throw "Add action is blocked at width $width"}
    if($script:sectionNav.Children[0].Content.Children[1].Text -ne 'Actions' -or $script:sectionNav.Children[1].Content.Children[1].Text -ne 'Connection'){throw 'Streamer.Bot tabs missing'}
    if($OutputDirectory){[void][IO.Directory]::CreateDirectory($OutputDirectory);$bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($window);$encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap));$stream=[IO.File]::Create((Join-Path $OutputDirectory ('automations-'+$width+'.png')));try{$encoder.Save($stream)}finally{$stream.Dispose()}}
}
$window.Close()
'Automation UI passed: tabs, drafts, triggers, sub-action order, duplication, action order, save and three window sizes.'
