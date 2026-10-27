#import "QLMMediaKit.h"
#import <CoreVideo/CoreVideo.h>
#import <CoreImage/CoreImage.h>
#import <os/log.h>
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <libavutil/imgutils.h>
#include <libavutil/hwcontext.h>
#include <libavutil/channel_layout.h>
#include <libavutil/opt.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>

// Parti di QuickLook Manager; l'idea di decodificare con ffmpeg e VideoToolbox viene da QLVideo di Jonathan Harris (GPL 2+).

static NSString *const QLMMediaErrorDomain = @"QLMMediaKit";
static const int kAudioRate = 48000;
static const NSUInteger kMaxVideoPackets = 160;
static const NSUInteger kMaxAudioPackets = 400;

/// Un pacchetto in coda, con il numero di «generazione» del momento in cui è stato letto: dopo un salto tutti
/// quelli vecchi sono da buttare.
@interface QLMPacket : NSObject {
@public
    AVPacket *pkt;
    int generation;
}
@end
@implementation QLMPacket
- (void)dealloc { if (pkt) av_packet_free(&pkt); }
@end

static void QLMAVLog(void *avcl, int level, const char *fmt, va_list vl) {
    if (level > AV_LOG_WARNING) return;
    char line[512];
    vsnprintf(line, sizeof line, fmt, vl);
    static os_log_t log; static dispatch_once_t once;
    dispatch_once(&once, ^{ log = os_log_create("com.giovariot.QuickLookManager", "ffmpeg"); });
    os_log(log, "%{public}s", line);
}

static NSError *QLMError(NSString *what, int averr) {
    char buf[128] = "";
    if (averr < 0) av_strerror(averr, buf, sizeof buf);
    NSString *text = averr < 0 ? [NSString stringWithFormat:@"%@ (%s)", what, buf] : what;
    return [NSError errorWithDomain:QLMMediaErrorDomain code:averr userInfo:@{NSLocalizedDescriptionKey: text}];
}

static enum AVPixelFormat QLMPickFormat(AVCodecContext *ctx, const enum AVPixelFormat *fmts) {
    for (const enum AVPixelFormat *p = fmts; *p != AV_PIX_FMT_NONE; p++) {
        if (*p == AV_PIX_FMT_VIDEOTOOLBOX) return *p;
    }
    return fmts[0];
}

static int QLMSwsColorspace(const AVFrame *f) {
    switch (f->colorspace) {
        case AVCOL_SPC_BT709: return SWS_CS_ITU709;
        case AVCOL_SPC_BT470BG:
        case AVCOL_SPC_SMPTE170M: return SWS_CS_ITU601;
        case AVCOL_SPC_SMPTE240M: return SWS_CS_SMPTE240M;
        case AVCOL_SPC_BT2020_NCL:
        case AVCOL_SPC_BT2020_CL: return SWS_CS_BT2020;
        default: return f->height >= 720 ? SWS_CS_ITU709 : SWS_CS_ITU601;
    }
}

/// Converte un fotogramma software in un CVPixelBuffer BGRA. `ctx` è la cache di swscale, tenuta da chi chiama.
static CVPixelBufferRef QLMBGRAFromFrame(const AVFrame *frame, struct SwsContext **ctx, int outW, int outH) {
    *ctx = sws_getCachedContext(*ctx, frame->width, frame->height, (enum AVPixelFormat)frame->format,
                                outW, outH, AV_PIX_FMT_BGRA, SWS_BILINEAR, NULL, NULL, NULL);
    if (!*ctx) return NULL;
    const int *coef = sws_getCoefficients(QLMSwsColorspace(frame));
    sws_setColorspaceDetails(*ctx, coef, frame->color_range == AVCOL_RANGE_JPEG, sws_getCoefficients(SWS_CS_DEFAULT), 1, 0, 1 << 16, 1 << 16);
    CVPixelBufferRef pb = NULL;
    NSDictionary *attrs = @{(id)kCVPixelBufferIOSurfacePropertiesKey: @{}, (id)kCVPixelBufferMetalCompatibilityKey: @YES};
    if (CVPixelBufferCreate(kCFAllocatorDefault, outW, outH, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)attrs, &pb) != kCVReturnSuccess) return NULL;
    CVPixelBufferLockBaseAddress(pb, 0);
    uint8_t *dst[4] = { CVPixelBufferGetBaseAddress(pb), NULL, NULL, NULL };
    int dstStride[4] = { (int)CVPixelBufferGetBytesPerRow(pb), 0, 0, 0 };
    sws_scale(*ctx, (const uint8_t *const *)frame->data, frame->linesize, 0, frame->height, dst, dstStride);
    CVPixelBufferUnlockBaseAddress(pb, 0);
    return pb;
}

