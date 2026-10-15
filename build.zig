const std = @import("std");
const Translator = @import("translate_c").Translator;
const rc = @import("rc");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // The releases leave the debug information out of the editor.
    const strip = b.option(bool, "strip", "Leave the debug information out of the editor") orelse false;
    // The C and C++ libraries' headers become a Zig module through the translate-c package, as in
    // OpenReliant.
    const translate_c = b.dependency("translate_c", .{});

    // OpenReliant's library, which reads and writes missions exactly as the game does, and its
    // mission source parser, which builds missions from their source.
    const openreliant = b.dependency("openreliant", .{ .target = target, .optimize = optimize });

    // SDL3 for the window, the input and the GPU, the same package and version as OpenReliant's.
    // Building for a Mac other than the host, SDL and the editor need the SDK's paths: from xcrun.
    const macos_sdk: ?[]const u8 = if (target.result.os.tag == .macos and !target.query.isNative())
        std.mem.trimEnd(u8, b.run(&.{ "xcrun", "--sdk", "macosx", "--show-sdk-path" }), "\n")
    else
        null;
    const sdl_dependency = if (macos_sdk) |sdk| b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
        .system_include_path = b.graph.cwdRelativePath(b.pathJoin(&.{ sdk, "usr/include" })),
        .system_framework_path = b.graph.cwdRelativePath(b.pathJoin(&.{ sdk, "System/Library/Frameworks" })),
        .library_path = b.graph.cwdRelativePath(b.pathJoin(&.{ sdk, "usr/lib" })),
    }) else b.dependency("sdl", .{ .target = target, .optimize = optimize });
    const sdl_library = sdl_dependency.artifact("SDL3");

    // Dear ImGui's docking branch draws the whole interface. It is C++: Dear Bindings' C API wraps
    // it, its own backends drive it with SDL3 and SDL_GPU, and the text editor and the few
    // internal calls the editor makes join it through small C shims (`src/ui/text_editor`,
    // `src/ui/imgui_extras`).
    const interface = interfaceLibrary(b, target, sdl_library);
    if (macos_sdk) |sdk| addMacosSdk(b, interface.root_module, sdk);

    // The one translated header holds SDL, Dear ImGui and the text editor's shim, so that the types
    // they share, such as `SDL_GPUDevice`, are the same Zig types.
    const translator: Translator = .init(translate_c, .{
        .c_source_file = b.path("src/platform/c.h"),
        .target = target,
        .optimize = optimize,
        .default_init = true,
    });
    translator.linkLibrary(interface);
    translator.linkLibrary(sdl_library);
    for (interfaceIncludes(b)) |include| translator.addIncludePath(include);

    // The version Release Please keeps in build.zig.zon, and where the checkout is past its last
    // release, for `--version` (`src/version.zig`).
    const build_options = b.addOptions();
    build_options.addOption([]const u8, "version", @import("build.zig.zon").version);
    build_options.addOption([]const u8, "describe", describe(b));

    const editor = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip,
        .imports = &.{
            .{ .name = "openreliant", .module = openreliant.module("openreliant") },
            .{ .name = "source_parser", .module = openreliant.module("source_parser") },
            .{ .name = "c", .module = translator.mod },
        },
    });
    editor.addOptions("build_options", build_options);
    if (macos_sdk) |sdk| addMacosSdk(b, editor, sdk);
    addFonts(b, editor, openreliant);
    // Luau's licence goes with the program, whose mission source parser it is.
    b.getInstallStep().dependOn(&b.addInstallFile(openreliant.path("deps/luau/LICENSE.txt"), "LICENSE-luau.txt").step);
    // The editor's icon, which the window shows on macOS, also in the Dock, and on Linux
    // (`src/platform/icon.zig`). On Windows, the executable carries it.
    for ([_][]const u8{ "openreliant-editor-256.png", "openreliant-editor-512.png" }) |icon| {
        editor.addAnonymousImport(icon, .{ .root_source_file = b.path(b.fmt("assets/icon/{s}", .{icon})) });
    }

    const exe = b.addExecutable(.{ .name = "openreliant-editor", .root_module = editor });
    if (target.result.os.tag == .windows) addWindowsResources(b, exe, target, optimize);
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    run.addPassthruArgs();
    b.step("run", "Run the editor").dependOn(&run.step);

    // The tests, and `zig build check`, which compiles the program and the tests without linking
    // them: `zig build check -fincremental --watch` reports errors within moments of a save.
    const tests = b.addTest(.{ .root_module = editor });
    b.step("test", "Run tests").dependOn(&b.addRunArtifact(tests).step);
    const check = b.step("check", "Check that the program and the tests compile, without writing binaries");
    check.dependOn(&b.addTest(.{ .root_module = editor }).step);
    check.dependOn(&b.addExecutable(.{ .name = "openreliant-editor", .root_module = editor }).step);
}

