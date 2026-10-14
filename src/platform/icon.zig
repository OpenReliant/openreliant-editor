//! The editor's icon, OpenReliant's own, from OpenReliant's package (`assets/icon`), which the
//! window shows where the system takes a window's icon from the window: on macOS, where it is
//! also the application's in the Dock, and on Linux. On Windows, the executable carries it
//! (`build.zig`).

const std = @import("std");
const builtin = @import("builtin");
const c = @import("c");

/// The icon as PNG files, at the size for a display at 100% and at the size for one at 200%.
pub const pngs = [_][]const u8{ @embedFile("openreliant-256.png"), @embedFile("openreliant-512.png") };

/// Gives `window` the icon. A system that can't take a window's icon, such as a Wayland
/// compositor without the protocol for it, shows its own.
pub fn set(window: *c.SDL_Window) void {
    if (builtin.target.os.tag == .windows) return;
    const icon = surface(pngs[0]) orelse return;
    defer c.SDL_DestroySurface(icon);
    for (pngs[1..]) |picture| {
        const larger = surface(picture) orelse continue;
        defer c.SDL_DestroySurface(larger);
        _ = c.SDL_AddSurfaceAlternateImage(icon, larger);
    }
    _ = c.SDL_SetWindowIcon(window, icon);
}

/// The PNG file `bytes` as a surface.
fn surface(bytes: []const u8) ?*c.SDL_Surface {
    const stream = c.SDL_IOFromConstMem(bytes.ptr, bytes.len) orelse return null;
    return c.SDL_LoadPNG_IO(stream, true);
}

test "the icon's pictures are PNG files of their sizes" {
    for (pngs, [_]u32{ 256, 512 }) |file, side| {
        try std.testing.expectEqualStrings("\x89PNG", file[0..4]);
        // The header's width and height, after the signature and the IHDR chunk's length and type.
        try std.testing.expectEqual(side, std.mem.readInt(u32, file[16..20], .big));
        try std.testing.expectEqual(side, std.mem.readInt(u32, file[20..24], .big));
    }
}
