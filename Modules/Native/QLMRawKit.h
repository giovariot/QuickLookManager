#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Cosa LibRaw ha trovato in una foto RAW: l'immagine (incorporata, o ricostruita) e i dati di scatto.
@interface QLMRawResult : NSObject
/// JPEG incorporato (`isJPEG`) oppure pixel RGB a 8 bit (`width` × `height` × 3).
@property (nonatomic, strong) NSData *imageData;
@property (nonatomic) BOOL isJPEG;
@property (nonatomic) NSInteger width;
@property (nonatomic) NSInteger height;
/// Orientamento secondo i valori EXIF (1…8); 0 se ignoto.
@property (nonatomic) NSInteger orientation;
/// `YES` se l'immagine non era incorporata nel file ma è stata sviluppata a mezza risoluzione.
@property (nonatomic) BOOL wasRendered;

@property (nonatomic, copy, nullable) NSString *make;
@property (nonatomic, copy, nullable) NSString *model;
@property (nonatomic, copy, nullable) NSString *lens;
@property (nonatomic) float iso;
@property (nonatomic) float shutter;   // secondi
@property (nonatomic) float aperture;  // f/
@property (nonatomic) float focalLength; // mm
@property (nonatomic, strong, nullable) NSDate *date;
@property (nonatomic) NSInteger rawWidth;
@property (nonatomic) NSInteger rawHeight;
@end

@interface QLMRawKit : NSObject
/// Legge il file con LibRaw. Se `render` è `NO` e non c'è un'immagine incorporata, fallisce.
+ (nullable QLMRawResult *)readFileAtPath:(NSString *)path
                         renderIfMissing:(BOOL)render
                                   error:(NSError * _Nullable * _Nullable)error;
+ (NSString *)libRawVersion;
@end

NS_ASSUME_NONNULL_END
