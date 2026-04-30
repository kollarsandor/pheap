const std = @import("std");
const header = @import("header.zig");
const pointer = @import("pointer.zig");
const security = @import("security.zig");

const posix = std.posix;

const ReadObjectResult = struct {
    header: header.ObjectHeader,
    data: []const u8,
};

const OpenResult = struct {
    file: std.fs.File,
    needs_init: bool,
    map_size: u64,
};

pub const PersistentHeap = struct {
    base_addr: []align(std.mem.page_size) u8,
    size: u64,
    mapped_size: u64,
    file: std.fs.File,
    file_path: []u8,
    header: *header.HeapHeader,
    pool_uuid: u128,
    security: ?*security.SecurityManager,
    allocator: std.mem.Allocator,
    dirty_pages: []bool,
    dirty_page_count: u64,
    is_dirty: bool,

    const MMAP_PROT: u32 = posix.PROT.READ | posix.PROT.WRITE;
    const MMAP_FLAGS: u32 = posix.MAP.SHARED;

    pub fn init(
        allocator: std.mem.Allocator,
        file_path: []const u8,
        size: u64,
        security_mgr: ?*security.SecurityManager,
    ) !*PersistentHeap {
        const self = try allocator.create(PersistentHeap);
        errdefer allocator.destroy(self);

        const path_copy = try allocator.dupe(u8, file_path);
        errdefer allocator.free(path_copy);

        const requested_size = try normalizeHeapSize(size);
        const open_result = try openOrCreateFile(file_path, requested_size);
        const file = open_result.file;
        var needs_init = open_result.needs_init;
        const mapped_size = open_result.map_size;
        errdefer file.close();

        if (mapped_size < minimumHeapSize()) {
            return error.InvalidHeapSize;
        }

        const base_addr = try mapFile(file.handle, mapped_size);
        errdefer unmapFile(base_addr);

        const heap_header: *header.HeapHeader = @ptrCast(@alignCast(base_addr.ptr));
        var heap_size: u64 = mapped_size;

        if (!needs_init) {
            var header_valid = false;
            if (heap_header.validate()) |_| {
                header_valid = true;
            } else |_| {
                header_valid = false;
            }

            if (header_valid) {
                heap_size = heap_header.heap_size;
                if (heap_size < minimumHeapSize()) {
                    return error.InvalidHeapSize;
                }
                if (heap_size > mapped_size) {
                    return error.InvalidHeapSize;
                }
                if (heap_size % pageSize() != 0) {
                    return error.InvalidHeapSize;
                }
            } else {
                needs_init = true;
            }
        }

        if (needs_init) {
            const mapped_len = try u64ToUsize(mapped_size);
            @memset(base_addr[0..mapped_len], 0);
            heap_header.* = header.HeapHeader.init(mapped_size);
            heap_header.setDirty(false);
            heap_header.updateChecksum();
            try flushRangeRaw(base_addr, heapHeaderSize());
            heap_size = mapped_size;
        }

        const pool_uuid = heap_header.getPoolUUID();
        const page_count = try pageCountForSize(mapped_size);
        const dirty_pages = try allocator.alloc(bool, page_count);
        errdefer allocator.free(dirty_pages);
        @memset(dirty_pages, false);

        self.* = PersistentHeap{
            .base_addr = base_addr,
            .size = heap_size,
            .mapped_size = mapped_size,
            .file = file,
            .file_path = path_copy,
            .header = heap_header,
            .pool_uuid = pool_uuid,
            .security = security_mgr,
            .allocator = allocator,
            .dirty_pages = dirty_pages,
            .dirty_page_count = 0,
            .is_dirty = false,
        };

        return self;
    }

    pub fn deinit(self: *PersistentHeap) !void {
        const alloc = self.allocator;
        defer {
            unmapFile(self.base_addr);
            self.file.close();
            alloc.free(self.dirty_pages);
            alloc.free(self.file_path);
            alloc.destroy(self);
        }

        try self.flush();
    }

    pub fn getSize(self: *const PersistentHeap) u64 {
        return self.size;
    }

    pub fn getUsedSize(self: *const PersistentHeap) u64 {
        return self.header.used_size;
    }

    pub fn getBaseAddress(self: *const PersistentHeap) []u8 {
        return self.base_addr;
    }

    pub fn getPoolUUID(self: *const PersistentHeap) u128 {
        return self.pool_uuid;
    }

    pub fn getRoot(self: *const PersistentHeap) ?pointer.PersistentPtr {
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
        try self.markDirty(0, heapHeaderSize());
        try self.flushRangeAt(0, heapHeaderSize());
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

        const addr = try ptrAt(self.base_addr, ptr.offset);
        const byte_ptr: *u8 = &addr[0];
        return @ptrCast(byte_ptr);
    }

    pub fn getNativePtr(
        self: *const PersistentHeap,
        comptime T: type,
        ptr: pointer.PersistentPtr,
    ) !?*T {
        if (@alignOf(T) > 1) {
            const required_alignment: u64 = @intCast(@alignOf(T));
            if (ptr.offset % required_alignment != 0) {
                return error.InvalidAlignment;
            }
        }

        const raw = try self.resolvePtr(ptr);
        if (raw) |r| {
            const typed: *T = @ptrCast(@alignCast(r));
            return typed;
        }
        return null;
    }

    pub fn allocate(
        self: *PersistentHeap,
        tx: anytype,
        size: u64,
        alignment: u64,
    ) !pointer.PersistentPtr {
        _ = tx;

        if (size == 0) {
            return error.InvalidSize;
        }

        const minimum_offset = try alignTo(minimumHeapSize(), alignment);
        const current_used = @max(self.header.used_size, minimum_offset);
        const aligned_offset = try alignTo(current_used, alignment);
        const end_offset = try checkedAddU64(aligned_offset, size);

        if (end_offset > self.size) {
            return error.OutOfMemory;
        }

        self.header.used_size = end_offset;
        self.header.updateChecksum();
        try self.markDirty(0, heapHeaderSize());

        return pointer.PersistentPtr{
            .pool_uuid = self.pool_uuid,
            .offset = aligned_offset,
        };
    }

    pub fn deallocate(
        self: *PersistentHeap,
        tx: anytype,
        ptr: pointer.PersistentPtr,
    ) !void {
        _ = tx;

        if (ptr.isNull()) {
            return;
        }

        if (ptr.pool_uuid != self.pool_uuid) {
            return error.UUIDMismatch;
        }

        if (ptr.offset >= self.size) {
            return error.OutOfBounds;
        }

        _ = self;
    }

    pub fn write(self: *PersistentHeap, offset: u64, data: []const u8) !void {
        const len = try usizeToU64(data.len);
        try checkRange(self.size, offset, len);

        if (data.len == 0) {
            return;
        }

        const dest = try ptrAt(self.base_addr, offset);
        @memcpy(dest[0..data.len], data);

        try self.markDirty(offset, len);
    }

    pub fn read(self: *const PersistentHeap, offset: u64, buffer: []u8) !void {
        const len = try usizeToU64(buffer.len);
        try checkRange(self.size, offset, len);

        if (buffer.len == 0) {
            return;
        }

        const src = try constPtrAt(self.base_addr, offset);
        @memcpy(buffer, src[0..buffer.len]);
    }

    pub fn writeObject(
        self: *PersistentHeap,
        offset: u64,
        obj_header: *const header.ObjectHeader,
        data: []const u8,
    ) !void {
        const object_header_len = objectHeaderSize();
        const data_len = try usizeToU64(data.len);
        const header_data_len: u64 = @intCast(obj_header.size);

        if (header_data_len != data_len) {
            return error.SizeMismatch;
        }

        const total_size = try checkedAddU64(object_header_len, data_len);
        try checkRange(self.size, offset, total_size);

        const header_dest = try ptrAt(self.base_addr, offset);
        const header_bytes = std.mem.asBytes(obj_header);
        @memcpy(header_dest[0..@sizeOf(header.ObjectHeader)], header_bytes[0..]);

        const data_offset = try checkedAddU64(offset, object_header_len);
        if (data.len > 0) {
            const data_dest = try ptrAt(self.base_addr, data_offset);
            @memcpy(data_dest[0..data.len], data);
        }

        try self.markDirty(offset, total_size);
    }

    pub fn readObject(self: *const PersistentHeap, offset: u64) !?ReadObjectResult {
        const object_header_len = objectHeaderSize();

        if (offset > self.size or object_header_len > self.size - offset) {
            return null;
        }

        const header_src = try constPtrAt(self.base_addr, offset);
        var obj_header: header.ObjectHeader = undefined;
        const header_bytes = std.mem.asBytes(&obj_header);
        @memcpy(header_bytes[0..@sizeOf(header.ObjectHeader)], header_src[0..@sizeOf(header.ObjectHeader)]);

        try obj_header.validate();

        if (obj_header.isFreed()) {
            return null;
        }

        const data_offset = try checkedAddU64(offset, object_header_len);
        const data_size: u64 = @intCast(obj_header.size);

        try checkRange(self.size, data_offset, data_size);

        const data_len = try u64ToUsize(data_size);
        const data_ptr = try constPtrAt(self.base_addr, data_offset);
        const data = data_ptr[0..data_len];

        return .{
            .header = obj_header,
            .data = data,
        };
    }

    pub fn markDirty(self: *PersistentHeap, offset: u64, len: u64) !void {
        if (len == 0) {
            return;
        }

        if (offset >= self.size) {
            return;
        }

        const clamped_len = @min(len, self.size - offset);
        if (clamped_len == 0) {
            return;
        }

        const ps = pageSize();
        const start_page = offset / ps;
        const last_byte = try checkedAddU64(offset, clamped_len - 1);
        const end_page = last_byte / ps;

        const start_page_usize = try u64ToUsize(start_page);
        const end_page_usize = try u64ToUsize(end_page);

        var i = start_page_usize;
        while (i <= end_page_usize and i < self.dirty_pages.len) : (i += 1) {
            if (!self.dirty_pages[i]) {
                self.dirty_pages[i] = true;
                self.dirty_page_count = try checkedAddU64(self.dirty_page_count, 1);
            }
        }

        self.is_dirty = true;
    }

    pub fn flush(self: *PersistentHeap) !void {
        if (!self.is_dirty and self.dirty_page_count == 0) {
            return;
        }

        self.header.setDirty(false);
        self.header.updateChecksum();
        try self.markDirty(0, heapHeaderSize());

        try self.flushDirtyPages();

        self.is_dirty = false;
        @memset(self.dirty_pages, false);
        self.dirty_page_count = 0;
    }

    pub fn flushRange(self: *PersistentHeap, len: u64) !void {
        try self.flushRangeAt(0, len);
    }

    fn flushRangeAt(self: *PersistentHeap, offset: u64, len: u64) !void {
        if (len == 0) {
            return;
        }

        if (offset >= self.size) {
            return;
        }

        const clamped = @min(len, self.size - offset);
        if (clamped == 0) {
            return;
        }

        const addr = try ptrAt(self.base_addr, offset);
        try flushRangeRaw(addr, clamped);
    }

    fn flushDirtyPages(self: *PersistentHeap) !void {
        const ps = pageSize();
        var i: usize = 0;
        while (i < self.dirty_pages.len) {
            while (i < self.dirty_pages.len and !self.dirty_pages[i]) : (i += 1) {}

            if (i >= self.dirty_pages.len) {
                break;
            }

            const start_page = i;

            while (i < self.dirty_pages.len and self.dirty_pages[i]) : (i += 1) {}

            const start_offset = try checkedMulU64(try usizeToU64(start_page), ps);
            const end_page_offset = try checkedMulU64(try usizeToU64(i), ps);
            const end_offset = @min(end_page_offset, self.size);

            if (end_offset > start_offset) {
                try self.flushRangeAt(start_offset, end_offset - start_offset);
            }
        }
    }

    pub fn sync(self: *PersistentHeap) !void {
        try self.flush();
        try posix.fsync(self.file.handle);
    }

    pub fn expand(self: *PersistentHeap, new_size: u64) !void {
        if (new_size <= self.size) {
            return;
        }

        const aligned_new_size = try normalizeHeapSize(new_size);

        if (aligned_new_size <= self.size) {
            return;
        }

        const old_size = self.size;
        try self.flush();
        try self.file.setEndPos(aligned_new_size);
        errdefer self.file.setEndPos(old_size) catch {};

        const new_page_count = try pageCountForSize(aligned_new_size);
        const new_dirty_pages = try self.allocator.alloc(bool, new_page_count);
        errdefer self.allocator.free(new_dirty_pages);
        @memset(new_dirty_pages, false);

        const old_base = self.base_addr;
        const old_mapped_size = self.mapped_size;
        const old_dirty_pages = self.dirty_pages;

        const new_base = try mapFile(self.file.handle, aligned_new_size);

        self.base_addr = new_base;
        self.mapped_size = aligned_new_size;
        self.header = @ptrCast(@alignCast(new_base.ptr));
        self.size = aligned_new_size;
        self.header.heap_size = aligned_new_size;
        self.header.updateChecksum();
        self.dirty_pages = new_dirty_pages;
        self.dirty_page_count = 0;
        self.is_dirty = false;

        unmapFile(old_base);
        self.allocator.free(old_dirty_pages);
        try self.markDirty(0, heapHeaderSize());
    }

    pub fn getDirtyPages(self: *const PersistentHeap, allocator: std.mem.Allocator) ![]bool {
        const copy = try allocator.alloc(bool, self.dirty_pages.len);
        @memcpy(copy, self.dirty_pages);
        return copy;
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
        const ov = @addWithOverflow(self.header.transaction_id, 1);
        if (ov[1] != 0) return error.TransactionIdOverflow;
        self.header.transaction_id = ov[0];
        self.header.setDirty(true);
        self.header.updateChecksum();
        try self.markDirty(0, heapHeaderSize());
        try self.flushRangeAt(0, heapHeaderSize());
    }

    pub fn endTransaction(self: *PersistentHeap) !void {
        self.header.setDirty(false);
        self.header.updateChecksum();
        try self.markDirty(0, heapHeaderSize());
        try self.flushRangeAt(0, heapHeaderSize());
        try self.sync();
    }

    pub fn getTransactionId(self: *const PersistentHeap) u64 {
        return self.header.transaction_id;
    }
};

