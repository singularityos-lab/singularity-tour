project('singularity-tour', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

i18n = import('i18n')
add_project_arguments('-DGETTEXT_PACKAGE="singularity-tour"', language: 'c')
subdir('po')

gtk_dep   = dependency('gtk4')
gee_dep   = dependency('gee-0.8')
pangocairo_dep = dependency('pangocairo')

libsingularity_dep = dependency('singularity-1.0',
  fallback: ['libsingularity', 'libsingularity_dep']
)

if not meson.is_subproject() and libsingularity_dep.type_name() == 'internal'
  libsingularity_vapi_dir = join_paths(meson.project_build_root(), 'subprojects', 'libsingularity')
  add_project_arguments(['--vapidir=' + libsingularity_vapi_dir], language: 'vala')
endif

gnome = import('gnome')

resources = gnome.compile_resources(
  'singularity-tour-resources',
  'resources/dev.sinty.tour.gresource.xml',
  source_dir: meson.current_source_dir() / 'data',
)

executable('singularity-tour',
  files('src/slides.vala', 'src/scene.vala', 'src/agent_setup.vala', 'src/window.vala', 'src/app.vala') + [resources],
  dependencies: [gtk_dep, gee_dep, pangocairo_dep, dependency('gio-unix-2.0'), dependency('json-glib-1.0'), libsingularity_dep, meson.get_compiler('c').find_library('m')],
  install: true
)

shared_module('singularity-tour-widget',
  files('widget/tip_widget.vala'),
  dependencies: [gtk_dep, gee_dep, dependency('gio-unix-2.0'), libsingularity_dep],
  install: true,
  install_dir: get_option('libdir') / 'singularity' / 'widgets'
)

install_data('widget/dev.sinty.tour.tip-of-the-day.widget',
  install_dir: get_option('datadir') / 'singularity' / 'widgets'
)

slides_test = executable('tour-test',
  files('src/slides.vala', 'tests/slides_test.vala'),
  dependencies: [gee_dep, dependency('gio-2.0')],
)
test('tour', slides_test,
  env: ['TOUR_FIXTURES=' + meson.current_source_dir() / 'tests' / 'fixtures',
        'TOUR_SLIDES=' + meson.current_source_dir() / 'data' / 'slides']
)

install_subdir('data/slides',
  install_dir: get_option('datadir') / 'singularity' / 'tour',
  strip_directory: true
)

install_data('data/dev.sinty.tour.desktop',
  install_dir: get_option('datadir') / 'applications'
)

install_data('data/icons/dev.sinty.tour.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)
