const std = @import("std");
const stdInstant = std.time.Instant;
const is_test = @import("builtin").is_test;
const testing = std.testing;
const expect = std.testing.expect;

/// time of timer start
pub var startTime: stdInstant = undefined;

/// initialize Timer
pub fn startTimerNow() error{Unsupported}!void {
    startTime = try stdInstant.now();
}

/// nano seconds per decisecond
pub const ns_per_ds = std.time.ns_per_ms * 100;

///
var advance_offset: u32 = 0;
/// advance the time in deciseconds
/// this works only for tests
pub fn advanceTime(ds: u32) void {
    if (is_test) {
        advance_offset += ds;
    }
}

/// timestamp with decisecond (1/10 second) resolution
pub const Instant = struct {
    timestamp: u32,
    pub fn now() Instant {
        const dt_ns = stdInstant.since(
            // if not implemented we return
            // the startup time wich wont exist
            // in this case, either way
            stdInstant.now() catch startTime,
            startTime,
        );
        const ts = if (is_test)
            @as(u32, @intCast(dt_ns / ns_per_ds)) + advance_offset
        else
            @as(u32, @intCast(dt_ns / ns_per_ds));
        return Instant{
            .timestamp = ts,
        };
    }
    // difference in deciseconds
    pub fn since(self: Instant, earlier: Instant) u32 {
        return self.timestamp - earlier.timestamp;
    }
};

test "advance time" {
    try startTimerNow();
    const earlier = Instant.now();
    advanceTime(10);
    const later = Instant.now();
    try expect(later.since(earlier) >= 10);
}
