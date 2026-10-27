#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// Lettore di file audio e video basato su ffmpeg: legge il contenitore, decodifica (con VideoToolbox quando può)
/// e restituisce `CMSampleBuffer` pronti per `AVSampleBufferDisplayLayer` e `AVSampleBufferAudioRenderer`.
///
/// Un thread interno legge i pacchetti e li mette in due code limitate; le due funzioni `copyNext…` si chiamano
/// da due thread diversi (uno per il video, uno per l'audio) e bloccano finché c'è qualcosa da decodificare.
@interface QLMMediaReader : NSObject

+ (nullable instancetype)readerWithPath:(NSString *)path error:(NSError * _Nullable * _Nullable)error;

/// Durata in secondi, 0 se ignota.
@property (nonatomic, readonly) double duration;
@property (nonatomic, readonly) BOOL hasVideo;
@property (nonatomic, readonly) BOOL hasAudio;
/// Dimensioni da mostrare (tiene conto del rapporto dei pixel).
@property (nonatomic, readonly) CGSize displaySize;
@property (nonatomic, readonly, copy, nullable) NSString *videoCodec;
@property (nonatomic, readonly, copy, nullable) NSString *audioCodec;
@property (nonatomic, readonly, copy, nullable) NSString *title;
/// `YES` se il video è decodificato da VideoToolbox.
@property (nonatomic, readonly) BOOL usesHardwareDecoding;

/// Avvia il thread di lettura. Da chiamare una volta, prima di leggere campioni.
- (void)start;
/// Il prossimo fotogramma, o NULL a fine file (o dopo `stop`). Blocca.
- (nullable CMSampleBufferRef)copyNextVideoSample CF_RETURNS_RETAINED;
/// Il prossimo blocco di audio PCM float 32 bit, stereo a 48 kHz, o NULL a fine file. Blocca.
- (nullable CMSampleBufferRef)copyNextAudioSample CF_RETURNS_RETAINED;
/// Si sposta in avanti o indietro. I campioni già letti vanno scartati dal chiamante; quelli nuovi partono dal punto richiesto.
- (void)seekToTime:(double)seconds;
/// Ferma tutto e sblocca chi sta aspettando. Dopo non si può riusare il lettore.
- (void)stop;

/// Una miniatura: il primo fotogramma dopo `fraction` (0…1) della durata, ridotto a stare in `maxSize` pixel.
+ (nullable CGImageRef)copyThumbnailForPath:(NSString *)path fraction:(double)fraction maxSize:(int)maxSize CF_RETURNS_RETAINED;

@end

NS_ASSUME_NONNULL_END
