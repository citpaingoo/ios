//
//  OCCommunication.m
//  Owncloud iOs Client
//
// Copyright (C) 2016, ownCloud GmbH.  ( http://www.owncloud.org/ )
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
//
//  Add : getNotificationServer & setNotificationServer
//  Add : getUserProfileServer
//  Add : Support for Favorite
//  Add : getActivityServer
//
//  Author Marino Faggiana <marino.faggiana@nextcloud.com>
//  Copyright (c) 2017 Marino Faggiana. All rights reserved.
//


#import "OCCommunication.h"
#import "OCHTTPRequestOperation.h"
#import "UtilsFramework.h"
#import "OCXMLSharedParser.h"
#import "OCXMLServerErrorsParser.h"
#import "NSString+Encode.h"
#import "OCFrameworkConstants.h"
#import "OCWebDAVClient.h"
#import "OCXMLShareByLinkParser.h"
#import "OCErrorMsg.h"
#import "OCShareUser.h"
#import "OCActivity.h"
#import "OCExternalSites.h"
#import "OCCapabilities.h"
#import "OCNotifications.h"
#import "OCNotificationsAction.h"
#import "OCRichObjectStrings.h"
#import "OCUserProfile.h"
#import "NCRichDocumentTemplate.h"
#import "HCFeatures.h"
#import "NCXMLCommentsParser.h"
#import "NCXMLListParser.h"

@interface OCCommunication ()

@property (nonatomic, strong) NSString *currentServerVersion;

@end

@implementation OCCommunication


-(id) init {
    
    self = [super init];
    
    if (self) {
        
        //Init the Donwload queue array
        self.downloadTaskNetworkQueueArray = [NSMutableArray new];
        
        //Credentials not set yet
        self.kindOfCredential = credentialNotSet;
        
        [self setSecurityPolicyManagers:[self createSecurityPolicy]];
        
        self.isCookiesAvailable = YES;
        self.isForbiddenCharactersAvailable = NO;
        
#ifdef UNIT_TEST
        
        self.uploadSessionManager = [[AFURLSessionManager alloc] initWithSessionConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
        self.downloadSessionManager = [[AFURLSessionManager alloc] initWithSessionConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
        self.networkSessionManager = [[AFURLSessionManager alloc] initWithSessionConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
        self.networkSessionManager.responseSerializer = [AFHTTPResponseSerializer serializer];
#else
        //Network Upload queue for NSURLSession (iOS 7)
        NSURLSessionConfiguration *uploadConfiguration = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:k_session_name];
        uploadConfiguration.HTTPShouldUsePipelining = YES;
        uploadConfiguration.HTTPMaximumConnectionsPerHost = 1;
        uploadConfiguration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        self.uploadSessionManager = [[AFURLSessionManager alloc] initWithSessionConfiguration:uploadConfiguration];
        [self.uploadSessionManager.operationQueue setMaxConcurrentOperationCount:1];
        
        //Network Download queue for NSURLSession (iOS 7)
        NSURLSessionConfiguration *downConfiguration = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:k_download_session_name];
        downConfiguration.HTTPShouldUsePipelining = YES;
        downConfiguration.HTTPMaximumConnectionsPerHost = 1;
        downConfiguration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        self.downloadSessionManager = [[AFURLSessionManager alloc] initWithSessionConfiguration:downConfiguration];
        [self.downloadSessionManager.operationQueue setMaxConcurrentOperationCount:1];
        
        //Network Download queue for NSURLSession (iOS 7)
        NSURLSessionConfiguration *networkConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
        networkConfiguration.HTTPShouldUsePipelining = YES;
        networkConfiguration.HTTPMaximumConnectionsPerHost = 1;
        networkConfiguration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        self.networkSessionManager = [[AFURLSessionManager alloc] initWithSessionConfiguration:networkConfiguration];
        [self.networkSessionManager.operationQueue setMaxConcurrentOperationCount:1];
        self.networkSessionManager.responseSerializer = [AFHTTPResponseSerializer serializer];
#endif
        
    }
    
    return self;
}

-(id) initWithUploadSessionManager:(AFURLSessionManager *) uploadSessionManager {
    
    self = [super init];
    
    if (self) {
        
        //Init the Donwload queue array
        self.downloadTaskNetworkQueueArray = [NSMutableArray new];
        
        self.isCookiesAvailable = YES;
        self.isForbiddenCharactersAvailable = NO;
        
        //Credentials not set yet
        self.kindOfCredential = credentialNotSet;
        
        [self setSecurityPolicyManagers:[self createSecurityPolicy]];
        
        self.uploadSessionManager = uploadSessionManager;
    }
    
    return self;
}

-(id) initWithUploadSessionManager:(AFURLSessionManager *) uploadSessionManager andDownloadSessionManager:(AFURLSessionManager *) downloadSessionManager andNetworkSessionManager:(AFURLSessionManager *) networkSessionManager {
    
    self = [super init];
    
    if (self) {
    
        //Init the Donwload queue array
        self.downloadTaskNetworkQueueArray = [NSMutableArray new];
        
        //Credentials not set yet
        self.kindOfCredential = credentialNotSet;
        
        [self setSecurityPolicyManagers:[self createSecurityPolicy]];
        
        self.uploadSessionManager = uploadSessionManager;
        self.downloadSessionManager = downloadSessionManager;
        self.networkSessionManager = networkSessionManager;
    }
    
    return self;
}

- (AFSecurityPolicy *) createSecurityPolicy {
    return [AFSecurityPolicy defaultPolicy];
}

- (void)setSecurityPolicyManagers:(AFSecurityPolicy *)securityPolicy {
    self.securityPolicy = securityPolicy;
    self.uploadSessionManager.securityPolicy = securityPolicy;
    self.downloadSessionManager.securityPolicy = securityPolicy;
}

#pragma mark - Setting Credentials

- (void) setCredentialsWithUser:(NSString*) user andUserID:(NSString *) userID andPassword:(NSString*) password  {
    self.kindOfCredential = credentialNormal;
    self.user = user;
    self.userID = userID;
    self.password = password;
}

- (void) setCredentialsWithCookie:(NSString*) cookie {
    self.kindOfCredential = credentialCookie;
    self.password = cookie;
}

- (void) setCredentialsOauthWithToken:(NSString*) token {
    self.kindOfCredential = credentialOauth;
    self.password = token;
}

- (void) setupNextcloudVersion:(NSInteger) version
{
    self.nextcloudVersion = version;
}


///-----------------------------------
/// @name getRequestWithCredentials
///-----------------------------------

/**
 * Method to return the request with the right credential
 *
 * @param OCWebDAVClient like a dinamic typed
 *
 * @return OCWebDAVClient like a dinamic typed
 *
 */
- (id) getRequestWithCredentials:(id) request {
    
    if ([request isKindOfClass:[NSMutableURLRequest class]]) {
        NSMutableURLRequest *myRequest = (NSMutableURLRequest *)request;
        
        switch (self.kindOfCredential) {
            case credentialNotSet:
                //Without credentials
                break;
            case credentialNormal:
            {
                NSString *basicAuthCredentials = [NSString stringWithFormat:@"%@:%@", self.user, self.password];
                [myRequest addValue:[NSString stringWithFormat:@"Basic %@", [UtilsFramework AFBase64EncodedStringFromString:basicAuthCredentials]] forHTTPHeaderField:@"Authorization"];
                break;
            }
            case credentialCookie:
                NSLog(@"Cookie: %@", self.password);
                [myRequest addValue:self.password forHTTPHeaderField:@"Cookie"];
                break;
            case credentialOauth:
                [myRequest addValue:[NSString stringWithFormat:@"Bearer %@", self.password] forHTTPHeaderField:@"Authorization"];
                break;
            default:
                break;
        }
        
        if (self.userAgent) {
            [myRequest addValue:self.userAgent forHTTPHeaderField:@"User-Agent"];
        }
        
        return myRequest;
        
    } else if([request isKindOfClass:[OCWebDAVClient class]]) {
        OCWebDAVClient *myRequest = (OCWebDAVClient *)request;
        
        switch (self.kindOfCredential) {
            case credentialNotSet:
                //Without credentials
                break;
            case credentialNormal:
                [myRequest setAuthorizationHeaderWithUsername:self.user password:self.password];
                break;
            case credentialCookie:
                [myRequest setAuthorizationHeaderWithCookie:self.password];
                break;
            case credentialOauth:
                [myRequest setAuthorizationHeaderWithToken:[NSString stringWithFormat:@"Bearer %@", self.password]];
                break;
            default:
                break;
        }
        
        if (self.userAgent) {
           [myRequest setUserAgent:self.userAgent];
        }
    
        return request;
        
    } else {
        NSLog(@"We do not know witch kind of object is");
        return  request;
    }
}


#pragma mark - WebDav network Operations

///-----------------------------------
/// @name Check Server
///-----------------------------------
- (void) checkServer: (NSString *) path
     onCommunication:(OCCommunication *)sharedOCCommunication
      successRequest:(void(^)(NSHTTPURLResponse *response, NSString *redirectedServer)) successRequest
      failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    if (self.userAgent) {
        [request setUserAgent:self.userAgent];
    }
    
    path = [path encodeString:NSUTF8StringEncoding];
    
    [request checkServer:path onCommunication:sharedOCCommunication
                 success:^(NSHTTPURLResponse *response, id responseObject) {
                     if (successRequest) {
                         successRequest(response, request.redirectedServer);
                     }
                 } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
                     failureRequest(response, error, request.redirectedServer);
                 }];
}

///-----------------------------------
/// @name Create a folder
///-----------------------------------
- (void) createFolder: (NSString *) path
      onCommunication:(OCCommunication *)sharedOCCommunication withForbiddenCharactersSupported:(BOOL)isFCSupported
       successRequest:(void(^)(NSHTTPURLResponse *response, NSString *redirectedServer)) successRequest
       failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest
   errorBeforeRequest:(void(^)(NSError *error)) errorBeforeRequest {
    
    
    if ([UtilsFramework isForbiddenCharactersInFileName:[UtilsFramework getFileNameOrFolderByPath:path] withForbiddenCharactersSupported:isFCSupported]) {
        NSError *error = [UtilsFramework getErrorByCodeId:OCErrorForbidenCharacters];
        errorBeforeRequest(error);
    } else {
        OCWebDAVClient *request = [OCWebDAVClient new];
        request = [self getRequestWithCredentials:request];
        
        
        path = [path encodeString:NSUTF8StringEncoding];
        
        [request makeCollection:path onCommunication:sharedOCCommunication
                        success:^(NSHTTPURLResponse *response, id responseObject) {
                            if (successRequest) {
                                successRequest(response, request.redirectedServer);
                            }
                        } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
                            
                            OCXMLServerErrorsParser *serverErrorParser = [OCXMLServerErrorsParser new];
                            
                            [serverErrorParser startToParseWithData:responseData withCompleteBlock:^(NSError *err) {
                                
                                if (err) {
                                    failureRequest(response, err, request.redirectedServer);
                                }else{
                                    failureRequest(response, error, request.redirectedServer);
                                }
                                
                                
                            }];
                            
                        }];
    }
}

///-----------------------------------
/// @name Move a file or a folder
///-----------------------------------
- (void) moveFileOrFolder:(NSString *)sourcePath
                toDestiny:(NSString *)destinyPath
          onCommunication:(OCCommunication *)sharedOCCommunication withForbiddenCharactersSupported:(BOOL)isFCSupported
           successRequest:(void (^)(NSHTTPURLResponse *response, NSString *redirectServer))successRequest
           failureRequest:(void (^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer))failureRequest
       errorBeforeRequest:(void (^)(NSError *error))errorBeforeRequest {
    
    if ([UtilsFramework isTheSameFileOrFolderByNewURLString:destinyPath andOriginURLString:sourcePath]) {
        //We check that we are not trying to move the file to the same place
        NSError *error = [UtilsFramework getErrorByCodeId:OCErrorMovingTheDestinyAndOriginAreTheSame];
        errorBeforeRequest(error);
    } else if ([UtilsFramework isAFolderUnderItByNewURLString:destinyPath andOriginURLString:sourcePath]) {
        //We check we are not trying to move a folder inside himself
        NSError *error = [UtilsFramework getErrorByCodeId:OCErrorMovingFolderInsideHimself];
        errorBeforeRequest(error);
    } else if ([UtilsFramework isForbiddenCharactersInFileName:[UtilsFramework getFileNameOrFolderByPath:destinyPath] withForbiddenCharactersSupported:isFCSupported]) {
        //We check that we are making a move not a rename to prevent special characters problems
        NSError *error = [UtilsFramework getErrorByCodeId:OCErrorMovingDestinyNameHaveForbiddenCharacters];
        errorBeforeRequest(error);
    } else {
        
        sourcePath = [sourcePath encodeString:NSUTF8StringEncoding];
        destinyPath = [destinyPath encodeString:NSUTF8StringEncoding];
        
        OCWebDAVClient *request = [OCWebDAVClient new];
        request = [self getRequestWithCredentials:request];
        
        
        [request movePath:sourcePath toPath:destinyPath onCommunication:sharedOCCommunication success:^(NSHTTPURLResponse *response, id responseObject) {
            if (successRequest) {
                successRequest(response, request.redirectedServer);
            }
        } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
            
            OCXMLServerErrorsParser *serverErrorParser = [OCXMLServerErrorsParser new];
            
            [serverErrorParser startToParseWithData:responseData withCompleteBlock:^(NSError *err) {
                
                if (err) {
                    failureRequest(response, err, request.redirectedServer);
                }else{
                    failureRequest(response, error, request.redirectedServer);
                }
                
            }];
            
        }];
    }
}


///-----------------------------------
/// @name Delete a file or a folder
///-----------------------------------
- (void) deleteFileOrFolder:(NSString *)path
            onCommunication:(OCCommunication *)sharedOCCommunication
             successRequest:(void (^)(NSHTTPURLResponse *response, NSString *redirectedServer))successRequest
              failureRquest:(void (^)(NSHTTPURLResponse *resposne, NSError *error, NSString *redirectedServer))failureRequest {
    
    path = [path encodeString:NSUTF8StringEncoding];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    
    [request deletePath:path onCommunication:sharedOCCommunication success:^(NSHTTPURLResponse *response, id responseObject) {
        if (successRequest) {
            successRequest(response, request.redirectedServer);
        }
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        failureRequest(response, error, request.redirectedServer);
    }];
}


///-----------------------------------
/// @name Read folder
///-----------------------------------
- (void) readFolder: (NSString *) path depth:(NSString *)depth withUserSessionToken:(NSString *)token
    onCommunication:(OCCommunication *)sharedOCCommunication
     successRequest:(void(^)(NSHTTPURLResponse *response, NSArray *items, NSString *redirectedServer, NSString *token)) successRequest
     failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *token, NSString *redirectedServer)) failureRequest{
    
    if (!token){
        token = @"no token";
    }
    
    path = [path encodeString:NSUTF8StringEncoding];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request listPath:path depth:depth onCommunication:sharedOCCommunication withUserSessionToken:token success:^(NSHTTPURLResponse *response, id responseObject, NSString *token) {
        if (successRequest) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSData *responseData = (NSData*) responseObject;
                
                //            NSString* newStr = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
                //            NSLog(@"newStrReadFolder: %@", newStr);
                
                NCXMLListParser *parser = [NCXMLListParser new];
                [parser initParserWithData:responseData controlFirstFileOfList:true];
                NSMutableArray *list = [parser.list mutableCopy];

                dispatch_async(dispatch_get_main_queue(), ^{
                    successRequest(response, list, request.redirectedServer, token);
                });
            });
        }
    } failure:^(NSHTTPURLResponse *response, id responseData, NSError *error, NSString *token) {
        NSLog(@"Failure");
        failureRequest(response, error, token, request.redirectedServer);
    }];
}

///-----------------------------------
/// @name Read File
///-----------------------------------
- (void) readFile: (NSString *) path
  onCommunication:(OCCommunication *)sharedOCCommunication
   successRequest:(void(^)(NSHTTPURLResponse *response, NSArray *items, NSString *redirectedServer)) successRequest
   failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    path = [path encodeString:NSUTF8StringEncoding];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request propertiesOfPath:path onCommunication:sharedOCCommunication success:^(NSHTTPURLResponse *response, id responseObject) {
        if (successRequest) {
            if (successRequest) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    NSData *responseData = (NSData*) responseObject;
                    
                    //            NSString* newStr = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
                    //            NSLog(@"newStrReadFolder: %@", newStr);
                    
                    NCXMLListParser *parser = [NCXMLListParser new];
                    [parser initParserWithData:responseData controlFirstFileOfList:true];
                    NSMutableArray *list = [parser.list mutableCopy];
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        successRequest(response, list, request.redirectedServer);
                    });
                });
            }
        }
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        failureRequest(response, error, request.redirectedServer);
        
    }];
    
}

///-----------------------------------
/// @name search
///-----------------------------------
- (void)search:(NSString *)path folder:(NSString *)folder fileName:(NSString *)fileName depth:(NSString *)depth lteDateLastModified:(NSString *)lteDateLastModified gteDateLastModified:(NSString *)gteDateLastModified contentType:(NSArray *)contentType withUserSessionToken:(NSString *)token onCommunication:(OCCommunication *)sharedOCCommunication successRequest:(void(^)(NSHTTPURLResponse *response, NSArray *items, NSString *redirectedServer, NSString *token)) successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *token, NSString *redirectedServer)) failureRequest{
    
    if (!token){
        token = @"no token";
    }
    
    path = [path encodeString:NSUTF8StringEncoding];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request search:path folder:folder fileName:fileName depth:depth lteDateLastModified:lteDateLastModified gteDateLastModified:gteDateLastModified contentType:contentType user:_user userID:_userID onCommunication:sharedOCCommunication withUserSessionToken:token success:^(NSHTTPURLResponse *response, id responseObject, NSString *token) {
        if (successRequest) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                NSData *responseData = (NSData*) responseObject;
                
                NCXMLListParser *parser = [NCXMLListParser new];
                [parser initParserWithData:responseData controlFirstFileOfList:false];
                NSMutableArray *list = [parser.list mutableCopy];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    successRequest(response, list, request.redirectedServer, token);
                });
            });
        }
    } failure:^(NSHTTPURLResponse *response, id responseData, NSError *error, NSString *token) {
        
        failureRequest(response, error, token, request.redirectedServer);
    }];
}

