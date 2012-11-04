//
//  DBRestClient.m
//  DropboxSDK
//
//  Created by Brian Smith on 4/9/10.
//  Copyright 2010 Dropbox, Inc. All rights reserved.
//
//	March 2012. Roustem Karimov. Added NSOperationQueue for DBRequests

#import "DBRestClient.h"

#import "DBDeltaEntry.h"
#import "DBAccountInfo.h"
#import "DBError.h"
#import "DBLog.h"
#import "DBMetadata.h"
#import "DBRequest.h"
#import "MPOAuthURLRequest.h"
#import "MPURLRequestParameter.h"
#import "MPOAuthSignatureParameter.h"
#import "NSString+URLEscapingAdditions.h"


@interface DBRestClient () {	
	/* Map from path to the load request. Needs to be expanded to a general framework for cancelling
	 requests. */
	NSMutableDictionary* loadRequests;
	NSMutableDictionary* imageLoadRequests;
	NSMutableDictionary* uploadRequests;
	NSMutableSet *requests;
	
	DBSession* session;
	NSString* userId;
	NSString* root;
	
	NSOperationQueue *requestQueue;
	
	dispatch_semaphore_t _completionSemaphore;
}

	// This method escapes all URI escape characters except /
+ (NSString *)escapePath:(NSString*)path;
+ (NSString *)bestLanguage;
+ (NSString *)userAgent;

- (NSMutableURLRequest*)requestWithHost:(NSString *)host path:(NSString *)path parameters:(NSDictionary *)params;
- (NSMutableURLRequest*)requestWithHost:(NSString *)host path:(NSString *)path parameters:(NSDictionary *)params method:(NSString *)method;

- (void)checkForAuthenticationFailure:(DBRequest*)request;

@property (nonatomic, readonly) MPOAuthCredentialConcreteStore *credentialStore;

@end


@implementation DBRestClient

- (id)initWithSession:(DBSession*)aSession userId:(NSString *)theUserId {
    if (!aSession) {
        DBLogError(@"DropboxSDK: cannot initialize a DBRestClient with a nil session");
        return nil;
    }
	
    if ((self = [super init])) {
        session = aSession;
        userId = theUserId;
        root = aSession.root;
        
		requests = [[NSMutableSet alloc] init];
        loadRequests = [[NSMutableDictionary alloc] init];
        imageLoadRequests = [[NSMutableDictionary alloc] init];
        uploadRequests = [[NSMutableDictionary alloc] init];
		
		requestQueue = [[NSOperationQueue alloc] init];
		requestQueue.name = @"dropbox-request-queue";
		requestQueue.maxConcurrentOperationCount = 8;
		
		_completionSemaphore = dispatch_semaphore_create(0);
    }
    return self;
}

- (id)initWithSession:(DBSession *)aSession {
    NSString *uid = [aSession.userIds count] > 0 ? [aSession.userIds objectAtIndex:0] : nil;
//    NSString *uid = [aSession.userIds count] > 0 ? [aSession.userIds objectAtIndex:0] : kDBDropboxUnknownUserId;
    return [self initWithSession:aSession userId:uid];
}

- (void)dealloc {
	[self cancelAllRequests];
}

- (BOOL)active {
	return [requestQueue operationCount] > 0;
}

- (void)submitCompletionSignal {
	[requestQueue addOperationWithBlock:^{
		dispatch_semaphore_signal(_completionSemaphore);
	}];
}

- (void)waitUntilAllRequestsAreCompleted {
	dispatch_semaphore_wait(_completionSemaphore, DISPATCH_TIME_FOREVER);
	[requestQueue cancelAllOperations]; // Cancel all operations submitted after the completion signal
}

- (void)cancelAllRequests {
	[requestQueue cancelAllOperations];

	@synchronized (requests) {
		for (DBRequest* request in requests) [request cancel];
		[requests removeAllObjects];
	}
	
	@synchronized (loadRequests) {
		for (DBRequest* request in [loadRequests allValues]) [request cancel];
		[loadRequests removeAllObjects];
	}
	
	@synchronized (imageLoadRequests) {
		for (DBRequest* request in [imageLoadRequests allValues]) [request cancel];
		[imageLoadRequests removeAllObjects];
	}
	
	@synchronized (uploadRequests) {
		for (DBRequest* request in [uploadRequests allValues]) [request cancel];
		[uploadRequests removeAllObjects];
	}
	
	if (_completionSemaphore) dispatch_semaphore_signal(_completionSemaphore);
}


- (NSInteger)maxConcurrentRequests {
	return requestQueue.maxConcurrentOperationCount;
}

- (void)setMaxConcurrentRequests:(NSInteger)maxConcurrentRequests {
	requestQueue.maxConcurrentOperationCount = maxConcurrentRequests;
}

//- (DBRequest *)requestWithURLRequest:(NSURLRequest *)urlRequest selector:(SEL)selector {
//    DBRequest* request = [[DBRequest alloc] initWithURLRequest:urlRequest andInformTarget:self selector:selector];
//	[requestQueue addOperation:request];
//	
//	return request;
//}

