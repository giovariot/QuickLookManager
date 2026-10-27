#import "QLMArchiveKit.h"
#include <archive.h>
#include <archive_entry.h>

@implementation QLMArchiveEntry
@end

@implementation QLMArchiveListing
@end

@implementation QLMArchiveKit

+ (QLMArchiveListing *)listFileAtPath:(NSString *)path maxEntries:(NSInteger)maxEntries error:(NSError **)error {
    struct archive *a = archive_read_new();
    archive_read_support_filter_all(a);
    archive_read_support_format_all(a);
    archive_read_support_format_raw(a); // un .gz o .xz solo: una voce
    return [self listArchive:a open:archive_read_open_filename(a, path.fileSystemRepresentation, 65536) maxEntries:maxEntries error:error];
}

+ (QLMArchiveListing *)listData:(NSData *)data maxEntries:(NSInteger)maxEntries error:(NSError **)error {
    struct archive *a = archive_read_new();
    archive_read_support_filter_all(a);
    archive_read_support_format_all(a);
    int rc = archive_read_open_memory(a, data.bytes, data.length);
    return [self listArchive:a open:rc maxEntries:maxEntries error:error];
}

/// Il giro vero: legge le intestazioni di un archivio già aperto (`open` è l'esito dell'apertura) e libera `a`.
+ (QLMArchiveListing *)listArchive:(struct archive *)a open:(int)open maxEntries:(NSInteger)maxEntries error:(NSError **)error {
    if (open != ARCHIVE_OK) {
        if (error) {
            const char *msg = archive_error_string(a);
            *error = [NSError errorWithDomain:@"QLMArchiveKit" code:archive_errno(a)
                                     userInfo:@{NSLocalizedDescriptionKey: msg ? @(msg) : @"Archivio non leggibile."}];
        }
        archive_read_free(a);
        return nil;
    }

    QLMArchiveListing *listing = [QLMArchiveListing new];
    NSMutableArray<QLMArchiveEntry *> *entries = [NSMutableArray array];
    struct archive_entry *e;
    int r;
    BOOL first = YES;
    while ((r = archive_read_next_header(a, &e)) == ARCHIVE_OK || r == ARCHIVE_WARN) {
        if (first) {
            listing.format = @(archive_format_name(a) ?: "?");
            const char *filter = archive_filter_name(a, 0);
            listing.filter = @(filter ?: "none");
            first = NO;
        }
        listing.totalCount++;
        int64_t size = archive_entry_size_is_set(e) ? archive_entry_size(e) : 0;
        BOOL isDir = archive_entry_filetype(e) == AE_IFDIR;
        if (!isDir) listing.totalSize += size;
        if ((NSInteger)entries.count < maxEntries) {
            QLMArchiveEntry *item = [QLMArchiveEntry new];
            const char *name = archive_entry_pathname(e);
            item.path = name ? (@(name) ?: [[NSString alloc] initWithBytes:name length:strlen(name) encoding:NSISOLatin1StringEncoding]) : @"?";
            item.size = size;
            item.isDirectory = isDir;
            item.isSymlink = archive_entry_filetype(e) == AE_IFLNK;
            item.isEncrypted = archive_entry_is_encrypted(e) != 0;
            if (archive_entry_mtime_is_set(e)) item.modified = [NSDate dateWithTimeIntervalSince1970:archive_entry_mtime(e)];
            [entries addObject:item];
        } else {
            listing.truncated = YES;
        }
        archive_read_data_skip(a);
    }
    if (r != ARCHIVE_EOF && listing.totalCount == 0) {
        if (error) {
            const char *msg = archive_error_string(a);
            *error = [NSError errorWithDomain:@"QLMArchiveKit" code:archive_errno(a)
                                     userInfo:@{NSLocalizedDescriptionKey: msg ? @(msg) : @"Archivio non leggibile."}];
        }
        archive_read_free(a);
        return nil;
    }
    if (first) { listing.format = @"?"; listing.filter = @"none"; }
    listing.entries = entries;
    archive_read_free(a);
    return listing;
}

@end
