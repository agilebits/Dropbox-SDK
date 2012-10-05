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

@interface MPOAuthCredentialConcreteStore : NSObject <MPOAuthCredentialStore, MPOAuthParameterFactory>

@property (nonatomic, readonly) NSURL *baseURL;
@property (nonatomic, readonly) NSURL *authenticationURL;

@property (nonatomic, readonly) NSString *tokenSecret;
@property (nonatomic, readonly) NSString *signingKey;

@property (nonatomic, strong) NSString *requestToken;
@property (nonatomic, strong) NSString *requestTokenSecret;
@property (nonatomic, strong) NSString *accessToken;
@property (nonatomic, strong) NSString *accessTokenSecret;

@property (nonatomic, strong) NSString *sessionHandle;

- (id)initWithCredentials:(NSDictionary *)inCredential;
- (id)initWithCredentials:(NSDictionary *)inCredentials forBaseURL:(NSURL *)inBaseURL;
- (id)initWithCredentials:(NSDictionary *)inCredentials forBaseURL:(NSURL *)inBaseURL withAuthenticationURL:(NSURL *)inAuthenticationURL;

- (void)setCredential:(id)inCredential withName:(NSString *)inName;
- (void)removeCredentialNamed:(NSString *)inName;
	

@end
