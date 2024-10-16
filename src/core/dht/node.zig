const std = @import("std");
const tox = @import("../../tox.zig");
const PublicKey = tox.crypto.PublicKey;
const Ip4Address = std.net.Ip4Address;
const Ip6Address = std.net.Ip6Address;
const Address = std.net.Address;
const AF = std.posix.AF;
const Instant = tox.core.time.Instant;
const PackedNode = tox.packet.dht.PackedNode;

/// Ping interval in decisecond for each node in our lists.
pub const ping_interval: u32 = 60 * 10;

/// Interval of time in deciseconds for a
/// non responsive node to become bad.
pub const bad_node_timeout: u32 = ping_interval * 2 + 2 * 10;

/// The timeout after which a node is discarded completely.
pub const kill_node_timeout: u32 = bad_node_timeout + ping_interval;

fn SockAndTime(comptime T: type) type {
    return struct {
        const Self = @This();
        /// Socket Addr of node.
        saddr: ?T = null,
        /// Last received ping/nodes-response time
        last_resp_time: ?Instant = null,
        /// Last sent ping-req time
        last_ping_req_time: ?Instant = null,
        /// Returned by this node. Either our friend or us
        ret_saddr: ?T = null,
        /// Last time for receiving returned packet
        ret_last_resp_time: ?Instant = null,

        pub fn init(saddr: T, now: Instant) Self {
            return Self{
                .saddr = saddr,
                .last_resp_time = now,
            };
        }
        /// Check if the address is considered bad i.e. it does not answer on
        /// addresses for `bad_node_timeout`.
        pub fn isBad(self: Self, now: Instant) bool {
            return if (self.last_resp_time) |t| now.since(t) > bad_node_timeout else true;
        }
        /// Check if the node is considered discarded i.e. it does not answer on
        /// addresses for `kill_node_timeout`.
        pub fn isDiscarded(self: Self, now: Instant) bool {
            return if (self.last_resp_time) |t| now.since(t) > kill_node_timeout else true;
        }
        /// Check if `ping_interval` is passed after last ping request.
        pub fn isPingIntervalPassed(self: Self, now: Instant) bool {
            return if (self.last_ping_req_time) |t| now.since(t) >= ping_interval else true;
        }
        /// Get address if it should be pinged and update `last_ping_req_time`.
        pub fn pingAddr(self: *Self, now: Instant) ?T {
            if (self.saddr) |addr| {
                if (!self.isDiscarded(now) and
                    self.isPingIntervalPassed(now))
                {
                    self.last_ping_req_time = now;
                    return addr;
                }
            }
            return null;
        }
    };
}

