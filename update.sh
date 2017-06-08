#!/bin/bash
set -e

cd "$(readlink -f "$(dirname "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
    versions=( */ )
fi

get_part() {
    dir="$1"
    shift
    part="$1"
    shift
    if [ -f "$dir/$part" ]; then
	cat "$dir/$part"
	return 0
	fi
    if [ -f "$part" ]; then
	cat "$part"
	return 0
	fi
    if [ $# -gt 0 ]; then
	echo "$1"
	return 0
	fi
    return 1
}

repo="$(get_part . repo)"

for version in "${versions[@]}"; do
    version="${version%/}"
    dir="$(readlink -f "$version")"
    url="$(get_part "$dir" url)"
    tags="$(get_part "$dir" tags)"
    centos_version="$(get_part "$dir" version)"
    arch="$(get_part "$dir" arch)"
    qemu_arch="$(get_part "$dir" qemu_arch "")"
    scw_arch="$(get_part "$dir" scw_arch "$arch")"
    cd "$dir"

    # fetch image
    wget -N $url

    mkdir -p iso-slim

    # create rootfs.tar
    if [ "$(echo *.img.xz)" != "*.img.xz" ]; then
	imgxzfilename="$(echo *.img.xz)"
	imgfilename="${imgxzfilename%.xz}"

	if [ ! -f "${imgfilename}" ]; then
	    cat "${imgxzfilename}" | unxz > "${imgfilename}"
	fi
	if [ ! -f iso-slim/rootfs.tar ]; then
	    virt-tar-out -a "${imgfilename}" / - > iso-slim/rootfs.tar
	fi
    fi
    if [ "$(echo *.qcow2)" != "*.qcow2" ]; then
	qcow2filename="$(echo *.qcow2)"
	if [ ! -f iso-slim/rootfs.tar ]; then
	    virt-tar-out -a "${qcow2filename}" / - > iso-slim/rootfs.tar
	fi
    fi
    if [ "$(echo *.iso)" != "*.iso" ]; then
	isofilename="$(echo *.iso)"
	if [ ! -f iso-slim/rootfs.tar ]; then
	    virt-tar-out -a "${isofilename}" / - > iso-slim/rootfs.tar
	fi
    fi

    # create iso-slim dockerfile
    cat > iso-slim/Dockerfile <<EOF
FROM scratch
ADD rootfs.tar /
ENV ARCH=${scw_arch} CENTOS_VERSION=${centos_version} DOCKER_REPO=${repo} CENTOS_IMAGE_URL=${url} QEMU_ARCH=${qemu_arch}

EOF

    ## build iso-slim image
    docker build -t $repo:$version-iso-slim iso-slim
    for tag in $tags; do
    	docker tag $repo:$version-iso-slim $repo:$tag-iso-slim
    done

    # create iso dockerfile
    mkdir -p iso
    if [ -n "${qemu_arch}" -a ! -f "iso/qemu-${qemu_arch}-static" ]; then
	wget https://github.com/multiarch/qemu-user-static/releases/download/v2.8.0/qemu-${qemu_arch}-static -O "iso/qemu-${qemu_arch}-static"
	chmod +x "iso/qemu-${qemu_arch}-static"
    fi
    if [ -n "${qemu_arch}" ]; then
	cat > iso/Dockerfile <<EOF
FROM $repo:$version-iso-slim
ADD qemu-${qemu_arch}-static /usr/bin
EOF
    else
	cat > iso/Dockerfile <<EOF
FROM $repo:$version-iso-slim
EOF
    fi
    docker build -t $repo:$version-iso iso
    for tag in $tags; do
	docker tag $repo:$version-iso $repo:$tag-iso
    done

    docker run -it --rm $repo:$version-iso uname -a

    # build iso-cleanup image
    mkdir -p iso-clean
    cat > iso-clean/Dockerfile <<EOF
FROM $repo:$version-iso
RUN yum remove -y \
      kernel-* *-firmware grub* centos-logos mariadb*       \
      postfix btrfs* mozjs17 xfsprogs cloud-init pciutils*  \
      libsoup* libgudev* python-prettytable                 \
      python-setuptools python-boto yum-utils               \
      libsysfs* glib-networking libproxy plymouth*          \
      libdrm wpa_supplicant *-desktop-*                     \
      perl gcc cpp doxygen emacs-nox || true
RUN rm -rf /boot
EOF
    docker build -t tmp-$repo:$version-iso-cleaner iso-clean
    tmpname=export-$(openssl rand -base64 10 | sed 's@[=/]@@g')
    docker run --name="$tmpname" --entrypoint=/does/not/exist tmp-$repo:$version-iso-cleaner 2>/dev/null || true
    docker export "$tmpname" | \
	docker import \
	       -c "ENV ARCH=${scw_arch} CENTOS_VERSION=${centos_version} DOCKER_REPO=${repo} CENTOS_IMAGE_URL=${url} QEMU_ARCH=${qemu_arch}" \
	       - "$repo:$version-clean"
    docker rm "$tmpname"
    for tag in $tags; do
	docker tag $repo:$version-clean $repo:$tag-clean
    done
    docker run -it --rm $repo:$version-clean uname -a
done
