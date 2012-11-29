//
//  DBRestClient.h
//  DropboxSDK
//
//  Created by Brian Smith on 4/9/10.
//  Copyright 2010 Dropbox, Inc. All rights reserved.
//


#import "DBSession.h"

@protocol DBRestClientDelegate;

@class DBAccountInfo;
@class DBMetadata;

typedef void (^DBMetadataCompletionBlock)(NSError *error, BOOL changed, DBMetadata *metadata);
typedef void (^DBDeltaCompletionBlock)(NSError *error, NSArray *entryArrays, BOOL shouldReset, NSString *cursor, BOOL hasMore);
typedef void (^DBLoadFileCompletionBlock)(NSError *error, NSString *contentType, DBMetadata *metadata);
typedef void (^DBLoadThumbnailCompletionBlock)(NSError *error, NSString *filename, DBMetadata *metadata);
typedef void (^DBUploadFileCompletionBlock)(NSError *error, DBMetadata *metadata);
typedef void (^DBLoadRevisionsCompletionBlock)(NSError *error, NSArray *revisions);
typedef void (^DBRestoreFileCompletionBlock)(NSError *error, DBMetadata *metadata);
typedef void (^DBMoveFileCompletionBlock)(NSError *error);
typedef void (^DBCopyFileCompletionBlock)(NSError *error);
typedef void (^DBCreateCopyRefCompletionBlock)(NSError *error, NSString *copyRef);
typedef void (^DBCopyFromRefCompletionBlock)(NSError *error, DBMetadata *metadata);
typedef void (^DBDeletePathCompletionBlock)(NSError *error);
typedef void (^DBCreateFolderCompletionBlock)(NSError *error, DBMetadata *metadata);
typedef void (^DBLoadAccountCompletionBlock)(NSError *error, DBAccountInfo *accountInfo);
typedef void (^DBSearchPathCompletionBlock)(NSError *error, NSArray *results);
typedef void (^DBLoadShareableLinkCompletionBlock)(NSError *error, NSString *shareableLink);
typedef void (^DBLoadStreamableURLCompletionBlock)(NSError *error, NSURL *URL);

@interface DBRestClient : NSObject 

@property (nonatomic, weak) id<DBRestClientDelegate> delegate;

@property (nonatomic) NSInteger maxConcurrentRequests;
@property (readonly) BOOL active;
@property (atomic) BOOL canceled;

- (id)initWithSession:(DBSession*)session;
- (id)initWithSession:(DBSession *)session userId:(NSString *)userId;

- (void)submitCompletionSignal;
- (void)waitUntilAllRequestsAreCompleted;

/* Cancels all outstanding requests. No callback for those requests will be sent */
- (void)cancelAllRequests;

/* Loads metadata for the object at the given root/path and returns the result to the delegate as a 
   dictionary */
- (void)loadMetadata:(NSString*)path withHash:(NSString*)hash completion:(DBMetadataCompletionBlock)completion;
- (void)loadMetadata:(NSString*)path completion:(DBMetadataCompletionBlock)completion;

/* This will load the metadata of a file at a given rev */
- (void)loadMetadata:(NSString *)path atRev:(NSString *)rev completion:(DBMetadataCompletionBlock)completion;

/* Loads a list of files (represented as DBDeltaEntry objects) that have changed since the cursor was generated */
- (void)loadDelta:(NSString *)cursor completion:(DBDeltaCompletionBlock)completion;

/* Loads the file contents at the given root/path and stores the result into destinationPath */
- (void)loadFile:(NSString *)path intoPath:(NSString *)destinationPath completion:(DBLoadFileCompletionBlock)completion;

/* This will load a file as it existed at a given rev */
- (void)loadFile:(NSString *)path atRev:(NSString *)rev intoPath:(NSString *)destPath completion:(DBLoadFileCompletionBlock)completion;
- (void)cancelFileLoad:(NSString*)path;


- (void)loadThumbnail:(NSString *)path ofSize:(NSString *)size intoPath:(NSString *)destinationPath completion:(DBLoadThumbnailCompletionBlock)completion;
- (void)cancelThumbnailLoad:(NSString*)path size:(NSString*)size;

