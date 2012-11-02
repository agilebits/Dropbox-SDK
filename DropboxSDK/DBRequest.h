//
//  DBRestRequest.h
//  DropboxSDK
//
//  Created by Brian Smith on 4/9/10.
//  Copyright 2010 Dropbox, Inc. All rights reserved.
//
//	March 2012. Roustem Karimov. Changed DBRequest to subclass NSOperation

@class DBRequest;
@protocol DBNetworkRequestDelegate;

typedef void (^DBRequestBlock)(DBRequest *request);

/* DBRestRequest will download a URL either into a file that you provied the name to or it will
   create an NSData object with the result. When it has completed downloading the URL, it will
   notify the target with a selector that takes the DBRestRequest as the only parameter. */
@interface DBRequest : NSOperation

/*  Set this to get called when _any_ request starts or stops. This should hook into whatever
    network activity indicator system you have. */
+ (void)setNetworkRequestDelegate:(id<DBNetworkRequestDelegate>)delegate;

/*  This constructor downloads the URL into the resultData object */
- (id)initWithURLRequest:(NSURLRequest *)aRequest completionBlock:(DBRequestBlock)completionBlock;

/*  Cancels the request and prevents it from sending additional messages to the delegate. */
- (void)cancel;

/* If there is no error, it will parse the response as JSON and make sure the JSON object is the
   correct type. If not, it will set the error object with an error code of DBErrorInvalidResponse */
- (id)parseResponseAsType:(Class)cls;

@property (nonatomic) NSString* resultFilename; // The file to put the HTTP body in, otherwise body is stored in resultData
@property (nonatomic) NSDictionary* userInfo;

@property (nonatomic, strong) DBRequestBlock completionBlock;
@property (nonatomic, strong) DBRequestBlock failureBlock;
@property (nonatomic, strong) DBRequestBlock uploadProgressBlock;
@property (nonatomic, strong) DBRequestBlock downloadProgressBlock;

@property (nonatomic, readonly) NSURLRequest* request;
@property (nonatomic, readonly) NSHTTPURLResponse* response;
@property (nonatomic, readonly) NSDictionary* xDropboxMetadataJSON;
@property (nonatomic, readonly) NSInteger statusCode;
@property (nonatomic, readonly) CGFloat downloadProgress;
@property (nonatomic, readonly) CGFloat uploadProgress;
@property (nonatomic, readonly) NSData* resultData;

@property (nonatomic, readonly) NSString* resultString;
@property (nonatomic, readonly) NSObject* resultJSON;
@property (nonatomic, readonly) NSError* error;

@property (nonatomic, readonly) BOOL cancelled;

// NSOperation methods
- (void)main;

@end


@protocol DBNetworkRequestDelegate 

- (void)networkRequestStarted;
- (void)networkRequestStopped;

@end
