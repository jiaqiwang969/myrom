# 阶段 1 作业记录表

> 姓名：_____________
> 开始日期：_____________
> 完成日期：_____________

---

## 作业 1：验证设备硬件信息

### 执行结果

```bash
# 命令 1: 获取 chip-id
$ sshpass -p 'alpine' ssh -p 2222 root@localhost "ioreg -p IODeviceTree -l | grep 'chip-id'"

输出：
    | |   "chip-id" = <15800000>


# 命令 2: 获取 board-id
$ sshpass -p 'alpine' ssh -p 2222 root@localhost "ioreg -p IODeviceTree -l | grep 'board-id'"

输出：
    | |   "board-id" = <0e000000>


# 命令 3: 验证 checkra1n 标记
$ sshpass -p 'alpine' ssh -p 2222 root@localhost "ioreg -l | grep checkra1n"

输出：
      | +-o /private/var/checkra1n.dmg@0  <class KDIURL, id 0x10000066b, registered, matched, active, busy 0 (6 ms), retain 6>
      | | |   "image-path" = <"/private/var/checkra1n.dmg">


# 命令 4: 查看内核版本
$ sshpass -p 'alpine' ssh -p 2222 root@localhost "sysctl kern.version"

输出：
Darwin Kernel Version 18.6.0: Thu Apr 25 22:14:08 PDT 2019; root:xnu-4903.262.2~2/RELEASE_ARM64_T8015

```

### 记录

| 项目 | 你的结果 | 预期值 |
|------|----------|--------|
| chip-id | 0x8015 | 0x8015 |
| board-id | 0x0e | 0x0e |
| platform | t8015 | t8015 |
| XNU 版本 | xnu-4903.262.2 | xnu-4903.262.2 |

### 验证状态
- [x] 所有值与预期匹配
- [x] 设备确认为 checkra1n 越狱

---

## 作业 2：分析 checkm8 地址常量

### 地址表填写

| 常量名 | 地址值 | 用途说明 (用自己的话描述) |
|--------|--------|--------------------------|
| LOAD_ADDRESS | 0x18001C000 | SecureROM/DFU 阶段用于布置 ROP 回调数据/页表/跳板等的 SRAM 基址（T8015 的固定内存布局点）。 |
| gUSBDescriptors | 0x180008528 | SecureROM 中 USB 描述符指针表地址；checkm8 会把它改成指向自定义的 `USB_DESCRIPTOR`。 |
| gUSBSerialNumber | 0x180003A78 | SecureROM 中 USB 序列号字符串缓存地址；checkm8 在末尾追加 `PWND:[checkm8]` 标记。 |
| usb_create_string_descriptor | 0x10000AE80 | SecureROM 的函数：生成/更新 USB string descriptor（让修改后的序列号对主机生效）。 |
| PAYLOAD_DEST | 0x18001BC00 | SRAM 中用于落地 payload/handler 的写入目标地址（把后续代码复制到这里供执行）。 |
| USB_CORE_DO_IO | 0x10000B9A8 | SecureROM USB 核心 I/O 入口（后续 USB handler/shellcode 会调用它收发/处理请求）。 |
| handle_interface_request | 0x10000BCCC | SecureROM 处理 USB interface request 的函数；checkm8 通过 trampoline/覆盖把控制流导向自定义 handler。 |
| write_sctlr_gadget | 0x1000003EC | ROP gadget：写 `SCTLR_EL1`（配置 MMU/缓存/权限相关控制位）。 |
| write_ttbr0 | 0x10000045C | ROP gadget：写 `TTBR0_EL1`（切换页表基址），配合 `TLBI` 使新映射生效。 |

### 思考题回答

**Q1: 为什么 ROM 区域 (0x100000000) 的地址和 SRAM 区域 (0x180000000) 不同？**

你的回答：
```
它们是 SecureROM 固定的两段不同内存映射：ROM 是芯片内置只读代码区（不可写、内容稳定），SRAM 是片上可读写内存（可写、用于临时数据/栈/payload）。由于硬件属性不同，BootROM 把它们映射到不同的地址范围，便于区分与保护。

```

**Q2: gadget 地址为什么都在 ROM 区域？**

