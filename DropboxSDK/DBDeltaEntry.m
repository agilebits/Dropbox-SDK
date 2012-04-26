//
//  DBDeltaEntry.m
//  DropboxSDK
//
//  Created by Brian Smith on 3/25/12.
//  Copyright (c) 2012 Dropbox, Inc. All rights reserved.
//

#import "DBDeltaEntry.h"

@implementation DBDeltaEntry

@synthesize lowercasePath;
@synthesize metadata;

- (id)initWithArray:(NSArray *)array {
    if ((self = [super init])) {
        lowercasePath = [array objectAtIndex:0];
        NSObject *maybeMetadata = [array objectAtIndex:1];
        if (maybeMetadata != [NSNull null]) {
            metadata = [[DBMetadata alloc] initWithDictionary:[array objectAtIndex:1]];
        }
    }
    return self;
}

@end