- (void)search:(NSString *)path folder:(NSString *)folder fileName:(NSString *)fileName dateLastModified:(NSString *)dateLastModified numberOfItem:(NSInteger)numberOfItem withUserSessionToken:(NSString *)token onCommunication:(OCCommunication *)sharedOCCommunication successRequest:(void(^)(NSHTTPURLResponse *response, NSArray *items, NSString *redirectedServer, NSString *token)) successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *token, NSString *redirectedServer)) failureRequest {
    
    if (!token){
        token = @"no token";
    }
    
    path = [path encodeString:NSUTF8StringEncoding];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request search:path folder:folder fileName:fileName dateLastModified:dateLastModified numberOfItem:numberOfItem userID:_userID onCommunication:sharedOCCommunication withUserSessionToken:token success:^(NSHTTPURLResponse *response, id responseObject, NSString *token) {
        if (successRequest) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                NSData *responseData = (NSData*) responseObject;
                
                NCXMLListParser *parser = [NCXMLListParser new];
                [parser initParserWithData:responseData controlFirstFileOfList:false];
                NSMutableArray *list = [parser.list mutableCopy];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    successRequest(response, list, request.redirectedServer, token);
                });
            });
        }
    } failure:^(NSHTTPURLResponse *response, id responseData, NSError *error, NSString *token) {
        failureRequest(response, error, token, request.redirectedServer);
    }];
}

///-----------------------------------
/// @name Setting favorite
///-----------------------------------
- (void)settingFavoriteServer:(NSString *)path andFileOrFolderPath:(NSString *)filePath favorite:(BOOL)favorite withUserSessionToken:(NSString *)token onCommunication:(OCCommunication *)sharedOCCommunication successRequest:(void(^)(NSHTTPURLResponse *response, NSString *redirectedServer, NSString *token)) successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *token, NSString *redirectedServer)) failureRequest {
    
    if (!token){
        token = @"no token";
    }
    
    path = [NSString stringWithFormat:@"%@/files/%@/%@", path, _userID, filePath];
    path = [path encodeString:NSUTF8StringEncoding];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request settingFavorite:path favorite:favorite onCommunication:sharedOCCommunication withUserSessionToken:token success:^(NSHTTPURLResponse *response, id responseObject, NSString *token) {
        
        if (successRequest) {
            //Return success
            successRequest(response, request.redirectedServer, token);
        }
        
    } failure:^(NSHTTPURLResponse *response, id responseData, NSError *error, NSString *token) {
        
        NSLog(@"Failure");
        failureRequest(response, error, token, request.redirectedServer);
    }];
}

///-----------------------------------
/// @name Listing favorites
///-----------------------------------
- (void)listingFavorites:(NSString *)path folder:(NSString *)folder withUserSessionToken:(NSString *)token onCommunication:(OCCommunication *)sharedOCCommunication successRequest:(void(^)(NSHTTPURLResponse *response, NSArray *items, NSString *redirectedServer, NSString *token)) successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *token, NSString *redirectedServer)) failureRequest{
    
    if (!token){
        token = @"no token";
    }
    
    path = [path encodeString:NSUTF8StringEncoding];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request listingFavorites:path folder:folder user:_user userID:_userID onCommunication:sharedOCCommunication withUserSessionToken:token success:^(NSHTTPURLResponse *response, id responseObject, NSString *token) {
        if (successRequest) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                NSData *responseData = (NSData*) responseObject;
                
                NCXMLListParser *parser = [NCXMLListParser new];
                [parser initParserWithData:responseData controlFirstFileOfList:false];
                NSMutableArray *list = [parser.list mutableCopy];
            
                dispatch_async(dispatch_get_main_queue(), ^{
                    successRequest(response, list, request.redirectedServer, token);
                });
            });
        }
    } failure:^(NSHTTPURLResponse *response, id responseData, NSError *error, NSString *token) {
        failureRequest(response, error, token, request.redirectedServer);
    }];
}

///-----------------------------------
/// @name Download File Session
///-----------------------------------



- (NSURLSessionDownloadTask *) downloadFileSession:(NSString *)remotePath toDestiny:(NSString *)localPath defaultPriority:(BOOL)defaultPriority encode:(BOOL)encode onCommunication:(OCCommunication *)sharedOCCommunication progress:(void(^)(NSProgress *progress))downloadProgress successRequest:(void(^)(NSURLResponse *response, NSURL *filePath)) successRequest failureRequest:(void(^)(NSURLResponse *response, NSError *error)) failureRequest {
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    if (encode) remotePath = [remotePath encodeString:NSUTF8StringEncoding];
    
    NSURLSessionDownloadTask *downloadTask = [request downloadWithSessionPath:remotePath toPath:localPath defaultPriority:defaultPriority onCommunication:sharedOCCommunication progress:^(NSProgress *progress) {
        downloadProgress(progress);
    } success:^(NSURLResponse *response, NSURL *filePath) {
        
        [UtilsFramework addCookiesToStorageFromResponse:(NSURLResponse *) response andPath:[NSURL URLWithString:remotePath]];
        successRequest(response,filePath);
        
    } failure:^(NSURLResponse *response, NSError *error) {
        [UtilsFramework addCookiesToStorageFromResponse:(NSURLResponse *) response andPath:[NSURL URLWithString:remotePath]];
        failureRequest(response,error);
    }];
    
    return downloadTask;
}


///-----------------------------------
/// @name Set Download Task Complete Block
///-----------------------------------


- (void)setDownloadTaskComleteBlock: (NSURL * (^)(NSURLSession *session, NSURLSessionDownloadTask *downloadTask, NSURL *location))block{
    
    [self.downloadSessionManager setDownloadTaskDidFinishDownloadingBlock:block];

    
}


///-----------------------------------
/// @name Set Download Task Did Get Body Data Block
///-----------------------------------


- (void) setDownloadTaskDidGetBodyDataBlock: (void(^)(NSURLSession *session, NSURLSessionDownloadTask *downloadTask, int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpectedToWrite)) block{
    
    [self.downloadSessionManager setDownloadTaskDidWriteDataBlock:^(NSURLSession *session, NSURLSessionDownloadTask *downloadTask, int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpectedToWrite) {
        block(session,downloadTask,bytesWritten,totalBytesWritten,totalBytesExpectedToWrite);
    }];
    
}

///-----------------------------------
/// @name Upload File Session
///-----------------------------------

- (NSURLSessionUploadTask *) uploadFileSession:(NSString *) localPath toDestiny:(NSString *) remotePath encode:(BOOL)encode onCommunication:(OCCommunication *)sharedOCCommunication progress:(void(^)(NSProgress *progress))uploadProgress successRequest:(void(^)(NSURLResponse *response, NSString *redirectedServer)) successRequest failureRequest:(void(^)(NSURLResponse *response, NSString *redirectedServer, NSError *error)) failureRequest failureBeforeRequest:(void(^)(NSError *error)) failureBeforeRequest {
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    if (encode) remotePath = [remotePath encodeString:NSUTF8StringEncoding];
    
    NSURLSessionUploadTask *uploadTask = [request putWithSessionLocalPath:localPath atRemotePath:remotePath onCommunication:sharedOCCommunication progress:^(NSProgress *progress) {
            uploadProgress(progress);
        } success:^(NSURLResponse *response, id responseObjec){
            [UtilsFramework addCookiesToStorageFromResponse:(NSURLResponse *) response andPath:[NSURL URLWithString:remotePath]];
            //TODO: The second parameter is the redirected server
            successRequest(response, @"");
        } failure:^(NSURLResponse *response, id responseObject, NSError *error) {
            [UtilsFramework addCookiesToStorageFromResponse:(NSURLResponse *) response andPath:[NSURL URLWithString:remotePath]];
            //TODO: The second parameter is the redirected server

            NSData *responseData = (NSData*) responseObject;
            
            OCXMLServerErrorsParser *serverErrorParser = [OCXMLServerErrorsParser new];
            
            [serverErrorParser startToParseWithData:responseData withCompleteBlock:^(NSError *err) {
                
                if (err) {
                    failureRequest(response, @"", err);
                }else{
                    failureRequest(response, @"", error);
                }
                
            }];
            
        } failureBeforeRequest:^(NSError *error) {
            failureBeforeRequest(error);
        }];
    
    return uploadTask;
}

///-----------------------------------
/// @name Set Task Did Complete Block
///-----------------------------------

- (void) setTaskDidCompleteBlock: (void(^)(NSURLSession *session, NSURLSessionTask *task, NSError *error)) block{
    
    [self.uploadSessionManager setTaskDidCompleteBlock:^(NSURLSession *session, NSURLSessionTask *task, NSError *error) {

        block(session, task, error);
    }];
    
}


///-----------------------------------
/// @name Set Task Did Send Body Data Block
///-----------------------------------


- (void) setTaskDidSendBodyDataBlock: (void(^)(NSURLSession *session, NSURLSessionTask *task, int64_t bytesSent, int64_t totalBytesSent, int64_t totalBytesExpectedToSend)) block{
    
   [self.uploadSessionManager setTaskDidSendBodyDataBlock:^(NSURLSession *session, NSURLSessionTask *task, int64_t bytesSent, int64_t totalBytesSent, int64_t totalBytesExpectedToSend) {
       block(session, task, bytesSent, totalBytesSent, totalBytesExpectedToSend);
   }];
}

#pragma mark - OC/NC API Calls

- (NSString *) getCurrentServerVersion {
    return self.currentServerVersion;
}

- (void) getServerVersionWithPath:(NSString*) path onCommunication:(OCCommunication *)sharedOCCommunication
                   successRequest:(void(^)(NSHTTPURLResponse *response, NSString *serverVersion, NSString *redirectedServer)) success
                   failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failure{
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    
    if (self.userAgent) {
        [request setUserAgent:self.userAgent];
    }
    
    [request getStatusOfTheServer:path onCommunication:sharedOCCommunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        NSData *data = (NSData*) responseObject;
        NSString *versionString = [NSString new];
        NSError* error=nil;
        
        if (data) {
            NSMutableDictionary *jsonArray = [NSJSONSerialization JSONObjectWithData: data options: NSJSONReadingMutableContainers error: &error];
            if(error) {
                NSLog(@"Error parsing JSON: %@", error);
            } else {
                //Obtain the server version from the version field
                versionString = [jsonArray valueForKey:@"version"];
                self.currentServerVersion = versionString;
            }
        } else {
            NSLog(@"Error parsing JSON: data is null");
        }
        success(response, versionString, request.redirectedServer);
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        failure(response, error, request.redirectedServer);
    }];
    
}

///-----------------------------------
/// @name Get UserName by cookie
///-----------------------------------

- (void) getUserNameByCookie:(NSString *) cookieString ofServerPath:(NSString *)path onCommunication:
(OCCommunication *)sharedOCCommunication success:(void(^)(NSHTTPURLResponse *response, NSData *responseData, NSString *redirectedServer))success
                     failure:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer))failure{
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    
    [request requestUserNameOfServer: path byCookie:cookieString onCommunication:sharedOCCommunication success:^(NSHTTPURLResponse *response, id responseObject) {
        success(response, responseObject, request.redirectedServer);
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        failure(response, error, request.redirectedServer);
    }];
}

- (void) getFeaturesSupportedByServer:(NSString*) path onCommunication:(OCCommunication *)sharedOCCommunication
                     successRequest:(void(^)(NSHTTPURLResponse *response, BOOL hasShareSupport, BOOL hasShareeSupport, BOOL hasCookiesSupport, BOOL hasForbiddenCharactersSupport, BOOL hasCapabilitiesSupport, BOOL hasFedSharesOptionShareSupport, NSString *redirectedServer)) success
                     failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failure{
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    
    if (self.userAgent) {
        [request setUserAgent:self.userAgent];
    }
    
    [request getStatusOfTheServer:path onCommunication:sharedOCCommunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        if (responseObject) {
            
            NSError* error = nil;
            NSMutableDictionary *jsonArray = [NSJSONSerialization JSONObjectWithData: (NSData*) responseObject options: NSJSONReadingMutableContainers error: &error];
            
            if(error) {
                // NSLog(@"Error parsing JSON: %@", error);
                failure(response, error, request.redirectedServer);
            }else{
                
                self.currentServerVersion = [jsonArray valueForKey:@"version"];
                
                BOOL hasShareSupport = [UtilsFramework isServerVersion:self.currentServerVersion higherThanLimitVersion:k_version_support_shared];
                BOOL hasShareeSupport = [UtilsFramework isServerVersion:self.currentServerVersion higherThanLimitVersion:k_version_support_sharee_api];
                BOOL hasCookiesSupport = [UtilsFramework isServerVersion:self.currentServerVersion higherThanLimitVersion:k_version_support_cookies];
                BOOL hasForbiddenCharactersSupport = [UtilsFramework isServerVersion:self.currentServerVersion higherThanLimitVersion:k_version_support_forbidden_characters];
                BOOL hasCapabilitiesSupport = [UtilsFramework isServerVersion:self.currentServerVersion higherThanLimitVersion:k_version_support_capabilities];
                BOOL hasFedSharesOptionShareSupport = [UtilsFramework isServerVersion:self.currentServerVersion higherThanLimitVersion:k_version_support_share_option_fed_share];

                success(response, hasShareSupport, hasShareeSupport, hasCookiesSupport, hasForbiddenCharactersSupport, hasCapabilitiesSupport, hasFedSharesOptionShareSupport, request.redirectedServer);
            }
            
        } else {
            // NSLog(@"Error parsing JSON: data is null");
            failure(response, nil, request.redirectedServer);
        }
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        failure(response, error, request.redirectedServer);
    }];
}

#pragma mark - Share

- (void) readSharedByServer: (NSString *) path
            onCommunication:(OCCommunication *)sharedOCCommunication
             successRequest:(void(^)(NSHTTPURLResponse *response, NSArray *listOfShared, NSString *redirectedServer)) successRequest
             failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    path = [path encodeString:NSUTF8StringEncoding];
    path = [path stringByAppendingString:k_url_acces_shared_api];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request listSharedByServer:path onCommunication:sharedOCCommunication success:^(NSHTTPURLResponse *response, id responseObject) {
        if (successRequest) {
            NSData *responseData = (NSData*) responseObject;
            OCXMLSharedParser *parser = [[OCXMLSharedParser alloc]init];
            
          //NSLog(@"response: %@", [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding]);
            
            [parser initParserWithData:responseData];
            NSMutableArray *sharedList = [parser.shareList mutableCopy];
            
            //Return success
            successRequest(response, sharedList, request.redirectedServer);
        }
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void) readSharedByServer: (NSString *) serverPath andPath: (NSString *) path
            onCommunication:(OCCommunication *)sharedOCCommunication
             successRequest:(void(^)(NSHTTPURLResponse *response, NSArray *listOfShared, NSString *redirectedServer)) successRequest
             failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
   serverPath = [serverPath encodeString:NSUTF8StringEncoding];
   serverPath = [serverPath stringByAppendingString:k_url_acces_shared_api];
    
   path = [path encodeString:NSUTF8StringEncoding];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request listSharedByServer:serverPath andPath:path onCommunication:sharedOCCommunication success:^(NSHTTPURLResponse *response, id responseObject) {
        if (successRequest) {
            NSData *responseData = (NSData*) responseObject;
            OCXMLSharedParser *parser = [[OCXMLSharedParser alloc]init];
            
//            NSString *str = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
//            NSLog(@"responseDataReadSharedByServer:andPath: %@", str);
//            NSLog(@"pathFolders: %@", path);
//            NSLog(@"serverPath: %@", serverPath);
            
            [parser initParserWithData:responseData];
            NSMutableArray *sharedList = [parser.shareList mutableCopy];
            
            //Return success
            successRequest(response, sharedList, request.redirectedServer);
        }
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void) shareFileOrFolderByServer: (NSString *) serverPath andFileOrFolderPath: (NSString *) filePath andPassword:(NSString *)password andPermission:(NSInteger)permission andHideDownload:(BOOL)hideDownload
                   onCommunication:(OCCommunication *)sharedOCCommunication
                    successRequest:(void(^)(NSHTTPURLResponse *response, NSString *token, NSString *redirectedServer)) successRequest
                    failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [serverPath encodeString:NSUTF8StringEncoding];
    serverPath = [serverPath stringByAppendingString:k_url_acces_shared_api];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request shareByLinkFileOrFolderByServer:serverPath andPath:filePath andPassword:password andPermission:permission andHideDownload:hideDownload onCommunication:sharedOCCommunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        NSData *responseData = (NSData*) responseObject;
        
        OCXMLShareByLinkParser *parser = [[OCXMLShareByLinkParser alloc]init];
        
      //  NSLog(@"response: %@", [[NSString alloc] initWithData:response encoding:NSUTF8StringEncoding]);
        
        [parser initParserWithData:responseData];
        
        if (parser.statusCode == kOCSharedAPISuccessful || parser.statusCode == kOCShareeAPISuccessful) {
            
            NSString *url = parser.url;
            NSString *token = parser.token;
            
            if (url != nil) {
                
                successRequest(response, url, request.redirectedServer);
                
            } else if (token != nil) {
                
                //We remove the \n and the empty spaces " "
                token = [token stringByReplacingOccurrencesOfString:@"\n" withString:@""];
                token = [token stringByReplacingOccurrencesOfString:@" " withString:@""];
                
                successRequest(response, token, request.redirectedServer);
                
            } else {
                
                NSError *error = [UtilsFramework getErrorWithCode:parser.statusCode andCustomMessageFromTheServer:parser.message];
                failureRequest(response, error, request.redirectedServer);
            }
            
        } else {
            
            NSError *error = [UtilsFramework getErrorWithCode:parser.statusCode andCustomMessageFromTheServer:parser.message];
            failureRequest(response, error, request.redirectedServer);
        }
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void) shareFileOrFolderByServer: (NSString *) serverPath andFileOrFolderPath: (NSString *) filePath
                   onCommunication:(OCCommunication *)sharedOCCommunication
                    successRequest:(void(^)(NSHTTPURLResponse *response, NSString *shareLink, NSString *redirectedServer)) successRequest
                    failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [serverPath encodeString:NSUTF8StringEncoding];
    serverPath = [serverPath stringByAppendingString:k_url_acces_shared_api];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request shareByLinkFileOrFolderByServer:serverPath andPath:filePath onCommunication:sharedOCCommunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        NSData *responseData = (NSData*) responseObject;
        
        OCXMLShareByLinkParser *parser = [[OCXMLShareByLinkParser alloc]init];
        
      //  NSLog(@"response: %@", [[NSString alloc] initWithData:response encoding:NSUTF8StringEncoding]);
        
        [parser initParserWithData:responseData];
        
        if (parser.statusCode == kOCSharedAPISuccessful || parser.statusCode == kOCShareeAPISuccessful) {
            
            NSString *url = parser.url;
            NSString *token = parser.token;
            
            if (url != nil) {
                
                successRequest(response, url, request.redirectedServer);
                
            } else if (token != nil) {
                //We remove the \n and the empty spaces " "
                token = [token stringByReplacingOccurrencesOfString:@"\n" withString:@""];
                token = [token stringByReplacingOccurrencesOfString:@" " withString:@""];
                
                successRequest(response, token, request.redirectedServer);
                
            } else {
                
                NSError *error = [UtilsFramework getErrorWithCode:parser.statusCode andCustomMessageFromTheServer:parser.message];
                failureRequest(response, error, request.redirectedServer);
            }

        } else {
            
            NSError *error = [UtilsFramework getErrorWithCode:parser.statusCode andCustomMessageFromTheServer:parser.message];
            failureRequest(response, error, request.redirectedServer);
        }
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)shareWith:(NSString *)userOrGroup shareeType:(NSInteger)shareeType inServer:(NSString *) serverPath andFileOrFolderPath:(NSString *) filePath andPermissions:(NSInteger) permissions onCommunication:(OCCommunication *)sharedOCCommunication
          successRequest:(void(^)(NSHTTPURLResponse *response, NSString *redirectedServer))successRequest
          failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer))failureRequest{
    
    serverPath = [serverPath encodeString:NSUTF8StringEncoding];
    serverPath = [serverPath stringByAppendingString:k_url_acces_shared_api];
    userOrGroup = [userOrGroup encodeString:NSUTF8StringEncoding];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request shareWith:userOrGroup shareeType:shareeType inServer:serverPath andPath:filePath andPermissions:permissions onCommunication:sharedOCCommunication success:^(NSHTTPURLResponse *response, id responseObject) {
        NSData *responseData = (NSData*) responseObject;
        
        OCXMLShareByLinkParser *parser = [[OCXMLShareByLinkParser alloc]init];
        
        //  NSLog(@"response: %@", [[NSString alloc] initWithData:response encoding:NSUTF8StringEncoding]);
        
        [parser initParserWithData:responseData];
        
        if (parser.statusCode == kOCSharedAPISuccessful || parser.statusCode == kOCShareeAPISuccessful) {
            successRequest(response, request.redirectedServer);
        } else {
            NSError *error = [UtilsFramework getErrorWithCode:parser.statusCode andCustomMessageFromTheServer:parser.message];
            failureRequest(response, error, request.redirectedServer);
        }
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        failureRequest(response, error, request.redirectedServer);
    }];
    
}

