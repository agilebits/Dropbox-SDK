//
//  MPOAuthURLResponse.h
//  MPOAuthConnection
//
//  Created by Karl Adam on 08.12.05.
//  Copyright 2008 matrixPointer. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface MPOAuthURLResponse : NSObject {
	NSURLResponse	*_urlResponse;
	NSDictionary	*_oauthParameters;
}

@property (nonatomic, strong) NSURLResponse *urlResponse;
@property (nonatomic, strong) NSDictionary *oauthParameters;

@end
