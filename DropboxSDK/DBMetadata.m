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
	NSMutableArray *_contents;
}

@property (nonatomic, strong) NSDictionary * dict;
@property (nonatomic, strong) NSDate * cachedClientMtime;
@end

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

- (id)initWithDictionary:(NSDictionary*)dictionary {
    if ((self = [super init])) {
		_dict = dictionary;
	}

	return self;
}

- (NSDictionary *)dictionary {
	return _dict;
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
	return [[_dict objectForKey:@"thumb_exists"] boolValue];
}

- (long long)totalBytes {
	return [[_dict objectForKey:@"bytes"] longLongValue];
}

- (NSDate *)lastModifiedDate {
	if ([_dict objectForKey:@"modified"]) {
		return [[DBMetadata dateFormatter] dateFromString:[_dict objectForKey:@"modified"]];
	}

	return nil;
}

- (NSDate *)clientMtime {
	if (_cachedClientMtime) return _cachedClientMtime;
	
 	// file's mtime for display purposes only
	if ([_dict objectForKey:@"client_mtime"]) {
		_cachedClientMtime = [[DBMetadata dateFormatter] dateFromString:[_dict objectForKey:@"client_mtime"]];
	}
	
	return _cachedClientMtime;
}

- (NSString *)path {
	return [_dict objectForKey:@"path"];
}

- (BOOL)isDirectory {
	return [[_dict objectForKey:@"is_dir"] boolValue];
}

- (NSArray *)contents {
	if (_contents) return _contents;
	if (![_dict objectForKey:@"contents"]) return nil;

	NSArray *subfileDicts = [_dict objectForKey:@"contents"];
	_contents = [[NSMutableArray alloc] initWithCapacity:[subfileDicts count]];
	for (NSDictionary *subfileDict in subfileDicts) {
		DBMetadata *subfile = [[DBMetadata alloc] initWithDictionary:subfileDict];
		[_contents addObject:subfile];
	}

	return _contents;
}

- (void)setContents:(NSArray *)contents {
	_contents = [contents mutableCopy];
	
	NSMutableArray *dicts = [[NSMutableArray alloc] initWithCapacity:[_contents count]];
	for (DBMetadata *metadata in _contents) {
		[dicts addObject:[metadata dictionary]];
	}
	
	NSMutableDictionary *mutableDict = [_dict mutableCopy];
	mutableDict[@"contents"] = dicts;
	
	_dict = mutableDict;
}

- (NSString *)hash {
	return [_dict objectForKey:@"hash"];
}

- (NSString *)humanReadableSize {
	return [_dict objectForKey:@"size"];
}

- (NSString *)root {
	return [_dict objectForKey:@"root"];
}

- (NSString *)icon {
	return [_dict objectForKey:@"icon"];
}

- (NSString *)rev {
	return [_dict objectForKey:@"rev"];
}

- (long long)revision {
 	// Deprecated; will be removed in version 2. Use rev whenever possible
	return [[_dict objectForKey:@"revision"] longLongValue];
}

- (BOOL)isDeleted {
	return [[_dict objectForKey:@"is_deleted"] boolValue];
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
		_dict = [coder decodeObjectForKey:@"dict"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder*)coder {
	[coder encodeObject:_dict forKey:@"dict"];
}

@end
