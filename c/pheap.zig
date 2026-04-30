const std = @import("std");
const builtin = @import("builtin");
const header = @import("header.zig");
const pointer = @import("pointer.zig");
const wal_mod = @import("wal.zig");
const security = @import("security.zig");

const os = std.os;
const posix = std.posix;

pub const PersistentHeap = struct {
    base_addr: [*]align(std.mem.page_size) u8,
    size: u64,
    file: std.fs.File,
    file_path: []const u8,
    header: *header.HeapHeader,
    pool_uuid: u128,
    security: ?*security.SecurityManager,
    allocator: std.mem.Allocator,
    dirty_pages: []bool,
    dirty_page_count: u64,
    is_dirty: bool,
    mmap_fd: posix.fd_t,

    const MMAP_PROT = posix.PROT.READ | posix.PROT.WRITE;
    const MMAP_FLAGS = posix.MAP.SHARED;

    pub fn init(
        allocator_ptr: std.mem.Allocator,
        file_path: []const u8,
        size: u64,
        security_mgr: ?*security.SecurityManager,
    ) !*PersistentHeap {
        const self = try allocator_ptr.create(PersistentHeap);
        errdefer allocator_ptr.destroy(self);

        const path_copy = try allocator_ptr.dupe(u8, file_path);
        errdefer allocator_ptr.free(path_copy);

        const aligned_size = alignToPageSize(size);
        const open_result = try openOrCreateFile(file_path, aligned_size);
        var file = open_result.file;
        const needs_init = open_result.created;
        errdefer file.close();

        const base_addr = try mapFile(file.handle, aligned_size);
        errdefer unmapFile(base_addr, aligned_size);

        const heap_header: *header.HeapHeader = @ptrCast(@alignCast(base_addr));

        if (needs_init) {
            heap_header.* = header.HeapHeader.init(aligned_size);
            heap_header.setDirty(true);
            heap_header.updateChecksum();
            try flushRangeRaw(base_addr, @sizeOf(header.HeapHeader));
            heap_header.setDirty(false);
            heap_header.updateChecksum();
            try flushRangeRaw(base_addr, @sizeOf(header.HeapHeader));
        } else {
            try heap_header.validate();
        }

        const pool_uuid = heap_header.getPoolUUID();
        const page_count = pageCount(aligned_size);
        const dirty_pages = try allocator_ptr.alloc(bool, page_count);
        @memset(dirty_pages, false);

        self.* = PersistentHeap{
            .base_addr = base_addr,
            .size = aligned_size,
            .file = file,
            .file_path = path_copy,
            .header = heap_header,
            .pool_uuid = pool_uuid,
            .security = security_mgr,
            .allocator = allocator_ptr,
            .dirty_pages = dirty_pages,
            .dirty_page_count = 0,
            .is_dirty = false,
            .mmap_fd = file.handle,
        };

        return self;
    }

    pub fn deinit(self: *PersistentHeap) void {
        self.flush() catch {};
        unmapFile(self.base_addr, self.size);
        self.file.close();
        self.allocator.free(self.dirty_pages);
        self.allocator.free(self.file_path);
        self.allocator.destroy(self);
    }

    pub fn getSize(self: *const PersistentHeap) u64 {
        return self.size;
    }

    pub fn getUsedSize(self: *const PersistentHeap) u64 {
        return self.header.used_size;
    }

    pub fn getBaseAddress(self: *const PersistentHeap) [*]u8 {
        return @ptrCast(self.base_addr);
    }

    pub fn getPoolUUID(self: *const PersistentHeap) u128 {
        return self.pool_uuid;
    }

    pub fn getRoot(self: *PersistentHeap) ?pointer.PersistentPtr {
        const root = self.header.getRootPtr();
        if (root) |r| {
            return pointer.PersistentPtr{
                .pool_uuid = r.uuid,
                .offset = r.offset,
            };
        }
        return null;
    }

    pub fn setRoot(self: *PersistentHeap, tx: anytype, ptr: pointer.PersistentPtr) !void {
        _ = tx;
        self.header.setRootPtr(ptr.offset, ptr.pool_uuid);
        self.header.updateChecksum();
        try self.flushRange(@sizeOf(header.HeapHeader));
    }

    pub fn resolvePtr(self: *const PersistentHeap, ptr: pointer.PersistentPtr) !?*anyopaque {
        if (ptr.isNull()) {
            return null;
        }

        if (ptr.pool_uuid != self.pool_uuid) {
            return error.UUIDMismatch;
        }

        if (ptr.offset >= self.size) {
            return error.OutOfBounds;
        }

        const addr = @intFromPtr(self.base_addr) + toUsize(ptr.offset);
        return @ptrFromInt(addr);
    }

    pub fn getNativePtr(self: *const PersistentHeap, comptime T: type, ptr: pointer.PersistentPtr) !?*T {
        const raw = try self.resolvePtr(ptr);
        if (raw) |r| {
            return @ptrCast(@alignCast(r));
        }
        return null;
    }

    pub fn allocate(self: *PersistentHeap, tx: anytype, size: u64, alignment: u64) !pointer.PersistentPtr {
        _ = tx;
        const effective_alignment = if (alignment == 0) 1 else alignment;
        const aligned_size = alignTo(size, effective_alignment);
        const aligned_offset = alignTo(self.header.used_size, effective_alignment);

        if (aligned_offset > self.size or aligned_size > self.size - aligned_offset) {
            return error.OutOfMemory;
        }

        self.header.used_size = aligned_offset + aligned_size;
        self.header.setDirty(true);
        self.header.updateChecksum();
        self.markDirty(0, @sizeOf(header.HeapHeader));

        return pointer.PersistentPtr{
            .pool_uuid = self.pool_uuid,
            .offset = aligned_offset,
        };
    }

    pub fn deallocate(self: *PersistentHeap, tx: anytype, ptr: pointer.PersistentPtr) !void {
        _ = self;
        _ = tx;
        _ = ptr;
    }

    pub fn write(self: *PersistentHeap, offset: u64, data: []const u8) !void {
        const data_len: u64 = @intCast(data.len);
        if (offset > self.size or data_len > self.size - offset) {
            return error.OutOfBounds;
        }

        const dest = addressAt(self.base_addr, offset);
        @memcpy(dest[0..data.len], data);

        self.markDirty(offset, data_len);
    }

    pub fn read(self: *const PersistentHeap, offset: u64, buffer: []u8) !void {
        const buffer_len: u64 = @intCast(buffer.len);
        if (offset > self.size or buffer_len > self.size - offset) {
            return error.OutOfBounds;
        }

        const src = addressAt(self.base_addr, offset);
        @memcpy(buffer, src[0..buffer.len]);
    }

    pub fn writeObject(self: *PersistentHeap, offset: u64, obj_header: *const header.ObjectHeader, data: []const u8) !void {
        const object_header_size: u64 = @intCast(@sizeOf(header.ObjectHeader));
        const data_len: u64 = @intCast(data.len);
        const total_size = object_header_size + data_len;

        if (offset > self.size or total_size > self.size - offset) {
            return error.OutOfBounds;
        }

        const header_ptr: *header.ObjectHeader = @ptrCast(@alignCast(addressAt(self.base_addr, offset)));
        header_ptr.* = obj_header.*;

        const data_offset = offset + object_header_size;
        try self.write(data_offset, data);

        self.markDirty(offset, total_size);
    }

    pub fn readObject(self: *const PersistentHeap, offset: u64) !?struct { header: header.ObjectHeader, data: []u8 } {
        const object_header_size: u64 = @intCast(@sizeOf(header.ObjectHeader));
        if (offset > self.size or object_header_size > self.size - offset) {
            return null;
        }

        const obj_header: *const header.ObjectHeader = @ptrCast(@alignCast(addressAt(self.base_addr, offset)));
        try obj_header.validate();

        if (obj_header.isFreed()) {
            return null;
        }

        const data_offset = offset + object_header_size;
        const data_size: usize = @intCast(obj_header.size);
        const data_size_u64: u64 = @intCast(data_size);

        if (data_offset > self.size or data_size_u64 > self.size - data_offset) {
            return error.CorruptedObject;
        }

        const data_ptr = addressAt(self.base_addr, data_offset);
        const data = data_ptr[0..data_size];

        return .{
            .header = obj_header.*,
            .data = data,
        };
    }

    pub fn markDirty(self: *PersistentHeap, offset: u64, len: u64) void {
        if (len == 0) {
            return;
        }

        const page_size_u64 = @as(u64, std.mem.page_size);
        const start_page: usize = @intCast(offset / page_size_u64);
        const end_page: usize = @intCast((offset + len - 1) / page_size_u64);

        var i: usize = start_page;
        while (i <= end_page and i < self.dirty_pages.len) : (i += 1) {
            if (!self.dirty_pages[i]) {
                self.dirty_pages[i] = true;
                self.dirty_page_count += 1;
            }
        }
        self.is_dirty = true;
    }

    pub fn flush(self: *PersistentHeap) !void {
        if (!self.is_dirty) return;

        self.header.setDirty(false);
        self.header.updateChecksum();

        try self.flushRange(self.size);

        self.is_dirty = false;
        @memset(self.dirty_pages, false);
        self.dirty_page_count = 0;
    }

    pub fn flushRange(self: *PersistentHeap, len: u64) !void {
        const clamped = @min(len, self.size);
        try flushRangeRaw(self.base_addr, @as(usize, @intCast(clamped)));
    }

    pub fn sync(self: *PersistentHeap) !void {
        try self.flush();
        try posix.fsync(self.file.handle);
    }

    pub fn expand(self: *PersistentHeap, new_size: u64) !void {
        if (new_size <= self.size) {
            return;
        }

        try self.flush();

        const aligned_new_size = alignToPageSize(new_size);
        const old_base = self.base_addr;
        const old_size = self.size;

        try self.file.setEndPos(aligned_new_size);
        errdefer self.file.setEndPos(old_size) catch {};

        const new_base = try mapFile(self.file.handle, aligned_new_size);
        errdefer unmapFile(new_base, aligned_new_size);

        const new_header: *header.HeapHeader = @ptrCast(@alignCast(new_base));
        new_header.heap_size = aligned_new_size;
        new_header.setDirty(true);
        new_header.updateChecksum();
        try flushRangeRaw(new_base, @sizeOf(header.HeapHeader));
        new_header.setDirty(false);
        new_header.updateChecksum();
        try flushRangeRaw(new_base, @sizeOf(header.HeapHeader));

        const new_page_count = pageCount(aligned_new_size);
        const new_dirty_pages = try self.allocator.alloc(bool, new_page_count);
        errdefer self.allocator.free(new_dirty_pages);
        @memset(new_dirty_pages, false);

        self.base_addr = new_base;
        self.header = new_header;
        self.size = aligned_new_size;
        self.mmap_fd = self.file.handle;

        unmapFile(old_base, old_size);
        self.allocator.free(self.dirty_pages);
        self.dirty_pages = new_dirty_pages;
        self.dirty_page_count = 0;
        self.is_dirty = false;
    }

    pub fn getDirtyPages(self: *const PersistentHeap) []const bool {
        return self.dirty_pages;
    }

    pub fn getDirtyPageCount(self: *const PersistentHeap) u64 {
        return self.dirty_page_count;
    }

    pub fn clearDirty(self: *PersistentHeap) void {
        @memset(self.dirty_pages, false);
        self.dirty_page_count = 0;
        self.is_dirty = false;
    }

    pub fn beginTransaction(self: *PersistentHeap) !void {
        self.header.transaction_id += 1;
        self.header.setDirty(true);
        self.header.updateChecksum();
        try self.flushRange(@sizeOf(header.HeapHeader));
    }

    pub fn endTransaction(self: *PersistentHeap) !void {
        self.header.setDirty(false);
        self.header.updateChecksum();
        try self.flushRange(@sizeOf(header.HeapHeader));
        try self.sync();
    }

    pub fn getTransactionId(self: *const PersistentHeap) u64 {
        return self.header.transaction_id;
    }
};

