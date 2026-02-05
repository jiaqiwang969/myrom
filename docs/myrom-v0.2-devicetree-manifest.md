# MyROM v0.2 — DeviceTree Manifest（工程版）

v0.1 已经证明：我们能在 `preboot_hook` 里测量“将要执行的 kernelcache”，并把结果通过 `kern.bootargs` 在用户态读出来。

v0.2 做的事情更像“真正的 measured boot 载体”：

- 把 manifest 放进 DeviceTree：`IODeviceTree:/chosen` → `myrom-manifest`
- iOS 侧提供 `myromctl`：读取该字段并打印/落盘
- 同时（best-effort）在 `/chosen/memory-map` 导出一个 `MyROMManifest` memmap，方便后续做 kernel-side consumer

## 1. Manifest 字段（当前）

当前写入的是一个 NUL 结尾的 JSON（便于 iOS 侧打印/存档）：

```json
{"myrom":1,"v":"0.2","nonce":"...","ksha256":"...","slide":"0x...","klen":"0x..."}
```

- `nonce`：每次启动的 best-effort nonce（来自 `cntvct_el0`）
- `ksha256`：对 “post-KPF 的 in-memory kernelcache Mach-O（按 file size）” 做 SHA-256
- `slide`：KASLR slide（来自 pongoOS 导出符号）
- `klen`：kernelcache 的 file size（按 segment 的 `fileoff+filesize` 取 max）

## 2. pongoOS 侧实现（关键点）

模块：`modules/myrom_manifest_dt/main.c`

- hook 点：`preboot_hook`
- 写入 DeviceTree 的方式：不是原地扩容，而是
  - `dt_check()` 验证原 DeviceTree blob
  - 复制整个 Apple DeviceTree（`dt_node_t`/`dt_prop_t` 格式）
  - 在 `chosen` 节点新增一个 property：`myrom-manifest`
  - 更新 `boot_args.deviceTreeP / deviceTreeLength` 指向新 blob
- memmap：在新 DeviceTree 的 `memory-map` 里分配一个条目 `MyROMManifest`，指向 `alloc_static()` 的持久 blob

> 为什么要 `alloc_static()`：这块内存会被纳入 xnu static region，能跨过 boot 继续存在。

## 3. 复现顺序（建议）

1) 基线越狱（确保是越狱态）：

```bash
./jailbreak_normal.sh
```

2) iOS 内安装 `OpenSSH`

3) 跑 v0.2：

```bash
./run_myrom_v0_2.sh
```

4) 单独验证（也可用于后续每次启动）：

```bash
./verify_myrom_dt_manifest.sh
```

## 4. iOS 侧落盘（可选）

安装 LaunchDaemon：`ios/myrom_logger/`

```bash
./ios/myrom_logger/install.sh
```

默认把每次启动的 manifest 追加到：

- `/var/log/myrom/myrom.jsonl`

## 5. Debug Checklist

- `verify_myrom_dt_manifest.sh` 报 myromctl 不存在：
  - 脚本会自动尝试编译/部署（需要本机 `xcrun`）
  - 或手动装：`ios/myromctl/build_and_deploy.sh`（需要 SSH 可达）
- manifest 为空/读不到：
  - 先看 `sysctl -n kern.bootargs | tr \" \" \"\\n\" | egrep '^myrom'`
  - 如果看到 `myrom_dt=0`：说明本次 DeviceTree 注入失败，先排查 pongoOS 输出日志

