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
    if [ "$(echo *.iso)" != "*.iso" ]; then
	echo "FIXME: todo"
	exit 1
    fi

    cat > iso-slim/Dockerfile <<EOF
FROM scratch
ADD rootfs.tar /
EOF
    docker build -t $repo:$version-iso-slim iso-slim

    for tag in $tags; do
	echo $tag
    done
done
