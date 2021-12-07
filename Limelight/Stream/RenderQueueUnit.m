//
//  RenderQueueUnit.m
//  Moonlight
//
//  Created by Felipe Cavalcanti on 27/10/21.
//  Copyright © 2021 Moonlight Game Streaming Project. All rights reserved.
//

#import "RenderQueueUnit.h"

@implementation RenderQueueUnit

- (id)initWithFrameType:(int)frameType blockBufferRef:(CMBlockBufferRef)blockBufferRef sampleBufferRef:(CMSampleBufferRef)sampleBufferRef{
    self = [super init];
    _frameType = frameType;
    _blockBufferRef = blockBufferRef;
    _sampleBufferRef = sampleBufferRef;
    return self;
}

@end
