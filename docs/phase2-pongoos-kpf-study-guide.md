# 阶段 2：pongoOS 与内核补丁 (KPF) 学习指南

> 学习目标：理解 pongoOS 预启动环境和内核补丁查找器 (KPF) 的工作原理

---

## 📋 学习概览

| 项目 | 内容 |
|------|------|
| **前置条件** | 完成阶段 1 (checkm8 原理) |
| **学习周期** | 建议 2-3 周 |
| **核心文件** | pongoOS/src/, pongoOS/checkra1n/kpf/ |
| **目标** | 理解从 bootrom 控制到内核控制的完整链路 |

---

## 🏗️ 知识架构

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         越狱完整链路                                     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   阶段 1 (已学)              阶段 2 (本章)           阶段 3 (下一章)      │
│   ┌─────────────┐          ┌─────────────┐        ┌─────────────┐      │
│   │  checkm8    │ ──────▶  │  pongoOS    │ ─────▶ │  越狱后     │      │
│   │  SecureROM  │          │  KPF 补丁   │        │  Substrate  │      │
│   │  exploit    │          │  内核修改   │        │  Tweak 开发 │      │
│   └─────────────┘          └─────────────┘        └─────────────┘      │
│         │                        │                      │              │
│         ▼                        ▼                      ▼              │
│   控制 bootrom            修改内核安全检查         运行未签名代码        │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 📚 第一周：pongoOS 基础

### 1.1 什么是 pongoOS？

**定义：**
```
pongoOS = Pre-boot Execution Environment
        = 预启动执行环境
        = 在 iOS 启动之前运行的迷你操作系统
```

**作用：**
```
┌─────────────────────────────────────────────────────────────┐
│  pongoOS 的职责：                                            │
├─────────────────────────────────────────────────────────────┤
│  1. 接管 checkm8 之后的控制权                                │
│  2. 提供一个 shell 环境 (可以通过 USB 交互)                  │
│  3. 加载内核补丁模块 (KPF)                                   │
│  4. 在内核启动前修改内核代码                                 │
│  5. 引导修改后的内核启动                                     │
└─────────────────────────────────────────────────────────────┘
```

**启动流程对比：**
```
正常启动：
SecureROM → iBoot → XNU 内核 → iOS

checkra1n 启动：
SecureROM → checkm8 → pongoOS → 补丁 XNU → iOS (越狱版)
                         ↑
                    我们在这里工作
```

### 1.2 pongoOS 源码结构

```
checkra1n_research/pongoOS/
│
├── src/                          # pongoOS 核心源码
│   ├── kernel/
│   │   ├── entry.c              ← ★ 入口点，一切从这里开始
│   │   ├── mm.c                 ← 内存管理
│   │   ├── task.c               ← 任务/线程管理
│   │   ├── lowlevel.c           ← 底层硬件操作
│   │   └── pongo.h              ← 主头文件
│   │
│   ├── drivers/
│   │   ├── usb/                 ← USB 驱动 (和电脑通信)
│   │   ├── framebuffer/         ← 屏幕驱动 (显示 logo)
│   │   ├── uart/                ← 串口驱动 (调试输出)
│   │   ├── sep/                 ← SEP 安全处理器交互
│   │   └── xnu/
│   │       └── xnu.c            ← XNU 内核操作
│   │
│   ├── shell/                   ← pongoOS shell 命令
│   └── boot/                    ← 启动相关代码
│
├── checkra1n/
│   └── kpf/
│       ├── main.c               ← ★★★ 核心！内核补丁查找器
│       └── shellcode.S          ← 注入内核的 shellcode
│
└── scripts/
    └── pongoterm               ← 和 pongoOS shell 交互的工具
```

### 1.3 关键概念

| 概念 | 说明 |
|------|------|
| **KPF** | Kernel Patchfinder，内核补丁查找器 |
| **XNU** | iOS/macOS 的内核，X is Not Unix |
| **kext** | Kernel Extension，内核扩展 |
| **AMFI** | Apple Mobile File Integrity，代码签名验证 |
| **Sandbox** | 沙盒，限制 App 访问范围 |
| **tfp0** | task_for_pid(0)，获取内核任务端口 |

