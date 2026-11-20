#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob

package_version=${PACKAGE_VERSION:-$(awk -F': ' '$1 == "Version" { print $2; exit }' control)}
source_deb_glob=${SOURCE_DEB_GLOB:-packages/*arm64e*.deb}
output_dir=${OUTPUT_DIR:-packages}
tweak_dylib_name=${TWEAK_DYLIB_NAME:-DYYY.dylib}
required_arch=${REQUIRED_ARCH:-arm64e}

if [[ -z "$package_version" ]]; then
    echo "Unable to read package version from control" >&2
    exit 1
fi

matching_debs=()
while IFS= read -r deb; do matching_debs+=("$deb"); done < <(compgen -G "$source_deb_glob" | sort)
if [[ "${#matching_debs[@]}" -ne 1 ]]; then
    echo "Expected exactly one arm64e Deb package, found ${#matching_debs[@]}:" >&2
    printf '  %s\n' "${matching_debs[@]}" >&2
    exit 1
fi

source_deb=${matching_debs[0]}
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$work_dir/data"
(cd "$work_dir" && ar -x "$GITHUB_WORKSPACE/$source_deb")
data_archives=("$work_dir"/data.tar.*)
if [[ "${#data_archives[@]}" -ne 1 ]]; then
    echo "Expected exactly one data.tar archive, found ${#data_archives[@]}" >&2
    exit 1
fi
tar -xf "${data_archives[0]}" -C "$work_dir/data"

dylib_paths=()
while IFS= read -r file; do dylib_paths+=("$file"); done < <(find "$work_dir/data" -type f -name "$tweak_dylib_name" | sort)
if [[ "${#dylib_paths[@]}" -ne 1 ]]; then
    echo "Expected exactly one $tweak_dylib_name in arm64e package, found ${#dylib_paths[@]}" >&2
    printf '  %s\n' "${dylib_paths[@]}" >&2
    exit 1
fi

mkdir -p "$output_dir"
output_file="$output_dir/DYYY_${package_version}.dylib"
cp "${dylib_paths[0]}" "$output_file"
lipo_info=$(lipo -info "$output_file")
echo "$lipo_info"
grep -Eq "(^|[^[:alnum:]_])${required_arch}([^[:alnum:]_]|$)" <<< "$lipo_info" || {
    echo "Extracted dylib does not contain required architecture: $required_arch" >&2
    exit 1
}
echo "Created $output_file"