/// Gives `module` the macOS SDK's headers, frameworks and libraries at `sdk`, which a build for a
/// Mac other than the host does not find by itself.
fn addMacosSdk(b: *std.Build, module: *std.Build.Module, sdk: []const u8) void {
    module.addSystemIncludePath(b.graph.cwdRelativePath(b.pathJoin(&.{ sdk, "usr/include" })));
    module.addSystemFrameworkPath(b.graph.cwdRelativePath(b.pathJoin(&.{ sdk, "System/Library/Frameworks" })));
    module.addLibraryPath(b.graph.cwdRelativePath(b.pathJoin(&.{ sdk, "usr/lib" })));
}

/// `git describe` of the checkout against the release tags, such as `v0.0.1-12-gabc1234-dirty`, or
/// nothing where there is no git or no tag, as in a source archive. The build can't track what
/// the answer depends on, so asking makes the build run build.zig again each time, as OpenReliant's
/// does.
fn describe(b: *std.Build) []const u8 {
    b.graph.poisonCache();
    const root = b.root.toString(b.allocator) catch @panic("out of memory");
    return switch (b.runFallible(&.{ "git", "-C", root, "describe", "--tags", "--match", "v*", "--long", "--dirty", "--abbrev=7" }, .{ .stderr_behavior = .ignore })) {
        .success => |out| std.mem.trimEnd(u8, out, "\n"),
        else => "",
    };
}

/// Gives the Windows executable the editor's icon (`assets/icon`), its name and version for the
/// file's properties and the Task Manager, and its manifest (`src/platform/windows.manifest`). The
/// rc package compiles them without the system's headers, so every system builds the same bytes.
/// Its compiler is built in Debug, which compiles fastest, as it reads only these few files.
fn addWindowsResources(b: *std.Build, exe: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, optimize: std.lang.Optimize) void {
    const version = @import("build.zig.zon").version;
    const numbers = std.SemanticVersion.parse(version) catch @panic("build.zig.zon's version isn't a semantic version");
    const script = b.addWriteFiles().add("editor.rc", b.fmt(
        \\1 ICON "openreliant-editor.ico"
        \\
        \\1 VERSIONINFO
        \\FILEVERSION {0d},{1d},{2d},0
        \\PRODUCTVERSION {0d},{1d},{2d},0
        \\BEGIN
        \\  BLOCK "StringFileInfo"
        \\  BEGIN
        \\    BLOCK "040904B0"
        \\    BEGIN
        \\      VALUE "ProductName", "OpenReliant Editor"
        \\      VALUE "FileDescription", "OpenReliant Editor"
        \\      VALUE "ProductVersion", "{3s}"
        \\      VALUE "FileVersion", "{3s}"
        \\      VALUE "OriginalFilename", "openreliant-editor.exe"
        \\    END
        \\  END
        \\  BLOCK "VarFileInfo"
        \\  BEGIN
        \\    VALUE "Translation", 0x0409, 1200
        \\  END
        \\END
        \\
    , .{ numbers.major, numbers.minor, numbers.patch, version }));
    const resources: rc.Compiler = .init(b.dependency("rc", .{ .optimize = .debug }), .{
        .rc_files = &.{script},
        .manifest = .{ .file = b.path("src/platform/windows.manifest"), .for_dll = false },
        .target = target,
        .optimize = optimize,
        .rc_options = .{ .auto_includes = .none, .include_paths = &.{b.path("assets/icon")} },
    });
    exe.root_module.addObjectFile(resources.getObjectFile());
}

