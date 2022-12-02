//
//  VideoDecoderRenderer.m
//  Moonlight
//
//  Created by Cameron Gutman on 10/18/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

@import VideoToolbox;

#import "VideoDecoderRenderer.h"
#import "StreamView.h"
#import "LinkedBlockingQueue.h"

#include "Limelight.h"

#define MAX_PENDING_FRAMES 150

typedef struct BUFFER_HOLDER {
    LINKED_BLOCKING_QUEUE_ENTRY entry;
    CVImageBufferRef buffer;
} BUFFER_HOLDER, *PBUFFER_HOLDER;

@implementation VideoDecoderRenderer {
    StreamView* _view;
    id<ConnectionCallbacks> _callbacks;
    float _streamAspectRatio;
    
    CALayer* displayLayer;
    Boolean waitingForSps, waitingForPps, waitingForVps;
    int videoFormat;
    int frameRate;
    
    NSData *spsData, *ppsData, *vpsData;
    CMVideoFormatDescriptionRef formatDesc;
    CMVideoFormatDescriptionRef formatDescImageBuffer;
    VTDecompressionSessionRef decompressionSession;
    LINKED_BLOCKING_QUEUE framesQueue;
    LINKED_BLOCKING_QUEUE framesQueueFreeList;
    
    CADisplayLink* _displayLink;
    BOOL framePacing;
}

- (void)reinitializeDisplayLayer
{
    CALayer *oldLayer = displayLayer;
    
    displayLayer = [[AVSampleBufferDisplayLayer alloc] init];
    displayLayer.backgroundColor = [UIColor blackColor].CGColor;
    
    // Ensure the AVSampleBufferDisplayLayer is sized to preserve the aspect ratio
    // of the video stream. We used to use AVLayerVideoGravityResizeAspect, but that
    // respects the PAR encoded in the SPS which causes our computed video-relative
    // touch location to be wrong in StreamView if the aspect ratio of the host
    // desktop doesn't match the aspect ratio of the stream.
    CGSize videoSize;
    if (_view.bounds.size.width > _view.bounds.size.height * _streamAspectRatio) {
        videoSize = CGSizeMake(_view.bounds.size.height * _streamAspectRatio, _view.bounds.size.height);
    } else {
        videoSize = CGSizeMake(_view.bounds.size.width, _view.bounds.size.width / _streamAspectRatio);
    }
    displayLayer.position = CGPointMake(CGRectGetMidX(_view.bounds), CGRectGetMidY(_view.bounds));
    displayLayer.bounds = CGRectMake(0, 0, videoSize.width, videoSize.height);

    // Hide the layer until we get an IDR frame. This ensures we
    // can see the loading progress label as the stream is starting.
    displayLayer.hidden = YES;
    
    if (oldLayer != nil) {
        // Switch out the old display layer with the new one
        [_view.layer replaceSublayer:oldLayer with:displayLayer];
    }
    else {
        [_view.layer addSublayer:displayLayer];
    }
    
    // We need some parameter sets before we can properly start decoding frames
    waitingForSps = true;
    spsData = nil;
    waitingForPps = true;
    ppsData = nil;
    waitingForVps = true;
    vpsData = nil;
    
    if (formatDesc != nil) {
        CFRelease(formatDesc);
        formatDesc = nil;
    }
    
    if (formatDescImageBuffer != nil) {
        CFRelease(formatDescImageBuffer);
        formatDescImageBuffer = nil;
    }
    
    if (decompressionSession != nil){
        VTDecompressionSessionInvalidate(decompressionSession);
        CFRelease(decompressionSession);
        decompressionSession = nil;
    }
}

- (id)initWithView:(StreamView*)view callbacks:(id<ConnectionCallbacks>)callbacks streamAspectRatio:(float)aspectRatio useFramePacing:(BOOL)useFramePacing
{
    self = [super init];
    
    _view = view;
    _callbacks = callbacks;
    _streamAspectRatio = aspectRatio;
    framePacing = useFramePacing;
    
    [self reinitializeDisplayLayer];
    
    return self;
}

- (void)setupWithVideoFormat:(int)videoFormat frameRate:(int)frameRate
{
    self->videoFormat = videoFormat;
    self->frameRate = frameRate;
    
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkCallback:)];
    if (@available(iOS 15.0, tvOS 15.0, *)) {
        _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(self->frameRate, self->frameRate, self->frameRate);
    }
    else if (@available(iOS 10.0, tvOS 10.0, *)) {
        _displayLink.preferredFramesPerSecond = self->frameRate;
    }
    
    LbqInitializeLinkedBlockingQueue(&framesQueue, MAX_PENDING_FRAMES);
    LbqInitializeLinkedBlockingQueue(&framesQueueFreeList, MAX_PENDING_FRAMES);
    
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];

}

