// Kung Fu Chaos launcher: picks the recomp's options, saves them beside the exe
// (KFCLauncher.ini) and starts kfc_recomp.exe with them as environment variables.
// Build: build-launcher.ps1 (the .NET Framework csc that ships with Windows).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("Kung Fu Chaos Launcher")]
[assembly: AssemblyProduct("Kung Fu Chaos (native recompilation)")]
[assembly: AssemblyVersion("1.0.0.0")]

namespace KFCLauncher
{
    class Choice
    {
        public string Label, Value;
        public Choice(string label, string value) { Label = label; Value = value; }
        public override string ToString() { return Label; }
    }

    class Settings
    {
        public Dictionary<string, string> Values = new Dictionary<string, string>();
        readonly string path;

        public static readonly Dictionary<string, string> Defaults = new Dictionary<string, string> {
            { "scale", "3" }, { "window", "window" }, { "winsize", "1440x1080" }, { "aspect", "4:3" },
            { "movie", "black" }, { "filter", "linear" }, { "overscan", "0" }, { "vsync", "0" },
            { "aniso", "16" }, { "progressive", "1" }, { "deinterlace", "1" }, { "cpu", "all" },
            { "pacing", "sleep" }, { "player", "1" }, { "keyboard", "1" },
            { "lowlat", "1" }, { "rumble", "1" }, { "fps", "60" }, { "pads", "4" },
        };

        public Settings(string path)
        {
            this.path = path;
            foreach (var kv in Defaults) Values[kv.Key] = kv.Value;
            if (!File.Exists(path)) return;
            foreach (var line in File.ReadAllLines(path)) {
                int eq = line.IndexOf('=');
                if (eq <= 0 || line.StartsWith("#")) continue;
                string k = line.Substring(0, eq).Trim(), v = line.Substring(eq + 1).Trim();
                if (Defaults.ContainsKey(k)) Values[k] = v;
            }
        }

        public void Save()
        {
            var lines = new List<string> { "# Kung Fu Chaos launcher settings" };
            foreach (var kv in Values) lines.Add(kv.Key + "=" + kv.Value);
            File.WriteAllLines(path, lines.ToArray());
        }
    }

