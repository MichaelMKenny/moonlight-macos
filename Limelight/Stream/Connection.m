//
//  Connection.m
//  Moonlight
//
//  Created by Diego Waxemberg on 1/19/14.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "Connection.h"
#import "Utils.h"

#import "Moonlight-Swift.h"

#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <stdatomic.h>
#include "Limelight.h"


@implementation Connection {
    SERVER_INFORMATION _serverInfo;
    STREAM_CONFIGURATION _streamConfig;
    CONNECTION_LISTENER_CALLBACKS _clCallbacks;
    DECODER_RENDERER_CALLBACKS _drCallbacks;
    AUDIO_RENDERER_CALLBACKS _arCallbacks;
    char _hostString[256];
    char _appVersionString[32];
    char _gfeVersionString[32];
}

static NSLock* initLock;
static id<ConnectionCallbacks> _callbacks;

static int channelCount;
static float audioVolumeMultiplier = 1.0f;
static NSString *hostAddress;

static OPUS_MULTISTREAM_CONFIGURATION audioConfig;
static AVAudioEngine *audioEngine = nil;
static AVAudioPlayerNode *playerNode = nil;
static AVAudioConverter* audioConverter = nil;
static AVAudioFormat *inputOpusFormat = nil;
static AVAudioFormat *outputPcmFormat = nil;
static atomic_int queuePackets = 0;



static VideoDecoderRenderer* renderer;

int DrDecoderSetup(int videoFormat, int width, int height, int redrawRate, void* context, int drFlags)
{
    [renderer setupWithVideoFormat:videoFormat frameRate:redrawRate];
    return 0;
}

void DrStart(void)
{
    [renderer start];
}

void DrStop(void)
{
    [renderer stop];

    _callbacks = nil;
    renderer = nil;
}

int DrSubmitDecodeUnit(PDECODE_UNIT decodeUnit)
{
    int offset = 0;
    int ret;
    unsigned char* data = (unsigned char*) malloc(decodeUnit->fullLength);
    if (data == NULL) {
        // A frame was lost due to OOM condition
        return DR_NEED_IDR;
    }

    PLENTRY entry = decodeUnit->bufferList;
    while (entry != NULL) {
        // Submit parameter set NALUs directly since no copy is required by the decoder
        if (entry->bufferType != BUFFER_TYPE_PICDATA) {
            ret = [renderer submitDecodeBuffer:(unsigned char*)entry->data
                                        length:entry->length
                                    bufferType:entry->bufferType
                                     frameType:decodeUnit->frameType
                                           pts:decodeUnit->presentationTimeMs];
            if (ret != DR_OK) {
                free(data);
                return ret;
            }
        }
        else {
            memcpy(&data[offset], entry->data, entry->length);
            offset += entry->length;
        }

        entry = entry->next;
    }

    // This function will take our picture data buffer
    return [renderer submitDecodeBuffer:data
                                 length:offset
                             bufferType:BUFFER_TYPE_PICDATA
                              frameType:decodeUnit->frameType
                                    pts:decodeUnit->presentationTimeMs];
}