---

## 🔬 第二周：KPF 内核补丁分析

### 2.1 KPF 工作原理

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         KPF 工作流程                                     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  1. 内核被加载到内存 (但还没执行)                                        │
│                    ↓                                                    │
│  2. KPF 扫描内核的 __TEXT_EXEC 段                                       │
│                    ↓                                                    │
│  3. 使用模式匹配找到目标代码                                             │
│     • 搜索特定的指令序列                                                │
│     • 例如：找 AMFI 的签名检查代码                                      │
│                    ↓                                                    │
│  4. 找到后，修改这些指令                                                │
│     • 把检查代码改成 NOP (空操作)                                       │
│     • 或改成直接返回 true                                               │
│                    ↓                                                    │
│  5. 所有补丁打完，让内核继续启动                                         │
│                    ↓                                                    │
│  6. 内核启动时，安全检查已被绕过                                         │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.2 主要补丁详解

#### 补丁 1：AMFI (代码签名)

**原理：**
```
AMFI = Apple Mobile File Integrity

正常流程：
App 启动 → AMFI 检查签名 → 没签名？→ 拒绝运行

补丁后：
App 启动 → AMFI 检查签名 → 直接返回"有签名" → 允许运行
```

**源码位置：** `checkra1n/kpf/main.c`

```c
bool kpf_amfi_callback(struct xnu_pf_patch* patch, uint32_t* opcode_stream) {
    // 找到 AMFI 检查代码后
    // 把它改成直接返回 1 (true)

    opcode_stream[0] = 0xd2800020;  // MOV X0, #1
    opcode_stream[1] = RET;          // RET

    // 现在 AMFI 认为所有程序都在信任缓存中
    puts("KPF: Found AMFI");
    return true;
}
```

**搜索模式：**
```c
uint64_t matches[] = {
    0x91000000, // ADD 指令
    0x52800200, // MOV W*, 0x16
    0xd3000000, // LSR 指令
    0x9b000000  // MADD 指令
};
```

#### 补丁 2：mac_mount (根文件系统)

**原理：**
```
正常流程：
mount -uw / → 内核检查 → "根目录不能重新挂载！" → 拒绝

补丁后：
mount -uw / → 内核检查 → 检查被跳过 → 允许
```

**源码：**
```c
bool kpf_mac_mount_callback(struct xnu_pf_patch* patch, uint32_t* opcode_stream) {
    // 找到检查 MNT_ROOTFS 的代码
    // 把 tbnz (测试并跳转) 改成 NOP

    mac_mount_1[0] = NOP;  // 0xd503201f

    // 找到检查 mnt_flag 的代码
    // 把 ldrb 改成 mov x8, xzr (清零)
    mac_mount_1[0] = 0xaa1f03e8;  // MOV X8, XZR

    puts("KPF: Found mac_mount");
    return true;
}
```

#### 补丁 3：vm_map_protect (W^X 保护)

**原理：**
```
正常流程：
App 请求 W+X 内存 → 内核检查 → "不允许同时可写可执行！" → 拒绝

补丁后：
App 请求 W+X 内存 → 内核检查被跳过 → 允许

这对于 Cydia Substrate 的函数 hook 至关重要
```

**源码：**
```c
bool kpf_mac_vm_map_protect_callback(struct xnu_pf_patch* patch, uint32_t* opcode_stream) {
    // 找到 W^X 检查代码
    // 修改跳转，绕过检查

    uint32_t delta = first_ldr - (&opcode_stream[2]);
    delta &= 0x03ffffff;
    delta |= 0x14000000;  // 构造 B 指令
    opcode_stream[2] = delta;  // 跳过检查

    puts("KPF: Found vm_map_protect");
    return true;
}
```

#### 补丁 4：task_conversion_eval (tfp0)

**原理：**
```
tfp0 = task_for_pid(0) = 获取 PID 0 (内核) 的任务端口

正常流程：
App 调用 tfp0 → 内核检查 → "普通 App 不能获取内核端口！" → 拒绝

补丁后：
App 调用 tfp0 → 检查被绕过 → 返回内核任务端口

有了 tfp0，就可以读写内核内存，完全控制系统
```