fn alignTo(value: u64, alignment: u64) u64 {
    if (alignment <= 1) {
        return value;
    }

    const remainder = value % alignment;
    if (remainder == 0) {
        return value;
    }

    return value + (alignment - remainder);
}

fn alignToPageSize(value: u64) u64 {
    return alignTo(value, @as(u64, std.mem.page_size));
}

fn toUsize(value: u64) usize {
    return @as(usize, @intCast(value));
}

fn pageCount(size: u64) usize {
    return toUsize(size / @as(u64, std.mem.page_size));
}

fn addressAt(base_addr: [*]align(std.mem.page_size) u8, offset: u64) [*]u8 {
    const addr: usize = @intFromPtr(base_addr) + toUsize(offset);
    return @ptrFromInt(addr);
}

const OpenResult = struct {
    file: std.fs.File,
    created: bool,
};

fn openOrCreateFile(path: []const u8, size: u64) !OpenResult {
    const existing = std.fs.cwd().openFile(path, .{ .mode = .read_write }) catch |err| switch (err) {
        error.FileNotFound => {
            const file = try std.fs.cwd().createFile(path, .{ .read = true, .truncate = false });
            errdefer file.close();
            try file.setEndPos(size);
            return .{ .file = file, .created = true };
        },
        else => return err,
    };
    errdefer existing.close();

    const stat = try existing.stat();
    if (stat.size < size) {
        try existing.setEndPos(size);
    }
    return .{ .file = existing, .created = stat.size == 0 };
}

