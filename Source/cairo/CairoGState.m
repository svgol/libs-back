/*
 * CairoGState.m

 * Copyright (C) 2003 Free Software Foundation, Inc.
 * August 31, 2003
 * Written by Banlu Kemiyatorn <object at gmail dot com>
 * Rewrite: Fred Kiefer <fredkiefer@gmx.de>
 * Date: Jan 2006
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.

 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.

 * You should have received a copy of the GNU Library General Public
 * License along with this library; if not, write to the Free
 * Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02111 USA.
 */

#include <AppKit/NSAffineTransform.h>
#include <AppKit/NSBezierPath.h>
#include <AppKit/NSColor.h>
#include <AppKit/NSGraphics.h>
#include "cairo/CairoGState.h"
#include "cairo/CairoFontInfo.h"
#include "cairo/CairoSurface.h"
#include "cairo/CairoContext.h"
#include <math.h>


// Macro stolen from base/Header/Additions/GNUstepBase/GSObjRuntime.h
#ifndef	GS_MAX_OBJECTS_FROM_STACK
/**
 * The number of objects to try to get from varargs into an array on
 * the stack ... if there are more than this, use the heap.
 * NB. This MUST be a multiple of 2
 */
#define	GS_MAX_OBJECTS_FROM_STACK	128
#endif

// Macros stolen from base/Source/GSPrivate.h
/**
 * Macro to manage memory for chunks of code that need to work with
 * arrays of items.  Use this to start the block of code using
 * the array and GS_ENDITEMBUF() to end it.  The idea is to ensure that small
 * arrays are allocated on the stack (for speed), but large arrays are
 * allocated from the heap (to avoid stack overflow).
 */
#define	GS_BEGINITEMBUF(P, S, T) { \
  T _ibuf[(S) <= GS_MAX_OBJECTS_FROM_STACK ? (S) : 0]; \
  T *_base = ((S) <= GS_MAX_OBJECTS_FROM_STACK) ? _ibuf \
    : (T*)NSZoneMalloc(NSDefaultMallocZone(), (S) * sizeof(T)); \
  T *(P) = _base;

/**
 * Macro to manage memory for chunks of code that need to work with
 * arrays of items.  Use GS_BEGINITEMBUF() to start the block of code using
 * the array and this macro to end it.
 */
#define	GS_ENDITEMBUF() \
  if (_base != _ibuf) \
    NSZoneFree(NSDefaultMallocZone(), _base); \
  }

@implementation CairoGState 

+ (void) initialize
{
  if (self == [CairoGState class])
    {
    }
}

- (void) dealloc
{
  if (_ct)
    {
      cairo_destroy(_ct);
    }
  RELEASE(_surface);

  [super dealloc];
}

- (id) copyWithZone: (NSZone *)zone
{
  CairoGState *copy = (CairoGState *)[super copyWithZone: zone];

  if (_ct)
    {
      cairo_path_t *cpath;
      cairo_status_t status;
      cairo_matrix_t local_matrix;
 
      // FIXME: Need some way to do a copy
      //cairo_copy(copy->_ct, _ct);
      copy->_ct = cairo_create(cairo_get_target(_ct));
      cairo_get_matrix(_ct, &local_matrix);
      cairo_set_matrix(copy->_ct, &local_matrix);
      cpath = cairo_copy_path(_ct);
      cairo_append_path(copy->_ct, cpath);
      cairo_path_destroy(cpath);
      
      cairo_set_operator(copy->_ct, cairo_get_operator(_ct));
      cairo_set_source(copy->_ct, cairo_get_source(_ct));
      cairo_set_tolerance(copy->_ct, cairo_get_tolerance(_ct));
      cairo_set_antialias(copy->_ct, cairo_get_antialias(_ct));
      cairo_set_line_width(copy->_ct, cairo_get_line_width(_ct));
      cairo_set_line_cap(copy->_ct, cairo_get_line_cap(_ct));
      cairo_set_line_join(copy->_ct, cairo_get_line_join(_ct));
      cairo_set_miter_limit(copy->_ct, cairo_get_miter_limit(_ct));
      // FIXME: In cairo 1.2.4 there is no way get the dash or copy it.
      // There also is no way to get the current clipping path
 
      status = cairo_status(copy->_ct);
      if (status != CAIRO_STATUS_SUCCESS)
        {
          NSLog(@"Cairo status %s in copy", cairo_status_to_string(status));
        }
    }

  RETAIN(_surface);

  return copy;
}

