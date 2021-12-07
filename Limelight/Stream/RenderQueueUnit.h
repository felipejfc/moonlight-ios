//
//  RenderQueueUnit.h
//  Moonlight
//
//  Created by Felipe Cavalcanti on 27/10/21.
//  Copyright © 2021 Moonlight Game Streaming Project. All rights reserved.
//

@import AVFoundation;

NS_ASSUME_NONNULL_BEGIN

@interface RenderQueueUnit : NSObject
@property (nonatomic) int frameType;
@property (nonatomic) CMBlockBufferRef blockBufferRef;
@property (nonatomic) CMSampleBufferRef sampleBufferRef;

- (id)initWithFrameType:(int)frameType blockBufferRef:(CMBlockBufferRef)blockBufferRef sampleBufferRef:(CMSampleBufferRef)sampleBufferRef;

@end


NS_ASSUME_NONNULL_END
