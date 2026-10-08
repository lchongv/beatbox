shared_module('statistics', 'Statistics.vala',
  dependencies: core_dep,
  install: true,
  install_dir: prefix / plugin_subdir / 'statistics')
# next to the library in the build tree too, so it runs from there
configure_file(input: 'statistics.plugin', output: 'statistics.plugin', copy: true,
  install: true, install_dir: prefix / plugin_subdir / 'statistics')
