using Gtk;
using Singularity;

namespace Singularity.Apps.Tour {

    public class TipProvider : Object, OverviewWidgetProvider {
        public string id { get { return "tour.tip-of-the-day"; } }
        public string provider_id { get { return "dev.sinty.tour"; } }
        public string display_name { get { return _("Tip of the Day"); } }
        public string icon_name { get { return "dialog-information-symbolic"; } }
        private WidgetSize[] sizes = { WidgetSize (2, 1) };
        public WidgetSize[] supported_sizes { get { return sizes; } }

        public Gtk.Widget create_instance (string instance_id, WidgetSize size, Variant? config) {
            return new TipWidget ();
        }
    }

    public struct Tip {
        public string keys;
        public string icon;
        public string text;
        public string slide;
    }

    public class TipWidget : Box {
        private Button button;
        private uint timer = 0;
        private int shown = -1;

        public static Tip[] tips () {
            return {
                { "Super", "", _("Open the launcher and type the name of an app, a file or a setting."), "30-launcher" },
                { "Super Tab", "", _("Open the command palette to run any command."), "30-launcher" },
                { "Super W", "", _("See every workspace at once."), "60-workspaces" },
                { "", "input-touchpad-symbolic", _("Swipe sideways on the touchpad to move between workspaces."), "60-workspaces" },
                { "Super Left", "", _("Snap a window to half of the screen with Super and the arrow keys."), "50-windows" },
                { "Super R", "", _("Arrange every window of the workspace in a grid."), "50-windows" },
                { "Super D", "", _("Show the desktop."), "50-windows" },
                { "", "input-mouse-symbolic", _("Right-click an app in the dock to keep it there or open a new window."), "40-dock" },
                { "", "x-office-calendar-symbolic", _("Click the clock in the top bar to open the calendar."), "20-top-bar" }
            };
        }

        public static int today () {
            var now = new DateTime.now_local ();
            int n = tips ().length;
            return (int) (((int64) now.get_year () * 366 + now.get_day_of_year ()) % n);
        }

        public TipWidget () {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            add_css_class ("overview-widget-card");
            hexpand = true;
            vexpand = true;
            button = new Button ();
            button.has_frame = false;
            button.add_css_class ("flat");
            button.hexpand = true;
            button.vexpand = true;
            button.tooltip_text = _("Open this step of the tour");
            button.clicked.connect (open_slide);
            append (button);
            map.connect (() => {
                update ();
                if (timer == 0) timer = Timeout.add_seconds (600, () => {
                    update ();
                    return Source.CONTINUE;
                });
            });
            unmap.connect (() => {
                if (timer != 0) Source.remove (timer);
                timer = 0;
            });
        }

        private void update () {
            int index = today ();
            if (index == shown) return;
            shown = index;
            var tip = tips ()[index];
            var box = new Box (Orientation.HORIZONTAL, 14);
            box.margin_start = 10;
            box.margin_end = 10;
            box.margin_top = 6;
            box.margin_bottom = 6;
            box.valign = Align.CENTER;
            var keys = new Box (Orientation.HORIZONTAL, 4);
            keys.valign = Align.CENTER;
            if (tip.keys != "") {
                foreach (string key in tip.keys.split (" ")) {
                    var cap = new Label (key_label (key));
                    cap.add_css_class ("heading");
                    cap.width_chars = 2;
                    cap.set_size_request (-1, 34);
                    var pad = new Box (Orientation.HORIZONTAL, 0);
                    pad.add_css_class ("overview-widget-tile");
                    cap.margin_start = 10;
                    cap.margin_end = 10;
                    pad.append (cap);
                    keys.append (pad);
                }
            } else {
                var icon = new Image.from_icon_name (tip.icon);
                icon.pixel_size = 32;
                keys.append (icon);
            }
            box.append (keys);
            var text = new Box (Orientation.VERTICAL, 2);
            text.valign = Align.CENTER;
            text.hexpand = true;
            var title = new Label (_("Tip of the Day"));
            title.add_css_class ("caption-heading");
            title.add_css_class ("dim-label");
            title.xalign = 0;
            text.append (title);
            var body = new Label (tip.text);
            body.xalign = 0;
            body.wrap = true;
            body.lines = 2;
            body.ellipsize = Pango.EllipsizeMode.END;
            text.append (body);
            box.append (text);
            button.child = box;
        }

        private static string key_label (string key) {
            switch (key) {
                case "Super": return _("Super");
                case "Tab": return _("Tab");
                case "Left": return _("Arrows");
                default: return key;
            }
        }

        private void open_slide () {
            var tip = tips ()[today ()];
            var info = new DesktopAppInfo ("dev.sinty.tour.desktop");
            string exe = info != null && info.get_executable () != null ? info.get_executable () : "singularity-tour";
            try {
                var app = AppInfo.create_from_commandline (GLib.Shell.quote (exe) + " --slide=" + GLib.Shell.quote (tip.slide), null, AppInfoCreateFlags.NONE);
                app.launch (null, get_display ().get_app_launch_context ());
            } catch (Error e) {
                warning ("Tip widget: %s", e.message);
            }
        }
    }

    [CCode (cname = "singularity_tour_widget_new")]
    public static Object singularity_tour_widget_new () {
        try {
            string exe = FileUtils.read_link ("/proc/self/exe");
            Intl.bindtextdomain ("singularity-tour", Path.build_filename (Path.get_dirname (Path.get_dirname (exe)), "share", "locale"));
            Intl.bind_textdomain_codeset ("singularity-tour", "UTF-8");
        } catch (Error e) {
        }
        return new TipProvider ();
    }
}
