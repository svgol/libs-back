/* The X-specific DND session

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

#include "x11/XDNDSession.h"
#include "x11/XGDragView.h"

#include <Foundation/NSData.h>
#include <Foundation/NSRunLoop.h>
#include <Foundation/NSDebug.h>

#include <AppKit/NSPasteboard.h>

#define XDND_SESSION_NONE  -1 // no active DnD session
#define XDND_SESSION_LOCAL  0 // a local DnD session inside a GNUstep app
#define XDND_SESSION_GS_GS  1 // a DnD session between two GNUstep apps
#define XDND_SESSION_GS_X   2 // a DnD session from GNUstep app to another X-App
#define XDND_SESSION_X_GS   3 // a DnD session from another X-app to GNUstep app

/*
 * Macros to access elements in atom_names array.
 */
#define XG_CHAR_POSITION        _dnd.atoms[0]
#define XG_CLIENT_WINDOW        _dnd.atoms[1]
#define XG_HOST_NAME            _dnd.atoms[2]
#define XG_HOSTNAME             _dnd.atoms[3]
#define XG_LENGTH               _dnd.atoms[4]
#define XG_LIST_LENGTH          _dnd.atoms[5]
#define XG_NAME                 _dnd.atoms[6]
#define XG_OWNER_OS             _dnd.atoms[7]
#define XG_SPAN                 _dnd.atoms[8]
#define XG_TARGETS              _dnd.atoms[9]
#define XG_TIMESTAMP            _dnd.atoms[10]
#define XG_USER                 _dnd.atoms[11]
#define XG_TEXT                 _dnd.atoms[12]
#define XG_NULL                 _dnd.atoms[13]
#define XG_FILE_NAME		_dnd.atoms[14]
#define XA_CLIPBOARD		_dnd.atoms[15]
#define XG_UTF8_STRING		_dnd.atoms[16]
#define XG_MULTIPLE		_dnd.atoms[17]
#define XG_COMPOUND_TEXT	_dnd.atoms[18]
#define XG_INCR         	_dnd.atoms[19]
#define XG_MIME_PLAIN    	_dnd.atoms[20]
#define XG_MIME_URI      	_dnd.atoms[21]
#define XG_MIME_PS      	_dnd.atoms[22]
#define XG_MIME_TSV      	_dnd.atoms[23]
#define XG_MIME_RICHTEXT  _dnd.atoms[24]
#define XG_MIME_TIFF      _dnd.atoms[25]
#define XG_MIME_OCTET     _dnd.atoms[26]
#define XG_MIME_ROOTWINDOW _dnd.atoms[27]
#define XG_MIME_APP_RICHTEXT _dnd.atoms[28]
#define XG_MIME_RTF       _dnd.atoms[29]
#define XG_MIME_HTML      _dnd.atoms[30]
#define XG_MIME_XHTML     _dnd.atoms[31]
#define XG_MIME_PNG       _dnd.atoms[32]
#define XG_MIME_SVG       _dnd.atoms[33]
#define XG_MIME_APP_RTF   _dnd.atoms[34]
#define XG_MIME_TEXT_RICHTEXT _dnd.atoms[35]

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
      typelist[i] = XInternAtom(xDisplay, [mime cString], False); // False - to create the atom
    }
  typelist[count] = 0;

  return typelist;
}

// FIXME: code duplication
static inline
NSArray *
pasteboardTypeForMimeType(Display *xDisplay, NSZone *zone, Atom *typelist)
{
  Atom *type = typelist;
  NSMutableArray *newTypes = [[NSMutableArray allocWithZone: zone] init];

  while (*type != None)
    {
      char *s = XGetAtomName(xDisplay, *type);
      
      if (s)
	{
	  [newTypes addObject: [NSPasteboard pasteboardTypeForMimeType: 
	    [NSString stringWithCString: s]]];
	  XFree(s);
	}
      type++;
    }
  
  return AUTORELEASE(newTypes);
}

@implementation XDNDSession

static	XDNDSession	*sharedSession = nil;

+ (id) sharedSession
{
  if (sharedSession == nil)
    {
      sharedSession = [XDNDSession new];
    }

  return sharedSession;
}

- (id)init
{
  if ((self = [super init]) != nil)
    {
      _dnd = xdnd();
      sessionType = -1;
    }

  return self;
}



/**
 *  The method to call on incoming X-events.
 *  Returns NO if the DnD session fails.
 */
