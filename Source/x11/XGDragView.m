/*
   XGDragView - Drag and Drop code for X11 backends.

   Copyright (C) 1998-2010 Free Software Foundation, Inc.

   Created by: Wim Oudshoorn <woudshoo@xs4all.nl>
   Date: Nov 2001

   Written by:  Adam Fedor <fedor@gnu.org>
   Date: Nov 1998
   
   This file is part of the GNU Objective C User Interface Library.

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

#include <Foundation/NSDebug.h>
#include <Foundation/NSThread.h>
#include <Foundation/NSSet.h>

#include <AppKit/NSApplication.h>
#include <AppKit/NSCursor.h>
#include <AppKit/NSGraphics.h>
#include <AppKit/NSImage.h>
#include <AppKit/NSPasteboard.h>
#include <AppKit/NSView.h>
#include <AppKit/NSWindow.h>

#include "x11/XGServer.h"
#include "x11/XGServerWindow.h"
#include "x11/XGDragView.h"

/* Size of the dragged window */
#define	DWZ	48

#define XDPY  [XGServer xDisplay]

#define SLIDE_TIME_STEP   .02   /* in seconds */
#define SLIDE_NR_OF_STEPS 20  

#define	DRAGWINDEV [XGServer _windowWithTag: [_window windowNumber]]
#define	XX(P)	(P.x)
#define	XY(P)	([(XGServer *)GSCurrentServer() xScreenSize].height - P.y)



@interface XGRawWindow : NSWindow
@end

@interface NSCursor (BackendPrivate)
- (void *)_cid;
- (void) _setCid: (void *)val;
@end

// --- DRAG AND DROP SUPPORT  (XDND) -----------------------------------

/*
 * This will get initialized when we declare a window that will
 * accept dragging or if we start a dragging ourself. Up to than
 * even the dragging messages are not defined.
 */
static DndClass dnd;
static BOOL     xDndInitialized = NO;

/*
 * Macros to access elements in atom_names array.
 */
#define XG_CHAR_POSITION        dnd.atoms[0]
#define XG_CLIENT_WINDOW        dnd.atoms[1]
#define XG_HOST_NAME            dnd.atoms[2]
#define XG_HOSTNAME             dnd.atoms[3]
#define XG_LENGTH               dnd.atoms[4]
#define XG_LIST_LENGTH          dnd.atoms[5]
#define XG_NAME                 dnd.atoms[6]
#define XG_OWNER_OS             dnd.atoms[7]
#define XG_SPAN                 dnd.atoms[8]
#define XG_TARGETS              dnd.atoms[9]
#define XG_TIMESTAMP            dnd.atoms[10]
#define XG_USER                 dnd.atoms[11]
#define XG_TEXT                 dnd.atoms[12]
#define XG_NULL                 dnd.atoms[13]
#define XG_FILE_NAME		dnd.atoms[14]
#define XA_CLIPBOARD		dnd.atoms[15]
#define XG_UTF8_STRING		dnd.atoms[16]
#define XG_MULTIPLE		dnd.atoms[17]
#define XG_COMPOUND_TEXT	dnd.atoms[18]
#define XG_INCR         	dnd.atoms[19]
#define XG_MIME_PLAIN    	dnd.atoms[20]
#define XG_MIME_URI      	dnd.atoms[21]
#define XG_MIME_PS      	dnd.atoms[22]
#define XG_MIME_TSV      	dnd.atoms[23]
#define XG_MIME_RICHTEXT  dnd.atoms[24]
#define XG_MIME_TIFF      dnd.atoms[25]
#define XG_MIME_OCTET     dnd.atoms[26]
#define XG_MIME_ROOTWINDOW dnd.atoms[27]
#define XG_MIME_APP_RICHTEXT dnd.atoms[28]
#define XG_MIME_RTF       dnd.atoms[29]
#define XG_MIME_HTML      dnd.atoms[30]
#define XG_MIME_XHTML     dnd.atoms[31]
#define XG_MIME_PNG       dnd.atoms[32]
#define XG_MIME_SVG       dnd.atoms[33]
#define XG_MIME_APP_RTF   dnd.atoms[34]
#define XG_MIME_TEXT_RICHTEXT dnd.atoms[35]

void
GSEnsureDndIsInitialized (void)
{
  if (xDndInitialized == NO)
    {
      xDndInitialized = YES;
      xdnd_init (&dnd, XDPY);
    }
}


