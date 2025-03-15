# zig-typeset
A way to declare a tagged union that has no duplicate types and then call methods on it regardless of what the active type is.

Designed to make static dispatch more convenient.

The status quo convention to do static dispatch is with a tagged union:
```zig
const Monster = union(enum) {orc: Orc, troll: Troll};
var orc = Monster{ .orc = {} };
switch(orc) {
    inline else => |*x| x.my_method(42)
}
```

A TypeSet is a wrapper to a tagged union with some convenient methods:
```zig
const Monster: type = TypeSet("Monster", .{Orc, Troll, Skeleton, Demon});
```

A TypeSet can then be instantiated to a specific payload, just like instantiating a union:
```zig
const troll: Monster = Monster.init(Troll{ .hp = 1000 });
```

An instantianted TypeSet has a "call" method, so you can do:
```zig
const Monster = TypeSet("debug_name", .{Orc, Troll});
var orc = Monster.init(Orc{});
orc.call(.my_method, .{ 42 });
```

See `typeset.zig` header comments for usage.
