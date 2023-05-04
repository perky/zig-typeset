//! ## Typeset ##
//! A way to declare a tagged union that has no duplicate types and then call methods
//! on it regardless of what the active type is. Reduces the boilerplate involved
//! in using switch(..) { inline else => ... }.
//!
//! Usage:
//!     const Typeset = @import("typeset.zig").Typeset;
//!     // ... assume structs of Orc, Skeleton, and Human are declared.
//!     const Monster = Typeset("Monster", .{Orc, Skeleton, Human});
//!     var monster_01 = Monster.init(Orc{});
//!     var monster_02 = Monster.init(Skeleton{});
//!
//!     // You can still switch on an init'd Typeset:
//!     switch(monster_01) {
//!         Monster.Tag(Orc) => |orc| orc.attack(),
//!         Monster.Tag(Skeleton) => |skeleton| skeleton.die(),
//!         Monster.Tag(Human) => |human| human.eat(.cherry, 3),
//!     }
//!
//!     // 'inline else' also still works.
//!     switch(monster_01) {
//!          inline else => |impl| impl.eat(.cherry, 3)
//!     }
//!
//!     // But there's a helper method to shorten 'inline else':
//!     Monster.call(&monster_02, "eat", .{.cherry, 3});
//!
//!     // If you know the active tag, there's a helper method to get its value:
//!     var skeleton = Monster.get(Skeleton, monster_02);
//!
//!     // When wanting to pass a Typeset instance as a function parameter, you use Monster.T:
//!     fn eatCherry(monster: *Monster.T, amount: u32) void {
//!         Monster.call(monster, "eat", .{.cherry, amount});
//!     }
//!
//!     // If you know the active tag, there's a helper method to get its value:
//!     var skeleton = Monster.get(Skeleton, monster_02);
//!
//! const TypesetAPI = struct {
//!     pub const T = <union type>;
//!     pub const tag_type = <union enum type>;
//!     pub const debug_name = <user defined debug name>;
//!
//!     pub const init = fn (data: anytype) T;
//!     pub const call = fn (data_ptr: anytype, 
//!                     comptime fn_name: []const u8, 
//!                     args: anytype) <return type of method>;
//!     pub const Tag = fn (comptime SubT: type) tag_type;
//!     pub const get = fn (comptime SubT: type, data: anytype) SubT;
//! };

const std = @import("std");

pub fn Typeset(comptime name: []const u8, comptime types: anytype) type {
    const builtin = std.builtin;
    const math = std.math;
    const meta = std.meta;
    var enum_fields: [types.len]builtin.Type.EnumField = undefined;
    inline for (types, 0..) |T, i| {
        enum_fields[i] = .{ .name = @typeName(T), .value = i };
    }
    const TypesetTag = @Type(.{
        .Enum = .{
            .tag_type = meta.Int(.unsigned, math.log2_int_ceil(u16, types.len)),
            .fields = &enum_fields,
            .decls = &[_]builtin.Type.Declaration{},
            .is_exhaustive = true,
        }
    });
    var union_fields: [types.len]builtin.Type.UnionField = undefined;
    inline for (types, 0..) |T, i| {
        union_fields[i] = .{ .name = @typeName(T), .type = T, .alignment = @alignOf(T) };
    }
    const U = @Type(.{
        .Union = .{
            .layout = .Auto,
            .tag_type = TypesetTag,
            .fields = &union_fields,
            .decls = &[_]builtin.Type.Declaration{}
        }
    });

    return struct {
        pub const T = U;
        pub const tag_type = TypesetTag;
        pub const debug_name = name;

        pub fn init(data: anytype) U {
            return @unionInit(U, @typeName(@TypeOf(data)), data);
        }

        pub fn call(data_ptr: anytype, 
                    comptime fn_name: []const u8, 
                    args: anytype) ReturnTypeForMethod(U, fn_name, name) 
        {
             return switch(data_ptr.*) {
                inline else => |*val_ptr| blk: {
                    const _T = @TypeOf(val_ptr.*);
                    switch(@typeInfo(_T)) {
                        .Pointer => |type_info| {
                            const fn_ptr = &@field(type_info.child, fn_name);
                            break :blk @call(.auto, fn_ptr, .{val_ptr.*} ++ args);
                        },
                        else => {
                            const fn_ptr = &@field(_T, fn_name);
                            break :blk @call(.auto, fn_ptr, .{val_ptr} ++ args);
                        }
                    }
                }
            };
        }

        pub fn Tag(comptime _T: type) TypesetTag {
            return @field(TypesetTag, @typeName(_T));
        }

        pub fn get(comptime _T: type, data: anytype) _T {
            return @field(data, @typeName(_T));
        }
    };
}

