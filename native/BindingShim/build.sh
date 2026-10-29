#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: build.sh --endstone-root <dir> --expected-lite-include <dir> --nlohmann-include <dir> [options]

Options:
  --endstone-root <dir>           Endstone checkout containing include/endstone (required).
  --expected-lite-include <dir>   Directory containing nonstd/expected.hpp (required).
  --nlohmann-include <dir>        Directory containing nlohmann/json.hpp (required).
  --output <file>                 Output shared library.
                                  Default: artifacts/native/libHosihikari.Bindings.Endstone.Shim.so
  --shim-source <file>            Generated binding_table.cpp to compile.
                                  Default: generated/win-x64-server/endstone/binding_table.cpp
  --generated-include <dir>       Directory holding the generated endstone/version.h.
                                  Default: artifacts/endstone-generated/include
  --cxx <compiler>                C++ compiler. Default: g++, or the CXX environment variable.
EOF
}

script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_root/../.." && pwd)"
endstone_root=""
expected_lite_include=""
nlohmann_include=""
output="$repo_root/artifacts/native/libHosihikari.Bindings.Endstone.Shim.so"
shim_source=""
generated_include=""
cxx="${CXX:-g++}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --endstone-root)
            endstone_root="${2:-}"
            shift 2
            ;;
        --expected-lite-include)
            expected_lite_include="${2:-}"
            shift 2
            ;;
        --nlohmann-include)
            nlohmann_include="${2:-}"
            shift 2
            ;;
        --output)
            output="${2:-}"
            shift 2
            ;;
        --shim-source)
            shim_source="${2:-}"
            shift 2
            ;;
        --generated-include)
            generated_include="${2:-}"
            shift 2
            ;;
        --cxx)
            cxx="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ -z "$endstone_root" ] || [ -z "$expected_lite_include" ] || [ -z "$nlohmann_include" ]; then
    usage >&2
    exit 2
fi

endstone_root="$(cd "$endstone_root" && pwd)"
expected_lite_include="$(cd "$expected_lite_include" && pwd)"
nlohmann_include="$(cd "$nlohmann_include" && pwd)"

shim_dir="$script_root/generated/win-x64-server/endstone"
if [ -z "$shim_source" ]; then
    shim_source="$shim_dir/binding_table.cpp"
fi
source_file="$(cd "$(dirname "$shim_source")" && pwd)/$(basename "$shim_source")"
if [ ! -f "$source_file" ]; then
    echo "Generated BindingShim sources are missing: $source_file" >&2
    exit 1
fi

if [ ! -f "$endstone_root/include/endstone/endstone.hpp" ]; then
    echo "Endstone headers were not found under $endstone_root/include." >&2
    exit 1
fi

if [ ! -f "$expected_lite_include/nonstd/expected.hpp" ]; then
    echo "expected-lite headers were not found under $expected_lite_include." >&2
    exit 1
fi

version="$(sed -n 's/.*project[[:space:]]*([[:space:]]*endstone[[:space:]]*VERSION[[:space:]]*\([0-9][0-9.]*\).*/\1/p' \
    "$endstone_root/include/CMakeLists.txt" | head -n 1)"
version="${version:-0.11.15}"
IFS='.' read -r major minor patch <<EOF
$version
EOF
major="${major:-0}"
minor="${minor:-0}"
patch="${patch:-0}"

if [ -n "$generated_include" ]; then
    generated_root="$(mkdir -p "$generated_include" && cd "$generated_include" && pwd)"
else
    generated_root="$repo_root/artifacts/endstone-generated/include"
fi
mkdir -p "$generated_root/endstone" "$(dirname "$output")"
cat > "$generated_root/endstone/version.h" <<EOF
#pragma once
#define ENDSTONE_VERSION_MAJOR $major
#define ENDSTONE_VERSION_MINOR $minor
#define ENDSTONE_VERSION_PATCH $patch
#define ENDSTONE_API_VERSION "$major.$minor"
#ifndef ENDSTONE_VERSION
#define ENDSTONE_VERSION "$version"
#endif
EOF

"$cxx" \
    -std=c++20 \
    -shared \
    -fPIC \
    -O2 \
    -pthread \
    -include "$script_root/linux-compat.h" \
    -I "$endstone_root/include" \
    -I "$endstone_root/include/endstone" \
    -I "$generated_root" \
    -I "$expected_lite_include" \
    -I "$nlohmann_include" \
    "$source_file" \
    -o "$output" \
    -ldl

if command -v nm >/dev/null 2>&1; then
    exports="$(nm -D --defined-only "$output")"
    if ! printf '%s\n' "$exports" | grep -q 'hosihikari_get_binding_table_v1'; then
        echo "The built shim does not export hosihikari_get_binding_table_v1." >&2
        exit 1
    fi
    if ! printf '%s\n' "$exports" | grep -q 'hosihikari_endstone_get_server'; then
        echo "The built shim does not export hosihikari_endstone_get_server." >&2
        exit 1
    fi
fi

echo "Built $output"
