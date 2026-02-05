# 阶段 3：越狱后环境与 Tweak 开发学习指南

> 学习目标：理解越狱后的运行时环境，掌握函数 Hook 技术和 Tweak 开发基础

---

## 📋 学习概览

| 项目 | 内容 |
|------|------|
| **前置条件** | 完成阶段 1 (checkm8) 和阶段 2 (KPF) |
| **学习周期** | 建议 3-4 周 |
| **核心技术** | Substrate/Substitute, Hook, Tweak |
| **目标** | 能够开发简单的 iOS Tweak |

---

## 🏗️ 知识架构

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         越狱后技术栈                                     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   阶段 1          阶段 2           阶段 3 (本章)                         │
│   ┌────────┐     ┌────────┐      ┌─────────────────────────────┐       │
│   │checkm8 │ ──▶ │  KPF   │ ──▶  │     越狱后环境              │       │
│   │        │     │        │      │  ┌─────────────────────┐    │       │
│   │SecureROM│     │内核补丁│      │  │ Substrate/Substitute│    │       │
│   │ exploit│     │        │      │  │     (Hook 框架)     │    │       │
│   └────────┘     └────────┘      │  └──────────┬──────────┘    │       │
│                                  │             │               │       │
│                                  │  ┌──────────▼──────────┐    │       │
│                                  │  │      Tweaks         │    │       │
│                                  │  │   (功能扩展插件)     │    │       │
│                                  │  └─────────────────────┘    │       │
│                                  └─────────────────────────────┘       │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 📚 第一周：Hook 框架基础

### 1.1 什么是 Hook？

**定义：**
```
Hook = 钩子 = 拦截并修改程序行为的技术

当程序调用某个函数时：
  正常：  App → 原始函数 → 返回结果
  Hook后：App → 你的代码 → (可选)原始函数 → 返回结果
```

**用人话说：**
```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   想象你在餐厅点餐：                                         │
│                                                             │
│   正常流程：                                                 │
│   你 → 服务员 → 厨房 → 菜端上来                              │
│                                                             │
│   Hook 后：                                                  │
│   你 → 服务员 → [你的人] → 厨房 → 菜端上来                   │
│                    ↑                                        │
│              可以偷看订单                                    │
│              可以修改订单                                    │
│              可以直接返回假的菜                              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 iOS 上的 Hook 框架

| 框架 | 说明 | 状态 |
|------|------|------|
| **Cydia Substrate** | 最经典的 Hook 框架，saurik 开发 | 老牌，iOS 12 前主流 |
| **Substitute** | 开源替代品，comex 开发 | checkra1n 默认使用 |
| **libhooker** | 新一代框架，CoolStar 开发 | 性能更好 |
| **fishhook** | Facebook 开源，只能 hook C 函数 | 轻量级 |
| **frida** | 动态插桩框架，跨平台 | 调试/逆向用 |

**你的设备状态：**
```bash
# 检查已安装的 Hook 框架
sshpass -p 'alpine' ssh -p 2222 root@localhost \
  "dpkg -l | grep -iE 'substrate|substitute|libhooker'"
```

### 1.3 Hook 的实现原理

#### 方法 1：Inline Hook (内联钩子)

```
原理：直接修改函数开头的指令，跳转到你的代码

┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   原始函数：                                                 │
│   ┌─────────────────────┐                                   │
│   │ STP X29, X30, [SP]  │ ← 函数开头                        │
│   │ MOV X29, SP         │                                   │
│   │ ...                 │                                   │
│   │ RET                 │                                   │
│   └─────────────────────┘                                   │
│                                                             │
│   Hook 后：                                                  │
│   ┌─────────────────────┐      ┌─────────────────────┐      │
│   │ B  my_hook_func     │ ──▶  │ 你的 Hook 函数      │      │
│   │ (原指令被覆盖)       │      │ ...                │      │
│   │ ...                 │  ┌── │ BL original_func   │      │
│   │ RET                 │  │   │ ...                │      │
│   └─────────────────────┘  │   │ RET                │      │
│                            │   └─────────────────────┘      │
│   ┌─────────────────────┐  │                                │
│   │ 保存的原始指令       │ ◀┘                                │
│   │ STP X29, X30, [SP]  │                                   │
│   │ B  original+8       │ ← 跳回原函数继续执行               │
│   └─────────────────────┘                                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

#### 方法 2：Method Swizzling (ObjC 方法交换)

