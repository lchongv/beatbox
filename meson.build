project('beatbox', 'vala', 'c', version: '0.9.25')

gnome = import('gnome')
i18n = import('i18n')

prefix = get_option('prefix')
datadir = prefix / get_option('datadir')
pkgdatadir = datadir / meson.project_name()

conf = configuration_data()
conf.set('DATADIR', datadir)
conf.set('PKG_DATADIR', pkgdatadir)
conf.set('ICON_DIR', datadir / 'icons' / 'hicolor')
conf.set('SCHEMA_DIR', pkgdatadir / 'database')
conf.set('GETTEXT_PACKAGE', meson.project_name())
conf.set('RELEASE_NAME', 'Everlong')
conf.set('VERSION', meson.project_version())
conf.set('VERSION_INFO', 'Pre-Release')
conf.set('CMAKE_INSTALL_PREFIX', prefix)
config_vala = configure_file(input: 'config.vala.in', output: 'config.vala', configuration: conf)

add_project_arguments('-DGETTEXT_PACKAGE="beatbox"', '-w', language: 'c')
add_project_arguments('--vapidir=' + meson.current_source_dir() / 'vapi', '--target-glib=2.56', language: 'vala')

valac = meson.get_compiler('vala')
# iPod sync needs libgpod (meson setup -Dipod=disabled builds without it)
gpod_dep = dependency('libgpod-1.0', required: get_option('ipod'))
gpod_vala_args = gpod_dep.found() ? ['-D', 'HAVE_GPOD'] : []
taglib_dep = dependency('taglib_c')
deps = [
  dependency('glib-2.0'),
  dependency('gio-2.0'),
  dependency('gio-unix-2.0'),
  dependency('gtk+-3.0'),
  dependency('gdk-x11-3.0'),
  dependency('gee-0.8'),
  dependency('gstreamer-1.0'),
  dependency('gstreamer-pbutils-1.0'),
  dependency('gstreamer-video-1.0'),
  dependency('gstreamer-tag-1.0'),
  taglib_dep,
  dependency('libxml-2.0'),
  dependency('libnotify'),
  dependency('libsoup-3.0'),
  dependency('json-glib-1.0'),
  dependency('granite'),
  dependency('sqlite3'),
  gpod_dep,
  valac.find_library('posix'),
  meson.get_compiler('c').find_library('m'),
]

core_sources = files(
  'core/SQLHeavy.vala',
  'core/Settings.vala',
  'core/EqualizerPreset.vala',
  'core/SideTreeCategory.vala',
  'core/LibraryInterface.vala',
  'core/LibraryWindowInterface.vala',
  'core/ActionsInterface.vala',
  'core/FileInterface.vala',
  'core/OperationsInterface.vala',
  'core/CoverInterface.vala',
  'core/PlaybackInterface.vala',
  'core/IconsInterface.vala',
  'core/InfoInterface.vala',
  'core/DatabaseInterface.vala',
  'core/PlaylistInterface.vala',
  'core/DeviceInterface.vala',
  'core/PodcastInterface.vala',
  'core/LastFMInterface.vala',
  'core/Library.vala',
  'core/ListSetupInterface.vala',
  'core/MediaEditorInterface.vala',
  'core/TopDisplayInterface.vala',
  'core/NowPlayingViewInterface.vala',
  'core/CellRenderers/CellDataFunctionHelper.vala',
  'core/Devices/DevicePreferences.vala',
  'core/Devices/Device.vala',
  'core/Info/BasicInfo.vala',
  'core/Info/InfoURL.vala',
  'core/Info/TrackInfo.vala',
  'core/Info/AlbumInfo.vala',
  'core/Info/ArtistInfo.vala',
  'core/Info/InfoSource.vala',
  'core/Info/Lyrics.vala',
  'core/Info/LyricFetcher.vala',
  'core/Info/LyricsInterface.vala',
  'core/Utils/Icon.vala',
  'core/Utils/Http.vala',
  'core/Utils/UI.vala',
  'core/Utils/TimeUtils.vala',
  'core/Utils/String.vala',
  'core/Utils/Numeric.vala',
  'core/Utils/ListUtils.vala',
  'core/Utils/Shortcuts.vala',
  'core/Operations/Operation.vala',
  'core/Operations/FilesOperation.vala',
  'core/Operations/PlaylistOperation.vala',
  'core/Operations/ParseRssOperation.vala',
  'core/Operations/MediasOperation.vala',
  'core/Media/Media.vala',
  'core/Media/Preview.vala',
  'core/Media/Album.vala',
  'core/Media/ExternalAlbum.vala',
  'core/Media/Artist.vala',
  'core/Media/Genre.vala',
  'core/Playlists/BasePlaylist.vala',
  'core/Playlists/StaticPlaylist.vala',
  'core/Playlists/SmartQuery.vala',
  'core/Playlists/SmartPlaylist.vala',
  'core/Preferences/PreferencesSection.vala',
  'core/Views/View.vala',
  'core/Views/TreeViewSetup.vala',
  'core/Views/StyledContentBox.vala',
  'core/Grids/FastGrid.vala',
  'core/Grids/FastGridModel.vala',
  'core/Lists/FastList.vala',
  'core/Lists/FastListModel.vala',
  'core/Lists/MusicColumn.vala',
  'core/Lists/PodcastColumn.vala',
  'core/Lists/RadioColumn.vala',
  'core/Lists/DuplicateColumn.vala',
  'core/TopDisplay/Display.vala',
  'core/Widgets/FieldEditor.vala',
  'core/Widgets/NavigationArrows.vala',
  'core/Widgets/StyledBox.vala',
)

