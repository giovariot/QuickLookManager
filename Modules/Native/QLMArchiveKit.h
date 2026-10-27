#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface QLMArchiveEntry : NSObject
/// Percorso dentro l'archivio, con `/` come separatore.
@property (nonatomic, copy) NSString *path;
@property (nonatomic) int64_t size;
@property (nonatomic, strong, nullable) NSDate *modified;
@property (nonatomic) BOOL isDirectory;
@property (nonatomic) BOOL isSymlink;
@property (nonatomic) BOOL isEncrypted;
@end

@interface QLMArchiveListing : NSObject
/// Per esempio «ZIP 2.0 (deflate)», «7-Zip», «POSIX pax interchange format».
@property (nonatomic, copy) NSString *format;
/// Compressione esterna (gzip, bzip2, xz…), o «none».
@property (nonatomic, copy) NSString *filter;
@property (nonatomic, strong) NSArray<QLMArchiveEntry *> *entries;
/// Voci totali e dimensione totale non compressa, anche oltre quelle elencate.
@property (nonatomic) NSInteger totalCount;
@property (nonatomic) int64_t totalSize;
@property (nonatomic) BOOL truncated;
@end

@interface QLMArchiveKit : NSObject
/// Elenca il contenuto con libarchive (quella di sistema).
+ (nullable QLMArchiveListing *)listFileAtPath:(NSString *)path
                                     maxEntries:(NSInteger)maxEntries
                                          error:(NSError * _Nullable * _Nullable)error;
/// Come `listFileAtPath`, ma su dati già in memoria (per esempio gli script di un pacchetto, un cpio compresso).
+ (nullable QLMArchiveListing *)listData:(NSData *)data
                              maxEntries:(NSInteger)maxEntries
                                   error:(NSError * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
