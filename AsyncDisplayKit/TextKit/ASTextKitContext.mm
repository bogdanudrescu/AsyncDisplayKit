//
//  ASTextKitContext.mm
//  AsyncDisplayKit
//
//  Copyright (c) 2014-present, Facebook, Inc.  All rights reserved.
//  This source code is licensed under the BSD-style license found in the
//  LICENSE file in the root directory of this source tree. An additional grant
//  of patent rights can be found in the PATENTS file in the same directory.
//

#import "ASTextKitContext.h"
#import "ASLayoutManager.h"

#import <mutex>

@implementation ASTextKitContext
{
  // All TextKit operations (even non-mutative ones) must be executed serially.
  std::mutex _textKitMutex;

  NSLayoutManager *_layoutManager;
  NSTextStorage *_textStorage;
  NSTextContainer *_textContainer;
  
  NSAttributedString *_attributedString;
  ASTextKitContextTextStorageCreationBlock _textStorageCreationBlock;
}

#pragma mark - Lifecycle

- (instancetype)initWithAttributedString:(NSAttributedString *)attributedString
                           lineBreakMode:(NSLineBreakMode)lineBreakMode
                    maximumNumberOfLines:(NSUInteger)maximumNumberOfLines
                          exclusionPaths:(NSArray *)exclusionPaths
                         constrainedSize:(CGSize)constrainedSize
              layoutManagerCreationBlock:(NSLayoutManager * (^)(void))layoutCreationBlock
                   layoutManagerDelegate:(id<NSLayoutManagerDelegate>)layoutManagerDelegate
                textStorageCreationBlock:(ASTextKitContextTextStorageCreationBlock)textStorageCreationBlock

{
  if (self = [super init]) {
    // Concurrently initialising TextKit components crashes (rdar://18448377) so we use a global lock.
    static std::mutex __static_mutex;
    std::lock_guard<std::mutex> l(__static_mutex);
    
    _attributedString = [attributedString copy];
    _textStorageCreationBlock = [textStorageCreationBlock copy];
    
    // Create the TextKit component stack with our default configuration.
    if (textStorageCreationBlock) {
      _textStorage = textStorageCreationBlock(attributedString);
    } else {
      _textStorage = [[NSTextStorage alloc] init];
      [self _resetTextStorage];
    }
    
    
    _layoutManager = layoutCreationBlock ? layoutCreationBlock() : [[ASLayoutManager alloc] init];
    _layoutManager.usesFontLeading = NO;
    _layoutManager.delegate = layoutManagerDelegate;
    [_textStorage addLayoutManager:_layoutManager];

    _textContainer = [[NSTextContainer alloc] initWithSize:constrainedSize];
    // We want the text laid out up to the very edges of the container.
    _textContainer.lineFragmentPadding = 0;
    _textContainer.lineBreakMode = lineBreakMode;
    _textContainer.maximumNumberOfLines = maximumNumberOfLines;
    _textContainer.exclusionPaths = exclusionPaths;
    [_layoutManager addTextContainer:_textContainer];
  }
  return self;
}

#pragma mark - Text Storage

- (void)resetTextStorage
{
  std::lock_guard<std::mutex> l(_textKitMutex);
  [self _resetTextStorage];
}

- (void)_resetTextStorage
{
  if (_textStorageCreationBlock) {
    [_textStorage setAttributedString:_textStorageCreationBlock(_attributedString)];
  } else {
    [_textStorage setAttributedString:_attributedString];
  }
}

#pragma mark - Setter / Getter

- (CGSize)constrainedSize
{
  std::lock_guard<std::mutex> l(_textKitMutex);
  return _textContainer.size;
}

- (void)setConstrainedSize:(CGSize)constrainedSize
{
  std::lock_guard<std::mutex> l(_textKitMutex);
  _textContainer.size = constrainedSize;
}

#pragma mark - Locking

- (void)performBlockWithLockedTextKitComponents:(void (^)(NSLayoutManager *,
                                                          NSTextStorage *,
                                                          NSTextContainer *))block
{
  std::lock_guard<std::mutex> l(_textKitMutex);
  block(_layoutManager, _textStorage, _textContainer);
}

@end
