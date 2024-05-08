const std = @import("std");

const targets: []const std.Target.Query = &.{
    .{ .cpu_arch = .x86_64 },
    .{ .cpu_arch = .riscv64 },
};

pub fn build(b: *std.Build) !void {
    const optimeze = b.standardOptimizeOption(.{});
    for (targets) |t| {
        const name = try std.fmt.allocPrint(b.allocator, "co-{s}", .{switch (t.cpu_arch.?) {
            .x86_64 => "x86-64",
            .riscv64 => "rv64",
            else => @panic("unsupport arch"),
        }});
        const libco = b.addSharedLibrary(.{
            .name = name,
            .root_source_file = .{ .path = "src/libco.zig" },
            .target = b.resolveTargetQuery(t),
            .optimize = optimeze,
        });

        // workaround for https://github.com/ziglang/zig/issues/7935
        if (t.cpu_arch == .x86)
            libco.link_z_notext = true;

        b.installArtifact(libco);
    }
}