int ArInit(int audioConfiguration, POPUS_MULTISTREAM_CONFIGURATION opusConfig, void* context, int flags)
{

    // Create engine and player node
    audioEngine = [[AVAudioEngine alloc] init];
    audioEngine.mainMixerNode.outputVolume = audioVolumeMultiplier;
    playerNode = [[AVAudioPlayerNode alloc] init];
    [audioEngine attachNode:playerNode];

    outputPcmFormat =[[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                  sampleRate:opusConfig->sampleRate
                                                    channels:opusConfig->channelCount
                                                 interleaved:NO];
    if ( !outputPcmFormat) {
        Log(LOG_E, @"Failed to create audio format");
        ArCleanup();
        return -1;
    }
    // Create compressed Opus AVAudioFormat (kAudioFormatOpus)
    AudioStreamBasicDescription opusDesc = {
        .mSampleRate       = (Float64)opusConfig->sampleRate,
        .mFormatID         = kAudioFormatOpus,
        .mFormatFlags      = 0,
        .mBytesPerPacket   = 0,
        .mFramesPerPacket  = (UInt32)opusConfig->samplesPerFrame,
        .mBytesPerFrame    = 0, //variable size
        .mChannelsPerFrame = (UInt32)opusConfig->channelCount,
        .mBitsPerChannel   = 0,
        .mReserved         = 0
    };

    inputOpusFormat = [[AVAudioFormat alloc] initWithStreamDescription:&opusDesc];
    if (!inputOpusFormat) {
        Log(LOG_E, @"Failed to create Opus AVAudioFormat (kAudioFormatOpus)");
        ArCleanup();
        return -1;
    }
    // Create converter from int16(interleaved) -> float32(non-interleaved)
    audioConverter = [[AVAudioConverter alloc] initFromFormat:inputOpusFormat toFormat:outputPcmFormat];
    if (!audioConverter) {
        Log(LOG_E, @"Failed to create AVAudioConverter");
        ArCleanup();
        return -1;
    }
    
    @try{
        [audioEngine connect:playerNode to:audioEngine.mainMixerNode format:outputPcmFormat];
    } @catch (NSException *e) {
        Log(LOG_E, @"Failed to connect playerNode: %@", e);
        ArCleanup();
        return -1;
    }
    
    NSError *errEngine = nil;
    if (![audioEngine startAndReturnError:&errEngine]) {
        Log(LOG_E, @"Failed to start AVAudioEngine: %@", errEngine);
        ArCleanup();
        return -1;
    }
    
    // Keep opus decoder and buffers
    audioConfig = *opusConfig;

    // Start playback
    [playerNode play];
    
    // Initialize queuedFrames
    atomic_store(&queuePackets, 0);
    
    return 0;
}

void ArCleanup(void)
{
    if (playerNode != nil) {
        @try {
            [playerNode stop];
            if (audioEngine != nil){
                [audioEngine detachNode:playerNode];
            }
        } @catch (...) {}
        playerNode = nil;
    }
    
    if (audioEngine != nil) {
        @try {
            [audioEngine stop];
        } @catch (...) {}
        audioEngine = nil;
    }
    
    inputOpusFormat = nil;
    outputPcmFormat = nil;
    
    audioConverter = nil;
    
    atomic_store(&queuePackets, 0);
}

void ArDecodeAndPlaySample(char* sampleData, int sampleLength)
{
    if(sampleLength == 0){
        return;
    }
    // Don't queue if there's already more than 30 ms of audio data waiting
    if (LiGetPendingAudioDuration() > 30) {
        return;
    }

    AVAudioCompressedBuffer *opusCompressedBuffer = [[AVAudioCompressedBuffer alloc]
            initWithFormat:inputOpusFormat
            packetCapacity:1
            maximumPacketSize:sampleLength];
    if (!opusCompressedBuffer) {
        Log(LOG_E, @"Failed to create AVAudioCompressedBuffer");
        return;
    }
    opusCompressedBuffer.packetCount = 1;
    if (opusCompressedBuffer.packetDescriptions != NULL) {
        opusCompressedBuffer.packetDescriptions[0].mStartOffset = 0;
        opusCompressedBuffer.packetDescriptions[0].mDataByteSize = (UInt32)sampleLength;
        opusCompressedBuffer.packetDescriptions[0].mVariableFramesInPacket = (UInt32)audioConfig.samplesPerFrame;
    }
    
    memcpy(opusCompressedBuffer.data, sampleData, sampleLength);
    opusCompressedBuffer.byteLength = sampleLength;

    AVAudioPCMBuffer *pcmOut = [[AVAudioPCMBuffer alloc] initWithPCMFormat:outputPcmFormat frameCapacity:audioConfig.samplesPerFrame];
    if (pcmOut == nil) {
        Log(LOG_E, @"Failed to create output AVAudioPCMBuffer");
        return;
    }

    NSError *convertError = nil;
    __block int8_t pendingPacket = 1;
    AVAudioConverterInputBlock inputBlock = ^AVAudioBuffer* (AVAudioPacketCount inNumPackets, AVAudioConverterInputStatus *outStatus) {
        if(pendingPacket > 0){
            *outStatus = AVAudioConverterInputStatus_HaveData;
            pendingPacket--;
            return opusCompressedBuffer;
        }else{
            *outStatus = AVAudioConverterInputStatus_NoDataNow;
            return nil;
        }
    };

    AVAudioConverterOutputStatus status =  [audioConverter convertToBuffer:pcmOut error:&convertError withInputFromBlock:inputBlock];

    if (status == AVAudioConverterOutputStatus_Error) {
        Log(LOG_E,@"[PcmPlayer] Audio conversion failed with status %ld error: %@", (long)status, convertError.localizedDescription);
        return;
    }else if(pcmOut.frameLength == 0){
        return;
    }

    // Backpressure: ensure we don't queue too many buffers locally
    while ((atomic_load(&queuePackets)) > 20) {
        usleep(1000);
    }

    // Schedule the converted buffer (float non-interleaved) on the player node
    atomic_fetch_add(&queuePackets, 1);
    [playerNode scheduleBuffer:pcmOut completionHandler:^{
        atomic_fetch_sub(&queuePackets, 1);
    }];
}

- (void)updateVolume {
    if (hostAddress != nil) {
        NSString *uuid = [SettingsClass getHostUUIDFrom:hostAddress];
        audioVolumeMultiplier = [SettingsClass volumeLevelFor:uuid];
    }
}

void ClStageStarting(int stage)
{
    [_callbacks stageStarting:LiGetStageName(stage)];
}

void ClStageComplete(int stage)
{
    [_callbacks stageComplete:LiGetStageName(stage)];
}

void ClStageFailed(int stage, int errorCode)
{
    [_callbacks stageFailed:LiGetStageName(stage) withError:errorCode];
}

void ClConnectionStarted(void)
{
    [_callbacks connectionStarted];
}

void ClConnectionTerminated(int errorCode)
{
    [_callbacks connectionTerminated: errorCode];
}

void ClLogMessage(const char* format, ...)
{
    va_list va;
    va_start(va, format);
    vfprintf(stderr, format, va);
    va_end(va);
}

void ClRumble(unsigned short controllerNumber, unsigned short lowFreqMotor, unsigned short highFreqMotor)
{
    [_callbacks rumble:controllerNumber lowFreqMotor:lowFreqMotor highFreqMotor:highFreqMotor];
}

void ClConnectionStatusUpdate(int status)
{
    [_callbacks connectionStatusUpdate:status];
}

-(void) terminate
{
    // Interrupt any action blocking LiStartConnection(). This is
    // thread-safe and done outside initLock on purpose, since we
    // won't be able to acquire it if LiStartConnection is in
    // progress.
    LiInterruptConnection();
    
    // We dispatch this async to get out because this can be invoked
    // on a thread inside common and we don't want to deadlock. It also avoids
    // blocking on the caller's thread waiting to acquire initLock.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [initLock lock];
        LiStopConnection();
        [initLock unlock];
    });
}