- (void)loadMetadata:(NSString*)path withParams:(NSDictionary *)params completion:(DBMetadataCompletionBlock)completion {
    NSString* fullPath = [NSString stringWithFormat:@"/metadata/%@%@", root, path];
    NSURLRequest* urlRequest = [self requestWithHost:kDBDropboxAPIHost path:fullPath parameters:params];
    
	DBRequest *operation = [[DBRequest alloc] initWithURLRequest:urlRequest completionBlock:^(DBRequest *request) {
		if (request.statusCode == 304) {
			if ([_delegate respondsToSelector:@selector(restClient:metadataUnchangedAtPath:)]) {
				NSString* path = [request.userInfo objectForKey:@"path"];
				[_delegate restClient:self metadataUnchangedAtPath:path];
			}
			
			if (completion) completion(nil, NO, nil);
		} 
		else if (request.error) {
			[self checkForAuthenticationFailure:request];
			if ([_delegate respondsToSelector:@selector(restClient:loadMetadataFailedWithError:)]) {
				[_delegate restClient:self loadMetadataFailedWithError:request.error];
			}
			
			if (completion) completion(request.error, NO, nil);
		} 
		else {
			NSDictionary* result = (NSDictionary*)[request resultJSON];
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
				DBMetadata* metadata = [[DBMetadata alloc] initWithDictionary:result];
				if (metadata) {
					if ([_delegate respondsToSelector:@selector(restClient:loadedMetadata:)]) {
						[_delegate restClient:self loadedMetadata:metadata];
					}
					
					if (completion) completion(nil, YES, metadata);
				}
				else {
					NSError *error = [NSError errorWithDomain:DBErrorDomain code:DBErrorInvalidResponse userInfo:request.userInfo];
					DBLogWarning(@"DropboxSDK: error parsing metadata");
					if ([_delegate respondsToSelector:@selector(restClient:loadMetadataFailedWithError:)]) {
						[_delegate restClient:self loadMetadataFailedWithError:error];
					}
					
					if (completion) completion(error, NO, nil);
				}
			});
		}
		
		@synchronized (requests) {
			[requests removeObject:request];
		}
	}];
	
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:path forKey:@"path"];
    if (params) [userInfo addEntriesFromDictionary:params];
    operation.userInfo = userInfo;
	
	@synchronized (requests) {
		[requests addObject:operation];
	}
	
	[requestQueue addOperation:operation];
}

- (void)loadMetadata:(NSString*)path completion:(DBMetadataCompletionBlock)completion {
    [self loadMetadata:path withParams:nil completion:completion];
}

- (void)loadMetadata:(NSString*)path withHash:(NSString*)hash completion:(DBMetadataCompletionBlock)completion {
    NSDictionary *params = (hash ? [NSDictionary dictionaryWithObject:hash forKey:@"hash"] : nil);
    [self loadMetadata:path withParams:params completion:completion];
}

- (void)loadMetadata:(NSString *)path atRev:(NSString *)rev completion:(DBMetadataCompletionBlock)completion {
    NSDictionary *params = (rev ? [NSDictionary dictionaryWithObject:rev forKey:@"rev"] : nil);
    [self loadMetadata:path withParams:params completion:completion];
}


- (void)loadDelta:(NSString *)cursor completion:(DBDeltaCompletionBlock)completion
{
    NSDictionary *params = cursor ? [NSDictionary dictionaryWithObject:cursor forKey:@"cursor"] : nil;
    NSString *fullPath = [NSString stringWithFormat:@"/delta"];
    NSMutableURLRequest *urlRequest = [self requestWithHost:kDBDropboxAPIHost path:fullPath parameters:params method:@"POST"];
	
    DBRequest* operation = [[DBRequest alloc] initWithURLRequest:urlRequest completionBlock:^(DBRequest *request) {
		if (request.error) {
			[self checkForAuthenticationFailure:request];
			if ([_delegate respondsToSelector:@selector(restClient:loadDeltaFailedWithError:)]) {
				[_delegate restClient:self loadDeltaFailedWithError:request.error];
			}
			
			if (completion) completion(request.error, nil, NO, nil, NO);
		}
		else {
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
				NSDictionary* result = [request parseResponseAsType:[NSDictionary class]];
				if (result) {
					NSArray *entryArrays = [result objectForKey:@"entries"];
					NSMutableArray *entries = [NSMutableArray arrayWithCapacity:[entryArrays count]];
					for (NSArray *entryArray in entryArrays) {
						DBDeltaEntry *entry = [[DBDeltaEntry alloc] initWithArray:entryArray];
						[entries addObject:entry];
					}
					BOOL reset = [[result objectForKey:@"reset"] boolValue];
					NSString *cursor = [result objectForKey:@"cursor"];
					BOOL hasMore = [[result objectForKey:@"has_more"] boolValue];
					
					if ([_delegate respondsToSelector:@selector(restClient:loadedDeltaEntries:reset:cursor:hasMore:)]) {
						[_delegate restClient:self loadedDeltaEntries:entryArrays reset:reset cursor:cursor hasMore:hasMore];
					}
					
					if (completion) completion(nil, entryArrays, reset, cursor, hasMore);
				} 
				else {
					NSError *error = [NSError errorWithDomain:DBErrorDomain code:DBErrorInvalidResponse userInfo:request.userInfo];
					DBLogWarning(@"DropboxSDK: error parsing metadata");
					if ([_delegate respondsToSelector:@selector(restClient:loadDeltaFailedWithError:)]) {
						[_delegate restClient:self loadDeltaFailedWithError:error];
					}
					if (completion) completion(request.error, nil, NO, nil, NO);
				}
			});
		}
		
		@synchronized (requests) {
			[requests removeObject:request];
		}
	}];
	
    operation.userInfo = params;
	
	@synchronized (requests) {
		[requests addObject:operation];
	}
	
	[requestQueue addOperation:operation];
}


