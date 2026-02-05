# MyROM（v0.1 / research）

把 iPhone X（A11）在 **checkra1n → pongoOS → XNU → iOS** 这条启动链里，`pongoOS` 当作“最早可控阶段”，做一个最小可复现的 **measured boot**：

- 在 XNU 执行前，对内存中的 `kernelcache` 做 SHA-256 度量
- 把度量结果通过 `boot-args` 传递给 iOS（用户态可读）
- 通过 SSH（`iproxy`）验证本次启动携带的 `myrom_*` 字段

这仓库的重点是“可复现”：把顺序、脚本、以及验证方式整理成别人照做就能跑通的路径。

## 已验证环境

- Device: `iPhone10,6`（iPhone X / A11）
- iOS: `12.3.1 (16F203)`
- checkra1n: `beta 0.12.4`（macOS）
- pongoOS: checkra1n bundle 内置版本（示例输出：`pongoOS 2.5.1-9234e72f`）

## 快速开始（从零复现）

### 0) 依赖

1) 安装 checkra1n.app（默认路径：`/Applications/checkra1n.app`）

2) 安装 Mac 侧工具：

```bash
brew install libimobiledevice sshpass
```

### 1) 基线：确认“越狱态” + 安装 OpenSSH

1) 手机进入 DFU（屏幕保持全黑）
2) 在仓库根目录运行：

```bash
./jailbreak_normal.sh
```

3) 回到 iOS 后：解锁 → 打开 Cydia → 安装 `OpenSSH`

> 如果 Cydia 会闪退，基本就是“没进越狱态”，先把基线跑通再继续。

### 2) MyROM v0.1：pongoOS 加载模块并 `bootx`

1) 再次进入 DFU（屏幕保持全黑）
2) 运行：

```bash
./run_myrom_v0_1.sh
```

这个脚本会自动完成：

- checkra1n 进入 pongo shell（`-p -E`）
- `pongoterm` 发送 `myrom_manifest` 模块并 `modload`
- `sep auto`
- `bootx`（patched boot；不要用 `bootux`）

### 3) 验证：SSH 读取 `kern.bootargs`

iOS 启动后：解锁，等 20~30 秒让 `sshd` 起起来，然后运行：

```bash
./verify_myrom_bootargs.sh
```

期望看到类似输出：

```text
myrom=1
myrom_v=0.1
myrom_nonce=...
myrom_ksha256=...
myrom_slide=...
```

## 手动操作顺序（当你已经在 `pongoOS>`）

```text
/send modules/myrom_manifest/build/myrom_manifest
modload
sep auto
bootx
```

## 发生了什么（实现要点）

- `modules/myrom_manifest/`
  - 通过设置 `preboot_hook`，在 checkra1n KPF 之后执行
  - 解析内存中的 `kernelcache`（Mach-O），计算 SHA-256
  - 将度量结果追加到 XNU `boot-args`（iOS 用户态可用 `sysctl -n kern.bootargs` 读取）
- `verify_myrom_bootargs.sh`
  - `idevice_id` 找到设备 UDID
  - `iproxy` 将 `localhost:<port>` 转发到设备 `22`
  - `ssh root@localhost sysctl -n kern.bootargs` 并提取 `myrom*` 字段

## 目录结构

- `checkra1n_research/pongoOS/`：submodule（pongoOS 源码 + `pongoterm`）
- `checkra1n_research/ipwndfu/`：submodule（可选；checkm8 相关）
- `xnu/`：submodule（可选；Apple OSS XNU）
- `modules/myrom_manifest/`：本项目的 pongoOS 模块（v0.1）
- `docs/`：学习材料 + 研究笔记（见 `docs/README.md`）
- `tweaks/`：tweak 示例
- `deps/`：iOS 侧依赖（substrate headers/libs）

## Submodules

克隆后需要初始化 submodules。

最小集（只跑 v0.1 实验所需）：

```bash
git submodule update --init --recursive checkra1n_research/pongoOS
```

全部（包含可选的 `ipwndfu` / `xnu`）：

```bash
git submodule update --init --recursive
```

## 常见问题

- Cydia 闪退：几乎一定是没进越狱态 → 重新跑 `./jailbreak_normal.sh`
- SSH 连接 refused：OpenSSH 未装/`sshd` 未起/设备未信任 → 先装 OpenSSH、解锁并信任
- pongoOS 里别用 `bootux`：那是 **unpatched** 启动，会回到未越狱态；要用 `bootx`

## 安全提示

装了 OpenSSH 后请尽快修改 root 密码（默认常见为 `alpine`）：

```bash
passwd
```

## 可配置项（环境变量）

- `CHECKRA1N_BIN`：指定 checkra1n 可执行文件路径（默认 `/Applications/checkra1n.app/Contents/MacOS/checkra1n`）
- `SSH_PASS`：root 密码（默认 `alpine`）
- `SSH_LOCAL_PORT`：本地转发端口起始值（默认 `2222`）