@implementation QLMMediaReader {
    AVFormatContext *_fmt;
    int _vIndex, _aIndex;
    AVCodecContext *_vctx, *_actx;
    AVRational _vTimeBase, _aTimeBase;
    struct SwsContext *_sws;
    struct SwrContext *_swr;
    AVFrame *_vframe, *_aframe;
    AVRational _sar;
    CMVideoFormatDescriptionRef _vdesc;
    CMAudioFormatDescriptionRef _adesc;
    BOOL _hardware, _hwRequested;

    NSThread *_demuxThread;
    NSCondition *_cond;
    NSMutableArray<QLMPacket *> *_vq, *_aq;
    BOOL _stopping, _vEOF, _aEOF, _started;
    int _generation;                 // sale a ogni salto
    BOOL _seekPending;
    double _seekTarget;              // secondi
    double _discardBefore;           // i fotogrammi con PTS minore (dopo un salto) si scartano
    int _vGeneration, _aGeneration;  // l'ultima generazione vista da ciascun decodificatore
    double _duration;
    CGSize _displaySize;
    NSString *_videoCodec, *_audioCodec, *_title;
}

@synthesize duration = _duration, displaySize = _displaySize, videoCodec = _videoCodec, audioCodec = _audioCodec, title = _title;
- (BOOL)hasVideo { return _vctx != NULL; }
- (BOOL)hasAudio { return _actx != NULL; }
- (BOOL)usesHardwareDecoding { return _hardware; }

// MARK: Apertura

+ (instancetype)readerWithPath:(NSString *)path error:(NSError **)error {
    av_log_set_callback(QLMAVLog);
    QLMMediaReader *r = [[QLMMediaReader alloc] init];
    NSError *err = [r openPath:path];
    if (err) { if (error) *error = err; return nil; }
    return r;
}

