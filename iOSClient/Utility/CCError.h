//
//  CCError.h
//  Nextcloud
//
//  Created by Marino Faggiana on 04/02/16.
//  Copyright (c) 2016 Marino Faggiana. All rights reserved.
//
//  Author Marino Faggiana <marino.faggiana@nextcloud.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

#import <Foundation/Foundation.h>

#import "OCErrorMsg.h"

@interface CCError : NSObject

+ (NSString *)manageErrorKCF:(NSInteger)errorCode withNumberError:(BOOL)withNumberError;

+ (NSString *)manageErrorDB:(NSInteger)errorCode;

+ (NSString *)manageErrorOC:(NSInteger)errorCode error:(NSError *)error;

@end
