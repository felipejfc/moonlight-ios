//
//  VideoDecoderRenderer.h
//  Moonlight
//
//  Created by Cameron Gutman on 10/18/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

@import AVFoundation;

#import "ConnectionCallbacks.h"
#import "MKBlockingQueue.h"
#import "RenderQueueUnit.h"
#import <Foundation/Foundation.h>

@interface VideoDecoderRenderer : NSObject

- (id)initWithView:(UIView*)view callbacks:(id<ConnectionCallbacks>)callbacks useVsync:(BOOL)useVsync;

- (void)setupWithVideoFormat:(int)videoFormat refreshRate:(int)refreshRate;

- (void)cleanup;

- (void)updateBufferForRange:(CMBlockBufferRef)existingBuffer data:(unsigned char *)data offset:(int)offset length:(int)nalLength;

- (int)submitDecodeBuffer:(unsigned char *)data length:(int)length bufferType:(int)bufferType frameType:(int)frameType pts:(unsigned int)pts;


@property (nonatomic, strong) MKBlockingQueue * renderQueue;
@property (nonatomic, strong) NSCondition *vsyncLock;
@property (nonatomic) BOOL vsync;

@end