core = shared_library('beatbox-core', core_sources, config_vala,
  dependencies: deps,
  vala_args: gpod_vala_args,
  vala_header: 'beatbox-core.h',
  vala_vapi: 'beatbox-core.vapi',
  install: true)
core_dep = declare_dependency(link_with: core, dependencies: deps, include_directories: include_directories('.'))

app_sources = files(
  'src/BeatBox.vala',
  'src/Core/Icons.vala',
  'src/Core/Actions.vala',
  'src/Core/LibraryWindow.vala',
  'src/Core/LibraryManager.vala',
  'src/Core/FileOperator.vala',
  'src/Core/PodcastManager.vala',
  'src/Core/PlaybackManager.vala',
  'src/Core/OperationsManager.vala',
  'src/Core/CoverManager.vala',
  'src/Core/Info.vala',
  'src/Core/PlaylistManager.vala',
  'src/Core/ListSetupManager.vala',
  'src/Core/LyricsManager.vala',
  'src/Core/Skins.vala',
  'src/Core/FolderWatcher.vala',
  'src/Core/CoverEmbedder.vala',
  'src/Core/Launcher.vala',
  'src/CellRenderers/SideBarRenderer.vala',
  'src/DataBase/DataBaseManager.vala',
  'src/DBus/MediaKeyListener.vala',
  'src/DBus/UnityIntegration.vala',
  'src/DBus/MPRIS/MPRIS.vala',
  'src/DBus/MPRIS/SoundMenuIntegration.vala',
  'src/Devices/DeviceManager.vala',
  'src/Devices/AndroidDevice.vala',
  'src/Devices/CDRomDevice.vala',
  'src/Dialogs/InstallGstreamerPluginsDialog.vala',
  'src/Dialogs/FileNotFoundDialog.vala',
  'src/Dialogs/RemoveFilesDialog.vala',
  'src/Dialogs/NotImportedDialog.vala',
  'src/Dialogs/SetLibraryFolderConfirmation.vala',
  'src/Dialogs/TransferFromDeviceDialog.vala',
  'src/Dialogs/SyncWarningDialog.vala',
  'src/Grids/GenericGrid.vala',
  'src/Grids/AlbumGrid.vala',
  'src/Grids/ExternalAlbumGrid.vala',
  'src/GStreamer/CDDA.vala',
  'src/GStreamer/Video.vala',
  'src/GStreamer/Equalizer.vala',
  'src/GStreamer/Pipeline.vala',
  'src/GStreamer/CDRipper.vala',
  'src/GStreamer/GStreamerTagger.vala',
  'src/GStreamer/ReplayGain.vala',
  'src/GStreamer/Streamer.vala',
  'src/Lastfm/LastFM.vala',
  'src/Lastfm/ListenBrainz.vala',
  'src/Lastfm/SimilarMedia.vala',
  'src/Lastfm/TopArtistSongs.vala',
  'src/Lastfm/TopArtistAlbums.vala',
  'src/Libraries/BaseLibrary.vala',
  'src/Libraries/SongLibrary.vala',
  'src/Libraries/PodcastLibrary.vala',
  'src/Libraries/StationLibrary.vala',
  'src/Lists/GenericList.vala',
  'src/Lists/MusicList.vala',
  'src/Lists/PodcastList.vala',
  'src/Lists/RadioList.vala',
  'src/Lists/DuplicateList.vala',
  'src/Media/Song.vala',
  'src/Media/Podcast.vala',
  'src/Media/Station.vala',
  'src/NowPlayingView/NowPlayingView.vala',
  'src/NowPlayingView/NowPlayingPage.vala',
  'src/NowPlayingView/SongSummarySection.vala',
  'src/NowPlayingView/PodcastSummarySection.vala',
  'src/Preferences/BehaviorPreferences.vala',
  'src/Preferences/ShortcutsPreferences.vala',
  'src/Preferences/LastfmPreferences.vala',
  'src/Preferences/MusicPreferences.vala',
  'src/Preferences/PodcastPreferences.vala',
  'src/SourceViews/SourceView.vala',
  'src/SourceViews/DefaultSourceView.vala',
  'src/SourceViews/MusicSourceView.vala',
  'src/SourceViews/PodcastSourceView.vala',
  'src/SourceViews/StationSourceView.vala',
  'src/SourceViews/DeviceSourceView.vala',
  'src/SourceViews/SimilarSourceView.vala',
  'src/SourceViews/DuplicateSourceView.vala',
  'src/SourceViews/QueueSourceView.vala',
  'src/SourceViews/HistorySourceView.vala',
  'src/SourceViews/SmartPlaylistSourceView.vala',
  'src/SourceViews/PlaylistSourceView.vala',
  'src/Utils/PixbufUtils.vala',
  'src/Utils/PlaylistUtils.vala',
  'src/Views/DeviceView.vala',
  'src/Views/DeviceSummaryWidget.vala',
  'src/Views/SideTreeView.vala',
  'src/Views/PopupListView.vala',
  'src/Widgets/PresetList.vala',
  'src/Widgets/SideBar.vala',
  'src/Widgets/RatingWidget.vala',
  'src/Widgets/SpaceWidget.vala',
  'src/Widgets/StatusBar.vala',
  'src/Widgets/CoverFlow.vala',
  'src/Widgets/AlbumWall.vala',
  'src/Widgets/AdvancedSearchBox.vala',
  'src/Widgets/SourceViewSearchSuggestions.vala',
  'src/Widgets/SimpleOptionChooser.vala',
  'src/Widgets/VolumeWidget.vala',
  'src/Widgets/EmbeddedAlert.vala',
  'src/Widgets/TopDisplay/TopDisplay.vala',
  'src/Widgets/TopDisplay/LcdCover.vala',
  'src/Widgets/TopDisplay/TimeScale.vala',
  'src/Widgets/TopDisplay/MetadataDisplay.vala',
  'src/Widgets/TopDisplay/SyncedLyrics.vala',
  'src/Widgets/TopDisplay/BufferDisplay.vala',
  'src/Widgets/TopDisplay/OperationDisplay.vala',
  'src/Windows/Editors/FieldEditorImpl.vala',
  'src/Windows/Editors/SmartPlaylistEditor.vala',
  'src/Windows/Editors/MediaEditor.vala',
  'src/Windows/Editors/SongEditor.vala',
  'src/Windows/Editors/PodcastEditor.vala',
  'src/Windows/Editors/StationEditor.vala',
  'src/Windows/Editors/InfoViewport.vala',
  'src/Windows/EqualizerWindow.vala',
  'src/Windows/PreferencesWindow.vala',
  'src/Windows/PlaylistNameWindow.vala',
  'src/Windows/AddPodcastWindow.vala',
  'src/Windows/DirectoryDialog.vala',
  'src/Windows/RemoveDuplicatesDialog.vala',
)

