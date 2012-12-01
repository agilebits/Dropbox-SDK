//
//  DBSession.m
//  DropboxSDK
//
//  Created by Brian Smith on 4/8/10.
//  Copyright 2010 Dropbox, Inc. All rights reserved.
//

#import "DBSession.h"

#import <CommonCrypto/CommonDigest.h>

#import "DBLog.h"
#import "MPOAuthCredentialConcreteStore.h"
#import "MPOAuthSignatureParameter.h"

NSString *kDBSDKVersion = @"1.2.3-b1"; // TODO: parameterize from build system

NSString *kDBDropboxAPIHost = @"api.dropbox.com";
NSString *kDBDropboxAPIContentHost = @"api-content.dropbox.com";
NSString *kDBDropboxWebHost = @"www.dropbox.com";
NSString *kDBDropboxAPIVersion = @"1";

NSString *kDBRootDropbox = @"dropbox";
NSString *kDBRootAppFolder = @"sandbox";

NSString *kDBProtocolHTTPS = @"https";
NSString *kDBDropboxUnknownUserId = @"unknown";

static NSString *kDBProtocolDropbox = @"dbapi-1";

static DBSession *_sharedSession = nil;
static NSString *kDBDropboxSavedCredentialsOld = @"kDBDropboxSavedCredentialsKey";
static NSString *kDBDropboxSavedCredentials = @"kDBDropboxSavedCredentials";
static NSString *kDBDropboxUserCredentials = @"kDBDropboxUserCredentials";
static NSString *kDBDropboxUserId = @"kDBDropboxUserId";


@interface DBSession () {
	BOOL _credentialStoreReady;
	NSString *_key;
	NSString *_secret;
	MPOAuthCredentialConcreteStore *_nilUserStore;
}

- (NSDictionary*)savedCredentials;
- (void)saveCredentials;
- (void)clearSavedCredentials;
- (void)setAccessToken:(NSString *)token accessTokenSecret:(NSString *)secret forUserId:(NSString *)userId;

@end


@implementation DBSession

@synthesize root = _root;

+ (DBSession *)sharedSession {
    return _sharedSession;
}

+ (void)setSharedSession:(DBSession *)session {
    if (session == _sharedSession) return;
    _sharedSession = session;
}

- (id)initWithAppKey:(NSString *)key appSecret:(NSString *)secret root:(NSString *)root {
    if ((self = [super init])) {
		_key = key;
		_secret = secret;
		_root = root;
    }
    return self;
}


- (void)prepareCredentialStore {
	if (_credentialStoreReady) return;

	baseCredentials = [[NSDictionary alloc] initWithObjectsAndKeys:
					   _key, kMPOAuthCredentialConsumerKey,
					   _secret, kMPOAuthCredentialConsumerSecret,
					   kMPOAuthSignatureMethodPlaintext, kMPOAuthSignatureMethod, nil];
	
	credentialStores = [NSMutableDictionary new];
	
	
	NSDictionary *oldSavedCredentials = [[NSUserDefaults standardUserDefaults] objectForKey:kDBDropboxSavedCredentialsOld];
	if (oldSavedCredentials) {
		if ([_key isEqual:[oldSavedCredentials objectForKey:kMPOAuthCredentialConsumerKey]]) {
			NSString *token = [oldSavedCredentials objectForKey:kMPOAuthCredentialAccessToken];
			NSString *secret = [oldSavedCredentials objectForKey:kMPOAuthCredentialAccessTokenSecret];
			[self setAccessToken:token accessTokenSecret:secret forUserId:kDBDropboxUnknownUserId];
		}
	}
	
	NSDictionary *savedCredentials = [self savedCredentials];
	if (savedCredentials != nil) {
		if ([_key isEqualToString:[savedCredentials objectForKey:kMPOAuthCredentialConsumerKey]]) {
            
			NSArray *allUserCredentials = [savedCredentials objectForKey:kDBDropboxUserCredentials];
			for (NSDictionary *userCredentials in allUserCredentials) {
				NSString *userId = [userCredentials objectForKey:kDBDropboxUserId];
				NSString *token = [userCredentials objectForKey:kMPOAuthCredentialAccessToken];
				NSString *secret = [userCredentials objectForKey:kMPOAuthCredentialAccessTokenSecret];
				[self setAccessToken:token accessTokenSecret:secret forUserId:userId];
			}
		} else {
			[self clearSavedCredentials];
		}
	}
	
	_credentialStoreReady = YES;
}

