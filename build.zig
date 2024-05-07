const std = @import("std");

const targets: []const std.Target.Query = &.{
    .{ .cpu_arch = .x86_64 },
};

pub fn build(b: *std.Build) !void {
    const optimeze = b.standardOptimizeOption(.{});
    for (targets) |t| {
        const name = "co-" ++ switch (t.cpu_arch.?) {
            .x86_64 => "x86-64",
            else => @panic("unsupport arch"),
        };
        const libco = b.addSharedLibrary(.{
            .name = name,
            .root_source_file = .{ .path = "src/libco.zig" },
            .target = b.resolveTargetQuery(t),
            .optimize = optimeze,
        });

        b.installArtifact(libco);
    }
}
