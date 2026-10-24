$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$repo=Split-Path -Parent $PSScriptRoot
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'YapLoq.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'PowerShell parse errors'}
foreach($name in @('Get-VoiceAccent','Get-VoiceIconRunner','Resolve-VoiceIcon')){
    $definition=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    Invoke-Expression $definition.Extent.Text
}
$appRoot=Join-Path ([IO.Path]::GetTempPath()) ('yaploq-icon-test-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($appRoot) | Out-Null
$resourceRoot=$repo
$configDir=Join-Path $appRoot 'data'
$oldRunner=$env:YAPLOQ_ICON_RUNNER;$oldUpdate=$env:YAPLOQ_UPDATE_EXE
try{
    $env:YAPLOQ_ICON_RUNNER='';$env:YAPLOQ_UPDATE_EXE=''
    $stable=Join-Path $appRoot 'YapLoq.exe';$preview=Join-Path $appRoot 'YapLoq-preview.exe'
    [IO.File]::WriteAllBytes($preview,[byte[]]@())
    if((Get-VoiceIconRunner) -ne $preview){throw 'Preview renderer fallback missing'}
    [IO.File]::WriteAllBytes($stable,[byte[]]@())
    if((Get-VoiceIconRunner) -ne $stable){throw 'Stable installation selected preview renderer'}
    $env:YAPLOQ_UPDATE_EXE=$preview
    if((Get-VoiceIconRunner) -ne $preview){throw 'Current executable override ignored'}
    $env:YAPLOQ_ICON_RUNNER=Join-Path $appRoot 'missing.exe'
    if((Get-VoiceIconRunner) -ne $preview){throw 'Stale override blocked valid renderer'}
    # Invalid helper executable must degrade gracefully, not throw on a null child.
    $icon=Resolve-VoiceIcon 'tabler:cat' -Fetch -WarningAction SilentlyContinue
    if($icon.Loaded -or -not $icon.Geometry){throw 'Failed fetch lost safe fallback'}
    Write-Output 'PASS: stable/preview selection, stale overrides and safe failed fetch'
}finally{
    $env:YAPLOQ_ICON_RUNNER=$oldRunner;$env:YAPLOQ_UPDATE_EXE=$oldUpdate
}