- (void) GSCurrentSurface: (CairoSurface **)surface: (int *)x : (int *)y
{
  if (x)
    *x = offset.x;
  if (y)
    *y = offset.y;
  if (surface)
    {
      *surface = _surface;
    }
}

- (void) GSSetSurface: (CairoSurface *)surface : (int)x : (int)y
{
  ASSIGN(_surface, surface);
  [self setOffset: NSMakePoint(x, y)];
  [self DPSinitgraphics];
}

- (void) setOffset: (NSPoint)theOffset
{
  if (_surface != nil)
    {
      NSSize size = [_surface size];

      cairo_surface_set_device_offset([_surface surface], -theOffset.x, 
                                      theOffset.y - size.height);
    }
  [super setOffset: theOffset];
}

- (void) DPSgrestore
{
  if (_ct)
    {
      cairo_restore(_ct);
      if (cairo_status(_ct) == CAIRO_STATUS_INVALID_RESTORE)
        {
        // Restore failed because there was no more state on the stack
        }
    }
}

- (void) DPSgsave
{
  if (_ct)
    {
      cairo_save(_ct);
    }
}

- (void) showPage
{
  if (_ct)
    {
      cairo_show_page(_ct);
    }
}

- (void) setSize: (NSSize)size
{
   if (_surface)
    {
      [_surface setSize: size];
    }
}

/*
 * Color operations
 */
- (void) setColor: (device_color_t *)color state: (color_state_t)cState
{
  device_color_t c;

  [super setColor: color state: cState];
  if (_ct == NULL)
    {
      // Window device isn't set yet
      return;
    }
  c = fillColor;
  gsColorToRGB(&c);
  // The underlying concept does not allow to determine if alpha is set or not.
  cairo_set_source_rgba(_ct, c.field[0], c.field[1], c.field[2], c.field[AINDEX]);
}

- (void) GSSetPatterColor: (NSImage*)image 
{
  // FIXME: Create a cairo surface from the image and set it as source.
  [super GSSetPatterColor: image];
}

/*
 * Text operations
 */

- (void) _setPoint
{
  NSPoint p;

  p = [path currentPoint];
  cairo_move_to(_ct, p.x, p.y);
}

- (void) DPScharpath: (const char *)s : (int)b
{
  if (_ct)
    {
      GS_BEGINITEMBUF(c, b + 1, char);

      [self _setPoint];
      memcpy(c, s, b);
      c[b] = 0;
      cairo_text_path(_ct, c);
      GS_ENDITEMBUF();
    }
}

- (void) DPSshow: (const char *)s
{
  if (_ct)
    {
      cairo_matrix_t saved_matrix;
      cairo_matrix_t local_matrix;
      NSPoint        p = [path currentPoint];

      cairo_get_matrix(_ct, &saved_matrix);

      cairo_matrix_init_scale(&local_matrix, 1, 1);
      cairo_matrix_translate(&local_matrix, 0, [_surface size].height-(p.y*2));
      cairo_set_matrix(_ct, &local_matrix);

      cairo_move_to(_ct, p.x, p.y);
      cairo_show_text(_ct, s);

      cairo_set_matrix(_ct, &saved_matrix);
    }
}

