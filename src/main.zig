const std = @import("std");
const expectEqual = std.testing.expectEqual;

pub fn Default(comptime def: anytype) type {
    return struct {
        pub const default: @TypeOf(def) = def;
    };
}

pub fn Options(comptime O: type) type {
    return struct {
        pub fn Parsed(comptime ArgT: type) type {
            const decls = @typeInfo(O).Struct.decls;
            const StructField = std.builtin.Type.StructField;
            comptime var kept: usize = 0;
            comptime var fields: [decls.len]StructField = undefined;
            outer: inline for (decls) |d| {
                if (@hasField(ArgT, d.name)) {
                    const ActualT = @TypeOf(@field(@as(ArgT, undefined), d.name));
                    const DesiredT: ?type = @field(O, d.name)(ActualT);
                    comptime var T: type = ActualT;
                    if (DesiredT) |DT| {
                        if (is_default(DT)) {
                            T = @TypeOf(DT.default);
                        } else {
                            T = DT;
                        }
                    }
                    inline for (@typeInfo(ArgT).Struct.fields) |_field| {
                        if (std.mem.eql(u8, d.name, _field.name)) {
                            comptime var field = _field;
                            field.field_type = T;
                            field.alignment = @alignOf(T);
                            if (field.default_value) |dv| {
                                const prev = @ptrCast(*const _field.field_type, dv);
                                field.default_value = default_pointer(T, prev.*);
                            }
                            fields[kept] = field;
                            kept += 1;
                            continue :outer;
                        }
                    }
                } else {
                    const DesiredT: ?type = @field(O, d.name)(null);
                    if (DesiredT) |DT| {
                        if (is_default(DT)) {
                            fields[kept] = StructField{
                                .name = d.name,
                                .field_type = @TypeOf(DT.default),
                                .default_value = &DT.default,
                                .is_comptime = true,
                                .alignment = @alignOf(@TypeOf(DT.default)),
                            };
                            kept += 1;
                            continue :outer;
                        } else {
                            continue :outer;
                        }
                    } else {
                        continue :outer;
                    }
                }
            }

            inline for (@typeInfo(ArgT).Struct.fields) |field| {
                if (!@hasDecl(O, field.name)) {
                    @compileError("Unknown kwargs field `" ++ field.name ++ "`");
                }
            }

            return @Type(.{ .Struct = .{
                .layout = .Auto,
                .fields = fields[0..kept],
                .decls = decls[0..0],
                .is_tuple = false,
            } });
        }

        pub fn parse(args: anytype) Parsed(@TypeOf(args)) {
            var rtn: Parsed(@TypeOf(args)) = undefined;
            inline for (@typeInfo(@TypeOf(args)).Struct.fields) |field| {
                @field(rtn, field.name) = @field(args, field.name);
            }
            return rtn;
        }
    };
}

fn is_default(comptime T: type) bool {
    if (@typeInfo(T) != .Struct)
        return false;
    if (!@hasDecl(T, "default"))
        return false;
    return Default(T.default) == T;
}

fn default_pointer(comptime T: type, comptime val: T) *const anyopaque {
    const Wrapper = struct {
        pub const default: T = val;
    };
    return &Wrapper.default;
}

pub fn required(comptime MaybeT: ?type, comptime field_name: anytype) void {
    if (MaybeT) |_| {} else {
        @compileError("Kwarg `" ++ field_name ++ "` is required");
    }
}

pub fn allowed_types(comptime MaybeT: ?type, comptime field_name: anytype, comptime types: anytype) void {
    if (MaybeT) |T| {
        inline for (types) |AllowedT| {
            if (T == AllowedT)
                return;
        }
        @compileError("Type `" ++ @typeName(T) ++ "` not allowed in field `" ++ field_name ++ "`");
    }
}

// A real "range" function probably wouldn't need such
// a complicated/asymmetric options description, but
// I want to demonstrate a few of the features
const RangeOpt = struct {
    fn start(comptime MaybeT: ?type) ?type {
        // Arbitrary type-checking
        allowed_types(MaybeT, "start", .{ usize, comptime_int });

        // Default value of @as(comptime_int, 0)
        return Default(0);
    }

    fn stop(comptime _: ?type) type {
        // Default values have whichever type you pass in
        return Default(@as(?comptime_int, null));
    }

    fn step(comptime MaybeT: ?type) ?type {
        // Easy to support required arguments
        //
        // Alternatively, you could have just made MaybeT
        // `type` rather than `?type`, but the error
        // message wouldn't be as clear.
        required(MaybeT, "step");

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
    fn max_count(comptime _: ?type) ?type {
        // User-provided value will be coerced to a usize
        return usize;
    }
};

fn range_sum(data: anytype, _kwargs: anytype) @TypeOf(data[0]) {
    var kwargs = Options(RangeOpt).parse(_kwargs);

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
