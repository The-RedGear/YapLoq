# Service form readiness is presentation state, never a saved credential or setting.
function Get-ServiceFieldValue([string]$name) {
    if($script:credentialFields.ContainsKey($name)){return [string]$script:credentialFields[$name].Mask.Password}
    $control=$window.FindName($name)
    if($control -is [Windows.Controls.ComboBox]){return [string]$control.Text}
    return [string]$control.Text
}
function Test-ServiceFields($service) {
    if($service.Id -eq 'windows'){return $true}
    foreach($alternatives in $service.Required){
        $complete=$true
        foreach($name in ($alternatives -split ',')){if(-not (Get-ServiceFieldValue $name).Trim()){$complete=$false}}
        if($complete){return $true}
    }
    return $false
}
function Update-ServiceConnectionForms {
    foreach($service in $script:serviceForms.Values){
        $ready=Test-ServiceFields $service
        $busy=$service.State -eq 'connecting'
        if($service.Button){$service.Button.IsEnabled=([bool]$service.Enabled.IsChecked -and $ready -and -not $busy);$service.Button.ToolTip=if(-not $ready){'Fill in the required connection fields first.'}elseif($busy){'Connecting...'}else{'Test connection and load voices'}}
    }
}
function Update-ServiceSecretPlaceholder($sender) {
    $entry=$sender.Resources['YapLoqCredential']
    if($entry -and $entry.Mask.Resources.Contains('CredentialPlaceholder')){
        $entry.Mask.Resources['CredentialPlaceholder'].Visibility=if($entry.Mask.Password -or $entry.Mask.IsKeyboardFocusWithin -or $entry.Unavailable){'Collapsed'}else{'Visible'}
    }
}
function Install-ServicePlaceholders {
    $hints=@{
        UrlBox='http://127.0.0.1:7860';KeyBox='API key (optional)'
        PollyAccessKeyBox='AWS access key ID';PollySecretKeyBox='AWS secret access key';PollySessionTokenBox='Session token (temporary credentials only)';PollyProfileBox='AWS profile name (alternative to keys)'
        ElevenLabsApiKeyBox='ElevenLabs API key';AzureKeyBox='Azure Speech resource key';AzureRegionBox='Resource region, e.g. eastus'
        GoogleApiKeyBox='Google Cloud API key';GoogleServiceAccountBox='Path to service-account JSON (alternative to API key)'
        WatsonApiKeyBox='IBM Cloud API key';WatsonServiceUrlBox='Text to Speech service URL'
        UberDuckApiKeyBox='UberDuck API key';TtsMonsterTokenBox='TTS.Monster API token';TtsMonsterOverlayBox='Overlay URL (alternative to token)'
        AcapelaAccountBox='Acapela account / login ID';AcapelaPasswordBox='Acapela password';AcapelaAppNameBox='Application name'
        CereProcUsernameBox='CereProc username';CereProcPasswordBox='CereProc password'
    }
    foreach($name in $hints.Keys){
        $control=$window.FindName($name);$control.ToolTip=$hints[$name]
        if($script:credentialFields.ContainsKey($name)){
            $entry=$script:credentialFields[$name];$entry.Plain.Tag=$hints[$name]
            $placeholder=[Windows.Controls.TextBlock]::new();$placeholder.Text=$hints[$name];$placeholder.Foreground=$window.FindResource('Muted');$placeholder.Margin='12,0';$placeholder.VerticalAlignment='Center';$placeholder.IsHitTestVisible=$false;$placeholder.TextTrimming='CharacterEllipsis'
            $entry.Mask.Resources['CredentialPlaceholder']=$placeholder
            [void]$entry.Mask.Parent.Children.Add($placeholder)
            $entry.Mask.Add_PasswordChanged({param($sender,$e)Update-ServiceSecretPlaceholder $sender})
            $entry.Mask.Add_GotKeyboardFocus({param($sender,$e)Update-ServiceSecretPlaceholder $sender})
            $entry.Mask.Add_LostKeyboardFocus({param($sender,$e)Update-ServiceSecretPlaceholder $sender})
            Update-ServiceSecretPlaceholder $entry.Mask
        }else{$control.Tag=$hints[$name]}
    }
}
function Reset-ServiceConnection($sender) {
    if($script:loadingSettings -or $script:globalSaveStaging){return}
    $credential=$sender.Resources['YapLoqCredential'];if($credential -and $credential.Syncing){return}
    $id=[string]$sender.Resources['ServiceConnectionId'];if(-not $id){return}
    $service=$script:serviceForms[$id];$service.Revision++;$service.State='offline'
    Update-ServiceConnectionForms
    Update-BridgeStatus ([bool]$script:backendOnline)
}
function Start-ServiceConnectionChecks {
    if(-not $script:serviceForms){return}
    foreach($service in $script:serviceForms.Values){
        if($service.Enabled.IsChecked -and (Test-ServiceFields $service)){$service.State='connecting';$service.CheckRevision=$service.Revision}
    }
    Update-ServiceConnectionForms;Update-BridgeStatus ([bool]$script:backendOnline)
}
function Complete-ServiceConnectionChecks($voices,$errors,[bool]$failed=$false) {
    if(-not $script:serviceForms){return}
    foreach($service in $script:serviceForms.Values){
        if($service.State -ne 'connecting' -or $service.CheckRevision -ne $service.Revision){continue}
        $hasVoices=@($voices|Where-Object{$_.provider -eq $service.Id}).Count -gt 0
        $hasError=@($errors|Where-Object{([string]$_).StartsWith($service.Name+':',[StringComparison]::OrdinalIgnoreCase)}).Count -gt 0
        $service.State=if(-not $failed -and $hasVoices -and -not $hasError){'connected'}else{'offline'}
    }
    Update-ServiceConnectionForms
}
function Install-ServiceConnectionForms {
    $script:serviceForms=@{}
    foreach($spec in @(
        @('voicestudio','VoiceStudio','VoiceStudio','UrlBox','UrlBox,KeyBox'),
        @('windows','Windows voices','Windows','',''),
        @('polly','Amazon Polly','Polly','PollyAccessKeyBox,PollySecretKeyBox,PollyRegionBox|PollyProfileBox,PollyRegionBox','PollyAccessKeyBox,PollySecretKeyBox,PollyRegionBox,PollyProfileBox,PollySessionTokenBox'),
        @('elevenlabs','ElevenLabs','ElevenLabs','ElevenLabsApiKeyBox','ElevenLabsApiKeyBox'),
        @('azure','Azure Speech','Azure','AzureKeyBox,AzureRegionBox','AzureKeyBox,AzureRegionBox'),
        @('google','Google Cloud TTS','Google','GoogleApiKeyBox|GoogleServiceAccountBox','GoogleApiKeyBox,GoogleServiceAccountBox'),
        @('watson','IBM Watson','Watson','WatsonApiKeyBox,WatsonServiceUrlBox','WatsonApiKeyBox,WatsonServiceUrlBox'),
        @('uberduck','UberDuck','UberDuck','UberDuckApiKeyBox','UberDuckApiKeyBox'),
        @('ttsmonster','TTS.Monster','TtsMonster','TtsMonsterTokenBox|TtsMonsterOverlayBox','TtsMonsterTokenBox,TtsMonsterOverlayBox'),
        @('acapela','Acapela','Acapela','AcapelaAccountBox,AcapelaPasswordBox,AcapelaAppNameBox','AcapelaAccountBox,AcapelaPasswordBox,AcapelaAppNameBox'),
        @('cereproc','CereProc','CereProc','CereProcUsernameBox,CereProcPasswordBox','CereProcUsernameBox,CereProcPasswordBox')
    )){
        $enabled=if($spec[0] -eq 'windows'){$WindowsVoicesCheck}else{$window.FindName($spec[2]+'EnabledCheck')}
        $service=[pscustomobject]@{Id=$spec[0];Name=$spec[1];Enabled=$enabled;Button=$window.FindName('Test'+$spec[2]+'Button');Required=@($spec[3] -split '\|');State='offline';Revision=0;CheckRevision=-1}
        $script:serviceForms[$spec[0]]=$service
        $enabled.Resources['ServiceConnectionId']=$spec[0];$enabled.Add_Click({param($sender,$e)Reset-ServiceConnection $sender})
        foreach($name in ($spec[4] -split ',')){
            if(-not $name){continue}
            $control=$window.FindName($name);$control.Resources['ServiceConnectionId']=$spec[0]
            if($script:credentialFields.ContainsKey($name)){
                $entry=$script:credentialFields[$name]
                foreach($field in @($entry.Mask,$entry.Plain)){$field.Resources['ServiceConnectionId']=$spec[0]}
                $entry.Mask.Add_PasswordChanged({param($sender,$e)Reset-ServiceConnection $sender})
                $entry.Plain.Add_TextChanged({param($sender,$e)Reset-ServiceConnection $sender})
            }elseif($control -is [Windows.Controls.ComboBox]){$control.Add_SelectionChanged({param($sender,$e)Reset-ServiceConnection $sender});$control.AddHandler([Windows.Controls.Primitives.TextBoxBase]::TextChangedEvent,[Windows.Controls.TextChangedEventHandler]{param($sender,$e)Reset-ServiceConnection $sender})}
            else{$control.Add_TextChanged({param($sender,$e)Reset-ServiceConnection $sender})}
        }
    }
    Install-ServicePlaceholders
    Update-ServiceConnectionForms
}