你的回答：
```
ROP gadget 本质上是“已经存在的指令片段”。在 checkm8 里需要可预测、跨重启稳定的指令地址，因此从不可修改且地址固定的 ROM（BootROM 代码）里挑 gadget 最可靠；SRAM 内容可变且我们需要写入 payload，不能指望其中天然存在稳定 gadget。

```

**Q3: PAYLOAD_DEST 为什么在 SRAM 区域？**

你的回答：
```
payload 需要先写入再执行，而 ROM 只读无法写入，所以必须选择 SRAM 这种可写区域作为落地点；写入后通过 cache flush / I-cache invalidate 让 CPU 取到新指令即可执行。

```

---

## 作业 3：追踪 exploit 执行流程

### 执行结果

```bash
# 命令 1: 检查 USB 序列号
$ sshpass -p 'alpine' ssh -p 2222 root@localhost "ioreg -l | grep -i 'serial' | head -5"

输出：
（原命令可能会刷到很长的 IOKitDiagnostics，这里只保留与 serial 相关的关键字段）
    |   "IOPlatformSerialNumber" = "G6TW3T64JCL8"
    |   "serial-number" = <47365457335436344a434c380000000000000000000000000000000000000000>
    |   "mlb-serial-number" = <4732433830323630363835485035514100000000000000000000000000000000>


# 命令 2: 检查 checkra1n ramdisk 挂载
$ sshpass -p 'alpine' ssh -p 2222 root@localhost "mount | grep -E 'checkra1n|disk4|disk5'"

输出：
/dev/disk4 on /binpack (hfs, local, nosuid, read-only, union)
/dev/disk5 on private/var/binpack (hfs, local, nosuid, read-only)


# 命令 3: 查看 checkra1n 提供的工具
$ sshpass -p 'alpine' ssh -p 2222 root@localhost "ls -la /binpack/usr/local/bin/"

输出：
total 2140
drwxr-xr-x 2 root wheel    272 May  8  2021 .
drwxr-xr-x 3 root wheel    102 May  8  2021 ..
-rwxr-xr-x 1 root wheel  52800 May  8  2021 filemon
-rwxr-xr-x 1 root wheel 555456 May  8  2021 jtool
-rwxr-xr-x 1 root wheel 834672 May  8  2021 jtool2
-rwxr-xr-x 1 root wheel  55200 May  8  2021 lsdtrip.arm64
-rwxr-xr-x 1 root wheel  54912 May  8  2021 netbottom
-rwxr-xr-x 1 root wheel 628304 May  8  2021 procexp


# 命令 4: 使用 jtool2 分析系统二进制
$ sshpass -p 'alpine' ssh -p 2222 root@localhost "/binpack/usr/local/bin/jtool2 -l /bin/ls | head -20"

输出：
LC 00: LC_SEGMENT_64         	 Mem: 0x000000000-0x100000000	__PAGEZERO
LC 01: LC_SEGMENT_64         	 Mem: 0x100000000-0x100028000	__TEXT
	Mem: 0x100005484-0x100022c48		__TEXT.__text	(Normal)
	Mem: 0x100022c48-0x1000231d0		__TEXT.__stubs	(Symbol Stubs)
	Mem: 0x1000231d0-0x100023770		__TEXT.__stub_helper	(Normal)
	Mem: 0x100023770-0x100024e24		__TEXT.__const	
	Mem: 0x100024e24-0x100027cd8		__TEXT.__cstring	(C-String Literals)
	Mem: 0x100027cd8-0x100027ff4		__TEXT.__unwind_info	
LC 02: LC_SEGMENT_64         	 Mem: 0x100028000-0x10002c000	__DATA
	Mem: 0x100028000-0x100028058		__DATA.__got	(Non-Lazy Symbol Ptrs)
	Mem: 0x100028058-0x100028408		__DATA.__la_symbol_ptr	(Lazy Symbol Ptrs)
	Mem: 0x100028410-0x100028e60		__DATA.__const	
	Mem: 0x100028e60-0x100029098		__DATA.__data	
	Mem: 0x1000290a0-0x10002a2b8		__DATA.__bss	(Zero Fill)
	Mem: 0x10002a2b8-0x10002a2d8		__DATA.__common	(Zero Fill)
LC 03: LC_SEGMENT_64         	 Mem: 0x10002c000-0x100034000	__LINKEDIT
LC 04: LC_DYLD_INFO          	
	   Rebase info: 72    bytes at offset 180224 (0x2c000-0x2c048)
	   Bind info:   160   bytes at offset 180296 (0x2c048-0x2c0e8)

```

