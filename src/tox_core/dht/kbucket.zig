const std = @import("std");
const sodium = @import("sodium");
const net = std.net;
const testing = std.testing;
const expectEqual = std.testing.expectEqual;

const PublicKey = sodium.PublicKey;

/// Calculate the [`k-tree`](../ktree/struct.Ktree.html) index of a PK compared
/// to "own" PK.
/// According to the [spec](https://zetok.github.io/tox-spec#bucket-index).
/// Fails (returns `None`) only if supplied keys are the same.
pub fn kbucket_index(own_pk: *const PublicKey, other_pk: *const PublicKey) ?u8 {
    for (own_pk, other_pk, 0..) |x, y, i| {
        const byte = x ^ y;
        for (0..8) |j| {
            const j_ = @as(u3, @intCast(j));
            if (byte & (@as(u8, 0x80) >> j_) != 0) {
                return @as(u8, @intCast(i)) * 8 + j_;
            }
        }
    }
    return null; // PKs are equal
}

test "kbucket index test" {
    const size = @typeInfo(PublicKey).Array.len;
    const pk1 = [_]u8{0b10_10_10_10} ** size;
    const pk2 = [_]u8{0} ** size;
    const pk3 = [_]u8{0b00_10_10_10} ** size;
    try expectEqual(kbucket_index(&pk1, &pk1), null);
    try expectEqual(kbucket_index(&pk1, &pk2), 0);
    try expectEqual(kbucket_index(&pk2, &pk3), 2);
}
