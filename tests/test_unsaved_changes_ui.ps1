$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'test_yaploq_shell.ps1')
$chromeTimer=[Windows.Threading.DispatcherTimer]::new();$chromeTimer.Interval=[TimeSpan]::FromMilliseconds(100)
$chromeTimer.Add_Tick({param($sender,$e)
    $popup=@([Windows.PresentationSource]::CurrentSources|ForEach-Object{$_.RootVisual}|Where-Object{$_ -is [Windows.Window] -and $_.Title -eq 'Unsaved changes'})[0]
    if(-not $popup){return}
    $sender.Stop()
    if($popup.WindowStyle -ne 'None' -or -not $popup.Resources['AppDialogChrome'] -or $popup.Content.Background.Color.ToString() -ne '#FF15131D'){$script:chromeFailure='Prompt has native window chrome or wrong background'}
    $header=$popup.Content.Child.Children[0].Child
    if(-not $header.Children[0].Children[0].Source){$script:chromeFailure='Prompt is missing the YapLoq logo'}
    $header.Children[1].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
})
$chromeTimer.Start()
$choice=Show-UnsavedChangesPrompt $null 'Fixture unsaved changes.'
$chromeTimer.Stop()
if($choice -ne 'Cancel' -or $script:chromeFailure){throw ('Custom prompt close failed: '+$script:chromeFailure)}
function Show-UnsavedChangesPrompt($owner,[string]$context){$script:promptCalls++;return $script:promptChoice}
foreach($group in $script:globalSaveGroups.Values){Reset-GlobalSaveGroup $group.Key}
$script:promptCalls=0
if(-not (Confirm-GlobalSaveExit) -or $script:promptCalls){throw 'Clean exit should not prompt'}
$original=$MaxQueueSettingBox.Text;$before=[IO.File]::ReadAllText($configPath)
$MaxQueueSettingBox.Text='49';$script:promptChoice='Cancel'
if(Confirm-GlobalSaveExit){throw 'Cancel allowed app exit'}
if($MaxQueueSettingBox.Text -ne '49'){throw 'Cancel lost the draft'}
$script:promptChoice='Discard'
if(-not (Confirm-GlobalSaveExit) -or [IO.File]::ReadAllText($configPath) -ne $before){throw 'Discard wrote pending settings'}
$script:promptChoice='Save';$MaxQueueSettingBox.Text='0'
if(Confirm-GlobalSaveExit){throw 'Invalid settings allowed exit'}
if([IO.File]::ReadAllText($configPath) -ne $before){throw 'Invalid exit Save changed settings'}
$MaxQueueSettingBox.Text='49'
if(-not (Confirm-GlobalSaveExit) -or (Read-Settings).max_queue -ne 49){throw 'Exit Save did not commit valid settings'}

foreach($scenario in @('Clean','Cancel','Discard','Save','Invalid')){
    $script:promptChoice=if($scenario -eq 'Invalid'){'Save'}else{$scenario}
    $dialog=[Windows.Markup.XamlReader]::Parse('<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Width="320" Height="160"><StackPanel><TextBox Name="Draft" Text="original"/><Button Name="Save" Content="Save"/></StackPanel></Window>')
    $dialog.Resources['Scenario']=$scenario
    $dialog.FindName('Save').Add_Click({param($sender,$e)$d=[Windows.Window]::GetWindow($sender);if($d.Resources['Scenario'] -ne 'Invalid'){$d.Resources['Saved']=$true;$d.DialogResult=$true}})
    Install-EditorCloseGuard $dialog
    $dialog.Add_ContentRendered({param($sender,$e)
        if($sender.Resources['Scenario'] -ne 'Clean'){$sender.FindName('Draft').Text='changed'}
        $sender.Close()
        if($sender.Resources['Scenario'] -in @('Cancel','Invalid')){
            [void]$sender.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::ApplicationIdle,[action]{
                if(-not $sender.IsVisible -or $sender.FindName('Draft').Text -ne 'changed'){$script:editorTestFailure='Cancelled/invalid editor lost its draft'}
                $sender.Resources['DraftBaseline']=Get-EditorDraftFingerprint $sender;$sender.Close()
            }.GetNewClosure())
        }
    })
    [void]$dialog.ShowDialog()
    if($scenario -eq 'Save' -and -not $dialog.Resources['Saved']){throw 'Editor Save did not use its existing save handler'}
    if($script:editorTestFailure){throw $script:editorTestFailure}
}
'Unsaved changes passed: clean exit, Cancel, Discard, valid/invalid Save, and editor close paths.'