fn checkedAddU64(a: u64, b: u64) !u64 {
    const ov = @addWithOverflow(a, b);
    if (ov[1] != 0) return error.IntegerOverflow;
    return ov[0];
}

fn checkedMulU64(a: u64, b: u64) !u64 {
    const ov = @mulWithOverflow(a, b);
    if (ov[1] != 0) return error.IntegerOverflow;
    return ov[0];
}

fn isPowerOfTwo(value: u64) bool {
    return value != 0 and (value & (value - 1)) == 0;
}

fn alignTo(value: u64, alignment: u64) !u64 {
    if (!isPowerOfTwo(alignment)) {
        return error.InvalidAlignment;
    }

    const mask = alignment - 1;
    const added = try checkedAddU64(value, mask);
    return added & ~mask;
}

fn alignToPageSize(value: u64) !u64 {
    return alignTo(value, pageSize());
}

fn pageSize() u64 {
    return @intCast(std.mem.page_size);
}

fn heapHeaderSize() u64 {
    return @intCast(@sizeOf(header.HeapHeader));
}

fn objectHeaderSize() u64 {
    return @intCast(@sizeOf(header.ObjectHeader));
}

fn declaredHeaderSize() u64 {
    return @intCast(header.HEADER_SIZE);
}

fn minimumHeapSize() u64 {
    return @max(heapHeaderSize(), declaredHeaderSize());
}

