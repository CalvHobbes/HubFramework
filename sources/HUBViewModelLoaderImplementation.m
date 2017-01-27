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

#import "HUBViewModelLoaderImplementation.h"

#import "HUBFeatureInfo.h"
#import "HUBConnectivityStateResolver.h"
#import "HUBContentOperationWithInitialContent.h"
#import "HUBContentOperationWithPaginatedContent.h"
#import "HUBContentOperationActionObserver.h"
#import "HUBContentOperationActionPerformer.h"
#import "HUBActionPerformer.h"
#import "HUBContentReloadPolicy.h"
#import "HUBJSONSchema.h"
#import "HUBViewModelBuilderImplementation.h"
#import "HUBViewModelImplementation.h"
#import "HUBContentOperationWrapper.h"
#import "HUBContentOperationExecutionInfo.h"
#import "HUBContentOperationAppendInfo.h"
#import "HUBContentOperation.h"
#import "HUBUtilities.h"

NS_ASSUME_NONNULL_BEGIN

@interface HUBViewModelLoaderImplementation () <HUBContentOperationWrapperDelegate, HUBConnectivityStateResolverObserver>

@property (nonatomic, copy, readonly) NSURL *viewURI;
@property (nonatomic, strong, readonly) id<HUBFeatureInfo> featureInfo;
@property (nonatomic, readonly) NSMutableArray<id<HUBContentOperation>> *contentOperations;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSNumber *, HUBContentOperationWrapper *> *contentOperationWrappers;
@property (nonatomic, strong, readonly) NSMutableArray<HUBContentOperationExecutionInfo *> *contentOperationQueue;

@property (nonatomic, strong, readonly) NSMutableArray<HUBContentOperationAppendInfo *> *contentOperationAppendQueue;
@property (nonatomic, strong, nullable, readonly) id<HUBContentReloadPolicy> contentReloadPolicy;
@property (nonatomic, strong, readonly) id<HUBJSONSchema> JSONSchema;
@property (nonatomic, strong, readonly) HUBComponentDefaults *componentDefaults;
@property (nonatomic, strong, readonly) id<HUBConnectivityStateResolver> connectivityStateResolver;
@property (nonatomic, assign) HUBConnectivityState connectivityState;
@property (nonatomic, strong, nullable, readonly) id<HUBIconImageResolver> iconImageResolver;
@property (nonatomic, strong, nullable) id<HUBViewModel> cachedInitialViewModel;
@property (nonatomic, strong, nullable) id<HUBViewModel> previouslyLoadedViewModel;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSNumber *,
HUBViewModelBuilderImplementation *> *builderSnapshots;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSNumber *, NSError *> *errorSnapshots;
@property (nonatomic, strong, nullable) HUBViewModelBuilderImplementation *currentBuilder;
@property (nonatomic, assign) BOOL anyContentOperationSupportsPagination;
@property (nonatomic, assign) NSUInteger pageIndex;

@end

@implementation HUBViewModelLoaderImplementation
    
static NSComparator descendingKeyComparator = ^NSComparisonResult(id a, id b) {
        NSNumber* first = (NSNumber*)a;
        NSNumber* second = (NSNumber*)b;
        if (first > second){
            return (NSComparisonResult)NSOrderedAscending;
        }
        else {
            return (NSComparisonResult)NSOrderedDescending;
        }
    };


//NSMutableArray<id<HUBContentOperation>> * _contentOperations;
//
//- (NSMutableArray<id<HUBContentOperation>> *)contentOperations {
//    return _contentOperations;
//}
//
//-(void) setContentOperations:(NSMutableArray<id<HUBContentOperation>> *)contentOperations {
//    
//    _contentOperations = contentOperations;
//}
@synthesize delegate = _delegate;



#pragma mark - Lifecycle

