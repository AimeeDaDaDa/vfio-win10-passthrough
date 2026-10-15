# KVM + VFIO 单显卡直通 —— Win10 去虚拟化游戏虚拟机

> 宿主机：Ubuntu 26.04 LTS · i5-12600KF (16线程) · 32GB · RTX 3050 6GB · 双 NVMe
> 形态：Linux 桌面照常用；开 VM 时桌面让位给 VM，关掉 VM 后桌面自动恢复。

---

## 1. 硬件盘点（已实测）

| 设备 | PCI 地址 | IOMMU 组 | 直通方案 |
|---|---|---|---|
| RTX 3050 6GB (10de:2584) | 01:00.0 | 12 | VFIO 直通 |
| RTX 3050 HDMI 音频 (10de:2291) | 01:00.1 | 12 | VFIO 直通（同组） |
| Acer SSD N3500CN 512G (10ec:5762) | 03:00.0 | 14 | **整盘直通**给 VM 当系统盘 |
| USB 3.2 控制器 x2 (8086:7a60 / 8086:7a27) | 00:14.0 / 00:14.2 | 3 | VFIO 直通（键鼠即插即用） |
| 系统盘 JUHOR J3500 (1dee:1202) | 02:00.0 | 13 | **不直通**（宿主机启动盘） |

全部设备组独立，无 ACS 拆分需求。QEMU 10.2 / libvirt 12 / swtpm / OVMF 已就绪，默认 NAT 网络已有。

## 2. ⚠️ 三个必须知道的事

1. **VM 运行时桌面会让位**：启动 VM 会自动结束你的图形会话、把显示器/键鼠切给 VM；VM 退出后恢复登录界面。所以日常从 SSH 管理 VM 最顺手（install.sh 会装好 openssh-server）。
2. **ACE 反作弊没有 100% 保证**：详见 §7。VFIO 直通解决性能和绝大多数检测点，但内核级反作弊的时序/行为检测无法完全消除，**有拒启动/掉线/封号案例，风险自担，建议小号先试**。
3. **第二块 NVMe 整盘直通**：该盘当前未挂载，分区布局（300M + 16M + 476G）像 Windows 系统盘。直通后 VM 对它可读写——**装机前先确认盘里没有要保留的数据**。若里面已有可启动的 Win10，直通后可直接启动它（最理想的"物理 Windows"形态，连装系统都省了）。

## 3. 安装（宿主机桌面终端，一条命令）

```bash
sudo bash /home/yssm/WorkBuddy/2026-10-13-16-44-19/vfio-win10-passthrough/install.sh
```

安装内容：openssh-server（宿主机无显示时管理用）、关闭 libvirt 的 AppArmor 隔离（本机 apparmor_parser 5.0.0~beta1 加载域侧写失败，且默认侧写限制直通设备访问）、libvirt hook（设备动态绑定）、虚拟机定义 `win10-game`。
**不改 GRUB、不动内核、不需要重启。** 现有 `win11.xml` 虚拟机定义未动，别同时运行两个 VM。

## 4. 首次安装 Win10

1. 挂安装光盘：Win10 ISO 放 `/opt/win10.iso`（微软 Media Creation Tool 制作）→ `sudo bash attach-install-iso.sh`
   （install.sh 检测到没有 ISO 时会自动移除光盘；此脚本可随时挂回来）
2. `sudo virsh start win10-game` —— 桌面让位，显示器切到 VM
3. 正常安装；磁盘选**直通的那块 NVMe**（整个盘，EFI 分区安装程序会自建）
4. 进系统后装 NVIDIA 驱动（官网下载，别用 Windows Update 版本）
5. 关机，移除安装光盘：`sudo virsh detach-disk win10-game sda --config`

> 若第二块盘已有 Windows：跳过 1–4，直接 `sudo virsh start win10-game`。若启动异常（自动修复/找不到引导），先 `sudo virsh detach-disk win10-game sda --config` 去掉光盘再试。

## 5. 日常使用

```bash
ssh <用户名>@192.168.17.12              # 宿主机（WiFi IP，以实际为准）
sudo bash start-vm.sh                  # 推荐：自检(AppArmor/光盘) + 启动一步完成
sudo virsh start win10-game            # 或直接启动（已确认环境正常时）
sudo virsh shutdown win10-game         # 正常关机；卡死则 virsh destroy
```

