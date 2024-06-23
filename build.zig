const std = @import("std");
const Build = std.Build;

fn project_root(comptime path: []const u8) []const u8 {
    const root = std.fs.path.dirname(@src().file) orelse unreachable;
    return std.fmt.comptimePrint("{s}/{s}", .{ root, path });
}

fn define_from_bool(val: bool) ?u1 {
    return if (val) 1 else null;
}

pub fn build(b: *Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const libusb = create_libusb(b, target.query, optimize);
    b.installArtifact(libusb);

    const build_all = b.step("all", "build libusb for all targets");
    for (targets) |t| {
        const lib = create_libusb(b, t, optimize);
        build_all.dependOn(&lib.step);
    }
}

fn create_libusb(
    b: *Build,
    target_: std.Target.Query,
    optimize: std.builtin.OptimizeMode,
) *Build.Step.Compile {
    const resolvedTarget = b.resolveTargetQuery(target_);
    const target = std.Target.Query.fromTarget(resolvedTarget.result);

    const is_posix =
        (target.os_tag != null and target.os_tag.?.isDarwin()) or
        target.os_tag == .linux or
        target.os_tag == .openbsd;

    const lib = b.addStaticLibrary(.{
        .name = "usb",
        .target = resolvedTarget,
        .optimize = optimize,
        .link_libc = true,
    });
    lib.addCSourceFiles(.{ .files = src });

    if (is_posix)
        lib.addCSourceFiles(.{ .files = posix_platform_src });

    if ((target.os_tag != null and target.os_tag.?.isDarwin())) {
        lib.addCSourceFiles(.{ .files = darwin_src });
        lib.linkFrameworkNeeded("IOKit");
        lib.linkFrameworkNeeded("Security");
    } else if (target.os_tag == .linux) {
        lib.addCSourceFiles(.{ .files = linux_src });
        lib.linkSystemLibrary("udev");
    } else if (target.os_tag == .windows) {
        lib.addCSourceFiles(.{ .files = windows_src });
        lib.addCSourceFiles(.{ .files = windows_platform_src });
    } else if (target.os_tag == .netbsd) {
        lib.addCSourceFiles(.{ .files = netbsd_src });
    } else if (target.os_tag == .openbsd) {
        lib.addCSourceFiles(.{ .files = openbsd_src });
    } else if (target.os_tag == .haiku) {
        lib.addCSourceFiles(.{ .files = haiku_src });
    } else if (target.os_tag == .solaris) {
        lib.addCSourceFiles(.{ .files = sunos_src });
    } else unreachable;

    lib.addIncludePath(b.path("libusb"));
    lib.installHeader(b.path("libusb/libusb.h"), "libusb.h");

    // config header
    if ((target.os_tag != null and target.os_tag.?.isDarwin())) {
        lib.addIncludePath(b.path("Xcode"));
    } else if (target.abi == .msvc) {
        lib.addIncludePath(b.path("msvc"));
    } else if (target.abi == .android) {
        lib.addIncludePath(b.path("android"));
    } else {
        const config_h = b.addConfigHeader(.{ .style = .{
            .autoconf = b.path("config.h.in"),
        } }, .{
            .DEFAULT_VISIBILITY = .@"__attribute__ ((visibility (\"default\")))",
            .ENABLE_DEBUG_LOGGING = define_from_bool(optimize == .Debug),
            .ENABLE_LOGGING = 1,
            .HAVE_ASM_TYPES_H = null,
            .HAVE_CLOCK_GETTIME = define_from_bool(!(target.os_tag == .windows)),
            .HAVE_DECL_EFD_CLOEXEC = null,
            .HAVE_DECL_EFD_NONBLOCK = null,
            .HAVE_DECL_TFD_CLOEXEC = null,
            .HAVE_DECL_TFD_NONBLOCK = null,
            .HAVE_DLFCN_H = null,
            .HAVE_EVENTFD = null,
            .HAVE_INTTYPES_H = null,
            .HAVE_IOKIT_USB_IOUSBHOSTFAMILYDEFINITIONS_H = define_from_bool((target.os_tag != null and target.os_tag.?.isDarwin())),
            .HAVE_LIBUDEV = null,
            .HAVE_NFDS_T = null,
            .HAVE_PIPE2 = null,
            .HAVE_PTHREAD_CONDATTR_SETCLOCK = null,
            .HAVE_PTHREAD_SETNAME_NP = null,
            .HAVE_PTHREAD_THREADID_NP = null,
            .HAVE_STDINT_H = 1,
            .HAVE_STDIO_H = 1,
            .HAVE_STDLIB_H = 1,
            .HAVE_STRINGS_H = 1,
            .HAVE_STRING_H = 1,
            .HAVE_STRUCT_TIMESPEC = 1,
            .HAVE_SYSLOG = define_from_bool(is_posix),
            .HAVE_SYS_STAT_H = 1,
            .HAVE_SYS_TIME_H = 1,
            .HAVE_SYS_TYPES_H = 1,
            .HAVE_TIMERFD = null,
            .HAVE_UNISTD_H = 1,
            .LT_OBJDIR = null,
            .PACKAGE = "libusb-1.0",
            .PACKAGE_BUGREPORT = "libusb-devel@lists.sourceforge.net",
            .PACKAGE_NAME = "libusb-1.0",
            .PACKAGE_STRING = "libusb-1.0 1.0.26",
            .PACKAGE_TARNAME = "libusb-1.0",
            .PACKAGE_URL = "http://libusb.info",
            .PACKAGE_VERSION = "1.0.26",
            .PLATFORM_POSIX = define_from_bool(is_posix),
            .PLATFORM_WINDOWS = define_from_bool(target.os_tag == .windows),
            .STDC_HEADERS = 1,
            .UMOCKDEV_HOTPLUG = null,
            .USE_SYSTEM_LOGGING_FACILITY = null,
            .VERSION = "1.0.26",
            ._GNU_SOURCE = 1,
            ._WIN32_WINNT = null,
            .@"inline" = null,
        });
        lib.addConfigHeader(config_h);
    }

    return lib;
}

