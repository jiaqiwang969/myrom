# 阶段 2 作业记录表

> 姓名：_____________
> 开始日期：_____________
> 完成日期：_____________

---

## 作业 1：查看设备上的安全组件

### 执行结果

```bash
# 命令: 列出内核中的安全相关 kext
$ sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "/binpack/usr/local/bin/jtool2 -k \
   /System/Library/Caches/com.apple.kernelcaches/kernelcache" | \
   grep -iE 'amfi|sandbox|trust|security'

输出：



```

### 记录

| Kext Bundle ID | 地址 | 功能描述 |
|----------------|------|----------|
| com.apple.driver.AppleMobileFileIntegrity | | |
| com.apple.kext.CoreTrust | | |
| com.apple.security.sandbox | | |
| com.apple.security.AppleImage4 | | |

### 思考

这些 kext 分别负责什么安全功能？
```




```

---

## 作业 2：分析 AMFI 守护进程

### 执行结果

```bash
# 命令 1: 查看 amfid 进程
$ sshpass -p 'alpine' ssh -p 2222 root@localhost "ps aux | grep amfid"

输出：


# 命令 2: 查看 amfid 的 entitlements
$ sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "/binpack/usr/local/bin/jtool2 --ent /usr/libexec/amfid"

输出：


# 命令 3: 查看 amfid 的代码签名
$ sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "/binpack/usr/local/bin/jtool2 --sig /usr/libexec/amfid"

输出：


```

### 思考题回答

**Q1: amfid 是用户态还是内核态进程？**
```


```

**Q2: 它和内核中的 AMFI kext 是什么关系？**
```


```

**Q3: 为什么 KPF 要补丁内核而不是 amfid？**
```


```

---

## 作业 3：检查代码签名状态

### 执行结果

```bash
# 命令 1: 查看代码签名相关的 sysctl 参数
$ sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "sysctl -a | grep -E 'cs_|amfi'"

输出：


# 命令 2: 查看 MAC 策略执行状态
$ sshpass -p 'alpine' ssh -p 2222 root@localhost "sysctl security.mac"

输出：


```

### 关键参数记录

| 参数 | 当前值 | 含义 |
|------|--------|------|
| vm.cs_force_kill | | |
| vm.cs_force_hard | | |
| vm.cs_debug | | |
| security.mac.proc_enforce | | |
| security.mac.vnode_enforce | | |
| security.mac.sandbox.sentinel | | |

### 分析

这些参数的值说明了什么？
```



```

---

## 作业 4：分析 KPF 源码

### 任务 1：列出所有补丁函数

文件路径：`checkra1n_research/pongoOS/checkra1n/kpf/main.c`

| 序号 | 函数名 | 补丁目标 |
|------|--------|----------|
| 1 | kpf_amfi_callback | AMFI 信任缓存检查 |
| 2 | kpf_mac_mount_callback | |
| 3 | kpf_mac_vm_map_protect_callback | |
| 4 | kpf_conversion_callback | |
| 5 | kpf_mac_dounmount_callback | |
| 6 | kpf_dyld_callback | |
| 7 | | |
| 8 | | |

### 任务 2：分析 AMFI 补丁

**搜索的指令模式：**
```c
uint64_t matches[] = {
    // 填写从源码中找到的模式



};
```

**掩码的作用：**
```



```

**找到后做了什么修改：**
```



```

---

## 作业 5：理解 XNU 内核结构

### 执行结果

```bash
# 命令: 查看 kernelcache 的段结构
$ sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "/binpack/usr/local/bin/jtool2 -l \
   /System/Library/Caches/com.apple.kernelcaches/kernelcache" | head -40

输出：


```

### 关键段记录

| 段名 | 起始地址 | 结束地址 | 用途 |
|------|----------|----------|------|
| __TEXT | | | |
| __DATA_CONST | | | |
| __TEXT_EXEC | | | |
| __DATA | | | |
| __PRELINK_TEXT | | | |
| __PRELINK_INFO | | | |

### 思考题回答

**Q1: KPF 主要修改哪个段？为什么？**
```



```

**Q2: 为什么 __TEXT_EXEC 和 __TEXT 要分开？**
```



```

---

## 作业 6：追踪沙盒配置

### 执行结果

```bash
# 命令 1: 查看沙盒配置文件列表
$ sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "ls -la /System/Library/Sandbox/Profiles/"

输出：


# 命令 2: 读取一个沙盒配置
$ sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "cat /System/Library/Sandbox/Profiles/com.apple.homed.sb" | head -50

输出：


```

### 沙盒规则分析

**Q1: 沙盒配置文件使用什么语法？**
```


```

**Q2: (deny default) 是什么意思？**
```


```

**Q3: (allow file-read*) 是什么意思？**
```


```

**Q4: 列出 3 个常见的沙盒规则：**
```
1.
2.
3.
```

---

## 作业 7：对比 XNU 源码和 KPF 补丁

### 执行结果

```bash
# 命令: 在 XNU 源码中搜索 AMFI 相关代码
$ grep -r "CS_AMFI" /Users/jqwang/185-苹果越狱后/xnu/bsd/kern/ | head -10

输出：


```

### 源码分析

**在 kern_codesigning.c 中找到的关键代码：**
```c
// 粘贴你找到的相关代码片段




```

### 对比表

| 功能 | XNU 原始代码 | KPF 修改后 |
|------|--------------|------------|
| 签名检查 | | |
| 信任缓存查询 | | |
| 权限验证 | | |

---

## 作业 8：实践 - 验证越狱效果

### 执行结果

```bash
# 命令 1: 验证可以访问根目录
$ sshpass -p 'alpine' ssh -p 2222 root@localhost "ls -la /"

输出：


# 命令 2: 验证可以写入
$ sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "touch /tmp/test_write && echo 'Write OK' && rm /tmp/test_write"

输出：


# 命令 3: 查看 Cydia 的特殊权限
$ sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "/binpack/usr/local/bin/jtool2 --ent /Applications/Cydia.app/Cydia"

输出：


# 命令 4: 验证未签名代码可以运行
$ sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "ls -la /binpack/usr/local/bin/"

输出：


```

### 验证清单

- [ ] 可以列出根目录内容
- [ ] 可以在 /tmp 创建和删除文件
- [ ] Cydia 拥有 platform-application entitlement
- [ ] Cydia 拥有 com.apple.private.skip-library-validation
- [ ] /binpack 中的未签名工具可以正常运行

### 分析

**这些能力是哪些补丁提供的？**

| 能力 | 对应的 KPF 补丁 |
|------|-----------------|
| 运行未签名代码 | |
| 访问根目录 | |
| 写入系统目录 | |

---

## 📝 阶段 2 自我评估

### 知识点检查

| 知识点 | 自评分数 (1-5) | 备注 |
|--------|----------------|------|
| pongoOS 作用和位置 | /5 | |
| KPF 工作原理 | /5 | |
| 模式匹配技术 | /5 | |
| AMFI 补丁原理 | /5 | |
| Sandbox 补丁原理 | /5 | |
| mac_mount 补丁原理 | /5 | |
| tfp0 补丁原理 | /5 | |
| XNU 内核结构 | /5 | |

### 总结问题

**Q: 用自己的话描述 KPF 的完整工作流程：**
```








```

**Q: 为什么补丁要在内核启动前打？启动后能打吗？**
```




```

**Q: 如果苹果更新了内核代码，KPF 会失效吗？为什么？**
```




```

---

## 📌 学习笔记区

```




















```

---

*完成日期：_____________*
*自评总分：_____ / 40*
*准备进入阶段 3：[ ] 是 [ ] 否*