DndClass xdnd (void)
{
  return dnd;			// FIX ME rename with private desig
}


Atom 
GSActionForDragOperation(unsigned int op)
{
  Atom xaction;

  if (op == NSDragOperationEvery)
    xaction = dnd.XdndActionAsk;
  else if (op == NSDragOperationAll)
    xaction = dnd.XdndActionAsk;
  else if (op & NSDragOperationCopy)
    xaction = dnd.XdndActionCopy;
  else if (op & NSDragOperationLink)
    xaction = dnd.XdndActionLink;
  else if (op & NSDragOperationGeneric)
    xaction = dnd.XdndActionCopy;
  else if (op & NSDragOperationPrivate)
    xaction = dnd.XdndActionPrivate;
  else if (op & NSDragOperationMove)
    xaction = dnd.XdndActionMove;
  else 
    xaction = None;
  return xaction;
}


NSDragOperation
GSDragOperationForAction(Atom xaction)
{
  NSDragOperation action;
  if (xaction == dnd.XdndActionCopy)
    action = NSDragOperationCopy;
  else if (xaction == dnd.XdndActionMove)
    action = NSDragOperationMove;
  else if (xaction == dnd.XdndActionLink)
    action = NSDragOperationLink;
  else if (xaction == dnd.XdndActionAsk)
    action = NSDragOperationEvery;
  else if (xaction == dnd.XdndActionPrivate)
    action = NSDragOperationPrivate;
  else
    action = NSDragOperationNone;
  return action;
}

// The result of this function must be freed by the caller
static inline
Atom *
mimeTypeForPasteboardType(Display *xDisplay, NSZone *zone, NSArray *types)
{
  Atom	*typelist;
  int	count = [types count];
  int	i;

  typelist = NSZoneMalloc(zone, (count+1) * sizeof(Atom));
  for (i = 0; i < count; i++)
    {
      NSString	*mime;

      mime = [types objectAtIndex: i];
      mime = [NSPasteboard mimeTypeForPasteboardType: mime];
      typelist[i] = XInternAtom(xDisplay, [mime cString], False);
    }
  typelist[count] = 0;

  return typelist;
}

// FIXME: code duplication... a copy from xpbs.m
static inline
NSArray *
pasteboardTypeForMimeType(Display *xDisplay, NSZone *zone, Atom *typelist)
{
  Atom            *type = typelist;
  NSMutableArray  *newTypes = [[NSMutableArray allocWithZone: zone] init];
  NSString        *mime;
  NSString        *ptype;

  while (*type != None)
    {
      char *s = XGetAtomName(xDisplay, *type);
      if (s)
	{
	  mime = [[NSString alloc] initWithCString: s encoding: NSASCIIStringEncoding];
	  ptype = [NSPasteboard pasteboardTypeForMimeType: mime];
	  if (ptype && ptype != mime)
	    {
	      // only supported ones are added
	      [newTypes addObject: ptype];
	    }
	  XFree(s);
	  RELEASE(mime);
	}
      type++;
    }

  return AUTORELEASE(newTypes);
}



@implementation XGDragView

static	XGDragView	*sharedDragView = nil;

+ (id) sharedDragView
{
  if (sharedDragView == nil)
    {
      GSEnsureDndIsInitialized ();
      sharedDragView = [XGDragView new];
    }
  return sharedDragView;
}

+ (Class) windowClass
{
  return [XGRawWindow class];
}

- (id) init
{
  self = [super init];
  if (self != nil)
    {
      changeCount = -1;
    }

  return self;
}

/*
 * Produces the pasteboard types available for DnD
 * from the source/dragger window.
 */
- (NSArray*) _availableTypes
{
  Atom *types;
  NSArray *newTypes;

  if (dnd.dragger_window == None)
    return nil;

  xdnd_get_type_list(&dnd, dnd.dragger_window, &types);
  newTypes = pasteboardTypeForMimeType(XDPY, [self zone], types);
  free(types);
  return newTypes;
}

/*
 * External drag operation
 */
