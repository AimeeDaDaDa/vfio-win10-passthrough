#!/bin/bash
# ============================================================
# 一键回滚：删除 hook、注销虚拟机、归还设备驱动
#   sudo bash rollback.sh
# 注意：若安装过"开机绑定模式"配置，需按 README §10 手动清理
# ============================================================
set -euo pipefail

echo "== 关闭虚拟机（触发 hook 归还驱动） =="
virsh shutdown win10-game 2>/dev/null || true
sleep 2
virsh destroy win10-game 2>/dev/null || true
sleep 1

echo "== 删除 hook =="
rm -f /etc/libvirt/hooks/qemu
rm -f /etc/libvirt/hooks/qemu.d/10-win10-game.hook

echo "== 注销虚拟机 =="
virsh undefine win10-game 2>/dev/null || true
rm -rf /run/vm-passthrough

echo "== 还原 libvirt AppArmor 隔离设置 =="
sed -i 's|^security_driver = .*|#security_driver = [ "apparmor", "selinux" ]|' /etc/libvirt/qemu.conf 2>/dev/null || true
systemctl restart libvirtd 2>/dev/null || true

echo "== 检查设备是否已归还 =="
for d in 0000:01:00.0 0000:01:00.1 0000:03:00.0 0000:00:14.0 0000:00:14.2; do
    cur=$(readlink -f "/sys/bus/pci/devices/$d/driver" 2>/dev/null | xargs -r basename)
    echo "  $d -> ${cur:-未绑定}"
done
echo ""
echo "回滚完成。若某设备仍显示 vfio-pci，重启宿主机即可自动恢复原驱动。"
echo "openssh-server 如不再需要：sudo apt remove openssh-server"
