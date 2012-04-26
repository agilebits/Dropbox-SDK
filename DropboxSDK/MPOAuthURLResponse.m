//
//  MPOAuthURLResponse.m
//  MPOAuthConnection
//
//  Created by Karl Adam on 08.12.05.
//  Copyright 2008 matrixPointer. All rights reserved.
//

#import "MPOAuthURLResponse.h"

@implementation MPOAuthURLResponse

- (id)init {
	if ((self = [super init])) {
		
	}
	return self;
}


@synthesize urlResponse = _urlResponse;
@synthesize oauthParameters = _oauthParameters;

@end
