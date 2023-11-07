const std = @import("std");
const _t = std.testing;

test "Table of Contents" {
    var a: Term = undefined;
    var b: Goal = undefined;
    var c: Relation = undefined;
    _ = c;
    _ = b;
    _ = a;
}

// tbh, can be string, but this is faster
/// variable identifier
const var_name = u16;
/// constractor identifier
const con_name = u16;
/// relation identifier
const rel_name = u16;

const Term = union(enum) {
    Var: var_name,
    Cst: con_name,
    Con: struct { name: con_name, inl: *const Term, inr: *const Term },
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
    next_var: var_name = 0,
};

const Substitutions = struct {};
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

pub fn unify(subst: Substitutions, l: *const Term, r: *const Term) !?Substitutions {
    const l: *const Term = subst.lookup(o.l);
    const r: *const Term = subst.lookup(o.r);
    // todo: reflections not included
    Var, Var => {
        transcript.add(subst.fuse(l, r));
    }
    Var Cst => {
        transcript.add(subst.bind(l, r));
    }
    Var Con => {
        transcript.add(subst.bind(l, r));
    }
    Cst Cst ,
    Con Con => {
        if (check match) transcript.add(subst);
    }
    else => {
        return null;
    }
}
