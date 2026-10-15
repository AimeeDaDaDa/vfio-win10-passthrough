#!/bin/bash
# ============================================================
# 挂载 Win10 安装光盘到 win10-game（持久配置）
# 用法： sudo bash attach-install-iso.sh [/path/to/win10.iso]
# 默认路径 /opt/win10.iso
# ============================================================
set -euo pipefail

ISO="${1:-/opt/win10.iso}"
[ -f "$ISO" ] || {
    echo "错误：找不到 ISO：$ISO"
    echo "先从微软官网制作 Win10 ISO 并放到该路径，或作为第一个参数传入。"
    exit 1
}

# 幂等：先移除旧光盘再挂新（避免重复 cdrom）
virsh detach-disk win10-game sda --config 2>/dev/null || true
virsh attach-disk win10-game "$ISO" sda --type cdrom --mode readonly --config

echo ""
echo "安装光盘已挂载。现在启动：sudo virsh start win10-game"
echo "（硬盘上无可启动系统时 UEFI 会自动进入安装程序；有系统时开机按 ESC 选 UEFI DVD）"
echo "装完系统后移除光盘：sudo virsh detach-disk win10-game sda --config"
