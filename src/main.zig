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
    const rect = cocoa.NSRect.make(150, 100, 400, 300);
    const stylemask: cocoa.NSWindow.StyleMask = .{
        .closable = true,
        .miniaturizable = true,
        .resizable = true,
        .titled = true,
        .fullsize_content_view = true,
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
        .{ cocoa.NSRect.make(0, 0, 400, 300), device },
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
    objc.registerClassPair(MTKViewDelegate);

    const view_delegate = cocoa.alloc(MTKViewDelegate).msgSend(objc.Object, "init", .{});

    const command_queue = device.msgSend(objc.Object, "newCommandQueue", .{});
    view_delegate.setInstanceVariable("commandQueue", command_queue);

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

fn drawInMTKView(target: objc.c.id, _: objc.c.SEL, view_id: objc.c.id) callconv(.C) void {
    const self = objc.Object.fromId(target); // delegate
    const view = objc.Object.fromId(view_id);
    const queue = self.getInstanceVariable("commandQueue");
    const cmd = queue.getProperty(objc.Object, "commandBuffer");
    const rpd = view.getProperty(objc.Object, "currentRenderPassDescriptor");
    const enc = cmd.msgSend(objc.Object, "renderCommandEncoderWithDescriptor:", .{rpd});
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
