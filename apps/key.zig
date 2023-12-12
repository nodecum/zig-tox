const std = @import("std");
const sodium = @import("sodium");

const PublicKey = sodium.PublicKey;
const SecretKey = sodium.SecretKey;

pub fn main() !void {
    try sodium.init();

    var pk: PublicKey = undefined;
    var sk: SecretKey = undefined;

    try sodium.key_pair(&pk, &sk);

    // const hexToBytes = std.fmt.hexToBytes;
    const bytesToHex = std.fmt.fmtSliceHexUpper;

    std.debug.print(
        ".secret_key=\"{s}\",\n",
        .{bytesToHex(&sk)},
    );
    std.debug.print(
        ".public_key=\"{s}\",\n",
        .{bytesToHex(&pk)},
    );
}
