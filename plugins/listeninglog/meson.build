# Copied next to the .plugin in the build tree too, so it runs from there
foreach f : ['listeninglog.plugin', 'listeninglog.py']
  configure_file(input: f, output: f, copy: true,
    install: true, install_dir: prefix / plugin_subdir / 'listeninglog')
endforeach
