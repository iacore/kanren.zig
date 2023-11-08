const std = @import("std");
const kanren = @import("main.zig");
const t = std.testing;

test {
    _ = kanren;
}

test "sudoku_4x4" {
    const s11 = 0;
    const s12 = 1;
    const s13 = 2;
    const s14 = 3;
    const s21 = 4;
    const s22 = 5;
    const s23 = 6;
    const s24 = 7;
    const s31 = 8;
    const s32 = 9;
    const s33 = 10;
    const s34 = 11;
    const s41 = 12;
    const s42 = 13;
    const s43 = 14;
    const s44 = 15;

    const GoalBuilder = struct {
        a: std.mem.Allocator,
        g: *const kanren.Goal,

        pub fn init(a: std.mem.Allocator) !@This() {
            const g = try a.create(kanren.Goal);
            g.* = .success;
            return .{ .a = a, .g = g };
        }
        pub fn one_to_four(this: *@This(), vars: [4]kanren.var_id) !void {
            for (1..5) |_i| {
                const i: kanren.con_id = @intCast(_i);
                var g_sub = try this.a.create(kanren.Goal);
                g_sub.* = .success;

                for (vars) |var_id| {
                    const g0 = try this.a.create(kanren.Goal);
                    g0.* = .{ .unify = .{
                        .l = kanren.Term{ .Var = var_id },
                        .r = kanren.Term{ .Cst = i },
                    } };
                    const g1 = try this.a.create(kanren.Goal);
                    g1.* = .{ .disj = .{
                        .l = g0,
                        .r = g_sub,
                    } };
                    g_sub = g1;
                }

                const g1 = try this.a.create(kanren.Goal);
                g1.* = .{ .conj = .{
                    .l = g_sub,
                    .r = this.g,
                } };
                this.g = g1;
            }
        }
        pub fn fix(this: *@This(), var_id: kanren.var_id, value: kanren.con_id) !void {
            const g0 = try this.a.create(kanren.Goal);
            g0.* = .{ .unify = .{
                .l = kanren.Term{ .Var = var_id },
                .r = kanren.Term{ .Cst = value },
            } };
            const g1 = try this.a.create(kanren.Goal);
            g1.* = .{ .conj = .{
                .l = g0,
                .r = this.g,
            } };
            this.g = g1;
        }
    };

    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var goal_builder = try GoalBuilder.init(arena.allocator());

    try goal_builder.one_to_four(.{ s11, s12, s13, s14 });
    try goal_builder.one_to_four(.{ s21, s22, s23, s24 });
    try goal_builder.one_to_four(.{ s31, s32, s33, s34 });
    try goal_builder.one_to_four(.{ s41, s42, s43, s44 });

    try goal_builder.one_to_four(.{ s11, s21, s31, s41 });
    try goal_builder.one_to_four(.{ s12, s22, s32, s42 });
    try goal_builder.one_to_four(.{ s13, s23, s33, s43 });
    try goal_builder.one_to_four(.{ s14, s24, s34, s44 });

    try goal_builder.one_to_four(.{ s11, s12, s21, s22 });
    try goal_builder.one_to_four(.{ s13, s14, s23, s24 });
    try goal_builder.one_to_four(.{ s31, s32, s41, s42 });
    try goal_builder.one_to_four(.{ s33, s34, s43, s44 });

    inline for (.{ s13, s14, s22, s31, s43, s44 }, .{ 2, 3, 2, 2, 1, 2 }) |var_id, number| {
        try goal_builder.fix(var_id, number);
    }

    // var tx = kanren.Transcript.init(t.allocator);
    // defer tx.deinit();
    // var gen = kanren.SymGen{};
    // try kanren.run_goal(
    //     goal_builder.g,
    //     &gen,
    //     kanren.Substitutions.initEmpty(t.allocator),
    //     &tx,
    // );
    // std.log.warn("#solutions={}", .{tx.log.items.len});
}
