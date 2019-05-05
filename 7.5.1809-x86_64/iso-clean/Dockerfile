FROM multiarch/centos:7.5.1809-x86_64-iso
RUN yum remove -y       kernel-* *-firmware grub* centos-logos mariadb*             postfix btrfs* mozjs17 xfsprogs cloud-init pciutils*        libsoup* libgudev* python-prettytable                       python-setuptools python-boto yum-utils                     libsysfs* glib-networking libproxy plymouth*                libdrm wpa_supplicant *-desktop-*                           perl gcc cpp doxygen emacs-nox || true
RUN rm -rf /boot