- (void) unShareFileOrFolderByServer: (NSString *) path andIdRemoteShared: (NSInteger) idRemoteShared
                     onCommunication:(OCCommunication *)sharedOCCommunication
                      successRequest:(void(^)(NSHTTPURLResponse *response, NSString *redirectedServer)) successRequest
                      failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest{
    
    path = [path encodeString:NSUTF8StringEncoding];
    path = [path stringByAppendingString:k_url_acces_shared_api];
    path = [path stringByAppendingString:[NSString stringWithFormat:@"/%ld",(long)idRemoteShared]];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request unShareFileOrFolderByServer:path onCommunication:sharedOCCommunication success:^(NSHTTPURLResponse *response, id responseObject) {
        if (successRequest) {
            //Return success
            successRequest(response, request.redirectedServer);
        }
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void) isShareFileOrFolderByServer: (NSString *) path andIdRemoteShared: (NSInteger) idRemoteShared
                     onCommunication:(OCCommunication *)sharedOCCommunication
                      successRequest:(void(^)(NSHTTPURLResponse *response, NSString *redirectedServer, BOOL isShared, id shareDto)) successRequest
                      failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    path = [path encodeString:NSUTF8StringEncoding];
    path = [path stringByAppendingString:k_url_acces_shared_api];
    path = [path stringByAppendingString:[NSString stringWithFormat:@"/%ld",(long)idRemoteShared]];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request isShareFileOrFolderByServer:path onCommunication:sharedOCCommunication success:^(NSHTTPURLResponse *response, id responseObject) {
        if (successRequest) {
        
            NSData *responseData = (NSData*) responseObject;
            OCXMLSharedParser *parser = [[OCXMLSharedParser alloc]init];
            
            // NSLog(@"response: %@", [[NSString alloc] initWithData:response encoding:NSUTF8StringEncoding]);
            
            [parser initParserWithData:responseData];
            
             BOOL isShared = NO;
            
             OCSharedDto *shareDto = nil;
            
            if (parser.shareList) {
                
                NSMutableArray *sharedList = [parser.shareList mutableCopy];
                
                if ([sharedList count] > 0) {
                    isShared = YES;
                    shareDto = [sharedList objectAtIndex:0];
                }
                
            }
     
            //Return success
            successRequest(response, request.redirectedServer, isShared, shareDto);
        }
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void) updateShare:(NSInteger)shareId ofServerPath:(NSString *)serverPath withPasswordProtect:(NSString*)password andNote:(NSString *)note andExpirationTime:(NSString*)expirationTime andPermissions:(NSInteger)permissions andHideDownload:(BOOL)hideDownload
                   onCommunication:(OCCommunication *)sharedOCCommunication
                    successRequest:(void(^)(NSHTTPURLResponse *response, NSString *redirectedServer)) successRequest
      failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest{
    
    serverPath = [serverPath encodeString:NSUTF8StringEncoding];
    serverPath = [serverPath stringByAppendingString:k_url_acces_shared_api];
    serverPath = [serverPath stringByAppendingString:[NSString stringWithFormat:@"/%ld",(long)shareId]];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request updateShareItem:shareId ofServerPath:serverPath withPasswordProtect:password andNote:note andExpirationTime:expirationTime andPermissions:permissions andHideDownload:hideDownload onCommunication:sharedOCCommunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        NSData *responseData = (NSData*) responseObject;
        
        OCXMLShareByLinkParser *parser = [[OCXMLShareByLinkParser alloc]init];
        
     //   NSLog(@"response: %@", [[NSString alloc] initWithData:response encoding:NSUTF8StringEncoding]);
        
        [parser initParserWithData:responseData];
        
        if (parser.statusCode == kOCSharedAPISuccessful || parser.statusCode == kOCShareeAPISuccessful) {
            successRequest(response, request.redirectedServer);
        } else {
            NSError *error = [UtilsFramework getErrorWithCode:parser.statusCode andCustomMessageFromTheServer:parser.message];
            failureRequest(response, error, request.redirectedServer);
        }
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
         failureRequest(response, error, request.redirectedServer);
    }];
    
}

- (void) searchUsersAndGroupsWith:(NSString *)searchString forPage:(NSInteger)page with:(NSInteger)resultsPerPage ofServer:(NSString*)serverPath onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSArray *itemList, NSString *redirectedServer)) successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest{
    
    serverPath = [serverPath encodeString:NSUTF8StringEncoding];
    serverPath = [serverPath stringByAppendingString:k_url_access_sharee_api];
    
    searchString = [searchString encodeString:NSUTF8StringEncoding];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request searchUsersAndGroupsWith:searchString forPage:page with:resultsPerPage ofServer:serverPath onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        NSData *responseData = (NSData*) responseObject;
        
        NSMutableArray *itemList = [NSMutableArray new];
        
        //Parse
        NSError *error;
        NSDictionary *jsongParsed = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingMutableContainers error:&error];
        
        if (error == nil) {
            
            NSDictionary *ocsDict = [jsongParsed valueForKey:@"ocs"];
            
            NSDictionary *metaDict = [ocsDict valueForKey:@"meta"];
            NSInteger statusCode = [[metaDict valueForKey:@"statuscode"] integerValue];
            
            if (statusCode == kOCShareeAPISuccessful || statusCode == kOCSharedAPISuccessful) {
                
                NSDictionary *dataDict = [ocsDict valueForKey:@"data"];
                NSArray *exactDict = [dataDict valueForKey:@"exact"];
                NSArray *usersFounded = [dataDict valueForKey:@"users"];
                NSArray *groupsFounded = [dataDict valueForKey:@"groups"];
                NSArray *usersRemote = [dataDict valueForKey:@"remotes"];
                NSArray *usersExact = [exactDict valueForKey:@"users"];
                NSArray *groupsExact = [exactDict valueForKey:@"groups"];
                NSArray *remotesExact = [exactDict valueForKey:@"remotes"];
                
                [self addUserItemOfType:shareTypeUser fromArray:usersFounded ToList:itemList];
                [self addUserItemOfType:shareTypeUser fromArray:usersExact ToList:itemList];
                [self addUserItemOfType:shareTypeRemote fromArray:usersRemote ToList:itemList];
                [self addUserItemOfType:shareTypeRemote fromArray:remotesExact ToList:itemList];
                [self addGroupItemFromArray:groupsFounded ToList:itemList];
                [self addGroupItemFromArray:groupsExact ToList:itemList];
            
            }else{
                
                NSString *message = (NSString*)[metaDict objectForKey:@"message"];
                
                if ([message isKindOfClass:[NSNull class]]) {
                    message = @"";
                }
                
                NSError *error = [UtilsFramework getErrorWithCode:statusCode andCustomMessageFromTheServer:message];
                failureRequest(response, error, request.redirectedServer);
                
            }
            
            //Return success
            successRequest(response, itemList, request.redirectedServer);
            
        }
        
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        failureRequest(response, error, request.redirectedServer);
    }];
}

#pragma mark - Capabilities

