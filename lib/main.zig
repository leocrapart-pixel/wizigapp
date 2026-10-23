//! WizigApp — random little calculators shared by every host.
//!
//! Every `pub fn` below is discovered by `wizig codegen` and exposed to the
//! Android host as a typed Kotlin method on `dev.wizig.WizigGeneratedApi`.
//! Inputs are whitespace-separated numbers, outputs are display strings.
const std = @import("std");
const builtin = @import("builtin");

const PASSWORD_LOWER = "abcdefghijkmnpqrstuvwxyz";
const PASSWORD_UPPER = "ABCDEFGHJKLMNPQRSTUVWXYZ";
const PASSWORD_DIGITS = "23456789";
const PASSWORD_SYMBOLS = "!@#$%^&*()-_=+[]{}";

/// Upper bound for any single output produced below.
const max_output_len = 1024;

pub fn randomInt(input: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const values = try expectNumbers(2, input);
    const min = try whole(values[0]);
    const max = try whole(values[1]);
    if (min > max) return error.InvalidInput;
    const span = @as(u128, @intCast(max)) - @as(u128, @intCast(min)) + 1;
    if (span > 1 << 32) return error.InvalidInput;
    const picked = min + @as(i64, @intCast(try randomBelow(@intCast(span))));
    return std.fmt.allocPrint(allocator, "{d}", .{picked});
}

pub fn rollDice(input: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const spec = try diceSpec(input);
    var rolls_buf: [100]u64 = undefined;
    const rolls = rolls_buf[0..@as(usize, @intCast(spec.count))];
    for (rolls) |*roll| roll.* = 1 + try randomBelow(spec.sides);

    var buf: [max_output_len]u8 = undefined;
    var scratch: [64]u8 = undefined;
    var len: usize = 0;
    for (rolls, 0..) |roll, index| {
        if (index > 0) len += try appendText(buf[len..], " + ");
        const face = std.fmt.bufPrint(&scratch, "{d}", .{roll}) catch return error.NoSpaceLeft;
        len += try appendText(buf[len..], face);
    }
    if (rolls.len > 1) {
        var total: u64 = 0;
        for (rolls) |roll| total += roll;
        const sum = std.fmt.bufPrint(&scratch, " = {d}", .{total}) catch return error.NoSpaceLeft;
        len += try appendText(buf[len..], sum);
    }
    return allocator.dupe(u8, buf[0..len]);
}

pub fn coinFlip(allocator: std.mem.Allocator) ![]u8 {
    return allocator.dupe(u8, if (try randomBelow(2) == 1) "Heads" else "Tails");
}

pub fn password(input: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const values = try expectNumbers(1, input);
    const length_i = try whole(values[0]);
    if (length_i < 4 or length_i > 128) return error.InvalidInput;
    const length: usize = @intCast(length_i);

    const sets = [_][]const u8{ PASSWORD_LOWER, PASSWORD_UPPER, PASSWORD_DIGITS, PASSWORD_SYMBOLS };
    const all = PASSWORD_LOWER ++ PASSWORD_UPPER ++ PASSWORD_DIGITS ++ PASSWORD_SYMBOLS;

    var buf: [128]u8 = undefined;
    // One character from every set first, so no class is missing by chance.
    for (sets, 0..) |set, index| buf[index] = set[try pickIndex(set.len)];
    for (buf[sets.len..length]) |*slot| {
        slot.* = all[try pickIndex(all.len)];
    }
    var i: usize = length - 1;
    while (i > 0) : (i -= 1) {
        const j: usize = @intCast(try randomBelow(i + 1));
        const tmp = buf[i];
        buf[i] = buf[j];
        buf[j] = tmp;
    }
    return allocator.dupe(u8, buf[0..length]);
}

pub fn bmi(input: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const values = try expectNumbers(2, input);
    const kg = values[0];
    const cm = values[1];
    if (!(kg > 0 and cm > 0)) return error.InvalidInput;
    const value = round2(kg / ((cm / 100.0) * (cm / 100.0)));
    const label = if (value < 18.5)
        "Underweight"
    else if (value < 25)
        "Healthy range"
    else if (value < 30)
        "Overweight"
    else
        "Obesity";
    return std.fmt.allocPrint(allocator, "{d:.1} - {s}", .{ value, label });
}

