$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'test_yaploq_shell.ps1')
$fixtureResources=$window.Resources
foreach($scenario in @('Save','Retry','Cancel','Discard')){
    foreach($group in $script:globalSaveGroups.Values){Reset-GlobalSaveGroup $group.Key}
    $before=[IO.File]::ReadAllText($configPath)
    $MaxQueueSettingBox.Text=if($scenario -eq 'Retry'){'0'}else{'53'}
    Update-GlobalSaveGroup 'Settings'
    $window=[Windows.Window]::new();$window.Resources.MergedDictionaries.Add($fixtureResources)
    $window.Width=400;$window.Height=180;$window.ShowInTaskbar=$false;$window.WindowStartupLocation='Manual';$window.Left=-20000
    $window.Content=[Windows.Controls.TextBlock]::new();$window.Content.Text='Exit fixture'
    Install-MainWindowCloseGuard $window
    $script:exitFixtureScenario=$scenario;$script:exitFixtureClicks=0;$script:exitFixtureError=''
    $deadline=[DateTime]::UtcNow.AddSeconds(12)
    $timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[TimeSpan]::FromMilliseconds(100)
    $timer.Add_Tick({param($sender,$e)
        $popup=@([Windows.PresentationSource]::CurrentSources|ForEach-Object{$_.RootVisual}|Where-Object{$_ -is [Windows.Window] -and $_.Title -eq 'Unsaved changes'})[0]
        if([DateTime]::UtcNow -gt $deadline){$script:exitFixtureError='Exit did not finish';if($popup){$popup.Close()};$window.Resources['ExitApproved']=$true;$window.Close();$sender.Stop();return}
        if(-not $popup){return}
        $buttons=@($popup.Resources['AppDialogBody'].Children|Where-Object{$_ -is [Windows.Controls.StackPanel] -and $_.Orientation -eq 'Horizontal'})[0]
        $choice=if($script:exitFixtureScenario -in @('Cancel','Discard')){$script:exitFixtureScenario}else{'Save'}
        if($script:exitFixtureScenario -eq 'Retry' -and $script:exitFixtureClicks){
            if($popup.Resources['SaveError'].Visibility -ne 'Visible'){$script:exitFixtureError='Save error was not visible'}
            $MaxQueueSettingBox.Text='54'
        }
        $script:exitFixtureClicks++
        @($buttons.Children|Where-Object Tag -eq $choice)[0].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        if($choice -eq 'Cancel'){
            if(-not $window.IsVisible){$script:exitFixtureError='Cancel closed the app'}
            $window.Resources['ExitApproved']=$true;$window.Close()
        }
    })
    $window.Add_ContentRendered({param($sender,$e)$sender.Close()})
    $timer.Start();[void]$window.ShowDialog();$timer.Stop()
    if($script:exitFixtureError){throw ($scenario+': '+$script:exitFixtureError)}
    if($scenario -eq 'Save' -and (Read-Settings).max_queue -ne 53){throw 'Save did not persist before closing'}
    if($scenario -eq 'Retry' -and ((Read-Settings).max_queue -ne 54 -or $script:exitFixtureClicks -ne 2)){throw 'Retry did not save and close'}
    if($scenario -in @('Cancel','Discard') -and [IO.File]::ReadAllText($configPath) -ne $before){throw 'Cancel/Discard wrote settings'}
}
'Real main-window exit passed: Save closes, invalid Save stays open with an error, retry, Cancel and Discard.'
