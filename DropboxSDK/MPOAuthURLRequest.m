//
//  MPOAuthURLRequest.m
//  MPOAuthConnection
//
//  Created by Karl Adam on 08.12.05.
//  Copyright 2008 matrixPointer. All rights reserved.
//

#import "MPOAuthURLRequest.h"
#import "MPURLRequestParameter.h"
#import "MPOAuthSignatureParameter.h"
#import "MPDebug.h"

#import "NSURL+MPURLParameterAdditions.h"
#import "NSString+URLEscapingAdditions.h"

@interface MPOAuthURLRequest ()
@property (nonatomic, readwrite) NSURLRequest *urlRequest;
@end

@implementation MPOAuthURLRequest

- (id)initWithURL:(NSURL *)inURL andParameters:(NSArray *)inParameters {
	if ((self = [super init])) {
		self.url = inURL;
		_parameters = inParameters ? [inParameters mutableCopy] : [[NSMutableArray alloc] initWithCapacity:10];
		self.HTTPMethod = @"GET";
	}
	return self;
}

- (id)initWithURLRequest:(NSURLRequest *)inRequest {
	if ((self = [super init])) {
		_url = [[inRequest URL] urlByRemovingQuery];
		_parameters = [[MPURLRequestParameter parametersFromString:[[inRequest URL] query]] mutableCopy];
		_httpMethod = [inRequest HTTPMethod];
	}
	return self;
}


@synthesize url = _url;
@synthesize HTTPMethod = _httpMethod;
@synthesize urlRequest = _urlRequest;
@synthesize parameters = _parameters;

#pragma mark -

- (NSMutableURLRequest*)urlRequestSignedWithSecret:(NSString *)inSecret usingMethod:(NSString *)inScheme {
	[self.parameters sortUsingSelector:@selector(compare:)];

	NSMutableURLRequest *aRequest = [[NSMutableURLRequest alloc] init];
	NSMutableString *parameterString = [[NSMutableString alloc] initWithString:[MPURLRequestParameter parameterStringForParameters:self.parameters]];
	MPOAuthSignatureParameter *signatureParameter = [[MPOAuthSignatureParameter alloc] initWithText:parameterString andSecret:inSecret forRequest:self usingMethod:inScheme];
	[parameterString appendFormat:@"&%@", [signatureParameter URLEncodedParameterString]];
	
	[aRequest setHTTPMethod:self.HTTPMethod];
	
	if ([[self HTTPMethod] isEqualToString:@"GET"] && [self.parameters count]) {
		NSString *urlString = [NSString stringWithFormat:@"%@?%@", [self.url absoluteString], parameterString];
		MPLog( @"urlString - %@", urlString);
		
		[aRequest setURL:[NSURL URLWithString:urlString]];
	} else if ([[self HTTPMethod] isEqualToString:@"POST"]) {
		NSData *postData = [parameterString dataUsingEncoding:NSUTF8StringEncoding];
		MPLog(@"urlString - %@", self.url);
		MPLog(@"postDataString - %@", parameterString);
		
		[aRequest setURL:self.url];
		[aRequest setValue:[NSString stringWithFormat:@"%jd", (intmax_t)[postData length]] forHTTPHeaderField:@"Content-Length"];
		[aRequest setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
		[aRequest setHTTPBody:postData];
	} else {
		[NSException raise:@"UnhandledHTTPMethodException" format:@"The requested HTTP method, %@, is not supported", self.HTTPMethod];
	}
	
	
	self.urlRequest = aRequest;
		
	return aRequest;
}

#pragma mark -

- (void)addParameters:(NSArray *)inParameters {
	[self.parameters addObjectsFromArray:inParameters];
}

@end