- (BOOL)receive:(XEvent *)xEvent
{
    if (xEvent->type == ClientMessage)
      {
	if (xEvent->xclient.message_type == _dnd.XdndEnter)
	  {
	    _dnd.dragger_window = XGetSelectionOwner(_dnd.display, _dnd.XdndSelection);
	    _dnd.dropper_window = ((XAnyEvent *)xEvent)->window;
	    if (_dnd.dragger_window == _dnd.dropper_window)
	      {
		// local DnD
		sessionType = XDND_SESSION_LOCAL;
		NSDebugLLog(@"NSDragging", @"XDND: LOCAL");
	      }
	    else
	      {
		XClassHint dragger;
		XClassHint dropper;
		Status st;

		st = XGetClassHint(_dnd.display, _dnd.dragger_window, &dragger);
		if (st == BadWindow)
		  {
		    NSDebugLLog(@"NSDragging", @"FIXME: ERROR: XGetClassHint for dragger -> BadWindow");
		    return NO;
		  }
		st = XGetClassHint(_dnd.display, _dnd.dropper_window, &dropper);
		if (st == BadWindow)
		  {
		    NSDebugLLog(@"NSDragging", @"FIXME: ERROR: XGetClassHint for dropper -> BadWindow");
		    return NO;
		  }
		if (strcmp(dragger.res_class, dropper.res_class) == 0)
		  {
		    // GS to GS, ignore such drag
		    sessionType = XDND_SESSION_GS_GS;
		    NSDebugLLog(@"NSDragging", @"XDND: GS to GS");
		  }
		else
		  {
		    // GS to X or X to GS
		    const char *gs = "GNUstep";
		    if (strcmp(gs, dropper.res_class) == 0)
		      {
			sessionType = XDND_SESSION_X_GS;
			NSDebugLLog(@"NSDragging", @"XDND: X to GS");
		      }
		    else
		      {
			sessionType = XDND_SESSION_GS_X;
			NSDebugLLog(@"NSDragging", @"XDND: GS to X");
		      }
		  }
		return YES;
	      }
	  }
	else if(xEvent->xclient.message_type == _dnd.XdndPosition)
	  {
	    if (sessionType > XDND_SESSION_GS_GS)
	      {
		if (xEvent->xclient.message_type == _dnd.XdndPosition)
		  {
		    static int to_rm_count = 0;

		    _dnd.time = XDND_POSITION_TIME(xEvent);
		    to_rm_count++;
		    if (to_rm_count % 30 == 0)
		      {
			NSDebugLLog(@"NSDragging", @"XDND: Position");
		      }
		    return YES;
		  }
	      }
	    else
	      {
		// ignore local and GS to GS dragging... gpbs' responsibility
	      }

	  }
	else if (xEvent->xclient.message_type == _dnd.XdndDrop)
	  {
	    if (sessionType == XDND_SESSION_X_GS)
	      {
		NSDebugLLog(@"NSDragging", @"XDND: XdndDrop received");
		[NSTimer scheduledTimerWithTimeInterval:0.0
						 target:self
					       selector:@selector(timer:)
					       userInfo:nil
						repeats:NO];
		return YES;
	      }
	    else
	      {
		// GS to GS
		NSDebugLLog(@"NSDragging", @"Ignore");
	      }
	  }
	else if (xEvent->xclient.message_type == _dnd.XdndStatus)
	  {
	    if (sessionType == XDND_SESSION_GS_X)
	      {
		// X-target infroms us
		NSDebugLLog(@"NSDragging", @"X-target informs us");
		return YES;
	      }
	    else
	      {
		// GS to GS 
		NSDebugLLog(@"NSDragging", @"Ignore");
	      }
	  }
      }
  else if (xEvent->type == SelectionNotify)
    {
      if (xEvent->xselection.requestor == _dnd.dropper_window)
	{
	  if (xEvent->xselection.property == None)
	    {
	      return NO;
	    }
	  NSDebugLLog(@"NSDragging", @"XDND: SelectionNotify received");
	  // trigger dropping
	  _dnd.stage = XDND_DROP_STAGE_ENTERED;
	  _dnd.property = xEvent->xselection.property;
	  return YES;
	}
    }
  else if (xEvent->type == SelectionRequest)
    {
      NSPasteboard *pb = [NSPasteboard pasteboardWithName: NSDragPboard];
      NSArray *types = [pb types];
      NSData *data = nil;
      Atom xType = xEvent->xselectionrequest.target;

      if (((xType == XG_UTF8_STRING) || 
	   (xType == XA_STRING) || 
	   (xType == XG_TEXT)) &&
	  [types containsObject: NSStringPboardType])
	{
	  NSString *s = [pb stringForType: NSStringPboardType];

	  if (xType == XG_UTF8_STRING)
	    {
	      data = [s dataUsingEncoding: NSUTF8StringEncoding];
	    }
	  else if ((xType == XA_STRING) || (xType == XG_TEXT))
	    {
	      data = [s dataUsingEncoding: NSISOLatin1StringEncoding];
	    }
	}
      // FIXME: Add support for more types. See: xpbs.m

      if (data != nil)
	{
	  // Send the data to the other process
	  xdnd_selection_send(&_dnd, &(xEvent->xselectionrequest), 
			      (unsigned char *)[data bytes], [data length]);        
	}

      return YES;

    }
  else
    {
      NSDebugLLog(@"NSDragging", @"FIXME: ERROR");
    }

  [self reset];

  return NO;
}