/* Uploads a file that will be named filename to the given path on the server. sourcePath is the
   full path of the file you want to upload. If you are modifying a file, parentRev represents the
   rev of the file before you modified it as returned from the server. If you are uploading a new
   file set parentRev to nil. */
- (void)uploadFile:(NSString *)filename toPath:(NSString *)path withParentRev:(NSString *)parentRev fromPath:(NSString *)sourcePath completion:(DBUploadFileCompletionBlock)completion;
- (void)cancelFileUpload:(NSString *)path;

/* Loads a list of up to 10 DBMetadata objects representing past revisions of the file at path */
- (void)loadRevisionsForFile:(NSString *)path completion:(DBLoadRevisionsCompletionBlock)completion;

/* Same as above but with a configurable limit to number of DBMetadata objects returned, up to 1000 */
- (void)loadRevisionsForFile:(NSString *)path limit:(NSInteger)limit completion:(DBLoadRevisionsCompletionBlock)completion;

/* Restores a file at path as it existed at the given rev and returns the metadata of the restored
   file after restoration */
- (void)restoreFile:(NSString *)path toRev:(NSString *)rev completion:(DBRestoreFileCompletionBlock)completion;

/* Creates a folder at the given root/path */
- (void)createFolder:(NSString*)path completion:(DBCreateFolderCompletionBlock)completion;

- (void)deletePath:(NSString*)path completion:(DBDeletePathCompletionBlock)completion;

- (void)copyFrom:(NSString*)from_path toPath:(NSString *)to_path completion:(DBCopyFileCompletionBlock)completion;

- (void)createCopyRef:(NSString *)path completion:(DBCreateCopyRefCompletionBlock)completion; // Used to copy between Dropboxes
- (void)copyFromRef:(NSString*)copyRef toPath:(NSString *)toPath completion:(DBCopyFromRefCompletionBlock)completion; // Takes copy ref created by above call
- (void)moveFrom:(NSString*)from_path toPath:(NSString *)to_path completion:(DBMoveFileCompletionBlock)completion;

- (void)loadAccountInfoWithCompletion:(DBLoadAccountCompletionBlock)completion;
- (void)searchPath:(NSString*)path forKeyword:(NSString*)keyword completion:(DBSearchPathCompletionBlock)completion;
- (void)loadSharableLinkForFile:(NSString *)path completion:(DBLoadShareableLinkCompletionBlock)completion;
- (void)loadStreamableURLForFile:(NSString *)path completion:(DBLoadStreamableURLCompletionBlock)completion;

@end




/* The delegate provides allows the user to get the result of the calls made on the DBRestClient.
   Right now, the error parameter of failed calls may be nil and [error localizedDescription] does
   not contain an error message appropriate to show to the user. */
@protocol DBRestClientDelegate <NSObject>

@optional

- (void)restClient:(DBRestClient*)client loadedMetadata:(DBMetadata*)metadata;
- (void)restClient:(DBRestClient*)client metadataUnchangedAtPath:(NSString*)path;
- (void)restClient:(DBRestClient*)client loadMetadataFailedWithError:(NSError*)error; 
// [error userInfo] contains the root and path of the call that failed

- (void)restClient:(DBRestClient*)client loadedDeltaEntries:(NSArray *)entries reset:(BOOL)shouldReset cursor:(NSString *)cursor hasMore:(BOOL)hasMore;
- (void)restClient:(DBRestClient*)client loadDeltaFailedWithError:(NSError *)error;

- (void)restClient:(DBRestClient*)client loadedAccountInfo:(DBAccountInfo*)info;
- (void)restClient:(DBRestClient*)client loadAccountInfoFailedWithError:(NSError*)error; 

- (void)restClient:(DBRestClient*)client loadedFile:(NSString*)destPath;
// Implement the following callback instead of the previous if you care about the value of the
// Content-Type HTTP header and the file metadata. Only one will be called per successful response.
- (void)restClient:(DBRestClient*)client loadedFile:(NSString*)destPath contentType:(NSString*)contentType metadata:(DBMetadata*)metadata;
- (void)restClient:(DBRestClient*)client loadProgress:(CGFloat)progress forFile:(NSString*)destPath;
- (void)restClient:(DBRestClient*)client loadFileFailedWithError:(NSError*)error;
// [error userInfo] contains the destinationPath


