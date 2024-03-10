const std = @import("std");
const objc = @import("zig-objc");
const cocoa = @import("cocoa.zig");

const app_name = "Aqua";

extern "C" fn MTLCreateSystemDefaultDevice() objc.c.id;

fn applicationShouldTerminateAfterLastWindowClosed(target: objc.c.id, sel: objc.c.SEL, sender: objc.c.id) callconv(.C) objc.c.BOOL {
    _ = target;
    _ = sel;
    _ = sender;
    return cocoa.YES;
}

fn applicationWillFinishLaunching(target: objc.c.id, sel: objc.c.SEL, notification: objc.c.id) callconv(.C) void {
    _ = target;
    _ = sel;
    _ = notification;
    cocoa.NSApp().msgSend(void, "setMainMenu:", .{createMenu()});
}

fn applicationDidFinishLaunching(target: objc.c.id, sel: objc.c.SEL, notification: objc.c.id) callconv(.C) void {
    _ = target;
    _ = sel;
    _ = notification;
    initWindow();
}

fn initAppDelegate() !objc.Object {
    // const NSApplicationDelegate = objc.getProtocol("NSApplicationDelegate").?;
    const NSObject = objc.getClass("NSObject").?;
    const AppDelegate = objc.allocateClassPair(NSObject, "AppDelegate").?;
    _ = try AppDelegate.addMethod("applicationShouldTerminateAfterLastWindowClosed:", applicationShouldTerminateAfterLastWindowClosed);
    _ = try AppDelegate.addMethod("applicationWillFinishLaunching:", applicationWillFinishLaunching);
    _ = try AppDelegate.addMethod("applicationDidFinishLaunching:", applicationDidFinishLaunching);
    objc.registerClassPair(AppDelegate);
    return cocoa.alloc(AppDelegate).msgSend(objc.Object, "init", .{});
}

fn initWindow() void {
    const rect = cocoa.NSRect.make(150, 100, 640, 400);
    const stylemask: cocoa.NSWindow.StyleMask = .{
        .closable = true,
        .miniaturizable = true,
        .resizable = true,
        .titled = true,
        .fullsize_content_view = false,
    };
    const window = cocoa.alloc("NSWindow").msgSend(
        objc.Object,
        "initWithContentRect:styleMask:backing:defer:",
        .{ rect, stylemask, cocoa.NSBackingStoreBuffered, cocoa.NO },
    );
    window.setProperty("title", cocoa.NSString(app_name));

    const device = MTLCreateSystemDefaultDevice();

    const mtk_view = cocoa.alloc("MTKView").msgSend(
        objc.Object,
        "initWithFrame:device:",
        .{ rect, device },
    );
    const MTLClearColor = struct { red: f64, green: f64, blue: f64, alpha: f64 };
    mtk_view.msgSend(void, "setClearColor:", .{MTLClearColor{ .red = 0.4, .green = 0.5, .blue = 0.6, .alpha = 1 }});

    const view_delegate = initMTKViewDelegate(objc.Object.fromId(device));
    mtk_view.msgSend(void, "setDelegate:", .{view_delegate});

    window.msgSend(void, "setContentView:", .{mtk_view});

    window.msgSend(void, "makeKeyAndOrderFront:", .{window});
}

fn initMTKViewDelegate(device: objc.Object) objc.Object {
    const MTKViewDelegate = objc.allocateClassPair(objc.getClass("NSObject").?, "MTKViewDelegate").?;
    _ = MTKViewDelegate.addMethod("drawInMTKView:", drawInMTKView) catch unreachable;
    _ = MTKViewDelegate.addMethod("mtkView:drawableSizeWillChange:", drawableSizeWillChange) catch unreachable;
    _ = MTKViewDelegate.addIvar("commandQueue");
    _ = MTKViewDelegate.addIvar("pipeline");
    objc.registerClassPair(MTKViewDelegate);

    const view_delegate = cocoa.alloc(MTKViewDelegate).msgSend(objc.Object, "init", .{});

    device.msgSend(void, "retain", .{});
    const command_queue = device.msgSend(objc.Object, "newCommandQueue", .{});
    view_delegate.setInstanceVariable("commandQueue", command_queue);
    const pipeline = buildShaders(device) catch unreachable;
    view_delegate.setInstanceVariable("pipeline", pipeline);

    return view_delegate;
}

fn createMenu() objc.Object {
    const NSMenu = objc.getClass("NSMenu").?;
    const NSMenuItem = objc.getClass("NSMenuItem").?;
    const menubar = cocoa.alloc(NSMenu).msgSend(objc.Object, "init", .{});
    const menubar_item = cocoa.alloc(NSMenuItem).msgSend(objc.Object, "init", .{});
    menubar.msgSend(void, "addItem:", .{menubar_item});
    const app_menu = cocoa.alloc(NSMenu).msgSend(objc.Object, "init", .{});
    const quit_menu_item = cocoa.alloc(NSMenuItem).msgSend(
        objc.Object,
        "initWithTitle:action:keyEquivalent:",
        .{ cocoa.NSString("Quit " ++ app_name), objc.sel("terminate:"), cocoa.NSString("q") },
    );
    app_menu.msgSend(void, "addItem:", .{quit_menu_item});
    menubar_item.msgSend(void, "setSubmenu:", .{app_menu});
    return menubar;
}