- (void) setupDecompressionSession {
    if (decompressionSession != NULL){
        VTDecompressionSessionInvalidate(decompressionSession);
        CFRelease(decompressionSession);
        decompressionSession = nil;
    }
    
    NSDictionary *pixelAttributes = @{
        (id)kCVPixelBufferIOSurfaceCoreAnimationCompatibilityKey : (id)kCFBooleanTrue,
        (id)kCVPixelBufferIOSurfacePropertiesKey : @{},
    };

    int status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                              formatDesc,
                                              nil,
                                              (__bridge CFDictionaryRef _Nullable)(pixelAttributes),
                                              nil,
                                              &decompressionSession);
    if (status != noErr) {
        Log(LOG_E, @"Failed to instance VTDecompressionSessionRef, status %d", status);
    }
        
}

// TODO: Refactor this
int DrSubmitDecodeUnit(PDECODE_UNIT decodeUnit);

- (void)displayLinkCallback:(CADisplayLink *)sender
{
    PBUFFER_HOLDER bufferHolder;
    while(framePacing && LbqPollQueueElement(&framesQueue, (void**)&bufferHolder) == LBQ_SUCCESS){
        [self updateViewWithImageBuffer:bufferHolder->buffer];
        if (LbqOfferQueueItem(&framesQueueFreeList, bufferHolder, &bufferHolder->entry) != LBQ_SUCCESS){
            free(bufferHolder);
        }
        
        double displayRefreshRate = 1 / (_displayLink.targetTimestamp - _displayLink.timestamp);
        
        // Only pace frames if the display refresh rate is >= 90% of our stream frame rate.
        // Battery saver, accessibility settings, or device thermals can cause the actual
        // refresh rate of the display to drop below the physical maximum.
        if (displayRefreshRate >= frameRate * 0.9f) {
            // Keep one pending frame to smooth out gaps due to
            // network jitter at the cost of 1 frame of latency
            if (LbqGetItemCount(&framesQueue) == 1) {
                break;
            }
        }
    }
}

- (void)cleanup
{
    [_displayLink invalidate];
    LbqSignalQueueShutdown(&framesQueue);
    LbqSignalQueueShutdown(&framesQueueFreeList);
    [self drainFramesQueue];
}

- (void)drainFramesQueue
{
    PLINKED_BLOCKING_QUEUE_ENTRY entry, nextEntry;
    entry = LbqDestroyLinkedBlockingQueue(&framesQueue);
    while (entry != NULL){
        nextEntry = entry->flink;
        PBUFFER_HOLDER holder = entry->data;
        CFRelease(holder->buffer);
        free(entry->data);
        entry = nextEntry;
    }
    
    entry = LbqDestroyLinkedBlockingQueue(&framesQueueFreeList);
    while (entry != NULL){
        nextEntry = entry->flink;
        free(entry->data);
        entry = nextEntry;
    }
}

#define NALU_START_PREFIX_SIZE 3
#define NAL_LENGTH_PREFIX_SIZE 4

- (Boolean)readyForPictureData
{
    if (videoFormat & VIDEO_FORMAT_MASK_H264) {
        return !waitingForSps && !waitingForPps;
    }
    else {
        // H.265 requires VPS in addition to SPS and PPS
        return !waitingForVps && !waitingForSps && !waitingForPps;
    }
}

- (void)updateBufferForRange:(CMBlockBufferRef)frameBuffer dataBlock:(CMBlockBufferRef)dataBuffer offset:(int)offset length:(int)nalLength
{
    OSStatus status;
    size_t oldOffset = CMBlockBufferGetDataLength(frameBuffer);
    
    // Append a 4 byte buffer to the frame block for the length prefix
    status = CMBlockBufferAppendMemoryBlock(frameBuffer, NULL,
                                            NAL_LENGTH_PREFIX_SIZE,
                                            kCFAllocatorDefault, NULL, 0,
                                            NAL_LENGTH_PREFIX_SIZE, 0);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferAppendMemoryBlock failed: %d", (int)status);
        return;
    }
    
    // Write the length prefix to the new buffer
    const int dataLength = nalLength - NALU_START_PREFIX_SIZE;
    const uint8_t lengthBytes[] = {(uint8_t)(dataLength >> 24), (uint8_t)(dataLength >> 16),
        (uint8_t)(dataLength >> 8), (uint8_t)dataLength};
    status = CMBlockBufferReplaceDataBytes(lengthBytes, frameBuffer,
                                           oldOffset, NAL_LENGTH_PREFIX_SIZE);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferReplaceDataBytes failed: %d", (int)status);
        return;
    }
    
    // Attach the data buffer to the frame buffer by reference
    status = CMBlockBufferAppendBufferReference(frameBuffer, dataBuffer, offset + NALU_START_PREFIX_SIZE, dataLength, 0);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferAppendBufferReference failed: %d", (int)status);
        return;
    }
}

