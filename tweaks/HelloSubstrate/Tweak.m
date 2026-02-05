#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#include "substrate.h"

#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>

static const char *kLogPath = "/var/tmp/hello_substrate_springboard.log";

static void hs_append_line(const char *line) {
  int fd = open(kLogPath, O_CREAT | O_WRONLY | O_APPEND, 0644);
  if (fd < 0) {
    return;
  }

  (void)write(fd, line, (size_t)strlen(line));
  (void)write(fd, "\n", 1);
  (void)close(fd);
}

static void hs_logf(NSString *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
  va_end(ap);

  // Also emit to system log (best-effort).
  NSLog(@"[HelloSubstrate] %@", msg);

  // Persist to a known path so we can verify via SSH after respring.
  hs_append_line([[NSString stringWithFormat:@"[HelloSubstrate] %@", msg] UTF8String]);
}

static void (*orig_UIApplication_sendEvent)(UIApplication *self, SEL _cmd, UIEvent *event);

static void replaced_UIApplication_sendEvent(UIApplication *self, SEL _cmd, UIEvent *event) {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    hs_logf(@"Hook fired: -[UIApplication sendEvent:] (first event observed)");
  });

  orig_UIApplication_sendEvent(self, _cmd, event);
}

__attribute__((constructor))
static void hello_substrate_init(void) {
  @autoreleasepool {
    NSString *proc = [NSProcessInfo processInfo].processName ?: @"(unknown)";
    NSString *bundle = [NSBundle mainBundle].bundleIdentifier ?: @"(no bundle id)";
    hs_logf(@"Loaded. process=%@ bundle=%@", proc, bundle);

    Class UIApplicationClass = objc_getClass("UIApplication");
    if (UIApplicationClass == Nil) {
      hs_logf(@"ERROR: objc_getClass(\"UIApplication\") returned Nil");
      return;
    }

    SEL sel = @selector(sendEvent:);
    if (![UIApplicationClass instancesRespondToSelector:sel]) {
      hs_logf(@"ERROR: UIApplication does not respond to sendEvent:");
      return;
    }

    MSHookMessageEx(
        UIApplicationClass,
        sel,
        (IMP)replaced_UIApplication_sendEvent,
        (IMP *)&orig_UIApplication_sendEvent);
    hs_logf(@"Installed hook: -[UIApplication sendEvent:]");
  }
}