- (void)updateAccessToken:(NSString *)token accessTokenSecret:(NSString *)secret forUserId:(NSString *)userId {
    [self setAccessToken:token accessTokenSecret:secret forUserId:userId];
    [self saveCredentials];
}

- (void)setAccessToken:(NSString *)token accessTokenSecret:(NSString *)secret forUserId:(NSString *)userId {
    MPOAuthCredentialConcreteStore *credentialStore = [credentialStores objectForKey:userId];
    if (!credentialStore) {
        credentialStore = [[MPOAuthCredentialConcreteStore alloc] initWithCredentials:baseCredentials];
        [credentialStores setObject:credentialStore forKey:userId];
        
        if (![userId isEqual:kDBDropboxUnknownUserId] && [credentialStores objectForKey:kDBDropboxUnknownUserId]) {
            // If the unknown user is in credential store, replace it with this new entry
            [credentialStores removeObjectForKey:kDBDropboxUnknownUserId];
        }
    }
	
    credentialStore.accessToken = token;
    credentialStore.accessTokenSecret = secret;
}

- (BOOL)isLinked {
	@synchronized (self) {
		[self prepareCredentialStore];
		
		return [credentialStores count] != 0;
	}
}

- (void)unlinkAll {
	@synchronized (self) {
		[self prepareCredentialStore];

		[credentialStores removeAllObjects];
		[self clearSavedCredentials];
	}
}

- (void)unlinkUserId:(NSString *)userId {
	@synchronized (self) {
		[self prepareCredentialStore];

		[credentialStores removeObjectForKey:userId];
		[self saveCredentials];
	}
}

- (MPOAuthCredentialConcreteStore *)credentialStoreForUserId:(NSString *)userId {
	@synchronized (self) {
		[self prepareCredentialStore];

		if (!userId) {
			if (!_nilUserStore) _nilUserStore = [[MPOAuthCredentialConcreteStore alloc] initWithCredentials:baseCredentials];
			return _nilUserStore;
		}
		return [credentialStores objectForKey:userId];
	}
}

- (NSArray *)userIds {
	@synchronized (self) {
		[self prepareCredentialStore];

		return [credentialStores allKeys];
	}
}


#pragma mark private methods

- (NSDictionary *)savedCredentials {
	if ([self.credentialsDelegate respondsToSelector:@selector(dropboxSessionLoadCredentials:)]) {
		return [self.credentialsDelegate dropboxSessionLoadCredentials:self];
	}

    return [[NSUserDefaults standardUserDefaults] objectForKey:kDBDropboxSavedCredentials];
}

- (void)saveCredentials
{
    NSMutableDictionary *credentials = [NSMutableDictionary dictionaryWithDictionary:baseCredentials];
    NSMutableArray *allUserCredentials = [NSMutableArray array];
    for (NSString *userId in [credentialStores allKeys]) {
        MPOAuthCredentialConcreteStore *store = [credentialStores objectForKey:userId];
        NSMutableDictionary *userCredentials = [NSMutableDictionary new];
        [userCredentials setObject:userId forKey:kDBDropboxUserId];
        [userCredentials setObject:store.accessToken forKey:kMPOAuthCredentialAccessToken];
        [userCredentials setObject:store.accessTokenSecret forKey:kMPOAuthCredentialAccessTokenSecret];
        [allUserCredentials addObject:userCredentials];
    }
    [credentials setObject:allUserCredentials forKey:kDBDropboxUserCredentials];

    if ([self.credentialsDelegate respondsToSelector:@selector(dropboxSession:saveCredentials:)]) {
		[self.credentialsDelegate dropboxSession:self saveCredentials:credentials];
	}
	else {
		[[NSUserDefaults standardUserDefaults] setObject:credentials forKey:kDBDropboxSavedCredentials];
		[[NSUserDefaults standardUserDefaults] removeObjectForKey:kDBDropboxSavedCredentialsOld];
		[[NSUserDefaults standardUserDefaults] synchronize];
	}
}

- (void)clearSavedCredentials {
	if ([self.credentialsDelegate respondsToSelector:@selector(dropboxSessionRemoveCredentials:)]) {
		[self.credentialsDelegate dropboxSessionRemoveCredentials:self];
	}
	
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kDBDropboxSavedCredentials];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
