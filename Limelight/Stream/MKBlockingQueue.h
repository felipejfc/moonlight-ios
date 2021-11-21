//  MKBlockingQueue.m
//  Moonlight
//
//  Created by Felipe Cavalcanti on 27/10/21.
//

/*
 The MIT License (MIT)

 Copyright (c) 2014 Min Kwon

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */

#ifndef MKBlockingQueue_h
#define MKBlockingQueue_h

@interface MKBlockingQueue : NSObject

/**
 * Enqueues an object to the queue.
 * @param object Object to enqueue
 */
- (void)enqueue:(id)object;

/**
 * Dequeues an object from the queue.  This method will block.
 */
- (id)dequeue;

- (NSUInteger)count;

@end

@interface MKBlockingQueue()
@property (nonatomic, strong) NSMutableArray *queue;
@property (nonatomic, strong) NSCondition *emptyLock;
@property (nonatomic, strong) dispatch_queue_t dispatchQueue;
@property (nonatomic) bool interrupt;
@end

#endif /* MKBlockingQueue_h */