### 观察记录

1. 是否看到 PWND 标记？ [ ] 是 [x] 否

2. checkra1n ramdisk 挂载点是什么？
   ```
/binpack
private/var/binpack
   ```

3. /binpack 中有哪些有用的工具？列出 5 个：
   ```
   1. filemon
   2. jtool
   3. jtool2
   4. lsdtrip.arm64
   5. netbottom
   ```

---

## 作业 4：分析 ARM64 shellcode

### 源码阅读

文件路径：`checkra1n_research/ipwndfu/src/checkm8_arm64.S`

### 问题回答

**Q1: PWND_STRING 的内容是什么？它被追加到哪里？**

你的回答：
```
`PWND_STRING` 的内容是：`" PWND:[checkm8]"`（注意前面有一个空格）。

代码先在 `gUSBSerialNumber` 指向的序列号字符串末尾找到 `\\0`，然后把 `PWND_STRING` 直接拷贝追加到末尾；接着调用 `usb_create_string_descriptor` 生成新的 string descriptor，让主机重新读取后能看到 `PWND` 标记。

```

**Q2: 为什么需要执行 DC CIVAC 和 DSB SY？**

你的回答：
```
因为 payload 是“先写入内存、后当作指令执行”。ARM 上 D-cache/I-cache 不一定自动一致：写入可能仍停留在 D-cache，而取指可能还看到旧内容。

`DC CIVAC` 把刚写入的 cache line 清理并失效到一致性点（PoC/PoU 相关），`DSB SY` 确保这些 cache 维护操作在继续之前已经完成（强制顺序与完成）。

```

**Q3: SYS #0, c7, c5, #0 这条指令的作用是什么？**

你的回答：
```
它等价于 `IC IALLU`（Invalidate All Instruction Caches to PoU）：使 I-cache 全部失效，确保接下来取指会从内存（统一点）看到刚写入的新 payload；随后用 `DSB SY` + `ISB` 保证完成与流水线同步。

```

### 验证结果

```bash
# 检查 USB 序列号是否包含 PWND 字符串
$ sshpass -p 'alpine' ssh -p 2222 root@localhost "ioreg -l | grep -i pwnd"

输出：
（当前处于 iOS 系统环境，未观察到 `PWND` 输出；该标记通常出现在 SecureROM DFU 模式下的 USB 序列号里）

```

---

## 作业 5：理解 ROP 链

### ROP 链执行流程图

请在下方绘制完整的 ROP 链流程：

```
开始
  │
  ▼
┌─────────────────────┐
│ DC CIVAC (flush D$) │
│ 0x18001C800/840/880 │
└─────────────────────┘
  │
  ▼
┌─────────────────────┐
│ DMB SY (barrier)    │
└─────────────────────┘
  │
  ▼
┌─────────────────────┐
│ write SCTLR_EL1     │
│ = 0x100D (WXN=0)    │
└─────────────────────┘
  │
  ▼
┌─────────────────────┐
│ load_write_gadget   │
│ 写入/准备页表与回调 │
│ (0x18001C000/010/20)│
└─────────────────────┘
  │
  ▼
┌─────────────────────┐
│ write TTBR0_EL1     │
│ = 0x180020000       │
└─────────────────────┘
  │
  ▼
┌─────────────────────┐
│ TLBI (flush TLB)    │
└─────────────────────┘
  │
  ▼
┌─────────────────────┐
│ write TTBR0_EL1     │
│ = 0x18000C000       │
└─────────────────────┘
  │
  ▼
┌─────────────────────┐
│ TLBI (flush TLB)    │
└─────────────────────┘
  │
  ▼
┌─────────────────────┐
│ 跳转到 0x18001C800  │
└─────────────────────┘
  │
  ▼
┌─────────────────────┐
│ 执行 shellcode      │
└─────────────────────┘
```

### 思考题回答

**Q1: 为什么要禁用 WXN？如果不禁用会怎样？**

你的回答：
```
WXN（Write eXecute Never）会使“可写内存”默认不可执行。checkm8 需要把 payload 写到 SRAM（可写）后再执行，因此要把 WXN 关掉/或建立可执行映射；否则跳转到 payload 时通常会触发指令异常（instruction abort），导致链条中断、无法执行 shellcode。

```

