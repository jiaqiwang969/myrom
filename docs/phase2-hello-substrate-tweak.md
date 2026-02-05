# 阶段 2：第一个 Substrate Tweak（HelloSubstrate）

目标：用最小可验证的方式，完成一次 **MobileSubstrate 注入 + Hook**，并能通过 SSH 看到结果。

---

## 1) 项目位置

- 源码：`tweaks/HelloSubstrate/Tweak.m`
- 注入过滤器：`tweaks/HelloSubstrate/HelloSubstrate.plist`（仅注入 `com.apple.springboard`）
- 构建/部署脚本：`tweaks/HelloSubstrate/build_and_deploy.sh`

---

## 2) 一键构建 + 部署 + Respring

在仓库根目录执行：

```bash
tweaks/HelloSubstrate/build_and_deploy.sh
```

脚本会：
- 用 Xcode 的 iOS SDK 编译出 `HelloSubstrate.dylib`（arm64, min iOS 12.0）
- scp 到设备 `/Library/MobileSubstrate/DynamicLibraries/`
- `ldid -S` 签名
- `killall SpringBoard` 触发 respring
- tail 设备日志文件做验证

---

## 3) 验证注入/Hook 是否生效

日志文件固定写到：

`/var/tmp/hello_substrate_springboard.log`

通过 SSH 查看：

```bash
sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p 2222 root@localhost \
  "tail -n 50 /var/tmp/hello_substrate_springboard.log"
```

你应该能看到至少两行：
- `Loaded. process=SpringBoard bundle=com.apple.springboard`
- `Installed hook: -[UIApplication sendEvent:]`

然后你在手机上随便点一下/滑一下屏幕，再 tail 一次，应该会出现：
- `Hook fired: -[UIApplication sendEvent:] (first event observed)`

---

## 4) 卸载/禁用

删除或改名（推荐改名，便于恢复）：

```bash
sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p 2222 root@localhost \
  "mv /Library/MobileSubstrate/DynamicLibraries/HelloSubstrate.dylib /Library/MobileSubstrate/DynamicLibraries/HelloSubstrate.dylib.disabled && killall SpringBoard"
```

