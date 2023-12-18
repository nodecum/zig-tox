const std = @import("std");
const testing = std.testing;
const math = std.math;

pub const SearchResult = struct { found: bool, index: usize };

/// binary search with returned position of possible insertion if
/// value was not found and maintaining the sorted order.
pub fn binarySearch(
    comptime T: type,
    key: anytype,
    items: []const T,
    context: anytype,
    comptime compareFn: fn (context: @TypeOf(context), key: @TypeOf(key), mid_item: T) math.Order,
) SearchResult {
    var size: usize = items.len;
    var left: usize = 0;
    var right: usize = size;
    while (left < right) {
        const mid = left + size / 2;
        // SAFETY: the while condition means `size` is strictly positive, so
        // `size/2 < size`. Thus `left + size/2 < left + size`, which
        // coupled with the `left + size <= self.len()` invariant means
        // we have `left + size/2 < self.len()`, and this is in-bounds.
        switch (compareFn(context, key, items[mid])) {
            .eq => return .{ .found = true, .index = mid },
            .gt => left = mid + 1,
            .lt => right = mid,
        }
        size = right - left;
    }
    return .{ .found = false, .index = left };
}

test "binarySearch" {
    const S = struct {
        fn order_u32(context: void, lhs: u32, rhs: u32) math.Order {
            _ = context;
            return math.order(lhs, rhs);
        }
    };
    try testing.expectEqual(
        SearchResult{ .found = false, .index = 0 },
        binarySearch(u32, @as(u32, 1), &[_]u32{}, {}, S.order_u32),
    );
    try testing.expectEqual(
        SearchResult{ .found = true, .index = 0 },
        binarySearch(u32, @as(u32, 1), &[_]u32{1}, {}, S.order_u32),
    );
    try testing.expectEqual(
        SearchResult{ .found = false, .index = 1 },
        binarySearch(u32, @as(u32, 1), &[_]u32{0}, {}, S.order_u32),
    );
    try testing.expectEqual(
        SearchResult{ .found = false, .index = 0 },
        binarySearch(u32, @as(u32, 0), &[_]u32{1}, {}, S.order_u32),
    );
    try testing.expectEqual(
        SearchResult{ .found = true, .index = 2 },
        binarySearch(u32, @as(u32, 3), &[_]u32{ 1, 2, 3, 4, 5 }, {}, S.order_u32),
    );
    try testing.expectEqual(
        SearchResult{ .found = false, .index = 2 },
        binarySearch(u32, @as(u32, 3), &[_]u32{ 1, 2, 4, 5, 6 }, {}, S.order_u32),
    );
}