**源码：**
```c
bool kpf_conversion_callback(struct xnu_pf_patch* patch, uint32_t* opcode_stream) {
    // 找到 if (caller == victim) 检查
    // 把 CMP 改成 CMP XZR, XZR (永远相等)

    *opcode_stream = 0xeb1f03ff;  // CMP XZR, XZR

    puts("KPF: Found task_conversion_eval");
    return true;
}
```

### 2.3 模式匹配技术

KPF 使用掩码匹配来找到目标代码：

```c
// 定义要搜索的指令模式
uint64_t matches[] = {
    0xb9400000, // LDR W*, [X*]
    0x36500000, // TBZ W*, 0xa, *
    0xb9400000, // LDR W*, [X*]
    0x36500000, // TBZ W*, 0xa, *
};

// 定义掩码 (哪些位需要匹配)
uint64_t masks[] = {
    0xffc00000, // 只匹配操作码，忽略寄存器
    0xfff80000,
    0xffc00000,
    0xfef80000,
};

// 执行搜索
xnu_pf_maskmatch(patchset, "patch_name", matches, masks, count, callback);
```

**工作原理：**
```
指令:  0xb9400108
掩码:  0xffc00000
结果:  0xb9400000  ← 匹配！

指令 & 掩码 == 模式 & 掩码 → 匹配成功
```

---

## 🛠️ 第三周：硬件实践作业

### 作业 1：查看设备上的安全组件

```bash
# 列出内核中的安全相关 kext
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "/binpack/usr/local/bin/jtool2 -k \
   /System/Library/Caches/com.apple.kernelcaches/kernelcache" | \
   grep -iE 'amfi|sandbox|trust|security'
```

**预期输出：**
```
0xfffffff00582e4c0:com.apple.kext.CoreTrust
0xfffffff00582f300:com.apple.driver.AppleMobileFileIntegrity
0xfffffff005d76840:com.apple.security.sandbox
0xfffffff005ea6ec0:com.apple.security.AppleImage4
```

**记录你的结果：**
| Kext | 地址 | 功能 |
|------|------|------|
| AppleMobileFileIntegrity | | |
| CoreTrust | | |
| sandbox | | |
| AppleImage4 | | |

---

### 作业 2：分析 AMFI 守护进程

```bash
# 查看 amfid 进程
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "ps aux | grep amfid"

# 查看 amfid 的 entitlements
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "/binpack/usr/local/bin/jtool2 --ent /usr/libexec/amfid"

# 查看 amfid 的代码签名
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "/binpack/usr/local/bin/jtool2 --sig /usr/libexec/amfid"
```

**思考题：**
1. amfid 是用户态还是内核态进程？
2. 它和内核中的 AMFI kext 是什么关系？
3. 为什么 KPF 要补丁内核而不是 amfid？

---

### 作业 3：检查代码签名状态

```bash
# 查看代码签名相关的 sysctl 参数
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "sysctl -a | grep -E 'cs_|amfi'"

# 查看 MAC 策略执行状态
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "sysctl security.mac"
```

**记录关键参数：**
| 参数 | 值 | 含义 |
|------|-----|------|
| vm.cs_force_kill | | |
| vm.cs_force_hard | | |
| security.mac.proc_enforce | | |
| security.mac.vnode_enforce | | |

---

### 作业 4：分析 KPF 源码

打开 `checkra1n_research/pongoOS/checkra1n/kpf/main.c`

**任务 1：找到所有补丁函数**

列出所有 `kpf_*_callback` 函数：
```
1. kpf_amfi_callback -
2. kpf_mac_mount_callback -
3. kpf_mac_vm_map_protect_callback -
4. kpf_conversion_callback -
5. (继续列出...)
```

**任务 2：分析一个补丁的模式匹配**

选择 `kpf_amfi_patch` 函数，回答：
1. 它搜索的指令模式是什么？
2. 掩码的作用是什么？
3. 找到后做了什么修改？