pub fn tipSplit(input: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const values = try expectNumbers(3, input);
    const bill = values[0];
    const pct = values[1];
    const people = try whole(values[2]);
    if (!(bill >= 0) or !(pct >= 0) or people < 1) return error.InvalidInput;
    const tip = round2(bill * pct / 100.0);
    const total = round2(bill + tip);
    return std.fmt.allocPrint(allocator, "${d:.2} tip | ${d:.2} total | ${d:.2} each", .{
        tip,
        total,
        round2(total / @as(f64, @floatFromInt(people))),
    });
}

pub fn compound(input: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const values = try expectNumbers(3, input);
    const principal = values[0];
    const rate = values[1];
    const years = values[2];
    if (!(principal >= 0) or !(years >= 0)) return error.InvalidInput;
    const total = round2(principal * std.math.pow(f64, 1 + rate / 100.0, years));
    return std.fmt.allocPrint(allocator, "${d:.2} total | ${d:.2} gained", .{ total, round2(total - principal) });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Splits `input` into exactly `N` whitespace-or-comma separated numbers.
fn expectNumbers(comptime N: usize, input: []const u8) ![N]f64 {
    var out: [N]f64 = undefined;
    var index: usize = 0;
    var tokens = std.mem.tokenizeAny(u8, input, " ,;\t");
    while (tokens.next()) |token| {
        if (index == N) return error.InvalidInput;
        out[index] = std.fmt.parseFloat(f64, token) catch return error.InvalidInput;
        index += 1;
    }
    if (index != N) return error.InvalidInput;
    return out;
}

/// Accepts only integral values that fit an i64 (no silent truncation).
fn whole(value: f64) !i64 {
    if (value != @floor(value)) return error.InvalidInput;
    if (value < -9.0e18 or value > 9.0e18) return error.InvalidInput;
    return @intFromFloat(value);
}

const DiceSpec = struct { count: u64, sides: u64 };

/// Parses "2d6", "3d20", "4" (sides default to 6) into a bounded dice spec.
fn diceSpec(input: []const u8) !DiceSpec {
    var tokens = std.mem.tokenizeAny(u8, input, "dDxX* ,");
    const count_text = tokens.next() orelse return error.InvalidInput;
    const sides_text = tokens.next();
    if (tokens.next() != null) return error.InvalidInput;

    const count_i = try whole(std.fmt.parseFloat(f64, count_text) catch return error.InvalidInput);
    if (count_i < 1 or count_i > 100) return error.InvalidInput;
    if (sides_text == null) return .{ .count = @intCast(count_i), .sides = 6 };

    const sides_i = try whole(std.fmt.parseFloat(f64, sides_text.?) catch return error.InvalidInput);
    if (sides_i < 2 or sides_i > 1000) return error.InvalidInput;
    return .{ .count = @intCast(count_i), .sides = @intCast(sides_i) };
}

/// Zero-based index below `len`, via the same rejection sampler.
fn pickIndex(len: usize) !usize {
    return @intCast(try randomBelow(len));
}

/// Uniform in `[0, bound)`, rejection-sampled so no value is favoured.
fn randomBelow(bound: u64) !u64 {
    if (bound < 2) return 0;
    const limit = std.math.maxInt(u64) - (std.math.maxInt(u64) % bound);
    var bytes: [8]u8 = undefined;
    while (true) {
        try fillRandom(&bytes);
        const value = std.mem.readInt(u64, &bytes, .big);
        if (value < limit) return value % bound;
    }
}

/// Fills `buf` from the OS entropy pool.
///
/// Celing: this uses the Linux/Android `getrandom` syscall, which keeps the
/// app free of extra dependencies on the platforms we ship today. An iOS host
/// would need its own entropy path (pass an `std.Io`-backed RNG in) before
/// this module can compile for it.
fn fillRandom(buf: []u8) !void {
    if (builtin.os.tag != .linux) @compileError("fillRandom: only the Linux/Android getrandom path is wired up");
    var offset: usize = 0;
    while (offset < buf.len) {
        const rc = std.os.linux.getrandom(buf.ptr + offset, buf.len - offset, 0);
        const signed: isize = @bitCast(rc);
        if (signed <= 0) return error.EntropyUnavailable;
        offset += rc;
    }
}

fn round2(value: f64) f64 {
    return @round(value * 100.0) / 100.0;
}

fn appendText(dst: []u8, text: []const u8) !usize {
    if (dst.len < text.len) return error.NoSpaceLeft;
    @memcpy(dst[0..text.len], text);
    return text.len;
}

// ---------------------------------------------------------------------------
// Checks: `zig test lib/main.zig`
// ---------------------------------------------------------------------------

test "randomInt stays inside the requested range" {
    const arena = std.testing.allocator;
    var seen_min = false;
    var seen_max = false;
    var i: usize = 0;
    while (i < 200) : (i += 1) {
        const out = try randomInt("1 3", arena);
        defer arena.free(out);
        const n = try std.fmt.parseInt(i64, out, 10);
        try std.testing.expect(n >= 1 and n <= 3);
        if (n == 1) seen_min = true;
        if (n == 3) seen_max = true;
    }
    try std.testing.expect(seen_min and seen_max);
    try std.testing.expectError(error.InvalidInput, randomInt("9 2", arena));
    try std.testing.expectError(error.InvalidInput, randomInt("1.5 2", arena));
}

test "rollDice validates spec and sums correctly" {
    const arena = std.testing.allocator;
    const out = try rollDice("2d6", arena);
    defer arena.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, " = ") != null);
    try std.testing.expectError(error.InvalidInput, rollDice("0d6", arena));
    try std.testing.expectError(error.InvalidInput, rollDice("2d1", arena));
    try std.testing.expectError(error.InvalidInput, rollDice("2d6d6", arena));
}

