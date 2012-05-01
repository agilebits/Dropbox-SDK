//
//  DBMetadata.m
//  DropboxSDK
//
//  Created by Brian Smith on 5/3/10.
//  Copyright 2010 Dropbox, Inc. All rights reserved.
//

#import "DBMetadata.h"

@interface DBMetadata () {
	NSMutableDictionary *_contentsByFilename;
}

@property (nonatomic, strong) NSDictionary *dict;
@end

@implementation DBMetadata

@synthesize dict;

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

- (id)initWithDictionary:(NSDictionary*)dictionary {
    if ((self = [super init])) {
		dict = dictionary;
	}

	return self;
}

- (NSDictionary *)dictionary {
	return dict;
}

- (DBMetadata *)metadataForFilename:(NSString *)filename {
	if (_contentsByFilename == nil) {
		NSArray *contents = [self contents];
		_contentsByFilename = [[NSMutableDictionary alloc] initWithCapacity:(1 + [contents count])];
		for (DBMetadata *m in [self contents]) {
			if (m.filename) [_contentsByFilename setObject:m forKey:m.filename];
		}
	}

	return [_contentsByFilename objectForKey:filename];
}


- (BOOL)thumbnailExists {
	return [[dict objectForKey:@"thumb_exists"] boolValue];
}

- (long long)totalBytes {
	return [[dict objectForKey:@"bytes"] longLongValue];
}

- (NSDate *)lastModifiedDate {
	if ([dict objectForKey:@"modified"]) {
		return [[DBMetadata dateFormatter] dateFromString:[dict objectForKey:@"modified"]];
	}

	return nil;
}

- (NSDate *)clientMtime {
 	// file's mtime for display purposes only
	if ([dict objectForKey:@"client_mtime"]) {
		return [[DBMetadata dateFormatter] dateFromString:[dict objectForKey:@"client_mtime"]];
	}
	return nil;
}

- (NSString *)path {
	return [dict objectForKey:@"path"];
}

- (BOOL)isDirectory {
	return [[dict objectForKey:@"is_dir"] boolValue];
}

- (NSArray *)contents {
	if (![dict objectForKey:@"contents"]) return nil;

	NSArray *subfileDicts = [dict objectForKey:@"contents"];
	NSMutableArray *result = [[NSMutableArray alloc] initWithCapacity:[subfileDicts count]];
	for (NSDictionary *subfileDict in subfileDicts) {
		DBMetadata *subfile = [[DBMetadata alloc] initWithDictionary:subfileDict];
		[result addObject:subfile];
	}

	return result;
}

- (NSString *)hash {
	return [dict objectForKey:@"hash"];
}

- (NSString *)humanReadableSize {
	return [dict objectForKey:@"size"];
}

- (NSString *)root {
	return [dict objectForKey:@"root"];
}

- (NSString *)icon {
	return [dict objectForKey:@"icon"];
}

- (NSString *)rev {
	return [dict objectForKey:@"rev"];
}

- (long long)revision {
 	// Deprecated; will be removed in version 2. Use rev whenever possible
	return [[dict objectForKey:@"revision"] longLongValue];
}

- (BOOL)isDeleted {
	return [[dict objectForKey:@"is_deleted"] boolValue];
}

- (BOOL)isEqual:(id)object {
    if (object == self) return YES;
    if (![object isKindOfClass:[DBMetadata class]]) return NO;
    DBMetadata *other = (DBMetadata *)object;
    return [self.rev isEqualToString:other.rev];
}

- (NSString *)filename {
	return [self.path lastPathComponent];
}

#pragma mark NSCoding methods

- (id)initWithCoder:(NSCoder*)coder {
    if ((self = [super init])) {
		dict = [coder decodeObjectForKey:@"dict"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder*)coder {
	[coder encodeObject:dict forKey:@"dict"];
}

@end