fn mapFile(fd: posix.fd_t, size: u64) ![*]align(std.mem.page_size) u8 {
    const mapped_size: usize = @intCast(size);
    const ptr = try posix.mmap(
        null,
        mapped_size,
        posix.PROT.READ | posix.PROT.WRITE,
        .{ .TYPE = .SHARED },
        fd,
        0,
    );
    return @alignCast(ptr);
}

fn unmapFile(base_addr: [*]align(std.mem.page_size) u8, size: u64) void {
    const len: usize = @intCast(size);
    posix.munmap(base_addr[0..len]);
}

fn flushRangeRaw(base_addr: [*]align(std.mem.page_size) u8, len: usize) !void {
    if (len == 0) {
        return;
    }

    const page_size = std.mem.page_size;
    const addr_int = @intFromPtr(base_addr);
    const page_mask: usize = page_size - 1;
    const page_aligned = addr_int & ~page_mask;
    const offset_into_page = addr_int - page_aligned;
    const total_len = len + offset_into_page;
    const aligned_len = (total_len + page_mask) & ~page_mask;

    const aligned_ptr: [*]align(std.mem.page_size) u8 = @ptrFromInt(page_aligned);
    try posix.msync(aligned_ptr[0..aligned_len], posix.MSF.SYNC);
}