test "coinFlip says Heads or Tails" {
    const arena = std.testing.allocator;
    const out = try coinFlip(arena);
    defer arena.free(out);
    try std.testing.expect(std.mem.eql(u8, out, "Heads") or std.mem.eql(u8, out, "Tails"));
}

test "password has one character per class and no lookalikes" {
    const arena = std.testing.allocator;
    const out = try password("16", arena);
    defer arena.free(out);
    try std.testing.expectEqual(@as(usize, 16), out.len);
    var has_lower = false;
    var has_upper = false;
    var has_digit = false;
    var has_symbol = false;
    for (out) |c| {
        try std.testing.expect(std.mem.indexOfScalar(u8, "lIO01o", c) == null);
        has_lower = has_lower or (c >= 'a' and c <= 'z');
        has_upper = has_upper or (c >= 'A' and c <= 'Z');
        has_digit = has_digit or (c >= '2' and c <= '9');
        has_symbol = has_symbol or std.mem.indexOfScalar(u8, PASSWORD_SYMBOLS, c) != null;
    }
    try std.testing.expect(has_lower and has_upper and has_digit and has_symbol);
    try std.testing.expectError(error.InvalidInput, password("2", arena));
    try std.testing.expectError(error.InvalidInput, password("x", arena));
}

test "bmi rounds and classifies" {
    const arena = std.testing.allocator;
    const healthy = try bmi("70 175", arena);
    defer arena.free(healthy);
    try std.testing.expect(std.mem.eql(u8, healthy, "22.9 - Healthy range"));
    const obese = try bmi("120 175", arena);
    defer arena.free(obese);
    try std.testing.expect(std.mem.eql(u8, obese, "39.2 - Obesity"));
    try std.testing.expectError(error.InvalidInput, bmi("0 175", arena));
}

test "tipSplit splits the bill" {
    const arena = std.testing.allocator;
    const out = try tipSplit("100 15 2", arena);
    defer arena.free(out);
    try std.testing.expect(std.mem.eql(u8, out, "$15.00 tip | $115.00 total | $57.50 each"));
    try std.testing.expectError(error.InvalidInput, tipSplit("100 15 0", arena));
}

test "compound grows and reports interest" {
    const arena = std.testing.allocator;
    const out = try compound("1000 10 2", arena);
    defer arena.free(out);
    try std.testing.expect(std.mem.eql(u8, out, "$1210.00 total | $210.00 gained"));
    try std.testing.expectError(error.InvalidInput, compound("1000 10", arena));
}
