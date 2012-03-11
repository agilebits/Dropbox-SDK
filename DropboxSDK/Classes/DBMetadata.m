//
//  DBMetadata.m
//  DropboxSDK
//
//  Created by Brian Smith on 5/3/10.
//  Copyright 2010 Dropbox, Inc. All rights reserved.
//

#import "DBMetadata.h"

@implementation DBMetadata

+ (NSDateFormatter*)dateFormatter {
    NSMutableDictionary* dictionary = [[NSThread currentThread] threadDictionary];
    static NSString* dateFormatterKey = @"DBMetadataDateFormatter";
    
    NSDateFormatter* dateFormatter = [dictionary objectForKey:dateFormatterKey];
    if (dateFormatter == nil) {
        dateFormatter = [NSDateFormatter new];
        // Must set locale to ensure consistent parsing:
        // http://developer.apple.com/iphone/library/qa/qa2010/qa1480.html
        dateFormatter.locale = 
            [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        dateFormatter.dateFormat = @"EEE, dd MMM yyyy HH:mm:ss Z";
        [dictionary setObject:dateFormatter forKey:dateFormatterKey];
    }
    return dateFormatter;
}

- (id)initWithDictionary:(NSDictionary*)dict {
    if ((self = [super init])) {
        thumbnailExists = [[dict objectForKey:@"thumb_exists"] boolValue];
        totalBytes = [[dict objectForKey:@"bytes"] longLongValue];

        if ([dict objectForKey:@"modified"]) {
            lastModifiedDate = 
                [[DBMetadata dateFormatter] dateFromString:[dict objectForKey:@"modified"]];
        }

        path = [dict objectForKey:@"path"];
        isDirectory = [[dict objectForKey:@"is_dir"] boolValue];
        
        if ([dict objectForKey:@"contents"]) {
            NSArray* subfileDicts = [dict objectForKey:@"contents"];
            NSMutableArray* mutableContents = 
                [[NSMutableArray alloc] initWithCapacity:[subfileDicts count]];
            for (NSDictionary* subfileDict in subfileDicts) {
                DBMetadata* subfile = [[DBMetadata alloc] initWithDictionary:subfileDict];
                [mutableContents addObject:subfile];
            }
            contents = mutableContents;
        }
        
        hash = [dict objectForKey:@"hash"];
        humanReadableSize = [dict objectForKey:@"size"];
        root = [dict objectForKey:@"root"];
        icon = [dict objectForKey:@"icon"];
        rev = [dict objectForKey:@"rev"];
        revision = [[dict objectForKey:@"revision"] longLongValue];
        isDeleted = [[dict objectForKey:@"is_deleted"] boolValue];
    }
    return self;
}


@synthesize thumbnailExists;
@synthesize totalBytes;
@synthesize lastModifiedDate;
@synthesize path;
@synthesize isDirectory;
@synthesize contents;
@synthesize hash;
@synthesize humanReadableSize;
@synthesize root;
@synthesize icon;
@synthesize rev;
@synthesize revision;
@synthesize isDeleted;

- (BOOL)isEqual:(id)object {
    if (object == self) return YES;
    if (![object isKindOfClass:[DBMetadata class]]) return NO;
    DBMetadata *other = (DBMetadata *)object;
    return [self.rev isEqualToString:other.rev];
}

- (NSString *)filename {
    if (filename == nil) {
        filename = [path lastPathComponent];
    }
    return filename;
}

#pragma mark NSCoding methods

- (id)initWithCoder:(NSCoder*)coder {
    if ((self = [super init])) {
        thumbnailExists = [coder decodeBoolForKey:@"thumbnailExists"];
        totalBytes = [coder decodeInt64ForKey:@"totalBytes"];
        lastModifiedDate = [coder decodeObjectForKey:@"lastModifiedDate"];
        path = [coder decodeObjectForKey:@"path"];
        isDirectory = [coder decodeBoolForKey:@"isDirectory"];
        contents = [coder decodeObjectForKey:@"contents"];
        hash = [coder decodeObjectForKey:@"hash"];
        humanReadableSize = [coder decodeObjectForKey:@"humanReadableSize"];
        root = [coder decodeObjectForKey:@"root"];
        icon = [coder decodeObjectForKey:@"icon"];
        rev = [coder decodeObjectForKey:@"rev"];
        revision = [coder decodeInt64ForKey:@"revision"];
        isDeleted = [coder decodeBoolForKey:@"isDeleted"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder*)coder {
    [coder encodeBool:thumbnailExists forKey:@"thumbnailExists"];
    [coder encodeInt64:totalBytes forKey:@"totalBytes"];
    [coder encodeObject:lastModifiedDate forKey:@"lastModifiedDate"];
    [coder encodeObject:path forKey:@"path"];
    [coder encodeBool:isDirectory forKey:@"isDirectory"];
    [coder encodeObject:contents forKey:@"contents"];
    [coder encodeObject:hash forKey:@"hash"];
    [coder encodeObject:humanReadableSize forKey:@"humanReadableSize"];
    [coder encodeObject:root forKey:@"root"];
    [coder encodeObject:icon forKey:@"icon"];
    [coder encodeObject:rev forKey:@"rev"];
    [coder encodeInt64:revision forKey:@"revision"];
    [coder encodeBool:isDeleted forKey:@"isDeleted"];
}

@end