- (void) GSSetFont: (GSFontInfo *)fontref
{
  cairo_matrix_t font_matrix;
  const float *matrix; 

  [super GSSetFont: fontref];

  if (_ct)
    {
      matrix = [font matrix];
      cairo_set_font_face(_ct, [((CairoFontInfo *)font)->_faceInfo fontFace]);
      cairo_matrix_init(&font_matrix, matrix[0], matrix[1], matrix[2],
			matrix[3], matrix[4], matrix[5]);
      cairo_set_font_matrix(_ct, &font_matrix);
    }
}

- (void) GSSetFontSize: (float)size
{
  if (_ct)
    {
      cairo_set_font_size(_ct, size);
    }
}

- (void) GSShowText: (const char *)string : (size_t)length
{
  if (_ct)
    {
      GS_BEGINITEMBUF(c, length + 1, char);

      [self _setPoint];
      memcpy(c, string, length);
      c[length] = 0;
      cairo_show_text(_ct, c);
      GS_ENDITEMBUF();
    }
}

- (void) GSShowGlyphs: (const NSGlyph *)glyphs : (size_t)length
{
  if (_ct)
    {
      cairo_matrix_t local_matrix;
      NSAffineTransformStruct	matrix = [ctm transformStruct];

      [self _setPoint];
      // FIXME: Hack to get font in rotated view working
      cairo_save(_ct);
      cairo_matrix_init(&local_matrix, matrix.m11, matrix.m12, matrix.m21,
                        matrix.m22, 0, 0);
      cairo_transform(_ct, &local_matrix);
      // Undo the 
      cairo_matrix_init_scale(&local_matrix, 1, -1);
      cairo_matrix_translate(&local_matrix, 0,  -[_surface size].height);
      cairo_transform(_ct, &local_matrix);

      [(CairoFontInfo *)font drawGlyphs: glyphs
			length: length
			on: _ct];
      cairo_restore(_ct);
    }
}

/*
 * GState operations
 */

- (void) DPSinitgraphics
{
  cairo_status_t status;
  cairo_matrix_t local_matrix;

  [super DPSinitgraphics];

  if (_ct)
    {
      cairo_destroy(_ct);
    }
  if (!_surface)
    {
      return;
    }
  _ct = cairo_create([_surface surface]);
  status = cairo_status(_ct);
  if (status != CAIRO_STATUS_SUCCESS)
    {
      NSLog(@"Cairo status %s in DPSinitgraphics", cairo_status_to_string(status));
      _ct = NULL;
      return;
    }
  
  // cairo draws the other way around.
  // At this point in time viewIsFlipped has not been set, but it is
  // OK to ignore this here, as in that case the matrix will later 
  // get flipped by GUI,
  cairo_matrix_init_scale(&local_matrix, 1, -1);
  cairo_matrix_translate(&local_matrix, 0,  -[_surface size].height);
  cairo_set_matrix(_ct, &local_matrix);

  // super call did go to the old _ct, so redo it
  [self setColor: &fillColor state: COLOR_BOTH];

  // Cairo's default line width is 2.0
  cairo_set_line_width(_ct, 1.0);
  cairo_set_operator(_ct, CAIRO_OPERATOR_OVER);
  cairo_new_path(_ct);
}

- (void) DPScurrentflat: (float *)flatness
{
  if (_ct)
    {
      *flatness = cairo_get_tolerance(_ct);
    }
}

- (void) DPScurrentlinecap: (int *)linecap
{
  cairo_line_cap_t lc;

  if (_ct)
    {
      lc = cairo_get_line_cap(_ct);
      *linecap = lc;
    }
  /*
     switch (lc)
     {
     case CAIRO_LINE_CAP_BUTT:
     *linecap = 0;
     break;
     case CAIRO_LINE_CAP_ROUND:
     *linecap = 1;
     break;
     case CAIRO_LINE_CAP_SQUARE:
     *linecap = 2;
     break;
     default:
     NSLog(@"ERROR Line cap unknown");
     exit(-1);
     }
   */
}