```
原理：修改 ObjC 类的方法实现指针

┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   ObjC 类结构：                                              │
│   ┌─────────────────────────────────────────┐               │
│   │ Class: UIViewController                 │               │
│   │ ┌─────────────────────────────────────┐ │               │
│   │ │ Method: viewDidLoad                 │ │               │
│   │ │ IMP: 0x12345678 ──────────────────┐ │ │               │
│   │ └─────────────────────────────────┘ │ │ │               │
│   └───────────────────────────────────┘ │ │ │               │
│                                         │ │                 │
│                                         ▼ │                 │
│   ┌─────────────────────────────────────┐ │                 │
│   │ 原始 viewDidLoad 实现               │ │                 │
│   └─────────────────────────────────────┘ │                 │
│                                           │                 │
│   Swizzle 后：                            │                 │
│   ┌─────────────────────────────────────┐ │                 │
│   │ IMP: 0xAABBCCDD ──────────────────┐ │ │                 │
│   └─────────────────────────────────┘ │ │ │                 │
│                                       ▼ │                   │
│   ┌─────────────────────────────────────┐                   │
│   │ 你的 hook_viewDidLoad 实现          │                   │
│   │ {                                   │                   │
│   │   NSLog(@"viewDidLoad 被调用!");    │                   │
│   │   [self original_viewDidLoad];     │ ← 调用原实现       │
│   │ }                                   │                   │
│   └─────────────────────────────────────┘                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 1.4 Substrate API

**核心函数：**

```objc
// 1. Hook C/C++ 函数
void MSHookFunction(void *symbol, void *replace, void **original);

// 示例：Hook open() 系统调用
static int (*original_open)(const char *path, int flags, ...);

int hooked_open(const char *path, int flags, ...) {
    NSLog(@"App 试图打开: %s", path);
    return original_open(path, flags);  // 调用原函数
}

// 安装 Hook
MSHookFunction((void *)open, (void *)hooked_open, (void **)&original_open);
```

```objc
// 2. Hook ObjC 方法
void MSHookMessageEx(Class class, SEL selector, IMP replacement, IMP *original);

// 示例：Hook UIAlertController 的 show 方法
static void (*original_show)(id self, SEL _cmd);

void hooked_show(id self, SEL _cmd) {
    NSLog(@"有弹窗要显示!");
    original_show(self, _cmd);  // 调用原方法
}

// 安装 Hook
MSHookMessageEx(
    objc_getClass("UIAlertController"),
    @selector(show),
    (IMP)hooked_show,
    (IMP *)&original_show
);
```

---

## 🔧 第二周：Tweak 开发入门

### 2.1 什么是 Tweak？

```
Tweak = 插件 = 利用 Hook 技术修改系统或 App 行为的动态库

┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   Tweak 的本质：                                             │
│                                                             │
│   1. 一个 .dylib 动态库文件                                  │
│   2. 被注入到目标进程中                                      │
│   3. 在进程启动时自动执行                                    │
│   4. Hook 目标函数，修改行为                                 │
│                                                             │
│   常见 Tweak 示例：                                          │
│   • 去除 App 广告                                           │
│   • 修改 UI 外观                                            │
│   • 添加新功能                                              │
│   • 绕过某些限制                                            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Tweak 文件结构

```
MyTweak/
├── Makefile              ← 编译配置
├── control               ← 包信息 (名称、版本、依赖)
├── MyTweak.plist         ← 注入目标配置
└── Tweak.x               ← 源代码 (Logos 语法)
    或 Tweak.xm           ← 源代码 (Logos + ObjC++)
```

### 2.3 Logos 语法

Logos 是 Theos 提供的预处理语法，简化 Hook 代码：

```objc
// ============ Tweak.x ============

// 声明要 Hook 的类
%hook UIViewController

// Hook viewDidLoad 方法
- (void)viewDidLoad {
    %orig;  // 调用原始方法
    NSLog(@"[MyTweak] viewDidLoad 被调用: %@", self);
}

// Hook 带参数的方法
- (void)viewWillAppear:(BOOL)animated {
    NSLog(@"[MyTweak] viewWillAppear: %d", animated);
    %orig(animated);  // 传递参数给原方法
}

// 修改返回值
- (BOOL)shouldAutorotate {
    return NO;  // 禁止自动旋转，不调用 %orig
}

%end  // 结束 hook UIViewController


// Hook 另一个类
%hook SBLockScreenManager

- (void)lockUIFromSource:(int)source withOptions:(id)options {
    NSLog(@"[MyTweak] 锁屏被触发!");
    %orig;
}

%end
```

**Logos 关键字：**