- (void) setupDragInfoFromXEvent: (XEvent *)xEvent
{
  // Start a dragging session from another application
  dragSource = nil;
  destExternal = YES;
  operationMask = NSDragOperationAll;

  ASSIGN(dragPasteboard, [NSPasteboard pasteboardWithName: NSDragPboard]);

  dnd.dragger_window = XGetSelectionOwner(XDPY, dnd.XdndSelection);
  dnd.dropper_window = ((XAnyEvent *)xEvent)->window;

  changeCount = [dragPasteboard declareTypes: [self _availableTypes]
				       owner: self];
}

- (void) updateDragInfoFromEvent: (NSEvent*)event
{
  // Store the drag info, so that we can send status messages as response
  gswindow_device_t	*window = [XGServer _windowWithTag: [event windowNumber]];
  destWindow = GSWindowWithNumber(window->number);

  //destWindow = [event window]; // <- bug... XGServerEvent calls -[updateDragInfoFromEvent:] on receiving
                               //           XdndPosition which sent by the source/dragger to the target/destination/dropper.
                               //           The event's window points to the source/dragger window not the destination.
  dragPoint = [event locationInWindow];
  dragSequence = [event timestamp];
  dnd.time = ((Time)dragSequence)*1000;
  NSLog(@"dnd.time %lld", dnd.time);
  dragMask = [event data2];
}

- (void) resetDragInfo
{
  dnd.stage = XDND_DROP_STAGE_IDLE;
  dnd.dragger_window = None;
  dnd.dropper_window = None;
  dnd.time = CurrentTime;
  dnd.property = None;
  changeCount = -1;
  DESTROY(dragPasteboard);
}

/* switch the state into XDND_DROP_STAGE_ENTERED */
- (void)enterDropStage:(XEvent *)xEvent
{
  // trigger dropping
  dnd.stage = XDND_DROP_STAGE_ENTERED;
  dnd.property = xEvent->xselection.property;
}

/* FIXME... code duplication... it is a copy from xpbs.m */
#define FULL_LENGTH 8192L	/* Amount to read */
- (NSMutableData*) getSelectionDataOfType: (Atom*)type
{
  int		status;
  unsigned char	*data;
  long long_offset = 0L;
  long long_length = FULL_LENGTH;
  Atom req_type = AnyPropertyType;
  Atom actual_type;
  int		actual_format;
  unsigned long	bytes_remaining;
  unsigned long	number_items;
  NSMutableData	*md = nil;

  /*
   * Read data from property identified in SelectionNotify event.
   */
  do
    {
      status = XGetWindowProperty(dnd.display,
                                  dnd.dropper_window,
                                  dnd.property,
                                  long_offset,         // offset
                                  long_length,
                                  False,               // Aug 2011 - changed to False (don't delete property)
                                  req_type,
                                  &actual_type,
                                  &actual_format,
                                  &number_items,
                                  &bytes_remaining,
                                  &data);

      if ((status == Success) && (number_items > 0))
        {
          long count;
	  if (actual_type == XA_ATOM)
	    {
	      // xlib will report an actual_format of 32, even if
	      // data contains an array of 64-bit Atoms
	      count = number_items * sizeof(Atom);
	    }
	  else
	    {
	      count = number_items * actual_format / 8;
	    }

          if (md == nil)
            {
              md = [[NSMutableData alloc] initWithBytes: (void *)data
                                          length: count];
              req_type = actual_type;
            }
          else
            {
              if (req_type != actual_type)
                {
                  char *req_name = XGetAtomName(dnd.display, req_type);
                  char *act_name = XGetAtomName(dnd.display, actual_type);

                  NSLog(@"Selection changed type from %s to %s.",
                        req_name, act_name);
                  XFree(req_name);
                  XFree(act_name);
                  RELEASE(md);
                  return nil;
                }
              [md appendBytes: (void *)data length: count];
            }

          long_offset += count / 4;
          if (data)
            {
              XFree(data);
            }
        }
    }
  while ((status == Success) && (bytes_remaining > 0));

  if (status == Success)
    {
      *type = actual_type;
      return AUTORELEASE(md);
    }
  else
    {
      RELEASE(md);
      return nil;
    }
}

