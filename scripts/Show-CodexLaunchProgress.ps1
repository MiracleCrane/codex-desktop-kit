# Presentation only. Runs in a separate STA Windows PowerShell process.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StatusPath,
    [switch]$RenderOnly
)
$ErrorActionPreference = 'Stop'
$expected = Join-Path (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'AppData\Local\Temp') ([IO.Path]::GetFileName($StatusPath))
if ([IO.Path]::GetFileName($StatusPath) -notmatch '^codex-launch-[a-f0-9]{32}\.status$' -or
    [IO.Path]::GetFullPath($StatusPath) -ine [IO.Path]::GetFullPath($expected)) {
    throw 'Expected a launcher status file in the current user temp directory.'
}
function Read-LaunchState {
    try {
        $inputStream = [IO.File]::Open($StatusPath, 'Open', 'Read', 'ReadWrite')
        $reader = [IO.StreamReader]::new($inputStream)
        try { $reader.ReadToEnd().Trim() } finally { $reader.Dispose() }
    }
    catch { '' }
}

try {
    # A fast successful launch need not flash a window.
    if ((Read-LaunchState) -eq 'dispatched' -and !$RenderOnly) { return }
    Add-Type -AssemblyName PresentationFramework
    $markup = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Codex startup" SizeToContent="WidthAndHeight" ResizeMode="NoResize"
        WindowStartupLocation="CenterScreen" ShowActivated="False" ShowInTaskbar="False"
        Background="#F1F5FB" FontFamily="Segoe UI">
    <Border Padding="24">
        <Border.Background>
            <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                <GradientStop Color="#EDF4FF" Offset="0"/>
                <GradientStop Color="#F8FAFE" Offset="1"/>
            </LinearGradientBrush>
        </Border.Background>
        <Border Width="360" Padding="24" CornerRadius="19" Background="#FFFFFF" BorderBrush="#DFE9F8" BorderThickness="1">
            <Border.Effect><DropShadowEffect BlurRadius="21" ShadowDepth="4" Opacity=".12" Color="#26446F"/></Border.Effect>
            <StackPanel>
                <Border Width="44" Height="44" CornerRadius="13" HorizontalAlignment="Left" Background="#E8F0FF">
                    <TextBlock Text="&gt;_" AutomationProperties.Name="Codex" HorizontalAlignment="Center" VerticalAlignment="Center"
                               FontFamily="Consolas" FontWeight="Bold" FontSize="20" Foreground="#234D9D"/>
                </Border>
                <TextBlock x:Name="Headline" Margin="0,13,0,0" Text="Starting Codex"
                           FontSize="25" FontWeight="SemiBold" Foreground="#162744"/>
                <TextBlock x:Name="Detail" Margin="0,6,0,0" Text="Preparing to open the desktop app."
                           TextWrapping="Wrap" FontSize="14" Foreground="#435775"
                           AutomationProperties.LiveSetting="Polite"/>
                <Border x:Name="Track" Margin="0,20,0,0" Height="4" CornerRadius="2" Background="#E8F0FC">
                    <Grid ClipToBounds="True">
                        <Border x:Name="Sweep" Width="100" HorizontalAlignment="Left" CornerRadius="2" IsHitTestVisible="False">
                            <Border.Background>
                                <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                                    <GradientStop Color="#0084B1FF" Offset="0"/>
                                    <GradientStop Color="#557BE4" Offset=".54"/>
                                    <GradientStop Color="#0084B1FF" Offset="1"/>
                                </LinearGradientBrush>
                            </Border.Background>
                            <Border.RenderTransform><TranslateTransform X="-100"/></Border.RenderTransform>
                        </Border>
                    </Grid>
                </Border>
                <Button x:Name="Dismiss" Content="Close" Visibility="Collapsed"
                        Margin="0,18,0,0" Padding="16,4" HorizontalAlignment="Right" IsCancel="True"/>
            </StackPanel>
        </Border>
    </Border>
</Window>
'@
    $window = [Windows.Markup.XamlReader]::Parse($markup)
    $headline = $window.FindName('Headline')
    $detail = $window.FindName('Detail')
    $track = $window.FindName('Track')
    $sweep = $window.FindName('Sweep')
    $dismiss = $window.FindName('Dismiss')
    if ($RenderOnly) {
        $window.Content.Measure([Windows.Size]::new(1024,768))
        $window.Content.Arrange([Windows.Rect]::new($window.Content.DesiredSize))
        $window.Content.UpdateLayout()
        if ($headline.ActualHeight -le 0 -or $track.ActualWidth -le 0) { throw 'Progress view did not lay out.' }
        [pscustomobject]@{Headline=$headline.Text; Width=$window.Content.ActualWidth; Track=$track.ActualWidth}
        return
    }
    if ((Read-LaunchState) -eq 'dispatched') { return }
    $dismiss.Add_Click({ $window.Close() })
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $timer = [Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(125)
    $timer.Add_Tick({
        $state = Read-LaunchState
        if ($state -eq 'dispatched') { $timer.Stop(); $window.Close(); return }
        if ($state -in @('failed','unconfirmed') -or $clock.Elapsed.TotalSeconds -ge 150) {
            $timer.Stop()
            $headline.Text = if ($state -eq 'failed') { 'Could not start Codex' } else { 'Launch not confirmed' }
            $detail.Text = if ($state -eq 'failed') { 'See the launcher output for details.' } else { 'Check whether Codex opened. The launcher may still be running.' }
            $track.Visibility = 'Collapsed'
            $dismiss.Visibility = 'Visible'
        }
    })
    $window.Add_Closed({ $timer.Stop() })
    if ([Windows.SystemParameters]::ClientAreaAnimation) {
        $slide = [Windows.Media.Animation.DoubleAnimation]::new(-100,315,[Windows.Duration]::new([TimeSpan]::FromSeconds(1.65)))
        $slide.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
        $sweep.RenderTransform.BeginAnimation([Windows.Media.TranslateTransform]::XProperty,$slide)
    } else {
        $sweep.RenderTransform.X = 100
    }
    $timer.Start()
    $null = $window.ShowDialog()
} finally {
    Remove-Item -LiteralPath $StatusPath -ErrorAction SilentlyContinue
}
