//
//  MPOAuthAuthenticationMethodOAuth.h
//  MPOAuthConnection
//
//  Created by Karl Adam on 09.12.19.
//  Copyright 2009 matrixPointer. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MPOAuthAuthenticationMethod.h"
#import "MPOAuthAPI.h"
#import "MPOAuthAPIRequestLoader.h"

extern NSString * const MPOAuthNotificationRequestTokenReceived;
extern NSString * const MPOAuthNotificationRequestTokenRejected;

@protocol MPOAuthAuthenticationMethodOAuthDelegate;

@interface MPOAuthAuthenticationMethodOAuth : MPOAuthAuthenticationMethod <MPOAuthAPIInternalClient> {
	NSURL									*oauthRequestTokenURL_;
	NSURL									*oauthAuthorizeTokenURL_;
	BOOL									oauth10aModeActive_;
	
	id <MPOAuthAuthenticationMethodOAuthDelegate> __unsafe_unretained delegate_;
}

@property (nonatomic, readwrite, unsafe_unretained) id <MPOAuthAuthenticationMethodOAuthDelegate> delegate;

@property (nonatomic, readwrite) NSURL *oauthRequestTokenURL;
@property (nonatomic, readwrite) NSURL *oauthAuthorizeTokenURL;

- (void)authenticate;

@end

@protocol MPOAuthAuthenticationMethodOAuthDelegate <NSObject>
- (NSURL *)callbackURLForCompletedUserAuthorization;
- (BOOL)automaticallyRequestAuthenticationFromURL:(NSURL *)inAuthURL withCallbackURL:(NSURL *)inCallbackURL;

@optional
- (NSString *)oauthVerifierForCompletedUserAuthorization;
- (void)authenticationDidFailWithError:(NSError *)error;
@end