fn normalizeHeapSize(size: u64) !u64 {
    return alignToPageSize(@max(size, minimumHeapSize()));
}

fn pageCountForSize(size: u64) !usize {
    const aligned_size = try alignToPageSize(size);
    return u64ToUsize(aligned_size / pageSize());
}

fn u64ToUsize(value: u64) !usize {
    if (@bitSizeOf(usize) < 64) {
        if (value > std.math.maxInt(usize)) {
            return error.ValueTooLarge;
        }
    }
    return @intCast(value);
}

fn usizeToU64(value: usize) !u64 {
    if (@bitSizeOf(usize) > 64) {
        if (value > std.math.maxInt(u64)) {
            return error.ValueTooLarge;
        }
    }
    return @intCast(value);
}

fn checkRange(total: u64, offset: u64, len: u64) !void {
    if (offset > total) {
        return error.OutOfBounds;
    }

    if (len > total - offset) {
        return error.OutOfBounds;
    }
}

fn ptrAt(base_addr: []align(std.mem.page_size) u8, offset: u64) ![]u8 {
    const index = try u64ToUsize(offset);
    if (index > base_addr.len) {
        return error.OutOfBounds;
    }
    return base_addr[index..];
}

fn constPtrAt(base_addr: []align(std.mem.page_size) u8, offset: u64) ![]const u8 {
    const index = try u64ToUsize(offset);
    if (index > base_addr.len) {
        return error.OutOfBounds;
    }
    return base_addr[index..];
}

