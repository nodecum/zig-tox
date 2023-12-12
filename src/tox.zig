pub const tox_core = @import("tox_core.zig");
pub const tox_packet = @import("tox_packet.zig");

const testing = @import("std").testing;

test {
    testing.refAllDecls(@This());
}
