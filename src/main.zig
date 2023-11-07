const std = @import("std");
const _t = std.testing;

test "Table of Contents" {
    var a: Term = undefined;
    var b: Goal = undefined;
    var c: Relation = undefined;
    _ = c;
    _ = b;
    _ = a;
    _ = run_goal;
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
    unify: struct { l: *const Term, r: *const Term },
    disj: struct { l: *const Goal, r: *const Goal },
    conj: struct { l: *const Goal, r: *const Goal },
    fresh: Relation,
    invoke: struct { rel: Relation, term: *const Term },
};

const Relation = *const fn (*const Term) *const Goal;
// "const a"

/// State for generating symbols
const RunContext = struct {
    next_var: var_id = 0,
};

const Substitutions = struct {
    map: std.AutoHashMap(var_id, *const Term),

    pub fn initEmpty(a: std.mem.Allocator) @This() {
        return .{ .map = std.AutoHashMap(var_id, *const Term).init(a) };
    }
    pub fn deinit(this: *@This()) void {
        this.map.deinit();
    }
    pub fn clone(this: @This()) !@This() {
        return .{ .map = try this.map.clone() };
    }
    pub fn lookup(this: *const @This(), term: *const Term) *const Term {
        var _term = term;
        while (true) {
            switch (_term.*) {
                .Var => |id| {
                    if (this.map.get(id)) |bound| {
                        _term = bound;
                    } else {
                        return _term;
                    }
                },
                .Cst => |_| {
                    return term;
                },
                .Con => |_| {
                    return term;
                },
            }
        }
    }
    pub fn bind(this: *const @This(), id: var_id, value: *const Term) !@This() {
        var map = try this.map.clone();
        try map.put(id, value);
        return .{ .map = map };
    }
};

const ResultsRecorder = struct {};

pub fn run_goal(goal: *const Goal, ctx: *RunContext, subst: Substitutions, transcript: *ResultsRecorder) !void {
    switch (goal) {
        .fail => {},
        .fresh => |rel| {
            const root_var = RunContext.new_var();
            const inner_goal = rel(root_var);
            try run_goal(inner_goal, ctx, subst, transcript);
        },
        .invoke => |o| {
            const inner_goal = o.rel(o.term);
            try run_goal(inner_goal, ctx, subst, transcript);
        },
        .unify => |o| {
            const maybe_subst = unify(subst, o.l, o.r);
            if (maybe_subst) |subst_next| transcript.add_result(subst_next);
        },
        .conj => |o| {
            var tx = ResultsRecorder.init();
            try run_goal(o.l, ctx, subst, &tx);
            for (tx.items()) |item_subst| {
                try run_goal(o.r, ctx, item_subst, transcript);
            }
        },
        .disj => |o| {
            try run_goal(o.l, ctx, subst, transcript);
            try run_goal(o.r, ctx, subst, transcript);
        },
    }
}

// always allocate new subst (if not null)
pub fn unify(subst: Substitutions, _l: *const Term, _r: *const Term) !?Substitutions {
    const l: *const Term = subst.lookup(_l);
    const r: *const Term = subst.lookup(_r);
    switch (l.*) {
        .Var => |l_id| {
            switch (r.*) {
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
            switch (r.*) {
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
            switch (r.*) {
                .Var => |r_id| {
                    return try subst.bind(r_id, l);
                },
                .Cst => |_| {
                    return null;
                },
                .Con => |ro| {
                    const r_id = ro.name;
                    if (l_id == r_id) {
                        var subst1 = (try unify(subst, lo.inl, ro.inl)) orelse return null;
                        defer subst1.deinit();
                        var subst2 = (try unify(subst1, lo.inr, ro.inr)) orelse return null;
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
    var subst0 = Substitutions.initEmpty(_t.allocator);
    defer subst0.deinit();
    var subst1 = (try unify(subst0, &t0, &t1)).?;
    defer subst1.deinit();

    try _t.expectEqual(@as(usize, 1), subst1.map.count());

    var it = subst1.map.iterator();
    while (it.next()) |entry| {
        try _t.expectEqual(@as(var_id, 10), entry.key_ptr.*);
        try _t.expectEqual(&t1, entry.value_ptr.*);
    }
}
