# zkwargs

keyword-only arguments for Zig

## Purpose

This is mostly just having fun playing with Zig's metaprogramming. Compared with the main alternatives though (positional arguments, defining an input type with default arguments, defining a function capable of generating input types, ...), this will tend to be easier to use when some of the following apply:

1. You want to branch the behavior of your program based on which arguments were provided

1. You want to support variadic types in your keyword arguments

1. You're calling the function more than once or twice

1. Many of your function arguments could coerce to each other's types

1. You want to provide default values

## Installation

```zig
// build.zig.zon
.{
    .name = "foo",
    .version = "0.0.0",
    .dependencies = .{
        .zkwargs = .{
            .url = "https://github.com/hmusgrave/zkwargs/archive/4b23becf731ecaac1f29d629943d11b23c7802e8.tar.gz",
            .hash = "1220f6fd467fd42cd5ec98a360caacdcda9d3b9c3557fdcdef285cabbdee3c7c79dc",
        },
    },
}
```

```zig
// build.zig
const zkwargs_pkg = b.dependency("zkwargs", .{
    .target = target,
    .optimize = optimize,
});
const zkwargs_mod = zkwargs_pkg.module("zkwargs");
lib.addModule("zkwargs", zkwargs_mod);
main_tests.addModule("zkwargs", zkwargs_mod);
```

## Examples

There's a nice real-world example in [zshuffle](https://github.com/hmusgrave/zshuffle#examples). The API's behavior is able to easily branch at comptime based on whether an allocator is present or not. Here's a snippet of that example (note how the return type changes based on the optional arguments):

```zig
// You can shuffle it in-place
shuffle(rand, data, .{});

// Or else you can shuffle into a new result buffer
var shuffled = try shuffle(rand, data, .{.allocator = allocator});
defer allocator.free(shuffled);
```

Otherwise, here's an example that's less applicable to the real world as written but which shows off a little more how you might write an API using zkwargs and which features are available.

```zig
const zkwargs = @import("zkwargs");

// A real "range" function probably wouldn't need such
// a complicated/asymmetric options description, but
// I want to demonstrate a few of the available features
const RangeOpt = struct {
    pub fn start(comptime MaybeT: ?type) ?type {
        // Arbitrary type-checking
        zkwargs.allowed_types(MaybeT, "start", .{ usize, comptime_int });

        // Default value of @as(comptime_int, 0)
        return zkwargs.Default(0);
    }

    pub fn stop(comptime _: ?type) type {
        // Default values have whichever type you pass in
        return zkwargs.Default(@as(?comptime_int, null));
    }

    pub fn step(comptime MaybeT: ?type) ?type {
        // Easy to support required arguments
        //
        // Alternatively, you could have just made MaybeT
        // `type` rather than `?type`, but the error
        // message wouldn't be as clear.
        zkwargs.required(MaybeT, "step");

        // anytype: inferred from user-provided value
        //
        // Since we're returning null, signature must
        // be `fn(?type) ?type` rather than `fn (?type) type`
        return null;
    }

    // Especially useless optional argument for a typical
    // "range" implementation, only provided to demonstrate
    // the ability to choose how input arguments will be
    // interpreted.
    pub fn max_count(comptime _: ?type) ?type {
        // User-provided value will be coerced to a usize
        return usize;
    }
};

fn range_sum(data: anytype, _kwargs: anytype) @TypeOf(data[0]) {
    var kwargs = zkwargs.Options(RangeOpt).parse(_kwargs);

    var total: @TypeOf(data[0]) = 0;
    var i: usize = kwargs.start;
    var stop: usize = kwargs.stop orelse data.len;
    if (@hasField(@TypeOf(kwargs), "max_count")) {
        stop = @min(stop, kwargs.start + kwargs.max_count * kwargs.step);
    }
    while (i < stop) : (i += kwargs.step) {
        total += data[i];
    }
    return total;
}

test "doesn't crash" {
    var data = [_]u8{ 0, 1, 2, 3, 4, 5 };
    try expectEqual(@as(u8, 15), range_sum(data, .{ .step = 1 }));
    try expectEqual(@as(u8, 6), range_sum(data, .{ .step = 2 }));
    try expectEqual(@as(u8, 2), range_sum(data, .{ .step = 2, .max_count = 2 }));
    try expectEqual(@as(u8, 3), range_sum(data, .{ .start = 1, .stop = 3, .step = 1 }));
}
```

## Status
Working and builds for Zig 0.11 and 0.12. There isn't much in the way of marketing or other niceties other than this README and reading the source (there also isn't much source, so that ought to be easy).
