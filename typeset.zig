//! ## TypeSet ##
//! A way to declare a tagged union that has no duplicate types and then call methods
//! on it regardless of what the active type is. Designed to make static dispatch convenient.
//! 
//! The status quo convention to do static dispatch is with a tagged union:
//! const Monster = union(enum) {orc: Orc, troll: Troll};
//! var orc = Monster{ .orc = {} };
//! switch(orc) {
//!     inline else => |*x| x.my_method(42)
//! }
//! 
//! A TypeSet is a wrapper to a tagged union with some convenient methods:
//! const Monster: type = TypeSet("Monster", .{Orc, Troll, Skeleton, Demon});
//! 
//! A TypeSet can then be instantiated to a specific payload, just like instantiating a union:
//! const troll: Monster = Monster.init(Troll{ .hp = 1000 });
//! 
//! An instantianted TypeSet has a "call" method, so you can do:
//! const Monster = TypeSet("debug_name", .{Orc, Troll});
//! var orc = Monster.init(Orc{});
//! orc.call(.my_method, .{ 42 });
//!
//! Usage:
//!     const TypeSet = @import("typeset.zig").TypeSet;
//! 
//!     // Assume structs of Orc, Troll, and Human are declared.
//!     const Orc = struct {
//!         hp: u32,
//!         pub fn eat(self: *Orc, food: Food, amount: u32) void { ... }
//!         pub fn getHealth(self: *const Orc) u32 { return hp; }
//!     };
//!     const Troll = struct { ... };
//!     const Human = struct { ... };
//! 
//!     // TypeSet takes in a debug name and a list of types (both comptime known).
//!     // @TypeOf(monster_01.data) == Monster.UnionT
//!     const Monster = TypeSet("Monster", .{Orc, Troll, Human});
//!     var monster_01: Monster = .init(Orc{});
//!     var monster_02: Monster = .init(Troll{});
//!     
//!     // The tagged union is accessed at .data
//!     // you can still switch on an init'd TypeSet:
//!     switch(monster_01.data) {
//!         .Orc => |*orc| orc.attack(),
//!         .Troll => |*troll| troll.die(),
//!         .Human => |*human| human.eat(.cherry, 3),
//!     }
//!
//!     // 'inline else' also still works.
//!     switch(monster_01.data) {
//!          inline else => |*x| x.eat(.cherry, 3)
//!     }
//!
//!     // But there's a helper method to shorten 'inline else':
//!     monster_02.call(.eat, .{ .cherry, 3 });
//! 
//!     // 'call' will return the right data.
//!     const health: u32 = monster_01.call(.getHealth, .{});
//!
//!     // If you know the active tag, you can access the active payload:
//!     const orc: Orc = monster_01.data.Orc;
//! 
//!     // Another way to access the active payload is via .get and .getPtr:
//!     const troll: Troll = monster_02.get(Troll);
//!     const orc_ptr: *Orc = monster_01.getPtr(Orc);
//!     const troll_ptr: *const Troll = monster_02.getPtr(Troll);
//!     
//!     // If you know the active tag, you can access fields in the active payload:
//!     const health: u32 = monster_01.data.Orc.hp;
//! 
//!     // If all types inside the TypeSet (in this case Orc, Troll, Human) have
//!     // fields in common, you can access those fields with .fieldVal and .fieldPtr:
//!     const health: u32 = monster_01.fieldVal(.hp);
//!     const health_ptr: *u32 = monster_02.fieldPtr(.hp);
//!     health_ptr.* = 0;
//!     assert(monster_02.data.Troll.hp == 0);
//! 
//!     // The .maybeFieldVal and .maybeFieldPtr are helper methods to access
//!     // fields if there are not common across all set types:
//!     if (monster_01.maybeFieldPtr(.mana)) |mana_ptr| {
//!         mana_ptr.* -= 1;
//!     }
//!
//!     // You can use the TypeSet type in functions as a kind of static interface:
//!     fn eatApples(monster: *Monster, amount: u32) void {
//!         monster.call(.eat, .{ .apple, amount });
//!     }
//!

