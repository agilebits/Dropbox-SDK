//
//  DBRestRequest.m
//  DropboxSDK
//
//  Created by Brian Smith on 4/9/10.
//  Copyright 2010 Dropbox, Inc. All rights reserved.
//

#import "DBRequest.h"
#import "DBLog.h"
#import "DBError.h"

static id networkRequestDelegate = nil;

@interface DBRequest () {
    NSURLRequest* request;
	BOOL finished;
    id target;
    SEL selector;
    NSURLConnection* urlConnection;
    NSFileHandle* fileHandle;
	
    SEL failureSelector;
    SEL downloadProgressSelector;
    SEL uploadProgressSelector;
    NSString* resultFilename;
    NSString* tempFilename;
    NSDictionary* userInfo;
	
    NSHTTPURLResponse* response;
    NSDictionary* xDropboxMetadataJSON;
    NSInteger bytesDownloaded;
    CGFloat downloadProgress;
    CGFloat uploadProgress;
    NSMutableData* resultData;
    NSError* error;
}

- (void)setError:(NSError *)error;

@end


@implementation DBRequest

@synthesize failureSelector;
@synthesize downloadProgressSelector;
@synthesize uploadProgressSelector;
@synthesize userInfo;
@synthesize request;
@synthesize response;
@synthesize xDropboxMetadataJSON;
@synthesize downloadProgress;
@synthesize uploadProgress;
@synthesize resultData;
@synthesize resultFilename;
@synthesize error;

+ (void)setNetworkRequestDelegate:(id<DBNetworkRequestDelegate>)delegate {
    networkRequestDelegate = delegate;
}

- (id)initWithURLRequest:(NSURLRequest*)aRequest andInformTarget:(id)aTarget selector:(SEL)aSelector {
    if ((self = [super init])) {
        request = aRequest;
        target = aTarget;
        selector = aSelector;
    }
    return self;
}

- (void) dealloc {
    [urlConnection cancel];
    
}

- (void)networkRequestStopped {
	[self willChangeValueForKey:@"isExecuting"];
	[self willChangeValueForKey:@"isFinished"];
	
	finished = YES;
	urlConnection = nil;
    [networkRequestDelegate networkRequestStopped];
	
//	[[NSRunLoop currentRunLoop] removePort:port forMode:NSRunLoopCommonModes];
//	[[NSRunLoop currentRunLoop] stop];
	
	[self didChangeValueForKey:@"isFinished"];
	[self didChangeValueForKey:@"isExecuting"];
}

- (NSString*)resultString {
    return [[NSString alloc] 
             initWithData:resultData encoding:NSUTF8StringEncoding];
}

- (NSObject*)resultJSON {
	NSError *jsonError = nil;
	NSObject *result = [NSJSONSerialization JSONObjectWithData:resultData options:NSJSONReadingMutableContainers error:&jsonError];
	if (!result && jsonError) {
		NSLog(@"Failed to parse JSON: %@", jsonError);
	}
	
	return result;
} 

- (NSInteger)statusCode {
    return [response statusCode];
}

- (long long)responseBodySize {
    // Use the content-length header, if available.
    long long contentLength = [[[response allHeaderFields] objectForKey:@"Content-Length"] longLongValue];
    if (contentLength > 0) return contentLength;

    // Fall back on the bytes field in the metadata x-header, if available.
    if (xDropboxMetadataJSON != nil) {
        id bytes = [xDropboxMetadataJSON objectForKey:@"bytes"];
        if (bytes != nil) {
            return [bytes longLongValue];
        }
    }

    return 0;
}

- (void)cancel {
    [urlConnection cancel];
    target = nil;
    
    if (tempFilename) {
        [fileHandle closeFile];
        NSError* rmError;
        if (![[NSFileManager defaultManager] removeItemAtPath:tempFilename error:&rmError]) {
            DBLogError(@"DBRequest#cancel Error removing temp file: %@", rmError);
        }
    }
    
	[self networkRequestStopped];
}