- (void)loadFile:(NSString *)path atRev:(NSString *)rev intoPath:(NSString *)destPath completion:(DBLoadFileCompletionBlock)completion
{
    NSString* fullPath = [NSString stringWithFormat:@"/files/%@%@", root, path];
    NSDictionary *params = rev ? [NSDictionary dictionaryWithObject:rev forKey:@"rev"] : nil;
    
    NSURLRequest* urlRequest = [self requestWithHost:kDBDropboxAPIContentHost path:fullPath parameters:params];
	
	DBRequest *operation = [[DBRequest alloc] initWithURLRequest:urlRequest completionBlock:^(DBRequest *request) {
		NSString* path = [[request.userInfo objectForKey:@"path"] copy];
		
		if (request.error) {
			[self checkForAuthenticationFailure:request];
			if ([_delegate respondsToSelector:@selector(restClient:loadFileFailedWithError:)]) {
				[_delegate restClient:self loadFileFailedWithError:request.error];
			}
			
			if (completion) completion(request.error, nil, nil);
		} 
		else {
			NSString* filename = [request.resultFilename copy];
			NSDictionary* headers = [[request.response allHeaderFields] copy];
			NSString* contentType = [[headers objectForKey:@"Content-Type"] copy];
			NSDictionary* metadataDict = [[request xDropboxMetadataJSON] copy];
			NSString* eTag = [[headers objectForKey:@"Etag"] copy];
			DBRestClient *myself = self;
			
			if ([_delegate respondsToSelector:@selector(restClient:loadedFile:)]) {
				[_delegate restClient:self loadedFile:filename];
			} 
			else if ([_delegate respondsToSelector:@selector(restClient:loadedFile:contentType:metadata:)]) {
				DBMetadata* metadata = metadataDict ? [[DBMetadata alloc] initWithDictionary:metadataDict] : nil;
				[_delegate restClient:self loadedFile:filename contentType:contentType metadata:metadata];
			} 
			else if ([_delegate respondsToSelector:@selector(restClient:loadedFile:contentType:)]) {
				// This callback is deprecated and this block exists only for backwards compatibility.
				[_delegate restClient:self loadedFile:filename contentType:contentType];
			} 
			else if ([_delegate respondsToSelector:@selector(restClient:loadedFile:contentType:eTag:)]) {
				// This code is for the official Dropbox client to get eTag information from the server
				NSMethodSignature* signature = [self methodSignatureForSelector:@selector(restClient:loadedFile:contentType:eTag:)];
				NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:signature];
				
				[invocation setTarget:_delegate];
				[invocation setSelector:@selector(restClient:loadedFile:contentType:eTag:)];
				[invocation setArgument:&myself atIndex:2];
				[invocation setArgument:&filename atIndex:3];
				[invocation setArgument:&contentType atIndex:4];
				[invocation setArgument:&eTag atIndex:5];
				[invocation invoke];
			}
			
			if (completion) {
				DBMetadata* metadata = [[DBMetadata alloc] initWithDictionary:metadataDict];
				completion(nil, contentType, metadata);
			}
		}
		
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
			@synchronized (loadRequests) {
				[loadRequests removeObjectForKey:path];
			}
		});
	}];
	

    operation.resultFilename = destPath;
    operation.downloadProgressBlock = ^(DBRequest *r) {
		if ([_delegate respondsToSelector:@selector(restClient:loadProgress:forFile:)]) {
			[_delegate restClient:self loadProgress:operation.downloadProgress forFile:[r.resultFilename copy]];
		}
	};
	
    operation.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:path, @"path", destPath, @"destinationPath", rev, @"rev", nil];
    
	@synchronized (loadRequests) {
		[loadRequests setObject:operation forKey:path];
	}
	
	[requestQueue addOperation:operation];
}

- (void)loadFile:(NSString *)path intoPath:(NSString *)destPath completion:(DBLoadFileCompletionBlock)completion {
    [self loadFile:path atRev:nil intoPath:destPath completion:completion];
}

- (void)cancelFileLoad:(NSString *)path {
	@synchronized (loadRequests) {
		DBRequest *outstandingRequest = [loadRequests objectForKey:path];
		if (outstandingRequest) {
			[outstandingRequest cancel];
			[loadRequests removeObjectForKey:path];
		}
	}
}

- (void)restClient:(DBRestClient*)restClient loadedFile:(NSString*)destPath contentType:(NSString*)contentType eTag:(NSString*)eTag {
		// Empty selector to get the signature from
}



- (NSString*)thumbnailKeyForPath:(NSString*)path size:(NSString*)size {
    return [NSString stringWithFormat:@"%@##%@", path, size];
}


- (void)loadThumbnail:(NSString *)path ofSize:(NSString *)size intoPath:(NSString *)destinationPath completion:(DBLoadThumbnailCompletionBlock)completion {
    NSString* fullPath = [NSString stringWithFormat:@"/thumbnails/%@%@", root, path];
    
    NSString* format = @"JPEG";
    if ([path length] > 4) {
        NSString* extension = [[path substringFromIndex:[path length] - 4] uppercaseString];
        if ([[NSSet setWithObjects:@".PNG", @".GIF", nil] containsObject:extension]) {
            format = @"PNG";
        }
    }
    
    NSMutableDictionary* params = [NSMutableDictionary dictionaryWithObject:format forKey:@"format"];
    if (size) [params setObject:size forKey:@"size"];

    
    NSURLRequest* urlRequest = [self requestWithHost:kDBDropboxAPIContentHost path:fullPath parameters:params];
	DBRequest *operation = [[DBRequest alloc] initWithURLRequest:urlRequest completionBlock:^(DBRequest *request) {
		if (request.error) {
			[self checkForAuthenticationFailure:request];
			if ([_delegate respondsToSelector:@selector(restClient:loadThumbnailFailedWithError:)]) {
				[_delegate restClient:self loadThumbnailFailedWithError:request.error];
			}
			
			if (completion) completion(request.error, nil, nil);
		}
		else {
			NSString* filename = request.resultFilename;
			NSDictionary* metadataDict = [request xDropboxMetadataJSON];
			DBMetadata* metadata = [[DBMetadata alloc] initWithDictionary:metadataDict];

			if ([_delegate respondsToSelector:@selector(restClient:loadedThumbnail:metadata:)]) {
				[_delegate restClient:self loadedThumbnail:filename metadata:metadata];
			}
			else if ([_delegate respondsToSelector:@selector(restClient:loadedThumbnail:)]) {
				// This callback is deprecated and this block exists only for backwards compatibility.
				[_delegate restClient:self loadedThumbnail:filename];
			}
			
			if (completion) completion(nil, filename, metadata);
		}
		
		NSString* path = [request.userInfo objectForKey:@"path"];
		NSString* size = [request.userInfo objectForKey:@"size"];
		
		@synchronized (imageLoadRequests) {
			[imageLoadRequests removeObjectForKey:[self thumbnailKeyForPath:path size:size]];
		}
	}];
	
    operation.resultFilename = destinationPath;
    operation.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:root, @"root", path, @"path", destinationPath, @"destinationPath", size, @"size", nil];
	
	@synchronized (imageLoadRequests) {
		[imageLoadRequests setObject:operation forKey:[self thumbnailKeyForPath:path size:size]];
	}
	
	[requestQueue addOperation:operation];
}