const std = @import("std");
const assert = std.debug.assert;
const Symbol = @TypeOf(.enum_literal);

/// Functions that can be called on instances of a TypeSet.
/// Note that you can also call the same functions as methods on the instantiated TypeSet.
/// For example:
/// const Monster = TypeSet("Monster", .{ Orc, Troll, Skeleton });
/// const orc = Monster.init(Orc{});
/// const val1 = TypeSetAPI.call(&orc, .calcValue, .{1});
/// const val2 = orc.call(.calcValue, .{2});
pub const TypeSetAPI = struct {
    /// Call a method on the active payload of the TypeSet.
    /// Returns the same type that the called method returns.
    /// Will trigger a compile error if the method doesn't exist on all types within the TypeSet.
    /// 
    /// typeset_ptr: must be a pointer to a TypeSet instance.
    /// fn_symbol: the name of the method as a literal (i.e. .functionName)
    /// args: tuple of args to pass to the method.
    pub fn call(typeset_ptr: anytype, comptime fn_symbol: Symbol, args: anytype) 
        CallReturnType(@TypeOf(typeset_ptr.*), fn_symbol) 
    {
        switch (@typeInfo(@TypeOf(typeset_ptr))) {
            .pointer => return callInternal(typeset_ptr, fn_symbol, args),
            else => @compileError("TypeSet: typeset argument must be a pointer or const pointer")
        }
    }

    /// Attempt to call a method on the activate payload of the TypeSet.
    /// Will return null if that method doesn't exist otherwise it returns the same type the the method returns.
    /// 
    /// same arguments as call().
    pub fn maybeCall(typeset_ptr: anytype, comptime fn_symbol: Symbol, args: anytype) 
        ?CallReturnType(@TypeOf(typeset_ptr.*), fn_symbol) 
    {
        switch (@typeInfo(@TypeOf(typeset_ptr))) {
            .pointer => return maybeCallInternal(typeset_ptr, fn_symbol, args),
            else => @compileError("TypeSet: typeset argument must be a pointer or const pointer")
        }
    }

    /// Returns the value of the field on the active payload of the TypeSet.
    /// Will trigger a compile error if that field doesn't exist on all types within the TypeSet or 
    /// if that field is not the same type across all TypeSet types.
    /// 
    /// typeset_ptr: must be a pointer to a TypeSet instance.
    /// field_symbol: the name of the field to get as a literal (i.e. .fooBar)
    pub fn fieldVal(typeset_ptr: anytype, comptime field_symbol: Symbol) 
        FieldReturnType(@TypeOf(typeset_ptr.*), field_symbol) 
    {
        switch (typeset_ptr.data) {
            inline else => |payload| {
                return @field(payload, @tagName(field_symbol));
            }
        }
    }

    /// Attempts to return the value of the field on the active payload of the TypeSet.
    /// Returns null if the field is not found, otherwise returns the field by value.
    /// 
    /// arguments are the same as fieldVal().
    pub fn maybeFieldVal(typeset: anytype, comptime field_symbol: Symbol) 
        ?FieldReturnType(@TypeOf(typeset.*), field_symbol) 
    {
        const field_name = @tagName(field_symbol);
        switch (typeset.data) {
            inline else => |payload| {
                if (@hasField(@TypeOf(payload), field_name)) {
                    return @field(payload, field_name);
                }
            }
        }
        return null;
    }

    /// Returns a pointer to the field on the active payload of the TypeSet.
    /// Will trigger a compile error if that field does not exist on all types within the TypeSet
    /// or if the field does not have the same type across all TypeSet types.
    /// 
    /// typeset_ptr: must be a pointer to a TypeSet instance.
    /// field_symbol: the name of the field to get as a literal (i.e. .fooBar)
    pub fn fieldPtr(typeset_ptr: anytype, comptime field_symbol: Symbol) 
        PointerType(@TypeOf(typeset_ptr), FieldReturnType(@TypeOf(typeset_ptr.*), field_symbol)) 
    {
        const field_name = @tagName(field_symbol);
        const debug_name = @field(@TypeOf(typeset_ptr.*), "debug_name");
        switch (typeset_ptr.data) {
            inline else => |*payload| {
                if (!@hasField(@TypeOf(payload.*), field_name)) {
                    @compileError("TypeSet: Field " ++ field_name ++ " does not exist on all " ++ debug_name ++ " types, see " ++ @typeName(@TypeOf(payload.*)));
                }
                return &@field(payload, field_name);
            }
        }
        unreachable;
    }

    /// Attempts to return a pointer to the field on the active payload of the TypeSet.
    /// Returns null if that field does not exist, otherwise returns a pointer to the field.
    /// 
    /// arguments are the same as fieldPtr()
    pub fn maybeFieldPtr(typeset_ptr: anytype, comptime field_symbol: Symbol) 
        ?PointerType(@TypeOf(typeset_ptr), FieldReturnType(@TypeOf(typeset_ptr.*), field_symbol)) 
    {
        const field_name = @tagName(field_symbol);
        switch (typeset_ptr.data) {
            inline else => |*payload| {
                if (@hasField(@TypeOf(payload.*), field_name)) {
                    return &@field(payload, field_name);
                }
            }
        }
        return null;
    }

    /// Returns the active payload of the TypeSet by value.
    /// 
    /// typeset_ptr: must be a pointer to a TypeSet instance.
    /// TagT: the type of the of the payload to return.
    pub fn get(typeset_ptr: anytype, comptime TagT: type) TagT {
        return @field(typeset_ptr.data, shortTypeNameFromFull(TagT));
    }

    /// Returns the active payload of the TypeSet by pointer.
    /// 
    /// arguments are the same as get()
    pub fn getPtr(typeset_ptr: anytype, comptime TagT: type) PointerType(@TypeOf(typeset_ptr), TagT) {
        return &@field(typeset_ptr.data, shortTypeNameFromFull(TagT));
    }
};

