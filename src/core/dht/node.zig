const std = @import("std");
const sodium = @import("sodium");
const tox = @import("tox");
const PublicKey = sodium.PublicKey;
const Ip4Address = std.net.Ip4Address;
const Ip6Address = std.net.Ip6Address;
const Address = std.net.Address;
const Instant = tox.tox_core.time.Instant;
const PackedNode = tox.tox_packet.dht.PackedNode;

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
        saddr: ?T,
        /// Last received ping/nodes-response time
        last_resp_time: ?Instant,
        /// Last sent ping-req time
        last_ping_req_time: ?Instant,
        /// Returned by this node. Either our friend or us
        ret_saddr: ?T,
        /// Last time for receiving returned packet
        ret_last_resp_time: ?Instant,

        pub fn init(saddr: ?T) Self {
            return Self{
                .saddr = saddr,
                .last_resp_time = if (saddr) |_| {
                    Instant.now();
                } else null,
                .last_ping_req_time = null,
                .ret_saddr = null,
                .ret_last_resp_time = null,
            };
        }
        /// Check if the address is considered bad i.e. it does not answer on
        /// addresses for `bad_node_timeout`.
        pub fn is_bad(self: Self, now: Instant) bool {
            return if (self.last_resp_time) |t| now.since(t) > bad_node_timeout else true;
        }
        /// Check if the node is considered discarded i.e. it does not answer on
        /// addresses for `kill_node_timeout`.
        pub fn is_discarded(self: Self, now: Instant) bool {
            return if (self.last_resp_time) |t| now.since(t) > kill_node_timeout else true;
        }
        /// Check if `ping_interval` is passed after last ping request.
        pub fn is_ping_interval_passed(self: Self, now: Instant) bool {
            return if (self.last_ping_req_time) |t| now.since() >= ping_intervall else true;
        }
        /// Get address if it should be pinged and update `last_ping_req_time`.
        pub fn ping_addr(self: *Self, now: Instant) ?T {
            if (self.saddr) |addr| {
                if (!self.is_discarded(now) and
                    self.is_ping_interval_passed(now))
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
    const SockAndTimeIp4 = SockAndTime(Ip4Address);
    const SockAndTimeIp6 = SockAndTime(Ip6Address);

    /// Socket addr and times of node for IPv4.
    assoc4: SockAndTimeIp4,
    /// Socket addr and times of node for IPv6.
    assoc6: SockAndTimeIp6,
    /// Public key of the node.
    pk: PublicKey,

    /// create DhtNode object
    pub fn init(pn: PackedNode) DhtNode {
        const addr = pn.saddr;
        return switch (addr.any.family) {
            os.AF.INET => DhtNode{
                .assoc4 = SockAndTimeIp4.init(addr.in),
                .assoc6 = null,
                .pk = pn.pk,
            },
            os.AF.INET6 => DhtNode{
                .assoc4 = null,
                .assoc6 = SockAndTimeIp6.init(addr.in6),
                .pk = pn.pk,
            },
            else => unreachable,
        };
    }
    /// Check if the node is considered bad i.e. it does not answer both on IPv4
    /// and IPv6 addresses for `BAD_NODE_TIMEOUT` seconds.
    pub fn is_bad(self: DhtNode, now: Instant) bool {
        return self.assoc4.is_bad(now) and self.assoc6.is_bad(now);
    }

    /// Check if the node is considered discarded i.e. it does not answer both
    /// on IPv4 and IPv6 addresses for `KILL_NODE_TIMEOUT`.
    pub fn is_discarded(self: DhtNode, now: Instant) bool {
        return self.assoc4.is_discarded(now) and self.assoc6.is_discarded(now);
    }

    /// Return `SocketAddr` for `DhtNode` based on the last response time.
    pub fn get_socket_addr(self: DhtNode) Address {
        if (self.assoc4.last_resp_time) |t4| {
            if (self.assoc6.last_resp_time) |t6| {}
        }
    }
};