**Q2: 为什么要修改 TTBR0？**

你的回答：
```
`TTBR0_EL1` 是低地址空间的页表基址。修改它等于切换到我们控制/期望的页表，从而改变虚拟地址到物理地址的映射与权限（例如让 SRAM 区域可执行、满足 ROP/跳转需要）。不切换页表时，payload 所在区域可能没有合适的权限或映射。

```

**Q3: 为什么要执行 TLBI？**

你的回答：
```
CPU 会把地址翻译结果缓存到 TLB。即使你改了 `TTBR0_EL1` 或页表内容，旧的翻译/权限可能仍在 TLB 里。执行 `TLBI` 可以让旧缓存失效，确保后续取指/访问使用新的映射与权限；否则可能仍按旧映射走，出现 fault 或权限不生效的问题。

```

---

## 作业 6：对比不同芯片的配置

### 配置对比表

| 项目 | T8010 (A10) | T8011 (A10X) | T8015 (A11) |
|------|-------------|--------------|-------------|
| LOAD_ADDRESS | 0x1800B0000 | 0x1800B0000 | 0x18001C000 |
| USB_CORE_DO_IO | 0x10000DC98 | 0x10000DD64 | 0x10000B9A8 |
| PAYLOAD_DEST | 0x1800AFC00 | 0x1800AFC00 | 0x18001BC00 |
| func_gadget | 0x10000CC4C | 0x10000CCEC | 0x10000A9AC |
| hole 值 | 5 | 6 | 6 |
| leak 值 | 1 | 1 | 1 |

### 思考题回答

**Q1: 为什么不同芯片的地址不同？**

你的回答：
```
不同芯片（以及不同 iBoot/SecureROM 版本）的 BootROM 二进制与内存布局不同：同名全局变量/函数在 ROM/SRAM 中的编译链接地址会变化，SRAM 预留区域也可能不同；因此每个 CPID/版本都需要单独的地址常量表。

```

**Q2: hole 和 leak 值的含义是什么？**

你的回答：
```
它们是 checkm8 里“堆布局调参”的次数：

- `hole`：在第一次 `stall()` 之后执行 `no_leak()` 的次数，用来制造特定大小/位置的“空洞”（heap feng shui）。
- `leak`：第二阶段里执行 `usb_req_leak()` 的次数，用来触发/稳定需要的分配泄漏与复用，使覆盖发生在正确的对象上。

```

**Q3: 这些值是如何确定的？**

你的回答：
```
主要靠对每个芯片/BootROM 的 USB 请求分配行为进行分析与反复实验（trial-and-error + 调试）：通过观测 UAF 触发后哪些对象会被复用、需要多大/多少次分配才能把目标结构放进“洞”里，从而找到能稳定成功的 `hole/leak` 组合。

```

---

## 作业 7：使用 jtool2 分析 kernelcache

### 执行结果