const src = &.{
    "libusb/core.c",
    "libusb/descriptor.c",
    "libusb/hotplug.c",
    "libusb/io.c",
    "libusb/strerror.c",
    "libusb/sync.c",
};

const posix_platform_src: []const []const u8 = &.{
    "libusb/os/events_posix.c",
    "libusb/os/threads_posix.c",
};

const windows_platform_src: []const []const u8 = &.{
    "libusb/os/events_windows.c",
    "libusb/os/threads_windows.c",
};

const darwin_src: []const []const u8 = &.{
    "libusb/os/darwin_usb.c",
};

const haiku_src: []const []const u8 = &.{
    "libusb/os/haiku_pollfs.cpp",
    "libusb/os/haiku_usb_backend.cpp",
    "libusb/os/haiku_usb_raw.cpp",
};

const linux_src: []const []const u8 = &.{
    "libusb/os/linux_netlink.c",
    "libusb/os/linux_udev.c",
    "libusb/os/linux_usbfs.c",
};

const netbsd_src: []const []const u8 = &.{
    "libusb/os/netbsd_usb.c",
};

const null_src: []const []const u8 = &.{
    "libusb/os/null_usb.c",
};

const openbsd_src: []const []const u8 = &.{
    "libusb/os/openbsd_usb.c",
};

// sunos isn't supported by zig
const sunos_src: []const []const u8 = &.{
    "libusb/os/sunos_usb.c",
};

const windows_src: []const []const u8 = &.{
    "libusb/os/events_windows.c",
    "libusb/os/threads_windows.c",
    "libusb/os/windows_common.c",
    "libusb/os/windows_usbdk.c",
    "libusb/os/windows_winusb.c",
};

const targets: []const std.Target.Query = &.{
    // zig fmt: off
    .{},
    .{ .os_tag = .linux,   .cpu_arch = .x86_64,  .abi = .musl       },
    .{ .os_tag = .linux,   .cpu_arch = .x86_64,  .abi = .gnu        },
    .{ .os_tag = .linux,   .cpu_arch = .aarch64, .abi = .musl       },
    .{ .os_tag = .linux,   .cpu_arch = .aarch64, .abi = .gnu        },
    .{ .os_tag = .linux,   .cpu_arch = .arm,     .abi = .musleabi   },
    .{ .os_tag = .linux,   .cpu_arch = .arm,     .abi = .musleabihf },
    .{ .os_tag = .linux,   .cpu_arch = .arm,     .abi = .gnueabi    },
    .{ .os_tag = .linux,   .cpu_arch = .arm,     .abi = .gnueabihf  },
    .{ .os_tag = .macos,   .cpu_arch = .aarch64                     },
    .{ .os_tag = .macos,   .cpu_arch = .x86_64                      },
    .{ .os_tag = .windows, .cpu_arch = .aarch64                     },
    .{ .os_tag = .windows, .cpu_arch = .x86_64                      },
    .{ .os_tag = .netbsd,  .cpu_arch = .x86_64                      },
    .{ .os_tag = .openbsd, .cpu_arch = .x86_64                      },
    .{ .os_tag = .haiku,   .cpu_arch = .x86_64                      },
    .{ .os_tag = .solaris, .cpu_arch = .x86_64                      },
    // zig fmt: on
};