- (void)cancelThumbnailLoad:(NSString*)path size:(NSString*)size {
    NSString* key = [self thumbnailKeyForPath:path size:size];
	@synchronized (imageLoadRequests) {
		DBRequest* request = [imageLoadRequests objectForKey:key];
		if (request) {
			[request cancel];
			[imageLoadRequests removeObjectForKey:key];
		}
	}
}

- (NSString *)signatureForParams:(NSArray *)params url:(NSURL *)baseUrl {
    NSArray* paramList = [params sortedArrayUsingSelector:@selector(compare:)];
    NSString* paramString = [MPURLRequestParameter parameterStringForParameters:paramList];
    
    MPOAuthURLRequest* oauthRequest = [[MPOAuthURLRequest alloc] initWithURL:baseUrl andParameters:paramList];
    oauthRequest.HTTPMethod = @"POST";
 
	MPOAuthSignatureParameter *signatureParameter = [[MPOAuthSignatureParameter alloc] initWithText:paramString andSecret:self.credentialStore.signingKey forRequest:oauthRequest usingMethod:self.credentialStore.signatureMethod];
    return [signatureParameter URLEncodedParameterString];
}

- (NSMutableURLRequest *)requestForParams:(NSArray *)params urlString:(NSString *)urlString signature:(NSString *)sig {
	
    NSMutableArray *paramList = [NSMutableArray arrayWithArray:params];
		// Then rebuild request using that signature
    [paramList sortUsingSelector:@selector(compare:)];
    NSMutableString* realParamString = [[NSMutableString alloc] initWithString:
										 [MPURLRequestParameter parameterStringForParameters:paramList]];
    [realParamString appendFormat:@"&%@", sig];
    
    NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:@"%@?%@", urlString, realParamString]];
    NSMutableURLRequest* urlRequest = [NSMutableURLRequest requestWithURL:url];
    urlRequest.HTTPMethod = @"POST";
	
    return urlRequest;
}

- (void)uploadFile:(NSString*)filename toPath:(NSString*)path fromPath:(NSString *)sourcePath params:(NSDictionary *)params completion:(DBUploadFileCompletionBlock)completion 
{
    BOOL isDir = NO;
    BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:sourcePath isDirectory:&isDir];
    NSDictionary *fileAttrs = [[NSFileManager defaultManager] attributesOfItemAtPath:sourcePath error:nil];
	
    if (!fileExists || isDir || !fileAttrs) {
        NSString* destPath = [path stringByAppendingPathComponent:filename];
        NSDictionary* userInfo = [NSDictionary dictionaryWithObjectsAndKeys:sourcePath, @"sourcePath", destPath, @"destinationPath", nil];
        NSInteger errorCode = isDir ? DBErrorIllegalFileType : DBErrorFileNotFound;
        NSError* error = [NSError errorWithDomain:DBErrorDomain code:errorCode userInfo:userInfo];
        NSString *errorMsg = isDir ? @"Unable to upload folders" : @"File does not exist";
        
		DBLogWarning(@"DropboxSDK: %@ (%@)", errorMsg, sourcePath);

        if ([_delegate respondsToSelector:@selector(restClient:uploadFileFailedWithError:)]) {
            [_delegate restClient:self uploadFileFailedWithError:error];
        }
		
		if (completion) completion(error, nil);
        return;
    }
	
    NSString *destPath = [path stringByAppendingPathComponent:filename];
    NSString *urlString = [NSString stringWithFormat:@"%@://%@/%@/files_put/%@%@", kDBProtocolHTTPS, kDBDropboxAPIContentHost, kDBDropboxAPIVersion, root, [DBRestClient escapePath:destPath]];
    
    NSArray *extraParams = [MPURLRequestParameter parametersFromDictionary:params];
    NSArray *paramList = [[self.credentialStore oauthParameters] arrayByAddingObjectsFromArray:extraParams];
    NSString *sig = [self signatureForParams:paramList url:[NSURL URLWithString:urlString]];
    NSMutableURLRequest *urlRequest = [self requestForParams:paramList urlString:urlString signature:sig];
    
    NSString* contentLength = [NSString stringWithFormat: @"%qu", [fileAttrs fileSize]];
    [urlRequest addValue:contentLength forHTTPHeaderField: @"Content-Length"];
    [urlRequest addValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
    
    [urlRequest setHTTPBodyStream:[NSInputStream inputStreamWithFileAtPath:sourcePath]];
    
	
	DBRequest *operation = [[DBRequest alloc] initWithURLRequest:urlRequest completionBlock:^(DBRequest *request) {
		NSDictionary *result = [request parseResponseAsType:[NSDictionary class]];
		
		if (!result) {
			[self checkForAuthenticationFailure:request];
			if ([_delegate respondsToSelector:@selector(restClient:uploadFileFailedWithError:)]) {
				[_delegate restClient:self uploadFileFailedWithError:request.error];
			}
			if (completion) completion(request.error, nil);
		} 
		else {
			DBMetadata *metadata = [[DBMetadata alloc] initWithDictionary:result];
			
			NSString* sourcePath = [request.userInfo objectForKey:@"sourcePath"];
			NSString* destPath = [request.userInfo objectForKey:@"destinationPath"];
			
			if ([_delegate respondsToSelector:@selector(restClient:uploadedFile:from:metadata:)]) {
				[_delegate restClient:self uploadedFile:destPath from:sourcePath metadata:metadata];
			}
			else if ([_delegate respondsToSelector:@selector(restClient:uploadedFile:from:)]) {
				[_delegate restClient:self uploadedFile:destPath from:sourcePath];
			}
			
			if (completion) completion(nil, metadata);
		}
		
		@synchronized (uploadRequests) {
			[uploadRequests removeObjectForKey:[request.userInfo objectForKey:@"destinationPath"]];
		}
	}];
	
    operation.uploadProgressBlock = ^(DBRequest *r) {
		NSString* sourcePath = [(NSDictionary*)operation.userInfo objectForKey:@"sourcePath"];
		NSString* destPath = [operation.userInfo objectForKey:@"destinationPath"];
		
		if ([_delegate respondsToSelector:@selector(restClient:uploadProgress:forFile:from:)]) {
			[_delegate restClient:self uploadProgress:operation.uploadProgress forFile:destPath from:sourcePath];
		}
	};
	
    operation.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:sourcePath, @"sourcePath", destPath, @"destinationPath", nil];
    
	@synchronized (uploadRequests) {
		[uploadRequests setObject:operation forKey:destPath];
	}
	
	[requestQueue addOperation:operation];
}