-(id) initWithConfig:(StreamConfiguration*)config renderer:(VideoDecoderRenderer*)myRenderer connectionCallbacks:(id<ConnectionCallbacks>)callbacks
{
    self = [super init];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateVolume) name:@"volumeSettingChanged" object:nil];
    
    // Use a lock to ensure that only one thread is initializing
    // or deinitializing a connection at a time.
    if (initLock == nil) {
        initLock = [[NSLock alloc] init];
    }
    
    hostAddress = config.host;
    [self updateVolume];
    
    strncpy(_hostString,
            [config.host cStringUsingEncoding:NSUTF8StringEncoding],
            sizeof(_hostString));
    strncpy(_appVersionString,
            [config.appVersion cStringUsingEncoding:NSUTF8StringEncoding],
            sizeof(_appVersionString));
    if (config.gfeVersion != nil) {
        strncpy(_gfeVersionString,
                [config.gfeVersion cStringUsingEncoding:NSUTF8StringEncoding],
                sizeof(_gfeVersionString));
    }

    LiInitializeServerInformation(&_serverInfo);
    _serverInfo.address = _hostString;
    _serverInfo.serverInfoAppVersion = _appVersionString;
    if (config.gfeVersion != nil) {
        _serverInfo.serverInfoGfeVersion = _gfeVersionString;
    }

    renderer = myRenderer;
    _callbacks = callbacks;

    LiInitializeStreamConfiguration(&_streamConfig);
    _streamConfig.width = config.width;
    _streamConfig.height = config.height;
    _streamConfig.fps = config.frameRate;
    _streamConfig.bitrate = config.bitRate;
    _streamConfig.enableHdr = config.enableHdr;
    _streamConfig.audioConfiguration = config.audioConfiguration;
    _streamConfig.colorSpace = COLORSPACE_REC_709;
    _streamConfig.colorRange = COLOR_RANGE_FULL; // make use of 0-255 instead of default 16-235 limited range
    
    // Use some of the HEVC encoding efficiency improvements to
    // reduce bandwidth usage while still gaining some image
    // quality improvement.
    _streamConfig.hevcBitratePercentageMultiplier = 75;
    
    if ([Utils isActiveNetworkVPN]) {
        // Force remote streaming mode when a VPN is connected
        _streamConfig.streamingRemotely = STREAM_CFG_REMOTE;
        _streamConfig.packetSize = 1024;
    }
    else {
        // Detect remote streaming automatically based on the IP address of the target
        _streamConfig.streamingRemotely = STREAM_CFG_AUTO;
        _streamConfig.packetSize = 1392;
    }
    
    // HDR implies HEVC allowed
    if (config.enableHdr) {
        config.allowHevc = YES;
    }

    // On iOS 11, we can use HEVC if the server supports encoding it
    // and this device has hardware decode for it (A9 and later).
    // Additionally, iPhone X had a bug which would cause video
    // to freeze after a few minutes with HEVC prior to iOS 11.3.
    // As a result, we will only use HEVC on iOS 11.3 or later.
    if (@available(iOS 11.3, tvOS 11.3, macOS 10.14, *)) {
        _streamConfig.supportsHevc = config.allowHevc && VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC);
    }
    
    // HEVC must be supported when HDR is enabled
    assert(!_streamConfig.enableHdr || _streamConfig.supportsHevc);

    memcpy(_streamConfig.remoteInputAesKey, [config.riKey bytes], [config.riKey length]);
    memset(_streamConfig.remoteInputAesIv, 0, 16);
    int riKeyId = htonl(config.riKeyId);
    memcpy(_streamConfig.remoteInputAesIv, &riKeyId, sizeof(riKeyId));

    LiInitializeVideoCallbacks(&_drCallbacks);
    _drCallbacks.setup = DrDecoderSetup;
    _drCallbacks.start = DrStart;
    _drCallbacks.stop = DrStop;