- (void) getCapabilitiesOfServer:(NSString*)serverPath onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, OCCapabilities *capabilities, NSString *redirectedServer)) successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest{
    
    serverPath = [serverPath encodeString:NSUTF8StringEncoding];
    serverPath = [serverPath stringByAppendingString:k_url_capabilities];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request getCapabilitiesOfServer:serverPath onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        NSData *responseData = (NSData*) responseObject;
        OCCapabilities *capabilities = [OCCapabilities new];
        
        //Parse
        NSError *error;
        NSDictionary *jsongParsed = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingMutableContainers error:&error];
        NSLog(@"dic: %@",jsongParsed);
        
        if (jsongParsed && jsongParsed.allKeys > 0) {
            
            NSDictionary *ocs = [jsongParsed valueForKey:@"ocs"];
            NSDictionary *data = [ocs valueForKey:@"data"];
            NSDictionary *version = [data valueForKey:@"version"];
            
            if (ocs.count > 0 && data.count > 0 && version.count > 0) {
            
                //VERSION
            
                NSNumber *versionMajorNumber = (NSNumber*) [version valueForKey:@"major"];
                NSNumber *versionMinorNumber = (NSNumber*) [version valueForKey:@"minor"];
                NSNumber *versionMicroNumber = (NSNumber*) [version valueForKey:@"micro"];
            
                capabilities.versionMajor = versionMajorNumber.integerValue;
                capabilities.versionMinor = versionMinorNumber.integerValue;
                capabilities.versionMicro = versionMicroNumber.integerValue;
            
                capabilities.versionString = (NSString*)[version valueForKey:@"string"];
                capabilities.versionEdition = (NSString*)[version valueForKey:@"edition"];
            
                NSDictionary *capabilitiesDict = [data valueForKey:@"capabilities"];
                
                //CORE
            
                NSDictionary *core = [capabilitiesDict valueForKey:@"core"];
                
                NSNumber *corePollIntervalNumber = (NSNumber*)[core valueForKey:@"pollinterval"];
                capabilities.corePollInterval = corePollIntervalNumber.integerValue;
                capabilities.coreWebDavRoot = [core valueForKey:@"webdav-root"];
            
                //FILE SHARING
                
                NSDictionary *fileSharing = [capabilitiesDict valueForKey:@"files_sharing"];
            
                NSNumber *fileSharingAPIEnabled = (NSNumber*)[fileSharing valueForKey:@"api_enabled"];
                NSNumber *filesSharingDefaultPermissions = (NSNumber*)[fileSharing valueForKey:@"default_permissions"];
                NSNumber *fileSharingGroupSharing = (NSNumber*)[fileSharing valueForKey:@"group_sharing"];
                NSNumber *filesSharingReSharing = (NSNumber*)[fileSharing valueForKey:@"resharing"];
                
                capabilities.isFilesSharingAPIEnabled = fileSharingAPIEnabled.boolValue;
                capabilities.filesSharingDefaulPermissions = filesSharingDefaultPermissions.integerValue;
                capabilities.isFilesSharingGroupSharing = fileSharingGroupSharing.boolValue;
                capabilities.isFilesSharingReSharing = filesSharingReSharing.boolValue;

                //FILE SHARING - PUBLIC
                
                NSDictionary *fileSharingPublic = [fileSharing valueForKey:@"public"];
            
                NSNumber *filesSharingPublicShareLinkEnabledNumber = (NSNumber*)[fileSharingPublic valueForKey:@"enabled"];
                NSNumber *filesSharingAllowPublicUploadsEnabledNumber = (NSNumber*)[fileSharingPublic valueForKey:@"upload"];
                NSNumber *isFilesSharingAllowPublicUserSendMailNumber = (NSNumber*)[fileSharingPublic valueForKey:@"send_mail"];
                NSNumber *filesSharingAllowPublicUploadFilesDrop = (NSNumber*)[fileSharingPublic valueForKey:@"upload_files_drop"];
                NSNumber *filesSharingAllowPublicMultipleLinks = (NSNumber*)[fileSharingPublic valueForKey:@"multiple_links"];
                
                capabilities.isFilesSharingPublicShareLinkEnabled = filesSharingPublicShareLinkEnabledNumber.boolValue;
                capabilities.isFilesSharingAllowPublicUploadsEnabled = filesSharingAllowPublicUploadsEnabledNumber.boolValue;
                capabilities.isFilesSharingAllowPublicUserSendMail = isFilesSharingAllowPublicUserSendMailNumber.boolValue;
                capabilities.isFilesSharingAllowPublicUploadFilesDrop = filesSharingAllowPublicUploadFilesDrop.boolValue;
                capabilities.isFilesSharingAllowPublicMultipleLinks = filesSharingAllowPublicMultipleLinks.boolValue;
                
                NSDictionary *fileSharingPublicExpireDate = [fileSharingPublic valueForKey:@"expire_date"];
            
                NSNumber *filesSharingPublicExpireDateByDefaultEnabledNumber = (NSNumber*)[fileSharingPublicExpireDate valueForKey:@"enabled"];
                NSNumber *filesSharingPublicExpireDateEnforceEnabledNumber = (NSNumber*)[fileSharingPublicExpireDate valueForKey:@"enforced"];
                NSNumber *filesSharingPublicExpireDateDaysNumber = (NSNumber*)[fileSharingPublicExpireDate valueForKey:@"days"];
    
                capabilities.isFilesSharingPublicExpireDateByDefaultEnabled = filesSharingPublicExpireDateByDefaultEnabledNumber.boolValue;
                capabilities.isFilesSharingPublicExpireDateEnforceEnabled = filesSharingPublicExpireDateEnforceEnabledNumber.boolValue;
                capabilities.filesSharingPublicExpireDateDays = filesSharingPublicExpireDateDaysNumber.integerValue;
            
                NSDictionary *fileSharingPublicPassword = [fileSharingPublic valueForKey:@"password"];
            
                NSNumber *fileSharingPublicPasswordEnforcedEnabled = (NSNumber*)[fileSharingPublicPassword valueForKey:@"enforced"];
            
                capabilities.isFilesSharingPublicPasswordEnforced = fileSharingPublicPasswordEnforcedEnabled.boolValue;
            
                //FILE SHARING - USER

                NSDictionary *fileSharingUser = [fileSharing valueForKey:@"user"];
            
                NSNumber *isFilesSharingAllowUserSendMailNumber = (NSNumber*)[fileSharingUser valueForKey:@"send_mail"];
            
                capabilities.isFilesSharingAllowUserSendMail = isFilesSharingAllowUserSendMailNumber.boolValue;
            
                NSDictionary *fileSharingUserExpireDate = [fileSharingUser valueForKey:@"expire_date"];

                NSNumber *filesSharingUserExpireDateNumber = (NSNumber*)[fileSharingUserExpireDate valueForKey:@"enabled"];

                capabilities.isFilesSharingUserExpireDate = filesSharingUserExpireDateNumber.boolValue;
                
                //FILE SHARING - GROUP
                
                NSDictionary *fileSharingGroup = [fileSharing valueForKey:@"group"];
                
                NSNumber *filesSharingGroupEnabled = (NSNumber*)[fileSharingGroup valueForKey:@"enabled"];
                
                capabilities.isFilesSharingGroupEnabled = filesSharingGroupEnabled.boolValue;
                
                NSDictionary *fileSharingGroupExpireDate = [fileSharingGroup valueForKey:@"expire_date"];

                NSNumber *filesSharingGroupExpireDateNumber = (NSNumber*)[fileSharingGroupExpireDate valueForKey:@"enabled"];
                
                capabilities.isFilesSharingGroupExpireDate = filesSharingGroupExpireDateNumber.boolValue;
                
                //FILE SHARING - FEDERATION
            
                NSDictionary *fileSharingFederation = [fileSharing valueForKey:@"federation"];
                NSDictionary *fileSharingFederationExpireDate = [fileSharingFederation valueForKey:@"expire_date"];

                NSNumber *filesSharingFederationAllowUserSendSharesNumber = (NSNumber*)[fileSharingFederation valueForKey:@"outgoing"];
                NSNumber *filesSharingFederationAllowUserReceiveSharesNumber = (NSNumber*)[fileSharingFederation valueForKey:@"incoming"];
                NSNumber *filesSharingFederationExpireDateNumber = (NSNumber*)[fileSharingFederationExpireDate valueForKey:@"enabled"];

                capabilities.isFilesSharingFederationAllowUserSendShares = filesSharingFederationAllowUserSendSharesNumber.boolValue;
                capabilities.isFilesSharingFederationAllowUserReceiveShares = filesSharingFederationAllowUserReceiveSharesNumber.boolValue;
                capabilities.isFilesSharingFederationExpireDate = filesSharingFederationExpireDateNumber.boolValue;
            
                //FILE SHARING - SHAREBYMAIL
                
                NSDictionary *fileSharingShareByMail = [fileSharing valueForKey:@"sharebymail"];

                NSNumber *fileSharingShareByMailEnabled = (NSNumber*)[fileSharingShareByMail valueForKey:@"enabled"];
                
                capabilities.isFileSharingShareByMailEnabled = fileSharingShareByMailEnabled.boolValue;
                
                NSDictionary *fileSharingShareByMailExpireDate = [fileSharingShareByMail valueForKey:@"expire_date"];

                NSNumber *fileSharingShareByMailExpireDateNumber = (NSNumber*)[fileSharingShareByMailExpireDate valueForKey:@"enabled"];

                capabilities.isFileSharingShareByMailExpireDate = fileSharingShareByMailExpireDateNumber.boolValue;
                
                NSDictionary *fileSharingShareByMailPassword = [fileSharingShareByMail valueForKey:@"password"];
                
                NSNumber *fileSharingShareByMailPasswordNumber = (NSNumber*)[fileSharingShareByMailPassword valueForKey:@"enabled"];

                capabilities.isFileSharingShareByMailPassword = fileSharingShareByMailPasswordNumber.boolValue;

                NSDictionary *fileSharingShareByMailUploadFilesDrop = [fileSharingShareByMail valueForKey:@"upload_files_drop"];

                NSNumber *fileSharingShareByMailUploadFilesDropNumber = (NSNumber*)[fileSharingShareByMailUploadFilesDrop valueForKey:@"enabled"];

                capabilities.isFileSharingShareByMailUploadFilesDrop = fileSharingShareByMailUploadFilesDropNumber.boolValue;

                // EXTERNAL SITES
            
                NSDictionary *externalSitesDic = [capabilitiesDict valueForKey:@"external"];
                if (externalSitesDic) {
                    capabilities.isExternalSitesServerEnabled = YES;
                    NSArray *externalSitesArray = [externalSitesDic valueForKey:@"v1"];
                    capabilities.externalSiteV1 = [externalSitesArray componentsJoinedByString:@","];
                }
                
                // ACTIVITY
                
                NSDictionary *activityDic = [capabilitiesDict valueForKey:@"activity"];
                if (activityDic) {
                    NSArray *activityArray = [activityDic valueForKey:@"apiv2"];
                    if (activityArray) {
                        capabilities.isActivityV2Enabled = YES;
                        capabilities.activityV2 = [activityArray componentsJoinedByString:@","];
                    }
                }

                // NOTIFICATION
                
                NSDictionary *notificationDic = [capabilitiesDict valueForKey:@"notifications"];
                if (notificationDic) {
                    capabilities.isNotificationServerEnabled = YES;
                    NSArray *ocsendpointsArray = [notificationDic valueForKey:@"ocs-endpoints"];
                    capabilities.notificationOcsEndpoints = [ocsendpointsArray componentsJoinedByString:@","];
                    NSArray *pushArray = [notificationDic valueForKey:@"push"];
                    capabilities.notificationPush = [pushArray componentsJoinedByString:@","];
                }
                
                // SPREED
                
                NSDictionary *spreedDic = [capabilitiesDict valueForKey:@"spreed"];
                if (spreedDic) {
                    capabilities.isSpreedServerEnabled = YES;
                    NSArray *featuresArray = [capabilitiesDict valueForKey:@"features"];
                    capabilities.spreedFeatures = [featuresArray componentsJoinedByString:@","];
                }
                
                //FILES
            
                NSDictionary *files = [capabilitiesDict valueForKey:@"files"];
            
                NSNumber *fileBigFileChunkingEnabledNumber = (NSNumber*)[files valueForKey:@"bigfilechunking"];
                NSNumber *fileUndeleteEnabledNumber = (NSNumber*)[files valueForKey:@"undelete"];
                NSNumber *fileVersioningEnabledNumber = (NSNumber*)[files valueForKey:@"versioning"];
            
                capabilities.isFileBigFileChunkingEnabled = fileBigFileChunkingEnabledNumber.boolValue;
                capabilities.isFileUndeleteEnabled = fileUndeleteEnabledNumber.boolValue;
                capabilities.isFileVersioningEnabled = fileVersioningEnabledNumber.boolValue;
            
                NSDictionary *pagination = [files valueForKey:@"pagination"];
                if (pagination) {
                    capabilities.isPaginationEnabled = true;
                    capabilities.paginationEndponit = [pagination valueForKey:@"endpoint"];
                }
                
                //THEMING
            
                NSDictionary *theming = [capabilitiesDict valueForKey:@"theming"];
            
                if ([theming count] > 0) {
                
                    if ([theming valueForKey:@"background"] && ![[theming valueForKey:@"background"] isEqual:[NSNull null]])
                        capabilities.themingBackground = [theming valueForKey:@"background"];
                
                    if ([theming valueForKey:@"background-default"] && ![[theming valueForKey:@"background-default"] isEqual:[NSNull null]]) {
                        NSNumber *result = (NSNumber*)[theming valueForKey:@"background-default"];
                        capabilities.themingBackgroundDefault = result.boolValue;
                    }
                    
                    if ([theming valueForKey:@"background-plain"] && ![[theming valueForKey:@"background-plain"] isEqual:[NSNull null]]) {
                        NSNumber *result = (NSNumber*)[theming valueForKey:@"background-plain"];
                        capabilities.themingBackgroundPlain = result.boolValue;
                    }
                    
                    if ([theming valueForKey:@"color"] && ![[theming valueForKey:@"color"] isEqual:[NSNull null]])
                        capabilities.themingColor = [theming valueForKey:@"color"];
                
                    if ([theming valueForKey:@"color-element"] && ![[theming valueForKey:@"color-element"] isEqual:[NSNull null]])
                        capabilities.themingColorElement = [theming valueForKey:@"color-element"];
                    
                    if ([theming valueForKey:@"color-text"] && ![[theming valueForKey:@"color-text"] isEqual:[NSNull null]])
                        capabilities.themingColorText = [theming valueForKey:@"color-text"];
                    
                    if ([theming valueForKey:@"logo"] && ![[theming valueForKey:@"logo"] isEqual:[NSNull null]])
                        capabilities.themingLogo = [theming valueForKey:@"logo"];
                
                    if ([theming valueForKey:@"name"] && ![[theming valueForKey:@"name"] isEqual:[NSNull null]])
                        capabilities.themingName = [theming valueForKey:@"name"];
                
                    if ([theming valueForKey:@"slogan"] && ![[theming valueForKey:@"slogan"] isEqual:[NSNull null]])
                        capabilities.themingSlogan = [theming valueForKey:@"slogan"];
                
                    if ([theming valueForKey:@"url"] && ![[theming valueForKey:@"url"] isEqual:[NSNull null]])
                        capabilities.themingUrl = [theming valueForKey:@"url"];
                }
                
                //END TO END Encryption
                
                NSDictionary *endToEndEncryption = [capabilitiesDict valueForKey:@"end-to-end-encryption"];
                
                if ([endToEndEncryption count] > 0) {
                    
                    NSNumber *endToEndEncryptionEnabled = (NSNumber*)[endToEndEncryption valueForKey:@"enabled"];
                    capabilities.isEndToEndEncryptionEnabled = endToEndEncryptionEnabled.boolValue;
                    
                    if ([endToEndEncryption valueForKey:@"api-version"] && ![[endToEndEncryption valueForKey:@"api-version"] isEqual:[NSNull null]])
                        capabilities.endToEndEncryptionVersion = [endToEndEncryption valueForKey:@"api-version"];
                }
                
                //Richdocuments
                
                NSDictionary *richdocuments = [capabilitiesDict valueForKey:@"richdocuments"];
                
                if (richdocuments!= nil && [richdocuments count] > 0) {
                    capabilities.richdocumentsDirectEditing = [[richdocuments valueForKey:@"direct_editing"] boolValue];
                    capabilities.richdocumentsMimetypes = [richdocuments valueForKey:@"mimetypes"];
                }
                
                //Handwerkcloud
                
                NSDictionary *handwerkcloudDic = [capabilitiesDict valueForKey:@"handwerkcloud"];
                if (handwerkcloudDic) {
                    NSNumber *isHandwerkcloudEnabledNumber = (NSNumber*)[handwerkcloudDic valueForKey:@"enabled"];
                    capabilities.isHandwerkcloudEnabled = isHandwerkcloudEnabledNumber.boolValue;
                    
                    if ([handwerkcloudDic valueForKey:@"shop_url"] && ![[handwerkcloudDic valueForKey:@"shop_url"] isEqual:[NSNull null]])
                        capabilities.HCShopUrl = [handwerkcloudDic valueForKey:@"shop_url"];
                }
                
                //Imagemeter
                
                NSDictionary *imagemeterDic = [capabilitiesDict valueForKey:@"imagemeter"];
                if (imagemeterDic) {
                    NSNumber *isImagemeterEnabledNumber = (NSNumber*)[imagemeterDic valueForKey:@"enabled"];
                    capabilities.isImagemeterEnabled = isImagemeterEnabledNumber.boolValue;
                }
                
                //Fulltextsearch
                NSDictionary *fulltextsearchDic = [capabilitiesDict valueForKey:@"fulltextsearch"];
                if (fulltextsearchDic) {
                    NSNumber *isFulltextsearchEnabledNumber = (NSNumber*)[fulltextsearchDic valueForKey:@"remote"];
                    capabilities.isFulltextsearchEnabled = isFulltextsearchEnabledNumber.boolValue;
                }
                
                //extendedSupport
                NSDictionary *extendedSupportDic = [capabilitiesDict valueForKey:@"extendedSupport"];
                if (extendedSupportDic) {
                    NSNumber *isExtendedSupportEnabled = (NSNumber*)[extendedSupportDic valueForKey:@"enabled"];
                    capabilities.isExtendedSupportEnabled = isExtendedSupportEnabled.boolValue;
                }
            }
        
            successRequest(response, capabilities, request.redirectedServer);
            
        } else {
            failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
        }
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        failureRequest(response, error, request.redirectedServer);
    }];
}

#pragma mark - Thumbnail

- (NSURLSessionTask *) getRemoteThumbnailByServer:(NSString*)serverPath ofFilePath:(NSString *)filePath withWidth:(NSInteger)fileWidth andHeight:(NSInteger)fileHeight onCommunication:(OCCommunication *)sharedOCComunication
                     successRequest:(void(^)(NSHTTPURLResponse *response, NSData *thumbnail, NSString *redirectedServer)) successRequest
                     failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [serverPath encodeString:NSUTF8StringEncoding];
    filePath = [filePath encodeString:NSUTF8StringEncoding];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    
    OCHTTPRequestOperation *operation = [request getRemoteThumbnailByServer:serverPath ofFilePath:filePath withWidth:fileWidth andHeight:fileHeight onCommunication:sharedOCComunication
            success:^(NSHTTPURLResponse *response, id responseObject) {
                NSData *responseData = (NSData*) responseObject;
                
                successRequest(response, responseData, request.redirectedServer);
                                    
            } failure:^(NSHTTPURLResponse *response, id  _Nullable responseObject, NSError * _Nonnull error) {
                failureRequest(response, error, request.redirectedServer);
            }];
    
    [operation resume];

    return operation;
}

- (NSURLSessionTask *) getRemotePreviewByServer:(NSString*)serverPath ofFilePath:(NSString *)filePath withWidth:(NSInteger)fileWidth andHeight:(NSInteger)fileHeight andA:(NSInteger)a andMode:(NSString * _Nonnull)mode path:(NSString * _Nonnull)path onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSData *preview, NSString *redirectedServer)) successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [serverPath encodeString:NSUTF8StringEncoding];
    filePath = [filePath encodeString:NSUTF8StringEncoding];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    OCHTTPRequestOperation *operation = [request getRemotePreviewByServer:serverPath ofFilePath:filePath withWidth:fileWidth andHeight:fileHeight andA:a andMode:mode path:path onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        NSData *responseData = (NSData*) responseObject;
        
        successRequest(response, responseData, request.redirectedServer);
        
    } failure:^(NSHTTPURLResponse *response, id  _Nullable responseObject, NSError * _Nonnull error) {
        
        failureRequest(response, error, request.redirectedServer);

    }];
    
    [operation resume];
    
    return operation;
}

- (NSURLSessionTask *) getRemotePreviewTrashByServer:(NSString*)serverPath ofFileId:(NSString *)fileId size:(NSString *)size onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSData *preview, NSString *redirectedServer)) successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [serverPath encodeString:NSUTF8StringEncoding];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    OCHTTPRequestOperation *operation = [request getRemotePreviewTrashByServer:serverPath ofFileId:fileId size:size onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        NSData *responseData = (NSData*) responseObject;
        
        successRequest(response, responseData, request.redirectedServer);
        
    } failure:^(NSHTTPURLResponse *response, id  _Nullable responseObject, NSError * _Nonnull error) {
        
        failureRequest(response, error, request.redirectedServer);
    }];
    
    [operation resume];
    
    return operation;
}

#pragma mark - Notification

- (void)getNotificationServer:(NSString*)serverPath onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSArray *listOfNotifications, NSString *redirectedServer)) successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [serverPath encodeString:NSUTF8StringEncoding];
    serverPath = [serverPath stringByAppendingString:k_url_acces_remote_notification_api];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request getNotificationServer:serverPath onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSData *responseData = (NSData*) responseObject;
            NSMutableArray *listOfNotifications = [NSMutableArray new];

            //Parse
            NSError *error;
            NSDictionary *jsongParsed = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingMutableContainers error:&error];
            NSLog(@"[LOG] Notifications : %@",jsongParsed);
            
            if (jsongParsed && jsongParsed.allKeys > 0) {
            
                NSDictionary *ocs = [jsongParsed valueForKey:@"ocs"];
                NSDictionary *meta = [ocs valueForKey:@"meta"];
                NSDictionary *datas = [ocs valueForKey:@"data"];
            
                NSInteger statusCode = [[meta valueForKey:@"statuscode"] integerValue];
                
                if (statusCode == kOCNotificationAPINoContent || statusCode == kOCNotificationAPISuccessful) {
                    
                    for (NSDictionary *data in datas) {
                    
                        OCNotifications *notification = [OCNotifications new];
                        
                        if ([data valueForKey:@"notification_id"] && ![[data valueForKey:@"notification_id"] isEqual:[NSNull null]])
                            notification.idNotification = [[data valueForKey:@"notification_id"] integerValue];
                        
                        if ([data valueForKey:@"app"] && ![[data valueForKey:@"app"] isEqual:[NSNull null]])
                            notification.application = [data valueForKey:@"app"];
                        
                        if ([data valueForKey:@"user"] && ![[data valueForKey:@"user"] isEqual:[NSNull null]])
                            notification.user = [data valueForKey:@"user"];
                        
                        if ([data valueForKey:@"datetime"] && ![[data valueForKey:@"datetime"] isEqual:[NSNull null]]) {
                            
                            NSString *dateString = [data valueForKey:@"datetime"];
                            
                            NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
                            NSLocale *enUSPOSIXLocale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
                            [dateFormatter setLocale:enUSPOSIXLocale];
                            [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZZZZZ"];
                            
                            notification.date = [dateFormatter dateFromString:dateString];
                        }
                        
                        if ([data valueForKey:@"object_type"] && ![[data valueForKey:@"object_type"] isEqual:[NSNull null]])
                            notification.typeObject = [data valueForKey:@"object_type"];
                        
                        if ([data valueForKey:@"object_id"] && ![[data valueForKey:@"object_id"] isEqual:[NSNull null]])
                            notification.idObject = [data valueForKey:@"object_id"];
                        
                        if ([data valueForKey:@"subject"] && ![[data valueForKey:@"subject"] isEqual:[NSNull null]])
                            notification.subject = [data valueForKey:@"subject"];
                        
                        if ([data valueForKey:@"subjectRich"] && ![[data valueForKey:@"subjectRich"] isEqual:[NSNull null]])
                            notification.subjectRich = [data valueForKey:@"subjectRich"];
                        
                        if ([data valueForKey:@"subjectRichParameters"] && ![[data valueForKey:@"subjectRichParameters"] isEqual:[NSNull null]] && [[data valueForKey:@"subjectRichParameters"] count] > 0)
                            notification.subjectRichParameters = [data valueForKey:@"subjectRichParameters"];
                        
                        if ([data valueForKey:@"message"] && ![[data valueForKey:@"message"] isEqual:[NSNull null]])
                            notification.message = [data valueForKey:@"message"];
                        
                        if ([data valueForKey:@"messageRich"] && ![[data valueForKey:@"messageRich"] isEqual:[NSNull null]])
                            notification.messageRich = [data valueForKey:@"messageRich"];
                        
                        if ([data valueForKey:@"messageRichParameters"] && ![[data valueForKey:@"messageRichParameters"] isEqual:[NSNull null]] && [[data valueForKey:@"messageRichParameters"] count] > 0)
                            notification.messageRichParameters = [data valueForKey:@"messageRichParameters"];
                        
                        if ([data valueForKey:@"link"] && ![[data valueForKey:@"link"] isEqual:[NSNull null]])
                            notification.link = [data valueForKey:@"link"];
                        
                        if ([data valueForKey:@"icon"] && ![[data valueForKey:@"icon"] isEqual:[NSNull null]])
                            notification.icon = [data valueForKey:@"icon"];
                        
                        /* ACTION */
                        
                        NSMutableArray *actionsArr = [NSMutableArray new];
                        NSDictionary *actions = [data valueForKey:@"actions"];
                        
                        for (NSDictionary *action in actions) {
                            
                            OCNotificationsAction *notificationAction = [OCNotificationsAction new];
                            
                            if ([action valueForKey:@"label"] && ![[action valueForKey:@"label"] isEqual:[NSNull null]])
                                notificationAction.label = [action valueForKey:@"label"];
                            
                            if ([action valueForKey:@"link"] && ![[action valueForKey:@"link"] isEqual:[NSNull null]])
                                notificationAction.link = [action valueForKey:@"link"];
                            
                            if ([action valueForKey:@"primary"] && ![[action valueForKey:@"primary"] isEqual:[NSNull null]])
                                notificationAction.primary = [[action valueForKey:@"primary"] boolValue];
                            
                            if ([action valueForKey:@"type"] && ![[action valueForKey:@"type"] isEqual:[NSNull null]])
                                notificationAction.type = [action valueForKey:@"type"];

                            [actionsArr addObject:notificationAction];
                        }
                        
                        notification.actions = [[NSArray alloc] initWithArray:actionsArr];
                        [listOfNotifications addObject:notification];
                    }
                    dispatch_async(dispatch_get_main_queue(), ^{
                        successRequest(response, listOfNotifications, request.redirectedServer);
                    });
                } else {
                    
                    NSString *message = (NSString *)[meta objectForKey:@"message"];
                    if ([message isKindOfClass:[NSNull class]]) {
                        message = NSLocalizedString(@"_server_response_error_", nil);
                    }
                    dispatch_async(dispatch_get_main_queue(), ^{
                        failureRequest(response, [UtilsFramework getErrorWithCode:statusCode andCustomMessageFromTheServer:message], request.redirectedServer);
                    });
                }
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
                });
            }
        });
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)setNotificationServer:(NSString*)serverPath type:(NSString *)type onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void (^)(NSHTTPURLResponse *, NSString *))successRequest failureRequest:(void (^)(NSHTTPURLResponse *, NSError *, NSString *))failureRequest {
    
    serverPath = [serverPath encodeString:NSUTF8StringEncoding];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    __weak OCWebDAVClient *wrequest = request;
    
    [request setNotificationServer:serverPath type:type onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        successRequest(response, wrequest.redirectedServer);
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        
        failureRequest(response, error, wrequest.redirectedServer);
    }];
}

