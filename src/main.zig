const std = @import("std");
const coro = @import("coro");
const t = std.testing;
const Allocator = std.mem.Allocator;

test "Table of Contents" {
    // basic concepts
    _ = Term;
    _ = Goal;

    _ = .{ // algorithms
        unify,
        run_goal,
    };
}

// tbh, can be string, but this is faster
/// variable identifier
pub const var_id = u16;
/// constractor identifier
pub const con_id = u16;

pub const Term = union(enum) {
    /// unbound variable.
    Var: var_id,
    /// 0-arity constructor. numbers can be put here as well
    Cst: con_id,
    /// 2-arity constructor.
    Con: struct { name: con_id, inl: *const Term, inr: *const Term },
};

pub const Goal = union(enum) {
    fail,
    success,
    unify: struct { l: Term, r: Term },
    disj: struct { l: *const Goal, r: *const Goal },
    conj: struct { l: *const Goal, r: *const Goal },
    fresh: Relation, // zig bug: can't use Relation here
    invoke: struct { rel: Relation, term: Term },
};

pub const Relation = *const fn (Allocator, Term) Allocator.Error!*const Goal;

pub const SubstitutionMap = struct {
    map: std.AutoHashMap(var_id, Term),

    /// init empty substitution map
    pub fn init(a: Allocator) @This() {
        return .{ .map = std.meta.FieldType(@This(), .map).init(a) };
    }
    pub fn deinit(this: *@This()) void {
        this.map.deinit();
    }
    pub fn clone(this: @This()) !@This() {
        return .{ .map = try this.map.clone() };
    }
    pub fn lookup(this: @This(), term: Term) Term {
        // std.log.err("lookup: {} {}", .{ this.*, term.* });
        var current = term;
        while (true) {
            switch (current) {
                .Var => |id| {
                    if (this.map.get(id)) |bound| {
                        // std.log.err("lookup(bound)!", .{});
                        current = bound;
                    } else {
                        return current;
                    }
                },
                .Cst => |_| {
                    return current;
                },
                .Con => |_| {
                    return current;
                },
            }
        }
    }
    pub fn bind(this: @This(), id: var_id, value: Term) !@This() {
        var map = try this.map.clone();
        try map.put(id, value);
        return .{ .map = map };
    }
    pub fn format(this: @This(), comptime fmt: []const u8, options: anytype, writer: anytype) !void {
        _ = options;
        _ = fmt;
        try writer.writeAll("Subst{ ");
        var it = this.map.iterator();
        var first = true;
        while (it.next()) |entry| {
            if (first) {
                first = false;
            } else {
                try writer.writeAll(", ");
            }
            try writer.print("{} -> {}", .{
                entry.key_ptr.*,
                entry.value_ptr.*,
            });
        }
        try writer.writeAll(" }");
    }
};

// always allocate new subst (if not null)
pub fn unify(subst: SubstitutionMap, _l: Term, _r: Term) !?SubstitutionMap {
    const l: Term = subst.lookup(_l);
    const r: Term = subst.lookup(_r);
    // std.log.warn("unify: {} {}", .{ l.*, r.* });
    switch (l) {
        .Var => |l_id| {
            switch (r) {
                .Var => |_| {
                    return try subst.bind(l_id, r);
                },
                .Cst => |_| {
                    return try subst.bind(l_id, r);
                },
                .Con => |_| {
                    return try subst.bind(l_id, r);
                },
            }
        },
        .Cst => |l_id| {
            switch (r) {
                .Var => |r_id| {
                    return try subst.bind(r_id, l);
                },
                .Cst => |r_id| {
                    if (l_id == r_id) {
                        return try subst.clone();
                    } else {
                        return null;
                    }
                },
                .Con => |_| {
                    return null;
                },
            }
        },
        .Con => |lo| {
            const l_id = lo.name;
            switch (r) {
                .Var => |r_id| {
                    return try subst.bind(r_id, l);
                },
                .Cst => |_| {
                    return null;
                },
                .Con => |ro| {
                    const r_id = ro.name;
                    if (l_id == r_id) {
                        var subst1 = (try unify(subst, lo.inl.*, ro.inl.*)) orelse return null;
                        defer subst1.deinit();
                        var subst2 = (try unify(subst1, lo.inr.*, ro.inr.*)) orelse return null;
                        return subst2;
                    } else {
                        return null;
                    }
                },
            }
        },
    }
}

test "unify - sanity test" {
    const t0 = Term{ .Var = 10 };
    const t1 = Term{ .Cst = 42 };
    var subst0 = SubstitutionMap.init(t.allocator);
    defer subst0.deinit();
    var subst1 = (try unify(subst0, t0, t1)).?;
    defer subst1.deinit();

    try t.expectEqual(@as(usize, 1), subst1.map.count());

    var it = subst1.map.iterator();
    while (it.next()) |entry| {
        try t.expectEqual(@as(var_id, 10), entry.key_ptr.*);
        try t.expectEqual(t1, entry.value_ptr.*);
    }
}