| 关键字 | 用途 |
|--------|------|
| `%hook ClassName` | 开始 Hook 一个类 |
| `%end` | 结束 Hook |
| `%orig` | 调用原始方法 |
| `%orig(args)` | 带参数调用原始方法 |
| `%new` | 添加新方法 |
| `%group` | 分组 Hook |
| `%init` | 初始化 Hook 组 |
| `%ctor` | 构造函数，Tweak 加载时执行 |
| `%dtor` | 析构函数，Tweak 卸载时执行 |

### 2.4 Theos 开发环境

**Theos = Tweak 开发工具链**

```bash
# 安装 Theos (在 Mac 上)
bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"

# 设置环境变量
export THEOS=~/theos
export PATH=$THEOS/bin:$PATH

# 创建新 Tweak 项目
cd ~/Projects
$THEOS/bin/nic.pl

# 选择模板:
# [1] iphone/tweak
# Project Name: MyFirstTweak
# Package Name: com.yourname.myfirsttweak
# Author: Your Name
# MobileSubstrate Bundle filter: com.apple.springboard
```

### 2.5 Makefile 配置

```makefile
# ============ Makefile ============

# 设备 IP 和端口 (用于安装)
THEOS_DEVICE_IP = localhost
THEOS_DEVICE_PORT = 2222

# 目标 iOS 版本
TARGET := iphone:clang:latest:12.0
ARCHS = arm64

# 包含 Theos 通用配置
include $(THEOS)/makefiles/common.mk

# Tweak 名称
TWEAK_NAME = MyFirstTweak

# 源文件
MyFirstTweak_FILES = Tweak.x

# 依赖的框架
MyFirstTweak_FRAMEWORKS = UIKit Foundation

# 编译选项
MyFirstTweak_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
```

### 2.6 control 文件

```
Package: com.yourname.myfirsttweak
Name: My First Tweak
Version: 1.0.0
Architecture: iphoneos-arm
Description: 我的第一个 Tweak
Maintainer: Your Name
Author: Your Name
Section: Tweaks
Depends: mobilesubstrate
```

### 2.7 plist 过滤器

```xml
<!-- MyFirstTweak.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Filter</key>
    <dict>
        <!-- 只注入到 SpringBoard -->
        <key>Bundles</key>
        <array>
            <string>com.apple.springboard</string>
        </array>
    </dict>
</dict>
</plist>
```

**常见 Bundle ID：**

| Bundle ID | 应用 |
|-----------|------|
| `com.apple.springboard` | 主屏幕/锁屏 |
| `com.apple.UIKit` | 所有 UIKit App |
| `com.apple.MobileSMS` | 短信 |
| `com.apple.mobilesafari` | Safari |
| `com.apple.Preferences` | 设置 |

---

## 🛠️ 第三周：实战项目

### 3.1 项目 1：Hello World Tweak

**目标：** 在 SpringBoard 启动时打印日志

```objc
// Tweak.x
%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    NSLog(@"[HelloTweak] SpringBoard 启动了!");

    // 显示一个提示
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Hello"
        message:@"Tweak 加载成功!"
        preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction
        actionWithTitle:@"OK"
        style:UIAlertActionStyleDefault
        handler:nil]];

    // 延迟显示，等 UI 准备好
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
        dispatch_get_main_queue(), ^{
            [[UIApplication sharedApplication].keyWindow.rootViewController
                presentViewController:alert animated:YES completion:nil];
        });
}

%end
```

### 3.2 项目 2：隐藏状态栏图标

**目标：** 隐藏状态栏上的某些图标

```objc
// Tweak.x
%hook UIStatusBarItem

- (id)initWithType:(int)type {
    // type 对应不同的状态栏项目
    // 例如：电池、信号、WiFi 等

    if (type == 8) {  // 假设 8 是某个图标
        return nil;   // 返回 nil 隐藏它
    }
    return %orig;
}

%end
```

### 3.3 项目 3：修改 App 行为

**目标：** 让某个 App 认为设备没有越狱

```objc
// Tweak.x

// Hook 文件存在检查
%hook NSFileManager

- (BOOL)fileExistsAtPath:(NSString *)path {
    // 隐藏越狱相关路径
    NSArray *jbPaths = @[
        @"/Applications/Cydia.app",
        @"/Library/MobileSubstrate",
        @"/bin/bash",
        @"/usr/sbin/sshd",
        @"/etc/apt",
        @"/private/var/lib/apt"
    ];

    for (NSString *jbPath in jbPaths) {
        if ([path hasPrefix:jbPath]) {
            return NO;  // 假装不存在
        }
    }
    return %orig;
}

%end

// Hook URL scheme 检查
%hook UIApplication

- (BOOL)canOpenURL:(NSURL *)url {
    NSArray *jbSchemes = @[@"cydia://", @"sileo://"];

    for (NSString *scheme in jbSchemes) {
        if ([[url absoluteString] hasPrefix:scheme]) {
            return NO;
        }
    }
    return %orig;
}

%end
```