- (instancetype)initWithViewURI:(NSURL *)viewURI
                    featureInfo:(id<HUBFeatureInfo>)featureInfo
              contentOperations:(NSArray<id<HUBContentOperation>> *)contentOperations
            contentReloadPolicy:(nullable id<HUBContentReloadPolicy>)contentReloadPolicy
                     JSONSchema:(id<HUBJSONSchema>)JSONSchema
              componentDefaults:(HUBComponentDefaults *)componentDefaults
      connectivityStateResolver:(id<HUBConnectivityStateResolver>)connectivityStateResolver
              iconImageResolver:(nullable id<HUBIconImageResolver>)iconImageResolver
               initialViewModel:(nullable id<HUBViewModel>)initialViewModel
{
    NSParameterAssert(viewURI != nil);
    NSParameterAssert(featureInfo != nil);
    NSParameterAssert(contentOperations.count > 0);
    NSParameterAssert(JSONSchema != nil);
    NSParameterAssert(componentDefaults != nil);
    NSParameterAssert(connectivityStateResolver != nil);
    
    self = [super init];
    
    if (self) {
        _viewURI = [viewURI copy];
        _featureInfo = featureInfo;
        
        _contentOperations = [NSMutableArray arrayWithArray:contentOperations];
        _contentOperationWrappers = [NSMutableDictionary new];
        _contentOperationQueue = [NSMutableArray new];
        _contentOperationAppendQueue = [NSMutableArray new];
        _contentReloadPolicy = contentReloadPolicy;
        _JSONSchema = JSONSchema;
        _componentDefaults = componentDefaults;
        _connectivityStateResolver = connectivityStateResolver;
        _connectivityState = [_connectivityStateResolver resolveConnectivityState];
        _iconImageResolver = iconImageResolver;
        _cachedInitialViewModel = initialViewModel;
        _builderSnapshots = [NSMutableDictionary new];
        _errorSnapshots = [NSMutableDictionary new];
        
        [connectivityStateResolver addObserver:self];
    }
    
    return self;
}

- (void)dealloc
{
    [_connectivityStateResolver removeObserver:self];
}

#pragma mark - Public API

- (void)actionPerformedWithContext:(id<HUBActionContext>)context
{
    for (id<HUBContentOperation> const operation in self.contentOperations) {
        if (![operation conformsToProtocol:@protocol(HUBContentOperationActionObserver)]) {
            continue;
        }
        
        [(id<HUBContentOperationActionObserver>)operation actionPerformedWithContext:context
                                                                         featureInfo:self.featureInfo
                                                                   connectivityState:self.connectivityState];
    }
}

#pragma mark - Accessor overrides

- (void)setActionPerformer:(nullable id<HUBActionPerformer>)actionPerformer
{
    _actionPerformer = actionPerformer;
    
    [self setActionPerformer:actionPerformer forOperations:self.contentOperations];

}

#pragma mark - HUBViewModelLoader

- (id<HUBViewModel>)initialViewModel
{
    id<HUBViewModel> const cachedInitialViewModel = self.cachedInitialViewModel;
    
    if (cachedInitialViewModel != nil) {
        return cachedInitialViewModel;
    }
    
    HUBViewModelBuilderImplementation * const builder = [self createBuilder];
    
    for (id<HUBContentOperation> const operation in self.contentOperations) {
        if ([operation conformsToProtocol:@protocol(HUBContentOperationWithInitialContent)]) {
            id<HUBContentOperationWithInitialContent> const initialContentOperation = (id<HUBContentOperationWithInitialContent>)operation;
            [initialContentOperation addInitialContentForViewURI:self.viewURI toViewModelBuilder:builder];
        }
    }
    
    id<HUBViewModel> const initialViewModel = [builder build];
    self.cachedInitialViewModel = initialViewModel;
    return initialViewModel;
}

- (BOOL)isLoading
{
    return self.contentOperationQueue.count > 0;
}

- (void)loadViewModel
{
    if (self.contentReloadPolicy != nil) {
        if (self.previouslyLoadedViewModel != nil) {
            id<HUBViewModel> const previouslyLoadedViewModel = self.previouslyLoadedViewModel;
            
            if (![self.contentReloadPolicy shouldReloadContentForViewURI:self.viewURI currentViewModel:previouslyLoadedViewModel]) {
                return;
            }
        }
    }
    
    [self scheduleContentOperationsFromIndex:0 executionMode:HUBContentOperationExecutionModeMain];
}

- (void)loadViewModelRegardlessOfReloadPolicy
{
    [self scheduleContentOperationsFromIndex:0 executionMode:HUBContentOperationExecutionModeMain];
}

- (void)loadNextPageForCurrentViewModel
{
    if (self.previouslyLoadedViewModel == nil) {
        return;
    }
    
    if (!self.anyContentOperationSupportsPagination) {
        return;
    }
    
    [self scheduleContentOperationsFromIndex:0 executionMode:HUBContentOperationExecutionModePagination];
}


#pragma mark - HUBContentOperationWrapperDelegate