- (nullable NSError *)openPath:(NSString *)path {
    _cond = [[NSCondition alloc] init];
    _vq = [NSMutableArray array];
    _aq = [NSMutableArray array];
    _vIndex = _aIndex = -1;

    int rc = avformat_open_input(&_fmt, path.fileSystemRepresentation, NULL, NULL);
    if (rc < 0) return QLMError(@"Il file non si apre", rc);
    rc = avformat_find_stream_info(_fmt, NULL);
    if (rc < 0) return QLMError(@"Il file non si legge", rc);

    _vIndex = av_find_best_stream(_fmt, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
    _aIndex = av_find_best_stream(_fmt, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
    if (_vIndex >= 0 && (_fmt->streams[_vIndex]->disposition & AV_DISPOSITION_ATTACHED_PIC)) _vIndex = -1; // copertina, non filmato
    if (_vIndex < 0 && _aIndex < 0) return QLMError(@"Nessuna traccia audio o video", 0);

    if (_vIndex >= 0) {
        NSError *e = [self openVideoStream];
        if (e) { _vIndex = -1; if (_aIndex < 0) return e; }
    }
    if (_aIndex >= 0) {
        NSError *e = [self openAudioStream];
        if (e) { _aIndex = -1; if (_vIndex < 0) return e; }
    }
    if (_fmt->duration > 0) _duration = (double)_fmt->duration / AV_TIME_BASE;
    AVDictionaryEntry *t = av_dict_get(_fmt->metadata, "title", NULL, 0);
    if (t && t->value[0]) _title = [NSString stringWithUTF8String:t->value];
    return nil;
}

- (nullable NSError *)openVideoStream {
    AVStream *st = _fmt->streams[_vIndex];
    const AVCodec *codec = avcodec_find_decoder(st->codecpar->codec_id);
    if (!codec) return QLMError(@"Codec video non supportato", 0);
    _vctx = avcodec_alloc_context3(codec);
    avcodec_parameters_to_context(_vctx, st->codecpar);
    _vctx->pkt_timebase = st->time_base;
    _vctx->thread_count = 0;
    // VideoToolbox, se il codec lo permette; altrimenti decodifica software.
    for (int i = 0;; i++) {
        const AVCodecHWConfig *cfg = avcodec_get_hw_config(codec, i);
        if (!cfg) break;
        if (cfg->device_type == AV_HWDEVICE_TYPE_VIDEOTOOLBOX && (cfg->methods & AV_CODEC_HW_CONFIG_METHOD_HW_DEVICE_CTX)) {
            AVBufferRef *hw = NULL;
            if (av_hwdevice_ctx_create(&hw, AV_HWDEVICE_TYPE_VIDEOTOOLBOX, NULL, NULL, 0) == 0) {
                _vctx->hw_device_ctx = hw;
                _vctx->get_format = QLMPickFormat;
                _hwRequested = YES;
            }
            break;
        }
    }
    int rc = avcodec_open2(_vctx, codec, NULL);
    if (rc < 0 && _hwRequested) {  // l'hardware non ce l'ha fatta: da capo in software
        avcodec_free_context(&_vctx);
        _hwRequested = NO;
        _vctx = avcodec_alloc_context3(codec);
        avcodec_parameters_to_context(_vctx, st->codecpar);
        _vctx->pkt_timebase = st->time_base;
        _vctx->thread_count = 0;
        rc = avcodec_open2(_vctx, codec, NULL);
    }
    if (rc < 0) { avcodec_free_context(&_vctx); return QLMError(@"Il decodificatore video non parte", rc); }
    _vTimeBase = st->time_base;
    _vframe = av_frame_alloc();
    _sar = av_guess_sample_aspect_ratio(_fmt, st, NULL);
    if (_sar.num <= 0 || _sar.den <= 0) _sar = (AVRational){1, 1};
    _displaySize = CGSizeMake(_vctx->width * (double)_sar.num / _sar.den, _vctx->height);
    _videoCodec = [NSString stringWithUTF8String:codec->name];
    return nil;
}

- (nullable NSError *)openAudioStream {
    AVStream *st = _fmt->streams[_aIndex];
    const AVCodec *codec = avcodec_find_decoder(st->codecpar->codec_id);
    if (!codec) return QLMError(@"Codec audio non supportato", 0);
    _actx = avcodec_alloc_context3(codec);
    avcodec_parameters_to_context(_actx, st->codecpar);
    _actx->pkt_timebase = st->time_base;
    int rc = avcodec_open2(_actx, codec, NULL);
    if (rc < 0) { avcodec_free_context(&_actx); return QLMError(@"Il decodificatore audio non parte", rc); }
    _aTimeBase = st->time_base;
    _aframe = av_frame_alloc();
    _audioCodec = [NSString stringWithUTF8String:codec->name];

    AudioStreamBasicDescription asbd = {0};
    asbd.mSampleRate = kAudioRate;
    asbd.mFormatID = kAudioFormatLinearPCM;
    asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    asbd.mChannelsPerFrame = 2;
    asbd.mBitsPerChannel = 32;
    asbd.mBytesPerFrame = 8;
    asbd.mFramesPerPacket = 1;
    asbd.mBytesPerPacket = 8;
    CMAudioFormatDescriptionCreate(kCFAllocatorDefault, &asbd, 0, NULL, 0, NULL, NULL, &_adesc);
    return nil;
}

- (void)dealloc {
    [self stop];
    if (_sws) sws_freeContext(_sws);
    if (_swr) swr_free(&_swr);
    if (_vframe) av_frame_free(&_vframe);
    if (_aframe) av_frame_free(&_aframe);
    if (_vctx) avcodec_free_context(&_vctx);
    if (_actx) avcodec_free_context(&_actx);
    if (_fmt) avformat_close_input(&_fmt);
    if (_vdesc) CFRelease(_vdesc);
    if (_adesc) CFRelease(_adesc);
}

// MARK: Lettura dei pacchetti

- (void)start {
    [_cond lock];
    if (_started) { [_cond unlock]; return; }
    _started = YES;
    [_cond unlock];
    _demuxThread = [[NSThread alloc] initWithTarget:self selector:@selector(demuxLoop) object:nil];
    _demuxThread.name = @"QLMMediaReader.demux";
    _demuxThread.qualityOfService = NSQualityOfServiceUserInitiated;
    [_demuxThread start];
}

- (void)stop {
    [_cond lock];
    _stopping = YES;
    [_cond broadcast];
    [_cond unlock];
}

- (void)seekToTime:(double)seconds {
    [_cond lock];
    _seekTarget = MAX(0, seconds);
    _seekPending = YES;
    _generation++;
    [_vq removeAllObjects];
    [_aq removeAllObjects];
    _vEOF = _aEOF = NO;
    [_cond broadcast];
    [_cond unlock];
}

- (void)demuxLoop {
    @autoreleasepool {
        AVPacket *pkt = av_packet_alloc();
        for (;;) {
            [_cond lock];
            for (;;) {
                if (_stopping) { [_cond unlock]; av_packet_free(&pkt); return; }
                if (_seekPending) break;
                BOOL vFull = _vIndex < 0 || _vq.count >= kMaxVideoPackets;
                BOOL aFull = _aIndex < 0 || _aq.count >= kMaxAudioPackets;
                BOOL done = (_vEOF || _vIndex < 0) && (_aEOF || _aIndex < 0);
                if (!done && !(vFull && aFull)) break;
                [_cond wait];
            }
            BOOL seeking = _seekPending;
            double target = _seekTarget;
            int generation = _generation;
            if (seeking) _seekPending = NO;
            [_cond unlock];

            if (seeking) {
                int64_t ts = (int64_t)(target * AV_TIME_BASE);
                if (avformat_seek_file(_fmt, -1, INT64_MIN, ts, ts, 0) < 0) av_seek_frame(_fmt, -1, ts, AVSEEK_FLAG_BACKWARD);
                [_cond lock];
                _discardBefore = target;
                [_cond unlock];
            }

            int rc = av_read_frame(_fmt, pkt);
            [_cond lock];
            if (generation != _generation) {   // un altro salto è arrivato mentre si leggeva
                [_cond unlock];
                av_packet_unref(pkt);
                continue;
            }
            if (rc < 0) {
                if (rc == AVERROR_EOF || _fmt->pb->eof_reached) { _vEOF = _aEOF = YES; }
                else { _vEOF = _aEOF = YES; }
                [_cond broadcast];
                [_cond unlock];
                continue;
            }
            if (pkt->stream_index == _vIndex || pkt->stream_index == _aIndex) {
                QLMPacket *box = [[QLMPacket alloc] init];
                box->pkt = av_packet_alloc();
                av_packet_move_ref(box->pkt, pkt);
                box->generation = generation;
                if (box->pkt->stream_index == _vIndex) [_vq addObject:box]; else [_aq addObject:box];
                [_cond broadcast];
            } else {
                av_packet_unref(pkt);
            }
            [_cond unlock];
        }
    }
}

/// Il prossimo pacchetto della coda, o `nil` a fine file / dopo `stop`. `gen` dice a che generazione appartiene.
- (nullable QLMPacket *)nextPacketFromQueue:(NSMutableArray<QLMPacket *> *)q eof:(BOOL *)eofFlag {
    [_cond lock];
    QLMPacket *p = nil;
    for (;;) {
        if (_stopping) break;
        if (q.count > 0) { p = q.firstObject; [q removeObjectAtIndex:0]; [_cond broadcast]; break; }
        if (*eofFlag) break;
        [_cond wait];
    }
    [_cond unlock];
    return p;
}

// MARK: Video

- (CMSampleBufferRef)copyNextVideoSample {
    if (!_vctx) return NULL;
    for (;;) {
        // Il salto è avvenuto: si svuota il decodificatore.
        [_cond lock];
        int gen = _generation;
        double discard = _discardBefore;
        [_cond unlock];
        if (gen != _vGeneration) { avcodec_flush_buffers(_vctx); _vGeneration = gen; }

        int rc = avcodec_receive_frame(_vctx, _vframe);
        if (rc == 0) {
            double pts = _vframe->best_effort_timestamp == AV_NOPTS_VALUE ? 0 : _vframe->best_effort_timestamp * av_q2d(_vTimeBase);
            if (_vGeneration > 0 && pts < discard - 0.001) { av_frame_unref(_vframe); continue; }
            CMSampleBufferRef sb = [self makeVideoSampleFromFrame:_vframe pts:pts];
            av_frame_unref(_vframe);
            if (sb) return sb;
            continue;
        }
        if (rc == AVERROR(EAGAIN)) {
            QLMPacket *p = [self nextPacketFromQueue:_vq eof:&_vEOF];
            if (!p) {
                [_cond lock]; BOOL stopped = _stopping; [_cond unlock];
                if (stopped) return NULL;
                avcodec_send_packet(_vctx, NULL);        // fine file: si svuota il decodificatore
                rc = avcodec_receive_frame(_vctx, _vframe);
                if (rc != 0) return NULL;
                double pts = _vframe->best_effort_timestamp == AV_NOPTS_VALUE ? 0 : _vframe->best_effort_timestamp * av_q2d(_vTimeBase);
                CMSampleBufferRef sb = [self makeVideoSampleFromFrame:_vframe pts:pts];
                av_frame_unref(_vframe);
                if (sb) return sb;
                continue;
            }
            [_cond lock]; int current = _generation; [_cond unlock];
            if (p->generation == current) avcodec_send_packet(_vctx, p->pkt);
            continue;
        }
        if (rc == AVERROR_EOF) return NULL;
        // errore di decodifica di un fotogramma: si va avanti col successivo
        if (rc < 0 && rc != AVERROR(EAGAIN)) {
            QLMPacket *p = [self nextPacketFromQueue:_vq eof:&_vEOF];
            if (!p) return NULL;
            avcodec_send_packet(_vctx, p->pkt);
        }
    }
}

- (CMSampleBufferRef)makeVideoSampleFromFrame:(AVFrame *)frame pts:(double)pts {
    CVPixelBufferRef pb = NULL;
    _hardware = (frame->format == AV_PIX_FMT_VIDEOTOOLBOX);
    if (frame->format == AV_PIX_FMT_VIDEOTOOLBOX) {
        pb = (CVPixelBufferRef)frame->data[3];
        if (pb) CFRetain(pb);
    } else {
        pb = QLMBGRAFromFrame(frame, &_sws, frame->width, frame->height);
    }
    if (!pb) return NULL;
    if (_sar.num != _sar.den) {
        NSDictionary *par = @{(id)kCVImageBufferPixelAspectRatioHorizontalSpacingKey: @(_sar.num),
                              (id)kCVImageBufferPixelAspectRatioVerticalSpacingKey: @(_sar.den)};
        CVBufferSetAttachment(pb, kCVImageBufferPixelAspectRatioKey, (__bridge CFDictionaryRef)par, kCVAttachmentMode_ShouldPropagate);
    }
    CMVideoFormatDescriptionRef desc = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pb, &desc);
    double dur = frame->duration > 0 ? frame->duration * av_q2d(_vTimeBase) : 0;
    if (dur <= 0 && _fmt->streams[_vIndex]->avg_frame_rate.num > 0) dur = 1.0 / av_q2d(_fmt->streams[_vIndex]->avg_frame_rate);
    CMSampleTimingInfo timing = {
        .duration = dur > 0 ? CMTimeMakeWithSeconds(dur, 90000) : kCMTimeInvalid,
        .presentationTimeStamp = CMTimeMakeWithSeconds(pts, 90000),
        .decodeTimeStamp = kCMTimeInvalid,
    };
    CMSampleBufferRef sb = NULL;
    CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, pb, desc, &timing, &sb);
    CFRelease(desc);
    CVPixelBufferRelease(pb);
    return sb;
}

