// myromctl: tiny iOS-side reader for IODeviceTree:/chosen `myrom-manifest`.
//
// Build on macOS with Xcode toolchain (see build_and_deploy.sh), then deploy to
// a jailbroken device. This avoids depending on `ioreg` being present on-device.

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>

#include <mach/mach.h>

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static size_t my_strnlen(const char *s, size_t maxlen)
{
    size_t n = 0;
    if (!s) return 0;
    while (n < maxlen && s[n] != '\0') n++;
    return n;
}

static int write_all(int fd, const void *buf, size_t n)
{
    const unsigned char *p = (const unsigned char *)buf;
    while (n > 0) {
        ssize_t w = write(fd, p, n);
        if (w < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        p += (size_t)w;
        n -= (size_t)w;
    }
    return 0;
}

static int write_file(const char *path, const void *buf, size_t n, int append)
{
    int flags = O_WRONLY | O_CREAT;
    flags |= append ? O_APPEND : O_TRUNC;

    int fd = open(path, flags, 0644);
    if (fd < 0) return -1;
    int rc = write_all(fd, buf, n);
    int saved = errno;
    close(fd);
    errno = saved;
    return rc;
}

static void usage(const char *argv0)
{
    fprintf(stderr,
            "Usage:\n"
            "  %s print\n"
            "  %s dump <path>\n"
            "  %s append <path>\n",
            argv0, argv0, argv0);
}

int main(int argc, char **argv)
{
    const char *cmd = (argc >= 2) ? argv[1] : "print";
    const char *path = (argc >= 3) ? argv[2] : NULL;

    if ((strcmp(cmd, "dump") == 0 || strcmp(cmd, "append") == 0) && !path) {
        usage(argv[0]);
        return 64;
    }

    // Passing MACH_PORT_NULL means "use the default IOKit main port".
    io_registry_entry_t chosen = IORegistryEntryFromPath(MACH_PORT_NULL, "IODeviceTree:/chosen");
    if (!chosen) {
        fprintf(stderr, "myromctl: IORegistryEntryFromPath(IODeviceTree:/chosen) failed\n");
        return 1;
    }

    CFTypeRef prop = IORegistryEntryCreateCFProperty(chosen, CFSTR("myrom-manifest"), kCFAllocatorDefault, 0);
    IOObjectRelease(chosen);

    if (!prop) {
        fprintf(stderr, "myromctl: property not found: myrom-manifest\n");
        return 2;
    }

    const void *bytes = NULL;
    size_t len = 0;
    size_t printable_len = 0;

    if (CFGetTypeID(prop) == CFDataGetTypeID()) {
        CFDataRef d = (CFDataRef)prop;
        bytes = (const void *)CFDataGetBytePtr(d);
        len = (size_t)CFDataGetLength(d);
        printable_len = my_strnlen((const char *)bytes, len);
    } else if (CFGetTypeID(prop) == CFStringGetTypeID()) {
        CFStringRef s = (CFStringRef)prop;
        // Convert via UTF-8. (Our writer stores ASCII JSON + NUL.)
        char tmp[1024];
        if (!CFStringGetCString(s, tmp, (CFIndex)sizeof(tmp), kCFStringEncodingUTF8)) {
            fprintf(stderr, "myromctl: failed to convert CFString to UTF-8\n");
            CFRelease(prop);
            return 3;
        }
        bytes = tmp;
        len = strlen(tmp);
        printable_len = len;
        if (strcmp(cmd, "print") == 0) {
            fwrite(bytes, 1, printable_len, stdout);
            fputc('\n', stdout);
            CFRelease(prop);
            return 0;
        }
        int append = (strcmp(cmd, "append") == 0);
        if (write_file(path, bytes, printable_len, append) != 0 ||
            write_file(path, "\n", 1, 1) != 0) {
            fprintf(stderr, "myromctl: write(%s) failed: %s\n", path, strerror(errno));
            CFRelease(prop);
            return 4;
        }
        CFRelease(prop);
        return 0;
    } else {
        fprintf(stderr, "myromctl: unexpected property type (CFTypeID=%lu)\n", (unsigned long)CFGetTypeID(prop));
        CFRelease(prop);
        return 3;
    }

    // Default: print (for CFData values we expect NUL-terminated JSON).
    if (strcmp(cmd, "print") == 0) {
        fwrite(bytes, 1, printable_len, stdout);
        fputc('\n', stdout);
        CFRelease(prop);
        return 0;
    }

    int append = (strcmp(cmd, "append") == 0);
    if (write_file(path, bytes, printable_len, append) != 0 ||
        write_file(path, "\n", 1, 1) != 0) {
        fprintf(stderr, "myromctl: write(%s) failed: %s\n", path, strerror(errno));
        CFRelease(prop);
        return 4;
    }

    CFRelease(prop);
    return 0;
}