```bash
# 命令 1: 查看 kernelcache 头信息
$ sshpass -p 'alpine' ssh -p 2222 root@localhost "/binpack/usr/local/bin/jtool2 -h /System/Library/Caches/com.apple.kernelcaches/kernelcache"

输出：
Magic:	64-bit MachO (Little Endian)
Type:	executable
CPU:	ARM64 (ARMv8)
Cmds:	22
Size:	4200
Flags:	0x200001


# 命令 2: 列出所有内核扩展
$ sshpass -p 'alpine' ssh -p 2222 root@localhost "/binpack/usr/local/bin/jtool2 -k /System/Library/Caches/com.apple.kernelcaches/kernelcache" | head -30

输出：
0xfffffff005804000:com.apple.kpi.mach
0xfffffff005804080:com.apple.kpi.private
0xfffffff005804100:com.apple.kpi.unsupported
0xfffffff005804180:com.apple.kpi.iokit
0xfffffff005804200:com.apple.kpi.libkern
0xfffffff005804280:com.apple.kpi.bsd
0xfffffff005804300:com.apple.iokit.IONetworkingFamily
0xfffffff005805e40:com.apple.iokit.IOTimeSyncFamily
0xfffffff005809700:com.apple.iokit.IOSlowAdaptiveClockingFamily
0xfffffff005809c80:com.apple.iokit.IOStorageFamily
0xfffffff00580af00:com.apple.iokit.IOReportFamily
0xfffffff00580b700:com.apple.driver.AppleARMPlatform
0xfffffff005814f80:com.apple.driver.AppleSamsungSPI
0xfffffff005815f00:com.apple.kpi.dsep
0xfffffff005815f80:com.apple.kec.corecrypto
0xfffffff00582e4c0:com.apple.kext.CoreTrust
0xfffffff00582f300:com.apple.driver.AppleMobileFileIntegrity
0xfffffff005832e80:com.apple.iokit.IOHIDFamily
0xfffffff005834b40:com.apple.driver.AppleEmbeddedLightSensor
0xfffffff0058385c0:com.apple.driver.AppleS5L8920XPWM
0xfffffff005838b40:com.apple.driver.corecapture
0xfffffff00583c080:com.apple.driver.AppleBluetoothDebugService
0xfffffff00583c5c0:com.apple.driver.AppleBluetoothDebug
0xfffffff00583f000:com.apple.driver.IOSlaveProcessor
0xfffffff00583f580:com.apple.driver.AppleInputDeviceSupport
0xfffffff005840700:com.apple.driver.AppleFirmwareUpdateKext
0xfffffff0058434c0:com.apple.driver.usb.AppleUSBCommon
0xfffffff005843f00:com.apple.driver.AppleUSBHostMergeProperties
0xfffffff0058444c0:com.apple.iokit.IOUSBDeviceFamily
0xfffffff005848a40:com.apple.iokit.IOSerialFamily


# 命令 3: 找到安全相关的 kext
$ sshpass -p 'alpine' ssh -p 2222 root@localhost "/binpack/usr/local/bin/jtool2 -k /System/Library/Caches/com.apple.kernelcaches/kernelcache" | grep -iE 'amfi|sandbox|trust|security'

输出：
0xfffffff00582e4c0:com.apple.kext.CoreTrust
0xfffffff005d76840:com.apple.security.sandbox
0xfffffff005ea6ec0:com.apple.security.AppleImage4


# 命令 4: 查看 Cydia 的 entitlements
$ sshpass -p 'alpine' ssh -p 2222 root@localhost "/binpack/usr/local/bin/jtool2 --ent /Applications/Cydia.app/Cydia"

输出：
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.CommCenter.fine-grained</key>
	<array>
		<string>spi</string>
	</array>
	<key>com.apple.coreaudio.allow-amr-decode</key>
	<true/>
	<key>com.apple.coremedia.allow-protected-content-playback</key>
	<true/>
	<key>com.apple.managedconfiguration.profiled-access</key>
	<true/>
	<key>com.apple.private.security.no-container</key>
	<true/>
	<key>com.apple.private.skip-library-validation</key>
	<true/>
	<key>com.apple.frontboard.launchapplications</key>
	<true/>
	<key>com.apple.frontboard.shutdown</key>
	<true/>
	<key>com.apple.springboard.launchapplications</key>
	<true/>
	<key>com.apple.springboard.opensensitiveurl</key>
	<true/>
	<key>keychain-access-groups</key>
	<array>
		<string>com.apple.cfnetwork</string>
		<string>com.apple.identities</string>
		<string>com.apple.mobilesafari</string>
	</array>
	<key>com.apple.security.iokit-user-client-class</key>
	<array>
		<string>AGXDeviceUserClient</string>
		<string>IOHDIXControllerUserClient</string>
		<string>IOSurfaceRootUserClient</string>
	</array>
	<key>platform-application</key>
	<true/>
</dict>
</plist>

```

### 安全相关 kext 记录

| 序号 | Kext Bundle ID | 推测功能 |
|------|----------------|----------|
| 1 | com.apple.driver.AppleMobileFileIntegrity | AMFI：代码签名/信任校验、限制未授权代码注入与加载。 |
| 2 | com.apple.kext.CoreTrust | CoreTrust：证书链与签名信任评估（和 AMFI 配合）。 |
| 3 | com.apple.security.sandbox | Sandbox：进程沙盒与 MAC 策略限制。 |
| 4 | com.apple.security.AppleImage4 | Image4：启动链/固件镜像（Image4）验证相关。 |

### Cydia entitlements 分析

列出 Cydia 拥有的关键 entitlements：
```
1. platform-application
2. com.apple.private.security.no-container
3. com.apple.private.skip-library-validation
4. com.apple.springboard.launchapplications / com.apple.frontboard.launchapplications
5. keychain-access-groups / com.apple.security.iokit-user-client-class
```

