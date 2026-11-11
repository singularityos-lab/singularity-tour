using Gtk;

namespace Singularity.Apps.Tour {

    public class TourWindow : Singularity.Widgets.Window {
        private Stack stack;
        private Singularity.Widgets.StepIsland island;
        private Gee.List<Slide> slides;
        private int current = 0;
        private Label counter;
        private SimpleAction previous_action;
        private SimpleAction next_action;
        private AgentSetup? agent_setup = null;

        public TourWindow (Gtk.Application app) {
            Object (application: app, title: _("Tour"));
            set_default_size (860, 700);

            slides = SlideDeck.load ();

            stack = new Stack ();
            stack.hexpand = true;
            stack.vexpand = true;
            stack.transition_type = StackTransitionType.SLIDE_LEFT_RIGHT;
            stack.transition_duration = 260;
            for (int i = 0; i < slides.size; i++) stack.add_named (page (slides[i]), i.to_string ());

            string[] names = {};
            foreach (var s in slides) names += "";
            island = new Singularity.Widgets.StepIsland (names);
            island.back_clicked.connect (() => go (current - 1));
            island.next_clicked.connect (() => {
                if (agent_setup != null && slides[current].setup == "agent") agent_setup.commit ();
                if (current >= slides.size - 1) close ();
                else go (current + 1);
            });

            counter = add_bubble_label ("", true);

            var overlay = new Overlay ();
            overlay.add_css_class ("tour-content");
            overlay.child = stack;
            overlay.add_overlay (island);
            set_content (overlay);

            var keys = new EventControllerKey ();
            keys.key_pressed.connect ((keyval, code, state) => {
                if (keyval == Gdk.Key.Right || keyval == Gdk.Key.Page_Down) {
                    if (current < slides.size - 1) go (current + 1);
                    return true;
                }
                if (keyval == Gdk.Key.Left || keyval == Gdk.Key.Page_Up) {
                    go (current - 1);
                    return true;
                }
                if (keyval == Gdk.Key.Escape) {
                    close ();
                    return true;
                }
                return false;
            });
            ((Widget) this).add_controller (keys);

            var close_action = new SimpleAction ("close", null);
            close_action.activate.connect (() => close ());
            add_action (close_action);
            previous_action = new SimpleAction ("previous", null);
            previous_action.activate.connect (() => go (current - 1));
            previous_action.set_enabled (false);
            add_action (previous_action);
            next_action = new SimpleAction ("next", null);
            next_action.activate.connect (() => {
                if (current < slides.size - 1) go (current + 1);
            });
            next_action.set_enabled (false);
            add_action (next_action);

            if (slides.size == 0) {
                counter.visible = false;
                var welcome = new Singularity.Widgets.WelcomePage ();
                welcome.app_icon_name = "dev.sinty.tour";
                welcome.title = _("Tour");
                welcome.subtitle = _("Your system has no tour to show. Help has guides for the desktop and your apps.");
                welcome.add_action ("dev.sinty.help", _("Open Help"), _("Guides for the desktop, your apps and your system"), () => run_action ("help:singularity"));
                welcome.add_action ("user-desktop", _("Close"), _("Start using the desktop"), () => close ());
                set_content (welcome);
                return;
            }
            go (0);
            notify["is-active"].connect (() => {
                if (!is_active) return;
                Timeout.add (500, () => {
                    RealDesktop.get_default ().start ();
                    return Source.REMOVE;
                });
            });
        }

        public void show_slide (string id) {
            for (int i = 0; i < slides.size; i++) {
                if (slides[i].id == id) {
                    go (i);
                    return;
                }
            }
        }

        private void go (int index) {
            if (index < 0 || index >= slides.size) return;
            stack.transition_type = index >= current ? StackTransitionType.SLIDE_LEFT : StackTransitionType.SLIDE_RIGHT;
            current = index;
            stack.visible_child_name = index.to_string ();
            island.step = index;
            counter.label = _("%d of %d").printf (index + 1, slides.size);
            island.back_visible = index > 0;
            previous_action.set_enabled (index > 0);
            next_action.set_enabled (index < slides.size - 1);
            update_next ();
        }

        private void update_next () {
            if (current == 0) island.next_label = _("Start the Tour");
            else if (current == slides.size - 1) island.next_label = _("Done");
            else if (slides[current].setup == "agent" && agent_setup != null && !agent_setup.verified) island.next_label = _("Skip");
            else island.next_label = _("Next");
        }

