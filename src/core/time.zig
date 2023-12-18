const std = @import("std");
const stdInstant = std.time.Instant;

/// time of startup
pub const startup = stdInstant.now();

// nano seconds per decisecond
pub const ns_per_ds = std.time.ns_per_ms * 100;

/// timestamp with decisecond (1/10 second) resolution
pub const Instant = struct {
    timestamp: u32,
    pub fn now() error{Unsupported}!Instant {
        const dt_ns = stdInstant.since(
            stdInstant.now(),
            startup,
        );
        return Instant{
            .timestamp = @as(u32, @intCast(dt_ns / ns_per_ds)),
        };
    }
    // difference in deciseconds
    pub fn since(self: Instant, earlier: Instant) u32 {
        return earlier.timestamp - self.timestamp;
    }
};
