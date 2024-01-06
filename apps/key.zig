const std = @import("std");
const cr = @import("tox").crypto;

pub fn main() !void {
    const kp = try cr.KeyPair.create(null);

    const bytesToHex = std.fmt.fmtSliceHexUpper;

    std.debug.print(
        ".secret_key=\"{s}\",\n",
        .{bytesToHex(&kp.secret_key)},
    );
    std.debug.print(
        ".public_key=\"{s}\",\n",
        .{bytesToHex(&kp.public_key)},
    );
}
