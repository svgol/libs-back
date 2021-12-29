/* The header for X-specific DND session info

   Copyright (C) 2021 Free Software Foundation, Inc.

   Written by:  Sergei Golovin <Golovin.SV@gmail.com>
   Date: Dec 2021

   This file is part of the GNUstep project

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	 See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; see the file COPYING.LIB.
   If not, see <http://www.gnu.org/licenses/> or write to the
   Free Software Foundation, 51 Franklin Street, Fifth Floor,
   Boston, MA 02110-1301, USA.
*/

#ifndef _GNUstep_H_XDNDSession
#define _GNUstep_H_XDNDSession

#include <Foundation/NSObject.h>

#include "x11/XGServerWindow.h"
#include "x11/xdnd.h"

/**
 * This class fuses the GNUstep and X DnD technologies together.
 * The class will get initialized when we declare a window that will
 * accept dragging or if we start a dragging ourself. Up to than
 * even the dragging messages are not defined.
 */
@interface XDNDSession : NSObject
{
  DndClass   _dnd; // X-specific structure (xdnd.h)
  int sessionType; // the type of X dnd session:
		   // XDND_SESSION_LOCAL, XDND_SESSION_GS_GS,
		   // XDND_SESSION_GS_X, XDND_SESSION_X_GS
}
+ (id) sharedSession;

- (id)init;

/**
 *  The method to call on incoming X-events.
 *  Returns NO if the DnD session fails.
 */
- (BOOL)receive:(XEvent *)xEvent;

/**
 * The method to scheduled auxilliary timer.
 */
- (void)timer:(id)arg;

/**
 *  Supply the pasteboard with the data for the type.
 */
- (void)pasteboard:(NSPasteboard *)pb provideDataForType:(NSString *)type;

/**
 *  Reset the current DnD session.
 */
- (void)reset;

/*
 * Produces the pasteboard types available for DnD
 * from the source/dragger window.
 */
- (NSArray*) availableTypesFromXDragger;

/**
 *  Whether the dragger(source) is X-app, not GNUstep one.
 */
- (BOOL)isXDragger;

@end

#endif // _GNUstep_H_XDNDSession
