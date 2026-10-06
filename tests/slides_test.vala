using Singularity.Apps.Tour;

string fx (string name) {
    return Path.build_filename (Environment.get_variable ("TOUR_FIXTURES"), name);
}

void test_deck () {
    var slides = SlideDeck.load ({ fx ("etc"), fx ("share") });
    assert (slides.size == 3);
    assert (slides[0].id == "10-welcome" && slides[1].id == "25-distro" && slides[2].id == "30-store");
    assert (slides[0].body == "Running on %s.".printf (Slide.os_name ()));
    assert (slides[1].image == Path.build_filename (fx ("etc"), "repos.png"));
    assert (slides[1].action == "https://example.org" && slides[1].action_label == "Learn More");
    assert (slides[2].action == "");
}

void test_shipped () {
    string[] scenes = { "welcome", "top-bar", "launcher", "dock", "windows", "workspaces", "store", "settings", "help", "done" };
    var slides = SlideDeck.load ({ Environment.get_variable ("TOUR_SLIDES") });
    assert (slides.size == scenes.length);
    for (int i = 0; i < slides.size; i++) {
        assert (slides[i].scene == scenes[i]);
        assert (slides[i].title != "" && slides[i].body != "");
        assert (!slides[i].body.contains ("{"));
    }
    assert (slides[slides.size - 1].order > 900);
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/tour/deck", test_deck);
    Test.add_func ("/tour/shipped", test_shipped);
    return Test.run ();
}