test "heap initialization" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const test_path = "/tmp/test_heap_init.dat";
    std.fs.cwd().deleteFile(test_path) catch {};

    var heap = try PersistentHeap.init(alloc, test_path, 1024 * 1024, null);
    defer heap.deinit();

    try testing.expect(heap.size >= 1024 * 1024);
    try testing.expect(heap.pool_uuid != 0);
}

test "heap allocation" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const test_path = "/tmp/test_heap_alloc.dat";
    std.fs.cwd().deleteFile(test_path) catch {};

    var heap = try PersistentHeap.init(alloc, test_path, 1024 * 1024, null);
    defer heap.deinit();

    const ptr = try heap.allocate(null, 256, 64);
    try testing.expect(!ptr.isNull());
    try testing.expect(ptr.offset >= header.HEADER_SIZE);
}

test "heap read/write" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const test_path = "/tmp/test_heap_rw.dat";
    std.fs.cwd().deleteFile(test_path) catch {};

    var heap = try PersistentHeap.init(alloc, test_path, 1024 * 1024, null);
    defer heap.deinit();

    const test_data = "Hello, Persistent World!";
    try heap.write(header.HEADER_SIZE, test_data);

    var buffer: [32]u8 = undefined;
    try heap.read(header.HEADER_SIZE, buffer[0..test_data.len]);
    try testing.expectEqualSlices(u8, test_data, buffer[0..test_data.len]);
}
