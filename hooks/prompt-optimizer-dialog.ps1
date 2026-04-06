# Claude Code Prompt Optimizer - Result Dialog (WPF)
# Dark theme, two-panel diff view (original vs optimized) with scrolling

param(
    [int]$InTokens = 0,
    [int]$OutTokens = 0,
    [string]$IsOptimal = '1',
    [string]$OriginalFile = '',
    [string]$OptimizedFile = ''
)

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# Read texts from files
$originalText = ''
if ($OriginalFile -and (Test-Path $OriginalFile)) {
    $originalText = Get-Content $OriginalFile -Raw -Encoding UTF8
    if ($originalText) { $originalText = $originalText.Trim() }
}
$optimizedText = ''
if ($OptimizedFile -and (Test-Path $OptimizedFile)) {
    $optimizedText = Get-Content $OptimizedFile -Raw -Encoding UTF8
    if ($optimizedText) { $optimizedText = $optimizedText.Trim() }
}

$clipboardText = "ignore ai optimisation`r`n" + $optimizedText

# Status
$optimal = $IsOptimal -eq '1'
$reduction = 0
if ($InTokens -gt 0) {
    $reduction = [math]::Round((($InTokens - $OutTokens) / $InTokens) * 100, 1)
}

$accentHex = if ($optimal) { '#50C878' } else { '#FF8C00' }
$dimHex = '#A0A0A0'

$statusText = if ($optimal) {
    "Your prompt is optimal [$InTokens -> $OutTokens tokens, -${reduction}%]"
} else {
    "Your prompt is NOT optimal [$InTokens -> $OutTokens tokens, -${reduction}%]"
}
$iconChar = if ($optimal) { [char]0x2714 } else { [char]0x26A0 }

# --- XAML UI ---
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Prompt Optimizer" WindowState="Maximized"
        Background="#1E1E1E" FontFamily="Segoe UI" FontSize="14">
    <Window.Resources>
        <Style x:Key="DarkBtn" TargetType="Button">
            <Setter Property="Background" Value="#373737"/>
            <Setter Property="Foreground" Value="#E6E6E6"/>
            <Setter Property="BorderBrush" Value="#505050"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="border" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="3" Padding="10,5">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#4B4B4B"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#555555"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="4"/>
            <RowDefinition Height="55"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="50"/>
        </Grid.RowDefinitions>

        <Border Name="AccentBar" Grid.Row="0"/>

        <StackPanel Grid.Row="1" Orientation="Horizontal" VerticalAlignment="Center" Margin="20,0">
            <TextBlock Name="IconLabel" FontSize="20" Margin="0,0,10,0"/>
            <TextBlock Name="StatusLabel" FontSize="16" FontWeight="SemiBold"/>
        </StackPanel>

        <Grid Grid.Row="2" Margin="10,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="6"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <Grid Grid.Column="0">
                <Grid.RowDefinitions>
                    <RowDefinition Height="32"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <TextBlock Name="OrigLabel" Grid.Row="0" FontSize="13" FontWeight="SemiBold"
                           VerticalAlignment="Center" Margin="10,0"/>
                <TextBox Name="OrigText" Grid.Row="1" IsReadOnly="True" TextWrapping="Wrap"
                         VerticalScrollBarVisibility="Visible" HorizontalScrollBarVisibility="Disabled"
                         Background="#2D2D2D" Foreground="#C8C8C8" CaretBrush="#C8C8C8"
                         BorderThickness="0" FontFamily="Cascadia Code, Consolas" FontSize="13"
                         Padding="10" AcceptsReturn="True"/>
            </Grid>

            <GridSplitter Grid.Column="1" Width="6" HorizontalAlignment="Stretch"
                          Background="#464646" ResizeBehavior="PreviousAndNext"/>

            <Grid Grid.Column="2">
                <Grid.RowDefinitions>
                    <RowDefinition Height="32"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <TextBlock Name="OptLabel" Grid.Row="0" FontSize="13" FontWeight="SemiBold"
                           VerticalAlignment="Center" Margin="10,0"/>
                <TextBox Name="OptText" Grid.Row="1" IsReadOnly="True" TextWrapping="Wrap"
                         VerticalScrollBarVisibility="Visible" HorizontalScrollBarVisibility="Disabled"
                         Background="#2D2D2D" Foreground="#C8C8C8" CaretBrush="#C8C8C8"
                         BorderThickness="0" FontFamily="Cascadia Code, Consolas" FontSize="13"
                         Padding="10" AcceptsReturn="True"/>
            </Grid>
        </Grid>

        <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
            <Button Name="BtnCopyOrig" Content="Copy Original" Width="200" Height="36"
                    Margin="0,0,20,0" Style="{StaticResource DarkBtn}"/>
            <Button Name="BtnCopyOpt" Content="Copy Optimized" Width="200" Height="36"
                    Margin="0,0,20,0" Style="{StaticResource DarkBtn}"/>
            <Button Name="BtnClose" Content="Close" Width="120" Height="36"
                    IsCancel="True" Style="{StaticResource DarkBtn}"/>
        </StackPanel>
    </Grid>
