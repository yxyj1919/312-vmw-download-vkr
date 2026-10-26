#!/usr/bin/env bash
set -euo pipefail

BASE_TKG_CONTENT_LIBRARY_URI="https://wp-content.vmware.com/v2/latest"
TKG_CONTENT_LIBRARY_LIB_URL="${BASE_TKG_CONTENT_LIBRARY_URI}/lib.json"
TKG_CONTENT_LIBRARY_ITEMS_URL="${BASE_TKG_CONTENT_LIBRARY_URI}/items.json"

MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_DELAY="${RETRY_DELAY:-2}"
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-20}"
OUTPUT_DIR="${OUTPUT_DIR:-${HOME}}"
ITEMS_JSON="${ITEMS_JSON:-${TMPDIR:-/tmp}/vkr-items.json}"

usage() {
    cat <<'EOF'
Usage:
  ./download_vkr_images.sh

Selection input after the OVA list is shown:
  1          Download one version
  1,3,5      Download multiple versions
  2-6        Download a range
  all        Download all listed versions
  q          Quit

After selecting versions, the script shows the default download directory
and lets you change it interactively before any image files are downloaded.
EOF
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "[ERROR] Unknown argument: $1" >&2
                usage >&2
                exit 1
                ;;
        esac
    done
}

require_command() {
    local command_name="$1"

    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "[ERROR] ${command_name} is required but not installed." >&2
        exit 1
    fi
}

download_file() {
    local url="$1"
    local output="$2"
    local tmp_output="${output}.part"

    mkdir -p "$(dirname "${output}")"
    rm -f "${tmp_output}"

    for ((i=1; i<=MAX_RETRIES; i++)); do
        local http_code="000"

        if http_code=$(curl \
            --location \
            --fail-with-body \
            --silent \
            --show-error \
            --connect-timeout "${CONNECT_TIMEOUT}" \
            --write-out "%{http_code}" \
            --output "${tmp_output}" \
            "${url}"); then
            if [[ "${http_code}" == "200" ]]; then
                mv "${tmp_output}" "${output}"
                return 0
            fi
        fi

        rm -f "${tmp_output}"
        echo "  [WARN] HTTP ${http_code} for ${url} (attempt ${i}/${MAX_RETRIES})" >&2
        if [[ "${i}" -lt "${MAX_RETRIES}" ]]; then
            sleep "${RETRY_DELAY}"
        fi
    done

    echo "  [ERROR] Failed to download ${url} after ${MAX_RETRIES} attempts" >&2
    return 1
}

refresh_metadata() {
    echo -e "\033[36mDownloading ${ITEMS_JSON}\033[0m"
    download_file "${TKG_CONTENT_LIBRARY_ITEMS_URL}" "${ITEMS_JSON}"
}

save_metadata() {
    local output_items_json="${OUTPUT_DIR}/items.json"
    local output_lib_json="${OUTPUT_DIR}/lib.json"

    echo ""
    echo -e "\033[36mSaving Content Library metadata ...\033[0m"

    if [[ "${ITEMS_JSON}" != "${output_items_json}" ]]; then
        cp "${ITEMS_JSON}" "${output_items_json}"
    fi
    echo "  [SAVED] ${output_items_json}"

    download_file "${TKG_CONTENT_LIBRARY_LIB_URL}" "${output_lib_json}"
    echo "  [SAVED] ${output_lib_json}"
}