- (void) DPScurrentlinejoin: (int *)linejoin
{
  cairo_line_join_t lj;

  if (_ct)
    {
      lj = cairo_get_line_join(_ct);
      *linejoin = lj;
    }
  /*
     switch (lj)
     {
     case CAIRO_LINE_JOIN_MITER:
     *linejoin = 0;
     break;
     case CAIRO_LINE_JOIN_ROUND:
     *linejoin = 1;
     break;
     case CAIRO_LINE_JOIN_BEVEL:
     *linejoin = 2;
     break;
     default:
     NSLog(@"ERROR Line join unknown");
     exit(-1);
     }
   */
}

- (void) DPScurrentlinewidth: (float *)width
{
  if (_ct)
    {
      *width = cairo_get_line_width(_ct);
    }
}

- (void) DPScurrentmiterlimit: (float *)limit
{
  if (_ct)
    {
      *limit = cairo_get_miter_limit(_ct);
    }
}

- (void) DPScurrentstrokeadjust: (int *)b
{
    // FIXME
}

- (void) DPSsetdash: (const float *)pat : (int)size : (float)foffset
{
  if (_ct)
    {
      GS_BEGINITEMBUF(dpat, size, double);
      double doffset = foffset;
      int i;

      i = size;
      while (i)
        {
          i--;
          dpat[i] = pat[i];
        }
      // FIXME: There may be a difference in concept as some dashes look wrong
      cairo_set_dash(_ct, dpat, size, doffset);
      GS_ENDITEMBUF();
    }
}

- (void) DPSsetflat: (float)flatness
{
  [super DPSsetflat: flatness];
  if (_ct)
    {
      cairo_set_tolerance(_ct, flatness);
    }
}

- (void) DPSsetlinecap: (int)linecap
{
  if (_ct)
    {
      cairo_set_line_cap(_ct, (cairo_line_cap_t)linecap);
    }
}

- (void) DPSsetlinejoin: (int)linejoin
{
  if (_ct)
    {
      cairo_set_line_join(_ct, (cairo_line_join_t)linejoin);
    }
}

- (void) DPSsetlinewidth: (float)width
{
  if (_ct)
    {
      cairo_set_line_width(_ct, width);
    }
}

- (void) DPSsetmiterlimit: (float)limit
{
  if (_ct)
    {
      cairo_set_miter_limit(_ct, limit);
    }
}

- (void) DPSsetstrokeadjust: (int)b
{
    // FIXME
}

/*
 * Path operations
 */

- (void) _setPath
{
  unsigned count = [path elementCount];
  unsigned i;
  SEL elmsel = @selector(elementAtIndex:associatedPoints:);
  IMP elmidx = [path methodForSelector: elmsel];

  for (i = 0; i < count; i++) 
    {
      NSBezierPathElement type;
      NSPoint points[3];

      type = (NSBezierPathElement)(*elmidx)(path, elmsel, i, points);
      switch(type) 
        {
          case NSMoveToBezierPathElement:
            cairo_move_to(_ct, points[0].x, points[0].y);
            break;
          case NSLineToBezierPathElement:
            cairo_line_to(_ct, points[0].x, points[0].y);
            break;
          case NSCurveToBezierPathElement:
            cairo_curve_to(_ct, points[0].x, points[0].y, 
                           points[1].x, points[1].y, 
                           points[2].x, points[2].y);
            break;
          case NSClosePathBezierPathElement:
            cairo_close_path(_ct);
            break;
          default:
            break;
        }
    }
}

- (void) DPSclip
{
  if (_ct)
    {
      [self _setPath];
      cairo_clip(_ct);
    }
}

- (void) DPSeoclip
{
  if (_ct)
    {
      [self _setPath];
      cairo_set_fill_rule(_ct, CAIRO_FILL_RULE_EVEN_ODD);
      cairo_clip(_ct);
      cairo_set_fill_rule(_ct, CAIRO_FILL_RULE_WINDING);
    }
}

- (void) DPSeofill
{
  if (_ct)
    {
      [self _setPath];
      cairo_set_fill_rule(_ct, CAIRO_FILL_RULE_EVEN_ODD);
      cairo_fill(_ct);
      cairo_set_fill_rule(_ct, CAIRO_FILL_RULE_WINDING);
    }
}