fn openOrCreateFile(path: []const u8, size: u64) !OpenResult {
    if (std.fs.cwd().openFile(path, .{ .mode = .read_write })) |existing| {
        errdefer existing.close();

        const stat = try existing.stat();
        const target_size = try normalizeHeapSize(@max(stat.size, size));

        if (stat.size != target_size) {
            try existing.setEndPos(target_size);
        }

        return .{
            .file = existing,
            .needs_init = stat.size == 0,
            .map_size = target_size,
        };
    } else |err| switch (err) {
        error.FileNotFound => {
            const file = try std.fs.cwd().createFile(path, .{ .read = true, .truncate = false });
            errdefer file.close();

            const target_size = try normalizeHeapSize(size);
            try file.setEndPos(target_size);

            return .{
                .file = file,
                .needs_init = true,
                .map_size = target_size,
            };
        },
        else => return err,
    }
}

fn mapFile(fd: posix.fd_t, size: u64) ![]align(std.mem.page_size) u8 {
    const len = try u64ToUsize(size);

    if (len == 0) {
        return error.InvalidHeapSize;
    }

    const slice = try posix.mmap(
        null,
        len,
        PersistentHeap.MMAP_PROT,
        PersistentHeap.MMAP_FLAGS,
        fd,
        0,
    );
    return slice;
}