// This function must free data for bufferType == BUFFER_TYPE_PICDATA
- (int)submitDecodeBuffer:(unsigned char *)data length:(int)length bufferType:(int)bufferType frameType:(int)frameType pts:(unsigned int)pts
{
    OSStatus status;
    
    if (bufferType != BUFFER_TYPE_PICDATA) {
        int startLen = data[2] == 0x01 ? 3 : 4;
        
        if (bufferType == BUFFER_TYPE_VPS) {
            Log(LOG_I, @"Got VPS");
            vpsData = [NSData dataWithBytes:&data[startLen] length:length - startLen];
            waitingForVps = false;
            
            // We got a new VPS so wait for a new SPS to match it
            waitingForSps = true;
        }
        else if (bufferType == BUFFER_TYPE_SPS) {
            Log(LOG_I, @"Got SPS");
            spsData = [NSData dataWithBytes:&data[startLen] length:length - startLen];
            waitingForSps = false;
            
            // We got a new SPS so wait for a new PPS to match it
            waitingForPps = true;
        } else if (bufferType == BUFFER_TYPE_PPS) {
            Log(LOG_I, @"Got PPS");
            ppsData = [NSData dataWithBytes:&data[startLen] length:length - startLen];
            waitingForPps = false;
        }
        
        // See if we've got all the parameter sets we need for our video format
        if ([self readyForPictureData]) {
            if (videoFormat & VIDEO_FORMAT_MASK_H264) {
                const uint8_t* const parameterSetPointers[] = { [spsData bytes], [ppsData bytes] };
                const size_t parameterSetSizes[] = { [spsData length], [ppsData length] };
                
                Log(LOG_I, @"Constructing new H264 format description");
                status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                                             2, /* count of parameter sets */
                                                                             parameterSetPointers,
                                                                             parameterSetSizes,
                                                                             NAL_LENGTH_PREFIX_SIZE,
                                                                             &formatDesc);
                if (status != noErr) {
                    Log(LOG_E, @"Failed to create H264 format description: %d", (int)status);
                    formatDesc = NULL;
                }
            }
            else {
                const uint8_t* const parameterSetPointers[] = { [vpsData bytes], [spsData bytes], [ppsData bytes] };
                const size_t parameterSetSizes[] = { [vpsData length], [spsData length], [ppsData length] };
                
                Log(LOG_I, @"Constructing new HEVC format description");

                if (@available(iOS 11.0, *)) {
                    status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(kCFAllocatorDefault,
                                                                                 3, /* count of parameter sets */
                                                                                 parameterSetPointers,
                                                                                 parameterSetSizes,
                                                                                 NAL_LENGTH_PREFIX_SIZE,
                                                                                 nil,
                                                                                 &formatDesc);
                } else {
                    // This means Moonlight-common-c decided to give us an HEVC stream
                    // even though we said we couldn't support it. All we can do is abort().
                    abort();
                }
                
                if (status != noErr) {
                    Log(LOG_E, @"Failed to create HEVC format description: %d", (int)status);
                    formatDesc = NULL;
                }
            }
            
            [self setupDecompressionSession];
        }
        
        // Data is NOT to be freed here. It's a direct usage of the caller's buffer.
        
        // No frame data to submit for these NALUs
        return DR_OK;
    }
    
    if (formatDesc == NULL) {
        // Can't decode if we haven't gotten our parameter sets yet
        free(data);
        return DR_NEED_IDR;
    }
    
    // Now we're decoding actual frame data here
    CMBlockBufferRef frameBlockBuffer;
    CMBlockBufferRef dataBlockBuffer;
    
    status = CMBlockBufferCreateWithMemoryBlock(NULL, data, length, kCFAllocatorDefault, NULL, 0, length, 0, &dataBlockBuffer);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferCreateWithMemoryBlock failed: %d", (int)status);
        free(data);
        return DR_NEED_IDR;
    }
    
    // From now on, CMBlockBuffer owns the data pointer and will free it when it's dereferenced
    
    status = CMBlockBufferCreateEmpty(NULL, 0, 0, &frameBlockBuffer);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferCreateEmpty failed: %d", (int)status);
        CFRelease(dataBlockBuffer);
        return DR_NEED_IDR;
    }
    
    int lastOffset = -1;
    for (int i = 0; i < length - NALU_START_PREFIX_SIZE; i++) {
        // Search for a NALU
        if (data[i] == 0 && data[i+1] == 0 && data[i+2] == 1) {
            // It's the start of a new NALU
            if (lastOffset != -1) {
                // We've seen a start before this so enqueue that NALU
                [self updateBufferForRange:frameBlockBuffer dataBlock:dataBlockBuffer offset:lastOffset length:i - lastOffset];
            }
            
            lastOffset = i;
        }
    }
    
    if (lastOffset != -1) {
        // Enqueue the remaining data
        [self updateBufferForRange:frameBlockBuffer dataBlock:dataBlockBuffer offset:lastOffset length:length - lastOffset];
    }
        
    CMSampleBufferRef sampleBuffer;
    
    CMSampleTimingInfo sampleTiming = {kCMTimeInvalid, CMTimeMake(pts, 1000), kCMTimeInvalid};
    
    status = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                  frameBlockBuffer,
                                  formatDesc, 1, 1,
                                  &sampleTiming, 0, NULL,
                                  &sampleBuffer);
    if (status != noErr) {
        Log(LOG_E, @"CMSampleBufferCreate failed: %d", (int)status);
        CFRelease(dataBlockBuffer);
        CFRelease(frameBlockBuffer);
        CFRelease(sampleBuffer);
        return DR_NEED_IDR;
    }
       
    OSStatus decodeStatus = [self decodeFrameWithSampleBuffer: sampleBuffer frameType: frameType];
    
    // Dereference the buffers
    CFRelease(dataBlockBuffer);
    CFRelease(frameBlockBuffer);
    CFRelease(sampleBuffer);
     
    if (decodeStatus != noErr){
        Log(LOG_E, @"Failed to decompress frame: %d", decodeStatus);
        return DR_NEED_IDR;
    }
   
    return DR_OK;
}

