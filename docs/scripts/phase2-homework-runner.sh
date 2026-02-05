#!/bin/bash
# 阶段 2 作业执行脚本
# 用法: ./phase2-homework-runner.sh [作业编号]

SSH_CMD="sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p 2222 root@localhost"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_subheader() {
    echo -e "${CYAN}▶ $1${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────────────${NC}"
}

print_cmd() {
    echo -e "${GREEN}[命令]${NC} $1"
}

run_cmd() {
    eval "$SSH_CMD \"$1\""
}

print_explanation() {
    echo -e "${YELLOW}[说明]${NC} $1"
}

homework_1() {
    print_header "作业 1: 查看设备上的安全组件"

    print_subheader "1.1 列出内核中的安全相关 kext"
    print_cmd "/binpack/usr/local/bin/jtool2 -k kernelcache | grep -iE 'amfi|sandbox|trust|security'"
    run_cmd "/binpack/usr/local/bin/jtool2 -k /System/Library/Caches/com.apple.kernelcaches/kernelcache 2>&1 | grep -iE 'amfi|sandbox|trust|security|coretrust'"
    echo ""
    print_explanation "这些是 iOS 安全机制的核心内核扩展"
    echo ""

    echo -e "${CYAN}安全组件说明：${NC}"
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ AppleMobileFileIntegrity (AMFI)                             │"
    echo "│   → 代码签名验证，决定程序能否运行                           │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│ CoreTrust                                                   │"
    echo "│   → 信任缓存管理，存储已信任代码的哈希                       │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│ security.sandbox                                            │"
    echo "│   → 沙盒策略执行，限制 App 访问范围                          │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│ AppleImage4                                                 │"
    echo "│   → 安全启动验证，验证固件签名                               │"
    echo "└─────────────────────────────────────────────────────────────┘"
}

homework_2() {
    print_header "作业 2: 分析 AMFI 守护进程"

    print_subheader "2.1 查看 amfid 进程"
    print_cmd "ps aux | grep amfid"
    run_cmd "ps aux | grep amfid | grep -v grep"
    echo ""

    print_subheader "2.2 查看 amfid 的 entitlements"
    print_cmd "/binpack/usr/local/bin/jtool2 --ent /usr/libexec/amfid"
    run_cmd "/binpack/usr/local/bin/jtool2 --ent /usr/libexec/amfid 2>&1"
    echo ""

    print_subheader "2.3 查看 amfid 的代码签名"
    print_cmd "/binpack/usr/local/bin/jtool2 --sig /usr/libexec/amfid"
    run_cmd "/binpack/usr/local/bin/jtool2 --sig /usr/libexec/amfid 2>&1 | head -15"
    echo ""

    echo -e "${CYAN}AMFI 架构说明：${NC}"
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│                                                             │"
    echo "│   用户态                        内核态                       │"
    echo "│   ┌─────────┐                  ┌─────────────┐              │"
    echo "│   │ amfid   │ ◄─── Mach IPC ──►│ AMFI.kext   │              │"
    echo "│   │ (助手)  │                  │ (决策者)    │              │"
    echo "│   └─────────┘                  └─────────────┘              │"
    echo "│                                                             │"
    echo "│   amfid: 用户态进程，处理复杂的签名验证                      │"
    echo "│   AMFI.kext: 内核扩展，做最终决策                           │"
    echo "│                                                             │"
    echo "│   KPF 补丁内核中的 AMFI.kext，而不是 amfid                  │"
    echo "│   因为内核是最终决策者                                      │"
    echo "│                                                             │"
    echo "└─────────────────────────────────────────────────────────────┘"
}

homework_3() {
    print_header "作业 3: 检查代码签名状态"

    print_subheader "3.1 代码签名相关的 sysctl 参数"
    print_cmd "sysctl -a | grep -E 'cs_'"
    run_cmd "sysctl -a 2>/dev/null | grep -E 'cs_force|cs_debug|cs_enforcement'"
    echo ""

    print_subheader "3.2 MAC 策略执行状态"
    print_cmd "sysctl security.mac"
    run_cmd "sysctl security.mac"
    echo ""

    echo -e "${CYAN}参数含义：${NC}"
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ vm.cs_force_kill = 0                                        │"
    echo "│   → 不强制杀死未签名代码 (越狱后应该是 0)                    │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│ vm.cs_force_hard = 0                                        │"
    echo "│   → 代码签名检查已放松 (越狱后应该是 0)                      │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│ security.mac.proc_enforce = 1                               │"
    echo "│   → MAC 进程策略仍在执行                                    │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│ security.mac.vnode_enforce = 1                              │"
    echo "│   → MAC 文件策略仍在执行                                    │"
    echo "└─────────────────────────────────────────────────────────────┘"
}

