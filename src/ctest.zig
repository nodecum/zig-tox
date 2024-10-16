pub const crypto = @import("ctest/crypto.zig");
const testing = @import("std").testing;

test {
    _ = &crypto;
    // testing.refAllDecls(@This());
}
