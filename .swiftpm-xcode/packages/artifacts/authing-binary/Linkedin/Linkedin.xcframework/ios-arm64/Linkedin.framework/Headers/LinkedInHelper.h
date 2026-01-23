//
//  LinkedInHelper.h
//  linkedinDemo
//
//  Created by Ahmet MacPro on 22.3.2015.
//  Copyright (c) 2015 ahmetkgunay. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LinkedInHelper : NSObject

/*!
 * @brief Initialize shared Instance
 */
+ (LinkedInHelper *)sharedInstance;

/*!
 * @brief Connects the user to Linkedin and fetchs user informations
 * @param sender is the UIViewcontroller which the web authentication will be fired from
 * @param clientId the clientId of application that you created on linkedin developer portal
 * @param redirectUrl the applicationWithRedirectURL of application that you created on linkedin developer portal
 * @param permissions the grantedaccesses to fetch from Linkedin Rest api
 * @param failure Returns the failure statement of connection
 * @param state defaults DCEEFWF45453sdffef424
 * @warning redirectUrl can not be nil!
 * @warning clientId can not be nil!
 * @warning clientSecret can not be nil!
 */
- (void)requestMeWithSenderViewController:(id)sender
                                 clientId:(NSString *)clientId
                              redirectUrl:(NSString *)redirectUrl
                              permissions:(NSString *)permissions
                                    state:(NSString *)state
                         codeSuccessBlock:( void (^) (NSString *code) )codeSuccessBlock
                        failUserInfoBlock:( void (^) (NSError *error))failure;




/*!
 * @brief Cancel Button's text while getting AuthorizationCode via webview
 */
@property (nonatomic, copy) NSString *cancelButtonText;

/*!
 * @brief Yes if automaticly shows the activity indicator on the webview while getting authorization code
 */
@property (nonatomic, assign) BOOL showActivityIndicator;

/*!
 * @brief This library uses some default subpermissions (Look at LinkedInAppSettings.m Line:84)
 * And If you do not want to use this values so u can make your own with this property by using fields in LinkedInIOSFields.h or by visiting https://developer.linkedin.com/docs/fields
 * If THIS VALUE IS NIL SO LIBRARY FETCH'S ALMOST ALL INFORMATIONS OF MEMBER!! (BY PREPARING THIS VALUE IN LinkedInAppSettings.m Line:84)
 */
@property (nonatomic, copy) NSString *customSubPermissions;


// ================== Frequently Using Fields  =================

/*!
 * @brief User's job title
 */
@property (nonatomic, copy, readonly) NSString *title;

/*!
 * @brief User's company Name
 */
@property (nonatomic, copy, readonly) NSString *companyName;

/*!
 * @brief User's email Address
 */
@property (nonatomic, copy, readonly) NSString *emailAddress;

/*!
 * @brief User's Photo Url
 */
@property (nonatomic, copy, readonly) NSString *photo;

/*!
 * @brief User's Industry name
 */
@property (nonatomic, copy, readonly) NSString *industry;

/*!
 * @brief Access Token comes from Linkedin
 */
- (NSString *)accessToken;

/*!
 * @brief Removes All token and authorization data from keychain
 */
- (void)logout;

@end
