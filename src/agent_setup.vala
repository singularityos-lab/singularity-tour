using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Tour {

    public class AgentSetup : Box {
        public const string BINARY = "sinty";
        private const string[] IDS = { "local", "claude-code", "claude-api", "codex", "ollama" };
        private const string[] MODES = { "plan", "ask", "auto" };

        public signal void verified_changed ();
        public bool verified { get; private set; default = false; }

        public SelectionRow provider_row;
        public EntryRow model_row;
        private PasswordRow key_row;
        private ActionRow login_row;
        private ActionRow check_row;
        private Button check_btn;
        private Spinner spinner;
        private SelectionRow mode_row;
        private SwitchRow voice_row;
        private SwitchRow background_row;
        private Cancellable? running = null;

        private static string[] provider_names () {
            return { _("This Computer"), _("Claude Code"), _("Claude API"), _("Codex"), _("Ollama Cloud") };
        }

        private static string[] mode_names () {
            return { _("Plan"), _("Ask First"), _("Automatic") };
        }

        public static string config_path () {
            return Path.build_filename (Environment.get_user_config_dir (), "sinty-agent", "config.json");
        }

        public AgentSetup () {
            Object (orientation: Orientation.VERTICAL, spacing: 18);

            var model = new PreferencesGroup (_("Model"),
                _("Nothing leaves this computer until you choose a model. This Computer keeps everything here."));
            provider_row = new SelectionRow (_("Provider"), provider_names (), provider_names ()[0]);
            provider_row.selected.connect (() => provider_changed ());
            model.add_row (provider_row);
            model_row = new EntryRow (_("Model Name"));
            model_row.entry_changed.connect (() => reset ());
            model.add_row (model_row);
            key_row = new PasswordRow (_("API Key"));
            key_row.entry_changed.connect (() => reset ());
            model.add_row (key_row);
            login_row = new ActionRow (_("Sign In"));
            var login_btn = new Button.with_label (_("Open"));
            login_btn.valign = Align.CENTER;
            login_btn.clicked.connect (sign_in);
            login_row.add_suffix (login_btn);
            model.add_row (login_row);
            check_row = new ActionRow (_("Check the Model"), _("Sends one short real request and waits for the answer"));
            spinner = new Spinner ();
            spinner.visible = false;
            check_row.add_suffix (spinner);
            check_btn = new Button.with_label (_("Check"));
            check_btn.add_css_class ("suggested-action");
            check_btn.valign = Align.CENTER;
            check_btn.clicked.connect (() => check.begin ());
            check_row.add_suffix (check_btn);
            model.add_row (check_row);
            append (model);

            var behaviour = new PreferencesGroup (_("Behaviour"), _("Plan only reads and suggests. Ask First asks before lasting changes. Automatic asks only before what cannot be undone."));
            mode_row = new SelectionRow (_("Mode"), mode_names (), mode_names ()[1]);
            behaviour.add_row (mode_row);
            var keys_row = new ActionRow (_("Shortcuts"), _("Super+A to type, Super+Shift+A to talk"));
            behaviour.add_row (keys_row);
            voice_row = new SwitchRow (_("Voice"), _("Listen while Super+Shift+A is held"), true);
            behaviour.add_row (voice_row);
            background_row = new SwitchRow (_("Work in the Background"),
                _("Finish tasks while you use other apps. It still asks before anything that cannot be undone."), false);
            behaviour.add_row (background_row);
            append (behaviour);

            provider_changed ();
        }

        private string provider () {
            int i = provider_row.selected_index;
            return i >= 0 && i < IDS.length ? IDS[i] : IDS[0];
        }

        private void provider_changed () {
            string p = provider ();
            key_row.visible = p == "claude-api" || p == "ollama";
            model_row.visible = p != "claude-code" && p != "codex";
            login_row.visible = p == "claude-code" || p == "codex";
            login_row.subtitle = p == "codex"
                ? _("Codex uses your own login. Sign in once in its program.")
                : _("Claude Code uses your own login. Sign in once in its program.");
            model_row.placeholder_text = p == "local" ? _("Built-in model") : (p == "ollama" ? "gpt-oss:120b" : "claude-sonnet-5-5");
            reset ();
        }

        private void reset () {
            if (running != null) running.cancel ();
            check_row.subtitle = _("Sends one short real request and waits for the answer");
            if (verified) {
                verified = false;
                verified_changed ();
            }
        }

        private void sign_in () {
            string command = provider () == "codex" ? "codex login" : "claude";
            try {
                var info = AppInfo.create_from_commandline (command, null, AppInfoCreateFlags.NEEDS_TERMINAL);
                info.launch (null, get_display ().get_app_launch_context ());
            } catch (Error e) {
                login_row.subtitle = _("Open a terminal and run %s once").printf (command);
            }
        }

        private async bool store_key (string p, string key) {
            try {
                var process = new Subprocess (SubprocessFlags.STDIN_PIPE | SubprocessFlags.STDERR_SILENCE, BINARY, "key", p);
                yield process.communicate_utf8_async (key, null, null, null);
                return process.get_successful ();
            } catch (Error e) {
                return false;
            }
        }

        public async void check () {
            string p = provider ();
            string m = model_row.visible ? model_row.text.strip () : "";
            if (m == "" && model_row.visible && p != "local") m = model_row.placeholder_text;
            if (key_row.visible) {
                string key = key_row.text.strip ();
                if (key == "") {
                    check_row.subtitle = _("Paste the API key first");
                    return;
                }
                if (!(yield store_key (p, key))) {
                    check_row.subtitle = _("The keyring refused the key");
                    return;
                }
            }
            running = new Cancellable ();
            var cancel = running;
            check_btn.sensitive = false;
            spinner.visible = true;
            spinner.spinning = true;
            check_row.subtitle = _("Waiting for the answer");
            string[] argv = { BINARY, "check", "--provider", p };
            if (m != "") {
                argv += "--model";
                argv += m;
            }
            bool ok = false;
            bool timed_out = false;
            string message = "";
            uint timer = Timeout.add_seconds (120, () => {
                timed_out = true;
                cancel.cancel ();
                return Source.REMOVE;
            });
            try {
                var process = new Subprocess.newv (argv, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
                string? out_text, err_text;
                yield process.communicate_utf8_async (null, cancel, out out_text, out err_text);
                ok = process.get_successful () && out_text != null && out_text.strip () != "";
                if (!ok) {
                    message = err_text != null ? err_text.strip () : "";
                    if (message.has_prefix ("sinty: ")) message = message.substring (7);
                }
            } catch (Error e) {
                message = timed_out ? _("No answer in two minutes") : e.message;
            }
            if (!timed_out) Source.remove (timer);
            spinner.spinning = false;
            spinner.visible = false;
            check_btn.sensitive = true;
            if (running == cancel) running = null;
            if (cancel.is_cancelled () && !timed_out) return;
            if (!ok) {
                check_row.subtitle = message != "" ? _("Not working: %s").printf (message) : _("Not working: no answer");
                return;
            }
            check_row.subtitle = _("Working: the model answered");
            verified = true;
            save (p, m);
            verified_changed ();
        }

        public void save (string p, string m) {
            var root = new Json.Object ();
            try {
                var parser = new Json.Parser ();
                parser.load_from_file (config_path ());
                if (parser.get_root () != null && parser.get_root ().get_node_type () == Json.NodeType.OBJECT) root = parser.get_root ().get_object ();
            } catch (Error e) {
            }
            root.set_string_member ("provider", p);
            root.set_string_member ("model", m);
            if (!root.has_member ("endpoint")) root.set_string_member ("endpoint", "");
            int mi = mode_row.selected_index;
            root.set_string_member ("mode", mi >= 0 && mi < MODES.length ? MODES[mi] : "ask");
            root.set_boolean_member ("voice", voice_row.switch_btn.active);
            root.set_boolean_member ("background", background_row.switch_btn.active);
            var node = new Json.Node (Json.NodeType.OBJECT);
            node.set_object (root);
            var gen = new Json.Generator ();
            gen.set_root (node);
            gen.pretty = true;
            DirUtils.create_with_parents (Path.get_dirname (config_path ()), 0700);
            try {
                FileUtils.set_contents (config_path (), gen.to_data (null));
            } catch (Error e) {
                check_row.subtitle = _("Working, but the settings could not be saved: %s").printf (e.message);
            }
        }

        public void commit () {
            if (!verified) return;
            string p = provider ();
            string m = model_row.visible ? model_row.text.strip () : "";
            if (m == "" && model_row.visible && p != "local") m = model_row.placeholder_text;
            save (p, m);
        }
    }
}
