Name:       hesper-remote-engine
Version:    1.1.9
Release:    0
Summary:    Hesper Remote Engine
License:    GPL-3.0
Requires:   gtk3 libxcb1 libXfixes3 alsa-utils libXtst6 libva2 pam gstreamer-plugins-base gstreamer-plugin-pipewire
Recommends: libayatana-appindicator3-1 xdotool
Conflicts:  rustdesk, hesper-remote

# https://docs.fedoraproject.org/en-US/packaging-guidelines/Scriptlets/

%description
Hesper Remote - secure remote desktop and support engine.

%prep
# we have no source, so nothing here

%build
# we have no source, so nothing here

%global __python %{__python3}

%install
mkdir -p %{buildroot}/usr/bin/
mkdir -p %{buildroot}/usr/share/hesper-remote-engine/
mkdir -p %{buildroot}/usr/share/hesper-remote-engine/files/
mkdir -p %{buildroot}/usr/share/icons/hicolor/256x256/apps/
mkdir -p %{buildroot}/usr/share/icons/hicolor/scalable/apps/
install -m 755 $HBB/target/release/rustdesk %{buildroot}/usr/bin/hesper-remote-engine
install $HBB/libsciter-gtk.so %{buildroot}/usr/share/hesper-remote-engine/libsciter-gtk.so
install $HBB/res/hesper-remote-engine.service %{buildroot}/usr/share/hesper-remote-engine/files/
install $HBB/res/128x128@2x.png %{buildroot}/usr/share/icons/hicolor/256x256/apps/hesper-remote-engine.png
install $HBB/res/scalable.svg %{buildroot}/usr/share/icons/hicolor/scalable/apps/hesper-remote-engine.svg
install $HBB/res/hesper-remote-engine.desktop %{buildroot}/usr/share/hesper-remote-engine/files/
install $HBB/res/hesper-remote-engine-link.desktop %{buildroot}/usr/share/hesper-remote-engine/files/

%files
/usr/bin/hesper-remote-engine
/usr/share/hesper-remote-engine/libsciter-gtk.so
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
    rm /usr/share/applications/hesper-remote-engine.desktop || true
    rm /usr/share/applications/hesper-remote-engine-link.desktop || true
    update-desktop-database
  ;;
  1)
    # for upgrade
  ;;
esac