- (void)contentOperationWrapperDidFinish:(HUBContentOperationWrapper *)operationWrapper
{
    HUBPerformOnMainQueue(^{
        [self contentOperationWrapperDidFinish:operationWrapper withError:nil];
    });
}

- (void)contentOperationWrapper:(HUBContentOperationWrapper *)operationWrapper didFailWithError:(NSError *)error
{
    HUBPerformOnMainQueue(^{
        [self contentOperationWrapperDidFinish:operationWrapper withError:error];
    });
}

- (void)contentOperationWrapperDidFinish:(HUBContentOperationWrapper *)operationWrapper withError:(nullable NSError *)error
{
    [self.contentOperationQueue removeObjectAtIndex:0];
    self.builderSnapshots[@(operationWrapper.index)] = [self.currentBuilder copy];
    self.errorSnapshots[@(operationWrapper.index)] = error;
    [self performFirstContentOperationInQueue];
}

- (void)contentOperationWrapperRequiresRescheduling:(HUBContentOperationWrapper *)operationWrapper
{
    HUBPerformOnMainQueue(^{
        [self scheduleContentOperationsFromIndex:operationWrapper.index
                                   executionMode:HUBContentOperationExecutionModeMain];
    });
}

- (void)contentOperationWrapperHasNewOperations:(HUBContentOperationWrapper *)operationWrapper operations:(NSArray<id<HUBContentOperation>> *)contentOperations {
    
    HUBContentOperationAppendInfo* appendInfo =
    [[HUBContentOperationAppendInfo alloc] initWithContentOperations:contentOperations forIndex:operationWrapper.index];
    
    HUBPerformOnMainQueue(^{
        [self.contentOperationAppendQueue addObject:appendInfo];
        
        if (!self.isLoading){
            
            [self appendOperations];
        }
       
    });
}

#pragma mark - HUBConnectivityStateResolverObserver

- (void)connectivityStateResolverStateDidChange:(id<HUBConnectivityStateResolver>)resolver
{
    HUBConnectivityState previousConnectivityState = self.connectivityState;
    self.connectivityState = [self.connectivityStateResolver resolveConnectivityState];
    
    if (self.connectivityState != previousConnectivityState) {
        [self.delegate viewModelLoader:self didLoadViewModel:self.initialViewModel];
        
        [self scheduleContentOperationsFromIndex:0
                                   executionMode:HUBContentOperationExecutionModeMain];
    }
}

#pragma mark - Private utilities

- (HUBViewModelBuilderImplementation *)builderForExecutionInfo:(HUBContentOperationExecutionInfo *)executionInfo
{
    if (executionInfo.contentOperationIndex == 0) {
        switch (executionInfo.executionMode) {
            case HUBContentOperationExecutionModeMain:
                return [self createBuilder];
            case HUBContentOperationExecutionModePagination:
                return [self snapshotOfBuilderAtIndex:self.contentOperations.count - 1];
        }
    }
    
    return [self snapshotOfBuilderAtIndex:executionInfo.contentOperationIndex - 1];
}

- (HUBViewModelBuilderImplementation *)snapshotOfBuilderAtIndex:(NSUInteger)index
{
    HUBViewModelBuilderImplementation * const snapshot = self.builderSnapshots[@(index)];
    NSAssert(snapshot != nil, @"Unexpected nil shapshot for content operation at index: %lu", (unsigned long)index);
    return [snapshot copy];
}

- (HUBViewModelBuilderImplementation *)createBuilder
{
    return [[HUBViewModelBuilderImplementation alloc] initWithJSONSchema:self.JSONSchema
                                                       componentDefaults:self.componentDefaults
                                                       iconImageResolver:self.iconImageResolver];
}

- (nullable NSNumber *)pageIndexForExecutionInfo:(HUBContentOperationExecutionInfo *)executionInfo
{
    switch (executionInfo.executionMode) {
        case HUBContentOperationExecutionModeMain:
            return nil;
        case HUBContentOperationExecutionModePagination: {
            if (executionInfo.contentOperationIndex == 0) {
                self.pageIndex++;
            }
            
            return @(self.pageIndex);
        }
    }
}

- (nullable NSError *)previousErrorForExecutionInfo:(HUBContentOperationExecutionInfo *)executionInfo
{
    switch (executionInfo.executionMode) {
        case HUBContentOperationExecutionModeMain: {
            if (executionInfo.contentOperationIndex == 0) {
                return nil;
            }
            
            return self.errorSnapshots[@(executionInfo.contentOperationIndex - 1)];
        }
        case HUBContentOperationExecutionModePagination:
            return self.errorSnapshots[@(executionInfo.contentOperationIndex)];
    }
}

