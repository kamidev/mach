const std = @import("std");
const mach = @import("mach");
const gpu = mach.gpu;

pub const name = .game;
pub const Mod = mach.Mod(@This());

pub const global_events = .{
    .init = .{ .handler = init },
    .tick = .{ .handler = tick },
};

title_timer: mach.Timer,
pipeline: *gpu.RenderPipeline,

fn init(game: *Mod) !void {
    // Create our shader module
    const shader_module = mach.core.device.createShaderModuleWGSL("shader.wgsl", @embedFile("shader.wgsl"));
    defer shader_module.release();

    // Blend state describes how rendered colors get blended
    const blend = gpu.BlendState{};

    // Color target describes e.g. the pixel format of the window we are rendering to.
    const color_target = gpu.ColorTargetState{
        .format = mach.core.descriptor.format,
        .blend = &blend,
    };

    // Fragment state describes which shader and entrypoint to use for rendering fragments.
    const fragment = gpu.FragmentState.init(.{
        .module = shader_module,
        .entry_point = "frag_main",
        .targets = &.{color_target},
    });

    // Create our render pipeline that will ultimately get pixels onto the screen.
    const label = @tagName(name) ++ ".init";
    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .label = label,
        .fragment = &fragment,
        .vertex = gpu.VertexState{
            .module = shader_module,
            .entry_point = "vertex_main",
        },
    };
    const pipeline = mach.core.device.createRenderPipeline(&pipeline_descriptor);

    // Store our render pipeline in our module's state, so we can access it later on.
    game.init(.{
        .title_timer = try mach.Timer.start(),
        .pipeline = pipeline,
    });
    try updateWindowTitle();
}

pub fn deinit(game: *Mod) void {
    game.state().pipeline.release();
}

// TODO(important): remove need for returning an error here
fn tick(
    core: *mach.Core.Mod,
    game: *Mod,
) !void {
    // TODO(important): event polling should occur in mach.Core module and get fired as ECS event.
    var iter = mach.core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .close => core.send(.exit, .{}), // Tell mach.Core to exit the app
            else => {},
        }
    }

    // Grab the back buffer of the swapchain
    const back_buffer_view = mach.core.swap_chain.getCurrentTextureView().?;
    defer back_buffer_view.release();

    // Create a command encoder
    const label = @tagName(name) ++ ".tick";
    const encoder = mach.core.device.createCommandEncoder(&.{ .label = label });
    defer encoder.release();

    // Begin render pass
    const sky_blue_background = gpu.Color{ .r = 0.776, .g = 0.988, .b = 1, .a = 1 };
    const color_attachments = [_]gpu.RenderPassColorAttachment{.{
        .view = back_buffer_view,
        .clear_value = sky_blue_background,
        .load_op = .clear,
        .store_op = .store,
    }};
    const render_pass = encoder.beginRenderPass(&gpu.RenderPassDescriptor.init(.{
        .label = label,
        .color_attachments = &color_attachments,
    }));

    // Draw
    render_pass.setPipeline(game.state().pipeline);
    render_pass.draw(3, 1, 0, 0);

    // Finish render pass
    render_pass.end();

    // Submit our commands to the queue
    var command = encoder.finish(&.{ .label = label });
    defer command.release();
    mach.core.queue.submit(&[_]*gpu.CommandBuffer{command});

    // Present the frame
    mach.core.swap_chain.present();

    // update the window title every second
    if (game.state().title_timer.read() >= 1.0) {
        game.state().title_timer.reset();
        try updateWindowTitle();
    }
}

fn updateWindowTitle() !void {
    try mach.core.printTitle("mach.Core - custom entrypoint [ {d}fps ] [ Input {d}hz ]", .{
        mach.core.frameRate(),
        mach.core.inputRate(),
    });
}
