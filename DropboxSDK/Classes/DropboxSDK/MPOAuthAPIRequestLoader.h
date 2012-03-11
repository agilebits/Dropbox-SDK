//
//  MPOAuthAPIRequestLoader.h
//  MPOAuthConnection
//
//  Created by Karl Adam on 08.12.05.
//  Copyright 2008 matrixPointer. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString * const MPOAuthNotificationRequestTokenReceived;
extern NSString * const MPOAuthNotificationRequestTokenRejected;
extern NSString * const MPOAuthNotificationAccessTokenReceived;
extern NSString * const MPOAuthNotificationAccessTokenRejected;
extern NSString * const MPOAuthNotificationAccessTokenRefreshed;
extern NSString * const MPOAuthNotificationErrorHasOccurred;

@protocol MPOAuthCredentialStore;
@protocol MPOAuthParameterFactory;

@class MPOAuthURLRequest;
@class MPOAuthURLResponse;
@class MPOAuthCredentialConcreteStore;

@interface MPOAuthAPIRequestLoader : NSObject {
	MPOAuthCredentialConcreteStore	*_credentials;
	MPOAuthURLRequest				*_oauthRequest;
	MPOAuthURLResponse				*_oauthResponse;
	NSMutableData					*_dataBuffer;
	NSString						*_dataAsString;
	NSError							*_error;
	id								__unsafe_unretained _target;
	SEL								_action;
}

@property (nonatomic, readwrite) id <MPOAuthCredentialStore, MPOAuthParameterFactory> credentials;
@property (nonatomic, readwrite) MPOAuthURLRequest *oauthRequest;
@property (nonatomic, readwrite) MPOAuthURLResponse *oauthResponse;
@property (nonatomic, readonly) NSData *data;
@property (nonatomic, readonly) NSString *responseString;
@property (nonatomic, readwrite, unsafe_unretained) id target;
@property (nonatomic, readwrite, assign) SEL action;

- (id)initWithURL:(NSURL *)inURL;
- (id)initWithRequest:(MPOAuthURLRequest *)inRequest;

- (void)loadSynchronously:(BOOL)inSynchronous;

@end

