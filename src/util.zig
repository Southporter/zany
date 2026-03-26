// Compute a hash for a string.
// This is based on 'djb2' algorithm.
//
pub fn strhash(str: []const u8) u64 {
    var hash: u64 = 5381;

    for (str) |c| {
        hash = ((hash << 5) +% hash) + c;
    }

    return hash;
}