// MARK: Audio

- (CMSampleBufferRef)copyNextAudioSample {
    if (!_actx) return NULL;
    for (;;) {
        [_cond lock]; int gen = _generation; double discard = _discardBefore; [_cond unlock];
        if (gen != _aGeneration) {
            avcodec_flush_buffers(_actx);
            if (_swr) swr_free(&_swr);
            _aGeneration = gen;
        }
        int rc = avcodec_receive_frame(_actx, _aframe);
        if (rc == 0) {
            double pts = _aframe->best_effort_timestamp == AV_NOPTS_VALUE ? 0 : _aframe->best_effort_timestamp * av_q2d(_aTimeBase);
            CMSampleBufferRef sb = NULL;
            if (!(_aGeneration > 0 && pts + (double)_aframe->nb_samples / MAX(1, _aframe->sample_rate) < discard - 0.001)) {
                sb = [self makeAudioSampleFromFrame:_aframe pts:pts];
            }
            av_frame_unref(_aframe);
            if (sb) return sb;
            continue;
        }
        if (rc == AVERROR(EAGAIN)) {
            QLMPacket *p = [self nextPacketFromQueue:_aq eof:&_aEOF];
            if (!p) return NULL;
            [_cond lock]; int current = _generation; [_cond unlock];
            if (p->generation == current) avcodec_send_packet(_actx, p->pkt);
            continue;
        }
        if (rc == AVERROR_EOF) return NULL;
        QLMPacket *p = [self nextPacketFromQueue:_aq eof:&_aEOF];
        if (!p) return NULL;
        avcodec_send_packet(_actx, p->pkt);
    }
}

