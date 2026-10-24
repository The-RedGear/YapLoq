# Presentation only: keep the original string/object selection values intact.
function Initialize-AliasChoices {
    if('YapLoqAliasChoiceConverter' -as [type]){return}
    Add-Type -ReferencedAssemblies PresentationFramework,PresentationCore,WindowsBase,System.Xaml -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Windows;
using System.Windows.Data;
using System.Windows.Media;
public class YapLoqAliasChoice {
    public string Label {get;set;}
    public Geometry IconGeometry {get;set;}
    public Brush IconBrush {get;set;}
    public Brush AccentBrush {get;set;}
    public Brush AccentBackground {get;set;}
}
public class YapLoqAliasChoiceConverter : IValueConverter {
    public static Dictionary<string,YapLoqAliasChoice> Choices = new Dictionary<string,YapLoqAliasChoice>(StringComparer.OrdinalIgnoreCase);
    public static Geometry DefaultIcon;
    public static Geometry PlaylistIcon;
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) {
        string key = value == null ? "" : value.ToString();
        YapLoqAliasChoice choice;
        if(Choices.TryGetValue(key,out choice)) return choice;
        return new YapLoqAliasChoice {
            Label=key.Length == 0 ? "Use rules / default" : key,
            IconGeometry=key.StartsWith("playlist",StringComparison.OrdinalIgnoreCase) ? PlaylistIcon : DefaultIcon,
            IconBrush=new SolidColorBrush((Color)ColorConverter.ConvertFromString("#B6A3FF")),
            AccentBrush=new SolidColorBrush((Color)ColorConverter.ConvertFromString("#B6A3FF")),
            AccentBackground=new SolidColorBrush((Color)ColorConverter.ConvertFromString("#33B6A3FF"))
        };
    }
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) {return Binding.DoNothing;}
}
'@
}

function New-AliasChoiceTemplate([string]$path='.'){
    Initialize-AliasChoices
    $binding=[Windows.Data.Binding]::new($path);$binding.Converter=[YapLoqAliasChoiceConverter]::new()
    $factory=[Windows.FrameworkElementFactory]::new([Windows.Controls.ContentControl])
    $factory.SetBinding([Windows.Controls.ContentControl]::ContentProperty,$binding)
    $factory.SetValue([Windows.UIElement]::FocusableProperty,$false)
    $factory.SetValue([Windows.UIElement]::IsHitTestVisibleProperty,$false)
    $factory.SetValue([Windows.Controls.Control]::ForegroundProperty,[Windows.Media.BrushConverter]::new().ConvertFromString('#F6F3FA'))
    $factory.SetValue([Windows.Controls.ContentControl]::ContentTemplateProperty,[Windows.Markup.XamlReader]::Parse('<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><StackPanel Orientation="Horizontal"><Path Data="{Binding IconGeometry}" Fill="{Binding IconBrush}" Width="18" Height="18" Stretch="Uniform" Margin="0,0,10,0"/><TextBlock Text="{Binding Label}" TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/></StackPanel></DataTemplate>'))
    $template=[Windows.DataTemplate]::new();$template.VisualTree=$factory;return $template
}

