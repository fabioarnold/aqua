const std = @import("std");
const objc = @import("zig-objc");
const cocoa = @import("cocoa.zig");

pub fn build(device: objc.Object) !objc.Object {
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

fn unwrap(error_obj: objc.c.id) !void {
    if (error_obj == cocoa.nil) return;
    const error_str = objc.Object.fromId(error_obj);
    defer error_str.msgSend(void, "release", .{});
    const string = error_str.getProperty(objc.Object, "localizedDescription")
        .getProperty([*:0]const u8, "UTF8String");
    std.debug.print("{s}\n", .{string});
    return error.CompilationFailed;
}