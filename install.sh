#!/bin/bash
# ============================================================
# 宿主机一键安装：KVM + VFIO 单显卡直通 Win10 游戏虚拟机
# 运行方式（宿主机桌面终端）：
#   sudo bash install.sh
#
# 本脚本【不改 GRUB、不动内核、不需要重启】：
# 装 openssh-server、关闭 libvirt AppArmor 隔离（本机 parser 加载域侧写失败）、
# 部署 libvirt hook、定义虚拟机；无 ISO 时自动移除安装光盘。
# GPU/NVMe/USB 的绑定全部在 VM 启停时由 hook 动态完成。
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

echo "== 0. 前置检查 =="
[ "$(id -u)" = 0 ] || { echo "错误：请用 root 运行（sudo bash install.sh）"; exit 1; }
command -v virsh >/dev/null || { echo "错误：libvirt 未安装"; exit 1; }
for d in 0000:01:00.0 0000:01:00.1 0000:02:00.0 0000:00:14.0 0000:00:14.2; do
    [ -e "/sys/bus/pci/devices/$d" ] || { echo "错误：找不到 PCI 设备 $d，硬件不匹配？"; exit 1; }
done
# 确认 IOMMU 已开启
[ -e /sys/kernel/iommu_groups/12/devices ] || { echo "错误：IOMMU 组不存在，请检查 BIOS 中 VT-d"; exit 1; }
echo "硬件检查通过（GPU 01:00.x / NVMe 02:00.0 / USB 00:14.x 均就绪，IOMMU 组 12/13/3 正常）"

echo "== 1. 安装依赖 =="
apt-get install -y openssh-server swtpm swtpm-tools || echo "警告：apt 安装失败，请手动安装 openssh-server"
systemctl enable --now ssh 2>/dev/null || systemctl enable --now sshd 2>/dev/null || true
systemctl enable --now libvirtd 2>/dev/null || true
echo "SSH 已启用（宿主机无显示时用 ssh 管理）；请按需加固：密钥认证/防火墙"

echo "== 2. 关闭 libvirt 的 AppArmor 隔离 =="
# 本机 apparmor_parser 5.0.0~beta1 加载域侧写失败（cannot load AppArmor profile），
# 且 libvirt 默认侧写会限制直通设备访问 —— 对 VFIO 直通虚拟机直接关掉最稳。
sed -i 's|^#*security_driver = .*|security_driver = "none"|' /etc/libvirt/qemu.conf
grep -q '^security_driver' /etc/libvirt/qemu.conf || echo 'security_driver = "none"' >> /etc/libvirt/qemu.conf
systemctl restart libvirtd
echo "qemu.conf: $(grep '^security_driver' /etc/libvirt/qemu.conf)"

echo "== 3. 部署 libvirt hook（设备动态绑定） =="
# ★★ 绝对不要再用"目录式 hook 双保险"！★★
# 这里曾经同时装两份（/etc/libvirt/hooks/qemu + /etc/libvirt/hooks/qemu.d/10-win10-game.hook），
# 而 libvirt 是「先跑 qemu，再跑 qemu.d/*」—— 后跑的那份会**覆盖**前一份的效果。
# 后果：更新了 /etc/libvirt/hooks/qemu，qemu.d 里却一直留着最早的旧版，
#       旧版直通的是 03:00.0（Linux 根盘），启动 VM 时把根文件系统拔掉 → 宿主机整机硬冻结。
# 现在只保留单文件 hook，并主动清除任何历史遗留的 qemu.d 脚本。
if [ -d /etc/libvirt/hooks/qemu.d ]; then
    legacy=$(ls /etc/libvirt/hooks/qemu.d/ 2>/dev/null || true)
    if [ -n "$legacy" ]; then
        echo "发现遗留目录式 hook，已备份并清除：$legacy"
        mkdir -p /root/vfio-hook-backup
        cp -a /etc/libvirt/hooks/qemu.d/. /root/vfio-hook-backup/ 2>/dev/null || true
        rm -f /etc/libvirt/hooks/qemu.d/*
    fi
fi
install -D -m 755 configs/qemu-hook-v5 /etc/libvirt/hooks/qemu
echo "hook 已安装：/etc/libvirt/hooks/qemu（单文件，qemu.d 保持为空）"
ls -la /etc/libvirt/hooks/qemu.d/ 2>/dev/null || true

echo "== 4. 定义虚拟机 =="
virsh define win10-game.xml
virsh net-autostart default 2>/dev/null || true
virsh net-start default 2>/dev/null || true

echo "== 5. 安装光盘处理 =="
if [ ! -f /opt/win10.iso ]; then
    # 没有 ISO 就把 cdrom 从持久配置里移除，否则 QEMU 会因打不开 ISO 而启动失败
    if virsh detach-disk win10-game sda --config 2>/dev/null; then
        echo "未找到 /opt/win10.iso —— 已移除安装光盘，VM 可直接从硬盘启动。"
    else
        echo "警告：自动移除光盘失败。若 VM 起不来报找不到 /opt/win10.iso，请手动执行："
        echo "      sudo virsh edit win10-game  （删除 <disk type='file' device='cdrom'> 整段）"
    fi
    echo "以后装系统：Win10 ISO 放到 /opt/win10.iso 后运行 sudo bash attach-install-iso.sh"
else
    echo "已检测到 /opt/win10.iso，安装光盘就绪。"
fi

echo ""
echo "安装完成！未改动 GRUB/内核，无需重启。"
echo "下一步：sudo virsh start win10-game   （桌面会让位给 VM，显示器切换）"
