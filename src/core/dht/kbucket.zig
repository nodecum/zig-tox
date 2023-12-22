const std = @import("std");
const tox = @import("../../tox.zig");
const sodium = @import("sodium");
const net = std.net;
const testing = std.testing;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const log = std.log.scoped(.kbucket);

const PublicKey = sodium.PublicKey;
const PackedNode = tox.packet.dht.PackedNode;
const time = tox.core.time;
const Instant = time.Instant;
const dht = tox.core.dht;
const DhtNode = dht.node.DhtNode;
const KBucketDhtNode = dht.node.KBucketDhtNode;
const Address = net.Address;
const Order = std.math.Order;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const binarySearch = tox.sort.binarySearch;

/// Calculate the [`k-tree`](../ktree/struct.Ktree.html) index of a PK compared
/// to "own" PK.
/// According to the [spec](https://zetok.github.io/tox-spec#bucket-index).
/// Fails (returns `None`) only if supplied keys are the same.
pub fn kbucketIndex(own: *const PublicKey, other: *const PublicKey) ?u8 {
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
    try expectEqual(kbucketIndex(&pk1, &pk1), null);
    try expectEqual(kbucketIndex(&pk1, &pk2), 0);
    try expectEqual(kbucketIndex(&pk2, &pk3), 2);
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
    try expectEqual(distance(&pk_00, &pk_02, &pk_01), .gt);
    try expectEqual(distance(&pk_02, &pk_02, &pk_02), .eq);
    try expectEqual(distance(&pk_02, &pk_00, &pk_01), .lt);
    try expectEqual(distance(&pk_02, &pk_ff, &pk_fe), .gt);
    try expectEqual(distance(&pk_fe, &pk_ff, &pk_02), .lt);
}

const KBucketPackedNode = struct {
    const Node = PackedNode;
    const NewNode = PackedNode;
    const CheckNode = PackedNode;
    /// Check if the node can be updated with a new one.
    pub fn isOutdated(self: Node, other: CheckNode) bool {
        return self.saddr != other.saddr;
    }
    /// Update the existing node with a new one.
    pub fn update(self: *Node, other: NewNode, rcv_time: Instant) void {
        _ = rcv_time;
        self.* = other;
    }
    /// Check if the node can be evicted.
    pub fn isEvictable(self: Node, now: Instant) bool {
        _ = now;
        _ = self;
        return false;
    }
    /// Find the index of a node that should be evicted in case if `Kbucket` is
    /// full. It must return `Some` if and only if nodes list contains at least
    /// one evictable node.
    pub fn evictionIndex(nodes: []Node, now: Instant) ?usize {
        _ = now;
        _ = nodes;
        return null;
    }
    pub fn intoNode(n: NewNode, now: Instant) Node {
        _ = now;
        return n;
    }
};

/// Default number of nodes that kbucket can hold.
pub const kbucket_default_size = 8;

fn KBucket(comptime KBucketNode: type) type {
    const Node = comptime KBucketNode.Node;
    const NewNode = comptime KBucketNode.NewNode;
    const CheckNode = comptime KBucketNode.CheckNode;
    _ = CheckNode;
    const intoNode = KBucketNode.intoNode;
    const cmpFn = struct {
        fn cmp(k0: *const PublicKey, k2: *const PublicKey, n: Node) Order {
            return distance(k0, k2, &n.pk);
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
            const res = binarySearch(Node, pk, self.nodes.items, base_pk, cmpFn);
            if (res.found) {
                return res.index;
            } else {
                return null;
            }
        }
        /// Get reference to a `KbucketNode` by it's `PublicKey`.
        pub fn getNode(self: Self, base_pk: *const PublicKey, pk: *const PublicKey) ?*Node {
            if (self.find(base_pk, pk)) |i| {
                return self.nodes.items[i];
            } else return null;
        }
        pub fn tryAdd(
            self: *Self,
            base_pk: *const PublicKey,
            new_node: NewNode,
            now: Instant,
            evict: bool,
        ) bool {
            //log.info("step into", {});
            const res = binarySearch(Node, &new_node.pk, self.nodes.items, base_pk, cmpFn);
            if (res.found) {
                KBucketNode.update(&self.nodes.items[res.index], new_node, now);
                return true;
            } else if (evict == false or res.index == self.nodes.items.len) {
                // index is pointing past the end
                // we are not going to evict the farthest node or the current
                // node is the farthest one
                if (self.nodes.capacity == self.nodes.items.len) {
                    // list is full
                    if (KBucketNode.evictionIndex(self.nodes.items, now)) |eviction_index| {
                        // replace the farthest bad node
                        _ = self.nodes.orderedRemove(eviction_index);
                        const i = res.index - @as(usize, if (eviction_index < res.index) 1 else 0);
                        self.nodes.insertAssumeCapacity(i, intoNode(new_node, now));
                        return true;
                    } else {
                        // Node can't be added to the kbucket.
                        return false;
                    }
                } else {
                    // distance to the PK was bigger than the other keys, but
                    // there's still free space in the kbucket for a node
                    self.nodes.insertAssumeCapacity(res.index, intoNode(new_node, now));
                    return true;
                }
            } else {
                // index is pointing inside the list
                // we are going to evict the farthest node if the kbucket is full
                if (self.nodes.capacity == self.nodes.items.len) {
                    var eviction_index = self.nodes.items.len - 1;
                    if (KBucketNode.evictionIndex(self.nodes.items, now)) |i| {
                        eviction_index = i;
                    }
                    _ = self.nodes.orderedRemove(eviction_index);
                    const cor = @as(usize, if (eviction_index < res.index) 1 else 0);
                    const i = res.index - cor;
                    self.nodes.insertAssumeCapacity(i, intoNode(new_node, now));
                } else {
                    self.nodes.insertAssumeCapacity(res.index, intoNode(new_node, now));
                }
                return true;
            }
        }
        /// Remove KbucketNode with given PK from the Kbucket.
        /// Note that you must pass the same `base_pk` each call or the internal
        /// state will be undefined. Also `base_pk` must be equal to `base_pk` you added
        /// a node with. Normally you don't call this function on your own but Ktree does.
        /// If there's no `KbucketNode` with given PK, nothing is being done.
        pub fn remove(self: Self, base_pk: *const PublicKey, node_pk: *const PublicKey) void {
            const res = binarySearch(Node, node_pk, self.nodes.items, base_pk, cmpFn);
            if (res.found) {
                self.nodes.orderedRemove(res.index);
            }
        }

        /// Check if node with given PK is in the `Kbucket`.
        pub fn contains(self: Self, base_pk: *const PublicKey, pk: *const PublicKey) bool {
            const res = binarySearch(Node, pk, self.nodes.items, base_pk, cmpFn);
            return res.found;
        }
        /// Number of nodes this `Kbucket` contains.
        pub fn len(self: Self) usize {
            return self.nodes.items.len;
        }
        /// Get the capacity of the `Kbucket`.
        pub fn capacity(self: Self) usize {
            return self.nodes.capacity;
        }
        /// Check if `Kbucket` is empty.
        pub fn isEmpty(self: Self) bool {
            return self.len() == 0;
        }
        /// Check if `Kbucket` is full.
        pub fn isFull(self: Self) bool {
            return self.nodes.items.len == self.nodes.capacity;
        }
    };
}

