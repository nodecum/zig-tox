const std = @import("std");
const testing = std.testing;
const tox = @import("../tox.zig");
const crypto = tox.crypto;
// const c = @import("c-toxcore");
const c = @cImport({
    @cInclude("toxcore/crypto_core.h");
});

test "generate public key from secret key" {
    const kp = try crypto.KeyPair.create(null);
    var pk: crypto.PublicKey = undefined;
    c.crypto_derive_public_key(@ptrCast(&pk), @ptrCast(&kp.secret_key));
    try testing.expectEqualSlices(u8, &kp.public_key, &pk);
}