- (void)scheduleContentOperationsFromIndex:(NSUInteger)startIndex
                             executionMode:(HUBContentOperationExecutionMode)executionMode
{
    NSParameterAssert(startIndex < self.contentOperations.count);
    
    NSMutableArray<HUBContentOperationExecutionInfo *> * const appendedQueue = [NSMutableArray new];
    NSUInteger operationIndex = startIndex;
    
    while (operationIndex < self.contentOperations.count) {
        HUBContentOperationExecutionInfo * const executionInfo = [[HUBContentOperationExecutionInfo alloc] initWithContentOperationIndex:operationIndex
                                                                                                                           executionMode:executionMode];
        
        [appendedQueue addObject:executionInfo];
        operationIndex++;
    }
    
    BOOL const shouldRestartQueue = (self.contentOperationQueue.count == 0);
    [self.contentOperationQueue addObjectsFromArray:appendedQueue];
    
    if (shouldRestartQueue) {
        [self performFirstContentOperationInQueue];
    }
}

- (void)performFirstContentOperationInQueue
{
    if (self.contentOperationQueue.count == 0) {
        [self contentOperationQueueDidBecomeEmpty];
        return;
    }
    
    HUBContentOperationExecutionInfo * const executionInfo = self.contentOperationQueue[0];
    HUBContentOperationWrapper * const operation = [self getOrCreateWrapperForContentOperationAtIndex:executionInfo.contentOperationIndex];
    HUBViewModelBuilderImplementation * const builder = [self builderForExecutionInfo:executionInfo];
    NSNumber * const pageIndex = [self pageIndexForExecutionInfo:executionInfo];
    NSError * const previousError = [self previousErrorForExecutionInfo:executionInfo];
    
    self.currentBuilder = builder;
    
    [operation performOperationForViewURI:self.viewURI
                              featureInfo:self.featureInfo
                        connectivityState:self.connectivityState
                         viewModelBuilder:builder
                                pageIndex:pageIndex
                            previousError:previousError];
}

- (void)contentOperationQueueDidBecomeEmpty
{
    id<HUBViewModelLoaderDelegate> const delegate = self.delegate;
    NSError * const error = self.errorSnapshots[@(self.contentOperations.count - 1)];
    
    if (error != nil) {
        [delegate viewModelLoader:self didFailLoadingWithError:error];
        return;
    }
    
    if (!self.currentBuilder.headerComponentModelBuilderExists && self.currentBuilder.navigationBarTitle == nil) {
        self.currentBuilder.navigationBarTitle = self.featureInfo.title;
    }
    
    id<HUBViewModel> const viewModel = [self.currentBuilder build];
    self.previouslyLoadedViewModel = viewModel;
    [delegate viewModelLoader:self didLoadViewModel:viewModel];
    
    [self appendOperations];
}

- (HUBContentOperationWrapper *)getOrCreateWrapperForContentOperationAtIndex:(NSUInteger)operationIndex
{
    HUBContentOperationWrapper * const existingOperationWrapper = self.contentOperationWrappers[@(operationIndex)];
    
    if (existingOperationWrapper != nil) {
        return existingOperationWrapper;
    }
    
    id<HUBContentOperation> const operation = self.contentOperations[operationIndex];
    HUBContentOperationWrapper * const newOperationWrapper = [[HUBContentOperationWrapper alloc] initWithContentOperation:operation index:operationIndex];
    newOperationWrapper.delegate = self;
    self.contentOperationWrappers[@(operationIndex)] = newOperationWrapper;
    
    if ([operation conformsToProtocol:@protocol(HUBContentOperationWithPaginatedContent)]) {
        self.anyContentOperationSupportsPagination = YES;
    }
    
    return newOperationWrapper;
}

- (void)setActionPerformer:(nullable id<HUBActionPerformer>)actionPerformer forOperations:(NSArray<id<HUBContentOperation>> *)operations {
    
        // set action performer for each operation
        for (id<HUBContentOperation> const operation in operations) {
            if (![operation conformsToProtocol:@protocol(HUBContentOperationActionPerformer)]) {
                continue;
            }
            
            ((id<HUBContentOperationActionPerformer>)operation).actionPerformer = self.actionPerformer;
        }
    }
    
