# Built by packaging/build-rpm.sh, which passes the version as bb_version
Name:           beatbox
Version:        %{bb_version}
Release:        1%{?dist}
Summary:        Music player with Cover Flow, podcasts and internet radio
License:        GPL-3.0-or-later
URL:            https://github.com/lchongv/beatbox
Source0:        beatbox-%{version}.tar.gz

BuildRequires:  meson
BuildRequires:  vala
BuildRequires:  gcc
BuildRequires:  gettext
BuildRequires:  patchelf
BuildRequires:  pkgconfig(gtk+-3.0)
BuildRequires:  pkgconfig(gee-0.8)
BuildRequires:  pkgconfig(taglib_c)
BuildRequires:  pkgconfig(libxml-2.0)
BuildRequires:  pkgconfig(libnotify)
BuildRequires:  pkgconfig(libsoup-3.0)
BuildRequires:  pkgconfig(json-glib-1.0)
BuildRequires:  pkgconfig(sqlite3)
BuildRequires:  pkgconfig(libgpod-1.0)
BuildRequires:  pkgconfig(gstreamer-1.0)
BuildRequires:  pkgconfig(gstreamer-pbutils-1.0)
BuildRequires:  pkgconfig(gstreamer-video-1.0)
BuildRequires:  pkgconfig(gstreamer-tag-1.0)
Requires:       gstreamer1-plugins-base
Requires:       gstreamer1-plugins-good
Requires:       glib-networking
Requires:       hicolor-icon-theme

%description
BeatBox is a music player for GTK: a library with smart playlists, Cover Flow
and an inline cover grid, synced lyrics, podcasts, internet radio, Last.fm and
ListenBrainz scrobbling, and iPod sync.

%prep
%autosetup

%build
%meson
%meson_build

%install
%meson_install
# meson's install RPATH is the standard library directory, which Fedora rejects
patchelf --remove-rpath %{buildroot}%{_bindir}/beatbox
%find_lang beatbox

%check
%meson_test

%files -f beatbox.lang
%license COPYING
%doc README AUTHORS
%{_bindir}/beatbox
%{_libdir}/libbeatbox-core.so
%{_datadir}/applications/net.launchpad.beatbox.desktop
%{_datadir}/icons/hicolor/*/apps/beatbox.svg
%{_metainfodir}/net.launchpad.beatbox.metainfo.xml