/// Struct used by Bucket, DHT maintains close node list, when we got new node,
/// we should make decision to add new node to close node list, or not.
/// the PK's distance and status of node help making decision.
/// Bad node have higher priority than Good node.
/// If both node is Good node, then we compare PK's distance.
pub const DhtNode = struct {
    const Self = @This();
    const SockAndTimeIp4 = SockAndTime(Ip4Address);
    const SockAndTimeIp6 = SockAndTime(Ip6Address);

    /// Socket addr and times of node for IPv4.
    assoc4: SockAndTimeIp4,
    /// Socket addr and times of node for IPv6.
    assoc6: SockAndTimeIp6,
    /// Public key of the node.
    pk: PublicKey,

    /// create DhtNode object
    pub fn init(pn: PackedNode, now: Instant) Self {
        const addr = pn.saddr;
        return switch (addr.any.family) {
            AF.INET => Self{
                .assoc4 = SockAndTimeIp4.init(addr.in, now),
                .assoc6 = SockAndTimeIp6{},
                .pk = pn.pk,
            },
            AF.INET6 => Self{
                .assoc4 = SockAndTimeIp4{},
                .assoc6 = SockAndTimeIp6.init(addr.in6, now),
                .pk = pn.pk,
            },
            else => unreachable,
        };
    }
    /// Check if the node is considered bad i.e. it does not answer both on IPv4
    /// and IPv6 addresses for `BAD_NODE_TIMEOUT` seconds.
    pub fn isBad(self: Self, now: Instant) bool {
        return self.assoc4.isBad(now) and self.assoc6.isBad(now);
    }

    /// Check if the node is considered discarded i.e. it does not answer both
    /// on IPv4 and IPv6 addresses for `KILL_NODE_TIMEOUT`.
    pub fn isDiscarded(self: Self, now: Instant) bool {
        return self.assoc4.isDiscarded(now) and self.assoc6.isDiscarded(now);
    }

    /// Return `SocketAddr` for `DhtNode` based on the last response time.
    pub fn getSocketAddr(self: Self) ?Address {
        if (self.assoc4.last_resp_time) |t4| {
            if (self.assoc6.last_resp_time) |t6| {
                if (t6 > t4) {
                    if (self.assoc6.saddr) |a6| {
                        return Address{ .in6 = a6 };
                    }
                }
            }
            if (self.assoc4.saddr) |a4| {
                return Address{ .in = a4 };
            }
        }
        if (self.assoc6.saddr) |a6| {
            return Address{ .in6 = a6 };
        }
        return null;
    }
    pub fn getAllAddrs(self: Self, buf: [2]Address) []Address {
        var n: usize = 0;
        if (self.assoc4.saddr) |a4| {
            buf[n] = Address{ .in = a4 };
            n += 1;
        }
        if (self.assoc6.saddr) |a6| {
            buf[n] = Address{ .in6 = a6 };
            n += 1;
        }
        return buf[0..n];
    }
    /// Convert `DhtNode` to `PackedNode`. The address is chosen based on the
    /// last response time.
    pub fn toPackedNode(self: Self) ?PackedNode {
        if (self.getSocketAddr()) |ad| {
            return PackedNode{ .saddr = ad, .pk = self.pk };
        } else {
            return null;
        }
    }
    /// Convert `DhtNode` to list of `PackedNode` which can contain IPv4 and
    /// IPv6 addresses.
    pub fn toAllPackedNodes(self: Self, buf: [2]PackedNode) []PackedNode {
        const ads = self.get_all_addrs();
        for (ads, 0..) |ad, i| {
            buf[i] = PackedNode{ .saddr = ad, .pk = self.pk };
        }
        return buf[0..ads.len];
    }
    /// Update returned socket address and time of receiving packet
    pub fn updateReturnedAddr(self: *Self, addr: Address, now: Instant) void {
        switch (addr.any.family) {
            AF.INET => {
                self.assoc4.ret_saddr = addr.in;
                self.assoc4.ret_last_resp_time = now;
            },
            AF.INET6 => {
                self.assoc6.ret_saddr = addr.in6;
                self.assoc6.ret_last_resp_time = now;
            },
            else => unreachable,
        }
    }
};

pub const KBucketDhtNode = struct {
    pub const Node = DhtNode;
    pub const NewNode = PackedNode;
    pub const CheckNode = PackedNode;
    /// Check if the node can be updated with a new one.
    pub fn isOutdated(self: Node, other: CheckNode) bool {
        switch (other.saddr.any.family) {
            AF.INET => {
                if (self.assoc4.saddr) |a| {
                    return a == other.saddr.in;
                }
            },
            AF.INET6 => {
                if (self.assoc6.saddr) |a| {
                    return a == other.saddr.in6;
                }
            },
            else => unreachable,
        }
        return false;
    }
    /// Update the existing node with a new one.
    pub fn update(self: *Node, other: NewNode, rcv_time: Instant) void {
        switch (other.saddr.any.family) {
            AF.INET => {
                self.assoc4.saddr = other.saddr.in;
                self.assoc4.last_resp_time = rcv_time;
            },
            AF.INET6 => {
                self.assoc6.saddr = other.saddr.in6;
                self.assoc6.last_resp_time = rcv_time;
            },
            else => unreachable,
        }
    }
    /// Check if the node can be evicted.
    pub fn isEvictable(self: Node, now: Instant) bool {
        return self.isBad(now);
    }
    /// Find the index of a node that should be evicted in case if `Kbucket` is
    /// full. It must return `Some` if and only if nodes list contains at least
    /// one evictable node.ad
    pub fn evictionIndex(nodes: []Node, now: Instant) ?usize {
        var bad_idx = nodes.len;
        for (1..nodes.len + 1) |i| {
            const ri = nodes.len - i;
            if (nodes[ri].isDiscarded(now)) return ri;
            if (bad_idx == nodes.len and nodes[ri].isBad(now))
                bad_idx = ri;
        }
        if (bad_idx < nodes.len) return bad_idx;
        return null;
    }
    pub fn intoNode(n: NewNode, now: Instant) Node {
        return DhtNode.init(n, now);
    }
};