/**
 *  Sorts operationAppendInfo in descending order of operation index
 *
 */
- (NSArray<HUBContentOperationAppendInfo *>*)sortedOperationAppendInfo {
        
        NSArray<HUBContentOperationAppendInfo *>* sortedAppendInfo;
        
        if (self.contentOperationAppendQueue.count == 1) {
            
            sortedAppendInfo = self.contentOperationAppendQueue;
        }
        else {
            sortedAppendInfo = [self.contentOperationAppendQueue sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
                NSUInteger first = [(HUBContentOperationAppendInfo*)a contentOperationIndex];
                NSUInteger second = [(HUBContentOperationAppendInfo*)b contentOperationIndex];
                if (first > second){
                    return (NSComparisonResult)NSOrderedAscending;
                }
                else {
                    return (NSComparisonResult)NSOrderedDescending;
                }
            }];
        }
        
        return sortedAppendInfo;
    }
    
    - (NSArray<HUBContentOperationWrapper*>*) sortedOperationWrappers:(NSUInteger)afterIndex
    {
    
        // get all the wrappers with an index > afterIndex
        NSArray<HUBContentOperationWrapper*> *resultArray = [[self.contentOperationWrappers allValues] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"index > %u", afterIndex]];
        
        if (resultArray.count < 2)
        {
            
            return resultArray;
        }
        
        NSArray<HUBContentOperationWrapper*> *sortedOperationWrappers;
        
        sortedOperationWrappers = [resultArray sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
            NSUInteger first = [(HUBContentOperationWrapper*)a index];
            NSUInteger second = [(HUBContentOperationWrapper*)b index];
            if (first > second){
                return (NSComparisonResult)NSOrderedAscending;
            }
            else {
                return (NSComparisonResult)NSOrderedDescending;
            }
        }];
        
        return sortedOperationWrappers;
    
    }

- (void)appendOperations

