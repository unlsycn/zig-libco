const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;
const CoArg = ?*anyopaque;
const CoFunc = ?*const fn (CoArg) callconv(.C) void;

// use ?*anyopaque instead of [*c]Co here
// since the C code doesn't need to know the exact type of Co
const CoPtr = ?*anyopaque;

const ArchInfo = struct {
    ContextType: type,
    assembly: []const u8,
    stack_size: usize,
};

const arch_info = switch (builtin.cpu.arch) {
    .x86_64 => .{
        .ContextType = packed struct {
            return_address: u64,
            rsp: u64,
            rbp: u64,
            rbx: u64,
            r12: u64,
            r13: u64,
            r14: u64,
            r15: u64,
        },
        .assembly = @embedFile("asm/x86_64.s"),
        .stack_size = 64 * 1024, // 64 KiB
    },
    else => @compileError("Unsupport arch"),
};

comptime {
    asm (arch_info.assembly);
}

const CoStatus = enum { New, Running, Waiting, Dead };

const Co = struct {
    name: []const u8,
    func: CoFunc,
    arg: CoArg,

    allocator: Allocator,
    status: CoStatus,
    waiter: ?*Co,
    context: arch_info.ContextType,
    stack: [arch_info.stack_size]u8,

    pub fn init(allocator: Allocator, name: []const u8, func: CoFunc, arg: CoArg) !*Co {
        const co = try allocator.create(Co);

        co.name = name;
        co.func = func;
        co.arg = arg;
        co.allocator = allocator;
        co.status = .New;
        co.waiter = null;

        @memset(&co.stack, 0xdb);

        return co;
    }

    pub fn deinit(self: *Co) void {
        self.allocator.destroy(self);
    }

    fn funcWrapper(self: *Co) callconv(.C) noreturn {
        self.func.?(self.arg.?);

        // at this moment we cannot guarantee that the coroutine has been waited,
        // thus we set the status to Dead and destroy it until the only co_wait
        // before destroying it
        self.status = .Dead;
        co_yield();

        unreachable;
    }

    pub inline fn switchToNewCo(self: *Co) noreturn {
        asm volatile (
            \\movq %[sp], %%rsp
            \\movq %[arg], %%rdi
            \\jmp *%[entry]
            :
            : [sp] "r" (&self.stack[self.stack.len - 1]),
              [entry] "r" (&funcWrapper),
              [arg] "r" (self),
            : "memory"
        );
        unreachable;
    }
};

var current: *Co = undefined;

const CoQueue = std.fifo.LinearFifo(*Co, .Dynamic);
var co_queue: CoQueue = undefined;

const Gpa = std.heap.GeneralPurposeAllocator(.{});
var gpa: Gpa = undefined;

inline fn queueWriteError() noreturn {
    @panic("[error] No space for queue");
}

pub export fn co_start(name: [*c]const u8, func: CoFunc, arg: CoArg) CoPtr {
    const co = Co.init(gpa.allocator(), std.mem.span(name), func, arg) catch @panic("[error] No enough Memory!");

    co_queue.writeItem(co) catch queueWriteError();

    return co;
}

extern fn save_context(context: *arch_info.ContextType) callconv(.C) void;
extern fn restore_context(context: *arch_info.ContextType) noreturn;

pub export fn co_yield() void {
    save_context(&current.context);
    yield();
}

fn yield() void {
    current.context.return_address = @returnAddress();

    while (co_queue.readItem()) |next_co| {
        if (next_co.status != .Dead)
            co_queue.writeItem(next_co) catch queueWriteError();

        switch (next_co.status) {
            .New => {
                current = next_co;

                next_co.status = .Running;
                next_co.switchToNewCo();
            },
            .Running => {
                current = next_co;
                restore_context(&next_co.context);
            },
            .Waiting => continue,
            .Dead => if (next_co.waiter) |waiter| {
                waiter.status = .Running;
                continue;
            },
        }
    }
}

pub export fn co_wait(co_ptr: CoPtr) void {
    const co: *Co = @ptrCast(@alignCast(co_ptr));

    co.waiter = current;
    current.status = .Waiting;

    while (co.status != .Dead) {
        co_yield();

        // We assume that each coroutine will be waited exactly once,
        // hence we should free it in co_wait to avoid use-after-free
        if (co.status == .Dead) {
            co.deinit();
            return;
        }
    }
}

pub export fn co_init() void {
    gpa = std.heap.GeneralPurposeAllocator(.{}){};

    co_queue = CoQueue.init(gpa.allocator());

    current = @ptrCast(@alignCast(co_start("main", null, null)));
    current.status = .Running;
}

pub export fn co_deinit() void {
    defer if (gpa.deinit() == std.heap.Check.leak) {
        std.debug.print("> [error] memory leaked\n", .{});
    };
    defer {
        while (co_queue.readItem()) |item| {
            item.deinit();
        }
        co_queue.deinit();
    }
}

test "init and deinit" {
    co_init();
    defer co_deinit();
}