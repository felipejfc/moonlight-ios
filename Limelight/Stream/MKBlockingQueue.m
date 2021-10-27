//
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

#import <Foundation/Foundation.h>
#import "MKBlockingQueue.h"

@implementation MKBlockingQueue

- (id)init
{
    self = [super init];
    if (self)
    {
        self.queue = [[NSMutableArray alloc] init];
        self.lock = [[NSCondition alloc] init];
        self.waitLock = [[NSCondition alloc] init];
        self.dispatchQueue = dispatch_queue_create("com.min.kwon.mkblockingqueue", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)enqueue:(id)object
{
    [_lock lock];
    [_queue addObject:object];
    [_lock signal];
    [_lock unlock];
}

- (id)dequeue
{
    __block id object;
    dispatch_sync(_dispatchQueue, ^{
        [_lock lock];
        while (_queue.count == 0 && !_interrupt)
        {
            [_lock wait];
        }
        if (_interrupt){
            object = nil;
        } else {
            object = [_queue objectAtIndex:0];
            [_queue removeObjectAtIndex:0];
            [_lock unlock];
        }
    });
    
    return object;
}

- (NSUInteger)count
{
    return [_queue count];
}

- (void)dealloc
{
    self.dispatchQueue = nil;
    self.queue = nil;
    self.lock = nil;
}

@end