VM 退出后宿主机自动恢复图形登录界面。绑定日志：`/var/log/vm-passthrough.log`。
注意：WorkBuddy 容器内无法直接启动 VM（libvirtd 套接字被容器 /run 挂载遮挡、无 /dev/kvm 与 vfio 节点），启动命令必须在宿主机侧执行。

## 6. 去虚拟化清单

| 检测点 | 状态 | 手段 |
|---|---|---|
| CPUID hypervisor 位 | ✅ 已隐藏 | `kvm hidden` + `feature disable hypervisor` |
| CPUID KVM 签名 (KVMKVMKVM) | ✅ 已隐藏 | 同上 |
| SMBIOS / DMI / BIOS | ✅ 透传真实主板 | 技嘉 B760M H DDR4 / AMI F14（实测值） |
| 系统盘 | ✅ 真实 NVMe 整盘 | 零 QEMU 磁盘痕迹 |
| 显卡 | ✅ 真卡直通 | 无 Code 43 |
| 网卡 | ✅ e1000e + 伪造 Intel OUI | 避开 QEMU 默认 52:54:00 MAC |
| USB | ✅ 控制器整体直通 | 无仿真 USB 痕迹 |
| TPM | ✅ 虚拟 TPM 2.0 | swtpm |
| RDTSC 时序侧信道 | ❌ 无法完全消除 | KVM 固有，见 §7 |
| e1000e EEPROM 字符串 | ⚠️ 理论可读 | 极少有反作弊查这个 |

客户机内还需手动：改计算机名/用户名、装 NVIDIA 驱动、按需关闭遥测。

## 7. ACE 反作弊兼容性 —— 说实话

- VFIO 直通解决的是**性能**（≈ 原生 95%+）和**绝大多数静态检测点**。
- 腾讯 ACE 是内核级反作弊，剩余检测面：时序侧信道（RDTSC/TSC 测量）、驱动加载与进程行为、服务端交叉校验。这些没有公开的 100% 绕过方案，KVM 也无法完全消除时序差异。
- 社区现实：有直通 VM 稳定运行部分 ACE 游戏的案例，也有被拒启动 / 中途掉线 / 封号的案例。
- **建议**：小号或回归活动先验证；主力账号别赌；明确不支持虚拟机的游戏（如 Vanguard 系）直接放弃。

## 8. 故障排查

| 症状 | 处理 |
|---|---|
| 启动报"无法载入 AppArmor 侧写" | install.sh 已自动关闭 libvirt AppArmor 隔离；手动修复：`sudo sed -i 's\|^#*security_driver = .*\|security_driver = "none"\|' /etc/libvirt/qemu.conf && sudo systemctl restart libvirtd` |
| 启动报打不开 /opt/win10.iso | 放 ISO 后 `sudo bash attach-install-iso.sh`；或直接从硬盘引导：`sudo virsh detach-disk win10-game sda --config` |
| VM 起不来，提示 /dev/vfio 打不开 | 看 `/var/log/vm-passthrough.log`；`lspci -k -s 01:00.0` 确认在 vfio-pci |
| 黑屏无信号 | 显示器必须插 RTX 3050；确认 hook 正常接管 |
| 显卡 Code 43 | 确认 XML 中 `hidden state='on'` 与 `feature policy='disable' name='hypervisor'` 两行都在 |
| 宿主机桌面没自动恢复 | `sudo systemctl start gdm3`；或 reboot |
| hook 不生效（日志无记录） | 新版 libvirt 若只认目录式 hook，确认 `/etc/libvirt/hooks/qemu.d/10-win10-game.hook` 存在且可执行 |
| 键鼠在 VM 里失灵 | 键鼠必须插主板 USB 口（都在被直通的 00:14.x 组里） |

## 9. 回滚

```bash
sudo bash /home/yssm/WorkBuddy/2026-10-13-16-44-19/vfio-win10-passthrough/rollback.sh
```

删 hook、注销 VM、归还驱动，并还原 qemu.conf 的 AppArmor 设置。零 boot 层改动，**不需要重启**。

## 10. 进阶（可选）

- **开机绑定模式**（VM 常驻、宿主机永久无显示、SSH-only）：见 `configs/vfio-pci.boot.conf` 内步骤，含回滚与 GRUB 救援说明（7.0.0-27 内核未动，可救命）。
- **Moonlight + Sunshine**：VM 里装 Sunshine，手机/电视/Win 主机串流玩，宿主机纯后台。
- **Win11 VM**：TPM 已就绪；loader 换 `OVMF_CODE_4M.secboot.fd` 并开 Secure Boot 即可（注意：Vanguard 系仍明确不支持 VM）。
