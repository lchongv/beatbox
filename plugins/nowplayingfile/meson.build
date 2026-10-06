shared_module('nowplayingfile', 'NowPlayingFile.vala',
  dependencies: core_dep,
  install: true,
  install_dir: prefix / plugin_subdir / 'nowplayingfile')
# next to the library in the build tree too, so it runs from there
configure_file(input: 'nowplayingfile.plugin', output: 'nowplayingfile.plugin', copy: true,
  install: true, install_dir: prefix / plugin_subdir / 'nowplayingfile')