- (void)uploadFile:(NSString *)filename toPath:(NSString *)path withParentRev:(NSString *)parentRev fromPath:(NSString *)sourcePath completion:(DBUploadFileCompletionBlock)completion  {
	
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithObject:@"false" forKey:@"overwrite"];
    if (parentRev) {
        [params setObject:parentRev forKey:@"parent_rev"];
    }
    [self uploadFile:filename toPath:path fromPath:sourcePath params:params completion:completion];
}


- (void)cancelFileUpload:(NSString *)path {
	@synchronized (uploadRequests) {
		DBRequest *request = [uploadRequests objectForKey:path];
		if (request) {
			[request cancel];
			[uploadRequests removeObjectForKey:path];
		}
	}
}


- (void)loadRevisionsForFile:(NSString *)path completion:(DBLoadRevisionsCompletionBlock)completion {
    [self loadRevisionsForFile:path limit:10 completion:completion];
}

- (void)loadRevisionsForFile:(NSString *)path limit:(NSInteger)limit completion:(DBLoadRevisionsCompletionBlock)completion {
    NSString *fullPath = [NSString stringWithFormat:@"/revisions/%@%@", root, path];
    NSString *limitStr = [NSString stringWithFormat:@"%jd", (intmax_t)limit];
    NSDictionary *params = [NSDictionary dictionaryWithObject:limitStr forKey:@"rev_limit"];
    NSURLRequest* urlRequest = [self requestWithHost:kDBDropboxAPIHost path:fullPath parameters:params];
    
	DBRequest *operation = [[DBRequest alloc] initWithURLRequest:urlRequest completionBlock:^(DBRequest *request) {
		NSArray *resp = [request parseResponseAsType:[NSArray class]];
		
		if (!resp) {
			if ([_delegate respondsToSelector:@selector(restClient:loadRevisionsFailedWithError:)]) {
				[_delegate restClient:self loadRevisionsFailedWithError:request.error];
			}
			
			if (completion) completion(request.error, nil);
		}
		else {
			NSMutableArray *revisions = [NSMutableArray arrayWithCapacity:[resp count]];
			for (NSDictionary *dict in resp) {
				DBMetadata *metadata = [[DBMetadata alloc] initWithDictionary:dict];
				[revisions addObject:metadata];
			}
			
			NSString *path = [request.userInfo objectForKey:@"path"];
			
			if ([_delegate respondsToSelector:@selector(restClient:loadedRevisions:forFile:)]) {
				[_delegate restClient:self loadedRevisions:revisions forFile:path];
			}
			
			if (completion) completion(nil, revisions);
		}
		
		@synchronized (requests) {
			[requests removeObject:request];
		}
	}];
	
    operation.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:path, @"path", [NSNumber numberWithInt:limit], @"limit", nil];
	
	@synchronized (requests) {
		[requests addObject:operation];
	}
	
	[requestQueue addOperation:operation];
}


- (void)restoreFile:(NSString *)path toRev:(NSString *)rev completion:(DBRestoreFileCompletionBlock)completion
{
    NSString *fullPath = [NSString stringWithFormat:@"/restore/%@%@", root, path];
    NSDictionary *params = [NSDictionary dictionaryWithObject:rev forKey:@"rev"];
    NSURLRequest* urlRequest = [self requestWithHost:kDBDropboxAPIHost path:fullPath parameters:params];
    
	DBRequest *operation = [[DBRequest alloc] initWithURLRequest:urlRequest completionBlock:^(DBRequest *request) {
		NSDictionary *dict = [request parseResponseAsType:[NSDictionary class]];
		
		if (!dict) {
			if ([_delegate respondsToSelector:@selector(restClient:restoreFileFailedWithError:)]) {
				[_delegate restClient:self restoreFileFailedWithError:request.error];
			}
			if (completion) completion(request.error, nil);
		}
		else {
			DBMetadata *metadata = [[DBMetadata alloc] initWithDictionary:dict];
			if ([_delegate respondsToSelector:@selector(restClient:restoredFile:)]) {
				[_delegate restClient:self restoredFile:metadata];
			}
			if (completion) completion(nil, metadata);
		}
		
		@synchronized (requests) {
			[requests removeObject:request];
		}
	}];
	
    operation.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:path, @"path", rev, @"rev", nil];
	
	@synchronized (requests) {
		[requests addObject:operation];
	}
	
	[requestQueue addOperation:operation];
}


- (void)moveFrom:(NSString*)from_path toPath:(NSString *)to_path completion:(DBMoveFileCompletionBlock)completion
{
    NSDictionary* params = [NSDictionary dictionaryWithObjectsAndKeys:root, @"root", from_path, @"from_path", to_path, @"to_path", nil];
    NSMutableURLRequest* urlRequest = [self requestWithHost:kDBDropboxAPIHost path:@"/fileops/move" parameters:params method:@"POST"];
	
	DBRequest *operation = [[DBRequest alloc] initWithURLRequest:urlRequest completionBlock:^(DBRequest *request) {
		if (request.error) {
			[self checkForAuthenticationFailure:request];
			if ([_delegate respondsToSelector:@selector(restClient:movePathFailedWithError:)]) {
				[_delegate restClient:self movePathFailedWithError:request.error];
			}
			
			if (completion) completion(request.error);
		} 
		else {
			NSDictionary *params = (NSDictionary *)request.userInfo;
			
			if ([_delegate respondsToSelector:@selector(restClient:movedPath:toPath:)]) {
				[_delegate restClient:self movedPath:[params valueForKey:@"from_path"] toPath:[params valueForKey:@"to_path"]];
			}
			
			if (completion) completion(nil);
		}
		
		@synchronized (requests) {
			[requests removeObject:request];
		}
	}];
	
	@synchronized (requests) {
		[requests addObject:operation];
	}
	
	[requestQueue addOperation:operation];
}