- (void) DPSfill
{
  if (_ct)
    {
      [self _setPath];
      cairo_fill(_ct);
    }
}

- (void) DPSinitclip
{
  if (_ct)
    {
      cairo_reset_clip(_ct);
    }
}

- (void) DPSstroke
{
  if (_ct)
    {
      [self _setPath];
      cairo_stroke(_ct);
    }
}

- (NSDictionary *) GSReadRect: (NSRect)r
{
  NSMutableDictionary *dict;
  NSSize ssize;
  NSAffineTransform *matrix;
  double x, y;
  int ix, iy;
  cairo_format_t format = CAIRO_FORMAT_ARGB32;
  cairo_surface_t *surface;
  cairo_surface_t *isurface;
  cairo_t *ct;
  int size;
  int i;
  NSMutableData *data;
  unsigned char *cdata;

  if (!_ct)
    {
      return nil;
    }

  r = [ctm rectInMatrixSpace: r];
  x = NSWidth(r);
  y = NSHeight(r);
  ix = abs(floor(x));
  iy = abs(floor(y));
  ssize = NSMakeSize(ix, iy);

  dict = [NSMutableDictionary dictionary];
  [dict setObject: [NSValue valueWithSize: ssize] forKey: @"Size"];
  [dict setObject: NSDeviceRGBColorSpace forKey: @"ColorSpace"];
  
  [dict setObject: [NSNumber numberWithUnsignedInt: 8] forKey: @"BitsPerSample"];
  [dict setObject: [NSNumber numberWithUnsignedInt: 32]
	forKey: @"Depth"];
  [dict setObject: [NSNumber numberWithUnsignedInt: 4] 
	forKey: @"SamplesPerPixel"];
  [dict setObject: [NSNumber numberWithUnsignedInt: 1]
	forKey: @"HasAlpha"];

  matrix = [self GSCurrentCTM];
  [matrix translateXBy: -r.origin.x - offset.x 
	  yBy: r.origin.y + NSHeight(r) - offset.y];
  [dict setObject: matrix forKey: @"Matrix"];

  size = ix*iy*4;
  data = [NSMutableData dataWithLength: size];
  if (data == nil)
    return nil;
  cdata = [data mutableBytes];

  surface = cairo_get_target(_ct);
  isurface = cairo_image_surface_create_for_data(cdata, format, ix, iy, 4*ix);
  ct = cairo_create(isurface);

  if (_surface != nil)
    {
      ssize = [_surface size];
    }
  else 
    {
      ssize = NSMakeSize(0, 0);
    }
  cairo_set_source_surface(ct, surface, -r.origin.x, -ssize.height + r.size.height + r.origin.y);
  cairo_rectangle(ct, 0, 0, ix, iy);
  cairo_paint(ct);
  cairo_destroy(ct);
  cairo_surface_destroy(isurface);

  for (i = 0; i < 4 * ix * iy; i += 4)
    {
      unsigned char d = cdata[i];

#if GS_WORDS_BIGENDIAN
      cdata[i] = cdata[i + 1];
      cdata[i + 1] = cdata[i + 2];
      cdata[i + 2] = cdata[i + 3];
      cdata[i + 3] = d;
#else
      cdata[i] = cdata[i + 2];
      //cdata[i + 1] = cdata[i + 1];
      cdata[i + 2] = d;
      //cdata[i + 3] = cdata[i + 3];
#endif 
    }

  [dict setObject: data forKey: @"Data"];

  return dict;
}