- (void)pasteboard:(NSPasteboard *)pb provideDataForType:(NSString *)type
{
  NSDate                *timeoutDate;
  Atom                  *tlist;
  Atom actual_type;
  NSMutableData	*md = nil;
  id runLoopMode;
  int ret;

  if (destWindow != nil && changeCount == [pb changeCount])
    {
      dnd.stage = XDND_DROP_STAGE_CONVERTING;

      tlist = mimeTypeForPasteboardType (XDPY, [self zone], [NSArray arrayWithObject: type]);
      ret = xdnd_convert_selection(&dnd,
				   dnd.dragger_window, // owner
				   dnd.dropper_window, // requestor
				   tlist[0]);       // type
      NSZoneFree([self zone], tlist);
      tlist = NULL;

      if (ret != 0)
	{
	  [pb setData: nil forType: type];
	  return;
	}

      // now wait for SelectionNotify

      timeoutDate = [NSDate dateWithTimeIntervalSinceNow: 5.0];
      runLoopMode = [[NSRunLoop currentRunLoop] currentMode];
      while (dnd.stage != XDND_DROP_STAGE_ENTERED &&
	     [timeoutDate timeIntervalSinceNow] > 0.0)
	{
	  [[NSRunLoop currentRunLoop]
		       runMode: runLoopMode
		    beforeDate: timeoutDate];
	}


      if (dnd.stage == XDND_DROP_STAGE_ENTERED)
	{
	  md = [self getSelectionDataOfType: &actual_type];

	  if (md != nil)
	    {
	      if (actual_type == XG_INCR)
		{
		  XEvent event;
		  NSMutableData	*imd = nil;
		  BOOL wait = YES;

		  md = nil;
		  while (wait)
		    {
		      XNextEvent(dnd.display, &event);

		      if (event.type == PropertyNotify)
			{
			  if (event.xproperty.state != PropertyNewValue) continue;

			  imd = [self getSelectionDataOfType: &actual_type];
			  if (imd != nil)
			    {
			      if (md == nil)
				{
				  md = imd;
				}
			      else
				{
				  [md appendData: imd];
				}
			    }
			  else
			    {
			      wait = NO;
			    }
			}
		    }
		}
	    }

	  if (md != nil)
	    {
	      // Convert data to text string.
	      if (actual_type == XG_UTF8_STRING)
		{
		  NSString	*s;
		  NSData	*d;

		  s = [[NSString alloc] initWithData: md
					    encoding: NSUTF8StringEncoding];
		  if (s != nil)
		    {
		      d = [NSSerializer serializePropertyList: s];
		      RELEASE(s);
		      [pb setData: d forType: type];
		    }
		}
	      else if ((actual_type == XA_STRING)
		       || (actual_type == XG_TEXT)
		       || (actual_type == XG_MIME_PLAIN))
		{
		  NSString	*s;
		  NSData	*d;

		  s = [[NSString alloc] initWithData: md
					    encoding: NSISOLatin1StringEncoding];
		  if (s != nil)
		    {
		      d = [NSSerializer serializePropertyList: s];
		      RELEASE(s);
		      [pb setData: d forType: type];
		    }
		}
	      else if (actual_type == XG_FILE_NAME)
		{
		  NSArray *names;
		  NSData *d;
		  NSString *s;
		  NSURL *url;

		  s = [[NSString alloc] initWithData: md
					    encoding: NSUTF8StringEncoding];
		  url = [[NSURL alloc] initWithString: s];
		  RELEASE(s);
		  if ([url isFileURL])
		    {
		      s = [url path];
		      names = [NSArray arrayWithObject: s];
		      d = [NSSerializer serializePropertyList: names];
		      [pb setData: d forType: type];
		    }
		  RELEASE(url);
		}
	      else if ((actual_type == XG_MIME_RTF)
		       || (actual_type == XG_MIME_APP_RTF)
		       || (actual_type == XG_MIME_TEXT_RICHTEXT))
		{
		  [pb setData: md forType: type];
		}
	      else if (actual_type == XG_MIME_TIFF)
		{
		  [pb setData: md forType: type];
		}
	      else if (actual_type == XA_ATOM)
		{
		  // Used when requesting TARGETS to get available types
		  [pb setData: md forType: type];
		}
	      else
		{
		  char *name = XGetAtomName(dnd.display, actual_type);

		  NSDebugLLog(@"NSDragging", @"Unsupported data type '%s' from X selection.", 
			      name);
		  XFree(name);
		}
	    }
	}
      else
	{
	  NSDebugLLog(@"NSDragging", @"DnD is canceled by timeout");
	  [self resetDragInfo];
	}
    }
}

/*
 * Local drag operation
 */