    class MainForm : Form
    {
        [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
        [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
        [DllImport("user32.dll")] static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hh, bool rep);
        struct RECT { public int L, T, R, B; }

        readonly string dir = AppDomain.CurrentDomain.BaseDirectory;
        readonly Settings settings;
        readonly Dictionary<string, ComboBox> combos = new Dictionary<string, ComboBox>();
        readonly Dictionary<string, CheckBox> checks = new Dictionary<string, CheckBox>();
        readonly ToolTip tips = new ToolTip { AutoPopDelay = 15000 };
        Label winSizeLabel, deintLabel;
        Button play;

        static readonly Color CBg = Color.FromArgb(24, 22, 20), CPanel = Color.FromArgb(36, 33, 30),
            CText = Color.FromArgb(236, 228, 214), CDim = Color.FromArgb(150, 140, 126),
            CAccent = Color.FromArgb(222, 168, 46), CLine = Color.FromArgb(60, 55, 50);

        public MainForm()
        {
            settings = new Settings(Path.Combine(dir, "KFCLauncher.ini"));
            Text = "Kung Fu Chaos";
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = CBg;
            ForeColor = CText;
            Font = new Font("Segoe UI", 9.5f);
            ClientSize = new Size(520, 842);
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

            var banner = new PictureBox { Dock = DockStyle.Top, Height = 130, SizeMode = PictureBoxSizeMode.Zoom, BackColor = Color.Black };
            var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("banner.png");
            if (s != null) banner.Image = Image.FromStream(s);
            else banner.Controls.Add(new Label { Text = "KUNG FU CHAOS", Dock = DockStyle.Fill, ForeColor = CAccent,
                TextAlign = ContentAlignment.MiddleCenter, Font = new Font("Segoe UI", 26f, FontStyle.Bold) });
            Controls.Add(banner);

            var body = new TableLayoutPanel {
                Left = 20, Top = 146, Width = 480, Height = 624, ColumnCount = 2, AutoSize = false,
                BackColor = CBg,
            };
            body.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 190));
            body.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 290));
            Controls.Add(body);

            Section(body, "DISPLAY");
            Combo(body, "scale", "Internal resolution", "Renders the game at a multiple of the Xbox's 640x480. Higher is sharper and asks more of the GPU.",
                new Choice("1x  (640 x 480, original)", "1"), new Choice("2x  (1280 x 960)", "2"),
                new Choice("3x  (1920 x 1440)", "3"), new Choice("4x  (2560 x 1920)", "4"));
            Combo(body, "window", "Window mode", "Fullscreen is borderless, on the desktop's resolution.",
                new Choice("Window", "window"), new Choice("Fullscreen", "fullscreen"));
            winSizeLabel = Combo(body, "winsize", "Window size", "The size of the game's picture area in a window.",
                new Choice("640 x 480", "640x480"), new Choice("960 x 720", "960x720"), new Choice("1280 x 960", "1280x960"),
                new Choice("1440 x 1080", "1440x1080"), new Choice("1920 x 1440", "1920x1440"));
            Combo(body, "aspect", "Aspect ratio", "Widescreen shows more of each side of a match. Experimental: menu backgrounds look stretched at the sides, and the pause screen's sides are black.",
                new Choice("4:3  (original)", "4:3"), new Choice("16:9  (experimental)", "16:9"),
                new Choice("16:10  (experimental)", "16:10"), new Choice("21:9  (experimental)", "21:9"));
            Combo(body, "movie", "Movies on widescreen", "How full-screen videos and stills fill a wide picture.",
                new Choice("Black bars", "black"), new Choice("Stretch", "fit"), new Choice("Zoom", "fill"));
            Combo(body, "filter", "Upscaling filter", "How the picture is scaled to the window.",
                new Choice("Smooth", "linear"), new Choice("Sharp pixels", "nearest"), new Choice("Integer (pixel perfect)", "integer"));
            Combo(body, "overscan", "Overscan crop", "Crops the edges, as an old TV did.",
                new Choice("None", "0"), new Choice("Small", "8"), new Choice("Medium", "16"), new Choice("Large", "32"));
            Check(body, "vsync", "VSync", "Waits for the monitor's refresh: no tearing, a little more input lag.");

            Section(body, "GRAPHICS");
            Combo(body, "aniso", "Anisotropic filtering", "Keeps textures seen at an angle (the ring's floor) sharp.",
                new Choice("Off", "0"), new Choice("2x", "2"), new Choice("4x", "4"), new Choice("8x", "8"), new Choice("16x", "16"));
            Check(body, "progressive", "Progressive matches (480 lines)", "Matches drawn as full 640x480 frames. Off: the console's 480i fields, half the lines, which flicker.");
            deintLabel = Combo(body, "deinterlace", "Deinterlacing", "Only with progressive matches off: how the console's fields are shown.",
                new Choice("Adaptive", "1"), new Choice("Blend", "blend"), new Choice("Off (one field)", "0"));

            Section(body, "PERFORMANCE");
            Combo(body, "fps", "Frame rate", "The game times itself, so it runs at normal speed at any rate; higher is smoother. "
                + "Experimental above 60. Pick your monitor's refresh rate, or lower if the PC cannot hold it.",
                new Choice("60  (original)", "60"), new Choice("120  (experimental)", "120"),
                new Choice("144  (experimental)", "144"), new Choice("165  (experimental)", "165"),
                new Choice("240  (experimental)", "240"), new Choice("Custom...", "custom"));
            // With VRR (FreeSync / G-Sync) a rate a few frames under the monitor's keeps VSync off from tearing.
            int hz = MonitorHz();
            if (hz > 60 && hz - 3 <= 480)
                combos["fps"].Items.Insert(combos["fps"].Items.Count - 1,
                    new Choice(string.Format("{0}  (VRR, your monitor is {1} Hz)", hz - 3, hz), (hz - 3).ToString()));
            Combo(body, "cpu", "CPU threads", "All cores loads and moves more smoothly. Single core runs the game's threads as the console did.",
                new Choice("All cores", "all"), new Choice("Single core (console)", "one"));
            Combo(body, "pacing", "Frame pacing", "Low CPU sleeps between frames. Exact timing busy-waits, as the console did.",
                new Choice("Low CPU", "sleep"), new Choice("Exact timing", "spin"));
            Check(body, "lowlat", "Low latency", "At most one frame queued, and with VSync off the picture goes out as soon as it is ready (may tear in fullscreen).");

            Section(body, "INPUT");
            Combo(body, "pads", "Controllers", "How many controllers the game sees plugged in (up to 4 XInput pads, in Windows' order).",
                new Choice("1", "1"), new Choice("2", "2"), new Choice("3", "3"), new Choice("4", "4"));
            Combo(body, "player", "First controller is player", "The first controller plays as this player; the others follow.",
                new Choice("Player 1", "1"), new Choice("Player 2", "2"), new Choice("Player 3", "3"), new Choice("Player 4", "4"));
            Check(body, "keyboard", "Keyboard", "Play with the keyboard as well.");
            Check(body, "rumble", "Vibration", "The game's rumble on the controller.");

            var reset = MakeButton("Restore defaults", false);
            reset.SetBounds(20, ClientSize.Height - 56, 170, 38);
            reset.Click += delegate { foreach (var kv in Settings.Defaults) settings.Values[kv.Key] = kv.Value; LoadValues(); };
            Controls.Add(reset);
            play = MakeButton("PLAY", true);
            play.SetBounds(ClientSize.Width - 200, ClientSize.Height - 56, 180, 38);
            play.Click += delegate { Play(); };
            Controls.Add(play);
            AcceptButton = play;
            Shown += delegate { ActiveControl = play; };

            combos["window"].SelectedIndexChanged += delegate { UpdateEnabled(); };
            checks["progressive"].CheckedChanged += delegate { UpdateEnabled(); };
            combos["fps"].SelectedIndexChanged += delegate { FpsChanged(); };
            LoadValues();
        }

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct DEVMODE {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
            public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
            public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
            public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
            public short dmLogPixels;
            public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
        }

        // The primary monitor's refresh rate, 0 if Windows does not say.
        static int MonitorHz()
        {
            var dm = new DEVMODE { dmSize = (short)Marshal.SizeOf(typeof(DEVMODE)) };
            try { return EnumDisplaySettings(null, -1, ref dm) && dm.dmDisplayFrequency > 1 ? dm.dmDisplayFrequency : 0; }
            catch { return 0; }
        }

        int fpsIndex;

        // "Custom..." asks for a rate; it then shows in the list as its own entry.
        void FpsChanged()
        {
            var c = combos["fps"];
            if (((Choice)c.SelectedItem).Value != "custom") { fpsIndex = c.SelectedIndex; return; }
            int n = AskFps();
            if (n > 0) SetCustomFps(n); else c.SelectedIndex = fpsIndex;
        }

        void SetCustomFps(int n)
        {
            var c = combos["fps"];
            string v = n.ToString();
            for (int i = 0; i < c.Items.Count; i++)
                if (((Choice)c.Items[i]).Value == v) { c.SelectedIndex = i; return; }
            for (int i = 0; i < c.Items.Count; i++)
                if (((Choice)c.Items[i]).Label.EndsWith("(custom)")) { c.Items.RemoveAt(i); break; }
            c.Items.Insert(c.Items.Count - 1, new Choice(v + "  (custom)", v));
            c.SelectedIndex = c.Items.Count - 2;
        }

        int AskFps()
        {
            using (var f = new Form { Text = "Frame rate", FormBorderStyle = FormBorderStyle.FixedDialog, MaximizeBox = false,
                       MinimizeBox = false, StartPosition = FormStartPosition.CenterParent, BackColor = CBg, ForeColor = CText,
                       Font = Font, ClientSize = new Size(300, 120), ShowInTaskbar = false }) {
                var l = new Label { Text = "Frames per second (30 to 480):", AutoSize = true, Left = 16, Top = 16 };
                var n = new NumericUpDown { Minimum = 30, Maximum = 480, Left = 16, Top = 40, Width = 100,
                    BackColor = CPanel, ForeColor = CText };
                int cur;
                n.Value = int.TryParse(((Choice)combos["fps"].Items[fpsIndex]).Value, out cur) ? Math.Max(30, Math.Min(480, cur)) : 60;
                var ok = MakeButton("OK", true); ok.SetBounds(120, 76, 80, 30); ok.DialogResult = DialogResult.OK;
                var cancel = MakeButton("Cancel", false); cancel.SetBounds(206, 76, 80, 30); cancel.DialogResult = DialogResult.Cancel;
                f.Controls.AddRange(new Control[] { l, n, ok, cancel });
                f.AcceptButton = ok; f.CancelButton = cancel;
                return f.ShowDialog(this) == DialogResult.OK ? (int)n.Value : 0;
            }
        }

        Button MakeButton(string text, bool primary)
        {
            var b = new Button { Text = text, FlatStyle = FlatStyle.Flat, Cursor = Cursors.Hand,
                Font = new Font("Segoe UI", primary ? 11f : 9.5f, primary ? FontStyle.Bold : FontStyle.Regular),
                BackColor = primary ? CAccent : CPanel, ForeColor = primary ? Color.FromArgb(30, 22, 8) : CText };
            b.FlatAppearance.BorderColor = primary ? CAccent : CLine;
            return b;
        }

        void Section(TableLayoutPanel t, string title)
        {
            var l = new Label { Text = title, ForeColor = CAccent, AutoSize = true, Font = new Font("Segoe UI", 8.5f, FontStyle.Bold),
                Margin = new Padding(0, t.Controls.Count == 0 ? 0 : 10, 0, 2) };
            t.Controls.Add(l);
            t.SetColumnSpan(l, 2);
        }

        Label Combo(TableLayoutPanel t, string key, string label, string tip, params Choice[] choices)
        {
            var l = new Label { Text = label, AutoSize = true, ForeColor = CText, Margin = new Padding(0, 6, 0, 0) };
            var c = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 280, FlatStyle = FlatStyle.Flat,
                BackColor = CPanel, ForeColor = CText, Margin = new Padding(0, 2, 0, 2) };
            c.Items.AddRange(choices);
            tips.SetToolTip(l, tip); tips.SetToolTip(c, tip);
            t.Controls.Add(l); t.Controls.Add(c);
            combos[key] = c;
            return l;
        }

        void Check(TableLayoutPanel t, string key, string label, string tip)
        {
            var c = new CheckBox { Text = label, AutoSize = true, ForeColor = CText, Margin = new Padding(0, 6, 0, 2) };
            tips.SetToolTip(c, tip);
            t.Controls.Add(c);
            t.SetColumnSpan(c, 2);
            checks[key] = c;
        }

        void LoadValues()
        {
            foreach (var kv in combos) {
                kv.Value.SelectedIndex = 0;
                for (int i = 0; i < kv.Value.Items.Count; i++)
                    if (((Choice)kv.Value.Items[i]).Value == settings.Values[kv.Key]) kv.Value.SelectedIndex = i;
            }
            int saved;
            if (((Choice)combos["fps"].SelectedItem).Value != settings.Values["fps"]
                    && int.TryParse(settings.Values["fps"], out saved) && saved >= 30 && saved <= 480)
                SetCustomFps(saved);
            foreach (var kv in checks) kv.Value.Checked = settings.Values[kv.Key] == "1";
            UpdateEnabled();
        }

        void UpdateEnabled()
        {
            bool win = ((Choice)combos["window"].SelectedItem).Value == "window";
            combos["winsize"].Enabled = win; winSizeLabel.ForeColor = win ? CText : CDim;
            bool fields = !checks["progressive"].Checked;
            combos["deinterlace"].Enabled = fields; deintLabel.ForeColor = fields ? CText : CDim;
        }

        void Store()
        {
            foreach (var kv in combos) settings.Values[kv.Key] = ((Choice)kv.Value.SelectedItem).Value;
            foreach (var kv in checks) settings.Values[kv.Key] = kv.Value.Checked ? "1" : "0";
        }

        public void Play()
        {
            Store();
            try { settings.Save(); } catch { }
            string exe = Path.Combine(dir, "kfc_recomp.exe");
            if (!File.Exists(exe)) {
                MessageBox.Show(this, "kfc_recomp.exe was not found next to the launcher.", "Kung Fu Chaos",
                                MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
            var v = settings.Values;
            // Through a hidden cmd, so the game's log goes to log.txt beside it.
            var psi = new ProcessStartInfo("cmd.exe", "/c \"\"" + exe + "\" 2> \"" + Path.Combine(dir, "log.txt") + "\"\"")
                { WorkingDirectory = dir, UseShellExecute = false, CreateNoWindow = true };
            var env = psi.EnvironmentVariables;
            string game = Path.Combine(dir, "game", "Kung Fu Chaos");
            if (Directory.Exists(game)) env["RECOMP_GAME_FILES"] = game;
            string hdd = Path.Combine(dir, "hdd");
            if (Directory.Exists(hdd)) env["RECOMP_HDD_DIR"] = hdd;
            env["RECOMP_PB_BACKEND"] = "d3d11";
            env["RECOMP_PB_EXEC"] = "1";
            env["RECOMP_AC97_READY"] = "1";
            env["RECOMP_VBLANK"] = "1";
            env["RECOMP_FB_WINDOW"] = "1";
            env["RECOMP_USB"] = "1";
            env["RECOMP_USB_NDP"] = "4";
            env["RECOMP_USB_PADS"] = v["pads"];
            // XAPI hands the root hub's ports 3, 4, 1, 2 to players 1-4.
            env["RECOMP_USB_PORT"] = new[] { "2", "3", "0", "1" }[int.Parse(v["player"]) - 1];
            env["RECOMP_KEYBOARD"] = v["keyboard"];
            env["RECOMP_RENDER_SCALE"] = v["scale"];
            env["RECOMP_RENDER_ANISO"] = v["aniso"];
            env["RECOMP_DISPLAY_ASPECT"] = v["aspect"];
            env["RECOMP_DISPLAY_MOVIE"] = v["movie"];
            env["RECOMP_DISPLAY_OVERSCAN"] = v["overscan"];
            env["RECOMP_PRESENT_FILTER"] = v["filter"];
            env["RECOMP_PRESENT_FULLSCREEN"] = v["window"] == "fullscreen" ? "1" : "0";
            env["RECOMP_PRESENT_PACING"] = v["pacing"];
            env["RECOMP_PRESENT_VSYNC"] = v["vsync"];
            env["RECOMP_KFC_PROGRESSIVE"] = v["progressive"];
            env["RECOMP_FIELD_DEINTERLACE"] = v["deinterlace"];
            env["RECOMP_D3D11_LOW_LATENCY"] = v["lowlat"];
            env["RECOMP_RUMBLE"] = v["rumble"];
            env["RECOMP_VBLANK_HZ"] = v["fps"];
            // KFC_TRACE (diagnostics, e.g. grabar-audio.bat): more trace channels for the log.
            string extra = Environment.GetEnvironmentVariable("KFC_TRACE");
            env["RECOMP_TRACE"] = "title" + (string.IsNullOrEmpty(extra) ? "" : "," + extra);
            env["RECOMP_DEBUG"] = "rt_alias_check=0,guest_cpus=" + v["cpu"];
            try { Process.Start(psi); }
            catch (Exception e) {
                MessageBox.Show(this, "Could not start the game:\n" + e.Message, "Kung Fu Chaos",
                                MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
            if (v["window"] == "window") SizeWindow(v["winsize"]);
            Close();
        }

        // The game opens a 640x480 window; size its picture area as chosen,
        // centred on the screen it opened on.
        void SizeWindow(string size)
        {
            string[] wh = size.Split('x');
            int w = int.Parse(wh[0]), h = int.Parse(wh[1]);
            for (int i = 0; i < 100; i++) {
                Thread.Sleep(100);
                Process p = null;
                foreach (var q in Process.GetProcessesByName("kfc_recomp"))
                    if (q.MainWindowHandle != IntPtr.Zero) p = q;
                if (p == null) continue;
                RECT c, r;
                GetClientRect(p.MainWindowHandle, out c);
                GetWindowRect(p.MainWindowHandle, out r);
                int dx = (r.R - r.L) - c.R, dy = (r.B - r.T) - c.B;
                var screen = Screen.FromHandle(p.MainWindowHandle).WorkingArea;
                int x = screen.Left + Math.Max(0, (screen.Width - w - dx) / 2);
                int y = screen.Top + Math.Max(0, (screen.Height - h - dy) / 2);
                MoveWindow(p.MainWindowHandle, x, y, w + dx, h + dy, true);
                return;
            }
        }

        // --play: start the game with the saved settings, no window (a shortcut's target).
        [STAThread]
        static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            var f = new MainForm();
            if (Array.IndexOf(args, "--play") >= 0) {
                f.Play();
                return;
            }
            Application.Run(f);
        }
    }
}