static void
_set_op(cairo_t *ct, NSCompositingOperation op)
{
  switch (op)
    {
    case NSCompositeClear:
      cairo_set_operator(ct, CAIRO_OPERATOR_CLEAR);
      break;
    case NSCompositeCopy:
      cairo_set_operator(ct, CAIRO_OPERATOR_SOURCE);
      break;
    case NSCompositeSourceOver:
      cairo_set_operator(ct, CAIRO_OPERATOR_OVER);
      break;
    case NSCompositeSourceIn:
      cairo_set_operator(ct, CAIRO_OPERATOR_IN);
      break;
    case NSCompositeSourceOut:
      cairo_set_operator(ct, CAIRO_OPERATOR_OUT);
      break;
    case NSCompositeSourceAtop:
      cairo_set_operator(ct, CAIRO_OPERATOR_ATOP);
      break;
    case NSCompositeDestinationOver:
      cairo_set_operator(ct, CAIRO_OPERATOR_DEST_OVER);
      break;
    case NSCompositeDestinationIn:
      cairo_set_operator(ct, CAIRO_OPERATOR_DEST_IN);
      break;
    case NSCompositeDestinationOut:
      cairo_set_operator(ct, CAIRO_OPERATOR_DEST_OUT);
      break;
    case NSCompositeDestinationAtop:
      cairo_set_operator(ct, CAIRO_OPERATOR_DEST_ATOP);
      break;
    case NSCompositeXOR:
      cairo_set_operator(ct, CAIRO_OPERATOR_XOR);
      break;
    case NSCompositePlusDarker:
      // FIXME: There is no match for this operation in cairo!!!
      cairo_set_operator(ct, CAIRO_OPERATOR_SATURATE);
      break;
    case NSCompositeHighlight:
      // MacOSX 10.4 documentation maps this value onto NSCompositeSourceOver
      cairo_set_operator(ct, CAIRO_OPERATOR_OVER);
      break;
    case NSCompositePlusLighter:
      cairo_set_operator(ct, CAIRO_OPERATOR_ADD);
      break;
    default:
      cairo_set_operator(ct, CAIRO_OPERATOR_SOURCE);
    }
}