#pragma mark - Push Notification

- (void)subscribingNextcloudServerPush:(NSString *)serverPath pushTokenHash:(NSString *)pushTokenHash devicePublicKey:(NSString *)devicePublicKey proxyServerPath:(NSString *)proxyServerPath onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSString *publicKey, NSString *deviceIdentifier, NSString *signature, NSString *redirectedServer)) successRequest failureRequest:(void (^)(NSHTTPURLResponse *, NSError *, NSString *))failureRequest {
    
    serverPath = [serverPath encodeString:NSUTF8StringEncoding];
    serverPath = [serverPath stringByAppendingString:k_url_acces_remote_subscribing_nextcloud_server_api];

    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request subscribingNextcloudServerPush:serverPath pushTokenHash:pushTokenHash devicePublicKey:devicePublicKey proxyServerPath:proxyServerPath onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        NSData *responseData = (NSData*)responseObject;
        
        NSError *error;
        NSDictionary *jsongParsed = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingMutableContainers error:&error];
        
        if (jsongParsed && jsongParsed.allKeys > 0) {
            
            NSDictionary *ocs = [jsongParsed valueForKey:@"ocs"];
            NSDictionary *meta = [ocs valueForKey:@"meta"];
            NSDictionary *datas = [ocs valueForKey:@"data"];
            
            NSInteger statusCode = [[meta valueForKey:@"statuscode"] integerValue];
            
            if (statusCode == kOCPushNotificationAPISuccessful || statusCode == kOCPushNotificationAPINeedSendProxy) {
                
                NSString *publicKey = [datas objectForKey:@"publicKey"];
                NSString *deviceIdentifier = [datas objectForKey:@"deviceIdentifier"];
                NSString *signature = [datas objectForKey:@"signature"];
                
                successRequest(response, publicKey, deviceIdentifier, signature, request.redirectedServer);
                
            } else {
                
                NSString *message = (NSString *)[meta objectForKey:@"message"];
                if ([message isKindOfClass:[NSNull class]]) {
                    message = NSLocalizedString(@"_server_response_error_", nil);
                }
                failureRequest(response, [UtilsFramework getErrorWithCode:statusCode andCustomMessageFromTheServer:message], request.redirectedServer);
            }
        } else {
            failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
        }

    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
                
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)unsubscribingNextcloudServerPush:(NSString *)serverPath onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSString *redirectedServer)) successRequest failureRequest:(void (^)(NSHTTPURLResponse *, NSError *, NSString *))failureRequest {
    
    serverPath = [serverPath encodeString:NSUTF8StringEncoding];
    serverPath = [serverPath stringByAppendingString:k_url_acces_remote_subscribing_nextcloud_server_api];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request unsubscribingNextcloudServerPush:serverPath onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
        successRequest(response, request.redirectedServer);
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)subscribingPushProxy:(NSString *)serverPath pushToken:(NSString *)pushToken deviceIdentifier:(NSString *)deviceIdentifier deviceIdentifierSignature:(NSString *)deviceIdentifierSignature publicKey:(NSString *)publicKey onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void (^)(NSHTTPURLResponse *, NSString *redirectedServer))successRequest failureRequest:(void (^)(NSHTTPURLResponse *, NSError *, NSString *))failureRequest {
    
    serverPath = [serverPath encodeString:NSUTF8StringEncoding];
    serverPath = [serverPath stringByAppendingString:@"/devices"];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    [request.defaultHeaders setObject:self.userAgent forKey:@"User-Agent"];
    
    [request subscribingPushProxy:serverPath pushToken:pushToken deviceIdentifier:deviceIdentifier deviceIdentifierSignature:deviceIdentifierSignature publicKey:publicKey onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        if (successRequest) {
            //Return success
            successRequest(response, request.redirectedServer);
        }
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)unsubscribingPushProxy:(NSString *)serverPath deviceIdentifier:(NSString *)deviceIdentifier deviceIdentifierSignature:(NSString *)deviceIdentifierSignature publicKey:(NSString *)publicKey onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void (^)(NSHTTPURLResponse *, NSString *redirectedServer))successRequest failureRequest:(void (^)(NSHTTPURLResponse *, NSError *, NSString *))failureRequest {
    
    serverPath = [serverPath encodeString:NSUTF8StringEncoding];
    serverPath = [serverPath stringByAppendingString:@"/devices"];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    [request.defaultHeaders setObject:self.userAgent forKey:@"User-Agent"];
    
    [request unsubscribingPushProxy:serverPath deviceIdentifier:deviceIdentifier deviceIdentifierSignature:deviceIdentifierSignature publicKey:publicKey onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        if (successRequest) {
            //Return success
            successRequest(response, request.redirectedServer);
        }
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        
        failureRequest(response, error, request.redirectedServer);
    }];
}

#pragma mark - Activity

- (void) getActivityServer:(NSString*)serverPath since:(NSInteger)since limit:(NSInteger)limit objectId:(NSString *)objectId objectType:(NSString *)objectType previews:(BOOL)previews link:(NSString *)link onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSArray *listOfActivity, NSString *redirectedServer)) successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {

    serverPath = [serverPath encodeString:NSUTF8StringEncoding];
    serverPath = [serverPath stringByAppendingString:k_url_acces_remote_activity_api];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request getActivityServer:serverPath since:since limit:limit objectId:objectId objectType:objectType previews:previews link:link onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        NSData *responseData = (NSData*) responseObject;
        NSMutableArray *listOfActivity = [NSMutableArray new];

        //Parse
        NSError *error;
        NSDictionary *jsongParsed = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingMutableContainers error:&error];
        NSLog(@"[LOG] Activity : %@",jsongParsed);
        
        if (jsongParsed && [jsongParsed isKindOfClass:[NSDictionary class]] && jsongParsed.allKeys > 0) {
            
            NSDictionary *ocs = [jsongParsed valueForKey:@"ocs"];
            NSDictionary *meta = [ocs valueForKey:@"meta"];
            NSDictionary *datas = [ocs valueForKey:@"data"];
            
            NSInteger statusCode = [[meta valueForKey:@"statuscode"] integerValue];

            if (statusCode == kOCNotificationAPINoContent || statusCode == kOCNotificationAPISuccessful) {
                
                for (NSDictionary *data in datas) {
                    
                    OCActivity *activity = [OCActivity new];
                    
                    if ([data valueForKey:@"activity_id"] && ![[data valueForKey:@"activity_id"] isEqual:[NSNull null]])
                        activity.idActivity = [[data valueForKey:@"activity_id"] integerValue];
                    
                    if ([data valueForKey:@"datetime"] && ![[data valueForKey:@"datetime"] isEqual:[NSNull null]]) {
                        
                        NSString *dateString = [data valueForKey:@"datetime"];
                        
                        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
                        NSLocale *enUSPOSIXLocale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
                        [dateFormatter setLocale:enUSPOSIXLocale];
                        [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZZZZZ"];
                        
                        activity.date = [dateFormatter dateFromString:dateString];
                    }
                    
                    if ([data valueForKey:@"app"] && ![[data valueForKey:@"app"] isEqual:[NSNull null]])
                        activity.app = [data valueForKey:@"app"];
                    
                    if ([data valueForKey:@"type"] && ![[data valueForKey:@"type"] isEqual:[NSNull null]])
                        activity.type = [data valueForKey:@"type"];
                    
                    if ([data valueForKey:@"user"] && ![[data valueForKey:@"user"] isEqual:[NSNull null]])
                        activity.user = [data valueForKey:@"user"];
                    
                    if ([data valueForKey:@"subject"] && ![[data valueForKey:@"subject"] isEqual:[NSNull null]])
                        activity.subject = [data valueForKey:@"subject"];
                    
                    if ([data valueForKey:@"subject_rich"] && ![[data valueForKey:@"subject_rich"] isEqual:[NSNull null]])
                        activity.subject_rich = [data valueForKey:@"subject_rich"];
                    
                    if ([data valueForKey:@"message"] && ![[data valueForKey:@"message"] isEqual:[NSNull null]])
                        activity.message = [data valueForKey:@"message"];
                    
                    if ([data valueForKey:@"message_rich"] && ![[data valueForKey:@"message_rich"] isEqual:[NSNull null]])
                        activity.message_rich = [data valueForKey:@"message_rich"];
                    
                    if ([data valueForKey:@"icon"] && ![[data valueForKey:@"icon"] isEqual:[NSNull null]])
                        activity.icon = [data valueForKey:@"icon"];
                    
                    if ([data valueForKey:@"link"] && ![[data valueForKey:@"link"] isEqual:[NSNull null]])
                        activity.link = [data valueForKey:@"link"];
                    
                    if ([data valueForKey:@"object_type"] && ![[data valueForKey:@"object_type"] isEqual:[NSNull null]])
                        activity.object_type = [data valueForKey:@"object_type"];
                    
                    if ([data valueForKey:@"object_id"] && ![[data valueForKey:@"object_id"] isEqual:[NSNull null]])
                        activity.object_id = [[data valueForKey:@"object_id"] integerValue];
                    
                    if ([data valueForKey:@"object_name"] && ![[data valueForKey:@"object_name"] isEqual:[NSNull null]])
                        activity.object_name = [data valueForKey:@"object_name"];
                    
                    if ([data valueForKey:@"previews"] && ![[data valueForKey:@"previews"] isEqual:[NSNull null]])
                        activity.previews = [data valueForKey:@"previews"];
                    
                    [listOfActivity addObject:activity];
                }
                successRequest(response, listOfActivity, request.redirectedServer);

            } else {
                
                NSString *message = (NSString *)[meta objectForKey:@"message"];
                if ([message isKindOfClass:[NSNull class]]) {
                    message = NSLocalizedString(@"_server_response_error_", nil);
                }
                failureRequest(response, [UtilsFramework getErrorWithCode:statusCode andCustomMessageFromTheServer:message], request.redirectedServer);
            }
            
        } else {
            failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
        }

    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        failureRequest(response, error, request.redirectedServer);
    }];
}

#pragma mark - External Sites

- (void) getExternalSitesServer:(NSString*)serverPath onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSArray *listOfExternalSites, NSString *redirectedServer)) successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    serverPath = [serverPath encodeString:NSUTF8StringEncoding];
    serverPath = [serverPath stringByAppendingString:k_url_acces_external_sites_api];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request getExternalSitesServer:serverPath onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        NSData *responseData = (NSData*) responseObject;
        NSMutableArray *listOfExternalSites = [NSMutableArray new];

        //Parse
        NSError *error;
        NSDictionary *jsongParsed = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingMutableContainers error:&error];
        NSLog(@"[LOG] External Sites : %@",jsongParsed);
        
        if (jsongParsed && jsongParsed.allKeys > 0) {
            
            NSDictionary *ocs = [jsongParsed valueForKey:@"ocs"];
            NSDictionary *meta = [ocs valueForKey:@"meta"];
            NSDictionary *datas = [ocs valueForKey:@"data"];
            
            NSInteger statusCode = [[meta valueForKey:@"statuscode"] integerValue];
            
            if (statusCode == kOCNotificationAPINoContent || statusCode == kOCNotificationAPISuccessful) {
                
                for (NSDictionary *data in datas) {
                    
                    OCExternalSites *externalSites = [OCExternalSites new];
                    
                    externalSites.idExternalSite = [[data valueForKey:@"id"] integerValue];
    
                    if ([data valueForKey:@"icon"] && ![[data valueForKey:@"icon"] isEqual:[NSNull null]])
                        externalSites.icon = [data valueForKey:@"icon"];
                    
                    if ([data valueForKey:@"lang"] && ![[data valueForKey:@"lang"] isEqual:[NSNull null]])
                        externalSites.lang = [data valueForKey:@"lang"];
                    
                    if ([data valueForKey:@"name"] && ![[data valueForKey:@"name"] isEqual:[NSNull null]])
                        externalSites.name = [data valueForKey:@"name"];
                    
                    if ([data valueForKey:@"url"]  && ![[data valueForKey:@"url"]  isEqual:[NSNull null]])
                        externalSites.url  = [data valueForKey:@"url"];
                    
                    if ([data valueForKey:@"type"] && ![[data valueForKey:@"type"] isEqual:[NSNull null]])
                        externalSites.type = [data valueForKey:@"type"];
                    
                    [listOfExternalSites addObject:externalSites];
                }
                
                successRequest(response, listOfExternalSites, request.redirectedServer);

            } else {
                
                NSString *message = (NSString *)[meta objectForKey:@"message"];
                if ([message isKindOfClass:[NSNull class]]) {
                    message = NSLocalizedString(@"_server_response_error_", nil);
                }
                failureRequest(response, [UtilsFramework getErrorWithCode:statusCode andCustomMessageFromTheServer:message], request.redirectedServer);
            }
            
        } else {
            failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
        }
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        failureRequest(response, error, request.redirectedServer);
    }];
}

#pragma mark - User Profile

