const objc = @import("zig-objc");
const cocoa = @import("cocoa.zig");
const shaders = @import("shaders.zig");

pub fn initMetalLayerView(device: objc.Object, frame: cocoa.NSRect) objc.Object {
    const MetalLayerView = objc.allocateClassPair(objc.getClass("NSView").?, "MetalLayerView").?;
    _ = MetalLayerView.addMethod("makeBackingLayer", makeBackingLayer) catch unreachable;
    _ = MetalLayerView.addMethod("setFrameSize:", setFrameSize) catch unreachable;
    _ = MetalLayerView.addMethod("displayLayer:", displayLayer) catch unreachable;
    _ = MetalLayerView.addIvar("metalLayer");
    _ = MetalLayerView.addIvar("device");
    _ = MetalLayerView.addIvar("commandQueue");
    _ = MetalLayerView.addIvar("pipeline");
    objc.registerClassPair(MetalLayerView);

    const metal_layer_view = cocoa.alloc("MetalLayerView").msgSend(objc.Object, "init", .{});
    metal_layer_view.msgSendSuper(objc.getClass("NSView").?, void, "initWithFrame:", .{frame});

    device.msgSend(void, "retain", .{});
    metal_layer_view.setInstanceVariable("device", device);
    const command_queue = device.msgSend(objc.Object, "newCommandQueue", .{});
    metal_layer_view.setInstanceVariable("commandQueue", command_queue);
    const pipeline = shaders.build(device) catch unreachable;
    metal_layer_view.setInstanceVariable("pipeline", pipeline);

    metal_layer_view.setProperty("wantsLayer", true);
    metal_layer_view.setProperty("layerContentsRedrawPolicy", @as(u64, 2)); // .duringViewResize
    metal_layer_view.setProperty("layerContentsPlacement", @as(u64, 0)); // .scaleAxesIndependently

    return metal_layer_view;
}

fn makeBackingLayer(target: objc.c.id, _: objc.c.SEL) callconv(.C) objc.c.id {
    const self = objc.Object.fromId(target);

    const metal_layer = cocoa.alloc("CAMetalLayer").msgSend(objc.Object, "init", .{});
    self.setInstanceVariable("metalLayer", metal_layer);
    const mtl_pixel_format_bgra8unorm = 80;
    metal_layer.setProperty("pixelFormat", @as(u64, mtl_pixel_format_bgra8unorm));
    metal_layer.setProperty("device", self.getInstanceVariable("device"));
    metal_layer.setProperty("delegate", self);

    metal_layer.setProperty("allowsNextDrawableTimeout", false);

    // metalLayer.autoresizingMask = CAAutoresizingMask(arrayLiteral: [.layerHeightSizable, .layerWidthSizable])
    metal_layer.setProperty("needsDisplayOnBoundsChange", true);
    metal_layer.setProperty("presentsWithTransaction", true);

    return metal_layer.value;
}

var width: f32 = 1024.0;
var height: f32 = 1024.0;

fn setFrameSize(target: objc.c.id, _: objc.c.SEL, new_size: cocoa.NSSize) callconv(.C) void {
    const self = objc.Object.fromId(target);
    self.msgSendSuper(objc.getClass("NSView").?, void, "setFrameSize:", .{new_size});
    const converted = self.msgSend(cocoa.NSSize, "convertSizeToBacking:", .{new_size});
    width = @floatCast(converted.width);
    height = @floatCast(converted.height);
    const metal_layer = self.getInstanceVariable("metalLayer");
    metal_layer.setProperty("drawableSize", converted);
    // metalLayer.drawableSize = convertToBacking(newSize)
}

fn displayLayer(target: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.C) void {
    const self = objc.Object.fromId(target);
    const metal_layer = self.getInstanceVariable("metalLayer");
    const drawable = metal_layer.msgSend(objc.Object, "nextDrawable", .{});

    const rpd = objc.getClass("MTLRenderPassDescriptor").?.msgSend(objc.Object, "renderPassDescriptor", .{});
    const color_attachment0 = rpd.getProperty(objc.Object, "colorAttachments").msgSend(objc.Object, "objectAtIndexedSubscript:", .{@as(u64, 0)});
    const MTLClearColor = struct { red: f64, green: f64, blue: f64, alpha: f64 };
    const texture = drawable.getProperty(objc.Object, "texture");
    color_attachment0.setProperty("texture", texture);
    color_attachment0.setProperty("loadAction", @as(u64, 2)); // clear
    color_attachment0.setProperty("storeAction", @as(u64, 1)); // store
    color_attachment0.setProperty("clearColor", MTLClearColor{ .red = 0.4, .green = 0.5, .blue = 0.6, .alpha = 1 });

    const queue = self.getInstanceVariable("commandQueue");
    const cmd = queue.getProperty(objc.Object, "commandBuffer");
    const enc = cmd.msgSend(objc.Object, "renderCommandEncoderWithDescriptor:", .{rpd});
    const pipeline = self.getInstanceVariable("pipeline");
    enc.setProperty("renderPipelineState", pipeline);

    // float3 is padded to the size of float4
    var positions = [3 * 4]f32{
        -0.866, 0.5, 0.0, 1,
        0.0,    -1,  0.0, 1,
        0.866,  0.5, 0.0, 1,
    };
    // scale
    for (0..3) |i| {
        const x = positions[4 * i + 0];
        const y = positions[4 * i + 1];
        positions[4 * i + 0] = (x + 1) * 1024.0 / width - 1;
        positions[4 * i + 1] = 1 - (1 - y) * 1024.0 / height;
    }
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
        .{ @as(u64, 3), @as(u64, 0), @as(u64, 3) }, // .triangle
    );

    enc.msgSend(void, "endEncoding", .{});

    cmd.msgSend(void, "commit", .{});
    cmd.msgSend(void, "waitUntilScheduled", .{});
    drawable.msgSend(void, "present", .{});
}
