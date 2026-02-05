# 阶段 1 快速参考卡片

> 随时查阅的 checkm8 关键信息速查表

---

## 🎯 你的设备信息

```
┌────────────────────────────────────────────────┐
│  iPhone X (A11 Bionic)                         │
├────────────────────────────────────────────────┤
│  CPID:        0x8015 (T8015)                   │
│  Board ID:    0x0e (D221AP)                    │
│  iBoot:       iBoot-3332.0.0.1.23              │
│  iOS:         12.3.1 (16F203)                  │
│  XNU:         xnu-4903.262.2                   │
│  越狱:        checkra1n (bootrom exploit)      │
└────────────────────────────────────────────────┘
```

---

## 📍 T8015 内存地址速查

### SecureROM (只读)
| 地址 | 名称 | 用途 |
|------|------|------|
| `0x1000003EC` | write_sctlr_gadget | 写 SCTLR_EL1 |
| `0x10000045C` | write_ttbr0 | 写页表基址 |
| `0x1000004AC` | tlbi | TLB 无效化 |
| `0x1000004D0` | dc_civac | 数据缓存清理 |
| `0x1000004F0` | dmb | 数据内存屏障 |
| `0x10000945C` | load_write_gadget | 加载/写入 |
| `0x10000A9AC` | func_gadget | 函数调用 |
| `0x10000AE80` | usb_create_string_descriptor | USB 字符串 |
| `0x10000B9A8` | USB_CORE_DO_IO | USB I/O |
| `0x10000BCCC` | handle_interface_request | USB 请求处理 |

### SRAM (可读写)
| 地址 | 名称 | 用途 |
|------|------|------|
| `0x1800008FA` | gUSBSRNMStringDescriptor | USB 描述符 |
| `0x180003A78` | gUSBSerialNumber | USB 序列号 |
| `0x180008528` | gUSBDescriptors | USB 描述符表 |
| `0x180008638` | PAYLOAD_PTR | payload 指针 |
| `0x18001BC00` | PAYLOAD_DEST | shellcode 目标 |
| `0x18001C000` | LOAD_ADDRESS | 主加载地址 |
| `0x18001C020` | ROP callbacks | ROP 链数据 |

---

## 🔧 常用 SSH 命令

```bash
# 基础连接
alias jb='sshpass -p alpine ssh -p 2222 root@localhost'

# 设备信息
jb "uname -a"
jb "sysctl hw.machine hw.model"
jb "ioreg -p IODeviceTree -l | grep chip-id"

# 安全分析
jb "/binpack/usr/local/bin/jtool2 -k /System/Library/Caches/com.apple.kernelcaches/kernelcache"
jb "/binpack/usr/local/bin/jtool2 --ent /path/to/binary"
jb "/binpack/usr/local/bin/jtool2 --sig /path/to/binary"

# 系统状态
jb "sysctl security.mac"
jb "sysctl vm.cs_force_kill vm.cs_force_hard"
jb "launchctl list | grep -i security"
jb "ps aux | grep -E 'amfi|trustd|securityd'"

# 文件系统
jb "mount"
jb "ls -la /binpack/usr/local/bin/"
jb "cat /System/Library/CoreServices/SystemVersion.plist"
```

---

## 🛡️ 安全组件速查

### 内核扩展 (Kext)
| Bundle ID | 功能 |
|-----------|------|
| `com.apple.driver.AppleMobileFileIntegrity` | AMFI - 代码签名验证 |
| `com.apple.kext.CoreTrust` | 信任缓存验证 |
| `com.apple.security.sandbox` | 沙盒策略执行 |
| `com.apple.security.AppleImage4` | 安全启动验证 |

### 守护进程
| 进程 | 功能 |
|------|------|
| `/usr/libexec/amfid` | AMFI 守护进程 |
| `/usr/libexec/trustd` | 信任评估服务 |
| `/usr/libexec/securityd` | 安全服务守护进程 |

### 关键 sysctl 参数
| 参数 | 当前值 | 含义 |
|------|--------|------|
| `vm.cs_force_kill` | 0 | 不强制杀死未签名代码 |
| `vm.cs_force_hard` | 0 | 代码签名检查已放松 |
| `security.mac.proc_enforce` | 1 | MAC 进程策略执行中 |
| `security.mac.vnode_enforce` | 1 | MAC 文件策略执行中 |

