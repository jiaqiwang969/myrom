#!/bin/bash
# 阶段 1 作业执行脚本
# 用法: ./homework-runner.sh [作业编号]

SSH_CMD="sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p 2222 root@localhost"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_cmd() {
    echo -e "${GREEN}[命令]${NC} $1"
    echo -e "${BLUE}────────────────────────────────────────────────────────────${NC}"
}

run_cmd() {
    eval "$SSH_CMD \"$1\""
}

homework_1() {
    print_header "作业 1: 验证设备硬件信息"

    echo -e "${YELLOW}1.1 获取芯片 ID (chip-id)${NC}"
    print_cmd "ioreg -p IODeviceTree -l | grep 'chip-id'"
    run_cmd "ioreg -p IODeviceTree -l | grep 'chip-id'"
    echo -e "${GREEN}预期: <15800000> = 0x8015 (T8015 = A11 Bionic)${NC}"
    echo ""

    echo -e "${YELLOW}1.2 获取 Board ID${NC}"
    print_cmd "ioreg -p IODeviceTree -l | grep 'board-id'"
    run_cmd "ioreg -p IODeviceTree -l | grep 'board-id'"
    echo -e "${GREEN}预期: <0e000000> = 0x0e (D221AP = iPhone X Global)${NC}"
    echo ""

    echo -e "${YELLOW}1.3 获取平台名称${NC}"
    print_cmd "ioreg -p IODeviceTree -l | grep 'platform-name'"
    run_cmd "ioreg -p IODeviceTree -l | grep 'platform-name'"
    echo -e "${GREEN}预期: t8015${NC}"
    echo ""

    echo -e "${YELLOW}1.4 验证 checkra1n 标记${NC}"
    print_cmd "ioreg -l | grep checkra1n | head -3"
    run_cmd "ioreg -l | grep checkra1n | head -3"
    echo ""

    echo -e "${YELLOW}1.5 查看内核版本${NC}"
    print_cmd "sysctl kern.version"
    run_cmd "sysctl kern.version"
    echo -e "${GREEN}预期: xnu-4903.262.2 / RELEASE_ARM64_T8015${NC}"
}

homework_2() {
    print_header "作业 2: 分析 checkm8 地址常量"

    echo -e "${YELLOW}请打开以下文件进行分析:${NC}"
    echo "checkra1n_research/ipwndfu/checkm8.py"
    echo ""
    echo -e "${YELLOW}找到 T8015 配置 (第 376-424 行)，填写作业表中的地址表${NC}"
    echo ""
    echo -e "${BLUE}T8015 关键地址参考:${NC}"
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ ROM 区域 (0x100000000)                                      │"
    echo "│   - 只读，烧录在芯片中                                       │"
    echo "│   - 包含 gadgets 和系统函数                                  │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│ SRAM 区域 (0x180000000)                                     │"
    echo "│   - 可读写                                                  │"
    echo "│   - 存放 USB 数据结构和 payload                             │"
    echo "└─────────────────────────────────────────────────────────────┘"
}

homework_3() {
    print_header "作业 3: 追踪 exploit 执行流程"

    echo -e "${YELLOW}3.1 检查 checkra1n ramdisk 挂载${NC}"
    print_cmd "mount | grep -E 'checkra1n|disk4|disk5|binpack'"
    run_cmd "mount | grep -E 'checkra1n|disk4|disk5|binpack'"
    echo ""

    echo -e "${YELLOW}3.2 查看 checkra1n 提供的工具${NC}"
    print_cmd "ls -la /binpack/usr/local/bin/"
    run_cmd "ls -la /binpack/usr/local/bin/"
    echo ""

    echo -e "${YELLOW}3.3 使用 jtool2 分析系统二进制${NC}"
    print_cmd "/binpack/usr/local/bin/jtool2 -l /bin/ls | head -20"
    run_cmd "/binpack/usr/local/bin/jtool2 -l /bin/ls | head -20"
}

homework_4() {
    print_header "作业 4: 分析 ARM64 shellcode"

    echo -e "${YELLOW}请阅读以下源文件:${NC}"
    echo "checkra1n_research/ipwndfu/src/checkm8_arm64.S"
    echo "checkra1n_research/ipwndfu/src/usb_0xA1_2_arm64.S"
    echo ""

    echo -e "${YELLOW}4.1 验证 PWND 字符串${NC}"
    print_cmd "ioreg -l | grep -i pwnd"
    run_cmd "ioreg -l | grep -i pwnd" 2>/dev/null || echo "(可能没有直接显示)"
    echo ""

    echo -e "${BLUE}关键汇编指令解释:${NC}"
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ DC CIVAC, X0   - 清理并无效化数据缓存行                       │"
    echo "│ DSB SY         - 数据同步屏障，确保之前的操作完成              │"
    echo "│ ISB            - 指令同步屏障，刷新流水线                     │"
    echo "│ SYS #0,c7,c5,#0 - 无效化整个指令缓存                         │"
    echo "└─────────────────────────────────────────────────────────────┘"
}

