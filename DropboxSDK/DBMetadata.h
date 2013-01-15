//
//  DBMetadata.h
//  DropboxSDK
//
//  Created by Brian Smith on 5/3/10.
//  Copyright 2010 Dropbox, Inc. All rights reserved.
//


@interface DBMetadata : NSObject <NSCoding>

- (id)initWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionary;

- (DBMetadata *)metadataForFilename:(NSString *)filename;

@property (nonatomic, readonly) BOOL thumbnailExists;
@property (nonatomic, readonly) long long totalBytes;
@property (nonatomic, readonly) NSDate* lastModifiedDate;
@property (nonatomic, readonly) NSDate* clientMtime;
@property (nonatomic, readonly) NSString* path;
@property (nonatomic, readonly) BOOL isDirectory;
@property (nonatomic) NSArray* contents;
@property (nonatomic, readonly) NSString* hash;
@property (nonatomic, readonly) NSString* humanReadableSize;
@property (nonatomic, readonly) NSString* root;
@property (nonatomic, readonly) NSString* icon;
@property (nonatomic, readonly) long long revision; // Deprecated, use rev instead
@property (nonatomic, readonly) NSString* rev;
@property (nonatomic, readonly) BOOL isDeleted;
@property (nonatomic, readonly) NSString* filename;

@end
