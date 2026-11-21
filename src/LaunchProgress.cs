using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Threading;
using System.Windows.Forms;

namespace CodexDesktopKit
{
    internal enum LaunchStage { Proxy, Magpie, Bridge, Opening, Waiting, Done }

    // Presentation only: no progress state feeds back into any launch operation.
    internal sealed class LaunchProgress : IDisposable
    {
        internal const int ShowDelay = 420;
        internal const int HandoffLimit = 12000;
        private readonly Stopwatch clock = Stopwatch.StartNew();
        private readonly Thread ui;
        private readonly Func<bool> windowVisible;
        private volatile LaunchStage stage;
        private long waitingSince;

        public LaunchProgress(Func<bool> windowVisible)
        {
            this.windowVisible = windowVisible;
            ui = new Thread(Run) { IsBackground = true, Name = "Codex startup progress" };
            ui.SetApartmentState(ApartmentState.STA);
            ui.Start();
        }

        public void Report(LaunchStage next)
        {
            if (next == LaunchStage.Waiting) Interlocked.Exchange(ref waitingSince, clock.ElapsedMilliseconds);
            stage = next;
        }

        private void Run()
        {
            try {
                using (var card = new StartupCard())
                using (var timer = new System.Windows.Forms.Timer { Interval = 35 })
                {
                    using (var loop = new ApplicationContext())
                    {
                        bool shown = false;
                        long nextProbe = 0;
                        timer.Tick += delegate {
                            try {
                                LaunchStage current = stage;
                                long now = clock.ElapsedMilliseconds;
                                if (current == LaunchStage.Done) { loop.ExitThread(); return; }
                                if (current == LaunchStage.Waiting) {
                                    if (now - Interlocked.Read(ref waitingSince) >= HandoffLimit) { loop.ExitThread(); return; }
                                    if (now >= nextProbe) {
                                        nextProbe = now + 160;
                                        if (windowVisible()) { loop.ExitThread(); return; }
                                    }
                                }
                                if (!shown && now >= ShowDelay) { shown = true; card.Show(); }
                                if (shown) card.Render(current, now);
                            } catch { loop.ExitThread(); }
                        };
                        timer.Start();
                        Application.Run(loop);
                    }
                }
            } catch { /* An unavailable progress window must not affect Codex. */ }
        }

        public void WaitForHandoff(bool activated)
        {
            if (activated && stage == LaunchStage.Waiting)
                ui.Join(HandoffLimit + 500);
        }

        public void Dispose()
        {
            Report(LaunchStage.Done);
            ui.Join(250);
        }
    }

    internal sealed class StartupCard : Form
    {
        private LaunchStage stage;
        private long time;

        public StartupCard()
        {
            Text = "正在启动 Codex";
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Color.FromArgb(16, 20, 31);
            ClientSize = new Size(420, 176);
            DoubleBuffered = true;
        }

        protected override bool ShowWithoutActivation { get { return true; } }
        protected override CreateParams CreateParams {
            get {
                var parameters = base.CreateParams;
                parameters.ExStyle |= 0x08000080; // no activation, tool window
                parameters.ClassStyle |= 0x00020000; // Windows drop shadow
                return parameters;
            }
        }

        internal void Render(LaunchStage value, long milliseconds)
        {
            stage = value;
            time = milliseconds;
            Invalidate();
        }

        private static GraphicsPath Round(RectangleF bounds, float corner)
        {
            float d = corner * 2;
            var shape = new GraphicsPath();
            shape.AddArc(bounds.Left, bounds.Top, d, d, 180, 90);
            shape.AddArc(bounds.Right - d, bounds.Top, d, d, 270, 90);
            shape.AddArc(bounds.Right - d, bounds.Bottom - d, d, d, 0, 90);
            shape.AddArc(bounds.Left, bounds.Bottom - d, d, d, 90, 90);
            shape.CloseFigure();
            return shape;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
            g.ScaleTransform(ClientSize.Width / 420f, ClientSize.Height / 176f);
            using (var background = new LinearGradientBrush(new Rectangle(0, 0, 420, 176),
                Color.FromArgb(31, 39, 65), Color.FromArgb(14, 19, 31), 48f))
            using (var border = new Pen(Color.FromArgb(78, 94, 131)))
            using (var label = new SolidBrush(Color.FromArgb(175, 188, 214)))
            using (var white = new SolidBrush(Color.FromArgb(248, 250, 255)))
            using (var title = new Font("Microsoft YaHei UI", 21, FontStyle.Bold, GraphicsUnit.Pixel))
            using (var body = new Font("Microsoft YaHei UI", 12, FontStyle.Regular, GraphicsUnit.Pixel))
            using (var mark = new Font("Segoe UI", 18, FontStyle.Bold, GraphicsUnit.Pixel))
            using (var pill = Round(new RectangleF(25, 28, 44, 44), 13))
            using (var icon = new LinearGradientBrush(new Rectangle(25, 28, 44, 44),
                Color.FromArgb(65, 115, 218), Color.FromArgb(89, 62, 179), 45f))
            using (var track = Round(new RectangleF(26, 137, 368, 6), 3))
            using (var trackFill = new SolidBrush(Color.FromArgb(48, 57, 78)))
            {
                g.FillRectangle(background, 0, 0, 420, 176);
                g.DrawRectangle(border, 0, 0, 419, 175);
                g.FillPath(icon, pill);
                g.DrawString(">_", mark, white, 34, 38);
                g.DrawString("CODEX  /  DESKTOP KIT", body, label, 83, 27);
                g.DrawString("正在启动 Codex", title, white, 82, 46);
                string detail = stage == LaunchStage.Magpie ? "正在连接本机 Magpie 网关"
                    : stage == LaunchStage.Bridge ? "正在连接已启用的本地桥接"
                    : stage == LaunchStage.Opening ? "正在请求打开 Codex"
                    : stage == LaunchStage.Waiting ? "已请求打开，正在等待 Codex 窗口"
                    : "正在连接本地代理";
                g.DrawString(detail, body, label, 25, 106);

                g.FillPath(trackFill, track);
                var clip = g.Save();
                g.SetClip(track);
                float x = (time % 1450) / 1450f * 480f - 90f;
                using (var glow = new LinearGradientBrush(new RectangleF(x, 137, 116, 6),
                    Color.FromArgb(55, 79, 142), Color.FromArgb(55, 79, 142), 0f))
                {
                    glow.InterpolationColors = new ColorBlend {
                        Colors = new[] { Color.FromArgb(48, 57, 78), Color.FromArgb(107, 168, 255),
                            Color.FromArgb(175, 134, 255), Color.FromArgb(48, 57, 78) },
                        Positions = new[] { 0f, .42f, .64f, 1f }
                    };
                    g.FillRectangle(glow, x, 137, 116, 6);
                }
                g.Restore(clip);
            }
        }
    }
}