homework_4() {
    print_header "作业 4: 分析 KPF 源码"

    echo -e "${YELLOW}请打开以下文件进行分析：${NC}"
    echo ""
    echo "  checkra1n_research/pongoOS/checkra1n/kpf/main.c"
    echo ""

    echo -e "${CYAN}KPF 主要补丁函数列表：${NC}"
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│  函数名                          │ 补丁目标                 │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│  kpf_amfi_callback               │ AMFI 信任缓存检查        │"
    echo "│  kpf_mac_mount_callback          │ 根文件系统挂载限制       │"
    echo "│  kpf_mac_vm_map_protect_callback │ W^X 内存保护             │"
    echo "│  kpf_conversion_callback         │ tfp0 任务转换检查        │"
    echo "│  kpf_mac_dounmount_callback      │ 文件系统卸载限制         │"
    echo "│  kpf_dyld_callback               │ 动态链接器路径检查       │"
    echo "│  vm_fault_enter_callback         │ 页面错误处理             │"
    echo "│  kpf_find_shellcode_area_callback│ shellcode 注入区域       │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""

    echo -e "${CYAN}AMFI 补丁模式匹配示例：${NC}"
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│  // 搜索的指令模式                                          │"
    echo "│  uint64_t matches[] = {                                     │"
    echo "│      0x91000000,  // ADD 指令                               │"
    echo "│      0x52800200,  // MOV W*, 0x16                           │"
    echo "│      0xd3000000,  // LSR 指令                               │"
    echo "│      0x9b000000   // MADD 指令                              │"
    echo "│  };                                                         │"
    echo "│                                                             │"
    echo "│  // 找到后的修改                                            │"
    echo "│  opcode_stream[0] = 0xd2800020;  // MOV X0, #1              │"
    echo "│  opcode_stream[1] = RET;          // 直接返回               │"
    echo "└─────────────────────────────────────────────────────────────┘"
}

homework_5() {
    print_header "作业 5: 理解 XNU 内核结构"

    print_subheader "5.1 查看 kernelcache 的段结构"
    print_cmd "/binpack/usr/local/bin/jtool2 -l kernelcache | head -40"
    run_cmd "/binpack/usr/local/bin/jtool2 -l /System/Library/Caches/com.apple.kernelcaches/kernelcache 2>&1 | head -45"
    echo ""

    echo -e "${CYAN}内核段说明：${NC}"
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│  段名            │ 权限  │ 用途                             │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│  __TEXT          │ R--   │ 只读数据、常量字符串             │"
    echo "│  __TEXT_EXEC     │ R-X   │ 可执行代码 ← KPF 主要修改这里    │"
    echo "│  __DATA_CONST    │ R--   │ 只读常量数据                     │"
    echo "│  __DATA          │ RW-   │ 可读写数据                       │"
    echo "│  __PRELINK_TEXT  │ R-X   │ Kext 代码                        │"
    echo "│  __PRELINK_INFO  │ R--   │ Kext 元信息                      │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
    print_explanation "KPF 主要修改 __TEXT_EXEC 段，因为安全检查代码在这里"
}

homework_6() {
    print_header "作业 6: 追踪沙盒配置"

    print_subheader "6.1 查看沙盒配置文件列表"
    print_cmd "ls -la /System/Library/Sandbox/Profiles/"
    run_cmd "ls -la /System/Library/Sandbox/Profiles/"
    echo ""

    print_subheader "6.2 读取一个沙盒配置示例"
    print_cmd "cat com.apple.homed.sb | head -40"
    run_cmd "cat /System/Library/Sandbox/Profiles/com.apple.homed.sb 2>/dev/null | head -40"
    echo ""

    echo -e "${CYAN}沙盒规则语法说明：${NC}"
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│  (version 1)                                                │"
    echo "│    → 沙盒配置版本                                           │"
    echo "│                                                             │"
    echo "│  (deny default)                                             │"
    echo "│    → 默认拒绝所有操作                                       │"
    echo "│                                                             │"
    echo "│  (allow file-read*)                                         │"
    echo "│    → 允许读取文件                                           │"
    echo "│                                                             │"
    echo "│  (allow file-write* (subpath \"/tmp\"))                      │"
    echo "│    → 允许写入 /tmp 目录                                     │"
    echo "│                                                             │"
    echo "│  (allow mach-lookup (global-name \"com.apple.xxx\"))         │"
    echo "│    → 允许连接指定的 Mach 服务                               │"
    echo "└─────────────────────────────────────────────────────────────┘"
}