pub fn main() !void {
    const app = cocoa.NSApp();
    const app_delegate = try initAppDelegate();
    app.msgSend(void, "setDelegate:", .{app_delegate});
    app.msgSend(void, "activateIgnoringOtherApps:", .{cocoa.YES});
    app.msgSend(void, "run", .{});
}

fn unwrap(error_obj: objc.c.id) !void {
    if (error_obj == cocoa.nil) return;
    const error_str = objc.Object.fromId(error_obj);
    defer error_str.msgSend(void, "release", .{});
    const string = error_str.getProperty(objc.Object, "localizedDescription")
        .getProperty([*:0]const u8, "UTF8String");
    std.debug.print("{s}\n", .{string});
    return error.CompilationFailed;
}

fn buildShaders(device: objc.Object) !objc.Object {
    var error_obj: objc.c.id = undefined;

    const library = library: {
        const opts = cocoa.alloc("MTLCompileOptions").msgSend(objc.Object, "init", .{});
        defer opts.msgSend(void, "release", .{});
        const src = @embedFile("shader.metal");
        const shader_src = cocoa.NSString(src);
        break :library device.msgSend(
            objc.Object,
            "newLibraryWithSource:options:error:",
            .{ shader_src, opts, &error_obj },
        );
    };
    defer library.msgSend(void, "release", .{});
    try unwrap(error_obj);

    const vtxfn = cocoa.NSString("vertexMain");
    const frgfn = cocoa.NSString("fragmentMain");
    const vertex_fn = library.msgSend(objc.Object, "newFunctionWithName:", .{vtxfn});
    defer vertex_fn.msgSend(void, "release", .{});
    const fragment_fn = library.msgSend(objc.Object, "newFunctionWithName:", .{frgfn});
    defer fragment_fn.msgSend(void, "release", .{});

    const descriptor = cocoa.alloc("MTLRenderPipelineDescriptor").msgSend(objc.Object, "init", .{});
    defer descriptor.msgSend(void, "release", .{});
    descriptor.msgSend(void, "reset", .{});
    descriptor.setProperty("vertexFunction", vertex_fn);
    descriptor.setProperty("fragmentFunction", fragment_fn);

    const attachment = cocoa.alloc("MTLRenderPipelineColorAttachmentDescriptor").msgSend(objc.Object, "init", .{});
    defer attachment.msgSend(void, "release", .{});
    attachment.setProperty("pixelFormat", @as(u64, 80));
    attachment.setProperty("blendingEnabled", cocoa.YES);
    attachment.setProperty("destinationAlphaBlendFactor", @as(u64, 1));

    descriptor.getProperty(objc.Object, "colorAttachments")
        .msgSend(void, "setObject:atIndexedSubscript:", .{
        attachment,
        @as(u64, 0),
    });

    const pipeline = device.msgSend(
        objc.Object,
        "newRenderPipelineStateWithDescriptor:error:",
        .{ descriptor, &error_obj },
    );
    try unwrap(error_obj);

    return pipeline;
}

fn drawInMTKView(target: objc.c.id, _: objc.c.SEL, view_id: objc.c.id) callconv(.C) void {
    const self = objc.Object.fromId(target); // delegate
    const view = objc.Object.fromId(view_id);

    const queue = self.getInstanceVariable("commandQueue");
    const cmd = queue.getProperty(objc.Object, "commandBuffer");
    const rpd = view.getProperty(objc.Object, "currentRenderPassDescriptor");
    const enc = cmd.msgSend(objc.Object, "renderCommandEncoderWithDescriptor:", .{rpd});

    const MTLPrimitiveTypeTriangle = 3;
    const pipeline = self.getInstanceVariable("pipeline");
    enc.setProperty("renderPipelineState", pipeline);

    // float3 is padded to the size of float4
    const positions = [3 * 4]f32{
        -0.8, 0.8,  0.0, 1,
        0.0,  -0.8, 0.0, 1,
        0.8,  0.8,  0.0, 1,
    };
    const colors = [3 * 4]f32{
        1.0, 0.5, 0.2, 1,
        0.8, 1.0, 0.0, 1,
        0.2, 0.5, 1.0, 1,
    };
    enc.msgSend(void, "setVertexBytes:length:atIndex:", .{
        @as([*]const u8, @ptrCast(&positions)),
        @as(u64, @sizeOf(@TypeOf(positions))),
        @as(u64, 0),
    });
    enc.msgSend(void, "setVertexBytes:length:atIndex:", .{
        @as([*]const u8, @ptrCast(&colors)),
        @as(u64, @sizeOf(@TypeOf(colors))),
        @as(u64, 1),
    });
    enc.msgSend(
        void,
        "drawPrimitives:vertexStart:vertexCount:",
        .{ @as(u64, MTLPrimitiveTypeTriangle), @as(u64, 0), @as(u64, 3) },
    );

    enc.msgSend(void, "endEncoding", .{});
    cmd.msgSend(void, "presentDrawable:", .{view.getProperty(objc.Object, "currentDrawable")});
    cmd.msgSend(void, "commit", .{});
}

fn drawableSizeWillChange(
    target: objc.c.id,
    sel: objc.c.SEL,
    view_id: objc.c.id,
    size: cocoa.NSSize,
) callconv(.C) void {
    _ = target;
    _ = sel;
    _ = view_id;
    _ = size;
}
