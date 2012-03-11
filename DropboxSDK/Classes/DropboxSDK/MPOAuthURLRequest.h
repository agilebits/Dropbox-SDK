//
//  MPOAuthURLRequest.h
//  MPOAuthConnection
//
//  Created by Karl Adam on 08.12.05.
//  Copyright 2008 matrixPointer. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface MPOAuthURLRequest : NSObject {
@private
	NSURL			*_url;
	NSString		*_httpMethod;
	NSURLRequest	*_urlRequest;
	NSMutableArray	*_parameters;
}

@property (nonatomic, strong) NSURL *url;
@property (nonatomic, strong) NSString *HTTPMethod;
@property (nonatomic, readonly) NSURLRequest *urlRequest;
@property (nonatomic, strong) NSMutableArray *parameters;

- (id)initWithURL:(NSURL *)inURL andParameters:(NSArray *)parameters;
- (id)initWithURLRequest:(NSURLRequest *)inRequest;

- (void)addParameters:(NSArray *)inParameters;

- (NSMutableURLRequest*)urlRequestSignedWithSecret:(NSString *)inSecret usingMethod:(NSString *)inScheme;

@end
