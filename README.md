# 310-vmw-download-vkr

An interactive script for downloading VMware VKR/TKG OVA/OVF image content.

The script retrieves the latest `items.json` metadata from the VMware Content Library and lists the available image versions. For each image, it displays the operating system, OS version, Kubernetes/VKR version, total size, and file count.

You can download a single version, multiple versions, a range, or all listed versions. After you make a selection, the script displays the default download directory and lets you change it before downloading any image files. It also saves `lib.json` and `items.json` in the selected download directory.

## Requirements

- Bash 4+
- `curl`
- `jq`
- `awk`

## Usage

```bash
./download_vkr_images.sh
```

Selection formats:

```text
1       # Download one version
1,3,5   # Download multiple versions
2-6     # Download a range
all     # Download all listed versions
q       # Quit
```

The default download directory is the current user's home directory, such as `/Users/<user>` on macOS or `/home/<user>` on Linux. After you select the image versions, the script asks whether you want to change the directory.

The script preserves the VMware Content Library directory structure and skips image files that already exist locally. The `lib.json` and `items.json` files in the root of the download directory are updated with the metadata used for the current run.
