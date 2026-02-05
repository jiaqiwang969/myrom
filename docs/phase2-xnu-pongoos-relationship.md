# 阶段 2：XNU（源码）↔ kernelcache（内核镜像）↔ pongoOS（KPF）的关系

你现在看到的这条链路：

SecureROM → checkm8 → pongoOS →（内存中打补丁）→ XNU kernelcache → iOS

可以用一句话概括：**pongoOS 不是 XNU 的一部分，它是一个“在 XNU 启动前运行的 pre-boot 环境”，负责解析并修改 iBoot 已加载到内存的 kernelcache，然后把控制权交回给被修改后的内核。**

---

## 1) pongoOS 在哪里“插入”到 XNU 启动流程里？

- `checkra1n_research/pongoOS/src/kernel/entry.c:252`：
  `BOOT_FLAG_HOOK` 分支里会调用 `xnu_hook()`，这是“开始内核补丁”的入口。
- `checkra1n_research/pongoOS/src/drivers/xnu/xnu.c:1293`：
  `xnu_hook()` 本身只做一件事：如果 `preboot_hook` 被某个模块设置了，就调用它。

结论：**真正的 KPF（Kernel Patch Finder / kernel patch set）逻辑在“pongoOS 模块”里，通过设置 `preboot_hook` 挂进来。**

> 备注：本仓库里只有 patchfinder/工具链（`drivers/xnu`），没有 checkra1n 私有的具体 KPF patch 列表，所以你找不到 “patch AMFI / patch sandbox” 的实现文件，但能完整看到它依赖的 API。

---

## 2) pongoOS 怎么“认识”XNU？（它不是靠源码，而是靠解析 kernelcache Mach-O）

关键点：iOS 内核不是把源码带进设备里跑，而是 **iBoot 把编译好的 kernelcache（Mach-O + 预链接 kext）加载到内存**。

pongoOS 的 `drivers/xnu` 做了这些基础工作：

- 找到 kernelcache 的 Mach-O header：
  `checkra1n_research/pongoOS/src/drivers/xnu/xnu.c:341` (`xnu_header`)
- 解析 Mach-O 段/节（定位 `__TEXT`, `__TEXT_EXEC`, `__PRELINK_INFO` 等）：
  `checkra1n_research/pongoOS/src/drivers/xnu/xnu.c:356` (`macho_get_segment`)
  `checkra1n_research/pongoOS/src/drivers/xnu/xnu.c:370` (`macho_get_section`)
- 处理 KASLR slide / rebase 差异（不同年代 kernelcache 行为不同）：
  `checkra1n_research/pongoOS/src/drivers/xnu/xnu.c:412` (`has_been_rebased`)
  `checkra1n_research/pongoOS/src/drivers/xnu/xnu.c:431` (`xnu_rebase_va`)
- 按 bundle id 找预链接 kext 的 header：
  `checkra1n_research/pongoOS/src/drivers/xnu/xnu.c:491` (`xnu_pf_get_kext_header`)
- 对每个 kext 的 `__TEXT_EXEC,__text` 应用 patchset：
  `checkra1n_research/pongoOS/src/drivers/xnu/xnu.c:565` (`xnu_pf_apply_each_kext`)

---

## 3) KPF（模块）是怎么打补丁的？

pongoOS 暴露了一套“在内存里做二进制 pattern match → 修改指令/数据”的 API：

- 创建 patchset：
  `checkra1n_research/pongoOS/src/drivers/xnu/xnu.c:609` (`xnu_pf_patchset_create`)
- 典型匹配器：
  `checkra1n_research/pongoOS/src/drivers/xnu/xnu.c:733` (`xnu_pf_maskmatch`)
  `checkra1n_research/pongoOS/src/drivers/xnu/xnu.c:771` (`xnu_pf_ptr_to_data`)
- JIT 加速匹配循环（对应汇编模板）：
  `checkra1n_research/pongoOS/src/drivers/xnu/xnu.c:1052` (`xnu_pf_emit`)
  `checkra1n_research/pongoOS/src/drivers/xnu/xnu.S:1`（pf_jit_* 模板）
- 应用 patchset 到某个内存范围：
  `checkra1n_research/pongoOS/src/drivers/xnu/xnu.c:1238` (`xnu_pf_apply`)

这些符号会被导出给模块使用：
`checkra1n_research/pongoOS/src/dynamic/modload.c:1422`

---

## 4) XNU 源码在这里的“价值”是什么？

KPF 补丁是对“二进制内核镜像”做的，但你需要源码来回答两个问题：

1) 这个函数/检查点在做什么？（语义）
2) patch 掉它会造成什么副作用？（行为变化）

举两个你截图里提到的典型点：

- “Found mac_mount”
  对应 XNU 里的 mount syscall 路径（带 MACF 标签版本）：
  `xnu/bsd/vfs/vfs_syscalls.c:918` (`__mac_mount`)

- “Found AMFI”
  真实的 AMFI 强制逻辑主要在 **AppleMobileFileIntegrity kext（闭源）**，但 XNU 内核里有 AMFI 的接口挂点：
  `xnu/libkern/amfi/amfi.c:8` (`amfi_interface_register`)

同理：
- sandbox 是一个 MAC policy（kext 里实现），XNU 里提供 MACF 框架与 hook 点；
- CoreTrust / Image4 相关更多在闭源组件里，但 kernelcache 里可见其 kext，KPF 会按 bundle id 找到并 patch。

---

## 5) 建议的“读代码路线”（最贴近 checkra1n 机制）

1) 先看 pongoOS 的插入点与 hook：
   `checkra1n_research/pongoOS/src/kernel/entry.c:252`
   `checkra1n_research/pongoOS/src/drivers/xnu/xnu.c:1293`
2) 再看 pongoOS 如何定位 kernelcache / kext：
   `checkra1n_research/pongoOS/src/drivers/xnu/xnu.c:341`
   `checkra1n_research/pongoOS/src/drivers/xnu/xnu.c:491`
3) 最后用 XNU 源码补齐“被 patch 的点到底干了什么”：
   从你在日志里看到的 patch 名称（mac_mount / cs_enforcement / sandbox / amfi）去 `xnu/` 里定位对应源码。