homework_5() {
    print_header "作业 5: 理解 ROP 链"

    echo -e "${BLUE}T8015 ROP 链执行顺序:${NC}"
    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│  1. dc_civac (0x18001C800)    - 清理缓存行 1                 │"
    echo "│  2. dc_civac (0x18001C840)    - 清理缓存行 2                 │"
    echo "│  3. dc_civac (0x18001C880)    - 清理缓存行 3                 │"
    echo "│  4. dmb                        - 数据内存屏障                │"
    echo "│  5. write_sctlr (0x100D)      - ★ 禁用 WXN 保护             │"
    echo "│  6. load_write (0x18001C000)  - 设置数据                    │"
    echo "│  7. load_write (0x18001C010)  - 设置数据                    │"
    echo "│  8. write_ttbr0 (0x180020000) - 修改页表基址                 │"
    echo "│  9. tlbi                       - TLB 无效化                  │"
    echo "│ 10. load_write (0x18001C020)  - 设置数据                    │"
    echo "│ 11. write_ttbr0 (0x18000C000) - 修改页表基址                 │"
    echo "│ 12. tlbi                       - TLB 无效化                  │"
    echo "│ 13. 跳转到 0x18001C800        - 执行 shellcode              │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
    echo -e "${YELLOW}关键问题:${NC}"
    echo "Q1: 为什么要禁用 WXN (Write XOR Execute)?"
    echo "    → WXN 阻止同一内存页同时可写和可执行"
    echo "    → 禁用后才能执行我们注入的 shellcode"
    echo ""
    echo "Q2: 为什么要修改 TTBR0?"
    echo "    → TTBR0 是页表基址寄存器"
    echo "    → 修改它可以改变虚拟地址到物理地址的映射"
    echo ""
    echo "Q3: 为什么要执行 TLBI?"
    echo "    → TLB (Translation Lookaside Buffer) 缓存页表项"
    echo "    → 修改页表后必须刷新 TLB 才能生效"
}

homework_6() {
    print_header "作业 6: 对比不同芯片的配置"

    echo -e "${BLUE}请在 checkm8.py 中比较以下芯片配置:${NC}"
    echo ""
    echo "┌──────────────┬─────────────────┬─────────────────┬─────────────────┐"
    echo "│     项目     │   T8010 (A10)   │  T8011 (A10X)   │   T8015 (A11)   │"
    echo "├──────────────┼─────────────────┼─────────────────┼─────────────────┤"
    echo "│ LOAD_ADDRESS │  0x1800B0000    │  0x1800B0000    │  0x18001C000    │"
    echo "│ USB_CORE_DO  │  0x10000DC98    │  0x10000DD64    │  0x10000B9A8    │"
    echo "│ hole 值      │       5         │       6         │       6         │"
    echo "│ leak 值      │       1         │       1         │       1         │"
    echo "└──────────────┴─────────────────┴─────────────────┴─────────────────┘"
    echo ""
    echo -e "${YELLOW}思考:${NC}"
    echo "- 地址不同是因为每个芯片的 SecureROM 布局不同"
    echo "- hole 值决定了堆布局需要多少次分配/释放"
    echo "- 这些值是通过逆向工程和实验确定的"
}

homework_7() {
    print_header "作业 7: 使用 jtool2 分析 kernelcache"

    echo -e "${YELLOW}7.1 查看 kernelcache 头信息${NC}"
    print_cmd "/binpack/usr/local/bin/jtool2 -h /System/Library/Caches/com.apple.kernelcaches/kernelcache"
    run_cmd "/binpack/usr/local/bin/jtool2 -h /System/Library/Caches/com.apple.kernelcaches/kernelcache"
    echo ""

    echo -e "${YELLOW}7.2 列出安全相关的内核扩展${NC}"
    print_cmd "/binpack/usr/local/bin/jtool2 -k ... | grep -iE 'amfi|sandbox|trust|security'"
    run_cmd "/binpack/usr/local/bin/jtool2 -k /System/Library/Caches/com.apple.kernelcaches/kernelcache 2>&1 | grep -iE 'amfi|sandbox|trust|security|coretrust'"
    echo ""

    echo -e "${YELLOW}7.3 查看 Cydia 的 entitlements${NC}"
    print_cmd "/binpack/usr/local/bin/jtool2 --ent /Applications/Cydia.app/Cydia"
    run_cmd "/binpack/usr/local/bin/jtool2 --ent /Applications/Cydia.app/Cydia"
}

homework_8() {
    print_header "作业 8: 追踪系统调用"

    echo -e "${YELLOW}8.1 查看安全相关进程${NC}"
    print_cmd "ps aux | grep -E 'amfi|trustd|securityd'"
    run_cmd "ps aux | grep -E 'amfi|trustd|securityd' | grep -v grep"
    echo ""

    echo -e "${YELLOW}8.2 查看安全相关 launchd 服务${NC}"
    print_cmd "launchctl list | grep -iE 'security|trust'"
    run_cmd "launchctl list | grep -iE 'security|trust'"
    echo ""

    echo -e "${YELLOW}8.3 查看代码签名状态${NC}"
    print_cmd "sysctl vm.cs_force_kill vm.cs_force_hard vm.cs_debug"
    run_cmd "sysctl vm.cs_force_kill vm.cs_force_hard vm.cs_debug"
    echo ""

    echo -e "${YELLOW}8.4 查看 MAC 安全策略${NC}"
    print_cmd "sysctl security.mac"
    run_cmd "sysctl security.mac"
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
    echo -e "${YELLOW}        阶段 1 作业执行脚本 - checkm8 学习${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  1) 作业 1: 验证设备硬件信息"
    echo "  2) 作业 2: 分析 checkm8 地址常量"
    echo "  3) 作业 3: 追踪 exploit 执行流程"
    echo "  4) 作业 4: 分析 ARM64 shellcode"
    echo "  5) 作业 5: 理解 ROP 链"
    echo "  6) 作业 6: 对比不同芯片的配置"
    echo "  7) 作业 7: 使用 jtool2 分析 kernelcache"
    echo "  8) 作业 8: 追踪系统调用"
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