- (void) dragImage: (NSImage*)anImage
		at: (NSPoint)screenLocation
	    offset: (NSSize)initialOffset
	     event: (NSEvent*)event
	pasteboard: (NSPasteboard*)pboard
	    source: (id)sourceObject
	 slideBack: (BOOL)slideFlag
{
  typelist = mimeTypeForPasteboardType (XDPY, [self zone], [pboard types]);
  [super dragImage: anImage
		at: screenLocation
	    offset: initialOffset
	     event: event
	pasteboard: pboard
	    source: sourceObject
	 slideBack: slideFlag];
  NSZoneFree([self zone], typelist);
  typelist = NULL;
}

- (void) postDragEvent: (NSEvent *)theEvent
{
  if (destExternal)
    {
      gswindow_device_t	*window;

      window = [XGServer _windowWithTag: [theEvent windowNumber]];
      if ([theEvent subtype] == GSAppKitDraggingStatus)
	{
	  NSDragOperation action = [theEvent data2];
	  Atom xaction;

	  xaction = GSActionForDragOperation(action);
	  xdnd_send_status(&dnd,
			   [theEvent data1],
			   window->ident,
			   (action != NSDragOperationNone),
			   0,
			   0, 0, 0, 0,
			   xaction);
	}
      else if ([theEvent subtype] == GSAppKitDraggingFinished)
	{
	  xdnd_send_finished(&dnd, [theEvent data1], window->ident, 0);
	}
    }
  else
    {
      [super postDragEvent: theEvent];
    }
}

- (void) sendExternalEvent: (GSAppKitSubtype)subtype
                    action: (NSDragOperation)action
                  position: (NSPoint)eventLocation
                 timestamp: (NSTimeInterval)time
                  toWindow: (int)dWindowNumber
{
  gswindow_device_t *dragWindev = DRAGWINDEV;

  switch (subtype)
    {
      case GSAppKitDraggingDrop:
        if (targetWindowRef == dragWindev->root)
          {
            // FIXME There is an xdnd extension for root drop
          }
        xdnd_send_drop(&dnd, dWindowNumber, dragWindev->ident, time * 1000);
        break;

      case GSAppKitDraggingUpdate:
        xdnd_send_position(&dnd, dWindowNumber, dragWindev->ident,
                           GSActionForDragOperation(dragMask & operationMask),
                           XX(newPosition), XY(newPosition), time * 1000);
        break;

      case GSAppKitDraggingEnter:
        // FIXME: The first two lines need only be called once for every drag operation.
        // They should be moved to a different method.
        xdnd_set_selection_owner(&dnd, dragWindev->ident, typelist[0]);
        xdnd_set_type_list(&dnd, dragWindev->ident, typelist);

        xdnd_send_enter(&dnd, dWindowNumber, dragWindev->ident, typelist);
        xdnd_send_position(&dnd, dWindowNumber, dragWindev->ident,
                           GSActionForDragOperation (dragMask & operationMask),
                           XX(dragPosition), XY(dragPosition), time * 1000);
        break;

      case GSAppKitDraggingExit:
        xdnd_send_leave(&dnd, dWindowNumber, dragWindev->ident);
        break;

      default:
        break;
    }
}


- (NSWindow*) windowAcceptingDnDunder: (NSPoint)p
			    windowRef: (int*)mouseWindowRef
{
  gswindow_device_t	*dwindev;

  *mouseWindowRef = [self _xWindowAcceptingDnDunderX: XX(p) Y: XY(p)];
  dwindev = [XGServer _windowForXWindow: *mouseWindowRef];

  if (dwindev != 0)
    {
      return GSWindowWithNumber(dwindev->number);
    }
  else
    {
      return nil;
    }
}