- (void) getUserProfileServer:(NSString*)serverPath onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, OCUserProfile *userProfile, NSString *redirectedServer)) successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [serverPath stringByAppendingString:k_url_acces_remote_userprofile_api];
    serverPath = [serverPath encodeString:NSUTF8StringEncoding];

    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request getUserProfileServer:serverPath onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
    
        NSData *responseData = (NSData*) responseObject;
        OCUserProfile *userProfile = [OCUserProfile new];

        //Parse
        NSError *error;
        NSDictionary *jsongParsed = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingMutableContainers error:&error];
        NSLog(@"[LOG] User Profile : %@",jsongParsed);
        
        if (jsongParsed && jsongParsed.allKeys > 0) {

            NSDictionary *ocs = [jsongParsed valueForKey:@"ocs"];
            NSDictionary *meta = [ocs valueForKey:@"meta"];
            NSDictionary *data = [ocs valueForKey:@"data"];
            
            NSInteger statusCode = [[meta valueForKey:@"statuscode"] integerValue];
            
            if (statusCode == kOCUserProfileAPISuccessful) {
                
                if ([data valueForKey:@"address"] && ![[data valueForKey:@"address"] isKindOfClass:[NSNull class]])
                    userProfile.address = [data valueForKey:@"address"];
                
                if ([data valueForKey:@"display-name"] && ![[data valueForKey:@"display-name"] isKindOfClass:[NSNull class]])
                    userProfile.displayName = [data valueForKey:@"display-name"];
              
                if ([data valueForKey:@"email"] && ![[data valueForKey:@"email"] isKindOfClass:[NSNull class]])
                    userProfile.email = [data valueForKey:@"email"];
                
                if ([data valueForKey:@"enabled"] && ![[data valueForKey:@"enabled"] isKindOfClass:[NSNull class]])
                    userProfile.enabled = [[data valueForKey:@"enabled"] boolValue];
                
                if ([data valueForKey:@"id"] && ![[data valueForKey:@"id"] isKindOfClass:[NSNull class]])
                    userProfile.id = [data valueForKey:@"id"];
                
                if ([data valueForKey:@"phone"] && ![[data valueForKey:@"phone"] isKindOfClass:[NSNull class]])
                    userProfile.phone = [data valueForKey:@"phone"];
                
                if ([data valueForKey:@"twitter"] && ![[data valueForKey:@"twitter"] isKindOfClass:[NSNull class]])
                    userProfile.twitter = [data valueForKey:@"twitter"];
                
                if ([data valueForKey:@"webpage"] && ![[data valueForKey:@"webpage"] isKindOfClass:[NSNull class]])
                    userProfile.webpage = [data valueForKey:@"webpage"];

                /* QUOTA */
                    
                NSDictionary *quota = [data valueForKey:@"quota"];
                
                if ([quota count] > 0) {
                    
                    if ([quota valueForKey:@"free"] && ![[quota valueForKey:@"free"] isKindOfClass:[NSNull class]])
                        userProfile.quotaFree = [[quota valueForKey:@"free"] doubleValue];
                    
                    if ([quota valueForKey:@"quota"] && ![[quota valueForKey:@"quota"] isKindOfClass:[NSNull class]])
                        userProfile.quota = [[quota valueForKey:@"quota"] doubleValue];
                    
                    if ([quota valueForKey:@"relative"] && ![[quota valueForKey:@"relative"] isKindOfClass:[NSNull class]])
                        userProfile.quotaRelative = [[quota valueForKey:@"relative"] doubleValue];
                        
                    if ([quota valueForKey:@"total"] && ![[quota valueForKey:@"total"] isKindOfClass:[NSNull class]])
                        userProfile.quotaTotal = [[quota valueForKey:@"total"] doubleValue];
                        
                    if ([quota valueForKey:@"used"] && ![[quota valueForKey:@"used"] isKindOfClass:[NSNull class]])
                        userProfile.quotaUsed = [[quota valueForKey:@"used"] doubleValue];
                }
                
                successRequest(response, userProfile, request.redirectedServer);

            } else {
                
                NSString *message = (NSString *)[meta objectForKey:@"message"];
                if ([message isKindOfClass:[NSNull class]]) {
                    message = NSLocalizedString(@"_server_response_error_", nil);
                }
                failureRequest(response, [UtilsFramework getErrorWithCode:statusCode andCustomMessageFromTheServer:message], request.redirectedServer);
            }
            
        } else {
            failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
        }
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
    
        failureRequest(response, error, request.redirectedServer);
    }];
}

#pragma mark - End-to-End Encryption

- (void)getEndToEndPublicKeys:(NSString*)serverPath onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSString *publicKey, NSString *redirectedServer)) successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [serverPath stringByAppendingString:k_url_client_side_encryption];
    serverPath = [serverPath stringByAppendingString:@"/public-key"];
    serverPath = [serverPath stringByAppendingString:@"?format=json"];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request getEndToEndPublicKeys:serverPath onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        NSData *responseData = (NSData*) responseObject;
        NSString *publicKey = @"";
        
        //Parse
        NSError *error;
        NSDictionary *jsongParsed = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingMutableContainers error:&error];
        NSLog(@"[LOG] E2E Get PublicKey : %@",jsongParsed);
        
        if (jsongParsed && jsongParsed.allKeys > 0) {
            
            NSDictionary *ocs = [jsongParsed valueForKey:@"ocs"];
            NSDictionary *meta = [ocs valueForKey:@"meta"];
            NSDictionary *data = [ocs valueForKey:@"data"];
            
            NSInteger statusCode = [[meta valueForKey:@"statuscode"] integerValue];
            
            if (statusCode == kOCUserProfileAPISuccessful) {
                
                if ([data valueForKey:@"public-keys"] && ![[data valueForKey:@"public-keys"] isKindOfClass:[NSNull class]]) {
                    
                    NSDictionary *publickeys = [data valueForKey:@"public-keys"];
                    publicKey = [publickeys valueForKey:self.userID];
                    
                    successRequest(response, publicKey, request.redirectedServer);
                    
                } else {
                    failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
                }
                
            } else {
                
                NSString *message = (NSString *)[meta objectForKey:@"message"];
                if ([message isKindOfClass:[NSNull class]]) {
                    message = NSLocalizedString(@"_server_response_error_", nil);
                }
                failureRequest(response, [UtilsFramework getErrorWithCode:statusCode andCustomMessageFromTheServer:message], request.redirectedServer);
            }
            
        } else {
            failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
        }
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        
        //Return error
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)getEndToEndPrivateKeyCipher:(NSString*)serverPath onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSString *privateKeyChiper, NSString *redirectedServer)) successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [serverPath stringByAppendingString:k_url_client_side_encryption];
    serverPath = [serverPath stringByAppendingString:@"/private-key"];
    serverPath = [serverPath stringByAppendingString:@"?format=json"];

    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request getEndToEndPrivateKeyCipher:serverPath onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        NSData *responseData = (NSData*) responseObject;
        NSString *privateKeyChiper = @"";
        
        //Parse
        NSError *error;
        NSDictionary *jsongParsed = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingMutableContainers error:&error];
        NSLog(@"[LOG] E2E Get PrivateKey : %@",jsongParsed);
        
        if (jsongParsed && jsongParsed.allKeys > 0) {
            
            NSDictionary *ocs = [jsongParsed valueForKey:@"ocs"];
            NSDictionary *meta = [ocs valueForKey:@"meta"];
            NSDictionary *data = [ocs valueForKey:@"data"];
            
            NSInteger statusCode = [[meta valueForKey:@"statuscode"] integerValue];
            
            if (statusCode == kOCUserProfileAPISuccessful) {
                
                if ([data valueForKey:@"private-key"] && ![[data valueForKey:@"private-key"] isKindOfClass:[NSNull class]]) {
                    
                    privateKeyChiper = [data valueForKey:@"private-key"];
                    successRequest(response, privateKeyChiper, request.redirectedServer);
                    
                } else {
                    failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
                }
            } else {
                
                NSString *message = (NSString *)[meta objectForKey:@"message"];
                if ([message isKindOfClass:[NSNull class]]) {
                    message = NSLocalizedString(@"_server_response_error_", nil);
                }
                failureRequest(response, [UtilsFramework getErrorWithCode:statusCode andCustomMessageFromTheServer:message], request.redirectedServer);
            }
        } else {
            failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
        }
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        
        //Return error
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)getEndToEndServerPublicKey:(NSString*)serverPath onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSString *publicKey, NSString *redirectedServer)) successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [serverPath stringByAppendingString:k_url_client_side_encryption];
    serverPath = [serverPath stringByAppendingString:@"/server-key"];
    serverPath = [serverPath stringByAppendingString:@"?format=json"];

    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request getEndToEndServerPublicKey:serverPath onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        NSData *responseData = (NSData*) responseObject;
        NSString *publicKey = @"";
        
        //Parse
        NSError *error;
        NSDictionary *jsongParsed = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingMutableContainers error:&error];
        NSLog(@"[LOG] E2E Get Server PublicKey : %@",jsongParsed);
        
        if (jsongParsed && jsongParsed.allKeys > 0) {
            
            NSDictionary *ocs = [jsongParsed valueForKey:@"ocs"];
            NSDictionary *meta = [ocs valueForKey:@"meta"];
            NSDictionary *data = [ocs valueForKey:@"data"];
            
            NSInteger statusCode = [[meta valueForKey:@"statuscode"] integerValue];
            
            if (statusCode == kOCUserProfileAPISuccessful) {
                
                if ([data valueForKey:@"public-key"] && ![[data valueForKey:@"public-key"] isKindOfClass:[NSNull class]]) {
                    
                    publicKey = [data valueForKey:@"public-key"];
                    successRequest(response, publicKey, request.redirectedServer);
                    
                } else {
                    failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
                }
            } else {
                
                NSString *message = (NSString *)[meta objectForKey:@"message"];
                if ([message isKindOfClass:[NSNull class]]) {
                    message = NSLocalizedString(@"_server_response_error_", nil);
                }
                failureRequest(response, [UtilsFramework getErrorWithCode:statusCode andCustomMessageFromTheServer:message], request.redirectedServer);
            }
        } else {
            failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
        }
        
        //Return success
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        
        //Return error
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)signEndToEndPublicKey:(NSString*)serverPath publicKey:(NSString *)publicKey onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSString *publicKey,NSString *redirectedServer))successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [serverPath stringByAppendingString:k_url_client_side_encryption];
    serverPath = [serverPath stringByAppendingString:@"/public-key"];
    serverPath = [serverPath stringByAppendingString:@"?format=json"];
    
    OCWebDAVClient *request = [[OCWebDAVClient alloc] init];
    request = [self getRequestWithCredentials:request];
    
    [request signEndToEndPublicKey:serverPath key:publicKey onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        NSData *responseData = (NSData*) responseObject;
        NSString *publicKey = @"";
        
        //Parse
        NSError *error;
        NSDictionary *jsongParsed = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingMutableContainers error:&error];
        NSLog(@"[LOG] E2E Sign PublicKey : %@",jsongParsed);
        
        if (jsongParsed && jsongParsed.allKeys > 0) {
            
            NSDictionary *ocs = [jsongParsed valueForKey:@"ocs"];
            NSDictionary *meta = [ocs valueForKey:@"meta"];
            NSDictionary *data = [ocs valueForKey:@"data"];
            
            NSInteger statusCode = [[meta valueForKey:@"statuscode"] integerValue];
            
            if (statusCode == kOCUserProfileAPISuccessful) {
                
                if ([data valueForKey:@"public-key"] && ![[data valueForKey:@"public-key"] isKindOfClass:[NSNull class]]) {
                    
                    publicKey = [data valueForKey:@"public-key"];
                    successRequest(response, publicKey, request.redirectedServer);
                    
                } else {
                    failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
                }
            } else {
                
                NSString *message = (NSString *)[meta objectForKey:@"message"];
                if ([message isKindOfClass:[NSNull class]]) {
                    message = NSLocalizedString(@"_server_response_error_", nil);
                }
                failureRequest(response, [UtilsFramework getErrorWithCode:statusCode andCustomMessageFromTheServer:message], request.redirectedServer);
            }
        } else {
            failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
        }
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        
        //Return error
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)storeEndToEndPrivateKeyCipher:(NSString*)serverPath privateKeyChiper:(NSString *)privateKeyChiper onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSString *privateKey, NSString *redirectedServer))successRequest  failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [serverPath stringByAppendingString:k_url_client_side_encryption];
    serverPath = [serverPath stringByAppendingString:@"/private-key"];
    serverPath = [serverPath stringByAppendingString:@"?format=json"];
    
    OCWebDAVClient *request = [[OCWebDAVClient alloc] init];
    request = [self getRequestWithCredentials:request];
    
    [request storeEndToEndPrivateKeyCipher:serverPath key:privateKeyChiper onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        NSData *responseData = (NSData*) responseObject;
        NSString *privateKey = @"";
        
        //Parse
        NSError *error;
        NSDictionary *jsongParsed = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingMutableContainers error:&error];
        NSLog(@"[LOG] E2E Store PrivateKey : %@",jsongParsed);
        
        if (jsongParsed && jsongParsed.allKeys > 0) {
            
            NSDictionary *ocs = [jsongParsed valueForKey:@"ocs"];
            NSDictionary *meta = [ocs valueForKey:@"meta"];
            NSDictionary *data = [ocs valueForKey:@"data"];
            
            NSInteger statusCode = [[meta valueForKey:@"statuscode"] integerValue];
            
            if (statusCode == kOCUserProfileAPISuccessful) {
                
                if ([data valueForKey:@"private-key"] && ![[data valueForKey:@"private-key"] isKindOfClass:[NSNull class]]) {
                    
                    privateKey = [data valueForKey:@"private-key"];
                    successRequest(response, privateKey, request.redirectedServer);
                    
                } else {
                    failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
                }
                
            } else {
                
                NSString *message = (NSString *)[meta objectForKey:@"message"];
                if ([message isKindOfClass:[NSNull class]]) {
                    message = NSLocalizedString(@"_server_response_error_", nil);
                }
                failureRequest(response, [UtilsFramework getErrorWithCode:statusCode andCustomMessageFromTheServer:message], request.redirectedServer);
            }
        } else {
            failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
        }
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        
        //Return error
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)deleteEndToEndPublicKey:(NSString*)serverPath onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSString *redirectedServer)) successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [serverPath stringByAppendingString:k_url_client_side_encryption];
    serverPath = [serverPath stringByAppendingString:@"/public-key"];
    serverPath = [serverPath stringByAppendingString:@"?format=json"];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request deleteEndToEndPublicKey:serverPath onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        //Return success
        successRequest(response, request.redirectedServer);
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        
        //Return error
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)deleteEndToEndPrivateKey:(NSString*)serverPath onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSString *redirectedServer)) successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [serverPath stringByAppendingString:k_url_client_side_encryption];
    serverPath = [serverPath stringByAppendingString:@"/private-key"];
    serverPath = [serverPath stringByAppendingString:@"?format=json"];

    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request deleteEndToEndPrivateKey:serverPath onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        //Return success
        successRequest(response, request.redirectedServer);
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        
        //Return error
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)markEndToEndFolderEncrypted:(NSString*)serverPath fileId:(NSString *)fileId onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSString *redirectedServer)) successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [serverPath stringByAppendingString:k_url_client_side_encryption];
    serverPath = [NSString stringWithFormat:@"%@/encrypted/%@", serverPath, fileId];
    serverPath = [serverPath stringByAppendingString:@"?format=json"];

    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request markEndToEndFolderEncrypted:serverPath onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        //Return success
        successRequest(response, request.redirectedServer);
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        
        //Return error
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)deletemarkEndToEndFolderEncrypted:(NSString*)serverPath fileId:(NSString *)fileId e2eToken:(NSString *)e2eToken onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSString *redirectedServer)) successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [serverPath stringByAppendingString:k_url_client_side_encryption];
    serverPath = [NSString stringWithFormat:@"%@/encrypted/%@", serverPath, fileId];
    serverPath = [serverPath stringByAppendingString:@"?format=json"];

    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request deletemarkEndToEndFolderEncrypted:serverPath e2eToken:e2eToken onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        //Return success
        successRequest(response, request.redirectedServer);
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        
        //Return error
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)lockEndToEndFolderEncrypted:(NSString*)serverPath fileId:(NSString *)fileId e2eToken:(NSString *)e2eToken onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSString *e2eToken, NSString *redirectedServer)) successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [serverPath stringByAppendingString:k_url_client_side_encryption];
    serverPath = [NSString stringWithFormat:@"%@/lock/%@", serverPath, fileId];
    if (e2eToken) {
        serverPath = [NSString stringWithFormat:@"%@?e2e-token=%@", serverPath, e2eToken];
        serverPath = [serverPath stringByAppendingString:@"&format=json"];
    } else {
        serverPath = [serverPath stringByAppendingString:@"?format=json"];
    }

    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request lockEndToEndFolderEncrypted:serverPath e2eToken:e2eToken onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        NSData *responseData = (NSData*) responseObject;
        NSString *token = @"";
        
        //Parse
        NSError *error;
        NSDictionary *jsongParsed = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingMutableContainers error:&error];
        NSLog(@"[LOG] E2E Lock File : %@",jsongParsed);
        
        if (jsongParsed && jsongParsed.allKeys > 0) {
            
            NSDictionary *ocs = [jsongParsed valueForKey:@"ocs"];
            NSDictionary *meta = [ocs valueForKey:@"meta"];
            NSDictionary *data = [ocs valueForKey:@"data"];
            
            NSInteger statusCode = [[meta valueForKey:@"statuscode"] integerValue];
            
            if (statusCode == kOCUserProfileAPISuccessful) {
                
                if ([data valueForKey:@"e2e-token"] && ![[data valueForKey:@"e2e-token"] isKindOfClass:[NSNull class]]) {
                    
                    token = [data valueForKey:@"e2e-token"];
                    successRequest(response, token, request.redirectedServer);
                    
                } else {
                    failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_",  nil)], request.redirectedServer);
                }
            } else {
                
                NSString *message = (NSString *)[meta objectForKey:@"message"];
                if ([message isKindOfClass:[NSNull class]]) {
                    message = NSLocalizedString(@"_server_response_error_", nil);
                }
                failureRequest(response, [UtilsFramework getErrorWithCode:statusCode andCustomMessageFromTheServer:message], request.redirectedServer);
            }
        } else {
            failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
        }
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        
        //Return error
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)unlockEndToEndFolderEncrypted:(NSString*)serverPath fileId:(NSString *)fileId e2eToken:(NSString *)e2eToken onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSString *redirectedServer)) successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [serverPath stringByAppendingString:k_url_client_side_encryption];
    serverPath = [NSString stringWithFormat:@"%@/lock/%@", serverPath, fileId];
    serverPath = [serverPath stringByAppendingString:@"&format=json"];

    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request unlockEndToEndFolderEncrypted:serverPath e2eToken:e2eToken onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        //Return success
        successRequest(response, request.redirectedServer);
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        
        //Return error
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)getEndToEndMetadata:(NSString*)serverPath fileId:(NSString *)fileId onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSString *encryptedMetadata, NSString *redirectedServer))successRequest  failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [serverPath stringByAppendingString:k_url_client_side_encryption];
    serverPath = [NSString stringWithFormat:@"%@/meta-data/%@", serverPath, fileId];
    serverPath = [serverPath stringByAppendingString:@"?format=json"];

    OCWebDAVClient *request = [[OCWebDAVClient alloc] init];
    request = [self getRequestWithCredentials:request];
    
    [request getEndToEndMetadata:serverPath onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        NSData *responseData = (NSData*) responseObject;
        NSString *encryptedMetadata = @"";
        
        //Parse
        NSError *error;
        NSDictionary *jsongParsed = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingMutableContainers error:&error];
        NSLog(@"[LOG] E2E Get Metadata : %@",jsongParsed);
        
        if (jsongParsed && jsongParsed.allKeys > 0) {
            
            NSDictionary *ocs = [jsongParsed valueForKey:@"ocs"];
            NSDictionary *meta = [ocs valueForKey:@"meta"];
            NSDictionary *data = [ocs valueForKey:@"data"];
            
            NSInteger statusCode = [[meta valueForKey:@"statuscode"] integerValue];
            
            if (statusCode == kOCUserProfileAPISuccessful) {
                
                if ([data valueForKey:@"meta-data"] && ![[data valueForKey:@"meta-data"] isKindOfClass:[NSNull class]]) {
                    
                    encryptedMetadata = [data valueForKey:@"meta-data"];
                    successRequest(response, encryptedMetadata, request.redirectedServer);
                    
                } else {
                    failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
                }
            } else {
                NSString *message = (NSString *)[meta objectForKey:@"message"];
                if ([message isKindOfClass:[NSNull class]]) {
                    message = NSLocalizedString(@"_server_response_error_", nil);
                }
                failureRequest(response, [UtilsFramework getErrorWithCode:statusCode andCustomMessageFromTheServer:message], request.redirectedServer);
            }
        } else {
            failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
        }
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        
        //Return error
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)storeEndToEndMetadata:(NSString*)serverPath fileId:(NSString *)fileId e2eToken:(NSString *)e2eToken encryptedMetadata:(NSString *)encryptedMetadata onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSString *encryptedMetadata, NSString *redirectedServer))successRequest  failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    encryptedMetadata = [encryptedMetadata encodeString:NSUTF8StringEncoding];
    
    serverPath = [serverPath stringByAppendingString:k_url_client_side_encryption];
    serverPath = [NSString stringWithFormat:@"%@/meta-data/%@", serverPath, fileId];
    serverPath = [serverPath stringByAppendingString:@"?format=json"];
    
    OCWebDAVClient *request = [[OCWebDAVClient alloc] init];
    request = [self getRequestWithCredentials:request];
    
    [request storeEndToEndMetadata:serverPath metadata:encryptedMetadata e2eToken:e2eToken onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        NSData *responseData = (NSData*) responseObject;
        NSString *encryptedMetadata = @"";
        
        //Parse
        NSError *error;
        NSDictionary *jsongParsed = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingMutableContainers error:&error];
        NSLog(@"[LOG] E2E Store Metadata : %@",jsongParsed);
        
        if (jsongParsed && jsongParsed.allKeys > 0) {
            
            NSDictionary *ocs = [jsongParsed valueForKey:@"ocs"];
            NSDictionary *meta = [ocs valueForKey:@"meta"];
            NSDictionary *data = [ocs valueForKey:@"data"];
            
            NSInteger statusCode = [[meta valueForKey:@"statuscode"] integerValue];
            
            if (statusCode == kOCUserProfileAPISuccessful) {
                
                if ([data valueForKey:@"meta-data"] && ![[data valueForKey:@"meta-data"] isKindOfClass:[NSNull class]]) {
                    
                    encryptedMetadata = [data valueForKey:@"meta-data"];
                    successRequest(response, encryptedMetadata, request.redirectedServer);
                    
                } else {
                    failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
                }
            } else {
                
                NSString *message = (NSString *)[meta objectForKey:@"message"];
                if ([message isKindOfClass:[NSNull class]]) {
                    message = NSLocalizedString(@"_server_response_error_", nil);
                }
                failureRequest(response, [UtilsFramework getErrorWithCode:statusCode andCustomMessageFromTheServer:message], request.redirectedServer);
            }
        } else {
            failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
        }
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        
        //Return error
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)updateEndToEndMetadata:(NSString*)serverPath fileId:(NSString *)fileId encryptedMetadata:(NSString *)encryptedMetadata e2eToken:(NSString *)e2eToken onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSString *encryptedMetadata, NSString *redirectedServer))successRequest  failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    encryptedMetadata = [encryptedMetadata encodeString:NSUTF8StringEncoding];

    serverPath = [serverPath stringByAppendingString:k_url_client_side_encryption];
    serverPath = [NSString stringWithFormat:@"%@/meta-data/%@", serverPath, fileId];
    serverPath = [NSString stringWithFormat:@"%@?e2e-token=%@", serverPath, e2eToken];
    serverPath = [serverPath stringByAppendingString:@"&format=json"];
    
    OCWebDAVClient *request = [[OCWebDAVClient alloc] init];
    request = [self getRequestWithCredentials:request];
    
    [request updateEndToEndMetadata:serverPath metadata:encryptedMetadata e2eToken:e2eToken onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        NSData *responseData = (NSData*) responseObject;
        NSString *encryptedMetadata = @"";
        
        //Parse
        NSError *error;
        NSDictionary *jsongParsed = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingMutableContainers error:&error];
        NSLog(@"[LOG] E2E Update Metadata : %@",jsongParsed);
        
        if (jsongParsed && jsongParsed.allKeys > 0) {
            
            NSDictionary *ocs = [jsongParsed valueForKey:@"ocs"];
            NSDictionary *meta = [ocs valueForKey:@"meta"];
            NSDictionary *data = [ocs valueForKey:@"data"];
            
            NSInteger statusCode = [[meta valueForKey:@"statuscode"] integerValue];
            
            if (statusCode == kOCUserProfileAPISuccessful) {
                
                if ([data valueForKey:@"meta-data"] && ![[data valueForKey:@"meta-data"] isKindOfClass:[NSNull class]]) {
                    
                    encryptedMetadata = [data valueForKey:@"meta-data"];
                    successRequest(response, encryptedMetadata, request.redirectedServer);
                    
                } else {
                    failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
                }
            } else {
                
                NSString *message = (NSString *)[meta objectForKey:@"message"];
                if ([message isKindOfClass:[NSNull class]]) {
                    message = NSLocalizedString(@"_server_response_error_", nil);
                }
                failureRequest(response, [UtilsFramework getErrorWithCode:statusCode andCustomMessageFromTheServer:message], request.redirectedServer);
            }
        } else {
            failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
        }
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        
        //Return error
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)deleteEndToEndMetadata:(NSString*)serverPath fileId:(NSString *)fileId e2eToken:(NSString *)e2eToken onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSString *redirectedServer))successRequest  failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [serverPath stringByAppendingString:k_url_client_side_encryption];
    serverPath = [NSString stringWithFormat:@"%@/meta-data/%@", serverPath, fileId];
    serverPath = [serverPath stringByAppendingString:@"?format=json"];

    OCWebDAVClient *request = [[OCWebDAVClient alloc] init];
    request = [self getRequestWithCredentials:request];
    
    [request deleteEndToEndMetadata:serverPath e2eToken:e2eToken onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        //Return success
        successRequest(response, request.redirectedServer);
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        
        //Return error
        failureRequest(response, error, request.redirectedServer);
    }];
}

