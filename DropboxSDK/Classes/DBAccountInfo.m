//
//  DBAccountInfo.m
//  DropboxSDK
//
//  Created by Brian Smith on 5/3/10.
//  Copyright 2010 Dropbox, Inc. All rights reserved.
//

#import "DBAccountInfo.h"


@implementation DBAccountInfo

- (id)initWithDictionary:(NSDictionary*)dict {
    if ((self = [super init])) {
        country = [dict objectForKey:@"country"];
        displayName = [dict objectForKey:@"display_name"];
        if ([dict objectForKey:@"quota_info"]) {
            quota = [[DBQuota alloc] initWithDictionary:[dict objectForKey:@"quota_info"]];
        }
        userId = [[dict objectForKey:@"uid"] stringValue];
        referralLink = [dict objectForKey:@"referral_link"];
    }
    return self;
}


@synthesize country;
@synthesize displayName;
@synthesize quota;
@synthesize userId;
@synthesize referralLink;


#pragma mark NSCoding methods

- (void)encodeWithCoder:(NSCoder*)coder {
    [coder encodeObject:country forKey:@"country"];
    [coder encodeObject:displayName forKey:@"displayName"];
    [coder encodeObject:quota forKey:@"quota"];
    [coder encodeObject:userId forKey:@"userId"];
    [coder encodeObject:referralLink forKey:@"referralLink"];
}

- (id)initWithCoder:(NSCoder*)coder {
    self = [super init];
    country = [coder decodeObjectForKey:@"country"];
    displayName = [coder decodeObjectForKey:@"displayName"];
    quota = [coder decodeObjectForKey:@"quota"];
    userId = [coder decodeObjectForKey:@"userId"];
    referralLink = [coder decodeObjectForKey:@"referralLink"];
    return self;
}

@end