load_image_entries() {
    mapfile -t IMAGE_ENTRIES < <(jq -r '
        .items[]
        | select(
            .type == "vcsp.ovf"
            or any(.files[]?; (.name // "" | test("\\.(ova|ovf)$"; "i")))
          )
        | [
            .name,
            (.version // ""),
            (.created // ""),
            (([.files[]?.size // 0] | add) // 0 | tostring),
            ((.files // []) | length | tostring)
          ]
        | @tsv
    ' "${ITEMS_JSON}")
}

human_size() {
    local bytes="$1"
    local unit="B"
    local value="${bytes}"

    awk -v bytes="${bytes}" '
        BEGIN {
            split("B KiB MiB GiB TiB", units, " ")
            value = bytes
            unit = 1
            while (value >= 1024 && unit < 5) {
                value = value / 1024
                unit++
            }
            if (unit == 1) {
                printf "%d %s", value, units[unit]
            } else {
                printf "%.2f %s", value, units[unit]
            }
        }
    '
}

parse_image_name() {
    local item_name="$1"
    local os_name="unknown"
    local os_version="unknown"
    local image_version="unknown"

    if [[ "${item_name}" =~ photon-([0-9]+) ]]; then
        os_name="photon"
        os_version="${BASH_REMATCH[1]}"
    elif [[ "${item_name}" =~ ubuntu-([0-9]{2})([0-9]{2}) ]]; then
        os_name="ubuntu"
        os_version="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
    fi

    if [[ "${item_name}" =~ -v([0-9]+\.[0-9]+\.[0-9]+) ]]; then
        image_version="v${BASH_REMATCH[1]}"
    fi

    printf "%s\t%s\t%s\n" "${os_name}" "${os_version}" "${image_version}"
}

print_image_entries() {
    echo ""
    echo "Available OVA/OVF image versions:"
    echo "===================================================================================================================================="
    printf "%-5s %-8s %-8s %-12s %-10s %-5s %s\n" \
        "No." "OS" "OS Ver" "K8s/VKR" "Size" "Files" "Name"
    echo "------------------------------------------------------------------------------------------------------------------------------------"

    local index=1
    local entry item_name version created total_size file_count parsed os_name os_version image_version

    for entry in "${IMAGE_ENTRIES[@]}"; do
        item_name="${entry%%$'\t'*}"
        entry="${entry#*$'\t'}"
        version="${entry%%$'\t'*}"
        entry="${entry#*$'\t'}"
        created="${entry%%$'\t'*}"
        entry="${entry#*$'\t'}"
        total_size="${entry%%$'\t'*}"
        file_count="${entry#*$'\t'}"
        parsed="$(parse_image_name "${item_name}")"
        os_name="${parsed%%$'\t'*}"
        parsed="${parsed#*$'\t'}"
        os_version="${parsed%%$'\t'*}"
        image_version="${parsed#*$'\t'}"

        printf "%4d) %-8s %-8s %-12s %-10s %-5s %s\n" \
            "${index}" \
            "${os_name}" \
            "${os_version}" \
            "${image_version}" \
            "$(human_size "${total_size}")" \
            "${file_count}" \
            "${item_name}"
        printf "      created=%s  content-library-version=%s\n" \
            "${created:-n/a}" \
            "${version:-n/a}"
        ((++index))
    done

    echo "===================================================================================================================================="
}

select_download_directory() {
    local answer
    local custom_dir

    echo ""
    echo "Current download directory: ${OUTPUT_DIR}"

    while true; do
        read -r -p "Change download directory? [y/N]: " answer
        answer="$(printf '%s' "${answer}" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"

        case "${answer}" in
            ""|n|no)
                break
                ;;
            y|yes)
                read -r -p "Enter download directory: " custom_dir
                if [[ -z "${custom_dir}" ]]; then
                    echo "[ERROR] Download directory cannot be empty." >&2
                    continue
                fi

                OUTPUT_DIR="${custom_dir/#\~/${HOME}}"
                break
                ;;
            *)
                echo "[ERROR] Please enter y or n." >&2
                ;;
        esac
    done

    if ! mkdir -p "${OUTPUT_DIR}"; then
        echo "[ERROR] Failed to create download directory: ${OUTPUT_DIR}" >&2
        exit 1
    fi

    echo "Download directory: ${OUTPUT_DIR}"
}

expand_selection() {
    local raw_selection="$1"
    local max_index="$2"
    local normalized part start end index

    normalized="$(printf '%s' "${raw_selection}" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"

    if [[ -z "${normalized}" || "${normalized}" == "q" || "${normalized}" == "quit" ]]; then
        return 1
    fi

    if [[ "${normalized}" == "all" || "${normalized}" == "a" ]]; then
        for ((index=1; index<=max_index; index++)); do
            printf '%s\n' "${index}"
        done
        return 0
    fi

    IFS=',' read -r -a parts <<< "${normalized}"
    for part in "${parts[@]}"; do
        if [[ "${part}" =~ ^[0-9]+$ ]]; then
            if ((part < 1 || part > max_index)); then
                echo "[ERROR] Selection out of range: ${part}" >&2
                return 2
            fi
            printf '%s\n' "${part}"
        elif [[ "${part}" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            start="${BASH_REMATCH[1]}"
            end="${BASH_REMATCH[2]}"

            if ((start < 1 || end > max_index || start > end)); then
                echo "[ERROR] Selection range out of range: ${part}" >&2
                return 2
            fi

            for ((index=start; index<=end; index++)); do
                printf '%s\n' "${index}"
            done
        else
            echo "[ERROR] Invalid selection: ${part}" >&2
            return 2
        fi
    done | awk '!seen[$0]++'
}

download_selected_images() {
    local selected_indexes=("$@")
    local success_count=0
    local fail_count=0
    local skip_count=0
    local selected_index entry item_name file_hrefs href local_path download_url

    for selected_index in "${selected_indexes[@]}"; do
        entry="${IMAGE_ENTRIES[selected_index - 1]}"
        item_name="${entry%%$'\t'*}"

        echo ""
        echo -e "\033[36mProcessing: ${item_name}\033[0m"

        mapfile -t file_hrefs < <(jq -r --arg name "${item_name}" '
            .items[]
            | select(.name == $name)
            | .files[]?
            | .hrefs[]?
        ' "${ITEMS_JSON}")

        for href in "${file_hrefs[@]}"; do
            local_path="${OUTPUT_DIR}/${href}"
            download_url="${BASE_TKG_CONTENT_LIBRARY_URI}/${href}"

            if [[ -f "${local_path}" ]]; then
                echo "  [SKIP] Already exists: ${local_path}"
                ((++skip_count))
                continue
            fi

            echo -e "  \033[33mDownloading ${href} ...\033[0m"
            if download_file "${download_url}" "${local_path}"; then
                ((++success_count))
            else
                ((++fail_count))
            fi
        done
    done

    echo ""
    echo "============================================"
    echo "Download Summary:"
    echo "  Successful: ${success_count}"
    echo "  Skipped:    ${skip_count}"
    echo "  Failed:     ${fail_count}"
    echo "============================================"

    if [[ "${fail_count}" -gt 0 ]]; then
        exit 1
    fi
}

main() {
    parse_args "$@"

    require_command curl
    require_command jq
    require_command awk

    echo "Metadata file: ${ITEMS_JSON}"

    refresh_metadata
    load_image_entries

    if [[ "${#IMAGE_ENTRIES[@]}" -eq 0 ]]; then
        echo "[ERROR] No OVA/OVF image versions found in ${ITEMS_JSON}." >&2
        exit 1
    fi

    print_image_entries

    local selection
    local selected_indexes

    while true; do
        echo ""
        read -r -p "Select version(s) to download [1,3,5 | 2-6 | all | q]: " selection

        if selected_indexes="$(expand_selection "${selection}" "${#IMAGE_ENTRIES[@]}")"; then
            break
        else
            local status=$?
            if [[ "${status}" -eq 1 ]]; then
                echo "Quit."
                exit 0
            fi
        fi
    done

    mapfile -t SELECTED_INDEXES <<< "${selected_indexes}"
    select_download_directory
    save_metadata
    download_selected_images "${SELECTED_INDEXES[@]}"
}

main "$@"