- (CMSampleBufferRef)makeAudioSampleFromFrame:(AVFrame *)frame pts:(double)pts {
    if (!_swr) {
        AVChannelLayout out = AV_CHANNEL_LAYOUT_STEREO;
        if (swr_alloc_set_opts2(&_swr, &out, AV_SAMPLE_FMT_FLT, kAudioRate, &frame->ch_layout, (enum AVSampleFormat)frame->format,
                                frame->sample_rate, 0, NULL) < 0 || swr_init(_swr) < 0) {
            if (_swr) swr_free(&_swr);
            return NULL;
        }
    }
    int outSamples = swr_get_out_samples(_swr, frame->nb_samples);
    if (outSamples <= 0) return NULL;
    size_t bytes = (size_t)outSamples * 2 * sizeof(float);
    uint8_t *buf = malloc(bytes);
    if (!buf) return NULL;
    int got = swr_convert(_swr, &buf, outSamples, (const uint8_t **)frame->extended_data, frame->nb_samples);
    if (got <= 0) { free(buf); return NULL; }
    size_t used = (size_t)got * 2 * sizeof(float);

    CMBlockBufferRef block = NULL;
    OSStatus st = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault, NULL, used, kCFAllocatorDefault, NULL, 0, used,
                                                    kCMBlockBufferAssureMemoryNowFlag, &block);
    if (st != noErr) { free(buf); return NULL; }
    CMBlockBufferReplaceDataBytes(buf, block, 0, used);
    free(buf);
    CMSampleBufferRef sb = NULL;
    CMAudioSampleBufferCreateReadyWithPacketDescriptions(kCFAllocatorDefault, block, _adesc, got,
                                                         CMTimeMakeWithSeconds(pts, kAudioRate), NULL, &sb);
    CFRelease(block);
    return sb;
}

