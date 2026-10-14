//! The editor's window: SDL3 for the window and its events, SDL_GPU to draw, and Dear ImGui's own
//! SDL3 and SDL_GPU backends to feed ImGui the events and draw what it makes.

const std = @import("std");
const c = @import("c");

const icon = @import("icon.zig");

pub const Error = error{Sdl};

/// SDL's last error, logged under the call `what` that failed, as an error.
fn fail(what: []const u8) Error {
    logError(what);
    return error.Sdl;
}

fn logError(what: []const u8) void {
    std.log.scoped(.sdl).err("{s}: {s}", .{ what, c.SDL_GetError() });
}

/// How long the window waits for an event before it draws again when nothing happens, which keeps
/// the text cursor blinking and timed messages going while the editor is idle.
const idle_wait_ms = 250;

/// How many frames the window keeps drawing after the last event, which ImGui needs to settle
/// what an event changed, such as a window that resizes to fit its contents.
const settle_frames = 3;

pub const Window = struct {
    handle: *c.SDL_Window,
    gpu: *c.SDL_GPUDevice,
    /// The display's scale, such as 1.5 at 150%, which the style and the fonts are sized by.
    scale: f32,
    /// Whether the system asked the window to close, for the editor to decide.
    close_asked: bool = false,
    /// Frames left to draw before the window waits for the next event.
    busy_frames: u8 = settle_frames,
    /// A file dropped on the window since the last frame, copied from SDL's event, which SDL
    /// frees with the next one.
    dropped: ?[]const u8 = null,
    dropped_buffer: [4096]u8 = undefined,

    /// A window of `width` by `height` points at the display's scale, with ImGui set up to draw
    /// in it. ImGui keeps its layout in `ini_path`, or nowhere when it's null. A hidden window
    /// only draws into pictures (`capture`).
    pub fn open(title: [*:0]const u8, width: u32, height: u32, ini_path: ?[*:0]const u8, hidden: bool) Error!Window {
        if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return fail("SDL_Init");
        errdefer c.SDL_Quit();
        const scale = displayScale();
        const flags = c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_HIDDEN | c.SDL_WINDOW_HIGH_PIXEL_DENSITY;
        const handle = c.SDL_CreateWindow(title, @intFromFloat(@as(f32, @floatFromInt(width)) * scale), @intFromFloat(@as(f32, @floatFromInt(height)) * scale), flags) orelse return fail("SDL_CreateWindow");
        errdefer c.SDL_DestroyWindow(handle);
        _ = c.SDL_SetWindowPosition(handle, c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED);
        _ = c.SDL_SetWindowMinimumSize(handle, 800, 520);
        // The shader formats ImGui's backend carries: Vulkan's, and Metal's on Apple's systems,
        // as OpenReliant draws.
        const gpu = c.SDL_CreateGPUDevice(c.SDL_GPU_SHADERFORMAT_SPIRV | c.SDL_GPU_SHADERFORMAT_MSL | c.SDL_GPU_SHADERFORMAT_METALLIB, false, null) orelse return fail("SDL_CreateGPUDevice");
        errdefer c.SDL_DestroyGPUDevice(gpu);
        if (!c.SDL_ClaimWindowForGPUDevice(gpu, handle)) return fail("SDL_ClaimWindowForGPUDevice");
        errdefer c.SDL_ReleaseWindowFromGPUDevice(gpu, handle);
        _ = c.SDL_SetGPUSwapchainParameters(gpu, handle, c.SDL_GPU_SWAPCHAINCOMPOSITION_SDR, c.SDL_GPU_PRESENTMODE_VSYNC);
        // A text field takes text through the system's input methods only while one has the
        // focus, which ImGui's backend tells SDL.
        _ = c.SDL_StopTextInput(handle);

        _ = c.ImGui_CreateContext(null);
        const io = c.ImGui_GetIO();
        io.*.ConfigFlags |= c.ImGuiConfigFlags_DockingEnable | c.ImGuiConfigFlags_NavEnableKeyboard;
        io.*.IniFilename = ini_path;
        // Windows move by their title bars and tabs only, as in other editors, so that dragging in
        // a panel's contents never moves the panel.
        io.*.ConfigWindowsMoveFromTitleBarOnly = true;
        io.*.ConfigDockingWithShift = false;
        if (!c.cImGui_ImplSDL3_InitForSDLGPU(handle)) return fail("ImGui_ImplSDL3_InitForSDLGPU");
        var info: c.ImGui_ImplSDLGPU3_InitInfo = .{
            .Device = gpu,
            .ColorTargetFormat = c.SDL_GetGPUSwapchainTextureFormat(gpu, handle),
            .MSAASamples = c.SDL_GPU_SAMPLECOUNT_1,
            .SwapchainComposition = c.SDL_GPU_SWAPCHAINCOMPOSITION_SDR,
            .PresentMode = c.SDL_GPU_PRESENTMODE_VSYNC,
        };
        if (!c.cImGui_ImplSDLGPU3_Init(&info)) return fail("ImGui_ImplSDLGPU3_Init");
        icon.set(handle);
        if (!hidden) _ = c.SDL_ShowWindow(handle);
        return .{ .handle = handle, .gpu = gpu, .scale = scale };
    }

    pub fn close(window: *Window) void {
        _ = c.SDL_WaitForGPUIdle(window.gpu);
        c.cImGui_ImplSDL3_Shutdown();
        c.cImGui_ImplSDLGPU3_Shutdown();
        c.ImGui_DestroyContext(null);
        c.SDL_ReleaseWindowFromGPUDevice(window.gpu, window.handle);
        c.SDL_DestroyGPUDevice(window.gpu);
        c.SDL_DestroyWindow(window.handle);
        c.SDL_Quit();
    }

    /// Hands the system's events to ImGui, waiting for one when nothing has happened for a few
    /// frames, then starts ImGui's frame. False while the window is minimized, when there is
    /// nothing to draw.
    pub fn beginFrame(window: *Window) bool {
        window.dropped = null;
        var event: c.SDL_Event = undefined;
        if (window.busy_frames == 0) {
            if (c.SDL_WaitEventTimeout(&event, idle_wait_ms)) {
                window.handleEvent(&event);
            }
        }
        while (c.SDL_PollEvent(&event)) window.handleEvent(&event);
        if (window.busy_frames > 0) window.busy_frames -= 1;
        if (c.SDL_GetWindowFlags(window.handle) & c.SDL_WINDOW_MINIMIZED != 0) {
            c.SDL_Delay(10);
            return false;
        }
        c.cImGui_ImplSDLGPU3_NewFrame();
        c.cImGui_ImplSDL3_NewFrame();
        c.ImGui_NewFrame();
        return true;
    }

    fn handleEvent(window: *Window, event: *const c.SDL_Event) void {
        _ = c.cImGui_ImplSDL3_ProcessEvent(event);
        window.busy_frames = settle_frames;
        switch (event.type) {
            c.SDL_EVENT_QUIT => window.close_asked = true,
            c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => if (event.window.windowID == c.SDL_GetWindowID(window.handle)) {
                window.close_asked = true;
            },
            c.SDL_EVENT_DROP_FILE => if (event.drop.data) |data| {
                const path = std.mem.span(data);
                if (path.len <= window.dropped_buffer.len) {
                    @memcpy(window.dropped_buffer[0..path.len], path);
                    window.dropped = window.dropped_buffer[0..path.len];
                }
            },
            else => {},
        }
    }

    /// Keeps the window drawing frames without waiting for events, for something that moves, such
    /// as a timed message fading out.
    pub fn keepBusy(window: *Window) void {
        window.busy_frames = settle_frames;
    }

    /// Draws ImGui's frame on `background` and shows it.
    pub fn endFrame(window: *Window, background: [4]f32) void {
        c.ImGui_Render();
        const draw_data = c.ImGui_GetDrawData();
        const minimized = draw_data.*.DisplaySize.x <= 0 or draw_data.*.DisplaySize.y <= 0;
        const commands = c.SDL_AcquireGPUCommandBuffer(window.gpu) orelse {
            logError("SDL_AcquireGPUCommandBuffer");
            return;
        };
        var swapchain: ?*c.SDL_GPUTexture = null;
        if (!c.SDL_WaitAndAcquireGPUSwapchainTexture(commands, window.handle, &swapchain, null, null)) {
            logError("SDL_WaitAndAcquireGPUSwapchainTexture");
        }
        if (swapchain) |texture| if (!minimized) {
            c.cImGui_ImplSDLGPU3_PrepareDrawData(draw_data, commands);
            const target: c.SDL_GPUColorTargetInfo = .{
                .texture = texture,
                .clear_color = .{ .r = background[0], .g = background[1], .b = background[2], .a = background[3] },
                .load_op = c.SDL_GPU_LOADOP_CLEAR,
                .store_op = c.SDL_GPU_STOREOP_STORE,
            };
            const pass = c.SDL_BeginGPURenderPass(commands, &target, 1, null);
            c.cImGui_ImplSDLGPU3_RenderDrawData(draw_data, commands, pass);
            c.SDL_EndGPURenderPass(pass);
        };
        _ = c.SDL_SubmitGPUCommandBuffer(commands);
    }

    /// Draws ImGui's frame into a picture rather than on the screen, and saves it as a PNG file
    /// at `path`: for checking the screens against the design without showing a window.
    pub fn capture(window: *Window, background: [4]f32, path: [*:0]const u8) Error!void {
        c.ImGui_Render();
        const draw_data = c.ImGui_GetDrawData();
        const width: u32 = @intFromFloat(draw_data.*.DisplaySize.x * draw_data.*.FramebufferScale.x);
        const height: u32 = @intFromFloat(draw_data.*.DisplaySize.y * draw_data.*.FramebufferScale.y);
        const format = c.SDL_GetGPUSwapchainTextureFormat(window.gpu, window.handle);
        const texture = c.SDL_CreateGPUTexture(window.gpu, &.{
            .type = c.SDL_GPU_TEXTURETYPE_2D,
            .format = format,
            .usage = c.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET,
            .width = width,
            .height = height,
            .layer_count_or_depth = 1,
            .num_levels = 1,
        }) orelse return fail("SDL_CreateGPUTexture");
        defer c.SDL_ReleaseGPUTexture(window.gpu, texture);
        const size = width * height * 4;
        const transfer = c.SDL_CreateGPUTransferBuffer(window.gpu, &.{ .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD, .size = size }) orelse return fail("SDL_CreateGPUTransferBuffer");
        defer c.SDL_ReleaseGPUTransferBuffer(window.gpu, transfer);
        const commands = c.SDL_AcquireGPUCommandBuffer(window.gpu) orelse return fail("SDL_AcquireGPUCommandBuffer");
        c.cImGui_ImplSDLGPU3_PrepareDrawData(draw_data, commands);
        const target: c.SDL_GPUColorTargetInfo = .{
            .texture = texture,
            .clear_color = .{ .r = background[0], .g = background[1], .b = background[2], .a = background[3] },
            .load_op = c.SDL_GPU_LOADOP_CLEAR,
            .store_op = c.SDL_GPU_STOREOP_STORE,
        };
        const pass = c.SDL_BeginGPURenderPass(commands, &target, 1, null);
        c.cImGui_ImplSDLGPU3_RenderDrawData(draw_data, commands, pass);
        c.SDL_EndGPURenderPass(pass);
        const copy = c.SDL_BeginGPUCopyPass(commands);
        c.SDL_DownloadFromGPUTexture(copy, &.{ .texture = texture, .w = width, .h = height, .d = 1 }, &.{ .transfer_buffer = transfer });
        c.SDL_EndGPUCopyPass(copy);
        const fence = c.SDL_SubmitGPUCommandBufferAndAcquireFence(commands) orelse return fail("SDL_SubmitGPUCommandBufferAndAcquireFence");
        defer c.SDL_ReleaseGPUFence(window.gpu, fence);
        if (!c.SDL_WaitForGPUFences(window.gpu, true, &fence, 1)) return fail("SDL_WaitForGPUFences");
        const pixels = c.SDL_MapGPUTransferBuffer(window.gpu, transfer, false) orelse return fail("SDL_MapGPUTransferBuffer");
        defer c.SDL_UnmapGPUTransferBuffer(window.gpu, transfer);
        const pixel_format: c.SDL_PixelFormat = if (format == c.SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM) c.SDL_PIXELFORMAT_BGRA32 else c.SDL_PIXELFORMAT_RGBA32;
        const surface = c.SDL_CreateSurfaceFrom(@intCast(width), @intCast(height), pixel_format, pixels, @intCast(width * 4)) orelse return fail("SDL_CreateSurfaceFrom");
        defer c.SDL_DestroySurface(surface);
        if (!c.SDL_SavePNG(surface, path)) return fail("SDL_SavePNG");
    }

    pub fn toggleFullScreen(window: *Window) void {
        const full = c.SDL_GetWindowFlags(window.handle) & c.SDL_WINDOW_FULLSCREEN != 0;
        _ = c.SDL_SetWindowFullscreen(window.handle, !full);
    }

    /// Brings the window in front of the others, as the game holds the script.
    pub fn raise(window: *Window) void {
        _ = c.SDL_RaiseWindow(window.handle);
    }

    pub fn setTitle(window: *Window, title: [*:0]const u8) void {
        _ = c.SDL_SetWindowTitle(window.handle, title);
    }
};

/// The primary display's content scale, such as 1.5 for a display at 150%, or 1 where it's unknown.
fn displayScale() f32 {
    const scale = c.SDL_GetDisplayContentScale(c.SDL_GetPrimaryDisplay());
    return if (scale > 0) scale else 1;
}