- (id)parseResponseAsType:(Class)cls {
    if (error) return nil;
    NSObject *res = [self resultJSON];
    if (![res isKindOfClass:cls]) {
        [self setError:[NSError errorWithDomain:DBErrorDomain code:DBErrorInvalidResponse userInfo:userInfo]];
        return nil;
    }
    return res;
}

#pragma mark - NSURLConnection delegate methods

- (void)connection:(NSURLConnection*)connection didReceiveResponse:(NSURLResponse*)aResponse {
    response = (NSHTTPURLResponse*)aResponse;

    // Parse out the x-response-metadata as JSON.
	NSString *xDropboxMetadataString = [[response allHeaderFields] objectForKey:@"X-Dropbox-Metadata"];
	if ([xDropboxMetadataString length] > 1) {
		NSData *xDropboxMetadataData = [NSData dataWithBytes:[xDropboxMetadataString UTF8String] length:[xDropboxMetadataString lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
		xDropboxMetadataJSON = [NSJSONSerialization JSONObjectWithData:xDropboxMetadataData options:NSJSONReadingMutableContainers error:nil];
	}

    if (resultFilename && [self statusCode] == 200) {
        // Create the file here so it's created in case it's zero length
        // File is downloaded into a temporary file and then moved over when completed successfully
        NSString* filename = 
            [NSString stringWithFormat:@"%.0f", 1000*[NSDate timeIntervalSinceReferenceDate]];
        tempFilename = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
        
        NSFileManager* fileManager = [NSFileManager new];
        BOOL success = [fileManager createFileAtPath:tempFilename contents:nil attributes:nil];
        if (!success) {
            DBLogError(@"DBRequest#connection:didReceiveData: Error creating file at path: %@", tempFilename);
        }

        fileHandle = [NSFileHandle fileHandleForWritingAtPath:tempFilename];
    }
}

- (void)connection:(NSURLConnection*)connection didReceiveData:(NSData*)data {
    if (resultFilename && [self statusCode] == 200) {
        @try {
            [fileHandle writeData:data];
        } 
		@catch (NSException* e) {
            // In case we run out of disk space
            [urlConnection cancel];
            [fileHandle closeFile];
            [[NSFileManager defaultManager] removeItemAtPath:tempFilename error:nil];
            [self setError:[NSError errorWithDomain:DBErrorDomain code:DBErrorInsufficientDiskSpace userInfo:userInfo]];
            
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"			
            SEL sel = failureSelector ? failureSelector : selector;
            [target performSelector:sel withObject:self];
#pragma clang diagnostic pop
            
			[self networkRequestStopped];
            
            return;
        }
    } 
	else {
        if (resultData == nil) {
            resultData = [NSMutableData new];
        }
        [resultData appendData:data];
    }

    bytesDownloaded += [data length];

    long long responseBodySize = [self responseBodySize];
    if (responseBodySize > 0) {
        downloadProgress = (CGFloat)bytesDownloaded / (CGFloat)responseBodySize;
        if (downloadProgressSelector) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"			
            [target performSelector:downloadProgressSelector withObject:self];
#pragma clang diagnostic pop
        }
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection*)connection {
    [fileHandle closeFile];
    fileHandle = nil;
    
    if (self.statusCode != 200) {
        NSMutableDictionary* errorUserInfo = [NSMutableDictionary dictionaryWithDictionary:userInfo];
        // To get error userInfo, first try and make sense of the response as JSON, if that
        // fails then send back the string as an error message
        if ([resultData length] > 0) {
			NSError *jsonError = nil;
			NSDictionary *resultJSON = [NSJSONSerialization JSONObjectWithData:resultData options:NSJSONReadingMutableContainers error:&jsonError];
			if ([resultJSON isKindOfClass:[NSDictionary class]]) {
				[errorUserInfo addEntriesFromDictionary:resultJSON];
			}
			else {
                [errorUserInfo setObject:[self resultString] forKey:@"errorMessage"];
            }
        }
        [self setError:[NSError errorWithDomain:DBErrorDomain code:self.statusCode userInfo:errorUserInfo]];
    } 
	else if (tempFilename) {
        NSFileManager* fileManager = [NSFileManager new];
        NSError* moveError;
        
        // Check that the file size is the same as the Content-Length
        NSDictionary* fileAttrs = [fileManager attributesOfItemAtPath:tempFilename error:&moveError];
        
        if (!fileAttrs) {
            DBLogError(@"DBRequest#connectionDidFinishLoading: error getting file attrs: %@", moveError);
            [fileManager removeItemAtPath:tempFilename error:nil];
            [self setError:[NSError errorWithDomain:moveError.domain code:moveError.code userInfo:self.userInfo]];
        } 
		else if ([self responseBodySize] != 0 && [self responseBodySize] != [fileAttrs fileSize]) {
            // This happens in iOS 4.0 when the network connection changes while loading
            [fileManager removeItemAtPath:tempFilename error:nil];
            [self setError:[NSError errorWithDomain:DBErrorDomain code:DBErrorGenericError userInfo:self.userInfo]];
        } 
		else {        
            // Everything's OK, move temp file over to desired file
            [fileManager removeItemAtPath:resultFilename error:nil];
            
            BOOL success = [fileManager moveItemAtPath:tempFilename toPath:resultFilename error:&moveError];
            if (!success) {
                DBLogError(@"DBRequest#connectionDidFinishLoading: error moving temp file to desired location: %@",
                    [moveError localizedDescription]);
                [self setError:[NSError errorWithDomain:moveError.domain code:moveError.code userInfo:self.userInfo]];
            }
        }
        
        tempFilename = nil;
    }
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"			
    SEL sel = (error && failureSelector) ? failureSelector : selector;
    [target performSelector:sel withObject:self];
#pragma clang diagnostic pop

    [self networkRequestStopped];
}

- (void)connection:(NSURLConnection*)connection didFailWithError:(NSError*)anError {
    [fileHandle closeFile];
    [self setError:[NSError errorWithDomain:anError.domain code:anError.code userInfo:self.userInfo]];
    bytesDownloaded = 0;
    downloadProgress = 0;
    uploadProgress = 0;
    
    if (tempFilename) {
        NSFileManager* fileManager = [NSFileManager new];
        NSError* removeError;
        BOOL success = [fileManager removeItemAtPath:tempFilename error:&removeError];
        if (!success) {
            DBLogError(@"DBRequest#connection:didFailWithError: error removing temporary file: %@", 
                    [removeError localizedDescription]);
        }
        tempFilename = nil;
    }
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"			
    SEL sel = failureSelector ? failureSelector : selector;
    [target performSelector:sel withObject:self];
#pragma clang diagnostic pop

	[self networkRequestStopped];
}

- (void)connection:(NSURLConnection*)connection didSendBodyData:(NSInteger)bytesWritten 
    totalBytesWritten:(NSInteger)totalBytesWritten 
    totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite {
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"			
    uploadProgress = (CGFloat)totalBytesWritten / (CGFloat)totalBytesExpectedToWrite;
    if (uploadProgressSelector) {
        [target performSelector:uploadProgressSelector withObject:self];
    }
#pragma clang diagnostic pop
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)response {
	return nil;
}


#pragma mark - NSOperation methods

- (void)start {
	[self willChangeValueForKey:@"isExecuting"];
	
	NSRunLoop *runLoop = [NSRunLoop mainRunLoop];
	
	urlConnection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
	[urlConnection scheduleInRunLoop:runLoop forMode:NSRunLoopCommonModes];
	[urlConnection start];
	
	[networkRequestDelegate networkRequestStarted];
	
	[self didChangeValueForKey:@"isExecuting"];
}

- (BOOL)isConcurrent {
	return YES;
}

- (BOOL)isExecuting {
	return urlConnection != nil;
}

- (BOOL)isFinished {
	return finished;
}


#pragma mark - private methods

- (void)setError:(NSError *)theError {
    if (theError == error) return;
    error = theError;

	NSString *errorStr = [error.userInfo objectForKey:@"error"];
	if (!errorStr) {
		errorStr = [error description];
	}

	if (!([error.domain isEqual:DBErrorDomain] && error.code == 304)) {
		// Log errors unless they're 304's
		DBLogWarning(@"DropboxSDK: error making request to %@ - %@", [[request URL] path], errorStr);
	}
}

@end