- (void) DPSimage: (NSAffineTransform *)matrix : (int)pixelsWide
		 : (int)pixelsHigh : (int)bitsPerSample 
		 : (int)samplesPerPixel : (int)bitsPerPixel
		 : (int)bytesPerRow : (BOOL)isPlanar
		 : (BOOL)hasAlpha : (NSString *)colorSpaceName
		 : (const unsigned char *const[5])data
{
  cairo_format_t format;
  NSAffineTransformStruct tstruct;
  cairo_surface_t *surface;
  unsigned char	*tmp = NULL;
  int i = 0;
  int j;
  int index;
  unsigned int pixels = pixelsHigh * pixelsWide;
  unsigned char *rowData;
  cairo_matrix_t local_matrix;

  if (!_ct)
    {
	return;
    }

  if (isPlanar || !([colorSpaceName isEqualToString: NSDeviceRGBColorSpace] ||
		    [colorSpaceName isEqualToString: NSCalibratedRGBColorSpace]))
    {
      // FIXME: Need to conmvert to something that is supported
      NSLog(@"Image format not support in cairo backend.\n colour space: %@ planar %d", colorSpaceName, isPlanar);
      return;
    }

  // default is 8 bit grayscale 
  if (!bitsPerSample)
    bitsPerSample = 8;
  if (!samplesPerPixel)
    samplesPerPixel = 1;

  // FIXME - does this work if we are passed a planar image but no hints ?
  if (!bitsPerPixel)
    bitsPerPixel = bitsPerSample * samplesPerPixel;
  if (!bytesPerRow)
    bytesPerRow = (bitsPerPixel * pixelsWide) / 8;

  /* make sure its sane - also handles row padding if hint missing */
  while ((bytesPerRow * 8) < (bitsPerPixel * pixelsWide))
    bytesPerRow++;

  switch (bitsPerPixel)
    {
    case 32:
      rowData = (unsigned char *)data[0];
      tmp = objc_malloc(pixels * 4);
      index = 0;

      for (i = 0; i < pixelsHigh; i++)
        {
          unsigned char *d = rowData;

          for (j = 0; j < pixelsWide; j++)
            {
#if GS_WORDS_BIGENDIAN
              tmp[index++] = d[3];
              tmp[index++] = d[0];
              tmp[index++] = d[1];
              tmp[index++] = d[2];
#else
              tmp[index++] = d[2];
              tmp[index++] = d[1];
              tmp[index++] = d[0];
              tmp[index++] = d[3];
#endif 
              d += 4;
            }
          rowData += bytesPerRow;
        }
      format = CAIRO_FORMAT_ARGB32;
      break;
    case 24:
      rowData = (unsigned char *)data[0];
      tmp = objc_malloc(pixels * 4);
      index = 0;

      for (i = 0; i < pixelsHigh; i++)
        {
          unsigned char *d = rowData;

          for (j = 0; j < pixelsWide; j++)
            {
#if GS_WORDS_BIGENDIAN
              tmp[index++] = 0;
              tmp[index++] = d[0];
              tmp[index++] = d[1];
              tmp[index++] = d[2];
#else
              tmp[index++] = d[2];
              tmp[index++] = d[1];
              tmp[index++] = d[0];
              tmp[index++] = 0;
#endif
              d += 3;
            }
          rowData += bytesPerRow;
        }
      format = CAIRO_FORMAT_RGB24;
      break;
    default:
      NSLog(@"Image format not support");
      return;
    }

  surface = cairo_image_surface_create_for_data((void*)tmp,
						format,
						pixelsWide,
						pixelsHigh,
						pixelsWide * 4);

  if (cairo_surface_status(surface))
    {
      NSLog(@"Image surface could not be created");
      if (tmp)
        {
          objc_free(tmp);
        }

      return;
    }

  cairo_save(_ct);
  cairo_set_operator(_ct, CAIRO_OPERATOR_SOURCE);

  // Set the basic transformation
  tstruct =  [ctm transformStruct];
  cairo_matrix_init(&local_matrix,
		    tstruct.m11, tstruct.m12,
		    tstruct.m21, tstruct.m22, 
		    tstruct.tX, tstruct.tY);
  cairo_transform(_ct, &local_matrix);

  // add the local tranformation
  tstruct = [matrix transformStruct];
  cairo_matrix_init(&local_matrix,
		    tstruct.m11, tstruct.m12,
		    tstruct.m21, tstruct.m22, 
		    tstruct.tX, tstruct.tY);
  cairo_transform(_ct, &local_matrix);

  // Make up for flip done in GUI
  if (viewIsFlipped)
    {
      cairo_pattern_t *cpattern;
      cairo_matrix_t local_matrix;
      
      cpattern = cairo_pattern_create_for_surface(surface);
      cairo_matrix_init_scale(&local_matrix, 1, -1);
      cairo_matrix_translate(&local_matrix, 0, -2*pixelsHigh);
      cairo_pattern_set_matrix(cpattern, &local_matrix);
      cairo_set_source(_ct, cpattern);
      cairo_pattern_destroy(cpattern);

      cairo_rectangle(_ct, 0, pixelsHigh, pixelsWide, pixelsHigh);
    }
  else 
    {
      cairo_pattern_t *cpattern;
      cairo_matrix_t local_matrix;
      
      cpattern = cairo_pattern_create_for_surface(surface);
      cairo_matrix_init_scale(&local_matrix, 1, -1);
      cairo_matrix_translate(&local_matrix, 0, -pixelsHigh);
      cairo_pattern_set_matrix(cpattern, &local_matrix);
      cairo_set_source(_ct, cpattern);
      cairo_pattern_destroy(cpattern);

      cairo_rectangle(_ct, 0, 0, pixelsWide, pixelsHigh);
    }
  cairo_clip(_ct);
  cairo_paint(_ct);
  cairo_surface_destroy(surface);
  cairo_restore(_ct);

  if (tmp)
    {
      objc_free(tmp);
    }
}