test "KBucket try add" {
    try time.startTimerNow();
    const pk_size = @typeInfo(PublicKey).Array.len;
    const pk = [_]u8{0x00} ** pk_size;

    var kbucket_buffer: [kbucket_default_size]DhtNode = undefined;
    var kbucket = KBucket(KBucketDhtNode).init(&kbucket_buffer);

    for (0..8) |i| {
        const addr = Address.initIp4(.{ 1, 2, 3, 4 }, @as(u16, 12345) + @as(u16, @intCast(i)));
        const pk_i = [_]u8{@as(u8, @intCast(i + 2))} ** pk_size;
        const node = PackedNode{ .saddr = addr, .pk = pk_i };
        try expect(kbucket.tryAdd(&pk, node, Instant.now(), false));
    }
    //for (0..8) |i| {
    //    std.debug.print("i:{d} p:{d}\n", .{ i, kbucket_buffer[i].pk[0] });
    //}
    const closer_node = PackedNode{
        .saddr = Address.initIp4(.{ 1, 2, 3, 5 }, 12345),
        .pk = [_]u8{1} ** pk_size,
    };
    const farther_node = PackedNode{
        .saddr = Address.initIp4(.{ 1, 2, 3, 5 }, 12346),
        .pk = [_]u8{10} ** pk_size,
    };
    const existing_node = PackedNode{
        .saddr = Address.initIp4(.{ 1, 2, 3, 5 }, 12347),
        .pk = [_]u8{2} ** pk_size,
    };
    const now = Instant.now();
    // can't add a new farther node
    try expect(!kbucket.tryAdd(&pk, farther_node, now, true));
    // can't add a new farther node with eviction
    try expect(!kbucket.tryAdd(&pk, farther_node, now, false));
    // can't add a new closer node
    try expect(!kbucket.tryAdd(&pk, closer_node, now, false));
    // can add a new closer node with eviction
    try expect(kbucket.tryAdd(&pk, closer_node, now, true));
    // can update a node
    try expect(kbucket.tryAdd(&pk, existing_node, now, false));
}

test "KBucket try add should replace bad nodes" {
    try time.startTimerNow();
    const pk_size = @typeInfo(PublicKey).Array.len;
    const pk = [_]u8{0x00} ** pk_size;

    var kbucket_buffer: [1]DhtNode = undefined;
    var kbucket = KBucket(KBucketDhtNode).init(&kbucket_buffer);

    const node_1 = PackedNode{
        .saddr = Address.initIp4(.{ 1, 2, 3, 4 }, 12345),
        .pk = [_]u8{1} ** pk_size,
    };

    const node_2 = PackedNode{
        .saddr = Address.initIp4(.{ 1, 2, 3, 4 }, 12346),
        .pk = [_]u8{2} ** pk_size,
    };

    try expect(kbucket.tryAdd(&pk, node_2, Instant.now(), false));
    try expect(!kbucket.tryAdd(&pk, node_1, Instant.now(), false));

    time.advanceTime(dht.node.bad_node_timeout + 10);
    // replacing bad node
    try expect(kbucket.tryAdd(&pk, node_1, Instant.now(), false));
}