#pragma mark - Manage Mobile Editor OCS API

- (void)createLinkRichdocuments:(NSString *)serverPath fileId:(NSString *)fileId onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSString *link, NSString *redirectedServer))successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [serverPath stringByAppendingString:k_url_create_link_mobile_richdocuments];
    serverPath = [serverPath stringByAppendingString:@"?format=json"];
    
    OCWebDAVClient *request = [[OCWebDAVClient alloc] init];
    request = [self getRequestWithCredentials:request];
    
    [request createLinkRichdocuments:serverPath fileId:fileId onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *operation, id response) {
        
        NSData *responseData = (NSData*) response;
        
        //Parse
        NSError *error;
        NSDictionary *jsongParsed = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingMutableContainers error:&error];
        NSLog(@"[LOG] Link richdocuments : %@",jsongParsed);
        
        if (jsongParsed && jsongParsed.allKeys > 0) {
            
            NSDictionary *ocs = [jsongParsed valueForKey:@"ocs"];
            NSDictionary *meta = [ocs valueForKey:@"meta"];
            NSDictionary *data = [ocs valueForKey:@"data"];
            
            NSInteger statusCode = [[meta valueForKey:@"statuscode"] integerValue];
            
            if (statusCode == kOCUserProfileAPISuccessful) {
                
                if ([data valueForKey:@"url"] && ![[data valueForKey:@"url"] isKindOfClass:[NSNull class]]) {
                    
                    NSString *link = [data valueForKey:@"url"];
                    successRequest(response, link, request.redirectedServer);
                    
                } else {
                    failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
                }
                
            } else {
                
                NSString *message = (NSString *)[meta objectForKey:@"message"];
                if ([message isKindOfClass:[NSNull class]]) {
                    message = NSLocalizedString(@"_server_response_error_", nil);
                }
                failureRequest(response, [UtilsFramework getErrorWithCode:statusCode andCustomMessageFromTheServer:message], request.redirectedServer);
            }
            
        } else {
            failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
        }
  
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        
        //Return error
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)getTemplatesRichdocuments:(NSString *)serverPath typeTemplate:(NSString *)typeTemplate onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSArray *listOfTemplate, NSString *redirectedServer))successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [serverPath stringByAppendingString:k_url_get_template_mobile_richdocuments];
    serverPath = [serverPath stringByAppendingString:typeTemplate];
    serverPath = [serverPath stringByAppendingString:@"?format=json"];
    
    OCWebDAVClient *request = [[OCWebDAVClient alloc] init];
    request = [self getRequestWithCredentials:request];
    
    [request getTemplatesRichdocuments:serverPath onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *operation, id response) {
        
        NSData *responseData = (NSData*) response;
        
        //Parse
        NSError *error;
        NSDictionary *jsongParsed = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingMutableContainers error:&error];
        NSLog(@"[LOG] Link richdocuments : %@",jsongParsed);
        
        if (jsongParsed && jsongParsed.allKeys > 0) {
            
            NSMutableArray *list = [NSMutableArray new];
            
            NSDictionary *ocs = [jsongParsed valueForKey:@"ocs"];
            NSDictionary *meta = [ocs valueForKey:@"meta"];
            NSDictionary *data = [ocs valueForKey:@"data"];
            
            NSInteger statusCode = [[meta valueForKey:@"statuscode"] integerValue];
            
            if (statusCode == kOCUserProfileAPISuccessful) {
               
                for (NSDictionary *dicDatas in data) {
                    
                    NCRichDocumentTemplate *template = [NCRichDocumentTemplate new];
                    
                    if ([dicDatas valueForKey:@"id"] && ![[dicDatas valueForKey:@"id"] isEqual:[NSNull null]])
                        template.templateID = [[dicDatas valueForKey:@"id"] integerValue];
                    
                    if ([dicDatas valueForKey:@"delete"] && ![[dicDatas valueForKey:@"delete"] isKindOfClass:[NSNull class]])
                        template.delete = [dicDatas valueForKey:@"delete"];
                    
                    if ([dicDatas valueForKey:@"extension"] && ![[dicDatas valueForKey:@"extension"] isKindOfClass:[NSNull class]])
                        template.extension = [dicDatas valueForKey:@"extension"];
                    
                    if ([dicDatas valueForKey:@"name"] && ![[dicDatas valueForKey:@"name"] isKindOfClass:[NSNull class]])
                        template.name = [dicDatas valueForKey:@"name"];
                    
                    if ([dicDatas valueForKey:@"preview"] && ![[dicDatas valueForKey:@"preview"] isKindOfClass:[NSNull class]])
                        template.preview = [dicDatas valueForKey:@"preview"];
                    
                    if ([dicDatas valueForKey:@"type"] && ![[dicDatas valueForKey:@"type"] isKindOfClass:[NSNull class]])
                        template.type = [dicDatas valueForKey:@"type"];
                    
                    [list addObject:template];
                }
                
                successRequest(response, list, request.redirectedServer);

            } else {
                
                NSString *message = (NSString *)[meta objectForKey:@"message"];
                if ([message isKindOfClass:[NSNull class]]) {
                    message = NSLocalizedString(@"_server_response_error_", nil);
                }
                failureRequest(response, [UtilsFramework getErrorWithCode:statusCode andCustomMessageFromTheServer:message], request.redirectedServer);
            }
            
        } else {
            failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
        }
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        
        //Return error
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)createNewRichdocuments:(NSString *)serverPath path:(NSString *)path templateID:(NSString *)templateID onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSString *url, NSString *redirectedServer))successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [serverPath stringByAppendingString:k_url_create_new_mobile_richdocuments];
    serverPath = [serverPath stringByAppendingString:@"?format=json"];
    
    OCWebDAVClient *request = [[OCWebDAVClient alloc] init];
    request = [self getRequestWithCredentials:request];
    
    [request createNewRichdocuments:serverPath path:path templateID:templateID onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *operation, id response) {
        
        NSData *responseData = (NSData*) response;
        
        //Parse
        NSError *error;
        NSDictionary *jsongParsed = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingMutableContainers error:&error];
        NSLog(@"[LOG] URL Asset : %@",jsongParsed);
        
        NSDictionary *ocs = [jsongParsed valueForKey:@"ocs"];
        NSDictionary *meta = [ocs valueForKey:@"meta"];
        NSDictionary *data = [ocs valueForKey:@"data"];
        
        NSInteger statusCode = [[meta valueForKey:@"statuscode"] integerValue];
        
        if (statusCode == kOCUserProfileAPISuccessful) {            
            if ([data valueForKey:@"url"] && ![[data valueForKey:@"url"] isKindOfClass:[NSNull class]])
                successRequest(response, [data valueForKey:@"url"], request.redirectedServer);
            else
                successRequest(response, nil, request.redirectedServer);
        } else {
            failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
        }
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        
        //Return error
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)createAssetRichdocuments:(NSString *)serverPath path:(NSString *)path onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSString *url, NSString *redirectedServer))successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [serverPath stringByAppendingString:k_url_insert_assets_to_richdocuments];
    serverPath = [serverPath stringByAppendingString:@"?format=json"];
    
    OCWebDAVClient *request = [[OCWebDAVClient alloc] init];
    request = [self getRequestWithCredentials:request];
    
    [request createAssetRichdocuments:serverPath path:path onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *operation, id response) {
        
        NSData *responseData = (NSData*) response;
        
        //Parse
        NSError *error;
        NSDictionary *jsongParsed = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingMutableContainers error:&error];
        NSLog(@"[LOG] URL Asset : %@",jsongParsed);
        
        if (jsongParsed && jsongParsed.allKeys > 0) {
            
            if ([jsongParsed valueForKey:@"url"] && ![[jsongParsed valueForKey:@"url"] isKindOfClass:[NSNull class]]) {
                    
                NSString *url = [jsongParsed valueForKey:@"url"];
                successRequest(response, url, request.redirectedServer);
                    
            } else {
                failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
            }
                
        } else {
            failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
        }
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        
        //Return error
        failureRequest(response, error, request.redirectedServer);
    }];
}

#pragma mark - Trash

- (void)listingTrash:(NSString *)path depth:(NSString *)depth onCommunication:(OCCommunication *)sharedOCCommunication successRequest:(void(^)(NSHTTPURLResponse *response, NSArray *items, NSString *redirectedServer)) successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest
{
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    path = [path encodeString:NSUTF8StringEncoding];

    [request listTrash:path depth:depth onCommunication:sharedOCCommunication success:^(NSHTTPURLResponse *response, id responseObject) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            NCXMLListParser *parser = [NCXMLListParser new];
            [parser initParserWithData:responseObject controlFirstFileOfList:true];
            NSMutableArray *list = [parser.list mutableCopy];
        
            dispatch_async(dispatch_get_main_queue(), ^{
                successRequest(response, list, request.redirectedServer);
            });
        });
    } failure:^(NSHTTPURLResponse *response, id responseData, NSError *error) {
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)emptyTrash:(NSString *)path onCommunication:(OCCommunication *)sharedOCCommunication successRequest:(void(^)(NSHTTPURLResponse *response, NSString *redirectedServer)) successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest
{
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request emptyTrash:path onCommunication:sharedOCCommunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        successRequest(response, request.redirectedServer);
        
    } failure:^(NSHTTPURLResponse *response, id responseData, NSError *error) {
        
        failureRequest(response, error, request.redirectedServer);
    }];
}

#pragma mark - Fulltextsearch

- (void)fullTextSearch:(NSString *)serverPath data:(NSString *)data onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSArray *items, NSString *redirectedServer))successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [serverPath stringByAppendingString:k_url_fulltextsearch];
    
    OCWebDAVClient *request = [[OCWebDAVClient alloc] init];
    request = [self getRequestWithCredentials:request];
    
    [request fullTextSearch:serverPath data:data onCommunication:sharedOCComunication success:^(NSHTTPURLResponse * _Nonnull operation, id  _Nonnull response) {
    
        NSData *responseData = (NSData*) response;
        
        //Parse
        NSError *error;
        NSDictionary *jsongParsed = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingMutableContainers error:&error];
        NSLog(@"[LOG] Link richdocuments : %@",jsongParsed);
        
        if (jsongParsed && jsongParsed.allKeys > 0) {
            
            successRequest(response, nil, request.redirectedServer);
       
        } else {
            
            failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
        }
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        
        //Return error
        failureRequest(response, error, request.redirectedServer);
    }];
}

#pragma mark - Remore wipe

- (void)getRemoteWipeStatus:(NSString *)serverPath token:(NSString *)token onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, BOOL wipe, NSString *redirectedServer))successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [NSString stringWithFormat:@"%@/%@/check", serverPath, k_url_get_wipe];
    
    OCWebDAVClient *request = [[OCWebDAVClient alloc] init];
    request = [self getRequestWithCredentials:request];
    
    [request getSetRemoteWipe:serverPath token:token onCommunication:sharedOCComunication success:^(NSHTTPURLResponse * _Nonnull operation, id  _Nonnull response) {
    
        NSData *responseData = (NSData*) response;
        
        //Parse
        NSError *error;
        NSDictionary *jsongParsed = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingMutableContainers error:&error];
        
        if (jsongParsed && jsongParsed.allKeys > 0) {
            
            BOOL wipe = (BOOL)[jsongParsed valueForKey:@"wipe"];
            successRequest(response, wipe, request.redirectedServer);
            
        } else {
            
            failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
        }
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {

        //Return error
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)setRemoteWipeCompletition:(NSString *)serverPath token:(NSString *)token onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSString *redirectedServer))successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [NSString stringWithFormat:@"%@/%@/success", serverPath, k_url_get_wipe];
    
    OCWebDAVClient *request = [[OCWebDAVClient alloc] init];
    request = [self getRequestWithCredentials:request];
    
    [request getSetRemoteWipe:serverPath token:token onCommunication:sharedOCComunication success:^(NSHTTPURLResponse * _Nonnull operation, id  _Nonnull response) {
        
        successRequest(response, request.redirectedServer);
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        
        failureRequest(response, error, request.redirectedServer);
    }];
}