- (void)copyFrom:(NSString*)from_path toPath:(NSString *)to_path completion:(DBCopyFileCompletionBlock)completion
{
    NSDictionary* params = [NSDictionary dictionaryWithObjectsAndKeys:root, @"root", from_path, @"from_path", to_path, @"to_path", nil];
    NSMutableURLRequest* urlRequest = [self requestWithHost:kDBDropboxAPIHost path:@"/fileops/copy" parameters:params method:@"POST"];
	
	DBRequest *operation = [[DBRequest alloc] initWithURLRequest:urlRequest completionBlock:^(DBRequest *request) {
		if (request.error) {
			[self checkForAuthenticationFailure:request];
			if ([_delegate respondsToSelector:@selector(restClient:copyPathFailedWithError:)]) {
				[_delegate restClient:self copyPathFailedWithError:request.error];
			}
			
			if (completion) completion(request.error);
		}
		else {
			NSDictionary *params = (NSDictionary *)request.userInfo;
			
			if ([_delegate respondsToSelector:@selector(restClient:copiedPath:toPath:)]) {
				[_delegate restClient:self copiedPath:[params valueForKey:@"from_path"] toPath:[params valueForKey:@"to_path"]];
			}
			
			if (completion) completion(nil);
		}
		
		@synchronized (requests) {
			[requests removeObject:request];
		}
	}];
	
    operation.userInfo = params;

	@synchronized (requests) {
		[requests addObject:operation];
	}
	
	[requestQueue addOperation:operation];
}


- (void)createCopyRef:(NSString *)path completion:(DBCreateCopyRefCompletionBlock)completion
{
    NSString *fullPath = [NSString stringWithFormat:@"/copy_ref/%@%@", root, path];
    NSMutableURLRequest* urlRequest = [self requestWithHost:kDBDropboxAPIHost path:fullPath parameters:nil method:@"POST"];
	
	DBRequest *operation = [[DBRequest alloc] initWithURLRequest:urlRequest completionBlock:^(DBRequest *request) {
		NSDictionary *result = [request parseResponseAsType:[NSDictionary class]];
		if (!result) {
			[self checkForAuthenticationFailure:request];
			if ([_delegate respondsToSelector:@selector(restClient:createCopyRefFailedWithError:)]) {
				[_delegate restClient:self createCopyRefFailedWithError:request.error];
			}
			
			if (completion) completion(request.error, nil);
		}
		else {
			NSString *copyRef = [result objectForKey:@"copy_ref"];
			if ([_delegate respondsToSelector:@selector(restClient:createdCopyRef:)]) {
				[_delegate restClient:self createdCopyRef:copyRef];
			}
			
			if (completion) completion(nil, copyRef);
		}

		@synchronized (requests) {
			[requests removeObject:request];
		}
	}];
    
    operation.userInfo = [NSDictionary dictionaryWithObject:path forKey:@"path"];
	
	@synchronized (requests) {
		[requests addObject:operation];
	}
	
	[requestQueue addOperation:operation];
}


- (void)copyFromRef:(NSString*)copyRef toPath:(NSString *)toPath completion:(DBCopyFromRefCompletionBlock)completion {
    static NSString *fullPath = @"/fileops/copy/";
	NSDictionary *params = [NSDictionary dictionaryWithObjectsAndKeys:copyRef, @"from_copy_ref", root, @"root", toPath, @"to_path", nil];
    NSMutableURLRequest* urlRequest = [self requestWithHost:kDBDropboxAPIHost path:fullPath parameters:params method:@"POST"];
	
	DBRequest *operation = [[DBRequest alloc] initWithURLRequest:urlRequest completionBlock:^(DBRequest *request) {
		NSDictionary *result = [request parseResponseAsType:[NSDictionary class]];
		if (!result) {
			[self checkForAuthenticationFailure:request];
			if ([_delegate respondsToSelector:@selector(restClient:copyFromRefFailedWithError:)]) {
				[_delegate restClient:self copyFromRefFailedWithError:request.error];
			}
			
			if (completion) completion(request.error, nil);
		}
		else {
			NSString *copyRef = [request.userInfo objectForKey:@"from_copy_ref"];
			DBMetadata *metadata = [[DBMetadata alloc] initWithDictionary:result];
			if ([_delegate respondsToSelector:@selector(restClient:copiedRef:to:)]) {
				[_delegate restClient:self copiedRef:copyRef to:metadata];
			}
			
			if (completion) completion(nil, metadata);
		}
		
		@synchronized (requests) {
			[requests removeObject:request];
		}
	}];
	
    operation.userInfo = params;
	
	@synchronized (requests) {
		[requests addObject:operation];
	}
	
	[requestQueue addOperation:operation];
}



- (void)deletePath:(NSString*)path completion:(DBDeletePathCompletionBlock)completion {
    NSDictionary* params = [NSDictionary dictionaryWithObjectsAndKeys:root, @"root", path, @"path", nil];
    NSMutableURLRequest* urlRequest = [self requestWithHost:kDBDropboxAPIHost path:@"/fileops/delete" parameters:params method:@"POST"];
	
	DBRequest *operation = [[DBRequest alloc] initWithURLRequest:urlRequest completionBlock:^(DBRequest *request) {
		if (request.error) {
			[self checkForAuthenticationFailure:request];
			if ([_delegate respondsToSelector:@selector(restClient:deletePathFailedWithError:)]) {
				[_delegate restClient:self deletePathFailedWithError:request.error];
			}
			
			if (completion) completion(request.error);
		}
		else {
			if ([_delegate respondsToSelector:@selector(restClient:deletedPath:)]) {
				NSString* path = [request.userInfo objectForKey:@"path"];
				[_delegate restClient:self deletedPath:path];
			}
			
			if (completion) completion(nil);
		}
		
		@synchronized (requests) {
			[requests removeObject:request];
		}
	}];
	
    operation.userInfo = params;
	
	@synchronized (requests) {
		[requests addObject:operation];
	}
	
	[requestQueue addOperation:operation];
}


