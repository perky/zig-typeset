const std = @import("std");
const TypeSet = @import("typeset.zig").TypeSet;
var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;

const Orc = struct {
    hp: u32 = 20,
    hammer: u32 = 10,

    pub fn describe(self: *const Orc) void {
        std.debug.print("A disfugured Orc with {d} health and holding a hammer ({d} str)\n", .{self.hp, self.hammer});
    }
};

const Troll = struct {
    hp: u32 = 100,
    club: u32 = 15,

    pub fn describe(self: *const Troll) void {
        std.debug.print("A huge smelly Troll with {d} health and holding a club ({d} str)\n", .{self.hp, self.club});
    }
};

const Human = struct {
    hp: u32 = 10,
    gun: u32 = 50,

    pub fn describe(self: *const Human) void {
        std.debug.print("A small wise Human with {d} health and holding a gun ({d} str)\n", .{self.hp, self.gun});
    }

    pub fn heal(self: *Human, amount: u32) void {
        self.hp += amount;
    }
};

const Skeleton = struct {
    hp: u32 = 5,
    sword: u32 = 8,

    pub fn describe(self: *const Skeleton) void {
        std.debug.print("A boney Skeleton with {d} integrity and holding a sword ({d} str)\n", .{self.hp, self.sword});
    }

    pub fn getSwordStr(self: *const Skeleton) u32 {
        return self.sword;
    }
};

const Character = TypeSet("Character", .{Orc, Troll, Human, Skeleton});

pub fn main() !void {
    const allocator = gpa.allocator();
    var characters: std.ArrayList(Character) = .init(allocator);
    defer characters.deinit();
    
    try characters.append(.init(Orc{}));
    try characters.append(.init(Troll{}));
    try characters.append(.init(Human{ .hp = 12 }));
    try characters.append(.init(Skeleton{}));
    try characters.append(.init(Human{}));
    try characters.append(.init(Skeleton{ .sword = 99 }));

    for (characters.items) |character| {
        character.call(.describe, .{});
    }

    const heal_amount: u32 = 10;
    for (characters.items) |*character| {
        if (character.maybeCall(.heal, .{heal_amount})) |_| {
            std.debug.print("~ Healing human {d} hp\n", .{heal_amount});
            character.call(.describe, .{});
        }

        if (character.maybeCall(.getSwordStr, .{})) |sword_str| {
            std.debug.print("~ Skeleton's sword has {d} str\n", .{sword_str});
        }
    }
}