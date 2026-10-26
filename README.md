# 310-vmw-download-vkr

一个用于下载 VMware VKR/TKG OVA/OVF 镜像内容的交互式脚本。

脚本会从 VMware Content Library 获取最新的 `items.json` 元数据，列出可下载的镜像版本。列表会单独显示操作系统、操作系统版本、Kubernetes/VKR 版本、镜像大小和文件数量。用户可以选择单个版本、多个版本、版本范围，或一次下载全部版本。选择完成后，脚本会显示默认下载目录，并允许在真正下载镜像文件前手工修改目录。下载开始时，`lib.json` 和 `items.json` 也会保存到该下载目录。

## Requirements

- Bash 4+
- `curl`
- `jq`
- `awk`

## Usage

```bash
./download_vkr_images.sh
```

选择格式：

```text
1       # 下载一个版本
1,3,5   # 下载多个版本
2-6     # 下载一个范围
all     # 下载全部列出的版本
q       # 退出
```

默认下载目录是当前执行用户的 Home 目录，例如 macOS 上的 `/Users/<user>` 或 Linux 上的 `/home/<user>`。选择版本后，脚本会询问是否修改下载目录。

下载时会保留 VMware Content Library 中的目录结构，并跳过本地已经存在的镜像文件。下载目录根路径下的 `lib.json` 和 `items.json` 会更新为本次使用的元数据。
