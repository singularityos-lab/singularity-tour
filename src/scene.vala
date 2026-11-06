namespace Singularity.Apps.Tour {

    public class RealDesktop : Object {
        public Cairo.ImageSurface? panel;
        public Cairo.ImageSurface? dock;
        public Cairo.ImageSurface? wallpaper;
        public double screen_width;
        public double panel_scale = 1;
        private static RealDesktop? instance;

        public signal void loaded ();

        private bool started;

        public static RealDesktop get_default () {
            if (instance == null) instance = new RealDesktop ();
            return instance;
        }

        public void start () {
            if (started) return;
            started = true;
            load.begin ();
        }

        private static Cairo.ImageSurface? to_surface (Gdk.Texture tex) {
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, tex.width, tex.height);
            surf.flush ();
            unowned uchar[] data = surf.get_data ();
            data.length = surf.get_stride () * tex.height;
            tex.download (data, surf.get_stride ());
            surf.mark_dirty ();
            return surf;
        }

        private static Cairo.ImageSurface crop (Cairo.ImageSurface src) {
            int w = src.get_width (), h = src.get_height (), stride = src.get_stride ();
            unowned uchar[] d = src.get_data ();
            d.length = stride * h;
            int x1 = w, y1 = h, x2 = -1, y2 = -1;
            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    uint8 a = d[y * stride + x * 4 + 3];
                    if (a > 24) {
                        if (x < x1) x1 = x;
                        if (x > x2) x2 = x;
                        if (y < y1) y1 = y;
                        if (y > y2) y2 = y;
                    }
                }
            }
            if (x2 < x1 || y2 < y1) return src;
            var out_s = new Cairo.ImageSurface (Cairo.Format.ARGB32, x2 - x1 + 1, y2 - y1 + 1);
            var cr = new Cairo.Context (out_s);
            cr.set_source_surface (src, -x1, -y1);
            cr.paint ();
            return out_s;
        }

        private async void load () {
            try {
                Singularity.Shell.ShellService shell = yield Bus.get_proxy (BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                string p = shell.snapshot_component ("panel");
                if (p != "") {
                    var tex = Gdk.Texture.from_filename (p);
                    panel = to_surface (tex);
                    int scale = 1;
                    var display = Gdk.Display.get_default ();
                    var monitors = display.get_monitors ();
                    if (monitors.get_n_items () > 0) {
                        var mon = (Gdk.Monitor) monitors.get_item (0);
                        scale = mon.scale_factor;
                        screen_width = mon.geometry.width;
                    }
                    panel_scale = scale;
                    if (screen_width <= 0) screen_width = panel.get_width () / (double) scale;
                    FileUtils.remove (p);
                }
                string d = shell.snapshot_component ("dock");
                if (d != "") {
                    dock = crop (to_surface (Gdk.Texture.from_filename (d)));
                    FileUtils.remove (d);
                }
            } catch (Error e) {
                panel = null;
                dock = null;
            }
            try {
                Singularity.Shell.ShellService shell = yield Bus.get_proxy (BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                string b = shell.snapshot_component ("background");
                if (b != "") {
                    var tex = Gdk.Texture.from_filename (b);
                    FileUtils.remove (b);
                    double cover = double.max (1280.0 / tex.width, 800.0 / tex.height);
                    var big = to_surface (tex);
                    var small = new Cairo.ImageSurface (Cairo.Format.ARGB32, 1280, 800);
                    var cr = new Cairo.Context (small);
                    cr.translate ((1280 - tex.width * cover) / 2, (800 - tex.height * cover) / 2);
                    cr.scale (cover, cover);
                    cr.set_source_surface (big, 0, 0);
                    cr.get_source ().set_filter (Cairo.Filter.GOOD);
                    cr.paint ();
                    wallpaper = small;
                }
            } catch (Error e) {
                wallpaper = null;
            }
            loaded ();
        }
    }

    public class Scene : Gtk.Widget {
        private const double W = 640;
        private const double H = 400;

        private string kind;
        private Gdk.Texture? texture = null;
        private Gdk.Paintable? icon = null;
        private double phase = 0;
        private double bar_h = 20;
        private double dock_x = 195;
        private double dock_y = 354;
        private double dock_w = 250;
        private double dock_h = 34;
        private uint tick = 0;

        public Scene (Slide slide) {
            kind = slide.scene;
            add_css_class ("tour-scene");
            if (slide.image != "") {
                try {
                    texture = Gdk.Texture.from_filename (slide.image);
                } catch (Error e) {
                }
            }
            string icon_name = slide.icon != "" ? slide.icon : (kind == "welcome" ? "emblem-singularity" : "");
            if (icon_name != "") {
                var theme = Gtk.IconTheme.get_for_display (Gdk.Display.get_default ());
                icon = theme.lookup_icon (icon_name, null, 256, 1, Gtk.TextDirection.NONE, 0);
            }
            RealDesktop.get_default ().loaded.connect (() => queue_draw ());
            map.connect (() => {
                var gtk = Gtk.Settings.get_default ();
                if (gtk != null && !gtk.gtk_enable_animations) return;
                tick = add_tick_callback ((w, clock) => {
                    phase = (clock.get_frame_time () / 1000000.0) % 2.4 / 2.4;
                    queue_draw ();
                    return Source.CONTINUE;
                });
            });
            unmap.connect (() => {
                if (tick != 0) remove_tick_callback (tick);
                tick = 0;
            });
        }

        public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
            minimum_baseline = natural_baseline = -1;
            minimum = orientation == Gtk.Orientation.HORIZONTAL ? 240 : 150;
            natural = orientation == Gtk.Orientation.HORIZONTAL ? (int) W : (int) H;
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            double width = get_width ();
            double height = get_height ();
            double scale = double.min (width / W, height / H);
            double dx = (width - W * scale) / 2;
            double dy = (height - H * scale) / 2;
            var bounds = Graphene.Rect ().init ((float) dx, (float) dy, (float) (W * scale), (float) (H * scale));
            var rounded = Gsk.RoundedRect ().init_from_rect (bounds, (float) (18 * scale));
            var shadow_color = Gdk.RGBA () { red = 0, green = 0, blue = 0, alpha = 0.28f };
            snapshot.append_outset_shadow (rounded, shadow_color, 0, (float) (12 * scale), 0, (float) (30 * scale));
            snapshot.push_rounded_clip (rounded);
            if (texture != null) {
                snapshot.append_texture (texture, bounds);
            } else if (kind != "") {
                var cr = snapshot.append_cairo (bounds);
                cr.translate (dx, dy);
                cr.scale (scale, scale);
                paint (cr);
            } else {
                var cr = snapshot.append_cairo (bounds);
                cr.translate (dx, dy);
                cr.scale (scale, scale);
                glow_background (cr);
            }
            if (icon != null && texture == null && (kind == "welcome" || kind == "")) {
                double size = 132 * scale;
                snapshot.save ();
                snapshot.translate (Graphene.Point () { x = (float) (dx + (W * scale - size) / 2), y = (float) (dy + (H * scale - size) / 2) });
                icon.snapshot (snapshot, size, size);
                snapshot.restore ();
            }
            snapshot.pop ();
        }

        private Gdk.RGBA accent () {
            return get_color ();
        }

        private void paint (Cairo.Context cr) {
            switch (kind) {
                case "welcome":
                    glow_background (cr);
                    orbit (cr);
                    break;
                case "top-bar":
                    desktop (cr, "Files");
                    if (RealDesktop.get_default ().panel != null) {
                        window (cr, 170, bar_h + 150, 300, 150, "files");
                        highlight (cr, 2, 1, W - 4, bar_h - 2, bar_h / 2);
                        real_bar_lenses (cr);
                    } else {
                        window (cr, 70, 50, 380, 250, "files");
                        highlight (cr, 6, 3, 628, 14, 7);
                        calendar_card (cr);
                    }
                    break;
                case "launcher":
                    desktop (cr, "");
                    launcher (cr);
                    highlight (cr, 190, 36, 260, 26, 13);
                    break;
                case "dock":
                    desktop (cr, "Files");
                    window (cr, 90, bar_h + 26, 400, 200, "files");
                    highlight (cr, dock_x - 4, dock_y - 4, dock_w + 8, dock_h + 8, 14);
                    real_dock_lens (cr);
                    break;
                case "windows":
                    desktop (cr, "Files");
                    window (cr, 4, 24, 314, 326, "files");
                    window (cr, 322, 24, 314, 326, "write");
                    snap_hint (cr);
                    break;
                case "workspaces":
                    overview (cr);
                    break;
                case "store":
                    desktop (cr, "Store");
                    window (cr, 70, 38, 500, 300, "store");
                    break;
                case "settings":
                    desktop (cr, "");
                    window (cr, 40, 52, 330, 230, "write");
                    settings_panel (cr);
                    highlight (cr, 392, 26, 240, 318, 16);
                    break;
                case "help":
                    desktop (cr, "Help");
                    window (cr, 70, 38, 500, 300, "help");
                    break;
                case "done":
                    glow_background (cr);
                    done (cr);
                    break;
                case "assistant":
                    desktop (cr, "Notes");
                    window (cr, 40, 70, 300, 250, "write");
                    assistant (cr);
                    highlight (cr, 352, 30, 268, 222, 14);
                    break;
                default:
                    glow_background (cr);
                    break;
            }
        }

        private static void rrect (Cairo.Context cr, double x, double y, double w, double h, double r) {
            r = double.min (r, double.min (w, h) / 2);
            cr.new_sub_path ();
            cr.arc (x + w - r, y + r, r, -Math.PI / 2, 0);
            cr.arc (x + w - r, y + h - r, r, 0, Math.PI / 2);
            cr.arc (x + r, y + h - r, r, Math.PI / 2, Math.PI);
            cr.arc (x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
            cr.close_path ();
        }

        private static void rgb (Cairo.Context cr, uint hex, double alpha = 1) {
            cr.set_source_rgba (((hex >> 16) & 0xff) / 255.0, ((hex >> 8) & 0xff) / 255.0, (hex & 0xff) / 255.0, alpha);
        }

        private void set_accent (Cairo.Context cr, double alpha = 1) {
            var a = accent ();
            cr.set_source_rgba (a.red, a.green, a.blue, a.alpha * alpha);
        }

        private static void pill (Cairo.Context cr, double x, double y, double w, double h, uint hex, double alpha) {
            rrect (cr, x, y, w, h, h / 2);
            rgb (cr, hex, alpha);
            cr.fill ();
        }

        private static void text (Cairo.Context cr, string s, double x, double y, double size, uint hex, double alpha, bool bold = false, bool center = false, bool right = false) {
            var layout = Pango.cairo_create_layout (cr);
            var font = Pango.FontDescription.from_string ("Sans");
            font.set_absolute_size (size * Pango.SCALE);
            if (bold) font.set_weight (Pango.Weight.BOLD);
            layout.set_font_description (font);
            layout.set_text (s, -1);
            int lw, lh;
            layout.get_pixel_size (out lw, out lh);
            cr.move_to (right ? x - lw : (center ? x - lw / 2.0 : x), y - lh / 2.0);
            rgb (cr, hex, alpha);
            Pango.cairo_show_layout (cr, layout);
        }

        private void glow_background (Cairo.Context cr) {
            rgb (cr, 0x0e0f12);
            cr.paint ();
            var a = accent ();
            var g = new Cairo.Pattern.radial (W / 2, H / 2, 10, W / 2, H / 2, 300);
            g.add_color_stop_rgba (0, a.red, a.green, a.blue, 0.55);
            g.add_color_stop_rgba (0.45, a.red, a.green, a.blue, 0.16);
            g.add_color_stop_rgba (1, a.red, a.green, a.blue, 0);
            cr.set_source (g);
            cr.paint ();
        }

        private void orbit (Cairo.Context cr) {
            cr.save ();
            cr.translate (W / 2, H / 2);
            for (int i = 0; i < 3; i++) {
                cr.save ();
                cr.rotate (-0.35 + i * 0.35);
                cr.scale (1, 0.34);
                cr.arc (0, 0, 150 + i * 26, 0, 2 * Math.PI);
                cr.restore ();
                set_accent (cr, 0.5 - i * 0.14);
                cr.set_line_width (1.6);
                cr.stroke ();
            }
            double t = phase * 2 * Math.PI;
            cr.save ();
            cr.rotate (-0.35);
            double px = 150 * Math.cos (t);
            double py = 150 * 0.34 * Math.sin (t);
            cr.arc (px, py, 4.5, 0, 2 * Math.PI);
            rgb (cr, 0xffffff, 0.95);
            cr.fill ();
            cr.restore ();
            cr.restore ();
        }

        private void desktop (Cairo.Context cr, string app) {
            var real = RealDesktop.get_default ();
            if (real.wallpaper != null) {
                cr.save ();
                cr.scale (W / 1280.0, H / 800.0);
                cr.set_source_surface (real.wallpaper, 0, 0);
                cr.paint ();
                cr.restore ();
            } else {
                desktop_background (cr);
            }
            if (real.panel != null) {
                double s = W / real.panel.get_width ();
                bar_h = real.panel.get_height () * s;
                cr.save ();
                cr.scale (s, s);
                cr.set_source_surface (real.panel, 0, 0);
                cr.get_source ().set_filter (Cairo.Filter.GOOD);
                cr.paint ();
                cr.restore ();
            } else {
                bar_h = 20;
                mock_bar (cr, app);
            }
            dock (cr);
        }

        private void desktop_background (Cairo.Context cr) {
            rgb (cr, 0x0c0d10);
            cr.paint ();
            cr.move_to (0, 300);
            cr.curve_to (180, 250, 300, 130, 640, 180);
            cr.line_to (640, 400);
            cr.line_to (0, 400);
            cr.close_path ();
            rgb (cr, 0x1a1b1f);
            cr.fill ();
            cr.arc (W / 2, 196, 30, 0, 2 * Math.PI);
            rgb (cr, 0xffffff, 0.16);
            cr.set_line_width (9);
            cr.stroke ();
        }

        private void mock_bar (Cairo.Context cr, string app) {
            rgb (cr, 0x000000);
            cr.rectangle (0, 0, W, 20);
            cr.fill ();
            cr.arc (14, 10, 5.5, 0, 2 * Math.PI);
            rgb (cr, 0xffffff, 0.92);
            cr.set_line_width (1.8);
            cr.stroke ();
            if (app != "") {
                text (cr, app, 28, 10, 8.5, 0xffffff, 0.95, true);
                pill (cr, 64, 8, 18, 4, 0xffffff, 0.55);
                pill (cr, 88, 8, 22, 4, 0xffffff, 0.55);
                pill (cr, 116, 8, 26, 4, 0xffffff, 0.55);
            }
            for (int i = 0; i < 3; i++) {
                rrect (cr, 520 + i * 15, 6, 8, 8, 2);
                rgb (cr, 0xffffff, 0.8);
                cr.fill ();
            }
            text (cr, "Sat 11:02", 630, 10, 8.5, 0xffffff, 0.95, true, false, true);
        }

        private void dock (Cairo.Context cr) {
            var real = RealDesktop.get_default ();
            if (real.dock != null && real.screen_width > 0) {
                double s = W / (real.screen_width * real.panel_scale);
                dock_w = real.dock.get_width () * s;
                dock_h = real.dock.get_height () * s;
                dock_x = (W - dock_w) / 2;
                dock_y = H - dock_h - 10 * W / real.screen_width;
                cr.save ();
                cr.translate (dock_x, dock_y);
                cr.scale (s, s);
                cr.set_source_surface (real.dock, 0, 0);
                cr.get_source ().set_filter (Cairo.Filter.GOOD);
                cr.paint ();
                cr.restore ();
                return;
            }
            dock_x = 195;
            dock_y = 354;
            dock_w = 250;
            dock_h = 34;
            rrect (cr, 195, 354, 250, 34, 12);
            rgb (cr, 0x1c1d21, 0.96);
            cr.fill_preserve ();
            rgb (cr, 0xffffff, 0.1);
            cr.set_line_width (1);
            cr.stroke ();
            uint[] colors = { 0xe8e8ea, 0x1aa3c4, 0xc2386b, 0x2b2b30, 0x3a5bd6, 0xf2f2f2, 0x39404c };
            for (int i = 0; i < colors.length; i++) {
                double x = 207 + i * 33;
                rrect (cr, x, 360, 22, 22, 6);
                rgb (cr, colors[i]);
                cr.fill ();
                if (i == 3) {
                    cr.arc (x + 11, 371, 6, 0, 2 * Math.PI);
                    rgb (cr, 0x7b3fe4);
                    cr.fill ();
                }
            }
            cr.arc (207 + 33 + 11, 386, 1.6, 0, 2 * Math.PI);
            rgb (cr, 0xffffff, 0.9);
            cr.fill ();
        }

        private void window (Cairo.Context cr, double x, double y, double w, double h, string content) {
            cr.save ();
            rrect (cr, x + 2, y + 6, w, h, 12);
            rgb (cr, 0x000000, 0.35);
            cr.fill ();
            rrect (cr, x, y, w, h, 12);
            cr.clip ();
            rgb (cr, 0xf5f5f7);
            cr.paint ();
            double side = content == "write" ? 0 : double.min (110, w * 0.3);
            if (side > 0) {
                cr.rectangle (x, y, side, h);
                rgb (cr, 0xe4e9f1);
                cr.fill ();
            }
            for (int i = 0; i < 3; i++) {
                cr.arc (x + w - 16 - i * 19, y + 16, 7, 0, 2 * Math.PI);
                set_accent (cr, 0.22);
                cr.fill ();
            }
            switch (content) {
                case "files":
                    for (int i = 0; i < 4; i++) {
                        if (i == 1) {
                            rrect (cr, x + 8, y + 36 + i * 20, side - 16, 16, 6);
                            set_accent (cr, 0.2);
                            cr.fill ();
                        }
                        pill (cr, x + 16, y + 42 + i * 20, 12, 5, 0x5a6270, 0.7);
                        pill (cr, x + 34, y + 42 + i * 20, 40, 5, 0x2b2f36, 0.55);
                    }
                    for (int i = 0; i < 6; i++) {
                        double rx = x + side + 16;
                        double ry = y + 52 + i * 24;
                        if (ry > y + h - 20) break;
                        rrect (cr, rx, ry, 14, 11, 3);
                        rgb (cr, 0x4a90d9, 0.9);
                        cr.fill ();
                        pill (cr, rx + 22, ry + 3, 70, 5, 0x2b2f36, 0.6);
                        pill (cr, x + w - 90, ry + 3, 60, 5, 0x2b2f36, 0.25);
                    }
                    break;
                case "write":
                    rrect (cr, x + w * 0.16, y + 40, w * 0.68, h - 40, 4);
                    rgb (cr, 0xffffff);
                    cr.fill ();
                    pill (cr, x + w * 0.22, y + 62, w * 0.34, 8, 0x1d1f24, 0.85);
                    for (int i = 0; i < 9; i++) {
                        double ly = y + 86 + i * 16;
                        if (ly > y + h - 12) break;
                        double lw = i % 4 == 3 ? w * 0.3 : w * 0.54;
                        pill (cr, x + w * 0.22, ly, lw, 5, 0x2b2f36, 0.4);
                    }
                    break;
                case "store":
                    for (int i = 0; i < 5; i++) {
                        if (i == 0) {
                            rrect (cr, x + 8, y + 36, side - 16, 16, 6);
                            set_accent (cr, 0.2);
                            cr.fill ();
                        }
                        pill (cr, x + 16, y + 42 + i * 20, 12, 5, 0x5a6270, 0.7);
                        pill (cr, x + 34, y + 42 + i * 20, 44, 5, 0x2b2f36, 0.55);
                    }
                    double cx = x + side + 16;
                    double cw = w - side - 32;
                    var a = accent ();
                    var g = new Cairo.Pattern.linear (cx, 0, cx + cw, 0);
                    g.add_color_stop_rgba (0, a.red, a.green, a.blue, 1);
                    g.add_color_stop_rgba (1, a.red * 0.55, a.green * 0.55, a.blue * 0.75, 1);
                    rrect (cr, cx, y + 40, cw, 100, 12);
                    cr.set_source (g);
                    cr.fill ();
                    pill (cr, cx + 20, y + 72, 120, 10, 0xffffff, 0.95);
                    pill (cr, cx + 20, y + 92, 170, 6, 0xffffff, 0.7);
                    pill (cr, cx + 20, y + 112, 46, 14, 0xffffff, 0.95);
                    uint[] icons = { 0xe5534b, 0x2fb67c, 0xf0a531 };
                    double card = (cw - 20) / 3;
                    for (int i = 0; i < 3; i++) {
                        double kx = cx + i * (card + 10);
                        rrect (cr, kx, y + 156, card, 110, 12);
                        rgb (cr, 0xffffff);
                        cr.fill ();
                        rrect (cr, kx + 12, y + 170, 30, 30, 8);
                        rgb (cr, icons[i]);
                        cr.fill ();
                        pill (cr, kx + 12, y + 212, card * 0.55, 6, 0x1d1f24, 0.75);
                        pill (cr, kx + 12, y + 226, card * 0.75, 5, 0x2b2f36, 0.35);
                        rrect (cr, kx + 12, y + 242, 38, 14, 7);
                        set_accent (cr, 1);
                        cr.fill ();
                    }
                    break;
                case "help":
                    for (int i = 0; i < 4; i++) {
                        if (i == 0) {
                            rrect (cr, x + 8, y + 36, side - 16, 16, 6);
                            set_accent (cr, 0.2);
                            cr.fill ();
                        }
                        pill (cr, x + 16, y + 42 + i * 20, 12, 5, 0x5a6270, 0.7);
                        pill (cr, x + 34, y + 42 + i * 20, 50, 5, 0x2b2f36, 0.55);
                    }
                    double hx = x + side + 36;
                    double hw = w - side - 72;
                    pill (cr, hx, y + 46, 140, 12, 0x1d1f24, 0.9);
                    pill (cr, hx, y + 70, 200, 6, 0x2b2f36, 0.45);
                    rrect (cr, hx, y + 92, hw, 150, 10);
                    rgb (cr, 0xffffff);
                    cr.fill_preserve ();
                    rgb (cr, 0x000000, 0.06);
                    cr.set_line_width (1);
                    cr.stroke ();
                    for (int i = 0; i < 4; i++) {
                        double ry = y + 92 + i * 37.5;
                        if (i > 0) {
                            cr.move_to (hx, ry);
                            cr.line_to (hx + hw, ry);
                            rgb (cr, 0x000000, 0.06);
                            cr.stroke ();
                        }
                        pill (cr, hx + 14, ry + 12, 90 + (i % 2) * 30, 6, 0x1d1f24, 0.8);
                        pill (cr, hx + 14, ry + 24, 150, 5, 0x2b2f36, 0.35);
                        cr.move_to (hx + hw - 18, ry + 14);
                        cr.line_to (hx + hw - 13, ry + 19);
                        cr.line_to (hx + hw - 18, ry + 24);
                        rgb (cr, 0x2b2f36, 0.6);
                        cr.set_line_width (1.6);
                        cr.stroke ();
                    }
                    break;
            }
            cr.restore ();
        }

        private void calendar_card (Cairo.Context cr) {
            rrect (cr, 478, 26, 156, 132, 14);
            rgb (cr, 0x1c1d21, 0.97);
            cr.fill_preserve ();
            rgb (cr, 0xffffff, 0.1);
            cr.set_line_width (1);
            cr.stroke ();
            pill (cr, 492, 40, 60, 7, 0xffffff, 0.9);
            for (int r = 0; r < 5; r++) {
                for (int c = 0; c < 7; c++) {
                    double px = 496 + c * 20;
                    double py = 64 + r * 18;
                    if (r == 2 && c == 5) {
                        cr.arc (px, py, 7, 0, 2 * Math.PI);
                        set_accent (cr, 1);
                        cr.fill ();
                    }
                    cr.arc (px, py, 1.8, 0, 2 * Math.PI);
                    rgb (cr, 0xffffff, r == 2 && c == 5 ? 1 : 0.55);
                    cr.fill ();
                }
            }
        }

        private void launcher (Cairo.Context cr) {
            cr.rectangle (0, 20, W, H - 20);
            rgb (cr, 0x1f2229, 0.97);
            cr.fill ();
            rrect (cr, 190, 36, 260, 26, 8);
            rgb (cr, 0x2e323a);
            cr.fill ();
            cr.arc (204, 49, 4.5, 0, 2 * Math.PI);
            rgb (cr, 0xffffff, 0.85);
            cr.set_line_width (1.6);
            cr.stroke ();
            cr.move_to (207.5, 52.5);
            cr.line_to (211, 56);
            cr.stroke ();
            text (cr, "fil", 218, 49, 10, 0xffffff, 0.95);
            cr.rectangle (234, 42, 1.2, 14);
            set_accent (cr, 1);
            cr.fill ();
            uint[] colors = { 0x1aa3c4, 0xf2f2f4, 0xf2f2f4, 0x39404c };
            for (int i = 0; i < 4; i++) {
                double cx = 128 + i * 128;
                double cy = 140;
                if (i == 0) {
                    rrect (cr, cx - 46, cy - 36, 92, 92, 14);
                    rgb (cr, 0xffffff, 0.1);
                    cr.fill ();
                }
                rrect (cr, cx - 22, cy - 22, 44, 44, 10);
                rgb (cr, colors[i]);
                cr.fill ();
                if (i == 1 || i == 2) {
                    for (int l = 0; l < 4; l++) pill (cr, cx - 13, cy - 12 + l * 7, l == 3 ? 16 : 26, 3, 0x6b7380, 0.8);
                }
                if (i == 3) {
                    cr.arc (cx, cy, 11, 0, 2 * Math.PI);
                    rgb (cr, 0xffffff, 0.85);
                    cr.set_line_width (2.5);
                    cr.stroke ();
                }
                pill (cr, cx - 20, cy + 34, 40, 5, 0xffffff, i == 0 ? 0.9 : 0.55);
            }
        }

        private void assistant (Cairo.Context cr) {
            double x = 360, y = 38, w = 252;
            rrect (cr, x + 2, y + 6, w, 206, 14);
            rgb (cr, 0x000000, 0.3);
            cr.fill ();
            rrect (cr, x, y, w, 206, 14);
            rgb (cr, 0x1f2229, 0.97);
            cr.fill ();
            rrect (cr, x + 10, y + 10, w - 20, 26, 8);
            rgb (cr, 0x2e323a);
            cr.fill ();
            text (cr, "add milk to my shopping list", x + 20, y + 23, 9, 0xffffff, 0.95);
            double t = 0.5 + 0.5 * Math.sin (phase * 2 * Math.PI);
            cr.rectangle (x + 176, y + 16, 1.2, 14);
            set_accent (cr, t);
            cr.fill ();
            for (int i = 0; i < 2; i++) {
                double cy = y + 48 + i * 74;
                rrect (cr, x + 10, cy, w - 20, 64, 10);
                rgb (cr, 0xffffff, i == 0 ? 0.1 : 0.06);
                cr.fill ();
                rrect (cr, x + 20, cy + 12, 28, 28, 7);
                rgb (cr, i == 0 ? 0xf0a531 : 0x2fb67c);
                cr.fill ();
                pill (cr, x + 58, cy + 16, i == 0 ? 96 : 120, 7, 0xffffff, 0.9);
                pill (cr, x + 58, cy + 30, i == 0 ? 150 : 110, 5, 0xffffff, 0.5);
                rrect (cr, x + w - 70, cy + 40, 50, 16, 8);
                set_accent (cr, i == 0 ? 1 : 0.35);
                cr.fill ();
            }
        }

        private void snap_hint (Cairo.Context cr) {
            double t = 0.5 + 0.5 * Math.sin (phase * 2 * Math.PI);
            rrect (cr, 4, 24, 314, 326, 12);
            set_accent (cr, 0.1 + 0.08 * t);
            cr.fill_preserve ();
            set_accent (cr, 0.85);
            cr.set_line_width (2.5);
            cr.stroke ();
            double kx = 241;
            double ky = 288;
            rrect (cr, kx - 14, ky - 12, 186, 58, 16);
            rgb (cr, 0x1c1d21, 0.94);
            cr.fill_preserve ();
            rgb (cr, 0xffffff, 0.12);
            cr.set_line_width (1);
            cr.stroke ();
            keycap (cr, kx, ky, 86, "Super");
            text (cr, "+", kx + 100, ky + 16, 16, 0xffffff, 0.9, true, true);
            keycap (cr, kx + 114, ky, 44, "");
            cr.move_to (kx + 114 + 30, ky + 16);
            cr.line_to (kx + 114 + 14, ky + 16);
            cr.move_to (kx + 114 + 20, ky + 10);
            cr.line_to (kx + 114 + 14, ky + 16);
            cr.line_to (kx + 114 + 20, ky + 22);
            rgb (cr, 0x1d1f24, 0.9);
            cr.set_line_width (2.2);
            cr.set_line_cap (Cairo.LineCap.ROUND);
            cr.set_line_join (Cairo.LineJoin.ROUND);
            cr.stroke ();
        }

        private void keycap (Cairo.Context cr, double x, double y, double w, string label) {
            rrect (cr, x, y + 3, w, 32, 8);
            rgb (cr, 0x9aa0aa);
            cr.fill ();
            rrect (cr, x, y, w, 32, 8);
            rgb (cr, 0xfafafb);
            cr.fill ();
            if (label != "") text (cr, label, x + w / 2, y + 16, 12, 0x1d1f24, 0.9, true, true);
        }

        private void overview (Cairo.Context cr) {
            rgb (cr, 0x14161a);
            cr.paint ();
            var a = accent ();
            var g = new Cairo.Pattern.radial (W / 2, 0, 20, W / 2, 0, 420);
            g.add_color_stop_rgba (0, a.red, a.green, a.blue, 0.22);
            g.add_color_stop_rgba (1, a.red, a.green, a.blue, 0);
            cr.set_source (g);
            cr.paint ();
            double tw = 132;
            double th = 83;
            double gap = 18;
            double start = (W - (4 * tw + 3 * gap)) / 2;
            int active = (int) (phase * 3) % 3;
            for (int i = 0; i < 4; i++) {
                double x = start + i * (tw + gap);
                double y = 70;
                rrect (cr, x, y, tw, th, 10);
                if (i == 3) {
                    double[] dash = { 5, 4 };
                    cr.set_dash (dash, 0);
                    rgb (cr, 0xffffff, 0.35);
                    cr.set_line_width (1.5);
                    cr.stroke ();
                    cr.set_dash (null, 0);
                    cr.move_to (x + tw / 2 - 9, y + th / 2);
                    cr.line_to (x + tw / 2 + 9, y + th / 2);
                    cr.move_to (x + tw / 2, y + th / 2 - 9);
                    cr.line_to (x + tw / 2, y + th / 2 + 9);
                    rgb (cr, 0xffffff, 0.5);
                    cr.set_line_width (2);
                    cr.stroke ();
                    continue;
                }
                rgb (cr, 0x0c0d10);
                cr.fill ();
                cr.save ();
                rrect (cr, x, y, tw, th, 10);
                cr.clip ();
                cr.translate (x, y);
                cr.scale (tw / W, th / H);
                cr.move_to (0, 300);
                cr.curve_to (180, 250, 300, 130, 640, 180);
                cr.line_to (640, 400);
                cr.line_to (0, 400);
                cr.close_path ();
                rgb (cr, 0x1a1b1f);
                cr.fill ();
                double[,] wins = { { 60, 60, 300, 220 }, { 280, 90, 300, 240 }, { 120, 40, 400, 280 } };
                for (int k = 0; k <= i % 2; k++) {
                    int idx = (i + k) % 3;
                    rrect (cr, wins[idx, 0], wins[idx, 1], wins[idx, 2], wins[idx, 3], 30);
                    rgb (cr, 0xf5f5f7);
                    cr.fill ();
                }
                cr.restore ();
                if (i == active) {
                    rrect (cr, x - 3, y - 3, tw + 6, th + 6, 12);
                    set_accent (cr, 1);
                    cr.set_line_width (2.5);
                    cr.stroke ();
                }
            }
            double big_w = 360;
            double big_h = 225;
            double bx = (W - big_w) / 2;
            double by = 172;
            cr.save ();
            rrect (cr, bx, by, big_w, big_h, 16);
            cr.clip ();
            cr.translate (bx, by);
            cr.scale (big_w / W, big_h / H);
            desktop (cr, "");
            window (cr, 60, 50, 330, 240, "files");
            window (cr, 250, 100, 330, 220, "write");
            cr.restore ();
            touchpad (cr, 540, 300);
        }

        private void touchpad (Cairo.Context cr, double x, double y) {
            rrect (cr, x, y, 84, 58, 10);
            rgb (cr, 0xffffff, 0.08);
            cr.fill_preserve ();
            rgb (cr, 0xffffff, 0.25);
            cr.set_line_width (1.2);
            cr.stroke ();
            double shift = 12 * Math.sin (phase * 2 * Math.PI);
            for (int i = 0; i < 3; i++) {
                cr.arc (x + 30 + i * 12 + shift, y + 29, 4.5, 0, 2 * Math.PI);
                set_accent (cr, 1);
                cr.fill ();
            }
        }

        private void settings_panel (Cairo.Context cr) {
            rrect (cr, 392, 26, 240, 318, 16);
            rgb (cr, 0x17181c, 0.97);
            cr.fill_preserve ();
            rgb (cr, 0xffffff, 0.1);
            cr.set_line_width (1);
            cr.stroke ();
            pill (cr, 408, 42, 70, 8, 0xffffff, 0.9);
            uint[] walls = { 0x0c0d10, 0x2b3a67, 0x5a3d7a };
            for (int i = 0; i < 3; i++) {
                rrect (cr, 408 + i * 72, 62, 64, 42, 8);
                rgb (cr, walls[i]);
                cr.fill ();
                if (i == 0) {
                    rrect (cr, 406, 60, 68, 46, 10);
                    set_accent (cr, 1);
                    cr.set_line_width (2);
                    cr.stroke ();
                }
            }
            pill (cr, 408, 122, 56, 6, 0xffffff, 0.6);
            uint[] swatches = { 0x3584e4, 0x2190a4, 0x3a944a, 0xc88800, 0xed5b00, 0xe62d42, 0xd56199, 0x9141ac };
            for (int i = 0; i < swatches.length; i++) {
                double sx = 418 + i * 27;
                cr.arc (sx, 146, 9, 0, 2 * Math.PI);
                rgb (cr, swatches[i]);
                cr.fill ();
            }
            cr.arc (418 + 7 * 27, 146, 13, 0, 2 * Math.PI);
            set_accent (cr, 1);
            cr.set_line_width (2);
            cr.stroke ();
            pill (cr, 408, 176, 70, 6, 0xffffff, 0.6);
            rrect (cr, 408, 190, 104, 64, 10);
            rgb (cr, 0xf2f2f4);
            cr.fill ();
            rrect (cr, 520, 190, 104, 64, 10);
            rgb (cr, 0x2a2c31);
            cr.fill ();
            rrect (cr, 518, 188, 108, 68, 12);
            set_accent (cr, 1);
            cr.set_line_width (2);
            cr.stroke ();
            for (int i = 0; i < 2; i++) {
                double ry = 276 + i * 30;
                pill (cr, 408, ry, 90, 6, 0xffffff, 0.6);
                rrect (cr, 588, ry - 6, 30, 18, 9);
                if (i == 0) set_accent (cr, 1);
                else rgb (cr, 0xffffff, 0.2);
                cr.fill ();
                cr.arc (i == 0 ? 609 : 597, ry + 3, 7, 0, 2 * Math.PI);
                rgb (cr, 0xffffff);
                cr.fill ();
            }
        }

        private void done (Cairo.Context cr) {
            double cx = W / 2;
            double cy = H / 2;
            uint[] colors = { 0xf6d32d, 0x33d17a, 0xff7800, 0xdc8add, 0x62a0ea, 0xffffff };
            for (int i = 0; i < 18; i++) {
                double ang = i * 2 * Math.PI / 18 + 0.2;
                double r = 118 + (i % 3) * 22 + 6 * Math.sin (phase * 2 * Math.PI + i);
                cr.save ();
                cr.translate (cx + r * Math.cos (ang), cy + r * Math.sin (ang));
                cr.rotate (ang + i);
                rrect (cr, -6, -2.5, 12, 5, 2.5);
                rgb (cr, colors[i % colors.length], 0.9);
                cr.fill ();
                cr.restore ();
            }
            cr.arc (cx, cy, 64, 0, 2 * Math.PI);
            set_accent (cr, 1);
            cr.fill ();
            cr.move_to (cx - 26, cy + 2);
            cr.line_to (cx - 8, cy + 20);
            cr.line_to (cx + 28, cy - 18);
            rgb (cr, 0xffffff);
            cr.set_line_width (10);
            cr.set_line_cap (Cairo.LineCap.ROUND);
            cr.set_line_join (Cairo.LineJoin.ROUND);
            cr.stroke ();
        }

        private void lens (Cairo.Context cr, Cairo.ImageSurface src, double sx, double sy, double sw, double sh,
                           double dx, double dy, double dw, double from_x, double from_y) {
            double scale = dw / sw;
            double dh = sh * scale;
            set_accent (cr, 0.9);
            cr.set_line_width (1.5);
            cr.move_to (from_x, from_y);
            cr.line_to (dx + dw / 2, dy);
            cr.stroke ();
            rrect (cr, dx - 6 + 2, dy - 6 + 6, dw + 12, dh + 12, 14);
            rgb (cr, 0x000000, 0.35);
            cr.fill ();
            rrect (cr, dx - 6, dy - 6, dw + 12, dh + 12, 14);
            rgb (cr, 0x000000, 0.92);
            cr.fill_preserve ();
            set_accent (cr, 1);
            cr.set_line_width (2);
            cr.stroke ();
            cr.save ();
            rrect (cr, dx, dy, dw, dh, 9);
            cr.clip ();
            cr.translate (dx, dy);
            cr.scale (scale, scale);
            cr.set_source_surface (src, -sx, -sy);
            cr.get_source ().set_filter (Cairo.Filter.GOOD);
            cr.paint ();
            cr.restore ();
        }

        private bool real_bar_lenses (Cairo.Context cr) {
            var real = RealDesktop.get_default ();
            if (real.panel == null) return false;
            double pw = real.panel.get_width (), ph = real.panel.get_height ();
            double crop = double.min (pw * 0.42, 520 * real.panel_scale);
            double lw = 280;
            double s = W / pw;
            lens (cr, real.panel, 0, 0, crop, ph, 24, bar_h + 44, lw, crop * s / 2, bar_h);
            lens (cr, real.panel, pw - crop, 0, crop, ph, W - 24 - lw, bar_h + 96, lw, W - crop * s / 2, bar_h);
            return true;
        }

        private bool real_dock_lens (Cairo.Context cr) {
            var real = RealDesktop.get_default ();
            if (real.dock == null) return false;
            double dw = double.min (460, real.dock.get_width () / real.panel_scale * 1.0);
            double dh = real.dock.get_height () * dw / real.dock.get_width ();
            lens (cr, real.dock, 0, 0, real.dock.get_width (), real.dock.get_height (), (W - dw) / 2, dock_y - dh - 70, dw, W / 2, dock_y);
            return true;
        }

        private void highlight (Cairo.Context cr, double x, double y, double w, double h, double r) {
            double t = 0.5 + 0.5 * Math.sin (phase * 2 * Math.PI);
            cr.save ();
            cr.set_fill_rule (Cairo.FillRule.EVEN_ODD);
            cr.rectangle (0, 0, W, H);
            rrect (cr, x - 4, y - 4, w + 8, h + 8, r + 4);
            rgb (cr, 0x000000, 0.42);
            cr.fill ();
            cr.restore ();
            rrect (cr, x - 4, y - 4, w + 8, h + 8, r + 4);
            set_accent (cr, 0.18 + 0.2 * t);
            cr.set_line_width (8 + 4 * t);
            cr.stroke_preserve ();
            set_accent (cr, 1);
            cr.set_line_width (2.2);
            cr.stroke ();
        }
    }
}
