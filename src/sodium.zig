const std = @import("std");
//const testing = std.testing;
//const expectEqual = std.testing.expectEqual;

const c = @cImport({
    @cInclude("sodium.h");
});

/// Call this if you use libsodium
/// and have not initialized tox before.
/// returns error.Failed on failure.
pub fn init() !void {
    if (c.sodium_init() < 0) return error.Failed;
}

pub const PublicKey = [c.crypto_box_PUBLICKEYBYTES]u8;
pub const SecretKey = [c.crypto_box_SECRETKEYBYTES]u8;

//test "check that public and privat key have the same size" {
//    expectEqual(
//        c.crypto_box_PUBLICKEYBYTES,
//        c.crypto_box_SECRETKEYBYTES,
//    );
//}

pub fn key_pair(public_key: *PublicKey, secret_key: *SecretKey) !void {
    if (c.crypto_box_keypair(@ptrCast(public_key), @ptrCast(secret_key)) < 0) {
        return error.Failed;
    }
}
