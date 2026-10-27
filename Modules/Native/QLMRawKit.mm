#import "QLMRawKit.h"
#include <libraw/libraw.h>
#include <memory>

@implementation QLMRawResult
@end

static NSString *const QLMRawErrorDomain = @"QLMRawKit";

static NSString *str(const char *s) {
    if (!s || !s[0]) return nil;
    return [NSString stringWithUTF8String:s] ?: [[NSString alloc] initWithBytes:s length:strlen(s) encoding:NSISOLatin1StringEncoding];
}

/// Valore EXIF di orientamento a partire dal «flip» di LibRaw (0 = normale, 3 = 180°, 5 = 90° antiorario, 6 = 90° orario).
static NSInteger exifOrientation(int flip) {
    switch (flip) {
        case 3: return 3;
        case 5: return 8;
        case 6: return 6;
        default: return 1;
    }
}

@implementation QLMRawKit

+ (NSString *)libRawVersion { return @(LibRaw::version()); }

+ (NSError *)fail:(NSString *)what code:(int)code {
    return [NSError errorWithDomain:QLMRawErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: what}];
}

+ (QLMRawResult *)readFileAtPath:(NSString *)path renderIfMissing:(BOOL)render error:(NSError **)error {
    auto raw = std::make_unique<LibRaw>();
    int rc = raw->open_file(path.fileSystemRepresentation);
    if (rc != LIBRAW_SUCCESS) {
        if (error) *error = [self fail:[NSString stringWithFormat:@"LibRaw: %s", libraw_strerror(rc)] code:rc];
        return nil;
    }

    QLMRawResult *r = [QLMRawResult new];
    r.make = str(raw->imgdata.idata.make);
    r.model = str(raw->imgdata.idata.model);
    NSString *lens = str(raw->imgdata.lens.Lens);
    if (!lens) lens = str(raw->imgdata.lens.makernotes.Lens);
    r.lens = lens;
    r.iso = raw->imgdata.other.iso_speed;
    r.shutter = raw->imgdata.other.shutter;
    r.aperture = raw->imgdata.other.aperture;
    r.focalLength = raw->imgdata.other.focal_len;
    if (raw->imgdata.other.timestamp > 0) r.date = [NSDate dateWithTimeIntervalSince1970:raw->imgdata.other.timestamp];
    r.rawWidth = raw->imgdata.sizes.raw_width;
    r.rawHeight = raw->imgdata.sizes.raw_height;
    int flip = raw->imgdata.sizes.flip;

    // La più grande fra le anteprime incorporate.
    int best = -1;
    unsigned long bestArea = 0;
    const libraw_thumbnail_list_t &list = raw->imgdata.thumbs_list;
    for (int i = 0; i < list.thumbcount; i++) {
        const libraw_thumbnail_item_t &t = list.thumblist[i];
        if (t.tformat != LIBRAW_INTERNAL_THUMBNAIL_JPEG && t.tformat != LIBRAW_INTERNAL_THUMBNAIL_PPM) continue;
        unsigned long area = (unsigned long)t.twidth * t.theight;
        if (area == 0) area = t.tlength; // dimensioni ignote: vale la dimensione del file
        if (area > bestArea) { bestArea = area; best = i; }
    }
    if (best >= 0 && raw->unpack_thumb_ex(best) == LIBRAW_SUCCESS) {
        libraw_thumbnail_t &t = raw->imgdata.thumbnail;
        if (t.tformat == LIBRAW_THUMBNAIL_JPEG && t.thumb && t.tlength > 0) {
            r.imageData = [NSData dataWithBytes:t.thumb length:t.tlength];
            r.isJPEG = YES;
            r.width = t.twidth; r.height = t.theight;
            r.orientation = 0; // lo dice l'EXIF del JPEG; se manca, ci pensa il chiamante con `fallbackOrientation`
            r.orientation = exifOrientation(flip);
            return r;
        }
        if (t.tformat == LIBRAW_THUMBNAIL_BITMAP && t.thumb && t.tcolors == 3) {
            r.imageData = [NSData dataWithBytes:t.thumb length:(NSUInteger)t.twidth * t.theight * 3];
            r.isJPEG = NO;
            r.width = t.twidth; r.height = t.theight;
            r.orientation = exifOrientation(flip);
            return r;
        }
    }

    if (!render) {
        if (error) *error = [self fail:@"Nessuna anteprima incorporata nel file." code:1];
        return nil;
    }
    // Niente anteprima: si sviluppa il RAW a mezza risoluzione.
    raw->imgdata.params.half_size = 1;
    raw->imgdata.params.output_bps = 8;
    raw->imgdata.params.use_camera_wb = 1;
    raw->imgdata.params.user_flip = 0; // l'orientamento lo applica il chiamante
    rc = raw->unpack();
    if (rc == LIBRAW_SUCCESS) rc = raw->dcraw_process();
    if (rc != LIBRAW_SUCCESS) {
        if (error) *error = [self fail:[NSString stringWithFormat:@"LibRaw: %s", libraw_strerror(rc)] code:rc];
        return nil;
    }
    libraw_processed_image_t *img = raw->dcraw_make_mem_image(&rc);
    if (!img || img->type != LIBRAW_IMAGE_BITMAP || img->colors != 3 || img->bits != 8) {
        if (img) LibRaw::dcraw_clear_mem(img);
        if (error) *error = [self fail:@"Sviluppo del RAW non riuscito." code:rc ?: 2];
        return nil;
    }
    r.imageData = [NSData dataWithBytes:img->data length:img->data_size];
    r.isJPEG = NO;
    r.width = img->width; r.height = img->height;
    r.orientation = exifOrientation(flip);
    r.wasRendered = YES;
    LibRaw::dcraw_clear_mem(img);
    return r;
}

@end
