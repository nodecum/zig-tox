const std = @import("std");
const sodium = @import("sodium");
const Address = std.net.Address;
const PublicKey = sodium.PublicKey;
pub const PackedNode = @This();

/// Socket Addr of node.
saddr: net.Address,
/// Public key of the node.
pk: PublicKey,

// pub const Protocol = enum(u1) {
//        UDP = 0,
//        TCP = 1,
//    };
//    pub const AddressFamily = enum(u7) {
//        IPv4 = 2,
//        IPv6 = 10,
//    };
//    pub const ProtocolAndAddressFamily = packed struct(u8) {
//        family: AddressFamily, // lower bits
//        protocol: Protocol, // higher bits
//    };