fn unmapFile(base_addr: []align(std.mem.page_size) u8) void {
    if (base_addr.len == 0) {
        return;
    }

    posix.munmap(base_addr);
}

fn flushRangeRaw(base_addr: []u8, len: u64) !void {
    if (len == 0) {
        return;
    }

    const ps = std.mem.page_size;
    const addr_int = @intFromPtr(base_addr.ptr);
    const page_aligned = addr_int & ~(@as(usize, ps) - 1);
    const offset_into_page = addr_int - page_aligned;
    const len_usize = try u64ToUsize(len);

    const ov = @addWithOverflow(len_usize, offset_into_page);
    if (ov[1] != 0) return error.IntegerOverflow;
    const total_len = ov[0];

    const aligned_len = try alignForwardUsize(total_len, ps);

    const aligned_ptr: [*]align(std.mem.page_size) u8 = @ptrFromInt(page_aligned);
    try posix.msync(aligned_ptr[0..aligned_len], posix.MS.SYNC);
}

fn alignForwardUsize(value: usize, alignment: usize) !usize {
    if (alignment == 0 or (alignment & (alignment - 1)) != 0) {
        return error.InvalidAlignment;
    }

    const mask = alignment - 1;
    const ov = @addWithOverflow(value, mask);
    if (ov[1] != 0) return error.IntegerOverflow;
    return ov[0] & ~mask;
}

test "heap initialization" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const test_path = "test_heap_init.dat";
    std.fs.cwd().deleteFile(test_path) catch {};
    defer std.fs.cwd().deleteFile(test_path) catch {};

    const heap = try PersistentHeap.init(alloc, test_path, 1024 * 1024, null);
    try testing.expect(heap.size >= 1024 * 1024);
    try testing.expect(heap.pool_uuid != 0);
    try heap.deinit();
}

test "heap allocation" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const test_path = "test_heap_alloc.dat";
    std.fs.cwd().deleteFile(test_path) catch {};
    defer std.fs.cwd().deleteFile(test_path) catch {};

    const heap = try PersistentHeap.init(alloc, test_path, 1024 * 1024, null);
    const ptr = try heap.allocate({}, 256, 64);
    try testing.expect(!ptr.isNull());
    try testing.expect(ptr.offset >= declaredHeaderSize());
    try heap.deinit();
}

test "heap read/write" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const test_path = "test_heap_rw.dat";
    std.fs.cwd().deleteFile(test_path) catch {};
    defer std.fs.cwd().deleteFile(test_path) catch {};

    const heap = try PersistentHeap.init(alloc, test_path, 1024 * 1024, null);

    const test_data: []const u8 = "Hello, Persistent World!";
    const test_offset = declaredHeaderSize();
    try heap.write(test_offset, test_data);

    var buffer: [32]u8 = undefined;
    try heap.read(test_offset, buffer[0..test_data.len]);
    try testing.expectEqualSlices(u8, test_data, buffer[0..test_data.len]);

    try heap.deinit();
}
