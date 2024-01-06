const std = @import("std");
const crypto = std.crypto;
const X25519 = crypto.dh.X25519;
const nacl = crypto.nacl;

/// public key length
pub const pk_len = 32;
/// secret key length
pub const sk_len = 32;

pub const KeyPair = X25519.KeyPair;
pub const derivePublicKey = X25519.recoverPublicKey;

pub const encrypt = nacl.Box.seal;
pub const decrypt = nacl.Box.open;