test "unify - sanity test 2" {
    const t0 = Term{ .Cst = 11 };
    const t1 = Term{ .Cst = 22 };
    const t2 = Term{ .Var = 0 };
    const t3 = Term{ .Con = .{ .name = 44, .inl = &t0, .inr = &t1 } };
    const t4 = Term{ .Con = .{ .name = 44, .inl = &t0, .inr = &t2 } };
    var subst0 = SubstitutionMap.init(t.allocator);
    defer subst0.deinit();
    var subst1 = (try unify(subst0, t3, t4)).?;
    defer subst1.deinit();

    try t.expectEqual(@as(usize, 1), subst1.map.count());

    var it = subst1.map.iterator();
    while (it.next()) |entry| {
        try t.expectEqual(t1, entry.value_ptr.*);
    }
}

/// state for generating var_id
pub const SymGen = struct {
    next_var_id: var_id = std.math.maxInt(var_id),

    pub fn new_var(this: *@This()) Term {
        const x = this.next_var_id;
        this.next_var_id -= 1;
        return Term{ .Var = x };
    }
};

/// records results
pub const Transcript = struct {
    log: std.ArrayList(SubstitutionMap),
    cap: usize = std.math.maxInt(usize),

    pub fn init(a: Allocator) @This() {
        return .{
            .log = std.ArrayList(SubstitutionMap).init(a),
        };
    }
    pub fn deinit(this: @This()) void {
        for (this.log.items) |*subst| {
            subst.deinit();
        }
        this.log.deinit();
    }
    pub fn add(this: *@This(), subst: SubstitutionMap) !void {
        try this.log.append(subst);
        if (this.log.items.len >= this.cap) {
            return error.TranscriptCapacityReached;
        }
    }
};

pub fn run_goal(a: Allocator, goal: *const Goal, symgen: *SymGen, transcript: *Transcript, subst: SubstitutionMap) !void {
    switch (goal.*) {
        .fail => {},
        .success => {
            try transcript.add(try subst.clone());
        },
        .fresh => |rel| {
            const root_var = symgen.new_var();
            var arena = std.heap.ArenaAllocator.init(a);
            defer arena.deinit();
            const inner_goal = try rel(arena.allocator(), root_var);
            try run_goal(a, inner_goal, symgen, transcript, subst);
        },
        .invoke => |o| {
            var arena = std.heap.ArenaAllocator.init(a);
            defer arena.deinit();
            const inner_goal = try o.rel(arena.allocator(), o.term);
            try run_goal(a, inner_goal, symgen, transcript, subst);
        },
        .unify => |o| {
            const maybe_subst = try unify(subst, o.l, o.r);
            if (maybe_subst) |subst_next| {
                try transcript.add(subst_next);
            }
        },
        .conj => |o| {
            var tx = Transcript.init(a);
            defer tx.deinit();
            try run_goal(a, o.l, symgen, &tx, subst);
            for (tx.log.items) |item_subst| {
                try run_goal(a, o.r, symgen, transcript, item_subst);
            }
        },
        .disj => |o| {
            try run_goal(a, o.l, symgen, transcript, subst);
            try run_goal(a, o.r, symgen, transcript, subst);
        },
    }
}

test "run_goal - sanity test" {
    const S = struct {
        var t1: Term = undefined;
        var t2: Term = undefined;
        pub fn rel1(a: Allocator, _t1: Term) !*const Goal {
            t1 = _t1;
            const g = try a.create(Goal);
            g.* = Goal{
                .fresh = &rel2,
            };
            return g;
        }
        pub fn rel2(a: Allocator, _t2: Term) !*const Goal {
            t2 = _t2;
            const g1 = try a.create(Goal);
            g1.* = Goal{
                .unify = .{
                    .l = t1,
                    .r = Term{ .Cst = 1 },
                },
            };
            const g2 = try a.create(Goal);
            g2.* = Goal{
                .unify = .{
                    .l = t2,
                    .r = t1,
                },
            };
            const g3 = try a.create(Goal);
            g3.* = Goal{
                .conj = .{
                    .l = g1,
                    .r = g2,
                },
            };
            return g3;
        }
    };
    var tx = Transcript.init(t.allocator);
    defer tx.deinit();
    var gen = SymGen{};
    try run_goal(
        t.allocator,
        &Goal{
            .fresh = &S.rel1,
        },
        &gen,
        &tx,
        SubstitutionMap.init(t.allocator),
    );
    try t.expectEqual(@as(usize, 1), tx.log.items.len);

    const subst = tx.log.items[0];
    try t.expectEqual(@as(usize, 2), subst.map.count());

    var it = subst.map.iterator();
    while (it.next()) |entry| {
        try t.expectEqual(Term{ .Cst = 1 }, entry.value_ptr.*);
    }
}