        private void skip_group () {
            string group = slides[current].group;
            if (group == "") {
                go (current + 1);
                return;
            }
            int target = current;
            while (target < slides.size - 1 && slides[target].group == group) target++;
            go (target);
        }

        private Widget page (Slide slide) {
            if (slide.setup == "agent") return setup_page (slide);
            var col = new Box (Orientation.VERTICAL, 0);
            col.valign = Align.FILL;
            col.margin_start = 40;
            col.margin_end = 40;
            col.margin_bottom = 96;
            Singularity.Widgets.apply_titlebar_inset (col);

            var scene = new Scene (slide);
            scene.halign = Align.FILL;
            scene.vexpand = true;
            scene.margin_top = 24;
            scene.margin_bottom = 28;
            col.append (scene);

            var title = new Label (slide.title);
            title.add_css_class ("tour-title");
            title.wrap = true;
            title.justify = Justification.CENTER;
            col.append (title);

            if (slide.body != "") {
                var body = new Label (slide.body);
                body.add_css_class ("tour-body");
                body.wrap = true;
                body.justify = Justification.CENTER;
                body.max_width_chars = 56;
                body.halign = Align.CENTER;
                col.append (body);
            }

            var actions = new Box (Orientation.HORIZONTAL, 12);
            actions.halign = Align.CENTER;
            actions.homogeneous = true;
            if (slide.action != "") actions.append (action_button (slide.action_label, slide.action));
            if (slide.secondary_action != "") actions.append (action_button (slide.secondary_label, slide.secondary_action));
            if (actions.get_first_child () != null) col.append (actions);

            return new Singularity.Widgets.Clamp (col, 640 + 80);
        }

        private Button action_button (string label, string action) {
            var btn = new Button.with_label (label);
            btn.add_css_class ("tour-action");
            btn.clicked.connect (() => run_action (action));
            return btn;
        }

        private Widget setup_page (Slide slide) {
            var col = new Box (Orientation.VERTICAL, 0);
            col.margin_start = 40;
            col.margin_end = 40;
            col.margin_top = 24;
            col.margin_bottom = 110;
            Singularity.Widgets.apply_titlebar_inset (col);

            var title = new Label (slide.title);
            title.add_css_class ("tour-title");
            title.wrap = true;
            title.justify = Justification.CENTER;
            col.append (title);

            if (slide.body != "") {
                var body = new Label (slide.body);
                body.add_css_class ("tour-body");
                body.wrap = true;
                body.justify = Justification.CENTER;
                body.max_width_chars = 56;
                body.halign = Align.CENTER;
                body.margin_bottom = 18;
                col.append (body);
            }

            agent_setup = new AgentSetup ();
            agent_setup.verified_changed.connect (update_next);
            col.append (agent_setup);

            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            scroll.child = new Singularity.Widgets.Clamp (col, 560 + 80);
            return scroll;
        }

        private void run_action (string action) {
            try {
                if (action == "skip") {
                    skip_group ();
                } else if (action.has_prefix ("slide:")) {
                    show_slide (action.substring (6));
                } else if (action.has_prefix ("app:")) {
                    string id = action.substring (4);
                    if (!id.has_suffix (".desktop")) id += ".desktop";
                    var info = new GLib.DesktopAppInfo (id);
                    if (info != null) info.launch (null, get_display ().get_app_launch_context ());
                } else if (action.has_prefix ("settings:")) {
                    Singularity.Shell.ShellService shell = Bus.get_proxy_sync (BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                    shell.open_settings (action.substring (9));
                } else if (action.has_prefix ("help:") || action.has_prefix ("man:")) {
                    var help = new GLib.DesktopAppInfo ("dev.sinty.help.desktop");
                    var uris = new GLib.List<string> ();
                    uris.append (action);
                    if (help != null) help.launch_uris (uris, get_display ().get_app_launch_context ());
                    else AppInfo.launch_default_for_uri (action, get_display ().get_app_launch_context ());
                } else {
                    AppInfo.launch_default_for_uri (action, get_display ().get_app_launch_context ());
                }
            } catch (Error e) {
                warning ("tour action %s: %s", action, e.message);
            }
        }
    }
}
