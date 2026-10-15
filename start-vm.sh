#!/bin/bash
# ============================================================
# 一键启动 win10-game（自检 + 自动修复 + 启动）
# 运行方式（宿主机终端）：
#   sudo bash start-vm.sh
#
# 自动处理：
#   1. AppArmor 隔离未关 → 自动关闭并重启 libvirtd
#   2. 配置里挂着光盘但 /opt/win10.iso 不存在 → 自动摘除，VM 从硬盘启动
#   3. 启动 VM（hook 会接管显卡/USB/NVMe，桌面会话登出属预期行为）
# ============================================================
set -euo pipefail

echo "== 1/3 AppArmor 隔离自检 =="
if grep -q '^security_driver = "none"' /etc/libvirt/qemu.conf 2>/dev/null; then
    echo "  OK：libvirt AppArmor 隔离已关闭"
else
    sed -i 's|^#*security_driver = .*|security_driver = "none"|' /etc/libvirt/qemu.conf
    grep -q '^security_driver' /etc/libvirt/qemu.conf || echo 'security_driver = "none"' >> /etc/libvirt/qemu.conf
    systemctl restart libvirtd
    echo "  已自动关闭 libvirt AppArmor 隔离并重启 libvirtd"
fi

echo "== 2/3 安装光盘自检 =="
if virsh dumpxml win10-game 2>/dev/null | grep -q 'win10\.iso'; then
    if [ -f /opt/win10.iso ]; then
        echo "  OK：ISO 就绪，将进入 Win10 安装程序"
    else
        virsh detach-disk win10-game sda --config 2>/dev/null || true
        echo "  配置里挂着光盘但 /opt/win10.iso 不存在 → 已自动摘除，VM 改为从硬盘启动"
        echo "  注意：若直通的那块 NVMe 上还没有系统，VM 会进不了系统；"
        echo "        放好 Win10 ISO 后运行 sudo bash attach-install-iso.sh 再启动"
    fi
else
    echo "  未挂载安装光盘，VM 将从硬盘启动"
    if [ ! -f /opt/win10.iso ]; then
        echo "  注意：若直通的那块 NVMe 上还没有系统，VM 会进不了系统；"
        echo "        放好 Win10 ISO 后运行 sudo bash attach-install-iso.sh 再启动"
    fi
fi

echo "== 3/3 启动 =="
if virsh list --state-running --name 2>/dev/null | grep -qx win10-game; then
    echo "  win10-game 已在运行中，无需重复启动"
else
    echo "  即将启动——启动后你的桌面会话会被 VM 接管（GNOME 登出），这是预期行为"
    virsh start win10-game
    echo "  启动命令已下发，显示器/键鼠已切给 VM"
fi
echo ""
echo "绑定日志：sudo tail -20 /var/log/vm-passthrough.log"