pub fn TypeSet(comptime name: []const u8, comptime types: anytype) type {
    const builtin = std.builtin;
    const math = std.math;
    const meta = std.meta;

    var enum_fields: [types.len]builtin.Type.EnumField = undefined;
    inline for (types, 0..) |T, i| {
        enum_fields[i] = .{ .name = shortTypeNameFromFull(T), .value = i };
    }

    const EnumType = @Type(.{ .@"enum" = .{
        .tag_type = meta.Int(.unsigned, math.log2_int_ceil(u16, types.len)),
        .fields = &enum_fields,
        .decls = &[_]builtin.Type.Declaration{},
        .is_exhaustive = true,
    }});

    var union_fields: [types.len]builtin.Type.UnionField = undefined;
    inline for (types, enum_fields, 0..) |T, tag, i| {
        union_fields[i] = .{ .name = tag.name, .type = T, .alignment = @alignOf(T) };
    }

    const UnionType = @Type(.{ .@"union" = .{ 
        .layout = .auto, 
        .tag_type = EnumType, 
        .fields = &union_fields, 
        .decls = &[_]builtin.Type.Declaration{},
    }});

    return struct {
        data: UnionType,

        pub const UnionT = UnionType;
        pub const TagsT = EnumType;
        pub const debug_name = name;
        const Self = @This();

        pub fn init(in_data: anytype) @This() {
            return .{
                .data = @unionInit(UnionType, shortTypeNameFromFull(@TypeOf(in_data)), in_data)
            };
        }

        pub fn call(self: anytype, comptime fn_symbol: Symbol, args: anytype) CallReturnType(Self, fn_symbol) {
            return TypeSetAPI.call(self, fn_symbol, args);
        }

        pub fn maybeCall(self: anytype, comptime fn_symbol: Symbol, args: anytype) ?CallReturnType(Self, fn_symbol) {
            return TypeSetAPI.maybeCall(self, fn_symbol, args);
        }

        pub fn fieldVal(self: *const Self, comptime field_symbol: Symbol) FieldReturnType(Self, field_symbol) {
            return TypeSetAPI.fieldVal(self, field_symbol);
        }

        pub fn maybeFieldVal(self: *const Self, comptime field_symbol: Symbol) ?FieldReturnType(Self, field_symbol) {
            return TypeSetAPI.maybeFieldVal(self, field_symbol);
        }

        pub fn fieldPtr(self: anytype, comptime field_symbol: Symbol) PointerType(@TypeOf(self), FieldReturnType(Self, field_symbol)) {
            return TypeSetAPI.fieldPtr(self, field_symbol);
        }

        pub fn maybeFieldPtr(self: anytype, comptime field_symbol: Symbol) ?PointerType(@TypeOf(self), FieldReturnType(Self, field_symbol)) {
            return TypeSetAPI.maybeFieldPtr(self, field_symbol);
        }

        pub fn getPtr(self: anytype, comptime TagT: type) PointerType(@TypeOf(self), TagT) {
            return TypeSetAPI.getPtr(self, TagT);
        }

        pub fn get(self: *const Self, comptime TagT: type) TagT {
            return TypeSetAPI.get(self, TagT);
        }
    };
}