- (void)timer:(id)arg
{
  NSDebugLLog(@"NSDragging", @"auxilliary timer");
}

#define FULL_LENGTH 8192L	/* Amount to read */
- (NSMutableData*) _getSelectionDataOfType: (Atom*)type
{
  int		status;
  unsigned char	*data;
  long          long_offset = 0L;
  long          long_length = FULL_LENGTH;
  Atom          req_type = AnyPropertyType;
  Atom          actual_type;
  int		actual_format;
  unsigned long	bytes_remaining;
  unsigned long	number_items;
  NSMutableData	*md = nil;

  /*
   * Read data from property identified in SelectionNotify event.
   */
  do
    {
      status = XGetWindowProperty(_dnd.display,
                                  _dnd.dropper_window,
                                  _dnd.property,
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
                  char *req_name = XGetAtomName(_dnd.display, req_type);
                  char *act_name = XGetAtomName(_dnd.display, actual_type);

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

/**
 *  Supply the pasteboard with the data for the type.
 */
- (void)pasteboard:(NSPasteboard *)pb provideDataForType:(NSString *)type
{
  NSDate          *timeoutDate;
  Atom                  *tlist;
  Atom             actual_type;
  NSMutableData	     *md = nil;
  id               runLoopMode;
  int                      ret;

  _dnd.stage = XDND_DROP_STAGE_CONVERTING;

  NSDebugLLog(@"NSDragging", @"XDND: drop start");

  tlist = mimeTypeForPasteboardType (_dnd.display, [self zone], [NSArray arrayWithObject: type]);
  ret = xdnd_convert_selection(&_dnd,
			       _dnd.dragger_window, // owner
			       _dnd.dropper_window, // requestor
			       tlist[0]);       // type
  NSZoneFree([self zone], tlist);
  tlist = NULL;

  if (ret != 0)
    {
      [pb setData: nil forType: type];
      return;
    }

  // now wait for SelectionNotify
  NSDebugLLog(@"NSDragging", @"XDND: waiting for SelectionNotify");
  
  timeoutDate = [NSDate dateWithTimeIntervalSinceNow: 1.0];
  runLoopMode = [[NSRunLoop currentRunLoop] currentMode];
  while (_dnd.stage != XDND_DROP_STAGE_ENTERED &&
	 [timeoutDate timeIntervalSinceNow] > 0.0)
    {
      [[NSRunLoop currentRunLoop]
		       runMode: runLoopMode
		    beforeDate: timeoutDate];
    }

  NSDebugLLog(@"NSDragging", @"XDND: reading data");

  if (_dnd.stage == XDND_DROP_STAGE_ENTERED)
    {
      md = [self _getSelectionDataOfType: &actual_type];

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
		  XNextEvent(_dnd.display, &event);

		  if (event.type == PropertyNotify)
		    {
		      if (event.xproperty.state != PropertyNewValue) continue;

		      imd = [self _getSelectionDataOfType: &actual_type];
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
	      char *name = XGetAtomName(_dnd.display, actual_type);

	      NSDebugLLog(@"NSDragging", @"Unsupported data type '%s' from X selection.", 
			  name);
	      XFree(name);
	    }
	}
    }
  else
    {
      NSDebugLLog(@"NSDragging", @"DnD is canceled by timeout");
      [self reset];
    }
}

/**
 *  Reset the current DnD session.
 */
- (void)reset
{
  _dnd.stage = XDND_DROP_STAGE_IDLE;
  _dnd.dragger_window = None;
  _dnd.dropper_window = None;
  _dnd.time = CurrentTime;
  _dnd.property = None;
  sessionType = XDND_SESSION_NONE;
}

/*
 * Produces the pasteboard types available for DnD
 * from the source/dragger window.
 */
- (NSArray*) availableTypesFromXDragger
{
  if ([self isXDragger])
    {
      // types via X
      Atom *types;
      NSArray *newTypes;

      if (_dnd.dragger_window == None)
	return nil;

      xdnd_get_type_list(&_dnd, _dnd.dragger_window, &types);
      newTypes = pasteboardTypeForMimeType(_dnd.display, [self zone], types);
      free(types);
      return newTypes;
    }
  else
    {
      // types via GNUstep
    }

  return nil;
}

/**
 *  Whether the dragger(source) is X-app, not GNUstep one.
 */
- (BOOL)isXDragger
{
  return sessionType == XDND_SESSION_X_GS;
}

@end
