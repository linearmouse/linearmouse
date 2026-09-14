//
//  Header.h
//  
//
//  Created by Jiahao Lu on 2022/7/25.
//

#ifndef CGSKITC_H
#define CGSKITC_H

#import <Foundation/Foundation.h>
#import <IOKit/hidsystem/ev_keymap.h>
#import <IOKit/hidsystem/IOHIDLib.h>

#import "../CGSInternal/CGSInternal.h"

kern_return_t KeyKitPostAuxControlButton(io_connect_t handle, const NXEventData *eventData);

#endif /* CGSKITC_H */
