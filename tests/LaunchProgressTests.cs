using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Threading;

namespace CodexDesktopKit
{
    internal static class LaunchProgressTests
    {
        [STAThread]
        private static void Main(string[] args)
        {
            int checks = 0;
            using (var progress = new LaunchProgress(() => { Interlocked.Increment(ref checks); return true; }))
            {
                progress.Report(LaunchStage.Magpie);
                progress.WaitForHandoff(false);
            }
            if (checks != 0) throw new Exception("Failure cannot inspect the host.");
            var clock = Stopwatch.StartNew();
            using (var progress = new LaunchProgress(() => { Interlocked.Increment(ref checks); return true; }))
            {
                progress.Report(LaunchStage.Waiting);
                progress.WaitForHandoff(true);
            }
            if (checks != 1 || clock.ElapsedMilliseconds >= 2000) throw new Exception("Ready host did not hand off promptly.");
            using (var card = new StartupCard())
            using (var image = new Bitmap(card.ClientSize.Width, card.ClientSize.Height))
            {
                card.Render(LaunchStage.Magpie, 725);
                card.DrawToBitmap(image, card.ClientRectangle);
                if (image.GetPixel(20, 12).ToArgb() == image.GetPixel(399, 154).ToArgb())
                    throw new Exception("Startup card paint did not render the background.");
                if (args.Length == 1) image.Save(args[0], ImageFormat.Png);
            }
            Console.WriteLine("Startup progress: failed launch, ready handoff, and card rendering passed.");
        }
    }
}