fn ReturnTypeForMethod(comptime U: type, 
                       comptime fn_name: []const u8,
                       comptime typeset_name: []const u8) type 
{
    switch(@typeInfo(U)) {
        .Union => |info| {
            var found_type: ?type = null;
            inline for (info.fields) |field_info| {
                const T = field_info.type;
                switch (@typeInfo(T)) {
                    .Struct, .Union, .Enum, .Opaque => {
                        if (@hasDecl(T, fn_name)) {
                            const fn_t = @field(T, fn_name);
                            found_type = @typeInfo(@TypeOf(fn_t)).Fn.return_type.?;
                            break;
                        }
                    },
                    .Pointer => |ptr| {
                        const T2 = ptr.child;
                        if (@hasDecl(T2, fn_name)) {
                            const fn_t = @field(T2, fn_name);
                            found_type = @typeInfo(@TypeOf(fn_t)).Fn.return_type.?;
                            break;
                        }
                    },
                    else => unreachable
                }
            }
            if (found_type) |T| {
                return T;
            } else {
                @compileError("method named " ++ fn_name ++ " not found in any types of Typeset " ++ typeset_name);
            }
        },
        else => unreachable
    }
}

const tests = struct {
    pub const testing = std.testing;
    const Orc = struct { 
        hp: u32 = 10, 
        pub fn heal(self: *@This(), amount: u32) void { 
            self.hp += amount;
        }
        pub fn getHealth(self: *const @This()) u32 { 
            return self.hp;
        }
    };
    const Troll = struct { 
        hp: u32 = 50, 
        pub fn heal(self: *@This(), amount: u32) void { 
            self.hp += amount*2; 
        }
        pub fn getHealth(self: *const @This()) u32 { 
            return self.hp;
        }
    };
    const Monster = Typeset("monster", .{Orc, Troll});
    test "typeset init" {
        var monster = Monster.init(Troll{});
        try testing.expectEqualStrings("monster", Monster.debug_name);
        try testing.expectEqual(Monster.T, @TypeOf(monster));
    }
    test "typeset switch & tag" {
        var monster = Monster.init(Troll{});
        switch (monster) {
            Monster.Tag(Orc) => |orc| try testing.expectEqual(@as(u32, 10), orc.hp),
            Monster.Tag(Troll) => |troll| try testing.expectEqual(@as(u32, 50), troll.hp),
        }
    }
    test "typeset call & get mutable" {
        var monster1 = Monster.init(Troll{});
        var monster2 = Monster.init(Orc{});
        Monster.call(&monster1, "heal", .{5});
        Monster.call(&monster2, "heal", .{5});
        try testing.expectEqual(@as(u32, 60), Monster.get(Troll, monster1).hp);
        try testing.expectEqual(@as(u32, 15), Monster.get(Orc, monster2).hp);
    }
    test "typeset call & get const" {
        var monster1 = Monster.init(Troll{});
        var monster2 = Monster.init(Orc{});
        const hp1 = Monster.call(&monster1, "getHealth", .{});
        const hp2 = Monster.call(&monster2, "getHealth", .{});
        try testing.expectEqual(@as(u32, 50), hp1);
        try testing.expectEqual(@as(u32, 10), hp2);
    }
    test "typeset pointers mix" {
        const MonsterWithPtr = Typeset("Monster2", .{Orc, *Troll});
        var troll = Troll{ .hp = 100 };
        var monster1 = MonsterWithPtr.init(&troll);
        try testing.expectEqual(@as(u32, 100), Monster.get(*Troll, monster1).*.hp);
        Monster.call(&monster1, "heal", .{50});
        try testing.expectEqual(@as(u32, 200), Monster.get(*Troll, monster1).*.hp);
        try testing.expectEqual(@as(u32, 200), troll.hp);
        var monster2 = MonsterWithPtr.init(Orc{ .hp = 1 });
        try testing.expectEqual(@as(u32, 1), Monster.get(Orc, monster2).hp);
        Monster.call(&monster2, "heal", .{50});
        try testing.expectEqual(@as(u32, 51), Monster.get(Orc, monster2).hp);
    }
};
test { std.testing.refAllDecls(tests); }