fn CallReturnType(comptime TS: type, comptime fn_symbol: Symbol) type {
    const debug_name = @field(TS, "debug_name");
    const type_info = @typeInfo(@field(TS, "UnionT"));
    const fn_name = @tagName(fn_symbol);
    inline for (type_info.@"union".fields) |field_info| {
        const T = field_info.type;
        switch (@typeInfo(T)) {
            .@"struct", .@"union", .@"enum", .@"opaque" => {
                if (@hasDecl(T, fn_name)) {
                    const fn_t = @TypeOf(@field(T, fn_name));
                    return @typeInfo(fn_t).@"fn".return_type.?;
                }
            },
            .pointer => |ptr| {
                if (@hasDecl(ptr.child, fn_name)) {
                    const fn_t = @TypeOf(@field(ptr.child, fn_name));
                    return @typeInfo(fn_t).@"fn".return_type.?;
                }
            },
            else => @compileError("TypeSet: Invalid type for TypeSet method call: " ++ @typeName(T)),
        }
    }
    @compileError("TypeSet: Method named " ++ fn_name ++ " not found in TypeSet " ++ debug_name);
}

fn callInternal(typeset: anytype, comptime fn_symbol: Symbol, args: anytype) 
    CallReturnType(@TypeOf(typeset.*), fn_symbol) 
{
    const debug_name = @field(@TypeOf(typeset.*), "debug_name");
    const fn_name = @tagName(fn_symbol);
    const maybe_err_type: ?[:0]const u8 = blk: {
        switch (typeset.data) {
            inline else => |*payload| {
                const PayloadT = @TypeOf(payload.*);
                switch (@typeInfo(PayloadT)) {
                    .pointer => |type_info| {
                        if (!@hasDecl(type_info.child, fn_name)) {
                            break :blk @typeName(type_info.child);
                        }
                        const fn_ptr = &@field(type_info.child, fn_name);
                        return @call(.auto, fn_ptr, .{payload.*} ++ args);
                    },
                    .@"struct", .@"union", .@"enum", .@"opaque" => {
                        if (!@hasDecl(PayloadT, fn_name)) {
                            break :blk @typeName(PayloadT);
                        }
                        const fn_ptr = &@field(PayloadT, fn_name);
                        return @call(.auto, fn_ptr, .{payload} ++ args);
                    },
                    else => unreachable
                }
            }
        }
        break :blk null;
    };

    if (maybe_err_type) |err_type| {
        @compileError("TypeSet: Method named " ++ fn_name ++ " does not exist on all types of TypeSet " ++ debug_name ++ ", see " ++ err_type);
    }
}