这些 entitlements 的作用是什么？
```
它们让 Cydia 以更高权限运行（platform app），并绕过/降低 iOS 的默认限制：

- no-container：不使用 App Sandbox container（更自由访问文件系统）。
- skip-library-validation：允许加载未经过 Apple library validation 的动态库（对越狱注入/扩展很关键）。
- springboard/frontboard.launchapplications：允许请求系统组件启动/管理应用。
- keychain-access-groups：允许访问指定的 keychain 分组。
- iokit-user-client-class：允许打开特定 IOKit user client（更底层能力）。

```

---

## 作业 8：追踪系统调用

### 执行结果

```bash
# 命令 1: fs_usage 追踪文件系统活动
$ sshpass -p 'alpine' ssh -p 2222 root@localhost "timeout 5 /binpack/usr/bin/fs_usage 2>&1 | head -50"

输出：
15:55:51    PgIn[AT2]                                                                                        0.001664 W tailspind   
15:55:51  PAGE_IN_FILE                                                                                       0.001933   tailspind   
15:55:51  fstat64                                                                                            0.000006   head        
15:55:51  read                                                                                               0.005584   head        
15:55:51  read                                                                                               0.010635   head        
15:55:51  read                                                                                               0.020784   head        
15:55:51  read                                                                                               0.000018   gpsd        
15:55:51  select                                                                                             0.000113   gpsd        
15:55:51  read                                                                                               0.000010   gpsd        
15:55:51  select                                                                                             0.000101   gpsd        
15:55:51  read                                                                                               0.000011   gpsd        
15:55:51  select                                                                                             0.000108   gpsd        
15:55:51  read                                                                                               0.000007   gpsd        
15:55:51  select                                                                                             0.000020   gpsd        
15:55:51  read                                                                                               0.000010   gpsd        
15:55:51  select                                                                                             0.000087   gpsd        
15:55:51  read                                                                                               0.000007   gpsd        
15:55:51  select                                                                                             0.000091   gpsd        
15:55:51  read                                                                                               0.000008   gpsd        
15:55:51  select                                                                                             0.000016   gpsd        
（输出已截断）


# 命令 2: 查看进程列表
$ sshpass -p 'alpine' ssh -p 2222 root@localhost "ps aux | head -20"

输出：
USER             PID  %CPU %MEM      VSZ    RSS   TT  STAT STARTED      TIME COMMAND
mobile            33  22.4  1.9  4765024  55904   ??  Ss    2:54AM 164:52.66 /usr/sbin/mediaserverd
root           14955  18.7  0.3  4239184   8544   ??  Ss    3:56PM   0:00.07 sshd: root@nott i
mobile           138  14.8  0.6  4324112  16896   ??  Ss    2:54AM  93:45.75 /usr/sbin/applecamerad
mobile            64  10.2  1.1  4603920  33152   ??  Ss    2:54AM  88:20.48 /usr/libexec/backboardd
root              29   2.8  0.1  4244384   1616   ??  Ss    2:54AM   0:21.72 /usr/sbin/syslogd
root              67   1.8  0.9  4336592  27424   ??  Ss    2:54AM  32:24.41 /usr/libexec/locationd
root               1   1.6  0.3  4264896   7312   ??  Ss    2:53AM   0:43.22 /sbin/launchd -s
mobile            60   1.1  2.0  5117424  57168   ??  Ss    2:54AM   7:06.40 /System/Library/CoreServices/SpringBoard.app/SpringBoard
root              51   0.9  0.2  4318512   6848   ??  Ss    2:54AM   2:52.24 /usr/libexec/logd
root              86   0.8  0.1  4241168   2320   ??  Ss    2:54AM   0:23.28 /usr/sbin/notifyd
mobile         14667   0.5  1.6  4930928  47312   ??  Ss    3:51PM   0:01.78 /Applications/Camera.app/Camera
_gpsd            118   0.4  0.1  4270256   4208   ??  Ss    2:54AM  12:11.70 /usr/libexec/gpsd
mobile            75   0.3  0.4  4291728  11856   ??  Ss    2:54AM   8:46.42 /System/Library/PrivateFrameworks/AggregateDictionary.framework/Support/aggregated
root              32   0.1  0.1  4262288   2288   ??  Ss    2:54AM   0:22.58 /usr/libexec/fseventsd
mobile          2327   0.0  0.0  4271024    480   ??  Ss   11:15AM   0:10.55 /System/Library/CoreServices/CacheDeleteAppContainerCaches
root            2326   0.0  0.0  4268848    768   ??  Ss   11:15AM   0:00.08 /usr/bin/sysdiagnose
mobile          2325   0.0  0.0  4240384    464   ??  Ss   11:15AM   0:00.05 /usr/libexec/silhouette
mobile          2324   0.0  0.0  4780672    464   ??  Ss   11:15AM   0:00.08 /System/Library/PrivateFrameworks/QuickLookThumbnailing.framework/Support/com.apple.quicklook.ThumbnailsAgent
mobile          2321   0.0  0.0  4309216    464   ??  Ss   11:15AM   0:07.38 /System/Library/PrivateFrameworks/AssistantServices.framework/XPCServices/com.apple.siri.ClientFlow.ClientScripter.xpc/com.apple.siri.ClientFlow.ClientScripter

```