- (OSStatus) decodeFrameWithSampleBuffer:(CMSampleBufferRef)sampleBuffer frameType:(int)frameType{
    VTDecodeFrameFlags flags = kVTDecodeFrame_EnableAsynchronousDecompression;
    
    return VTDecompressionSessionDecodeFrameWithOutputHandler(decompressionSession, sampleBuffer, flags, NULL, ^(OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef  _Nullable imageBuffer, CMTime presentationTimestamp, CMTime presentationDuration) {
        if (status != noErr)
        {
            NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
            Log(LOG_E, @"Decompression session error: %@", error);
            LiRequestIdrFrame();
            return;
        }
 
        CVPixelBufferRetain(imageBuffer);
        CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);

        if (self->framePacing){
            PBUFFER_HOLDER holder = [self allocateBufferHolder];
            if (holder == NULL) {
                Log(LOG_I, @"No buffer holder allocated. Are we draining?");
                CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
                CVPixelBufferRelease(imageBuffer);
                return;
            }
            holder->buffer = imageBuffer;
            status = LbqOfferQueueItem(&self->framesQueue, holder, &holder->entry);
            if (status != LBQ_SUCCESS){
                CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
                CVPixelBufferRelease(imageBuffer);
                free(holder);
                Log(LOG_E, @"Error inserting sample buffer into frames queue");
                return;
            }
        } else {
            [self updateViewWithImageBuffer:imageBuffer];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (frameType == FRAME_TYPE_IDR) {
                // Ensure the layer is visible now
                self->displayLayer.hidden = NO;
                
                // Tell our parent VC to hide the progress indicator
                [self->_callbacks videoContentShown];
            }
        });
    });
}

- (void) updateViewWithImageBuffer:(CVImageBufferRef)imageBuffer{
    dispatch_async(dispatch_get_main_queue(), ^{
        IOSurfaceRef surface = CVPixelBufferGetIOSurface(imageBuffer);
        IOSurfaceLock(surface, kIOSurfaceLockReadOnly, nil);
        self->displayLayer.contents = (__bridge id _Nullable)(surface);
        IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, nil);
        CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
        CVPixelBufferRelease(imageBuffer);
    });
}

- (PBUFFER_HOLDER) allocateBufferHolder {
    PBUFFER_HOLDER holder;
    int status = LbqPollQueueElement(&self->framesQueueFreeList, (void**) &holder);
    if (status == LBQ_SUCCESS){
        return holder;
    }
    else if (status == LBQ_INTERRUPTED) {
        // We're shutting down. Don't bother allocating.
        return NULL;
    }
    else {
        LC_ASSERT(err == LBQ_NO_ELEMENT);
        // Otherwise we'll have to allocate
        return malloc(sizeof(*holder));
    }
    
}

@end