---

## 📝 ARM64 汇编速查

### 常用指令
```asm
; 数据传输
LDR  Xn, [Xm]         ; 加载 64 位
STR  Xn, [Xm]         ; 存储 64 位
LDP  Xn, Xm, [Xk]     ; 加载寄存器对
STP  Xn, Xm, [Xk]     ; 存储寄存器对
MOV  Xn, Xm           ; 移动

; 分支
B    label            ; 无条件跳转
BL   label            ; 带链接跳转
BLR  Xn               ; 跳转到寄存器
RET                   ; 返回
CBZ  Xn, label        ; 为零跳转
CBNZ Xn, label        ; 非零跳转

; 系统
MSR  reg, Xn          ; 写系统寄存器
MRS  Xn, reg          ; 读系统寄存器
DC   CIVAC, Xn        ; 清理数据缓存
DSB  SY               ; 数据同步屏障
ISB                   ; 指令同步屏障
```

### 关键系统寄存器
| 寄存器 | 用途 |
|--------|------|
| `SCTLR_EL1` | 系统控制 (包含 WXN 位) |
| `TTBR0_EL1` | 页表基址寄存器 0 |
| `TTBR1_EL1` | 页表基址寄存器 1 |
| `VBAR_EL1` | 异常向量基址 |

---

## 🔄 checkm8 执行流程

```
1. stall()          → 创建悬挂 USB 请求
2. no_leak() × 6    → 堆布局 (hole=6)
3. usb_req_leak()   → 泄漏分配
4. usb_reset()      → 触发 UAF
5. 重新连接         → 复用已释放内存
6. 发送 overwrite   → 覆盖控制结构
7. 发送 payload     → 注入 shellcode
8. usb_reset()      → 执行 ROP 链
9. ROP 链执行:
   - dc_civac       → 清理缓存
   - dmb            → 内存屏障
   - write_sctlr    → 禁用 WXN (0x100D)
   - write_ttbr0    → 设置页表
   - tlbi           → 刷新 TLB
   - 跳转 shellcode → 执行我们的代码
```

---

## 📁 关键文件路径

### 研究资料
```
checkra1n_research/
├── ipwndfu/
│   ├── checkm8.py              ← 主 exploit
│   ├── src/checkm8_arm64.S     ← ARM64 shellcode
│   ├── src/usb_0xA1_2_arm64.S  ← USB handler
│   └── src/t8010_t8011_disable_wxn_arm64.S
└── pongoOS/
    ├── src/kernel/entry.c      ← pongoOS 入口
    └── checkra1n/kpf/main.c    ← 内核补丁
```

### 设备上
```
/binpack/usr/local/bin/
├── jtool2      ← Mach-O 分析
├── procexp     ← 进程浏览器
├── filemon     ← 文件监控
└── lsdtrip     ← launchd 分析

/System/Library/Caches/
├── com.apple.kernelcaches/kernelcache
└── com.apple.dyld/dyld_shared_cache_arm64
```

---

## 🔢 Magic 值

| 值 | 十六进制 | 用途 |
|----|----------|------|
| `exec` | `0x6578656365786563` | 执行函数命令 |
| `done` | `0x646F6E65646F6E65` | 完成标记 |
| `memc` | `0x6D656D636D656D63` | 内存复制命令 |
| `mems` | `0x6D656D736D656D73` | 内存设置命令 |
| `0xbeefbeef` | - | 调试标记 |

---

## ⚡ 快速验证命令

```bash
# 验证 checkra1n 状态
sshpass -p 'alpine' ssh -p 2222 root@localhost "ioreg -l | grep checkra1n"

# 验证芯片 ID
sshpass -p 'alpine' ssh -p 2222 root@localhost "ioreg -p IODeviceTree -l | grep chip-id"
# 预期: <15800000> = 0x8015

# 验证代码签名状态
sshpass -p 'alpine' ssh -p 2222 root@localhost "sysctl vm.cs_force_kill vm.cs_force_hard"
# 预期: 都是 0 (已放松)

# 验证安全进程
sshpass -p 'alpine' ssh -p 2222 root@localhost "ps aux | grep amfid"
# 预期: /usr/libexec/amfid 运行中
```

---

*快速参考卡片 v1.0*
*适用于: iPhone X (T8015) / iOS 12.3.1 / checkra1n*