- (void) compositerect: (NSRect)aRect op: (NSCompositingOperation)op
{
  if (_ct)
    {
      NSBezierPath *oldPath = path;

      cairo_save(_ct);
      _set_op(_ct, op);

      // This is almost a rectclip::::, but the path stays unchanged.
      path = [NSBezierPath bezierPathWithRect: aRect];
      [path transformUsingAffineTransform: ctm];
      [self _setPath];
      cairo_clip(_ct);
      cairo_paint(_ct);
      cairo_restore(_ct);
      path = oldPath;
    }
}

- (void) compositeGState: (CairoGState *)source 
                fromRect: (NSRect)aRect 
                 toPoint: (NSPoint)aPoint 
                      op: (NSCompositingOperation)op
                fraction: (float)delta
{
  cairo_surface_t *src;
  double minx, miny;
  double width, height;
  double x, y;
  NSSize ssize;
  cairo_pattern_t *cpattern;
  cairo_matrix_t local_matrix;

  if (!_ct || !source->_ct)
    {
      return;
    }

  cairo_save(_ct);
  cairo_new_path(_ct);
  _set_op(_ct, op);

  src = cairo_get_target(source->_ct);
  if (src == cairo_get_target(_ct))
    {
/*
      NSRect targetRect;

      targetRect.origin = aPoint;
      targetRect.size = aRect.size;

      if (!NSIsEmptyRect(NSIntersectionRect(aRect, targetRect)))
        {
          NSLog(@"Copy onto self");
          NSLog(NSStringFromRect(aRect));
          NSLog(NSStringFromPoint(aPoint));
          NSLog(@"src %p(%p,%@) des %p(%p,%@)", 
                source,cairo_get_target(source->_ct),NSStringFromSize([source->_surface size]),
                self,cairo_get_target(_ct),NSStringFromSize([_surface size]));
        }
*/
    }

  // Undo flipping in gui
  if (viewIsFlipped)
    {
      aPoint.y -= NSHeight(aRect);
    }
  {
      NSRect newRect;
      
      newRect.origin = aPoint;
      newRect.size = aRect.size;
      [ctm boundingRectFor: newRect result: &newRect];
      aPoint = newRect.origin;
  }
  //aPoint = [ctm transformPoint: aPoint];
  [source->ctm boundingRectFor: aRect result: &aRect];

  x = aPoint.x;
  y = aPoint.y;
  minx = NSMinX(aRect);
  miny = NSMinY(aRect);
  width = NSWidth(aRect);
  height = NSHeight(aRect);

  if (source->_surface != nil)
    {
      ssize = [source->_surface size];
    }
  else 
    {
      ssize = NSMakeSize(0, 0);
    }

  cpattern = cairo_pattern_create_for_surface(src);
  cairo_matrix_init_scale(&local_matrix, 1, -1);
  cairo_matrix_translate(&local_matrix, -x + minx, - ssize.height - y + miny);
  cairo_pattern_set_matrix(cpattern, &local_matrix);
  cairo_set_source(_ct, cpattern);
  cairo_pattern_destroy(cpattern);
  cairo_rectangle(_ct, x, y, width, height);
  cairo_clip(_ct);

  if (delta < 1.0)
    {
      cairo_paint_with_alpha(_ct, delta);
    }
  else
    {
      cairo_paint(_ct);
    }
  cairo_restore(_ct);
}

- (void) compositeGState: (CairoGState *)source 
		fromRect: (NSRect)aRect 
		 toPoint: (NSPoint)aPoint 
		      op: (NSCompositingOperation)op
{
  [self compositeGState: source 
	       fromRect: aRect 
		toPoint: aPoint 
		     op: op
	       fraction: 1.0];
}

- (void) dissolveGState: (CairoGState *)source
	       fromRect: (NSRect)aRect
		toPoint: (NSPoint)aPoint 
		  delta: (float)delta
{
  [self compositeGState: source 
	       fromRect: aRect 
		toPoint: aPoint 
		     op: NSCompositeSourceOver
	       fraction: delta];
}

@end
