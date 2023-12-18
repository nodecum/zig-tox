const std = @import("std");
const sodium = @import("sodium");
const net = std.net;
const testing = std.testing;
const expectEqual = std.testing.expectEqual;

const PublicKey = sodium.PublicKey;

const Order = std.math.Order;
const ArrayListUnmanaged = std.ArrayListUnmanaged;

/// Calculate the [`k-tree`](../ktree/struct.Ktree.html) index of a PK compared
/// to "own" PK.
/// According to the [spec](https://zetok.github.io/tox-spec#bucket-index).
/// Fails (returns `None`) only if supplied keys are the same.
pub fn kbucket_index(own: *const PublicKey, other: *const PublicKey) ?u8 {
    for (own, other, 0..) |x, y, i| {
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

/// Check whether distance between PK1 and own PK is smaller than distance
/// between PK2 and own PK.
pub fn distance(
    own_key: *const PublicKey,
    key_1: *const PublicKey,
    key_2: *const PublicKey,
) Order {
    for (own_key, key_1, key_2) |k0, k1, k2| {
        if (k1 != k2) {
            return std.math.order(k0 ^ k1, k0 ^ k2);
        }
    }
    return .eq;
}

test "kbucket distance test" {
    const size = @typeInfo(PublicKey).Array.len;
    const pk_00 = [_]u8{0x00} ** size;
    const pk_01 = [_]u8{0x01} ** size;
    const pk_02 = [_]u8{0x02} ** size;
    const pk_ff = [_]u8{0xff} ** size;
    const pk_fe = [_]u8{0xfe} ** size;
    try expectEqual(distance(&pk_00, &pk_01, &pk_02), .lt);
    try expectEqual(distance(&pk_02, &pk_02, &pk_02), .eq);
    try expectEqual(distance(&pk_02, &pk_00, &pk_01), .lt);
    try expectEqual(distance(&pk_02, &pk_ff, &pk_fe), .gt);
    try expectEqual(distance(&pk_fe, &pk_ff, &pk_02), .lt);
}

const KBucketPackedNode = struct {
    const Node = comptime PackedNode;
    const NewNode = comptime PackedNode;
    const CheckNode = comptime PackedNode;
    /// Check if the node can be updated with a new one.
    fn is_outdated(self: Node, other: CheckNode) bool {
        return self.saddr != other.saddr;
    }
    /// Update the existing node with a new one.
    fn update(self: *Node, other: NewNode) void {
        self.*.saddr = other.saddr;
    }
    /// Check if the node can be evicted.
    fn is_evictable(self: Node) bool {
        return false;
    }
    /// Find the index of a node that should be evicted in case if `Kbucket` is
    /// full. It must return `Some` if and only if nodes list contains at least
    /// one evictable node.
    fn eviction_index(nodes: []Node) ?usize {
        return null;
    }
    //   fn eviction_index(nodes: &[Self]) -> Option<usize> {
    //        nodes.iter().rposition(|node| node.is_evictable())
    //    }
};

fn KBucket(comptime KBucketNode: type) type {
    const Node = comptime KBucketNode.Node;
    const NewNode = comptime KBucketNode.NewNode;
    const CheckNode = comptime KBucketNode.CheckNode;
    const cmpFn = struct {
        fn cmp(k0: *const PublicKey, k2: *const PublicKey, n: Node) Order {
            return distance(k0, n.pk, k2);
        }
    }.cmp;
    return struct {
        const Self = @This();
        nodes: ArrayListUnmanaged(Node),
        pub fn init(buffer: []Node) Self {
            return Self{
                .nodes = ArrayListUnmanaged(Node).initBuffer(buffer),
            };
        }
        fn find(self: Self, base_pk: *const PublicKey, pk: *const PublicKey) ?usize {
            return std.sort.binarySearch(Node, pk, self.nodes, base_pk, cmpFn);
        }
        /// Get reference to a `KbucketNode` by it's `PublicKey`.
        pub fn getNode(self: Self, base_pk: *const PublicKey, pk: *const PublicKey) ?*Node {
            if (self.find(base_pk, pk)) |i| {
                return self.nodes[i];
            } else return null;
        }
    };
}