resources = gnome.compile_resources('beatbox-resources', 'data/beatbox.gresource.xml', source_dir: 'data')
icon_resources = gnome.compile_resources('beatbox-icons', 'images/icons.gresource.xml', source_dir: 'images')
skin_resources = gnome.compile_resources('beatbox-skins', 'skins/skins.gresource.xml', source_dir: 'skins')

# Writing album art into files needs TagLib's complex properties (TagLib 2.0)
embed_cover_sources = []
app_vala_args = gpod_vala_args
if gpod_dep.found()
  app_sources += files('src/Devices/iPodDevice.vala')
endif
if taglib_dep.version().version_compare('>= 2.0')
  embed_cover_sources = files('src/C/embed-cover.c')
  app_vala_args += ['-D', 'HAVE_EMBED_COVER']
endif

executable('beatbox', app_sources, embed_cover_sources, resources, icon_resources, skin_resources,
  dependencies: core_dep,
  vala_args: app_vala_args,
  install_rpath: prefix / get_option('libdir'),
  export_dynamic: true,
  install: true)

# Only the application icon goes into the icon theme: the others are built into the
# program (GResource), and generic names in hicolor would cover other applications' icons
foreach size : ['16x16', '22x22', '24x24', '32x32', '48x48', '64x64', '128x128']
  install_data('images/icons' / size / 'apps' / 'beatbox.svg', install_dir: datadir / 'icons' / 'hicolor' / size / 'apps')
endforeach
# Wayland shells match the window to <application id>.desktop
install_data('data/beatbox.desktop', install_dir: datadir / 'applications', rename: 'net.launchpad.beatbox.desktop')
install_data('data/net.launchpad.beatbox.metainfo.xml', install_dir: datadir / 'metainfo')
gnome.post_install(gtk_update_icon_cache: true)
subdir('po')

test('ellipsize', executable('test-ellipsize', 'tests/ellipsize.vala', dependencies: core_dep))
test('list-utils', executable('test-list-utils', 'tests/list-utils.vala', dependencies: core_dep))
test('shortcuts', executable('test-shortcuts', 'tests/shortcuts.vala', dependencies: core_dep))
test('http-json', executable('test-http-json', 'tests/http-json.vala', dependencies: core_dep))