/// Dear ImGui with its docking branch, Dear Bindings' C API over it, its SDL3 and SDL_GPU backends,
/// and the text editor and ImPlot with their C shims, as one static library. It is built optimized
/// whatever the editor's own mode, so that typing in a long mission stays smooth in a debug build
/// too.
fn interfaceLibrary(b: *std.Build, target: std.Build.ResolvedTarget, sdl_library: *std.Build.Step.Compile) *std.Build.Step.Compile {
    const imgui = b.dependency("imgui", .{});
    const bindings = b.dependency("dear_bindings", .{});
    const text_editor = b.dependency("text_editor", .{});
    const implot = b.dependency("implot", .{});
    const library = b.addLibrary(.{
        .name = "interface",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = .fast,
            .link_libcpp = true,
        }),
    });
    library.root_module.linkLibrary(sdl_library);
    for (interfaceIncludes(b)) |include| library.root_module.addIncludePath(include);
    const flags: []const []const u8 = &.{ "-std=c++17", "-fno-sanitize=undefined" };
    library.root_module.addCSourceFiles(.{
        .root = imgui.path("."),
        .files = &.{ "imgui.cpp", "imgui_draw.cpp", "imgui_tables.cpp", "imgui_widgets.cpp", "imgui_demo.cpp", "backends/imgui_impl_sdl3.cpp", "backends/imgui_impl_sdlgpu3.cpp" },
        .flags = flags,
    });
    library.root_module.addCSourceFiles(.{
        .root = bindings.path("."),
        .files = &.{ "dcimgui.cpp", "backends/dcimgui_impl_sdl3.cpp", "backends/dcimgui_impl_sdlgpu3.cpp" },
        .flags = flags,
    });
    library.root_module.addCSourceFile(.{ .file = text_editor.path("TextEditor.cpp"), .flags = flags });
    library.root_module.addCSourceFile(.{ .file = b.path("src/ui/text_editor/shim.cpp"), .flags = flags });
    library.root_module.addCSourceFile(.{ .file = b.path("src/ui/imgui_extras/extras.cpp"), .flags = flags });
    library.root_module.addCSourceFiles(.{ .root = implot.path("."), .files = &.{ "implot.cpp", "implot_items.cpp" }, .flags = flags });
    library.root_module.addCSourceFile(.{ .file = b.path("src/ui/plot/plot_shim.cpp"), .flags = flags });
    // The libraries' licences go with the program.
    for ([_]struct { std.Build.LazyPath, []const u8 }{
        .{ imgui.path("LICENSE.txt"), "LICENSE-imgui.txt" },
        .{ bindings.path("LICENSE.txt"), "LICENSE-dear-bindings.txt" },
        .{ text_editor.path("LICENSE"), "LICENSE-text-editor.txt" },
        .{ implot.path("LICENSE"), "LICENSE-implot.txt" },
    }) |notice| b.getInstallStep().dependOn(&b.addInstallFile(notice[0], notice[1]).step);
    return library;
}

/// The folders the interface's headers are in.
fn interfaceIncludes(b: *std.Build) [9]std.Build.LazyPath {
    const imgui = b.dependency("imgui", .{});
    const bindings = b.dependency("dear_bindings", .{});
    return .{
        imgui.path("."),
        imgui.path("backends"),
        bindings.path("."),
        bindings.path("backends"),
        b.dependency("text_editor", .{}).path("."),
        b.path("src/ui/text_editor"),
        b.path("src/ui/imgui_extras"),
        b.dependency("implot", .{}).path("."),
        b.path("src/ui/plot"),
    };
}

/// The fonts the editor carries, which `src/platform/fonts.zig` embeds: IBM Plex Sans for the
/// interface, JetBrains Mono for code and values, Newtown for its name, from OpenReliant, and
/// Lucide's icons, with the codepoints its icons have.
fn addFonts(b: *std.Build, module: *std.Build.Module, openreliant: *std.Build.Dependency) void {
    const plex = b.dependency("plex_sans", .{});
    const mono = b.dependency("jetbrains_mono", .{});
    const lucide = b.dependency("lucide", .{});
    for ([_]struct { []const u8, std.Build.LazyPath }{
        .{ "IBMPlexSans-Regular.ttf", plex.path("fonts/complete/ttf/IBMPlexSans-Regular.ttf") },
        .{ "IBMPlexSans-Medium.ttf", plex.path("fonts/complete/ttf/IBMPlexSans-Medium.ttf") },
        .{ "IBMPlexSans-SemiBold.ttf", plex.path("fonts/complete/ttf/IBMPlexSans-SemiBold.ttf") },
        .{ "JetBrainsMono-Regular.ttf", mono.path("fonts/ttf/JetBrainsMono-Regular.ttf") },
        .{ "JetBrainsMono-Medium.ttf", mono.path("fonts/ttf/JetBrainsMono-Medium.ttf") },
        .{ "JetBrainsMono-SemiBold.ttf", mono.path("fonts/ttf/JetBrainsMono-SemiBold.ttf") },
        .{ "Newtown.ttf", openreliant.path("deps/newtown/Newtown.ttf") },
        .{ "lucide.ttf", lucide.path("font/lucide.ttf") },
        .{ "lucide-codepoints.json", lucide.path("font/codepoints.json") },
    }) |font| module.addAnonymousImport(font[0], .{ .root_source_file = font[1] });
    for ([_]struct { std.Build.LazyPath, []const u8 }{
        .{ plex.path("LICENSE.txt"), "LICENSE-ibm-plex.txt" },
        .{ mono.path("OFL.txt"), "LICENSE-jetbrains-mono.txt" },
        .{ lucide.path("LICENSE"), "LICENSE-lucide.txt" },
    }) |notice| b.getInstallStep().dependOn(&b.addInstallFile(notice[0], notice[1]).step);
}
