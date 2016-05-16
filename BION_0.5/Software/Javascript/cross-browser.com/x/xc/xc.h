/*-----------------------------------------------------------------------------
 xc.h
 X Library Compiler
 Copyright 2004-2007 Michael Foster (Cross-Browser.com)
 Distributed under the terms of the GNU LGPL
-----------------------------------------------------------------------------*/

// Includes

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <ctype.h>
#include <io.h>
#include <search.h>

// Constants

#define XC_VER "1.06"
#define X_VER_FILE "xlibrary.js"
#define XC_HDR_STR "\nX Library Compiler %s\nDistributed under the terms of the GNU LGPL\n"
#define X_HDR_STR "/* Compiled from X %s by XC %s on %s */\n"
#define SA_HDR_STR "/* Compiled by XC %s on %s */\n"
#define HELP_STR "\nUsage 1 (X Library Mode): xc prj_name[.ext]\n\nUsage 2 (Standalone Mode): xc output_file input_file1 input_file2 input_file3 ...\n\nFor more information visit Cross-Browser.com.\n"

#define bool unsigned char
#define true 1
#define false 0

#define MAX_SYMBOLS 300
#define MAX_NAME_LEN 100
#define INVALID 0xFFFF
#define MAX_LINE_LEN 2000
#define MAX_PATH_LEN 250
#define MAX_APP_FILES MAX_SYMBOLS
#define XML_FILE_MASK "*.xml"
#define LIB_EXT ".js"
#define PRJ_EXT ".xcp"
#define LOG_EXT ".log"
#define OBF_PREFIX 'X'
#define OBJ_PREFIX "X"
#define XML_ROOT "<x_symbol"

// end xc.h