// MARK: Miniatura

+ (CGImageRef)copyThumbnailForPath:(NSString *)path fraction:(double)fraction maxSize:(int)maxSize {
    AVFormatContext *fmt = NULL;
    if (avformat_open_input(&fmt, path.fileSystemRepresentation, NULL, NULL) < 0) return NULL;
    CGImageRef result = NULL;
    AVCodecContext *ctx = NULL;
    AVPacket *pkt = av_packet_alloc();
    AVFrame *frame = av_frame_alloc();
    struct SwsContext *sws = NULL;
    do {
        if (avformat_find_stream_info(fmt, NULL) < 0) break;
        const AVCodec *codec = NULL;
        int vi = av_find_best_stream(fmt, AVMEDIA_TYPE_VIDEO, -1, -1, &codec, 0);
        if (vi < 0 || !codec) break;
        AVStream *st = fmt->streams[vi];
        ctx = avcodec_alloc_context3(codec);
        avcodec_parameters_to_context(ctx, st->codecpar);
        ctx->thread_count = 0;
        if (avcodec_open2(ctx, codec, NULL) < 0) break;
        double duration = fmt->duration > 0 ? (double)fmt->duration / AV_TIME_BASE : 0;
        double target = duration * MAX(0, MIN(1, fraction));
        if (target > 0) avformat_seek_file(fmt, -1, INT64_MIN, (int64_t)(target * AV_TIME_BASE), (int64_t)(target * AV_TIME_BASE), 0);
        BOOL got = NO;
        for (int guard = 0; guard < 3000 && !got; guard++) {
            int rc = av_read_frame(fmt, pkt);
            if (rc < 0) { avcodec_send_packet(ctx, NULL); }
            else if (pkt->stream_index == vi) { avcodec_send_packet(ctx, pkt); }
            av_packet_unref(pkt);
            while (avcodec_receive_frame(ctx, frame) == 0) {
                double pts = frame->best_effort_timestamp == AV_NOPTS_VALUE ? 0 : frame->best_effort_timestamp * av_q2d(st->time_base);
                if (pts + 0.001 >= target || rc < 0) { got = YES; break; }
                av_frame_unref(frame);
            }
            if (rc < 0 && !got) break;
        }
        if (!got) break;
        AVRational sar = av_guess_sample_aspect_ratio(fmt, st, frame);
        double w = frame->width * ((sar.num > 0 && sar.den > 0) ? (double)sar.num / sar.den : 1.0), h = frame->height;
        double k = MIN((double)maxSize / w, (double)maxSize / h);
        int outW = MAX(2, (int)round(w * MIN(1, k))), outH = MAX(2, (int)round(h * MIN(1, k)));
        CVPixelBufferRef pb = QLMBGRAFromFrame(frame, &sws, outW, outH);
        if (!pb) break;
        CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
        CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGContextRef g = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pb), outW, outH, 8, CVPixelBufferGetBytesPerRow(pb), cs,
                                               kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
        result = g ? CGBitmapContextCreateImage(g) : NULL;   // copia i pixel: il buffer si può rilasciare
        if (g) CGContextRelease(g);
        CGColorSpaceRelease(cs);
        CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
        CVPixelBufferRelease(pb);
    } while (0);
    if (sws) sws_freeContext(sws);
    av_frame_free(&frame);
    av_packet_free(&pkt);
    if (ctx) avcodec_free_context(&ctx);
    avformat_close_input(&fmt);
    return result;
}

@end