{
    if (self.contentOperationAppendQueue.count == 0) {
        
        return;
    }
    
    //sort the array in descending order of operation index so that we can shift the
    //original indexes accurately
    
    NSArray<HUBContentOperationAppendInfo *> *sortedAppendInfo = [self sortedOperationAppendInfo];
   
    // last item in array is for the content operaton with the lowest index
    // this is the index from where we'll reschedule operations
    NSUInteger minIndex =  sortedAppendInfo.lastObject.contentOperationIndex;
    
    for (HUBContentOperationAppendInfo* appendInfo in sortedAppendInfo) {
        
        NSUInteger newOperationCount = appendInfo.contentOperations.count;
        
        if (newOperationCount < 1){
            
            continue;
        }
        
        // set action performer for each operation
        [self setActionPerformer:self.actionPerformer forOperations:appendInfo.contentOperations];

        
        NSUInteger operationIndex = appendInfo.contentOperationIndex;
        
        // if operations are to be inserted at an index that doesn't exist
        // currently, just add objects directly
        if ( operationIndex + 1 > self.contentOperations.count-1)
        {
            [[self contentOperations] addObjectsFromArray:appendInfo.contentOperations];
        }
        else
        {
            
            NSIndexSet *indexSet = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(operationIndex + 1, operationIndex + newOperationCount)];
            
            
            // insert new operations
            [[self contentOperations] insertObjects:appendInfo.contentOperations atIndexes:indexSet];
        }
        
        // now change the indexes for contentOperationWrappers
        // get all the wrappers with an index > operationIndex
//        NSArray<HUBContentOperationWrapper*> *resultArray = [[self.contentOperationWrappers allValues] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"index > %u", operationIndex]];
//        
//        NSArray<HUBContentOperationWrapper*> *sortedOperationWrapperArray;
//        sortedOperationWrapperArray = [resultArray sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
//            NSUInteger first = [(HUBContentOperationWrapper*)a index];
//            NSUInteger second = [(HUBContentOperationWrapper*)b index];
//            if (first > second){
//                return (NSComparisonResult)NSOrderedAscending;
//            }
//            else {
//                return (NSComparisonResult)NSOrderedDescending;
//            }
//        }];
        
        NSArray<HUBContentOperationWrapper*> *sortedOperationWrappers = [self sortedOperationWrappers:operationIndex];
        
        //change index and key in operationWrapper
        
        for (HUBContentOperationWrapper* operationWrapper in sortedOperationWrappers) {
            
            [self.contentOperationWrappers removeObjectForKey:@(operationWrapper.index)];
            
            NSUInteger newIndex = operationWrapper.index + newOperationCount;
            
            [operationWrapper updateOperationIndex:newIndex];
            
            self.contentOperationWrappers[@(newIndex)] = operationWrapper;
            
        }
        
        // shift items for builderSnapshots
        [self shiftItemsFor:self.builderSnapshots fromIndex:operationIndex by:newOperationCount];
        
//        // get all the builderSnapshots with an index > operationIndex
//        NSArray<NSNumber *> *filteredBuilderSnapshotKeys = [[self.builderSnapshots allKeys] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self > %u", operationIndex]];
//        
//        NSArray<NSNumber *> *sortedBuilderSnapshotKeys;
//        sortedBuilderSnapshotKeys = [filteredBuilderSnapshotKeys sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
//            NSNumber* first = (NSNumber*)a;
//            NSNumber* second = (NSNumber*)b;
//            if (first > second){
//                return (NSComparisonResult)NSOrderedAscending;
//            }
//            else {
//                return (NSComparisonResult)NSOrderedDescending;
//            }
//        }];
//        
//        
//        for (NSNumber *key in sortedBuilderSnapshotKeys) {
//            
//            NSUInteger keyValue = [key unsignedIntegerValue];
//            
//            NSNumber* index = [NSNumber numberWithUnsignedInteger:keyValue+newOperationCount];
//            
//            HUBViewModelBuilderImplementation * builder = self.builderSnapshots[key];
//            
//            self.builderSnapshots[index] = builder;
//            
//            [self.builderSnapshots removeObjectForKey:index];
//            
//            
//        }
        
        // shift items for errorSnapshots
        [self shiftItemsFor:self.errorSnapshots fromIndex:operationIndex by:newOperationCount];
        
//        // change key for errorSnapshots
//        // get all the builderSnapshots with an index > operationIndex
//        NSArray<NSNumber *> *filteredErrorSnapshotKeys = [[self.errorSnapshots allKeys] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self > %u", operationIndex]];
//        
//        NSArray<NSNumber *> *sortedErrorSnapshotKeys;
//        sortedErrorSnapshotKeys = [filteredErrorSnapshotKeys sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
//            NSNumber* first = (NSNumber*)a;
//            NSNumber* second = (NSNumber*)b;
//            if (first > second){
//                return (NSComparisonResult)NSOrderedAscending;
//            }
//            else {
//                return (NSComparisonResult)NSOrderedDescending;
//            }
//        }];
//        
//        
//        for (NSNumber *key in sortedErrorSnapshotKeys) {
//            
//            NSUInteger keyValue = [key unsignedIntegerValue];
//            
//            NSNumber* index = [NSNumber numberWithUnsignedInteger:keyValue+newOperationCount];
//            
//            NSError * error = self.errorSnapshots[key];
//            
//            self.errorSnapshots[index] = error;
//            
//            [self.errorSnapshots removeObjectForKey:index];
//            
//        }
        
        
    }
    
    [self.contentOperationAppendQueue removeAllObjects];
    [self scheduleContentOperationsFromIndex:minIndex executionMode:HUBContentOperationExecutionModeMain];
    
}

    -(void)shiftItemsFor:(NSMutableDictionary *)dictionary fromIndex:(NSUInteger)index by:(NSUInteger)count {
        
        
        // get all the keys with an index > operationIndex
        NSArray<NSNumber *> *filteredKeys = [[dictionary allKeys] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self > %u", index]];
        
        NSArray<NSNumber *> *sortedKeys;
        sortedKeys = [filteredKeys sortedArrayUsingComparator: descendingKeyComparator];
        
//        sortedKeys = [filteredKeys sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
//            NSNumber* first = (NSNumber*)a;
//            NSNumber* second = (NSNumber*)b;
//            if (first > second){
//                return (NSComparisonResult)NSOrderedAscending;
//            }
//            else {
//                return (NSComparisonResult)NSOrderedDescending;
//            }
//        }];
        
        
        for (NSNumber *key in sortedKeys) {
            
            NSUInteger keyValue = [key unsignedIntegerValue];
            
            NSNumber* newIndex = [NSNumber numberWithUnsignedInteger:keyValue + count];
            
            dictionary[newIndex] = dictionary[key];
            [dictionary removeObjectForKey: key];
            
        }
    }

@end

NS_ASSUME_NONNULL_END
