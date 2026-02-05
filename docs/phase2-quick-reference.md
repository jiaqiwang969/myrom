# 阶段 2 快速参考卡片

> pongoOS 与 KPF 关键信息速查表

---

## 🚀 启动链对比

```
正常启动：
┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐
│SecureROM │ → │  iBoot   │ → │   XNU    │ → │   iOS    │
└──────────┘   └──────────┘   └──────────┘   └──────────┘

checkra1n 越狱：
┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐
│SecureROM │ → │ checkm8  │ → │ pongoOS  │ → │补丁 XNU  │ → │越狱 iOS  │
└──────────┘   └──────────┘   └──────────┘   └──────────┘   └──────────┘
                                   ↑
                              KPF 在这里工作
```

---

## 📂 关键文件路径

### pongoOS 源码
```
checkra1n_research/pongoOS/
├── src/kernel/entry.c           ← pongoOS 入口点
├── src/kernel/mm.c              ← 内存管理
├── src/drivers/xnu/xnu.c        ← XNU 操作
└── checkra1n/kpf/main.c         ← ★ KPF 核心 (最重要!)
```

### XNU 源码 (对照分析)
```
xnu/
├── bsd/kern/kern_codesigning.c  ← 代码签名
├── bsd/kern/kern_cs.c           ← CS 验证
├── bsd/kern/kern_trustcache.c   ← 信任缓存
└── security/mac_vfs.c           ← MAC 策略
```

---

## 🔧 KPF 主要补丁速查

| 补丁名 | 目标 | 效果 | 关键函数 |
|--------|------|------|----------|
| **AMFI** | 代码签名检查 | 允许未签名代码运行 | `kpf_amfi_callback` |
| **mac_mount** | 根文件系统保护 | 允许 remount / | `kpf_mac_mount_callback` |
| **vm_map_protect** | W^X 内存保护 | 允许 W+X 内存 | `kpf_mac_vm_map_protect_callback` |
| **task_conversion** | tfp0 保护 | 允许获取内核端口 | `kpf_conversion_callback` |
| **dounmount** | 卸载保护 | 允许卸载根文件系统 | `kpf_mac_dounmount_callback` |
| **dyld** | 动态链接器路径 | 允许自定义 dyld | `kpf_dyld_callback` |

---

## 🛡️ 安全组件对照表

### 内核态 (Kext)
| Bundle ID | 功能 |
|-----------|------|
| `com.apple.driver.AppleMobileFileIntegrity` | AMFI - 代码签名验证 |
| `com.apple.kext.CoreTrust` | 信任缓存管理 |
| `com.apple.security.sandbox` | 沙盒策略执行 |
| `com.apple.security.AppleImage4` | 安全启动验证 |

### 用户态 (Daemon)
| 进程 | 路径 | 功能 |
|------|------|------|
| amfid | /usr/libexec/amfid | AMFI 用户态助手 |
| trustd | /usr/libexec/trustd | 证书信任评估 |
| securityd | /usr/libexec/securityd | 安全服务 |

---

## 💻 常用命令

### 分析内核
```bash
# 查看 kernelcache 结构
jb "/binpack/usr/local/bin/jtool2 -l /System/Library/Caches/com.apple.kernelcaches/kernelcache"

# 列出所有 kext
jb "/binpack/usr/local/bin/jtool2 -k /System/Library/Caches/com.apple.kernelcaches/kernelcache"

# 查找安全相关 kext
jb "/binpack/usr/local/bin/jtool2 -k /System/Library/Caches/com.apple.kernelcaches/kernelcache" | grep -iE 'amfi|sandbox|trust'
```

### 分析二进制
```bash
# 查看 entitlements
jb "/binpack/usr/local/bin/jtool2 --ent /path/to/binary"

# 查看代码签名
jb "/binpack/usr/local/bin/jtool2 --sig /path/to/binary"

# 查看 Mach-O 结构
jb "/binpack/usr/local/bin/jtool2 -l /path/to/binary"
```

### 检查系统状态
```bash
# 代码签名状态
jb "sysctl vm.cs_force_kill vm.cs_force_hard"

# MAC 策略状态
jb "sysctl security.mac"

# 安全进程
jb "ps aux | grep -E 'amfi|trustd|securityd'"
```

---

## 🔍 模式匹配原理

