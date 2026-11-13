Name:       hesper-remote-engine
Version:    1.4.8
Release:    0
Summary:    Hesper Remote Engine
License:    AGPL-3.0
URL:        https://hesperitsm.com
Vendor:     Arke Technologies <support@hesperitsm.com>
Requires:   gtk3 libxcb1 libXfixes3 alsa-utils libXtst6 libva2 pam gstreamer-plugins-base gstreamer-plugin-pipewire
Recommends: libayatana-appindicator3-1 xdotool
Provides:   libdesktop_drop_plugin.so()(64bit), libdesktop_multi_window_plugin.so()(64bit), libfile_selector_linux_plugin.so()(64bit), libflutter_custom_cursor_plugin.so()(64bit), libflutter_linux_gtk.so()(64bit), libscreen_retriever_plugin.so()(64bit), libtray_manager_plugin.so()(64bit), liburl_launcher_linux_plugin.so()(64bit), libwindow_manager_plugin.so()(64bit), libwindow_size_plugin.so()(64bit), libtexture_rgba_renderer_plugin.so()(64bit)
Conflicts:  rustdesk, hesper-remote

# https://docs.fedoraproject.org/en-US/packaging-guidelines/Scriptlets/

%description
Hesper Remote - secure remote desktop and support engine.

%prep
# we have no source, so nothing here

%build
# we have no source, so nothing here

# %global __python %{__python3}

%install

mkdir -p "%{buildroot}/usr/share/hesper-remote-engine" && cp -r ${HBB}/flutter/build/linux/x64/release/bundle/* -t "%{buildroot}/usr/share/hesper-remote-engine"
mkdir -p "%{buildroot}/usr/bin"
install -Dm 644 $HBB/res/hesper-remote-engine.service -t "%{buildroot}/usr/share/hesper-remote-engine/files"
install -Dm 644 $HBB/res/hesper-remote-engine.desktop -t "%{buildroot}/usr/share/hesper-remote-engine/files"
install -Dm 644 $HBB/res/hesper-remote-engine-link.desktop -t "%{buildroot}/usr/share/hesper-remote-engine/files"
install -Dm 644 $HBB/res/128x128@2x.png "%{buildroot}/usr/share/icons/hicolor/256x256/apps/hesper-remote-engine.png"
install -Dm 644 $HBB/res/scalable.svg "%{buildroot}/usr/share/icons/hicolor/scalable/apps/hesper-remote-engine.svg"

%files
/usr/share/hesper-remote-engine/*
/usr/share/hesper-remote-engine/files/hesper-remote-engine.service
/usr/share/icons/hicolor/256x256/apps/hesper-remote-engine.png
/usr/share/icons/hicolor/scalable/apps/hesper-remote-engine.svg
/usr/share/hesper-remote-engine/files/hesper-remote-engine.desktop
/usr/share/hesper-remote-engine/files/hesper-remote-engine-link.desktop

%changelog
# let's skip this for now

%pre
# can do something for centos7
case "$1" in
  1)
    # for install
  ;;
  2)
    # for upgrade
    systemctl stop hesper-remote-engine || true
  ;;
esac

%post
cp /usr/share/hesper-remote-engine/files/hesper-remote-engine.service /etc/systemd/system/hesper-remote-engine.service
cp /usr/share/hesper-remote-engine/files/hesper-remote-engine.desktop /usr/share/applications/
cp /usr/share/hesper-remote-engine/files/hesper-remote-engine-link.desktop /usr/share/applications/
ln -sf /usr/share/hesper-remote-engine/hesper-remote-engine /usr/bin/hesper-remote-engine
systemctl daemon-reload
systemctl enable hesper-remote-engine
systemctl start hesper-remote-engine
update-desktop-database

%preun
case "$1" in
  0)
    # for uninstall
    systemctl stop hesper-remote-engine || true
    systemctl disable hesper-remote-engine || true
    rm /etc/systemd/system/hesper-remote-engine.service || true
  ;;
  1)
    # for upgrade
  ;;
esac

%postun
case "$1" in
  0)
    # for uninstall
    rm /usr/bin/hesper-remote-engine || true
    rmdir /usr/lib/hesper-remote-engine || true
    rmdir /usr/local/hesper-remote-engine || true
    rmdir /usr/share/hesper-remote-engine || true
    rm /usr/share/applications/hesper-remote-engine.desktop || true
    rm /usr/share/applications/hesper-remote-engine-link.desktop || true
    update-desktop-database
  ;;
  1)
    # for upgrade
    rmdir /usr/lib/hesper-remote-engine || true
    rmdir /usr/local/hesper-remote-engine || true
  ;;
esac
