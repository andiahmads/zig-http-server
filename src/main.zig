const std = @import("std");
const http = std.http;
const log = std.log.scoped(.server);

const server_addr = "127.0.0.1";
const server_port = 9000;

// Jalankan server dan tangani permintaan masuk.
fn runServer(server: *http.Server, allocator: std.mem.Allocator) !void {
    outer: while (true) {
        // Terima koneksi masuk.
        var response = try server.accept(.{ .allocator = allocator });
        defer response.deinit();

        while (response.reset() != .closing) {
            // tangani error saat memproses request
            response.wait() catch |err| switch (err) {
                error.HttpHeadersInvalid => continue :outer,
                error.EndOfStream => continue,
                else => return err,
            };

            // proses request
            try handleRequest(&response, allocator);
        }
    }
}

fn handleRequest(response: *http.Server.Response, allocator: std.mem.Allocator) !void {
    log.info("{s} {s} {s}", .{ @tagName(response.request.method), @tagName(response.request.version), response.request.target });

    // membaca request body
    const body = try response.reader().readAllAlloc(allocator, 8192);
    defer allocator.free(body);

    //Setel tajuk "koneksi" ke "tetap hidup" jika ada di tajuk permintaan.
    if (response.request.headers.contains("connection")) {
        try response.headers.append("connection", "keep-alive");
    }

    // Periksa apakah target permintaan dimulai dengan "/get".
    if (std.mem.startsWith(u8, response.request.target, "/get")) {
        // Periksa apakah target permintaan berisi "?chunked".
        if (std.mem.indexOf(u8, response.request.target, "?chunked") != null) {
            response.transfer_encoding = .chunked;
        } else {
            response.transfer_encoding = .{ .content_length = 10 };
        }

        // Setel tajuk "tipe konten" ke "teks/polos".
        try response.headers.append("content_type", "text/plain");

        // tulis response body
        try response.do();
        if (response.request.method != .HEAD) {
            try response.writeAll("Zig ");
            try response.writeAll("Bits!\n");
            try response.finish();
        }
    } else {
        // set status jika 404
        response.status = .not_found;
        try response.do();
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    // initialize the server
    var server = http.Server.init(allocator, .{ .reuse_address = true });
    defer server.deinit();

    // mengikat server ke alamat yang telah kita tentukan sebelumnya:
    log.info("Server is running at {s}:{d}", .{ server_addr, server_port });

    //parsing alamat server
    const address = std.net.Address.parseIp(server_addr, server_port) catch unreachable;
    try server.listen(address);

    // run server
    runServer(&server, allocator) catch |err| {
        // tangani error server
        log.err("server error: {}", .{err});
        if (@errorReturnTrace()) |trace| {
            std.debug.dumpStackTrace(trace.*);
        }
        std.os.exit(0);
    };
}
