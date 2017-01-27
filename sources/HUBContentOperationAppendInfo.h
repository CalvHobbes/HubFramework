/*
 *  Copyright (c) 2016 Spotify AB.
 *
 *  Licensed to the Apache Software Foundation (ASF) under one
 *  or more contributor license agreements.  See the NOTICE file
 *  distributed with this work for additional information
 *  regarding copyright ownership.  The ASF licenses this file
 *  to you under the Apache License, Version 2.0 (the
 *  "License"); you may not use this file except in compliance
 *  with the License.  You may obtain a copy of the License at
 *
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing,
 *  software distributed under the License is distributed on an
 *  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 *  KIND, either express or implied.  See the License for the
 *  specific language governing permissions and limitations
 *  under the License.
 */
#import "HUBContentOperation.h"
#import "HUBHeaderMacros.h"

@protocol HUBContentOperation;

NS_ASSUME_NONNULL_BEGIN

/**
 *  Info class used to describe a new content operation that should be appended 
 *  to the current content loading chain.
 *
 *  This class is used by `HUBViewModelLoaderImplementation` to determine which operations to append,
 *  and after which current operation index.
 */
@interface HUBContentOperationAppendInfo : NSObject

/// The index of the content operation after which new operations should be appended
@property (nonatomic, assign) NSUInteger contentOperationIndex;

/// The new operations that should be appended
@property (nonatomic, copy, readonly) NSArray<id<HUBContentOperation>> *contentOperations;

/**
 *  Initialize an instance of this class
 *
 *  @param contentOperations New operations to append to content chain
 *  @param contentOperationIndex The index of the content operation after which new operations should be appended
 */
- (instancetype) initWithContentOperations:(NSArray<id<HUBContentOperation>> *)contentOperations forIndex:(NSUInteger)contentOperationIndex HUB_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
