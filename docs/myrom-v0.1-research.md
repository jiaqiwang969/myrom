# MyROM v0.1（研究型）— 在 iPhone X（checkra1n）上“从哪开始算数”

这份文档把《Bootstrapping Trust in Commodity Computers》的核心模型，翻译成你当前的启动链现实：

Apple SecureROM（不可改） → checkm8（获得早期执行） → pongoOS（可控早期阶段 = MyROM） → kernelcache（XNU） → iOS

## 0. 定义

- MyROM：你“最早能稳定控制”的启动阶段，以及它承诺做的事情（记录/验证/传递状态）。
- Measured boot（度量式启动）：不一定阻止启动，但会记录“启动了什么”。
- Secure boot（验证式启动）：不符合预期就不让启动。

## 1. 目标（v0.1）

v0.1 先做到两件事：

1) 在 XNU 执行前生成一份 **Boot Manifest**（度量结果 + 决策信息）  
2) 把这份 Manifest 以“后续系统能读取”的方式传下去（给内核/用户态至少一方能读到）

> v0.2 再考虑“验证/阻止”（比如不满足策略就不 boot iOS）。

## 2. 信任边界（说清楚“从哪开始算数”）

- 你无法改变 Apple 的硬件 Root-of-Trust（SecureROM/iBoot 的签名体系）。
- 你能建立的是“研究型逻辑 Root-of-Trust”：**从 pongoOS（或更早一点）开始，你写下的状态就当作 MyROM 的承诺。**

因此 v0.1 的承诺不是“能向第三方证明”（TPM 那种），而是：

- 给你自己/你的工具一个可复现的、可比对的“这次启动到底是什么状态”的答案。

## 3. Boot Manifest（最小数据模型）

建议 v0.1 记录这些字段（足够支撑后续分析与迭代）：

- myrom.version：MyROM 版本号（例如 `0.1.0`）
- device：机型/SoC/构建号（从设备树/boot-args 获取）
- boot.nonce：一次启动的随机值（防止“看起来像旧日志”的混淆）
- kernel.measurement：
  - kernelcache.hash（对“内存中将要执行的 kernelcache”做 hash）
  - kernelcache.slide（KASLR slide）
- patch.measurement：
  - patchset.id（补丁集 ID / git commit / build id）
  - patchset.list（补丁名列表：例如 "amfi", "sandbox", "mount", ...）
- decision：
  - mode：`measure-only` 或 `enforce`
  - allow_boot：true/false（enforce 模式才会用到）

格式建议：JSON 或 TLV（二进制更省空间）；v0.1 用 JSON 最直观。

## 4. “传下去”的两种做法（iPhone 上最实用）

### 方案 A：写入 DeviceTree（推荐）

理由：容量大、结构化、用户态/内核都容易读。

做法思路（与 pongoOS 现有 RAMDisk memmap 类似）：
- 在 pongoOS 分配一块静态内存放 manifest
- 在 devicetree 的 `memory-map` 下新增一个条目（比如 `MyROMManifest`）
- 或新增一个节点 `chosen/myrom`，挂上 `manifest-addr` / `manifest-size` / `manifest-hash`

你可以参考 `checkra1n_research/pongoOS/src/drivers/xnu/xnu.c:1297` 的 `xnu_loadrd()`：
它就是通过 `dt_alloc_memmap()` 往 `memory-map` 里挂 RAMDisk。

### 方案 B：写进 boot-args（备选）

理由：实现简单；缺点：长度受限（尤其 iOS 12 及更早）。

可以只塞一个短标记 + 指针：
- `myrom=1 myrom_manifest=0x... myrom_size=...`

## 5. pongoOS 侧落点（你现在仓库里看得到的“挂钩点”）

- 触发点：`checkra1n_research/pongoOS/src/kernel/entry.c:252`（BOOT_FLAG_HOOK → `xnu_hook()`）
- `xnu_hook()`：`checkra1n_research/pongoOS/src/drivers/xnu/xnu.c:1293`（调用 `preboot_hook`）
- kernelcache 解析与 patch API：`checkra1n_research/pongoOS/src/drivers/xnu/xnu.c`（xnu_pf_*）
- 模块可用 API 导出：`checkra1n_research/pongoOS/src/dynamic/modload.c:1422`

结论：v0.1 只要你写一个 pongoOS 模块，设置 `preboot_hook`，在里面生成 manifest 并写入 DT/boot-args 就够了。

## 6. XNU 源码在这里的“对照价值”

KPF 是对二进制 kernelcache 做 patch，但你需要源码回答：
- 这个检查点在做什么？
- patch 掉它会带来什么行为变化？

例子：
- mount 路径：`xnu/bsd/vfs/vfs_syscalls.c:918`（`__mac_mount`）
- 代码签名/AMFI 配置：`xnu/bsd/kern/kern_codesigning.c`（解析 boot-args，影响 cs config）
- AMFI 接口挂点：`xnu/libkern/amfi/amfi.c:8`（`amfi_interface_register`）

## 7. v0.1 验证方式（不依赖内核改动）

最简单的验证闭环：

1) MyROM（pongoOS 模块）写入 manifest 到 DeviceTree
2) iOS 启动后，用 `ioreg -p IODeviceTree -l` 读出你写的字段
3) 你本机保存每次启动的 manifest，做 diff（看 kernel hash/patchset 是否符合预期）

## 8. 下一步（你选一个）

- 路线 1：`measure-only`（先把 manifest 链路跑通）
- 路线 2：`enforce`（再加策略：不符合就不 boot iOS）