fn maybeCallInternal(typeset: anytype, comptime fn_symbol: Symbol, args: anytype) 
    ?CallReturnType(@TypeOf(typeset.*), fn_symbol) 
{
    const fn_name = @tagName(fn_symbol);
    switch (typeset.data) {
        inline else => |*payload| {
            const PayloadT = @TypeOf(payload.*);
            switch (@typeInfo(PayloadT)) {
                .pointer => |type_info| {
                    if (@hasDecl(type_info.child, fn_name)) {
                        const fn_ptr = &@field(type_info.child, fn_name);
                        return @call(.auto, fn_ptr, .{payload.*} ++ args);
                    }
                },
                .@"struct", .@"union", .@"enum", .@"opaque" => {
                    if (@hasDecl(PayloadT, fn_name)) {
                        const fn_ptr = &@field(PayloadT, fn_name);
                        return @call(.auto, fn_ptr, .{payload} ++ args);
                    }
                },
                else => unreachable
            }
        }
    }
    return null;
}

fn FieldReturnType(comptime TS: type, comptime field_symbol: Symbol) type {
    const debug_name = @field(TS, "debug_name");
    const type_info = @typeInfo(@field(TS, "UnionT"));
    const field_name = @tagName(field_symbol);
    var LastFieldT: type = void;
    inline for (type_info.@"union".fields) |payload_info| {
        switch (@typeInfo(payload_info.type)) {
            .@"struct" => |s| {
                const FieldT: type = blk: inline for (s.fields) |field| {
                    if (std.mem.eql(u8, field.name, field_name)) {
                        break :blk field.type;
                    }
                } else void;
                if (LastFieldT != void and FieldT != void and FieldT != LastFieldT) {
                    @compileError("TypeSet: Field " ++ field_name ++ " has different types across the TypeSet " ++ debug_name ++ " types.");
                }
                if (FieldT != void) {
                    LastFieldT = FieldT;
                }
            },
            else => @compileError("TypeSet: Unsupported field access on payload type " ++ payload_info.name)
        }
    }
    return LastFieldT;
}

fn PointerType(comptime T: type, comptime TagT: type) type {
    switch (@typeInfo(T)) {
        .pointer => |ptr| {
            if (ptr.is_const) {
                return *const TagT;
            } else {
                return *TagT;
            }
        },
        else => unreachable
    }
}

fn shortTypeNameFromFull(comptime T: type) [:0]const u8 {
    var iter = std.mem.splitBackwardsScalar(u8, @typeName(T), '.');
    return iter.first()[0.. :0];
}

