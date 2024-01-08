const std = @import("std");
const cr = @import("tox").crypto;

pub fn main() !void {
    const bytesToHex = std.fmt.fmtSliceHexUpper;

    const kp = try cr.KeyPair.create(null);
    std.debug.print(
        ".secret_key=\"{s}\",\n",
        .{bytesToHex(&kp.secret_key)},
    );
    std.debug.print(
        ".public_key=\"{s}\",\n",
        .{bytesToHex(&kp.public_key)},
    );
}