//#if TARGET_OS_IPHONE
    // RFI doesn't work properly with HEVC on iOS 11 with an iPhone SE (at least)
    // It doesnt work on macOS either, tested with Network Link Conditioner.
    _drCallbacks.capabilities = CAPABILITY_PULL_RENDERER;
//#endif

    LiInitializeAudioCallbacks(&_arCallbacks);
    _arCallbacks.init = ArInit;
    _arCallbacks.cleanup = ArCleanup;
    _arCallbacks.decodeAndPlaySample = ArDecodeAndPlaySample;
    _arCallbacks.capabilities = CAPABILITY_DIRECT_SUBMIT |
                                CAPABILITY_SUPPORTS_ARBITRARY_AUDIO_DURATION;

    LiInitializeConnectionCallbacks(&_clCallbacks);
    _clCallbacks.stageStarting = ClStageStarting;
    _clCallbacks.stageComplete = ClStageComplete;
    _clCallbacks.stageFailed = ClStageFailed;
    _clCallbacks.connectionStarted = ClConnectionStarted;
    _clCallbacks.connectionTerminated = ClConnectionTerminated;
    _clCallbacks.logMessage = ClLogMessage;
    _clCallbacks.rumble = ClRumble;
    _clCallbacks.connectionStatusUpdate = ClConnectionStatusUpdate;

    return self;
}


-(void) main
{
    [initLock lock];
    LiStartConnection(&_serverInfo,
                      &_streamConfig,
                      &_clCallbacks,
                      &_drCallbacks,
                      &_arCallbacks,
                      NULL, 0,
                      NULL, 0);
    [initLock unlock];
}

@end
