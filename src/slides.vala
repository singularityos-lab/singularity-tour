namespace Singularity.Apps.Tour {

    public class Slide : Object {
        public string id = "";
        public int order = 100;
        public string title = "";
        public string body = "";
        public string scene = "";
        public string image = "";
        public string icon = "";
        public string action = "";
        public string action_label = "";

        public static Slide? load (string path) {
            var kf = new KeyFile ();
            try {
                kf.load_from_file (path, KeyFileFlags.NONE);
            } catch (Error e) {
                return null;
            }
            return parse (kf, Path.get_basename (path), Path.get_dirname (path));
        }

        public static Slide? load_resource (string path) {
            var kf = new KeyFile ();
            try {
                var bytes = resources_lookup_data (path, ResourceLookupFlags.NONE);
                kf.load_from_bytes (bytes, KeyFileFlags.NONE);
            } catch (Error e) {
                return null;
            }
            return parse (kf, Path.get_basename (path), "");
        }

        private static Slide? parse (KeyFile kf, string name, string base_dir) {
            try {
                if (kf.has_key ("Slide", "Hidden") && kf.get_boolean ("Slide", "Hidden")) return null;
                var slide = new Slide ();
                slide.id = name.substring (0, name.length - ".slide".length);
                slide.title = expand (kf.get_locale_string ("Slide", "Title", null));
                if (kf.has_key ("Slide", "Body")) slide.body = expand (kf.get_locale_string ("Slide", "Body", null));
                if (kf.has_key ("Slide", "Order")) slide.order = kf.get_integer ("Slide", "Order");
                if (kf.has_key ("Slide", "Scene")) slide.scene = kf.get_string ("Slide", "Scene");
                if (kf.has_key ("Slide", "Icon")) slide.icon = kf.get_string ("Slide", "Icon");
                if (kf.has_key ("Slide", "Image")) {
                    string image = kf.get_locale_string ("Slide", "Image", null);
                    slide.image = Path.is_absolute (image) || base_dir == "" ? image : Path.build_filename (base_dir, image);
                }
                if (kf.has_key ("Slide", "Action")) slide.action = kf.get_string ("Slide", "Action");
                if (kf.has_key ("Slide", "ActionLabel")) slide.action_label = kf.get_locale_string ("Slide", "ActionLabel", null);
                if (slide.action == "" || slide.action_label == "") {
                    slide.action = "";
                    slide.action_label = "";
                }
                return slide;
            } catch (Error e) {
                return null;
            }
        }

        public static string os_name () {
            string? name = Environment.get_os_info (OsInfoKey.NAME);
            return name != null && name != "" ? name : "Linux";
        }

        private static string expand (string text) {
            return text.replace ("{os}", os_name ());
        }
    }

    public class SlideDeck : Object {
        private const string BUILTIN = "/dev/sinty/tour/slides/";

        public static string[] default_dirs () {
            string[] dirs = { Path.build_filename (Environment.get_user_config_dir (), "singularity", "tour") };
            foreach (string d in Environment.get_system_config_dirs ()) dirs += Path.build_filename (d, "singularity", "tour");
            dirs += Path.build_filename (Environment.get_user_data_dir (), "singularity", "tour");
            foreach (string d in Environment.get_system_data_dirs ()) dirs += Path.build_filename (d, "singularity", "tour");
            return dirs;
        }

        public static Gee.List<Slide> load (string[]? dirs = null) {
            var seen = new Gee.HashSet<string> ();
            var slides = new Gee.ArrayList<Slide> ();
            foreach (string dir in dirs ?? default_dirs ()) {
                string[] names = {};
                try {
                    var d = Dir.open (dir);
                    string? name;
                    while ((name = d.read_name ()) != null) {
                        if (name.has_suffix (".slide")) names += name;
                    }
                } catch (FileError e) {
                    continue;
                }
                foreach (string name in names) {
                    if (!seen.add (name)) continue;
                    var slide = Slide.load (Path.build_filename (dir, name));
                    if (slide != null) slides.add (slide);
                }
            }
            if (dirs == null) {
                try {
                    foreach (string name in resources_enumerate_children (BUILTIN, ResourceLookupFlags.NONE)) {
                        if (!name.has_suffix (".slide") || !seen.add (name)) continue;
                        var slide = Slide.load_resource (BUILTIN + name);
                        if (slide != null) slides.add (slide);
                    }
                } catch (Error e) {
                }
            }
            slides.sort ((a, b) => a.order != b.order ? a.order - b.order : strcmp (a.id, b.id));
            return slides;
        }
    }
}