</Window>
"@

# Load XAML
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# Get controls
$accentBar = $window.FindName('AccentBar')
$iconLbl = $window.FindName('IconLabel')
$statusLbl = $window.FindName('StatusLabel')
$origLabel = $window.FindName('OrigLabel')
$origTextBox = $window.FindName('OrigText')
$optLabel = $window.FindName('OptLabel')
$optTextBox = $window.FindName('OptText')
$btnCopyOrig = $window.FindName('BtnCopyOrig')
$btnCopyOpt = $window.FindName('BtnCopyOpt')
$btnClose = $window.FindName('BtnClose')

# Set colors
function New-SolidBrush($hex) {
    $color = [System.Windows.Media.ColorConverter]::ConvertFromString($hex)
    return New-Object System.Windows.Media.SolidColorBrush($color)
}

$accentBrush = New-SolidBrush $accentHex
$dimBrush = New-SolidBrush $dimHex

$accentBar.Background = $accentBrush
$iconLbl.Text = [string]$iconChar
$iconLbl.Foreground = $accentBrush
$statusLbl.Text = $statusText
$statusLbl.Foreground = $accentBrush

$origLabel.Text = "Original  [$InTokens tokens]"
$origLabel.Foreground = $dimBrush
$origTextBox.Text = $originalText

$optLabel.Text = "Optimized  [$OutTokens tokens]"
$optLabel.Foreground = $accentBrush
$optTextBox.Text = $optimizedText

# Copy button handlers with "Copied!" feedback
$btnCopyOrig.Add_Click({
    try {
        [System.Windows.Clipboard]::SetText("ignore ai optimisation`r`n" + $origTextBox.Text)
        $btnCopyOrig.Content = 'Copied!'
        $btnCopyOrig.Foreground = (New-SolidBrush '#50C878')
        $script:tOrig = New-Object System.Windows.Threading.DispatcherTimer
        $script:tOrig.Interval = [TimeSpan]::FromMilliseconds(1500)
        $script:tOrig.Add_Tick({
            $btnCopyOrig.Content = 'Copy Original'
            $btnCopyOrig.Foreground = (New-SolidBrush '#E6E6E6')
            $script:tOrig.Stop()
        })
        $script:tOrig.Start()
    } catch {
        # silent: clipboard
    }
})

$btnCopyOpt.Add_Click({
    try {
        [System.Windows.Clipboard]::SetText("ignore ai optimisation`r`n" + $optTextBox.Text)
        $btnCopyOpt.Content = 'Copied!'
        $btnCopyOpt.Foreground = (New-SolidBrush '#50C878')
        $script:tOpt = New-Object System.Windows.Threading.DispatcherTimer
        $script:tOpt.Interval = [TimeSpan]::FromMilliseconds(1500)
        $script:tOpt.Add_Tick({
            $btnCopyOpt.Content = 'Copy Optimized'
            $btnCopyOpt.Foreground = (New-SolidBrush '#E6E6E6')
            $script:tOpt.Stop()
        })
        $script:tOpt.Start()
    } catch {
        # silent: clipboard
    }
})

$btnClose.Add_Click({ $window.Close() })

$window.ShowDialog() | Out-Null