---

### 作业 5：理解 XNU 内核结构

```bash
# 查看 kernelcache 的段结构
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "/binpack/usr/local/bin/jtool2 -l \
   /System/Library/Caches/com.apple.kernelcaches/kernelcache" | head -40
```

**记录关键段：**
| 段名 | 起始地址 | 大小 | 用途 |
|------|----------|------|------|
| __TEXT | | | 代码 (只读) |
| __TEXT_EXEC | | | 可执行代码 |
| __DATA | | | 数据 (可读写) |
| __DATA_CONST | | | 常量数据 |
| __PRELINK_TEXT | | | kext 代码 |

**思考题：**
1. KPF 主要修改哪个段？
2. 为什么 __TEXT_EXEC 和 __TEXT 要分开？

---

### 作业 6：追踪沙盒配置

```bash
# 查看沙盒配置文件
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "ls -la /System/Library/Sandbox/Profiles/"

# 读取一个沙盒配置
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "cat /System/Library/Sandbox/Profiles/com.apple.homed.sb" | head -50
```

**分析沙盒规则：**
1. 沙盒配置文件使用什么语法？
2. `(deny default)` 是什么意思？
3. `(allow file-read*)` 是什么意思？

---

### 作业 7：对比 XNU 源码和 KPF 补丁

**任务：** 在 XNU 源码中找到 KPF 补丁对应的代码

1. 打开 `xnu/bsd/kern/kern_codesigning.c`
2. 搜索 `CS_AMFI` 相关代码
3. 理解原始的安全检查逻辑

```bash
# 在 XNU 源码中搜索
grep -r "CS_AMFI" /Users/jqwang/185-苹果越狱后/xnu/bsd/kern/
```

**对比：**
| 原始代码 | KPF 修改 |
|----------|----------|
| 检查签名有效性 | 直接返回有效 |
| 检查信任缓存 | 直接返回在缓存中 |

---

### 作业 8：实践 - 验证越狱效果

```bash
# 1. 验证可以访问根目录
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "ls -la /"

# 2. 验证可以写入系统目录 (小心操作!)
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "touch /tmp/test_write && echo 'Write OK' && rm /tmp/test_write"

# 3. 查看 Cydia 的特殊权限
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "/binpack/usr/local/bin/jtool2 --ent /Applications/Cydia.app/Cydia"

# 4. 验证未签名代码可以运行
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "ls -la /binpack/usr/local/bin/"
```

**记录：**
- [ ] 可以列出根目录
- [ ] 可以写入临时文件
- [ ] Cydia 有 platform-application entitlement
- [ ] /binpack 中的工具可以运行

---

## 📝 阶段 2 总结检查清单

完成所有作业后，确认你能回答以下问题：

- [ ] pongoOS 是什么？它在启动链中的位置？
- [ ] KPF 的工作原理是什么？
- [ ] AMFI 补丁做了什么？
- [ ] mac_mount 补丁的作用是什么？
- [ ] vm_map_protect 补丁为什么重要？
- [ ] tfp0 是什么？为什么需要它？
- [ ] 模式匹配是如何工作的？
- [ ] XNU 内核的主要段有哪些？

---

## 🔗 参考资源

### 必读源码
- `pongoOS/src/kernel/entry.c` - pongoOS 入口
- `pongoOS/checkra1n/kpf/main.c` - KPF 核心
- `xnu/bsd/kern/kern_codesigning.c` - XNU 代码签名
- `xnu/security/mac_vfs.c` - MAC 策略

### 推荐阅读
- iOS Kernel Exploitation (Stefan Esser)
- Mac OS X Internals (Jonathan Levin)
- *OS Internals (Jonathan Levin)

---

## ➡️ 下一阶段预告

**阶段 3：越狱后环境与 Tweak 开发**

学习内容：
- Cydia Substrate / Substitute 原理
- 函数 Hook 技术
- Tweak 开发入门
- 逆向工程基础

---

*文档版本: 1.0*
*创建日期: 2026-02-02*
*适用设备: iPhone X (A11/T8015) iOS 12.3.1*
