//
//  DBSession.h
//  DropboxSDK
//
//  Created by Brian Smith on 4/8/10.
//  Copyright 2010 Dropbox, Inc. All rights reserved.
//

#import "MPOAuthCredentialConcreteStore.h"

extern NSString *kDBSDKVersion;

extern NSString *kDBDropboxAPIHost;
extern NSString *kDBDropboxAPIContentHost;
extern NSString *kDBDropboxWebHost;
extern NSString *kDBDropboxAPIVersion;

extern NSString *kDBRootDropbox;
extern NSString *kDBRootAppFolder;

extern NSString *kDBProtocolHTTPS;
extern NSString *kDBDropboxUnknownUserId;

@protocol DBSessionDelegate;
@protocol DBSessionCredentialsDelegate;


/*  Creating and setting the shared DBSession should be done before any other Dropbox objects are
    used, perferrably in the UIApplication delegate. */
@interface DBSession : NSObject {
    NSDictionary *baseCredentials;
    NSMutableDictionary *credentialStores;
    MPOAuthCredentialConcreteStore *anonymousStore;
}

+ (DBSession*)sharedSession;
+ (void)setSharedSession:(DBSession *)session;

- (id)initWithAppKey:(NSString *)key appSecret:(NSString *)secret root:(NSString *)root;
- (BOOL)isLinked; // Session must be linked before creating any DBRestClient objects

- (void)unlinkAll;
- (void)unlinkUserId:(NSString *)userId;

- (MPOAuthCredentialConcreteStore *)credentialStoreForUserId:(NSString *)userId;
- (void)updateAccessToken:(NSString *)token accessTokenSecret:(NSString *)secret forUserId:(NSString *)userId;

@property (nonatomic, readonly) NSString *root;
@property (nonatomic, readonly) NSArray *userIds;

@property (nonatomic, weak) id<DBSessionDelegate> delegate;
@property (nonatomic, weak) id<DBSessionCredentialsDelegate> credentialsDelegate;

@end


@protocol DBSessionDelegate <NSObject>

- (void)sessionDidReceiveAuthorizationFailure:(DBSession *)session userId:(NSString *)userId;

@end

@protocol DBSessionCredentialsDelegate <NSObject>

- (NSDictionary *)dropboxSessionLoadCredentials:(DBSession *)session;
- (void)dropboxSession:(DBSession *)session saveCredentials:(NSDictionary *)credentials;
- (void)dropboxSessionRemoveCredentials:(DBSession *)session;


@end
