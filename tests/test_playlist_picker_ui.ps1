param([string]$OutputImage='')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Xaml
$root=Split-Path -Parent $PSScriptRoot
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'YapLoq.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'PowerShell parse errors'}
foreach($definition in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)){Invoke-Expression $definition.Extent.Text}
Initialize-RoundedChrome
$window=Load-Xaml (Join-Path $root 'YapLoq.xaml')
. (Join-Path $root 'assets/AliasChoices.ps1')
Initialize-AliasChoices
$choice=[YapLoqAliasChoice]::new();$choice.Label='Arbiter';$choice.AccentBrush=[Windows.Media.BrushConverter]::new().ConvertFromString('#86C6CB');$choice.IconBrush=$choice.AccentBrush;$choice.IconGeometry=[Windows.Media.Geometry]::Parse('M2 2H20V20H2Z')
[YapLoqAliasChoiceConverter]::Choices['Arbiter']=$choice
$row=New-PlaylistVoiceCheck 'Arbiter' $true
$panel=[Windows.Controls.StackPanel]::new();$panel.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#1E1A27');$panel.Width=450;$panel.Height=150
[void]$panel.Children.Add($row)
$panel.Measure([Windows.Size]::new(450,150));$panel.Arrange([Windows.Rect]::new(0,0,450,150));$panel.UpdateLayout()
$box=$row.Template.FindName('Box',$row)
if(-not $box -or $box.CornerRadius.TopLeft -ne 5){throw 'Playlist checkbox is not the rounded app template'}
if($box.Background.ToString() -ne '#FF86C6CB'){throw 'Selected checkbox lost alias color'}
if($row.Foreground.ToString() -ne '#FFF6F3FA' -or $row.MinHeight -lt 36){throw 'Playlist row has unreadable text or tight spacing'}
function Find-Label($node){
    if($node -is [Windows.Controls.TextBlock] -and $node.Text -eq 'Arbiter'){return $node}
    for($i=0;$i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($node);$i++){
        $found=Find-Label ([Windows.Media.VisualTreeHelper]::GetChild($node,$i));if($found){return $found}
    }
}
$label=Find-Label $row
if(-not $label -or $label.Foreground.ToString() -ne '#FFF6F3FA'){throw 'Nested alias label reverted to black'}
$row.IsChecked=$false;$panel.UpdateLayout()
if($box.Background.ToString() -ne '#FF1E1A27'){throw 'Unchecked checkbox lost dark background'}
if($OutputImage){
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(450,150,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($panel)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream=[IO.File]::Create($OutputImage);try{$encoder.Save($stream)}finally{$stream.Dispose()}
}
Write-Output 'PASS: readable nested alias label, rounded themed checkbox, alias accent and selection'