- (void)createFolder:(NSString*)path completion:(DBCreateFolderCompletionBlock)completion
{
    static NSString *fullPath = @"/fileops/create_folder";
    NSDictionary *params = [NSDictionary dictionaryWithObjectsAndKeys:root, @"root", path, @"path", nil];
    NSMutableURLRequest* urlRequest = [self requestWithHost:kDBDropboxAPIHost path:fullPath parameters:params method:@"POST"];
	
	DBRequest *operation = [[DBRequest alloc] initWithURLRequest:urlRequest completionBlock:^(DBRequest *request) {
		if (request.error) {
			[self checkForAuthenticationFailure:request];
			if ([_delegate respondsToSelector:@selector(restClient:createFolderFailedWithError:)]) {
				[_delegate restClient:self createFolderFailedWithError:request.error];
			}
			
			if (completion) completion(request.error, nil);
		}
		else {
			NSDictionary* result = (NSDictionary *)[request resultJSON];
			DBMetadata* metadata = [[DBMetadata alloc] initWithDictionary:result];
			if ([_delegate respondsToSelector:@selector(restClient:createdFolder:)]) {
				[_delegate restClient:self createdFolder:metadata];
			}
			
			if (completion) completion(nil, metadata);
		}
		
		@synchronized (requests) {
			[requests removeObject:request];
		}
	}];
	
    operation.userInfo = params;

	@synchronized (requests) {
		[requests addObject:operation];
	}
	
	[requestQueue addOperation:operation];
}


- (void)loadAccountInfoWithCompletion:(DBLoadAccountCompletionBlock)completion
{
    NSURLRequest* urlRequest = [self requestWithHost:kDBDropboxAPIHost path:@"/account/info" parameters:nil];
	
	DBRequest *operation = [[DBRequest alloc] initWithURLRequest:urlRequest completionBlock:^(DBRequest *request) {
		if (request.error) {
			[self checkForAuthenticationFailure:request];
			if ([_delegate respondsToSelector:@selector(restClient:loadAccountInfoFailedWithError:)]) {
				[_delegate restClient:self loadAccountInfoFailedWithError:request.error];
			}
			
			if (completion) completion(request.error, nil);
		}
		else {
			NSDictionary* result = (NSDictionary*)[request resultJSON];
			DBAccountInfo* accountInfo = [[DBAccountInfo alloc] initWithDictionary:result];
			if ([_delegate respondsToSelector:@selector(restClient:loadedAccountInfo:)]) {
				[_delegate restClient:self loadedAccountInfo:accountInfo];
			}
			
			if (completion) completion(nil, accountInfo);
		}
		
		@synchronized (requests) {
			[requests removeObject:request];
		}
	}];

    operation.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:root, @"root", nil];
	
	@synchronized (requests) {
		[requests addObject:operation];
	}
	
	[requestQueue addOperation:operation];
}



- (void)searchPath:(NSString *)path forKeyword:(NSString *)keyword completion:(DBSearchPathCompletionBlock)completion
{
    NSDictionary* params = [NSDictionary dictionaryWithObject:keyword forKey:@"query"];
    NSString* fullPath = [NSString stringWithFormat:@"/search/%@%@", root, path];
    
    NSURLRequest* urlRequest = [self requestWithHost:kDBDropboxAPIHost path:fullPath parameters:params];
    
	DBRequest *operation = [[DBRequest alloc] initWithURLRequest:urlRequest completionBlock:^(DBRequest *request) {
		if (request.error) {
			[self checkForAuthenticationFailure:request];
			if ([_delegate respondsToSelector:@selector(restClient:searchFailedWithError:)]) {
				[_delegate restClient:self searchFailedWithError:request.error];
			}
			
			if (completion) completion(request.error, nil);
		}
		else {
			NSMutableArray* results = nil;
			if ([[request resultJSON] isKindOfClass:[NSArray class]]) {
				NSArray* response = (NSArray*)[request resultJSON];
				results = [NSMutableArray arrayWithCapacity:[response count]];
				for (NSDictionary* dict in response) {
					DBMetadata* metadata = [[DBMetadata alloc] initWithDictionary:dict];
					[results addObject:metadata];
				}
			}
			NSString* path = [request.userInfo objectForKey:@"path"];
			NSString* keyword = [request.userInfo objectForKey:@"keyword"];
			
			if ([_delegate respondsToSelector:@selector(restClient:loadedSearchResults:forPath:keyword:)]) {
				[_delegate restClient:self loadedSearchResults:results forPath:path keyword:keyword];
			}
			
			if (completion) completion(nil, results);
		}
		
		@synchronized (requests) {
			[requests removeObject:request];
		}
		
	}];
	
    operation.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:path, @"path", keyword, @"keyword", nil];

	@synchronized (requests) {
		[requests addObject:operation];
	}
	
	[requestQueue addOperation:operation];
}

- (void)loadSharableLinkForFile:(NSString*)path completion:(DBLoadShareableLinkCompletionBlock)completion
{
    NSString* fullPath = [NSString stringWithFormat:@"/shares/%@%@", root, path];
    NSURLRequest* urlRequest = [self requestWithHost:kDBDropboxAPIHost path:fullPath parameters:nil];
	
	DBRequest *operation = [[DBRequest alloc] initWithURLRequest:urlRequest completionBlock:^(DBRequest *request) {
		if (request.error) {
			[self checkForAuthenticationFailure:request];
			if ([_delegate respondsToSelector:@selector(restClient:loadSharableLinkFailedWithError:)]) {
				[_delegate restClient:self loadSharableLinkFailedWithError:request.error];
			}
			
			if (completion) completion(request.error, nil);
		}
		else {
			NSString* sharableLink = [(NSDictionary*)request.resultJSON objectForKey:@"url"];
			NSString* path = [request.userInfo objectForKey:@"path"];
			if ([_delegate respondsToSelector:@selector(restClient:loadedSharableLink:forFile:)]) {
				[_delegate restClient:self loadedSharableLink:sharableLink forFile:path];
			}
		
			if (completion) completion(nil, sharableLink);
		}
		
		@synchronized (requests) {
			[requests removeObject:request];
		}
	}];
	
    operation.userInfo =  [NSDictionary dictionaryWithObject:path forKey:@"path"];

	@synchronized (requests) {
		[requests addObject:operation];
	}
	
	[requestQueue addOperation:operation];
}


