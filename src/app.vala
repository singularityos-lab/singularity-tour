using Gtk;

namespace Singularity.Apps.Tour {

    public class TourApp : Singularity.Application {

        public TourApp () {
            Object (application_id: "dev.sinty.tour", flags: ApplicationFlags.DEFAULT_FLAGS);
            add_main_option ("slide", 0, OptionFlags.NONE, OptionArg.STRING, _("Open the tour at a slide"), _("SLIDE"));
        }

        protected override int handle_local_options (VariantDict options) {
            string slide;
            if (!options.lookup ("slide", "s", out slide) || slide.strip () == "") return -1;
            try {
                register ();
            } catch (Error e) {
                return 1;
            }
            activate_action ("show-slide", new Variant.string (slide.strip ()));
            return get_is_remote () ? 0 : -1;
        }

        private TourWindow ensure_window () {
            var window = get_active_window () as TourWindow;
            if (window == null) window = new TourWindow (this);
            window.present ();
            return window;
        }

        protected override void startup () {
            base.startup ();
            var provider = new CssProvider ();
            provider.load_from_string (CSS);
            StyleContext.add_provider_for_display (Gdk.Display.get_default (), provider, STYLE_PROVIDER_PRIORITY_USER + 1);
            var menu = new GLib.Menu ();
            var file_menu = new GLib.Menu ();
            file_menu.append (_("Close Window"), "win.close");
            file_menu.append (_("Quit"), "app.quit");
            menu.append_submenu (_("File"), file_menu);
            var edit_menu = new GLib.Menu ();
            edit_menu.append (_("Settings"), "app.settings");
            menu.append_submenu (_("Edit"), edit_menu);
            var go_menu = new GLib.Menu ();
            go_menu.append (_("Previous Slide"), "win.previous");
            go_menu.append (_("Next Slide"), "win.next");
            menu.append_submenu (_("Go"), go_menu);
            set_menubar (menu);
            var quit_action = new SimpleAction ("quit", null);
            quit_action.activate.connect (() => quit ());
            add_action (quit_action);
            var settings_action = new SimpleAction ("settings", null);
            settings_action.activate.connect (() => {
                try {
                    Singularity.Shell.ShellService shell = Bus.get_proxy_sync (BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                    shell.open_app_settings ("dev.sinty.tour");
                } catch (Error e) {
                    warning ("Failed to open settings: %s", e.message);
                }
            });
            add_action (settings_action);
            var slide_action = new SimpleAction ("show-slide", VariantType.STRING);
            slide_action.activate.connect ((param) => ensure_window ().show_slide (param.get_string ()));
            add_action (slide_action);
            set_accels_for_action ("app.quit", { "<Control>q" });
            set_accels_for_action ("app.settings", { "<Control>comma" });
            set_accels_for_action ("win.close", { "<Control>w" });
            set_accels_for_action ("win.previous", { "Left", "Page_Up" });
            set_accels_for_action ("win.next", { "Right", "Page_Down" });
        }

        public override void activate () {
            ensure_window ();
        }

        private const string CSS = """
.tour-scene {
    color: @accent_color;
}

.tour-content {
    background-color: @view_bg_color;
}

.tour-title {
    font-size: 26px;
    font-weight: 800;
    margin-bottom: 10px;
}

.tour-body {
    font-size: 15px;
    color: alpha(@window_fg_color, 0.7);
}

.tour-action {
    margin-top: 18px;
    border-radius: 99px;
    padding: 6px 20px;
    font-weight: 600;
    color: @accent_color;
    background-color: alpha(@accent_bg_color, 0.14);
    border: none;
    box-shadow: none;
}

.tour-action:hover {
    background-color: alpha(@accent_bg_color, 0.24);
}
""";
    }

    public static int main (string[] args) {
        Intl.setlocale (LocaleCategory.ALL, "");
        string locale_dir = "/usr/share/locale";
        try {
            string exe = FileUtils.read_link ("/proc/self/exe");
            locale_dir = Path.build_filename (Path.get_dirname (Path.get_dirname (exe)), "share", "locale");
        } catch (Error e) {
        }
        Intl.bindtextdomain ("singularity-tour", locale_dir);
        Intl.bind_textdomain_codeset ("singularity-tour", "UTF-8");
        Intl.textdomain ("singularity-tour");
        return new TourApp ().run (args);
    }
}