```c
// KPF 使用掩码匹配找到目标代码

// 要搜索的指令模式
uint64_t matches[] = {
    0x91000000,  // ADD 指令
    0x52800200,  // MOV W*, 0x16
};

// 掩码 (1 = 必须匹配, 0 = 忽略)
uint64_t masks[] = {
    0xFF000000,  // 只匹配操作码
    0xFFFFFF00,  // 匹配操作码和立即数
};

// 匹配逻辑:
// (指令 & 掩码) == (模式 & 掩码) → 匹配成功
```

---

## 📝 ARM64 补丁指令

| 指令 | 机器码 | 用途 |
|------|--------|------|
| `NOP` | `0xd503201f` | 空操作，跳过检查 |
| `RET` | `0xd65f03c0` | 返回 |
| `MOV X0, #0` | `0xd2800000` | 返回 false |
| `MOV X0, #1` | `0xd2800020` | 返回 true |
| `MOV X8, XZR` | `0xaa1f03e8` | 清零寄存器 |
| `CMP XZR, XZR` | `0xeb1f03ff` | 永远相等 |

---

## 🎯 补丁效果对照

### AMFI 补丁
```
修改前: 检查签名 → 无效 → 拒绝执行
修改后: 检查签名 → 直接返回有效 → 允许执行
```

### mac_mount 补丁
```
修改前: mount -uw / → 检查 MNT_ROOTFS → 拒绝
修改后: mount -uw / → 检查被跳过 → 允许
```

### vm_map_protect 补丁
```
修改前: 请求 W+X 内存 → 检查 → 拒绝
修改后: 请求 W+X 内存 → 检查被跳过 → 允许
```

### tfp0 补丁
```
修改前: task_for_pid(0) → 权限检查 → 拒绝
修改后: task_for_pid(0) → 检查被绕过 → 返回内核端口
```

---

## 📊 XNU 内核段结构

| 段名 | 权限 | 内容 |
|------|------|------|
| `__TEXT` | R-- | 只读数据、字符串 |
| `__TEXT_EXEC` | R-X | 可执行代码 ← KPF 主要修改这里 |
| `__DATA_CONST` | R-- | 只读常量 |
| `__DATA` | RW- | 可读写数据 |
| `__PRELINK_TEXT` | R-X | Kext 代码 |
| `__PRELINK_INFO` | R-- | Kext 信息 |

---

## 🔑 关键概念速记

| 术语 | 全称 | 一句话解释 |
|------|------|------------|
| **KPF** | Kernel Patchfinder | 在内核中找到并修改安全检查代码 |
| **AMFI** | Apple Mobile File Integrity | 检查代码签名的内核组件 |
| **tfp0** | task_for_pid(0) | 获取内核任务端口，可读写内核内存 |
| **W^X** | Write XOR Execute | 内存不能同时可写和可执行 |
| **MAC** | Mandatory Access Control | 强制访问控制策略 |
| **Sandbox** | - | 限制 App 只能访问自己的文件 |
| **Trust Cache** | - | 预先信任的代码哈希列表 |

---

## ⚡ 快速验证命令

```bash
# 验证 AMFI 补丁效果 (未签名代码可运行)
jb "ls /binpack/usr/local/bin/"

# 验证 mac_mount 补丁效果 (可以看到根目录)
jb "ls -la /"

# 验证安全进程状态
jb "ps aux | grep amfid"

# 验证代码签名状态
jb "sysctl vm.cs_force_kill"
# 预期: 0 (不强制杀死未签名代码)
```

---

## 🔄 pongoOS 启动流程

```
1. checkm8 exploit 完成
        ↓
2. 加载 pongoOS 到内存
        ↓
3. pongoOS 初始化 (entry.c)
   • 设置异常向量
   • 初始化内存管理
   • 初始化 USB 驱动
   • 显示 checkra1n logo
        ↓
4. 等待内核加载
        ↓
5. KPF 开始工作 (main.c)
   • 扫描 __TEXT_EXEC 段
   • 模式匹配找到目标
   • 逐个打补丁
   • 打印 "KPF: Found XXX"
        ↓
6. 补丁完成，引导内核
        ↓
7. 修改后的内核启动
        ↓
8. iOS 启动 (越狱版)
```

---

*快速参考卡片 v1.0*
*适用于: 阶段 2 - pongoOS 与 KPF 学习*
