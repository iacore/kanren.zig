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

const RunContext = struct {
    next_var: var_name = 0,
};

const Substitutions = struct {};

pub fn run(rel: Relation, ctx: *RunContext, subst: Substitutions, results: *std.ArrayList(Term)) !void {
    const root_var = RunContext.new_var();
    const goal = rel(root_var);
    switch (goal) {
        .fail => {},
        .fresh => |inner_rel| {
            try run(inner_rel, ctx, subst, results);
        },
    }
}
