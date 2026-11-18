%global selinuxtype targeted
%global selinux_policyver 3.14.3-22
%global modulename python3-validity
%global pypi_name validity
%global commit 960b44bda3781b317272211e73856b5a9b0fb0e4

Name:           python-%{pypi_name}
Version:        0.15
Release:        1%{?dist}.local3
Summary:        Validity fingerprint sensor driver (pinned T480 fork)
License:        MIT
URL:            https://github.com/jon-mun/python-validity
Source0:        https://github.com/jon-mun/python-validity/archive/%{commit}.tar.gz
# Retain the existing Copr unit; do not enable competing resume workarounds.
Source1:        python3-validity-restart-after-resume.service
BuildArch:      noarch

Requires:       selinux-policy >= %{selinux_policyver}
Requires(post): selinux-policy-base >= %{selinux_policyver}
BuildRequires:  selinux-policy
BuildRequires:  selinux-policy-devel
BuildRequires:  selinux-policy-%{selinuxtype}
BuildRequires:  systemd-rpm-macros

%description
Pinned jon-mun T480 fork with upstream PR 290 recovery and persistent calibration.
Local Fedora 45 trial; no fingerprint reset or enrollment migration is performed
by this package. Existing host calibration must be preserved before installation.

%package -n python3-%{pypi_name}
Summary:        %{summary}
BuildRequires:  python3-devel
BuildRequires:  python3-setuptools
BuildRequires:  python3-pytest
BuildRequires:  python3-cryptography
BuildRequires:  python3-pyusb
BuildRequires:  policycoreutils
BuildRequires:  checkpolicy
BuildRequires:  bzip2
Requires:       policycoreutils
Requires:       innoextract
Requires:       open-fprintd

%description -n python3-%{pypi_name}
Validity fingerprint driver, pinned at %{commit} for a Fedora 45 T480 trial.

%prep
%autosetup -n %{name}-%{commit}

%build
%py3_build
cd selinux
checkmodule -M -m -o python3-validity.mod python3-validity.te
semodule_package -o python3-validity.pp -m python3-validity.mod
bzip2 python3-validity.pp

%pre
%selinux_relabel_pre -s %{selinuxtype}

%install
%py3_install
install -d -m 0700 %{buildroot}%{_sysconfdir}/python-validity
install -d -m 0700 %{buildroot}%{_localstatedir}/lib/python-validity
install -d -m 0755 %{buildroot}%{_unitdir}
install -d -m 0755 %{buildroot}%{_prefix}/lib/udev/rules.d
install -d -m 0755 %{buildroot}%{_datadir}/selinux/packages
install -m 0600 etc/python-validity/dbus-service.yaml %{buildroot}%{_sysconfdir}/python-validity/
install -m 0644 debian/python3-validity.service %{buildroot}%{_unitdir}/
install -m 0644 %{SOURCE1} %{buildroot}%{_unitdir}/
install -m 0644 debian/python3-validity.udev %{buildroot}%{_prefix}/lib/udev/rules.d/40-python3-validity.udev
install -m 0644 selinux/python3-validity.pp.bz2 %{buildroot}%{_datadir}/selinux/packages/

%check
%{__python3} -m pytest -q

%post -n python3-%{pypi_name}
%selinux_modules_install -s %{selinuxtype} %{_datadir}/selinux/packages/%{modulename}.pp.bz2
# Do not replace a migrated T480 firmware file or download it on every upgrade.
if [ ! -s %{_localstatedir}/lib/python-validity/6_07f_lenovo_mis_qm.xpfwext ]; then
    validity-sensors-firmware || true
fi
systemctl daemon-reload
udevadm control --reload-rules
udevadm trigger
%systemd_post python3-validity.service python3-validity-restart-after-resume.service

%preun -n python3-%{pypi_name}
%systemd_preun python3-validity.service python3-validity-restart-after-resume.service

%postun -n python3-%{pypi_name}
%systemd_postun_with_restart python3-validity.service python3-validity-restart-after-resume.service
if [ $1 -eq 0 ]; then
    %selinux_modules_uninstall -s %{selinuxtype} %{modulename}
fi

%posttrans
%selinux_relabel_post -s %{selinuxtype}

%files -n python3-%{pypi_name}
%doc README.md
%license LICENSE
%config(noreplace) %{_sysconfdir}/python-validity/dbus-service.yaml
%dir %attr(0700,root,root) %{_localstatedir}/lib/python-validity
%{_unitdir}/python3-validity.service
%{_unitdir}/python3-validity-restart-after-resume.service
%{_prefix}/lib/udev/rules.d/40-python3-validity.udev
%{python3_sitelib}/validitysensor/
%{python3_sitelib}/python_%{pypi_name}-%{version}-py*.egg-info/
%{_bindir}/validity-led-dance
%{_bindir}/validity-sensors-firmware
%{_prefix}/lib/%{name}/dbus-service
%{_datadir}/dbus-1/system.d/io.github.uunicorn.Fprint.conf
%{_datadir}/%{name}/
%{_datadir}/selinux/packages/python3-validity.pp.bz2

%changelog
* Tue Nov 17 2026 Local rebuild - 0.15-1.fc45.local3
- Test pinned jon-mun T480 fork 960b44b with PR 290 and persistent calibration.
- Keep bounded upstream restarts; do not apply the Copr restart-always patch.
- Run the fork's tests; retain cached T480 firmware during upgrades.