/*
  Search all descendents of parent and return
  X window  containing screen coordinates (x,y) that accepts drag and drop.
  -1        if we can only find the X window that we are dragging
  None      if there is no X window that accepts drag and drop.
*/
- (Window) _xWindowAcceptingDnDDescendentOf: (Window) parent
                                   ignoring: (Window) ident
				     underX: (int) x 
					  Y: (int) y
{
  Window *children;
  unsigned int nchildren;
  Window  result = None;
  Window  ignore, child2, root;
  Display *display = XDPY;
  XWindowAttributes attr;
  int ret_x, ret_y;

  if (parent == ident)
    return -1;

  XQueryTree(display, parent, &root, &ignore, &children, &nchildren);

  while (nchildren-- > 0)
    {
      Window child = children [nchildren];

      if (XGetWindowAttributes (display, child, &attr)
	&& attr.map_state == IsViewable
	&& XTranslateCoordinates (display, root, child, x, y, &ret_x, &ret_y,
	  &child2)
	&& ret_x >= 0 && ret_x < attr.width
	&& ret_y >= 0 && ret_y < attr.height)
        {
          result = [self _xWindowAcceptingDnDDescendentOf: child
                                                 ignoring: ident
						   underX: x
							Y: y];
          // With window decoration there may be multiple windows
          // at the same place. Try all of them.
          if ((result != (Window)-1) && (result != (Window) None))
            {
              break;
            }
        }
    }

  if (children)
    {
      XFree (children);
    }
  if (result == (Window) None)
    {
      if (xdnd_is_dnd_aware (&dnd, parent, &dnd.dragging_version, typelist))
        {
          result = parent;
        }
    }

  return result;
}

/*
  Return window under the mouse that accepts drag and drop
 */
- (Window) _xWindowAcceptingDnDunderX: (int) x Y: (int) y
{
  Window result;
  gswindow_device_t *dragWindev = DRAGWINDEV;

  result = [self _xWindowAcceptingDnDDescendentOf: dragWindev->root
                                         ignoring: dragWindev->ident
					   underX: x
						Y: y];
  if (result == (Window)-1)
    return None;
  else
    return result;
}

@end



@interface XGServer (DragAndDrop)
- (void) _resetDragTypesForWindow: (NSWindow *)win;
@end


@implementation XGServer (DragAndDrop)

- (void) _resetDragTypesForWindow: (NSWindow *)win
{
  int			winNum;
  Atom			*typelist;
  gswindow_device_t	*window;
  NSCountedSet		*drag_set = [self dragTypesForWindow: win];

  winNum = [win windowNumber];
  window = [[self class] _windowWithTag: winNum];

  GSEnsureDndIsInitialized ();

  typelist = mimeTypeForPasteboardType(XDPY, [self zone],
				       [drag_set allObjects]);
  NSDebugLLog(@"NSDragging", @"Set types on %lu to %@", 
	      window->ident, drag_set);
  xdnd_set_dnd_aware(&dnd, window->ident, typelist);

  NSZoneFree([self zone], typelist);
}

- (BOOL) addDragTypes: (NSArray*)types toWindow: (NSWindow *)win
{
  BOOL	did_add;
  int	winNum;

  did_add = [super addDragTypes: types toWindow: win];
  /* Check if window device exists */
  winNum = [win windowNumber];
  if (winNum > 0 && did_add == YES)
    {
      [self _resetDragTypesForWindow: win];
    }
  return did_add;
}

- (BOOL) removeDragTypes: (NSArray*)types fromWindow: (NSWindow *)win
{
  BOOL	did_change;
  int	winNum;

  did_change = [super removeDragTypes: types fromWindow: win];
  /* Check if window device exists. */
  winNum = [win windowNumber];
  if (winNum > 0 && did_change == YES)
    {
      [self _resetDragTypesForWindow: win];
    }
  return did_change;
}

@end




@implementation XGRawWindow

- (BOOL) canBecomeMainWindow
{
  return NO;
}

- (BOOL) canBecomeKeyWindow
{
  return NO;
}

- (void) _initDefaults
{
  [super _initDefaults];
  [self setReleasedWhenClosed: NO];
  [self setExcludedFromWindowsMenu: YES];
}

- (void) orderWindow: (NSWindowOrderingMode)place relativeTo: (NSInteger)otherWin
{
  XSetWindowAttributes winattrs;
  unsigned long valuemask;
  gswindow_device_t *window;

  [super orderWindow: place relativeTo: otherWin];

  window = [XGServer _windowWithTag: _windowNum];
  valuemask = (CWSaveUnder|CWOverrideRedirect);
  winattrs.save_under = True;
  /* Temporarily make this False? we don't handle it correctly (fedor) */
  winattrs.override_redirect = False;
  XChangeWindowAttributes (XDPY, window->ident, valuemask, &winattrs);
  [self setLevel: NSPopUpMenuWindowLevel];
}

@end