const tests = struct {
    pub const testing = std.testing;
    const Orc = struct {
        hp: u32 = 10,
        mana: u32 = 100, // Note that mana does not exist on Troll.
        pub fn heal(self: *@This(), amount: u32) void {
            self.hp += amount;
        }
        pub fn getHealth(self: *const @This()) u32 {
            return self.hp;
        }
    };

    const Troll = struct {
        hp: u32 = 50,
        pub fn heal(self: *Troll, amount: u32) void {
            self.hp += amount * 2;
        }
        pub fn getHealth(self: *const Troll) u32 {
            return self.hp;
        }
    };

    const Monster = TypeSet("monster", .{ Orc, Troll });

    test "typeset init" {
        const monster: Monster = .init(Troll{});
        try testing.expectEqualStrings("monster", Monster.debug_name);
        try testing.expectEqual(Monster.UnionT, @TypeOf(monster.data));
    }

    test "typeset switch & tag" {
        const monster: Monster = .init(Troll{});
        switch (monster.data) {
            .Troll => |troll| try testing.expectEqual(@as(u32, 50), troll.hp),
            else => unreachable
        }
    }

    test "typeset inline else" {
        var monster: Monster = .init(Orc{ .hp = 10 });
        switch (monster.data) {
            inline else => |*x| x.hp += 1
        }
        try testing.expectEqual(@as(u32, 11), monster.data.Orc.hp);
    }

    test "typeset call & get mutable" {
        var troll: Monster = .init(Troll{ .hp = 100 });
        var orc: Monster = .init(Orc{ .hp = 20 });
        troll.call(.heal, .{5});
        orc.call(.heal, .{5});
        try testing.expectEqual(@as(u32, 110), troll.data.Troll.hp);
        try testing.expectEqual(@as(u32, 25), orc.data.Orc.hp);
    }

    test "typeset call & get const" {
        const troll: Monster = .init(Troll{ .hp = 200 });
        const orc: Monster = .init(Orc{ .hp = 100 });
        const troll_hp = troll.call(.getHealth, .{});
        const orc_hp = orc.call(.getHealth, .{});
        try testing.expectEqual(@as(u32, 200), troll_hp);
        try testing.expectEqual(@as(u32, 100), orc_hp);
    }

    test "typeset pointers mix" {
        const MonsterWithPtr = TypeSet("Monster2", .{ Orc, *Troll });
        var troll = Troll{ .hp = 100 };
        var monster1 = MonsterWithPtr.init(&troll);
        try testing.expectEqual(@as(u32, 100), monster1.data.Troll.*.hp);
        monster1.call(.heal, .{50});
        try testing.expectEqual(@as(u32, 200), monster1.data.Troll.*.hp);
        try testing.expectEqual(@as(u32, 200), troll.hp);
        var monster2 = MonsterWithPtr.init(Orc{ .hp = 1 });
        try testing.expectEqual(@as(u32, 1), monster2.data.Orc.hp);
        monster2.call(.heal, .{50});
        try testing.expectEqual(@as(u32, 51), monster2.data.Orc.hp);
    }

    test "typeset unwrap" {
        const monster_01 = Monster.init(Orc{ .hp = 123 });
        const orc = monster_01.getPtr(Orc);
        try testing.expectEqual(@as(u32, 123), orc.hp);

        var monster_02 = Monster.init(Troll{ .hp = 123 });
        var troll = monster_02.getPtr(Troll);
        troll.hp += 10;
        try testing.expectEqual(@as(u32, 133), troll.hp);
        try testing.expectEqual(@as(u32, 133), monster_02.data.Troll.hp);
    }

    test "typeset entity array" {
        var entities = [_]Monster{
            .init(Orc{ .hp = 5 }),
            .init(Orc{ .hp = 15 }),
            .init(Troll{ .hp = 10 }),
            .init(Orc{ .hp = 8 }),
        };

        for (&entities) |*entity| {
            entity.call(.heal, .{2});
        }

        try testing.expectEqual(@as(u32, 7), entities[0].data.Orc.hp);
        try testing.expectEqual(@as(u32, 17), entities[1].data.Orc.hp);
        try testing.expectEqual(@as(u32, 14), entities[2].data.Troll.hp);
        try testing.expectEqual(@as(u32, 10), entities[3].data.Orc.hp);
    }

    test "typeset field ptr" {
        var monster_01 = Monster.init(Orc{ .hp = 50 });
        const hp: *u32 = monster_01.fieldPtr(.hp);
        hp.* = 25;
        try testing.expectEqual(@as(u32, 25), monster_01.data.Orc.hp);

        const monster_ptr: *const Monster = &monster_01;
        const hp_const: *const u32 = monster_ptr.fieldPtr(.hp);
        try testing.expectEqual(@as(u32, 25), hp_const.*);

        const hp_val: u32 = monster_ptr.fieldVal(.hp);
        try testing.expectEqual(@as(u32, 25), hp_val);

        const monster_02 = Monster.init(Orc{ .hp = 10, .mana = 25 });
        const maybe_mana: ?*const u32 = monster_02.maybeFieldPtr(.mana);
        try testing.expect(maybe_mana != null);
        if (maybe_mana) |mana| {
            try testing.expectEqual(@as(u32, 25), mana.*);
        }
    }

    test "typeset API" {
        var monster_01 = Monster.init(Orc{ .hp = 50 });
        TypeSetAPI.call(&monster_01, .heal, .{10});
        const hp = TypeSetAPI.fieldVal(&monster_01, .hp);
        try testing.expectEqual(@as(u32, 60), hp);

        const hp_ptr = TypeSetAPI.fieldPtr(&monster_01, .hp);
        try testing.expectEqual(@as(u32, 60), hp_ptr.*);
    }
};

test {
    std.testing.refAllDecls(tests);
}