function Set-AliasChoicePicker($control,[string]$path='.'){
    if(-not $control){return}
    Initialize-AliasChoices
    if(-not $control.Resources.Contains('AliasChoicePath')){
        $control.Resources['AliasChoicePath']=$path
        $script:aliasChoiceControls+=,[pscustomobject]@{Reference=[WeakReference]::new($control);Path=$path}
    }
    if($control -is [Windows.Controls.ComboBox]){$control.DisplayMemberPath=''}
    $control.ItemTemplate=New-AliasChoiceTemplate $path
    $kind=if($control -is [Windows.Controls.ComboBox]){'ComboBoxItem'}else{'ListBoxItem'}
    $highlight=if($kind -eq 'ComboBoxItem'){'<Trigger Property="IsHighlighted" Value="True"><Setter TargetName="Choice" Property="Background" Value="{Binding Tag.AccentBackground, RelativeSource={RelativeSource TemplatedParent}}"/><Setter TargetName="Choice" Property="BorderBrush" Value="{Binding Tag.AccentBrush, RelativeSource={RelativeSource TemplatedParent}}"/></Trigger>'}else{''}
    $style=[Windows.Markup.XamlReader]::Parse(@"
<Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="$kind">
 <Setter Property="Foreground" Value="#F6F3FA"/><Setter Property="HorizontalContentAlignment" Value="Stretch"/><Setter Property="Padding" Value="10,8"/>
 <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="$kind"><Border Name="Choice" Background="Transparent" BorderBrush="Transparent" BorderThickness="1" CornerRadius="6" Padding="{TemplateBinding Padding}"><ContentPresenter/></Border><ControlTemplate.Triggers>
  <Trigger Property="IsSelected" Value="True"><Setter TargetName="Choice" Property="Background" Value="{Binding Tag.AccentBackground, RelativeSource={RelativeSource TemplatedParent}}"/><Setter TargetName="Choice" Property="BorderBrush" Value="{Binding Tag.AccentBrush, RelativeSource={RelativeSource TemplatedParent}}"/></Trigger>
  <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Choice" Property="Background" Value="{Binding Tag.AccentBackground, RelativeSource={RelativeSource TemplatedParent}}"/><Setter TargetName="Choice" Property="BorderBrush" Value="{Binding Tag.AccentBrush, RelativeSource={RelativeSource TemplatedParent}}"/></Trigger>
  <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Choice" Property="BorderBrush" Value="{Binding Tag.AccentBrush, RelativeSource={RelativeSource TemplatedParent}}"/></Trigger>
  <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
  $highlight
 </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
</Style>
"@)
    $containerBinding=[Windows.Data.Binding]::new($path);$containerBinding.Converter=[YapLoqAliasChoiceConverter]::new()
    $style.Setters.Add([Windows.Setter]::new([Windows.FrameworkElement]::TagProperty,$containerBinding))
    $control.ItemContainerStyle=$style
}

function Update-AliasChoiceAppearance {
    Initialize-AliasChoices
    [YapLoqAliasChoiceConverter]::Choices.Clear()
    [YapLoqAliasChoiceConverter]::DefaultIcon=(Resolve-VoiceIcon 'mdi:music-note').Geometry
    [YapLoqAliasChoiceConverter]::PlaylistIcon=(Resolve-VoiceIcon 'mdi:playlist-music').Geometry
    foreach($row in @($PlayVoiceList.Tag|Where-Object{$_ -and $_.Name})){
        $appearance=[YapLoqAliasChoice]::new();$appearance.Label=$row.Name;$appearance.IconGeometry=$row.IconGeometry;$appearance.IconBrush=$row.IconBrush
        $appearance.AccentBrush=[Windows.Media.BrushConverter]::new().ConvertFromString($row.Accent)
        $appearance.AccentBackground=[Windows.Media.BrushConverter]::new().ConvertFromString($row.AccentBackground)
        [YapLoqAliasChoiceConverter]::Choices[$row.Name]=$appearance
    }
    if(Get-Command Update-AudioStimAppearance -ErrorAction SilentlyContinue){Update-AudioStimAppearance}
    $live=@($script:aliasChoiceControls|Where-Object{$_.Reference.IsAlive});$script:aliasChoiceControls=$live
    foreach($entry in $live){Set-AliasChoicePicker $entry.Reference.Target $entry.Path}
}

function Install-AliasChoicePickers {
    foreach($name in @('PlayVoiceList','PronunciationVoiceList','RouteAliasBox','VoiceRuleAliasBox','ExportVoiceAliasBox')){Set-AliasChoicePicker ($window.FindName($name))}
    Set-AliasChoicePicker $script:dashboardVoicePicker 'Name'
    Set-AliasChoicePicker (Get-ViewerControl 'ViewerVoice') 'Value'
    Set-AliasChoicePicker $script:assignmentDefaultPicker
    Update-AliasChoiceAppearance
}
