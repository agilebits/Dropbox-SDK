//
//  MPOAuthCredentialConcreteStore.h
//  MPOAuthConnection
//
//  Created by Karl Adam on 08.12.11.
//  Copyright 2008 matrixPointer. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MPOAuthCredentialStore.h"
#import "MPOAuthParameterFactory.h"

@interface MPOAuthCredentialConcreteStore : NSObject <MPOAuthCredentialStore, MPOAuthParameterFactory> {
	NSMutableDictionary *store_;
	NSURL				*baseURL_;
	NSURL				*authenticationURL_;
}

@property (nonatomic, readonly) NSURL *baseURL;
@property (nonatomic, readonly) NSURL *authenticationURL;

@property (weak, nonatomic, readonly) NSString *tokenSecret;
@property (weak, nonatomic, readonly) NSString *signingKey;

@property (nonatomic, readwrite) NSString *requestToken;
@property (nonatomic, readwrite) NSString *requestTokenSecret;
@property (nonatomic, readwrite) NSString *accessToken;
@property (nonatomic, readwrite) NSString *accessTokenSecret;

@property (nonatomic, readwrite) NSString *sessionHandle;

- (id)initWithCredentials:(NSDictionary *)inCredential;
- (id)initWithCredentials:(NSDictionary *)inCredentials forBaseURL:(NSURL *)inBaseURL;
- (id)initWithCredentials:(NSDictionary *)inCredentials forBaseURL:(NSURL *)inBaseURL withAuthenticationURL:(NSURL *)inAuthenticationURL;

- (void)setCredential:(id)inCredential withName:(NSString *)inName;
- (void)removeCredentialNamed:(NSString *)inName;
	

@end
