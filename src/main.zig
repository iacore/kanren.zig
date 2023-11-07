const std = @import("std");
const t = std.testing;

test "Table of Contents" {
    // basic concepts
    _ = Term;
    _ = Goal;
    _ = Relation;

    _ = .{ // algorithms
        unify,
        run_goal,
    };
}

// tbh, can be string, but this is faster
/// variable identifier
const var_id = u16;
/// constractor identifier
const con_id = u16;
/// relation identifier
const rel_name = u16;

const Term = union(enum) {
    Var: var_id,
    Cst: con_id,
    Con: struct { name: con_id, inl: *const Term, inr: *const Term },
};

const Goal = union(enum) {
    fail,
    unify: struct { l: Term, r: Term },
    disj: struct { l: *const Goal, r: *const Goal },
    conj: struct { l: *const Goal, r: *const Goal },
    fresh: *const fn (Term) *const Goal, // zig bug: can't use Relation here
    invoke: struct { rel: *const fn (Term) *const Goal, term: Term },
};

const Relation = fn (Term) *const Goal;

const Substitutions = struct {
    map: std.AutoHashMap(var_id, Term),

    pub fn initEmpty(a: std.mem.Allocator) @This() {
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
pub fn unify(subst: Substitutions, _l: Term, _r: Term) !?Substitutions {
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
    var subst0 = Substitutions.initEmpty(t.allocator);
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

/// state for generating var_id
const SymGen = struct {
    next_var: var_id = 0,

    pub fn new_var(this: *@This()) Term {
        const x = this.next_var;
        this.next_var += 1;
        return Term{ .Var = x };
    }
};

/// records results
const Transcript = struct {
    log: std.ArrayList(Substitutions),

    pub fn init(a: std.mem.Allocator) @This() {
        return .{
            .log = std.ArrayList(Substitutions).init(a),
        };
    }
    pub fn deinit(this: @This()) void {
        for (this.log.items) |*subst| {
            subst.deinit();
        }
        this.log.deinit();
    }
    pub fn add(this: *@This(), subst: Substitutions) !void {
        try this.log.append(subst);
    }
    pub fn items(this: @This()) []const Substitutions {
        return this.log.items;
    }
};

pub fn run_goal(goal: *const Goal, symgen: *SymGen, subst: Substitutions, transcript: *Transcript) !void {
    switch (goal.*) {
        .fail => {},
        .fresh => |rel| {
            const root_var = symgen.new_var();
            const inner_goal = rel(root_var);
            try run_goal(inner_goal, symgen, subst, transcript);
        },
        .invoke => |o| {
            const inner_goal = o.rel(o.term);
            try run_goal(inner_goal, symgen, subst, transcript);
        },
        .unify => |o| {
            const maybe_subst = try unify(subst, o.l, o.r);
            if (maybe_subst) |subst_next| {
                try transcript.add(subst_next);
            }
        },
        .conj => |o| {
            var tx = Transcript.init(transcript.log.allocator);
            defer tx.deinit();
            try run_goal(o.l, symgen, subst, &tx);
            for (tx.items()) |item_subst| {
                try run_goal(o.r, symgen, item_subst, transcript);
            }
        },
        .disj => |o| {
            try run_goal(o.l, symgen, subst, transcript);
            try run_goal(o.r, symgen, subst, transcript);
        },
    }
}

test "run goal - sanity test" {
    const S = struct {
        var t1: Term = undefined;
        var t2: Term = undefined;
        pub fn rel1(_t1: Term) *const Goal {
            t1 = _t1;
            return &Goal{
                .fresh = &rel2,
            };
        }
        pub fn rel2(_t2: Term) *const Goal {
            t2 = _t2;
            const g1 = Goal{
                .unify = .{
                    .l = t1,
                    .r = Term{ .Cst = 1 },
                },
            };
            const g2 = Goal{
                .unify = .{
                    .l = t2,
                    .r = t1,
                },
            };
            return &Goal{
                .conj = .{
                    .l = &g1,
                    .r = &g2,
                },
            };
        }
    };
    var tx = Transcript.init(t.allocator);
    defer tx.deinit();
    var gen = SymGen{};
    try run_goal(
        &Goal{
            .fresh = &S.rel1,
        },
        &gen,
        Substitutions.initEmpty(t.allocator),
        &tx,
    );
    try t.expectEqual(@as(usize, 1), tx.log.items.len);

    const s = try std.fmt.allocPrint(t.allocator, "{}", .{tx.log.items[0]});
    defer t.allocator.free(s);
    try t.expectEqualStrings("Subst{ 0 -> main.Term{ .Cst = 1 }, 1 -> main.Term{ .Cst = 1 } }", s);
}
