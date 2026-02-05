# 阶段 2：安装 Hooking 框架（通过 SSH）

目标：在 iOS 12.3.1（checkra1n）上安装 **Cydia Substrate**（`mobilesubstrate`）及其 **Safe Mode**（`com.saurik.substrate.safemode`），为后续 tweak / 注入调试做准备。

---

## 0) 连接验证

```bash
sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p 2222 root@localhost "uname -a; id"
```

---

## 1) 检查是否已安装

```bash
sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p 2222 root@localhost \
  "dpkg -l | egrep -i 'mobilesubstrate|substrate\\.safemode|substitute|libhooker' || true"
```

---

## 2) 安装（推荐：APT 直接装）

前提：设备端能正常访问 `https://apt.bingner.com/`（否则看下一节“离线安装”）。

```bash
sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p 2222 root@localhost \
  "apt-get update && apt-get install -y mobilesubstrate com.saurik.substrate.safemode"
```

---

## 3) 安装（离线：本机下载 .deb → scp 到设备 → APT 从本地缓存安装）

当设备端 `apt-get update`/`apt-get install` 因 HTTPS/TLS/超时失败时，用这一套（只走 SSH 传输，不依赖设备端下载）。

```bash
set -euo pipefail

BASE_URL='http://apt.bingner.com/debs/1443.00'
MOB='mobilesubstrate_0.9.7111_iphoneos-arm.deb'
SAFE='com.saurik.substrate.safemode_0.9.6005_iphoneos-arm.deb'

tmp="$(mktemp -d)"
curl -fL -o "$tmp/$MOB"  "$BASE_URL/$MOB"
curl -fL -o "$tmp/$SAFE" "$BASE_URL/$SAFE"

# 可选：校验（来自 apt-cache show 的 SHA256）
echo "e72704e8cc69239939b78ab3706f43f9b449425270bacc3cd8a4160b6986e8c0  $tmp/$MOB"  | sha256sum -c -
echo "de3f3c5e0bfde32d61e14daaca7a7899a73215f94753a77fca1aa4203b018c87  $tmp/$SAFE" | sha256sum -c -

# 推到设备的 APT 缓存目录
sshpass -p 'alpine' scp -o StrictHostKeyChecking=no -P 2222 \
  "$tmp/$MOB" "$tmp/$SAFE" root@localhost:/var/cache/apt/archives/

# 让 APT 直接从本地 archives 安装（无需重新 update）
sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p 2222 root@localhost \
  "apt-get install -y mobilesubstrate com.saurik.substrate.safemode"
```

---

## 4) 验证安装结果

```bash
sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p 2222 root@localhost <<'EOF'
dpkg -l | egrep -i 'mobilesubstrate|substrate\\.safemode' || true
ls -la /Library/Frameworks/CydiaSubstrate.framework 2>/dev/null || true
ls -la /Library/MobileSubstrate 2>/dev/null || true
EOF
```

---

## 5) 让系统加载（Respring）

安装后通常需要 respring：

```bash
sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p 2222 root@localhost "killall SpringBoard"
```

