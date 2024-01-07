const std = @import("std");
const crypto = std.crypto;
const X25519 = crypto.dh.X25519;
const nacl = crypto.nacl;

/// public key length
pub const pk_len = 32;
/// secret key length
pub const sk_len = 32;
/// array which can hold an public key
pub const PublicKey = [pk_len]u8;

pub const KeyPair = X25519.KeyPair;
pub const derivePublicKey = X25519.recoverPublicKey;

pub const encrypt = nacl.Box.seal;
pub const decrypt = nacl.Box.open;

test "encrypt and decrypt test" {
    const kp_a = try KeyPair.create(null);
    const kp_b = try KeyPair.create(null);
    const msg_1 = "Hello Tox!";
    var msg_enc: [msg_1.len + nacl.Box.tag_length]u8 = undefined;
    var msg_2: [msg_1.len]u8 = undefined;
    const nonce = [_]u8{0} ** nacl.Box.nonce_length;
    try encrypt(&msg_enc, msg_1, nonce, kp_b.public_key, kp_a.secret_key);
    try decrypt(&msg_2, &msg_enc, nonce, kp_a.public_key, kp_b.secret_key);
    try std.testing.expectEqualStrings(msg_1, &msg_2);
}