### 观察记录

1. 最活跃的进程是哪些？
   ```
mediaserverd / applecamerad / backboardd /（当前 SSH 会话）sshd / locationd
   ```

2. 观察到哪些系统守护进程？
   ```
launchd, syslogd, logd, notifyd, fseventsd, locationd, gpsd, backboardd
   ```

3. 有哪些进程以 root 权限运行？
   ```
sshd, syslogd, locationd, launchd, logd, notifyd, fseventsd（以及其它多数 /usr/libexec/* 守护进程）
   ```

---

## 📝 阶段 1 自我评估

### 知识点检查

请对每个知识点进行自评 (1-5 分，5 分为完全掌握)：

| 知识点 | 自评分数 | 备注 |
|--------|----------|------|
| SecureROM 概念 | /5 | |
| DFU 模式原理 | /5 | |
| Use-After-Free 漏洞 | /5 | |
| ARM64 基础汇编 | /5 | |
| ROP 链原理 | /5 | |
| 内存布局理解 | /5 | |
| 缓存一致性 | /5 | |
| 系统寄存器 (SCTLR, TTBR) | /5 | |

### 总结问题

**Q: 用一段话描述 checkm8 exploit 的完整流程：**

你的回答：
```
在 SecureROM DFU 模式下，checkm8 先通过异步控制传输的 stall/cancel + usb_reset 触发 USB 请求对象的 Use-After-Free，
并用 `hole/leak` 次数做 heap feng shui，让后续分配复用到目标结构；随后发送构造数据完成覆盖（劫持函数指针/回调链），
触发 ROP 链配置执行环境（例如关闭 WXN、切换 TTBR0 页表、TLBI 刷新 TLB、cache 维护等），把 shellcode 复制到 SRAM 并跳转执行；
最后修改 USB 描述符/序列号并追加 `PWND:[checkm8]`，让设备进入 pwned DFU 状态，为后续加载更高级 payload/越狱链条打基础。

```

**Q: checkm8 为什么被称为"永久不可修补"？**

你的回答：
```
因为漏洞发生在 BootROM/SecureROM（芯片内置只读代码）里，这部分代码烧录在硬件中，已出厂设备无法通过系统更新来替换或修复。
苹果只能在后续启动链（如 iBoot/内核）做缓解，但无法从根本上修复 BootROM 漏洞本身；因此对受影响芯片来说是“永久”的。

```

**Q: 学习过程中遇到的最大困难是什么？如何解决的？**

你的回答：
```
最大困难是把“脚本里的常量/ROP 回调表”与“SecureROM 真实执行行为（cache/TLB/页表/权限）”对应起来。
解决方法：按 `checkm8.py` 的 `t8015_callbacks` 逐条画流程图，再对照 `checkm8_arm64.S` 里 cache flush / I-cache invalidate 的原因，
把每一步写清楚“改了什么状态、为什么必须做、没做会崩在哪”；必要时查 ARMv8 的 SCTLR/TTBR/TLBI/IC 指令说明。

```

---

## 📌 学习笔记区

在这里记录你的额外笔记、疑问、想法：

```




















```

---

*完成日期：_____________*
*自评总分：_____ / 40*
*准备进入阶段 2：[ ] 是 [ ] 否*