### 3.4 项目 4：添加新功能

**目标：** 给 App 添加截图功能

```objc
// Tweak.x
%hook UIViewController

%new
- (void)takeScreenshot {
    UIGraphicsBeginImageContextWithOptions(self.view.bounds.size, NO, 0);
    [self.view drawViewHierarchyInRect:self.view.bounds afterScreenUpdates:YES];
    UIImage *screenshot = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    // 保存到相册
    UIImageWriteToSavedPhotosAlbum(screenshot, nil, nil, nil);

    NSLog(@"[MyTweak] 截图已保存!");
}

- (void)viewDidLoad {
    %orig;

    // 添加手势识别
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self
        action:@selector(takeScreenshot)];
    tap.numberOfTapsRequired = 3;  // 三击触发
    [self.view addGestureRecognizer:tap];
}

%end
```

---

## 🔬 第四周：进阶技术

### 4.1 逆向工程基础

**工具链：**

| 工具 | 用途 |
|------|------|
| **class-dump** | 导出 ObjC 类头文件 |
| **Hopper/IDA** | 反汇编、反编译 |
| **Frida** | 动态分析、Hook |
| **LLDB** | 调试器 |
| **Cycript** | 运行时探索 |

**class-dump 使用：**
```bash
# 导出 App 的头文件
class-dump -H /path/to/App.app/App -o ./headers/

# 查看某个类的方法
grep -r "methodName" ./headers/
```

### 4.2 运行时探索 (Cycript)

```bash
# 连接到进程
cycript -p SpringBoard

# 探索 UI 层级
UIApp.keyWindow.recursiveDescription().toString()

# 获取当前控制器
UIApp.keyWindow.rootViewController

# 调用方法
[UIApp setIdleTimerDisabled:YES]

# 修改属性
UIApp.keyWindow.backgroundColor = [UIColor redColor]
```

### 4.3 Frida 动态分析

```javascript
// frida_script.js

// Hook ObjC 方法
var className = "UIViewController";
var methodName = "- viewDidLoad";

var hook = ObjC.classes[className][methodName];
Interceptor.attach(hook.implementation, {
    onEnter: function(args) {
        console.log("[*] " + className + " " + methodName + " called");
        console.log("    self: " + ObjC.Object(args[0]));
    }
});

// Hook C 函数
Interceptor.attach(Module.findExportByName(null, "open"), {
    onEnter: function(args) {
        console.log("[*] open(" + Memory.readUtf8String(args[0]) + ")");
    }
});
```

```bash
# 运行 Frida
frida -U -f com.example.app -l frida_script.js --no-pause
```

### 4.4 调试技巧

```objc
// 在 Tweak 中添加调试日志
%hook SomeClass

- (void)someMethod {
    // 打印调用栈
    NSLog(@"[DEBUG] Call stack:\n%@", [NSThread callStackSymbols]);

    // 打印参数
    NSLog(@"[DEBUG] self = %@", self);

    %orig;
}

%end
```

---

## 📝 实践作业

### 作业 1：安装 Hook 框架

检查并安装 Substitute 或其他 Hook 框架。

### 作业 2：探索系统类

使用 class-dump 或 Cycript 探索 SpringBoard 的类结构。

### 作业 3：编写 Hello World Tweak

创建一个简单的 Tweak，在 SpringBoard 启动时显示提示。

### 作业 4：Hook 系统方法

Hook `UIAlertController` 的 `show` 方法，记录所有弹窗。

### 作业 5：逆向分析

选择一个 App，使用 class-dump 导出头文件，分析其结构。

### 作业 6：Frida 实践

使用 Frida 动态 Hook 一个 App，观察其行为。

---

## 🔗 参考资源

### 官方文档
- Theos Wiki: https://theos.dev/
- Logos 语法: https://theos.dev/docs/logos-syntax

### 推荐书籍
- iOS Application Security (David Thiel)
- iOS Hacker's Handbook

### 社区资源
- r/jailbreak
- iPhoneDevWiki

---

## ➡️ 学习路线总结

```
阶段 1: checkm8 (SecureROM exploit)
    ↓
阶段 2: pongoOS/KPF (内核补丁)
    ↓
阶段 3: Tweak 开发 (本章)
    ↓
进阶: 逆向工程、漏洞研究、安全分析
```

---

*文档版本: 1.0*
*创建日期: 2026-02-02*
*适用设备: iPhone X (A11/T8015) iOS 12.3.1*