homework_7() {
    print_header "作业 7: 对比 XNU 源码和 KPF 补丁"

    echo -e "${YELLOW}请在本地执行以下命令搜索 XNU 源码：${NC}"
    echo ""
    echo "  grep -r 'CS_AMFI' /Users/jqwang/185-苹果越狱后/xnu/bsd/kern/"
    echo ""

    echo -e "${CYAN}XNU 代码签名相关文件：${NC}"
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│  xnu/bsd/kern/kern_codesigning.c                            │"
    echo "│    → 代码签名主逻辑                                         │"
    echo "│                                                             │"
    echo "│  xnu/bsd/kern/kern_cs.c                                     │"
    echo "│    → CS (Code Signing) 验证                                 │"
    echo "│                                                             │"
    echo "│  xnu/bsd/kern/kern_trustcache.c                             │"
    echo "│    → 信任缓存管理                                           │"
    echo "│                                                             │"
    echo "│  xnu/security/mac_vfs.c                                     │"
    echo "│    → MAC 文件系统策略                                       │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""

    echo -e "${CYAN}对比示例：${NC}"
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│  XNU 原始代码 (伪代码):                                      │"
    echo "│  ─────────────────────                                      │"
    echo "│  if (!is_in_trust_cache(hash)) {                            │"
    echo "│      if (!has_valid_signature(binary)) {                    │"
    echo "│          return DENY;  // 拒绝执行                          │"
    echo "│      }                                                      │"
    echo "│  }                                                          │"
    echo "│  return ALLOW;                                              │"
    echo "│                                                             │"
    echo "│  KPF 补丁后 (伪代码):                                        │"
    echo "│  ─────────────────────                                      │"
    echo "│  return ALLOW;  // 直接返回允许，跳过所有检查                │"
    echo "└─────────────────────────────────────────────────────────────┘"
}

homework_8() {
    print_header "作业 8: 实践 - 验证越狱效果"

    print_subheader "8.1 验证可以访问根目录"
    print_cmd "ls -la /"
    run_cmd "ls -la / | head -15"
    echo ""

    print_subheader "8.2 验证可以写入临时文件"
    print_cmd "touch /tmp/test && echo OK && rm /tmp/test"
    run_cmd "touch /tmp/jb_test_write && echo 'Write test: OK' && rm /tmp/jb_test_write"
    echo ""

    print_subheader "8.3 查看 Cydia 的特殊权限"
    print_cmd "/binpack/usr/local/bin/jtool2 --ent /Applications/Cydia.app/Cydia"
    run_cmd "/binpack/usr/local/bin/jtool2 --ent /Applications/Cydia.app/Cydia 2>&1"
    echo ""

    print_subheader "8.4 验证未签名代码可以运行"
    print_cmd "ls /binpack/usr/local/bin/ && jtool2 --help"
    run_cmd "ls /binpack/usr/local/bin/"
    echo ""
    run_cmd "/binpack/usr/local/bin/jtool2 2>&1 | head -5"
    echo ""

    echo -e "${CYAN}越狱效果验证清单：${NC}"
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│  ✓ 可以列出根目录 → mac_mount 补丁生效                      │"
    echo "│  ✓ 可以写入文件 → 文件系统权限正常                          │"
    echo "│  ✓ Cydia 有 platform-application → AMFI 补丁生效            │"
    echo "│  ✓ 未签名工具可运行 → 代码签名检查被绕过                    │"
    echo "└─────────────────────────────────────────────────────────────┘"
}

all_homework() {
    homework_1
    echo ""
    read -p "按 Enter 继续下一个作业..."
    homework_2
    echo ""
    read -p "按 Enter 继续下一个作业..."
    homework_3
    echo ""
    read -p "按 Enter 继续下一个作业..."
    homework_4
    echo ""
    read -p "按 Enter 继续下一个作业..."
    homework_5
    echo ""
    read -p "按 Enter 继续下一个作业..."
    homework_6
    echo ""
    read -p "按 Enter 继续下一个作业..."
    homework_7
    echo ""
    read -p "按 Enter 继续下一个作业..."
    homework_8
}

show_menu() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}      阶段 2 作业执行脚本 - pongoOS 与 KPF 学习${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  1) 作业 1: 查看设备上的安全组件"
    echo "  2) 作业 2: 分析 AMFI 守护进程"
    echo "  3) 作业 3: 检查代码签名状态"
    echo "  4) 作业 4: 分析 KPF 源码"
    echo "  5) 作业 5: 理解 XNU 内核结构"
    echo "  6) 作业 6: 追踪沙盒配置"
    echo "  7) 作业 7: 对比 XNU 源码和 KPF 补丁"
    echo "  8) 作业 8: 实践 - 验证越狱效果"
    echo "  a) 执行所有作业"
    echo "  q) 退出"
    echo ""
}

# 主程序
if [ -n "$1" ]; then
    case $1 in
        1) homework_1 ;;
        2) homework_2 ;;
        3) homework_3 ;;
        4) homework_4 ;;
        5) homework_5 ;;
        6) homework_6 ;;
        7) homework_7 ;;
        8) homework_8 ;;
        a|all) all_homework ;;
        *) echo "无效的作业编号: $1" ;;
    esac
else
    while true; do
        show_menu
        read -p "请选择作业编号: " choice
        case $choice in
            1) homework_1 ;;
            2) homework_2 ;;
            3) homework_3 ;;
            4) homework_4 ;;
            5) homework_5 ;;
            6) homework_6 ;;
            7) homework_7 ;;
            8) homework_8 ;;
            a|A) all_homework ;;
            q|Q) echo "再见!"; exit 0 ;;
            *) echo -e "${RED}无效选择，请重试${NC}" ;;
        esac
        echo ""
        read -p "按 Enter 返回菜单..."
    done
fi