#pragma mark - Comments

- (void)getComments:(NSString *)serverPath fileId:(NSString *)fileId onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSArray *list, NSString *redirectedServer))successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [NSString stringWithFormat:@"%@/comments/files/%@", serverPath, fileId];
    serverPath = [serverPath encodeString:NSUTF8StringEncoding];

    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request getComments:serverPath onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *response, id responseObject) {
        
        NSData *responseData = (NSData *)responseObject;
        
        NCXMLCommentsParser *parser = [NCXMLCommentsParser new];
        [parser initParserWithData:responseData];
        NSMutableArray *list = [parser.list mutableCopy];
        
        successRequest(response, list, request.redirectedServer);
        
    } failure:^(NSHTTPURLResponse *response, id responseData, NSError *error) {
        
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)putComments:(NSString*)serverPath fileId:(NSString *)fileId message:(NSString *)message onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSString *redirectedServer))successRequest  failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [NSString stringWithFormat:@"%@/comments/files/%@", serverPath, fileId];
    serverPath = [serverPath encodeString:NSUTF8StringEncoding];
    
    OCWebDAVClient *request = [[OCWebDAVClient alloc] init];
    request = [self getRequestWithCredentials:request];
    
    [request putComments:serverPath message:message onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *operation, id response) {
        
        successRequest(response, request.redirectedServer);

    } failure:^(NSHTTPURLResponse *response, id responseObject, NSError *error) {
        
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)updateComments:(NSString*)serverPath fileId:(NSString *)fileId messageID:(NSString *)messageID message:(NSString *)message onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSString *redirectedServer))successRequest  failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [NSString stringWithFormat:@"%@/comments/files/%@/%@", serverPath, fileId, messageID];
    serverPath = [serverPath encodeString:NSUTF8StringEncoding];
    
    OCWebDAVClient *request = [[OCWebDAVClient alloc] init];
    request = [self getRequestWithCredentials:request];
    
    [request updateComments:serverPath message:message onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *operation, id response) {
        
        successRequest(response, request.redirectedServer);
        
    } failure:^(NSHTTPURLResponse *response, id responseObject, NSError *error) {
        
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)readMarkComments:(NSString*)serverPath fileId:(NSString *)fileId onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSString *redirectedServer))successRequest  failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [NSString stringWithFormat:@"%@/comments/files/%@", serverPath, fileId];

    serverPath = [serverPath encodeString:NSUTF8StringEncoding];
    
    OCWebDAVClient *request = [[OCWebDAVClient alloc] init];
    request = [self getRequestWithCredentials:request];
    
    [request readMarkComments:serverPath onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *operation, id response) {
        
        successRequest(response, request.redirectedServer);
        
    } failure:^(NSHTTPURLResponse *response, id responseObject, NSError *error) {
        
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)deleteComments:(NSString*)serverPath fileId:(NSString *)fileId messageID:(NSString *)messageID onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSString *redirectedServer))successRequest  failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [NSString stringWithFormat:@"%@/comments/files/%@/%@", serverPath, fileId, messageID];
    serverPath = [serverPath encodeString:NSUTF8StringEncoding];
    
    OCWebDAVClient *request = [[OCWebDAVClient alloc] init];
    request = [self getRequestWithCredentials:request];
    
    [request deleteComments:serverPath onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *operation, id response) {
        
        successRequest(response, request.redirectedServer);
        
    } failure:^(NSHTTPURLResponse *response, id responseObject, NSError *error) {
        
        failureRequest(response, error, request.redirectedServer);
    }];
}

#pragma mark - Third Parts

- (void)getHCUserProfile:(NSString *)serverPath onCommunication:(OCCommunication *)sharedOCCommunication successRequest:(void(^)(NSHTTPURLResponse *response, OCUserProfile *userProfile, NSString *redirectedServer)) successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest
{
    serverPath = [serverPath encodeString:NSUTF8StringEncoding];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request getHCUserProfile:serverPath onCommunication:sharedOCCommunication success:^(NSHTTPURLResponse * _Nonnull operation, id  _Nonnull response) {
        
        NSData *responseData = (NSData*) response;
        OCUserProfile *userProfile = [OCUserProfile new];
        
        //Parse
        NSError *error;
        NSDictionary *jsongParsed = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingMutableContainers error:&error];
        NSLog(@"[LOG] User Profile : %@",jsongParsed);
        
        if (jsongParsed && jsongParsed.allKeys > 0) {
            
            NSDictionary *ocs = [jsongParsed valueForKey:@"ocs"];
            NSDictionary *meta = [ocs valueForKey:@"meta"];
            NSDictionary *data = [ocs valueForKey:@"data"];
            NSInteger statusCode = [[meta valueForKey:@"statuscode"] integerValue];
            
            data = [data valueForKey:@"data"];

            if (statusCode == kOCUserProfileAPISuccessful) {
                
                if ([data valueForKey:@"address"] && ![[data valueForKey:@"address"] isKindOfClass:[NSNull class]])
                    userProfile.address = [data valueForKey:@"address"];
                
                if ([data valueForKey:@"displayname"] && ![[data valueForKey:@"displayname"] isKindOfClass:[NSNull class]])
                    userProfile.displayName = [data valueForKey:@"displayname"];
                
                if ([data valueForKey:@"businesssize"] && ![[data valueForKey:@"businesssize"] isKindOfClass:[NSNull class]]) {
                    switch ([[data valueForKey:@"businesssize"] integerValue]) {
                        case 1:
                            userProfile.businessSize = @"1-4";
                            break;
                        case 5:
                            userProfile.businessSize = @"5-9";
                            break;
                        case 10:
                            userProfile.businessSize = @"10-19";
                            break;
                        case 20:
                            userProfile.businessSize = @"20-49";
                            break;
                        case 50:
                            userProfile.businessSize = @"50-99";
                            break;
                        case 100:
                            userProfile.businessSize = @"100-249";
                            break;
                        case 250:
                            userProfile.businessSize = @"250-499";
                            break;
                        case 500:
                            userProfile.businessSize = @"500-999";
                            break;
                        case 1000:
                            userProfile.businessSize = @"1000+";
                            break;
                        default:
                            break;
                    }
                }
               
                if ([data valueForKey:@"businesstype"] && ![[data valueForKey:@"businesstype"] isKindOfClass:[NSNull class]])
                    userProfile.businessType = [data valueForKey:@"businesstype"];
                
                if ([data valueForKey:@"city"] && ![[data valueForKey:@"city"] isKindOfClass:[NSNull class]])
                    userProfile.city = [data valueForKey:@"city"];
                
                if ([data valueForKey:@"company"] && ![[data valueForKey:@"company"] isKindOfClass:[NSNull class]])
                    userProfile.company = [data valueForKey:@"company"];
                
                if ([data valueForKey:@"country"] && ![[data valueForKey:@"country"] isKindOfClass:[NSNull class]])
                    userProfile.country = [data valueForKey:@"country"];
                
                if ([data valueForKey:@"email"] && ![[data valueForKey:@"email"] isKindOfClass:[NSNull class]])
                    userProfile.email = [data valueForKey:@"email"];
                
                if ([data valueForKey:@"phone"] && ![[data valueForKey:@"phone"] isKindOfClass:[NSNull class]])
                    userProfile.phone = [data valueForKey:@"phone"];
                
                if ([data valueForKey:@"role"] && ![[data valueForKey:@"role"] isKindOfClass:[NSNull class]])
                    userProfile.role = [data valueForKey:@"role"];
                
                if ([data valueForKey:@"twitter"] && ![[data valueForKey:@"twitter"] isKindOfClass:[NSNull class]])
                    userProfile.twitter = [data valueForKey:@"twitter"];
                
                if ([data valueForKey:@"website"] && ![[data valueForKey:@"website"] isKindOfClass:[NSNull class]])
                    userProfile.webpage = [data valueForKey:@"website"];
                
                if ([data valueForKey:@"zip"] && ![[data valueForKey:@"zip"] isKindOfClass:[NSNull class]])
                    userProfile.zip = [data valueForKey:@"zip"];
                
                successRequest(response, userProfile, request.redirectedServer);
                
            } else {
                
                NSString *message = (NSString *)[meta objectForKey:@"message"];
                if ([message isKindOfClass:[NSNull class]]) {
                    message = NSLocalizedString(@"_server_response_error_", nil);
                }
                failureRequest(response, [UtilsFramework getErrorWithCode:statusCode andCustomMessageFromTheServer:message], request.redirectedServer);
            }
            
        } else {
            failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
        }
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        
        failureRequest(response, error, request.redirectedServer);
    }];
    
}

- (void)putHCUserProfile:(NSString*)serverPath data:(NSString *)data onCommunication:(OCCommunication *)sharedOCComunication successRequest:(void(^)(NSHTTPURLResponse *response, NSString *redirectedServer))successRequest  failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest {
    
    serverPath = [serverPath encodeString:NSUTF8StringEncoding];

    OCWebDAVClient *request = [[OCWebDAVClient alloc] init];
    request = [self getRequestWithCredentials:request];
    
    [request putHCUserProfile:serverPath data:data onCommunication:sharedOCComunication success:^(NSHTTPURLResponse *operation, id response) {
        
        successRequest(response, request.redirectedServer);
        
    } failure:^(NSHTTPURLResponse *response, id responseObject, NSError *error) {
        
        failureRequest(response, error, request.redirectedServer);
    }];
}

- (void)getHCFeatures:(NSString *)serverPath onCommunication:(OCCommunication *)sharedOCCommunication successRequest:(void(^)(NSHTTPURLResponse *response, HCFeatures *features, NSString *redirectedServer)) successRequest failureRequest:(void(^)(NSHTTPURLResponse *response, NSError *error, NSString *redirectedServer)) failureRequest
{
    serverPath = [serverPath encodeString:NSUTF8StringEncoding];
    
    OCWebDAVClient *request = [OCWebDAVClient new];
    request = [self getRequestWithCredentials:request];
    
    [request getHCUserProfile:serverPath onCommunication:sharedOCCommunication success:^(NSHTTPURLResponse * _Nonnull operation, id  _Nonnull response) {
        
        NSData *responseData = (NSData*) response;
        HCFeatures *features = [HCFeatures new];
        
        //Parse
        NSError *error;
        NSDictionary *jsongParsed = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingMutableContainers error:&error];
        NSLog(@"[LOG] User Profile Features : %@",jsongParsed);
        
        if (jsongParsed && jsongParsed.allKeys > 0) {
            
            NSDictionary *ocs = [jsongParsed valueForKey:@"ocs"];
            NSDictionary *meta = [ocs valueForKey:@"meta"];
            NSDictionary *data = [ocs valueForKey:@"data"];
            NSInteger statusCode = [[meta valueForKey:@"statuscode"] integerValue];
            
            data = [data valueForKey:@"data"];
            
            if (statusCode == kOCUserProfileAPISuccessful) {
                
                if ([data valueForKey:@"is_trial"] && ![[data valueForKey:@"is_trial"] isKindOfClass:[NSNull class]])
                    features.isTrial = [[data valueForKey:@"is_trial"] boolValue];
                
                if ([data valueForKey:@"trial_expired"] && ![[data valueForKey:@"trial_expired"] isKindOfClass:[NSNull class]])
                    features.trialExpired = [[data valueForKey:@"trial_expired"] boolValue];
                
                if ([data valueForKey:@"trial_remaining_sec"] && ![[data valueForKey:@"trial_remaining_sec"] isKindOfClass:[NSNull class]])
                    features.trialRemainingSec = [[data valueForKey:@"trial_remaining_sec"] integerValue];
                
                if ([data valueForKey:@"trial_end_time"] && ![[data valueForKey:@"trial_end_time"] isKindOfClass:[NSNull class]])
                    features.trialEndTime = [[data valueForKey:@"trial_end_time"] integerValue];
                
                if ([data valueForKey:@"trial_end"] && ![[data valueForKey:@"trial_end"] isKindOfClass:[NSNull class]])
                    features.trialEnd = [data valueForKey:@"trial_end"];
                
                if ([data valueForKey:@"account_remove_expired"] && ![[data valueForKey:@"account_remove_expired"] isKindOfClass:[NSNull class]])
                    features.accountRemoveExpired = [[data valueForKey:@"account_remove_expired"] boolValue];
                
                if ([data valueForKey:@"account_remove_remaining_sec"] && ![[data valueForKey:@"account_remove_remaining_sec"] isKindOfClass:[NSNull class]])
                    features.accountRemoveRemainingSec = [[data valueForKey:@"account_remove_remaining_sec"] integerValue];
                
                if ([data valueForKey:@"account_remove_time"] && ![[data valueForKey:@"account_remove_time"] isKindOfClass:[NSNull class]])
                    features.accountRemoveTime = [[data valueForKey:@"account_remove_time"] integerValue];
                
                if ([data valueForKey:@"account_remove"] && ![[data valueForKey:@"account_remove"] isKindOfClass:[NSNull class]])
                    features.accountRemove = [data valueForKey:@"account_remove"];
                
                NSDictionary *nextGroupExpirationDic = [data valueForKey:@"next_group_expiration"];
                if (nextGroupExpirationDic) {
                    if ([nextGroupExpirationDic valueForKey:@"group"] && ![[nextGroupExpirationDic valueForKey:@"group"] isKindOfClass:[NSNull class]])
                        features.nextGroupExpirationGroup = [nextGroupExpirationDic valueForKey:@"group"];
                    
                    if ([nextGroupExpirationDic valueForKey:@"group_expired"] && ![[nextGroupExpirationDic valueForKey:@"group_expired"] isKindOfClass:[NSNull class]])
                        features.nextGroupExpirationGroupExpired = [[nextGroupExpirationDic valueForKey:@"group_expired"] boolValue];
                    
                    if ([nextGroupExpirationDic valueForKey:@"expires_time"] && ![[nextGroupExpirationDic valueForKey:@"expires_time"] isKindOfClass:[NSNull class]])
                        features.nextGroupExpirationExpiresTime = [[nextGroupExpirationDic valueForKey:@"expires_time"] integerValue];
                    
                    if ([nextGroupExpirationDic valueForKey:@"expires"] && ![[nextGroupExpirationDic valueForKey:@"expires"] isKindOfClass:[NSNull class]])
                        features.nextGroupExpirationExpires = [nextGroupExpirationDic valueForKey:@"expires"];
                }
                
                successRequest(response, features, request.redirectedServer);
                
            } else {
                
                NSString *message = (NSString *)[meta objectForKey:@"message"];
                if ([message isKindOfClass:[NSNull class]]) {
                    message = NSLocalizedString(@"_server_response_error_", nil);
                }
                failureRequest(response, [UtilsFramework getErrorWithCode:statusCode andCustomMessageFromTheServer:message], request.redirectedServer);
            }
            
        } else {
            failureRequest(response, [UtilsFramework getErrorWithCode:k_CCErrorWebdavResponseError andCustomMessageFromTheServer:NSLocalizedString(@"_server_response_error_", nil)], request.redirectedServer);
        }
        
    } failure:^(NSHTTPURLResponse *response, NSData *responseData, NSError *error) {
        
        failureRequest(response, error, request.redirectedServer);
    }];
    
}

#pragma mark - Manage Mobile Editor OCS API

- (void)eraseURLCache
{
    [[NSURLCache sharedURLCache] setMemoryCapacity:0];
    [[NSURLCache sharedURLCache] setDiskCapacity:0];
}

#pragma mark - Utils

- (void) addUserItemOfType:(NSInteger) shareeType fromArray:(NSArray*) usersArray ToList: (NSMutableArray *) itemList
{

    for (NSDictionary *userFound in usersArray) {
        OCShareUser *user = [OCShareUser new];
        
        if ([[userFound valueForKey:@"label"] isKindOfClass:[NSNumber class]]) {
            NSNumber *number = [userFound valueForKey:@"label"];
            user.displayName = [NSString stringWithFormat:@"%ld", number.longValue];
        }else{
            user.displayName = [userFound valueForKey:@"label"];
        }
        
        NSDictionary *userValues = [userFound valueForKey:@"value"];
        
        if ([[userValues valueForKey:@"shareWith"] isKindOfClass:[NSNumber class]]) {
            NSNumber *number = [userValues valueForKey:@"shareWith"];
            user.name = [NSString stringWithFormat:@"%ld", number.longValue];
        }else{
            user.name = [userValues valueForKey:@"shareWith"];
        }
        user.shareeType = shareeType;
        user.server = [userValues valueForKey:@"server"];
        
        [itemList addObject:user];
    }
}

- (void) addGroupItemFromArray:(NSArray*) groupsArray ToList: (NSMutableArray *) itemList
{
    for (NSDictionary *groupFound in groupsArray) {
        
        OCShareUser *group = [OCShareUser new];
        
        NSDictionary *groupValues = [groupFound valueForKey:@"value"];
        if ([[groupValues valueForKey:@"shareWith"] isKindOfClass:[NSNumber class]]) {
            NSNumber *number = [groupValues valueForKey:@"shareWith"];
            group.name = [NSString stringWithFormat:@"%ld", number.longValue];
        }else{
            group.name = [groupValues valueForKey:@"shareWith"];
        }
        group.shareeType = shareTypeGroup;
        
        [itemList addObject:group];
        
    }
}

@end