- (void)loadStreamableURLForFile:(NSString *)path completion:(DBLoadStreamableURLCompletionBlock)completion {
    NSString* fullPath = [NSString stringWithFormat:@"/media/%@%@", root, path];
    NSURLRequest* urlRequest = [self requestWithHost:kDBDropboxAPIHost path:fullPath parameters:nil];
	
	DBRequest *operation = [[DBRequest alloc] initWithURLRequest:urlRequest completionBlock:^(DBRequest *request) {
		if (request.error) {
			[self checkForAuthenticationFailure:request];
			if ([_delegate respondsToSelector:@selector(restClient:loadStreamableURLFailedWithError:)]) {
				[_delegate restClient:self loadStreamableURLFailedWithError:request.error];
			}
			if (completion) completion(request.error, nil);
		}
		else {
			NSDictionary *response = [request parseResponseAsType:[NSDictionary class]];
			NSURL *url = [NSURL URLWithString:[response objectForKey:@"url"]];
			NSString *path = [request.userInfo objectForKey:@"path"];
			if ([_delegate respondsToSelector:@selector(restClient:loadedStreamableURL:forFile:)]) {
				[_delegate restClient:self loadedStreamableURL:url forFile:path];
			}
			if (completion) completion(nil, url);
		}
		
		@synchronized (requests) {
			[requests removeObject:request];
		}
	}];
	
    operation.userInfo = [NSDictionary dictionaryWithObject:path forKey:@"path"];

	@synchronized (requests) {
		[requests addObject:operation];
	}
	
	[requestQueue addOperation:operation];
}

- (NSUInteger)requestCount {
	return [requests count] + [loadRequests count] + [imageLoadRequests count] + [uploadRequests count];
}


#pragma mark private methods

+ (NSString*)escapePath:(NSString*)path {
    CFStringEncoding encoding = CFStringConvertNSStringEncodingToEncoding(NSUTF8StringEncoding);
    NSString *escapedPath = 
	(__bridge_transfer NSString *)CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
														(__bridge CFStringRef)path,
														NULL,
														(CFStringRef)@":?=,!$&'()*+;[]@#~",
														encoding);
    
    return escapedPath;
}

+ (NSString *)bestLanguage {
    static NSString *preferredLang = nil;
    if (!preferredLang) {
        NSString *lang = [[NSLocale preferredLanguages] objectAtIndex:0];
        if ([[[NSBundle mainBundle] localizations] containsObject:lang])
            preferredLang = [lang copy];
        else
            preferredLang =  @"en";
    }
    return preferredLang;
}

+ (NSString *)userAgent {
    static NSString *userAgent;
    if (!userAgent) {
        NSBundle *bundle = [NSBundle mainBundle];
        NSString *appName = [[bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"]
							 stringByReplacingOccurrencesOfString:@" " withString:@""];
        NSString *appVersion = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        userAgent =
		[[NSString alloc] initWithFormat:@"%@/%@ OfficialDropboxIosSdk/%@", appName, appVersion, kDBSDKVersion];
    }
    return userAgent;
}

- (NSMutableURLRequest*)requestWithHost:(NSString *)host path:(NSString *)path parameters:(NSDictionary*)params {
    return [self requestWithHost:host path:path parameters:params method:nil];
}


- (NSMutableURLRequest*)requestWithHost:(NSString *)host path:(NSString *)path parameters:(NSDictionary *)params method:(NSString *)method
{
    NSString* escapedPath = [DBRestClient escapePath:path];
    NSString* urlString = [NSString stringWithFormat:@"%@://%@/%@%@", 
						   kDBProtocolHTTPS, host, kDBDropboxAPIVersion, escapedPath];
    NSURL* url = [NSURL URLWithString:urlString];
	
    NSMutableDictionary *allParams = 
	[NSMutableDictionary dictionaryWithObject:[DBRestClient bestLanguage] forKey:@"locale"];
    if (params) {
        [allParams addEntriesFromDictionary:params];
    }
	
    NSArray *extraParams = [MPURLRequestParameter parametersFromDictionary:allParams];
    NSArray *paramList = 
    [[self.credentialStore oauthParameters] arrayByAddingObjectsFromArray:extraParams];
	
    MPOAuthURLRequest* oauthRequest = [[MPOAuthURLRequest alloc] initWithURL:url andParameters:paramList];
    if (method) {
        oauthRequest.HTTPMethod = method;
    }
	
    NSMutableURLRequest* urlRequest = [oauthRequest 
									   urlRequestSignedWithSecret:self.credentialStore.signingKey 
									   usingMethod:self.credentialStore.signatureMethod];
	
	NSTimeInterval timeout = [[NSUserDefaults standardUserDefaults] integerForKey:@"DropboxClientTimeout"];
	if (timeout == 0) timeout = 45;
	
    [urlRequest setTimeoutInterval:timeout];
    [urlRequest setValue:[DBRestClient userAgent] forHTTPHeaderField:@"User-Agent"];
    return urlRequest;
}


- (void)checkForAuthenticationFailure:(DBRequest*)request {
    if (request.error && request.error.code == 401 && [request.error.domain isEqual:DBErrorDomain]) {
        [session.delegate sessionDidReceiveAuthorizationFailure:session userId:userId];
    }
}

- (MPOAuthCredentialConcreteStore *)credentialStore {
    return [session credentialStoreForUserId:userId];
}

@end