- (void)restClient:(DBRestClient*)client loadedThumbnail:(NSString*)destPath metadata:(DBMetadata*)metadata;
- (void)restClient:(DBRestClient*)client loadThumbnailFailedWithError:(NSError*)error;

- (void)restClient:(DBRestClient*)client uploadedFile:(NSString*)destPath from:(NSString*)srcPath 
        metadata:(DBMetadata*)metadata;
- (void)restClient:(DBRestClient*)client uploadProgress:(CGFloat)progress 
        forFile:(NSString*)destPath from:(NSString*)srcPath;
- (void)restClient:(DBRestClient*)client uploadFileFailedWithError:(NSError*)error;
// [error userInfo] contains the sourcePath

// Deprecated upload callback
- (void)restClient:(DBRestClient*)client uploadedFile:(NSString*)destPath from:(NSString*)srcPath;

// Deprecated download callbacks
- (void)restClient:(DBRestClient*)client loadedFile:(NSString*)destPath contentType:(NSString*)contentType;
- (void)restClient:(DBRestClient*)client loadedThumbnail:(NSString*)destPath;

- (void)restClient:(DBRestClient*)client loadedRevisions:(NSArray *)revisions forFile:(NSString *)path;
- (void)restClient:(DBRestClient*)client loadRevisionsFailedWithError:(NSError *)error;

- (void)restClient:(DBRestClient*)client restoredFile:(DBMetadata *)fileMetadata;
- (void)restClient:(DBRestClient*)client restoreFileFailedWithError:(NSError *)error;

- (void)restClient:(DBRestClient*)client createdFolder:(DBMetadata*)folder;
// Folder is the metadata for the newly created folder
- (void)restClient:(DBRestClient*)client createFolderFailedWithError:(NSError*)error;
// [error userInfo] contains the root and path

- (void)restClient:(DBRestClient*)client deletedPath:(NSString *)path;
// Folder is the metadata for the newly created folder
- (void)restClient:(DBRestClient*)client deletePathFailedWithError:(NSError*)error;
// [error userInfo] contains the root and path

- (void)restClient:(DBRestClient*)client copiedPath:(NSString *)fromPath toPath:(DBMetadata *)to;
- (void)restClient:(DBRestClient*)client copyPathFailedWithError:(NSError*)error;
// [error userInfo] contains the root and path

- (void)restClient:(DBRestClient*)client createdCopyRef:(NSString *)copyRef;
- (void)restClient:(DBRestClient*)client createCopyRefFailedWithError:(NSError *)error;

- (void)restClient:(DBRestClient*)client copiedRef:(NSString *)copyRef to:(DBMetadata *)to;
- (void)restClient:(DBRestClient*)client copyFromRefFailedWithError:(NSError*)error;

- (void)restClient:(DBRestClient*)client movedPath:(NSString *)from_path toPath:(DBMetadata *)result; // Q: result is NSString or DBMetadata?
- (void)restClient:(DBRestClient*)client movePathFailedWithError:(NSError*)error;
// [error userInfo] contains the root and path

- (void)restClient:(DBRestClient*)restClient loadedSearchResults:(NSArray*)results 
forPath:(NSString*)path keyword:(NSString*)keyword;
// results is a list of DBMetadata * objects
- (void)restClient:(DBRestClient*)restClient searchFailedWithError:(NSError*)error;

- (void)restClient:(DBRestClient*)restClient loadedSharableLink:(NSString*)link 
forFile:(NSString*)path;
- (void)restClient:(DBRestClient*)restClient loadSharableLinkFailedWithError:(NSError*)error;

- (void)restClient:(DBRestClient*)restClient loadedStreamableURL:(NSURL*)url forFile:(NSString*)path;
- (void)restClient:(DBRestClient*)restClient loadStreamableURLFailedWithError:(NSError*)error;


@end


