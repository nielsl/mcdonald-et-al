/*-----------------------------------------------------------------------------
 xc.c
 X Library Compiler
 Copyright 2004-2007 Michael Foster (Cross-Browser.com)
 Distributed under the terms of the GNU LGPL

v1.06, 23Jun07
v1.05, 1Jun07
v1.04, 20May07, All revision history is now in 'xc_reference.php'.
-----------------------------------------------------------------------------*/

#include "xc.h"

// Global Variables

struct tag_symbol
{
  char id[MAX_NAME_LEN];    // Symbol identifier.
  char src[MAX_NAME_LEN];   // Source file name.
  int dep[MAX_SYMBOLS];     /* An array of dependencies for this symbol,
                               each array element is an index into the symbols array. */
  int dep_len;              // Length of the dep array.
  int inc;                  // Number of times this symbol was found in the app files.
  bool out;                 // Indicates this src file has been written to the output file.
  char type;                // Symbol type, 'V', 'O', 'P', 'M' or 'F'.
};
struct tag_symbol symbols[MAX_SYMBOLS];
int symbols_len = 0;

struct
{
  bool lib;  // true = Generate output file. Default = true.
  bool cmp;  // true = Compression applied to output file. Default = true.
  bool obf;  // true = Obfuscate function names. Default = false. Only valid if +cmp.
  bool obj;  /* true = Prefix function names with object name. Default = false.
                -obj is forced if +obf. Does not require +cmp. */
  bool app;  // true = Compiles application js files to output file. Default = false.
  bool dep;  /* true = Symbol dependents included in output. Default = true.
                When false it is useful for creating a lib file from a list of X symbols.
                I use -dep to create x_core.js, x_event.js, etc. */
  bool log;  // true = Generate log file. Default = false.
  bool dbg;  // true = Debug info in log file. Forces +log. Default = false.
} options;

char x_ver[MAX_NAME_LEN]; // current X version string read from X_VER_FILE
char prj_name[MAX_PATH_LEN]; // The project name (filename without extension).
char prj_ext[MAX_NAME_LEN]; // The project file extension.
char lib_path[MAX_PATH_LEN]; // Path to the X lib files.
char app_files[MAX_APP_FILES][MAX_PATH_LEN]; // Array of app file pathnames.
int app_files_len = 0; // Length of the app_files array.
FILE *log_fp = NULL; // Log file pointer.
char *delimiters = " \n\t,.;:{}()[]=<>?!+-*/%~^|&'\""; // Token delimiters.
char obf_prefix = OBF_PREFIX; // obfuscation prefix
char obj_prefix[MAX_NAME_LEN]; // object prefix
char prev_token[MAX_NAME_LEN]; // the previous token
bool standalone_mode = false; // "compress-only" if true
char out_file[MAX_PATH_LEN]; // output filename

// Function Prototypes

int main(int argc, char *argv[]);
bool read_project_file(char *name);
bool read_version_file();
bool get_valid_symbols();
bool get_symbol_dependents(int sym_idx);
bool get_app_file_symbols(char *fname);
bool create_library();
bool append_to_library(FILE *out_fp, char *name, int sym_idx);
int get_symbol_index(char *token, char sym_type);
void set_dependent(int sym_idx, int dep);
void include_symbol(int idx);
void set_symbol_complete(char *s);
void obfuscate_symbols(char *line);
int objectify_symbols(char *line);
void skip_ws(char **s);
void rtrim(char *s);
void write_final_log();
int stricmp(const char *s1, const char *s2);
char *uitoa(unsigned int value, char *string, int radix);
char *strreplw(char *str, size_t bufsiz, char *oldstr, char *newstr, bool line_start);
int strreplwg(char *str, size_t bufsiz, char *oldstr, char *newstr);
bool count_braces(char *s, bool first_call);
char *strstrw(char *str, char *word, bool line_start);
char *str_tok(char *str, char *del, char *tok_type);
int compare_fn(const void *ele1, const void *ele2);

void init_standalone_mode(int argc, char *argv[]);

// Function Definitions

int main(int argc, char *argv[])
{
  int i;
  char log_name[MAX_PATH_LEN];

  printf(XC_HDR_STR, XC_VER);

  if (argc <= 1)
  {
    printf("\nError: No file name specified on command line.\n");
    printf(HELP_STR);
    return 1;
  }

  // "Standalone" mode. Expects argv[1] to be name of output file
  // and argv[2] (and subsequent args) to be js files to be compressed.

  if (argc >= 3)
  {
    init_standalone_mode(argc, argv);
  }
  else
  {

    // "X Library" mode. Expects argv[1] to be project name with optional extension,
    // and expects it in the current directory.
  
    // Read project file.
  
    if (!read_project_file(argv[1]))
    {
      printf(HELP_STR);           
      return 2;
    }
  
    // Open log file.
  
    if (options.log)
    {
      strcpy(log_name, prj_name);
      strcat(log_name, LOG_EXT);
      if ((log_fp = fopen(log_name, "w")) == NULL)
      {
        printf("\nWarning: Could not open log file: %s\n", log_name);
      }
      else if (log_fp) fprintf(log_fp, XC_HDR_STR, XC_VER);
    }
  
    // Open X_VER_FILE and parse version string.
  
    if (!read_version_file())
    {
      if (log_fp)
      {
        fclose(log_fp);
      }
      return 3;
    }
  
    // Create symbol table.
  
    if (!get_valid_symbols())
    {
      if (log_fp)
      {
        fclose(log_fp);
      }
      return 4;
    }
  
    qsort(symbols, symbols_len, sizeof(struct tag_symbol), compare_fn); // sort the symbols array
  
    // Get symbols used in library files.
  
    if (options.dbg && log_fp) fprintf(log_fp, "\nLib File Dependencies\n");
  
    for (i = 0; i < symbols_len; ++i)
    {
      prev_token[0] = 0;
      if (!get_symbol_dependents(i))
      {
        if (log_fp)
        {
          fclose(log_fp);
        }
        return 5;
      }
    }
  
    // Get symbols used in application files.
  
    if (options.dbg && log_fp) fprintf(log_fp, "\n\nApp File Dependencies\n");
  
    for (i = 0; i < app_files_len; ++i)
    {
      prev_token[0] = 0;
      if (!get_app_file_symbols(app_files[i]))
      {
        if (log_fp)
        {
          fclose(log_fp);
        }
        return 6;
      }
    }
  
    // Force the inclusion of the 'xLibrary' object.
  
    include_symbol(get_symbol_index("xLibrary", 'O'));

  } // end X Library mode

  // Create output library file.

  if (options.lib)
  {
    if (!create_library())
    {
      if (log_fp)
      {
        fclose(log_fp);
      }
      return 7;
    }
  }

  // Report results.

  printf("\ncreated ");
  if (options.lib) printf("%s%s", prj_name, standalone_mode ? "" : LIB_EXT);
  if (options.lib && log_fp) printf(" and ");
  if (log_fp) printf("%s%s", prj_name, LOG_EXT);
  printf("\n");

  if (log_fp)
  {
    write_final_log();
    fclose(log_fp);
  }

  return 0; // success
}

/*
  For Standalone Mode.
  Sets options and reads output and input filenames from command line.
*/
void init_standalone_mode(int argc, char *argv[])
{
  int i;

  standalone_mode = true;
  strcpy(prj_name, argv[1]); // the output filename
  // set options
  options.lib = true;
  options.cmp = true;
  options.obf = false;
  options.obj = false;
  options.app = true;
  options.dep = false;
  options.log = false;
  options.dbg = false;
  // get app filenames
  app_files_len = 0;
  for (i = 2; i < argc; ++i)
  {
    strcpy(app_files[app_files_len++], argv[i]);
  }
}

/*
  For X Library Mode.
  Reads options, libpath, obfprefix, objprefix and appfiles from project file.
  See the xc_reference for project file details.
*/
bool read_project_file(char *name)
{
  FILE *fp;
  bool opt;
  char *p, line[MAX_LINE_LEN], *t, token[MAX_PATH_LEN];

  // XC does not require a specific extension for the project file,
  // but supplies PRJ_EXT if an ext is not found.
  // Thanks to gagenellina for this idea.
  strcpy(prj_name, name);
  p = strchr(prj_name, '.');
  if (p)
  {
    strcpy(prj_ext, p);
    *p = 0;
  }
  else strcpy(prj_ext, PRJ_EXT);

  // Open the project file.
  strcpy(line, prj_name); // use 'line' temporarily
  strcat(line, prj_ext);
  if ((fp = fopen(line, "r")) == NULL)
  {
    printf("\nError: Could not open project file: %s%s\n", prj_name, prj_ext);
    return false;
  }

  // option defaults
  options.lib = true;
  options.cmp = true;
  options.obf = false;
  options.obj = false;
  options.app = false;
  options.dep = true;
  options.log = false;
  options.dbg = false;
  strcpy(obj_prefix, OBJ_PREFIX); // set default obj_prefix

  while (fgets(line, sizeof(line), fp) != NULL )
  {
    p = line;
    skip_ws(&p);
    // skip newlines and comment lines
    if (*p == ';' || *p == '\n')
    {
      continue;
    }
    // expect directive as first token on line
    t = token;
    while (*p && *p != ' ' && *p != '\t' && *p != '\n' && *p != ';')
    {
      *t++ = *p++;
    }
    *t = 0;
    skip_ws(&p);
    // process directives
    if (!stricmp(token, "obfprefix"))
    {
      if (isalpha(*p) || *p == '_' || *p == '$') obf_prefix = *p;
      else
      {
        printf("\nWarning: invalid obfuscation prefix: '%c', defaulting to '%c'\n", *p, OBF_PREFIX);
        if (log_fp) fprintf(log_fp, "\nWarning: invalid obfuscation prefix: '%c', defaulting to '%c'\n", *p, OBF_PREFIX);
      }
    }
    else if (!stricmp(token, "objprefix"))
    {
      t = token;
      while (*p && *p != '\n' && *p != ';')
      {
        *t++ = *p++;
      }
      *t = 0;
      rtrim(token);
      strcpy(obj_prefix, token);
    }
    else if (!stricmp(token, "libpath"))
    {
      t = token;
      while (*p && *p != '\n' && *p != ';')
      {
        *t++ = *p++;
      }
      *t = 0;
      rtrim(token);
      strcpy(lib_path, token);
    }
    else if (!stricmp(token, "appfiles"))
    {
      // get app file pathnames (expects one per line)
      app_files_len = 0;
      while (fgets(line, sizeof(line), fp) != NULL )
      {
        p = line;
        skip_ws(&p);
        if (*p != ';' && *p != '\n')
        {
          rtrim(p);
          strcpy(app_files[app_files_len++], p);
        }
      }
    }
    else if (!stricmp(token, "options"))
    {
      // parse space-separated options on this line
      while (*p && *p != '\n' && *p != ';')
      {
        t = token;
        while (*p && *p != ' ' && *p != '\t' && *p != '\n' && *p != ';')
        {
          *t++ = tolower(*p++);
        }
        *t = 0;
        skip_ws(&p);
        opt = *token == '-' ? false : true;
        if (strstr(token, "lib")) { options.lib = opt; }
        else if (strstr(token, "cmp")) { options.cmp = opt; }
        else if (strstr(token, "app")) { options.app = opt; }
        else if (strstr(token, "obf")) { options.obf = opt; }
        else if (strstr(token, "obj")) { options.obj = opt; }
        else if (strstr(token, "dep")) { options.dep = opt; }
        else if (strstr(token, "log")) { options.log = opt; }
        else if (strstr(token, "dbg")) { options.dbg = opt; }
      } // end while
      if (options.dbg) { options.log = true; }
      if (options.obf)
      {
        if (options.obj)
        {
          printf("\nWarning: obf and obj are both enabled. Forcing -obj.\n");
          if (log_fp) fprintf(log_fp, "\nWarning: obf and obj are both enabled. Forcing -obj.\n");
        }
        options.obj = false;
      }
    }
  }
  if (options.obf && !options.app)
  {
    printf("\nWarning: function obfuscation enabled but app Js not included in output.\n");
    if (log_fp) fprintf(log_fp, "\nWarning: function obfuscation enabled but app Js not included in output.\n");
  }
  fclose(fp);
  return true;
}

/*
  Parse X version string from X_VER_FILE
*/
bool read_version_file()
{
  int i = 0;
  bool ret;
  FILE *fp;
  char line[MAX_LINE_LEN], *p;

  *x_ver = 0;
  strcpy(line, lib_path);
  strcat(line, X_VER_FILE);
  if ((fp = fopen(line, "r")) == NULL)
  {
    printf("\nWarning: Could not find X version file: %s%s\n", lib_path, X_VER_FILE);
    if (log_fp) fprintf(log_fp, "\nWarning: Could not find X version file: %s%s\n", lib_path, X_VER_FILE);
    return false;
  }

  while (fgets(line, sizeof(line), fp) != NULL)
  {
    p = strstr(line, "version");
    if (p)
    {
      p += 7;
      while (*p && *p != '\"' && *p != '\'')
      {
        ++p;
      }
      ++p;
      while (*p && *p != '\"' && *p != '\'')
      {
        x_ver[i++] = *p++;
      }
      x_ver[i] = 0;
      break; // out of while
    }
  } // end while

  if (!*x_ver)
  {
    printf("\nWarning: Could not read X version from file: %s%s\n", lib_path, X_VER_FILE);
    if (log_fp) fprintf(log_fp, "\nWarning: Could not read X version from file: %s%s\n", lib_path, X_VER_FILE);
    fclose(fp);
    ret = false;
  }
  else
  {
    printf("\ncompiling %s from X %s ...\n", prj_name, x_ver);
    if (log_fp) fprintf(log_fp, "\ncompiling %s from X %s ...\n", prj_name, x_ver);
    ret = true;
  }
  fclose(fp);
  return ret;
}

/*
 Open every XML file in the lib folder and parse out the symbol's id, src and type.
*/
bool get_valid_symbols()
{
  FILE *fp;
  long hFile;
  bool status = false;
  struct _finddata_t fd;
  int i, root_state, src_state, type_state;
  char *p, dir[MAX_PATH_LEN], pth[MAX_PATH_LEN], line[MAX_LINE_LEN];

  strcpy(dir, lib_path);
  strcat(dir, XML_FILE_MASK);
  if ((hFile = _findfirst(dir, &fd)) == -1L)
  {
    printf("\nError: get_valid_symbols could not find %s%s\n", lib_path, XML_FILE_MASK);
    if (log_fp) fprintf(log_fp,"\nError: get_valid_symbols could not find %s%s\n", lib_path, XML_FILE_MASK);
    status = false;
  }
  else
  {
    do
    {
      strcpy(pth, lib_path);
      strcat(pth, fd.name);
      if ((fp = fopen(pth, "r")) == NULL)
      {
        printf("\nError: get_valid_symbols could not find xml file: %s\n", pth);
        if (log_fp) fprintf(log_fp, "\nError: get_valid_symbols could not find xml file: %s\n", pth);
        _findclose(hFile);
        return false;
      }
      root_state = 0;
      src_state = 0;
      type_state = 0;
      while (fgets(line, sizeof(line), fp) != NULL )
      {
        if (root_state == 0)
        {
          if (strstr(line, XML_ROOT))
          {
            p = strstr(line, "id");
            if (p)
            {
              p += 2;
              while (*p && (*p == ' ' || *p == '\t' || *p == '=' || *p == '\'' || *p == '"'))
              {
                ++p;
              }
              for (i = 0; *p && *p != '\'' && *p != '"'; ++i, ++p)
              {
                symbols[symbols_len].id[i] = *p;
              }
              symbols[symbols_len].id[i] = 0;
              ++root_state;
            }
            else
            {
              ; // invalid xml file!
            }
          }
        } // end if (root_state == 0)
        else
        {
          if (src_state == 0)
          {
            if (strstr(line, "<sources")) { ++src_state; }
          }
          if (src_state == 1)
          {
            if (strstr(line, "<src")) { ++src_state; }
          }
          if (src_state == 2)
          {
            p = strstr(line, "<file>");
            if (p)
            {
              p += 6;
              skip_ws(&p);
              for (i = 0; *p && *p != '<' && *p != ' ' && *p != '\t'; ++i, ++p)
              {
                symbols[symbols_len].src[i] = *p;
              }
              symbols[symbols_len].src[i] = 0;
              ++src_state;
            }
          } // end if (src_state == 2)
          if (type_state == 0)
          {
            p = strstr(line, "<type>");
            if (p)
            {
              p += 6;
              skip_ws(&p);
              symbols[symbols_len].type = toupper(*p);
              ++type_state;
            }
          } // end if (type_state == 0)
        }
      } // end while (fgets

      fclose(fp);

      symbols[symbols_len].out = false;
      symbols[symbols_len].dep_len = 0;
      for (i = 0; i < MAX_SYMBOLS; ++i)
      {
        symbols[symbols_len].dep[i] = INVALID;
      }
      ++symbols_len;
    } while (_findnext(hFile, &fd) == 0);
    _findclose(hFile);
    status = true;
  }
  return status;
}

/*
 Update symbol table with dependency info from symbols[sym_idx].src.
*/
bool get_symbol_dependents(int sym_idx)
{
  int ln = 0;
  FILE *fp;
  char line[MAX_LINE_LEN], *p, tok_type;
  int dep;

  strcpy(line, lib_path);
  strcat(line, symbols[sym_idx].src);
  if ((fp = fopen(line, "r")) == NULL)
  {
    printf("\nError: get_symbol_dependents could not find symbol %i file: %s%s\n", sym_idx, lib_path, symbols[sym_idx].src);
    if (log_fp) fprintf(log_fp, "\nError: get_symbol_dependents could not find symbol %i file: %s%s\n", sym_idx, lib_path, symbols[sym_idx].src);
    return false;
  }

  if (options.dbg && log_fp) fprintf(log_fp, "\nX Symbols found in lib file %s:\n", line);

  while (fgets(line, sizeof(line), fp) != NULL )
  {
    ++ln; // line number
    p = line;
    if (*p && *p != '\n')
    {
      p = str_tok(line, delimiters, &tok_type);
      while (p != NULL)
      {
        dep = get_symbol_index(p, tok_type);
        if (options.dep && dep != INVALID && dep != sym_idx)
        {
          set_dependent(sym_idx, dep);
          if (options.dbg && log_fp) fprintf(log_fp, "%s(%i), ", p, dep);
        }
        strcpy(prev_token, p);
        p = str_tok(NULL, delimiters, &tok_type);
      }
    }
  }
  fclose(fp);
  return true;
}

/*
 Determine which X lib files get included in the output library
 by searching fname for X symbols.
*/
bool get_app_file_symbols(char *fname)
{
  FILE *fp;
  int ln = 0, sym_idx;
  bool in_scr = false, out_scr = false, is_html = false;
  char line[MAX_LINE_LEN], *p, tok_type;

  if ((fp = fopen(fname, "r")) == NULL)
  {
    printf("\nError: get_app_file_symbols could not find application file: %s\n", fname);
    if (log_fp) fprintf(log_fp, "\nError: get_app_file_symbols could not find application file: %s\n", fname);
    return false;
  }

  if (strstr(fname, ".htm"))
  {
    is_html = true;
  }

  if (options.dbg && log_fp) fprintf(log_fp, "\nX Symbols found in app file %s:\n", fname);

  while (fgets(line, sizeof(line), fp) != NULL )
  {
    ++ln; // app line number
    if (line[0] != '\n')
    {
      if (is_html && !in_scr)
      {
        if (strstr(line, "<script") || strstr(line, "<SCRIPT")) // if at the start of a script element
        {
          in_scr = true;
          if (options.dbg && log_fp) fprintf(log_fp, "(in_scr on line %i) ", ln);
        }
      }
      if (!is_html || in_scr)
      {
        if (is_html && (strstr(line, "</script>") || strstr(line, "</SCRIPT>"))) // if at the end of a script element
        {
          out_scr = true;
        }
        p = str_tok(line, delimiters, &tok_type);
        while (p != NULL)
        {
          sym_idx = get_symbol_index(p, tok_type);
          if (sym_idx != INVALID)
          {
            include_symbol(sym_idx);
            if (options.dbg && log_fp) fprintf(log_fp, "%s(%i), ", p, sym_idx);
          }
          strcpy(prev_token, p);
          p = str_tok(NULL, delimiters, &tok_type);
        }
        if (out_scr)
        {
          in_scr = out_scr = false;
          if (options.dbg && log_fp) fprintf(log_fp, "(out_scr on line %i) ", ln);
        }
      }
    }
  }
  fclose(fp);
  return true;
}

/*
 Create the output library file.
*/
bool create_library()
{
  int i, a = 0, sym_idx;
  FILE *out_fp;
  char tm_str[10];
  time_t tm;
  
  strcpy(out_file, prj_name);
  if (!standalone_mode) strcat(out_file, LIB_EXT);
  if ((out_fp = fopen(out_file, "w")) == NULL)
  {
    printf("\nError: Could not create output file: %s\n", out_file);
    if (log_fp) fprintf(log_fp, "\nError: Could not create output file: %s\n", out_file);
    return false;
  }

/*
  if (options.app)
  {
    if (standalone_mode)
    {
      tm = time(NULL);
      strftime(tm_str, 9, "%d%b%y", gmtime(&tm));
      fprintf(out_fp, SA_HDR_STR, XC_VER, tm_str);
    }

    // Include the app Js files in the output.
    for (i = 0; i < app_files_len; ++i)
    {
      if (standalone_mode || strstr(app_files[i], ".js"))
      {
        if (append_to_library(out_fp, app_files[i], INVALID))
          ++a;
      }
    }
    if (a) fprintf(out_fp, "\n");
  }
*/

  if (!standalone_mode)
  {
    tm = time(NULL);
    strftime(tm_str, 9, "%d%b%y", gmtime(&tm));
    fprintf(out_fp, X_HDR_STR, x_ver, XC_VER, tm_str);

    if (options.obj)
    {
      fprintf(out_fp, "var %s={};\n", obj_prefix);
    }
  
    // For every symbol which has 'symbols[sym_idx].inc > 0'
    // include symbols[sym_idx].src in the output.
  
    if (options.dbg && log_fp) fprintf(log_fp, "\n\nAppending symbol files...\n");
    for (sym_idx = 0; sym_idx < symbols_len; ++sym_idx)
    {
      if (symbols[sym_idx].inc)
      {
        if (options.dbg && log_fp) fprintf(log_fp, "\n%i:\n", sym_idx);
        if (!append_to_library(out_fp, symbols[sym_idx].src, sym_idx))
        {
          printf("\nWarning: Could not add %s%s to output\n", symbols[sym_idx].src, LIB_EXT);
          if (log_fp) fprintf(log_fp, "\nWarning: Could not add %s%s to output\n", symbols[sym_idx].src, LIB_EXT);
        }
      }
    }
  } // end if (!standalone_mode)

  if (options.app)
  {
    if (standalone_mode)
    {
      tm = time(NULL);
      strftime(tm_str, 9, "%d%b%y", gmtime(&tm));
      fprintf(out_fp, SA_HDR_STR, XC_VER, tm_str);
    }
    else
    {
      fprintf(out_fp, "\n/* Application */\n");
    }
    // Include the app Js files in the output.
    for (i = 0; i < app_files_len; ++i)
    {
      if (standalone_mode || strstr(app_files[i], ".js"))
      {
        if (append_to_library(out_fp, app_files[i], INVALID))
          ++a;
      }
    }
    if (a) fprintf(out_fp, "\n");
  } // end if (options.app)

  fclose(out_fp);
  return true;
}

/*
 Appends name to the output library js file. Applies optional compression,
 optional function name obfuscation and optional function name object prefix.
*/
bool append_to_library(FILE *out_fp, char *name, int sym_idx)
{
  int i, ln = 0, fd;
  FILE *lib_fp;
  bool in_com = false, en_brc_cnt = false, is_esc_str = false, in_rel = false, is_esc_rel = false;
  char lib_name[MAX_PATH_LEN], in_str = 0, last_char = ' ';
  char *p, line[MAX_LINE_LEN], buf[MAX_LINE_LEN];

  if (sym_idx == INVALID) // append an app file
  {
    strcpy(lib_name, name);
  }
  else // append a lib file
  {
    if (symbols[sym_idx].out) return true;
    strcpy(lib_name, lib_path);
    strcat(lib_name, name);
  }
  if ((lib_fp = fopen(lib_name, "r")) == NULL)
  {
    printf("\nError: append_to_library could not find file: %s\n", lib_name);
    if (log_fp) fprintf(log_fp, "\nError: append_to_library could not find file: %s\n", lib_name);
    return false;
  }

  while (fgets(line, sizeof(line), lib_fp) != NULL )
  {
    ++ln; // line number
    if (options.obf)
    {
      obfuscate_symbols(line);
    }
    else if (options.obj)
    {
      fd = objectify_symbols(line);
      if (fd == 1)
      {
        en_brc_cnt = true;
      }
      if (en_brc_cnt)
      {
        if (fd == 1)
        {
          en_brc_cnt = count_braces(line, true);
        }
        else if (fd == 0)
        {
          en_brc_cnt = count_braces(line, false);
        }
      }

    } // end if (options.obj)
    if (!options.cmp)
    {
      if (fputs(line, out_fp) == EOF)
      {
        fclose(lib_fp);
        printf("\nError: Could not write to output file: %s\n", out_file);
        if (log_fp) fprintf(log_fp, "\nError: Could not write to output file: %s\n", out_file);
        return false;
      }
    }
    else
    {
      // parse another line
      p = line;
      skip_ws(&p); // skip leading whitespace
      i = 0;

      // check last char from prev line
      if (!strchr(delimiters, last_char) && !strchr(delimiters, *p))
      {
        last_char = buf[i++] = ' '; // stuff a space in the output buf
      }

      while (*p && *p != '\n') // skip blank lines
      {
        // Process Strings
        if (!in_com && !in_rel)
        {
          if (!in_str)
          {
            if (*p == '\'' || *p == '\"') // start of string
            {
              in_str = *p;
            }
          }
          else // in string
          {
            if (*p == in_str && !is_esc_str) // end of string
            {
              in_str = 0;
            }
            if (*p == '\\' && !is_esc_str) // next char is escaped
            {
              is_esc_str = true;
            }
            else
            {
              is_esc_str = false;
            }
            if (*p != '\\') // next char is not escaped
            {
              is_esc_str = false;
            }
          }
        } // end processing strings

        // Replace a tab with a space
        if (!in_str && *p == '\t')
        {
          *p = ' ';
        }

        // Process Comments
        if (!in_str && !in_rel)
        {
          if (!in_com && *p == '/' && *(p+1) == '/') // skip single-line comments
          {
            break; // out of while (*p
          }
          // determine if *p is the start or end of a multi-line comment
          // but allow jscript conditional compilation syntax
          if (*p == '/' && *(p+1) == '*' && *(p+2) != '@')
          {
            in_com = true;
          }
          else if ((*p == '*') && (*(p+1) == '/')  && last_char != '@')
          {
            in_com = false;
            p += 2;
            continue; // with while (*p
          }
        } // end processing comments 

        // Process RegExp Literals
        if (!in_com && !in_str)
        {
          if (!in_rel)
          {
            // Start of RE literal. Have to also check for start or end of comment because we might be in a CC section.
            if (*p == '/' && last_char != '*' && *(p+1) != '/' && *(p+1) != '*')
            {
              if (last_char != ' ' && (last_char == '=' || last_char == '(' || last_char == ','))
              {
                in_rel = true;
              }
            }
          }
          else // in RE literal
          {
            if (*p == '/' && !is_esc_rel) // end of rel
            {
              in_rel = false;
            }
            if (*p == '\\' && !is_esc_rel) // next char is escaped
            {
              is_esc_rel = true;
            }
            else
            {
              is_esc_rel = false;
            }
            if (*p != '\\') // next char is not escaped
            {
              is_esc_rel = false;
            }
          }
        } // end processing RE literals

        // Skip certain spaces or store char to output buf
        if (!in_com)
        {
          // if not in a string nor RE literal, skip a space if it is followed by a space
          if ( !in_str && !in_rel && (*p == ' ') && (*(p+1) == ' ') )
          {
            *p = last_char; // in the next iteration we don't need to see this space we are skipping
            if (options.dbg && log_fp) fprintf(log_fp, "s");///////
          }
          // if not in a string nor RE literal, skip a space if it has a delimiter on either side of it
          else if (!in_str && !in_rel && *p == ' ' && ( strchr(delimiters, last_char) || (*(p+1) && strchr(delimiters, *(p+1))) ) )
          {
            if (options.dbg && log_fp) fprintf(log_fp, "d");///////
          }
          else
          {
            buf[i++] = *p; // store character to output buf
            last_char = *p; // save a copy of it
          }
        }
        else if (options.dbg && log_fp)
        {
          fprintf(log_fp, "c");///////
        }

        ++p; // point to next char in line

      } // end while (*p && *p != '\n')
      // terminate the string and write it to the output file
      buf[i] = 0;
      if (fputs(buf, out_fp) == EOF)
      {
        fclose(lib_fp);
        printf("\nError: Could not write to output file: %s\n", out_file);
        if (log_fp) fprintf(log_fp, "\nError: Could not write to output file: %s\n", out_file);
        return false;
      }
    } // end else
  } // end while (fgets
  fclose(lib_fp);
  if (sym_idx != INVALID) // appended a symbol file, not an app file
  {
    set_symbol_complete(name); // indicate that this file has been output
  }
  return true;
}

/*
 Determine if token matches an ID in the symbol table.
 If sym_type is 'P' or 'M' then the token searched for
 is: "prev_token.token".
*/
int get_symbol_index(char *token, char sym_type)
{
  int i, idx = INVALID;
  char tok[MAX_NAME_LEN];

  if (sym_type == 'P' || sym_type == 'M')
  {
    strcpy(tok, prev_token);
    strcat(tok, ".");
    strcat(tok, token);
    //if (log_fp) fprintf(log_fp, "\n\nprev_token: %s\ntok: %s\ntype: %c\n\n", prev_token, tok, sym_type);////////////
  }
  else
  {
    strcpy(tok, token);
  }
  for (i = 0; i < symbols_len; ++i)
  {
    if (!strcmp(tok, symbols[i].id)) // token == id
    {
      idx = i;
      break; // out of 'for'
    }
  }
  return idx;
}

/*
 if the 'symbols[sym_idx].dep' array does not already contain 'dep'
 then assign 'dep' to the next available array element.
*/
void set_dependent(int sym_idx, int dep)
{
  int i;

  for (i = 0; i < symbols[sym_idx].dep_len; ++i)
  {
    if (symbols[sym_idx].dep[i] == dep)
    {
      return;
    }
  }
  symbols[sym_idx].dep[symbols[sym_idx].dep_len++] = dep;
}

/*
 Indicate the X lib file symbols[sym_idx] (and all it's dependents)
 to be included in the output library file.
*/
void include_symbol(int sym_idx)
{
  int i;

  if (sym_idx >= symbols_len) return;
  if (!symbols[sym_idx].inc++)
  {
    for (i = 0; i < symbols[sym_idx].dep_len; ++i)
    {
      include_symbol(symbols[sym_idx].dep[i]);
    }
  }
}

/*
 For every symbol with src == s, mark that symbol
 as having been included in the output.
*/
void set_symbol_complete(char *s)
{
  int i;

  if (s && *s)
  {
    for (i = 0; i < symbols_len; ++i)
    {
      if (!strcmp(s, symbols[i].src))
      {
        symbols[i].out = true;
      }
    }
  }
}

/*
 For all symbols[].id found in line, replace them with obf_prefix plus
 the base 36 string version of the symbol's index in symbols[].
*/
void obfuscate_symbols(char *line)
{
  int i;
  char n[6], new_id[MAX_NAME_LEN];

  if (!*line) return;
  for (i = 0; i < symbols_len; ++i)
  {
    if (symbols[i].inc)
    {
      // create the new identifier
      new_id[0] = obf_prefix;
      new_id[1] = 0;
      strcat(new_id, uitoa(i, n, 36)); 
      // replace symbols
      strreplwg(line, MAX_LINE_LEN-1, symbols[i].id, new_id);
    }
  } // end for
}

/*
  returns -2 if !*line, -1 if buf len error, 1 if func decl made, else 0
*/
int objectify_symbols(char *line)
{
  int i, j, ret = 0, rep;
  char *p, *id, new_id[MAX_NAME_LEN];
  char old_dec[MAX_NAME_LEN], new_dec[MAX_NAME_LEN];

  if (!*line) return -2;
  for (i = 0; i < symbols_len; ++i)
  {
    if (symbols[i].inc && symbols[i].type == 'F')
    {
      // create the new identifier
      strcpy(new_id, obj_prefix);
      strcat(new_id, ".");
      id = symbols[i].id;
      if (*id == 'x' && isupper(*(id+1)))
      {
        j = strlen(new_id);
        new_id[j] = tolower(*(id+1));
        new_id[j+1] = 0;
        strcat(new_id, id+2);
      }
      else
      {
        strcat(new_id, id);
      }
      // check if this is a declaration
      p = strstrw(line, "function", true);
      if (p)
      {
        strcpy(old_dec, "function");
        p += 8;
        while (*p == ' ' || *p == '\t')
        {
          strcat(old_dec, " ");
          ++p;
        }
        strcat(old_dec, id);
        strcpy(new_dec, new_id);
        strcat(new_dec, "=function");
        // replace declaration
        rep = strreplwg(line, MAX_LINE_LEN-1, old_dec, new_dec);
        if (rep == -1)
        {
          printf("\nError: line not long enough in objectify_symbol\n");
          if (log_fp) fprintf(log_fp, "\nError: line not long enough in objectify_symbol\n");
          return -1;
        }
        else if (rep > 0)
        {
          ret = 1;
        }
      }
      // replace symbols
      if (-1 == strreplwg(line, MAX_LINE_LEN-1, id, new_id))
      {
        printf("\nError: line not long enough in objectify_symbol\n");
        if (log_fp) fprintf(log_fp, "\nError: line not long enough in objectify_symbol\n");
        return -1;
      }
    }
  } // end for
  return ret;
}

/*
 Increment *s past all white-space.
*/
void skip_ws(char **s)
{
  while (**s == ' ' || **s == '\t')
  {
    ++*s;
  }
}

/*
 Remove whitespace and newlines from end of s
*/
void rtrim(char *s)
{
  char *p;

  p = s + (strlen(s) - 1);
  while (*p == ' ' || *p == '\t' || *p == '\n')
  {
    --p;
  }
  ++p;
  *p = 0;
}

/*
 Write project info, app file list and symbol table to the log file.
*/
void write_final_log()
{
  int i, j;
  char n[6];

  fprintf(log_fp, "\n\nProject Info:\n\n");
  fprintf(log_fp, "project file: %s%s\n", prj_name, prj_ext);
  fprintf(log_fp, "output lib file: %s%s\n", prj_name, LIB_EXT);
  fprintf(log_fp, "library path: %s\n", lib_path);
  fprintf(log_fp, "options: lib=%i, cmp=%i, app=%i, obf=%i, obj=%i, dep=%i, log=%i, dbg=%i\n",
          options.lib,
          options.cmp,
          options.app,
          options.obf,
          options.obj,
          options.dep,
          options.log,
          options.dbg);
  fprintf(log_fp, "obfuscation prefix: %c\n", obf_prefix);
  fprintf(log_fp, "object prefix: %s\n", obj_prefix);

  fprintf(log_fp, "\nApplication Files:\n\n");
  for (i = 0; i < app_files_len; ++i)
  {
    fprintf(log_fp, "%i: %s\n", i, app_files[i]);
  }

  fprintf(log_fp, "\nOutput Files:\n\n");
  if (options.lib) fprintf(log_fp, " %s%s", prj_name, LIB_EXT);
  if (log_fp) fprintf(log_fp, ", %s%s", prj_name, LOG_EXT);
  fprintf(log_fp, "\n");

  fprintf(log_fp, "\nSymbol Table:\n\n");
  for (i = 0; i < symbols_len; ++i)
  {
    fprintf(log_fp, "%i(%s): %s(inc=%i)(src=%s)(type=%c)", i, uitoa(i,n,36), symbols[i].id, symbols[i].inc, symbols[i].src, symbols[i].type);
    for (j = 0; j < symbols[i].dep_len; ++j)
    {
      if (options.dbg)
      { // by number
        fprintf(log_fp, ", %i", symbols[i].dep[j]);
      }
      else
      { // by name
        fprintf(log_fp, ", %s", symbols[symbols[i].dep[j]].id);
      }
    }
    fprintf(log_fp, "\n");
  }

  if (options.dbg)
  {
    fprintf(log_fp, "\nSymbols:\n\n");
    for (i = 0; i < symbols_len; ++i)
    {
      fprintf(log_fp, "%s\n", symbols[i].id);
    }
  }
}

/*
  ANSI-compliant case-insensitive string comparison.
  I modified it from this source: http://c.snippets.org/
*/
int stricmp(const char *s1, const char *s2)
{
  int dif = 0;

  do
  {
    dif = tolower(*s1++) - tolower(*s2++);
  } while (!dif && *s1 && *s2);
  return dif;
}

/*
  ANSI-compliant? unsigned int to string conversion.
  All alpha chars will be uppercase. I modified it from this source:
  http://www.koders.com/c/fid5F9B1CF12E947E5030A132D309A367C5CCB671CE.aspx?s=itoa
*/
char *uitoa(unsigned int value, char *string, int radix)
{
  int i;
  char *sp;
  char tmp[33];
  char *tp = tmp;
  unsigned int v = value;

  if (!string || radix > 36 || radix <= 1)
  {
    return 0;
  }
  while (v || tp == tmp)
  {
    i = v % radix;
    v = v / radix;
    if (i < 10)
    {
      *tp++ = i + '0';
    }
    else
    {
      *tp++ = i + 'A' - 10; // use uppercase
    }
  }
  sp = string;
  while (tp > tmp)
  {
    *sp++ = *--tp;
  }
  *sp = 0;
  return string;
}

/*
** String Replace Word
** Replace whole-word oldstr by newstr in string str
** contained in buffer of size bufsiz.
**
** str and oldstr/newstr should not overlap.
** The empty string ("") is found at the beginning of every string.
**
** Returns: pointer to first location after where newstr was inserted.
**          str if oldstr was not found.
**          NULL if replacement would overflow str's buffer
  I modified it from this source: http://c.snippets.org/
*/
char *strreplw(char *str, size_t bufsiz, char *oldstr, char *newstr, bool line_start)
{
  int oldlen, newlen;
  char *p = str, *q;

  oldlen = strlen(oldstr);
  newlen = strlen(newstr);
  if (NULL == (p = strstrw(p, oldstr, line_start))) return str;
  if ((strlen(str) + newlen - oldlen + 1) > bufsiz) return NULL;
  memmove(q = p+newlen, p+oldlen, strlen(p+oldlen)+1);
  memcpy(p, newstr, newlen);
  return q;
}

/* String Replace Word Global
   Returns -1 if str is not long enough, else a count of replacements made.
*/
int strreplwg(char *str, size_t bufsiz, char *oldstr, char *newstr)
{
  int rep = 0;
  char *q, *p = str;
  size_t bufrem = bufsiz;
  bool line_start = true;

  while (p)
  {
    q = strreplw(p, bufrem, oldstr, newstr, line_start);
    if (!q) return -1; // error, str not long enough
    if (p == q) return rep;
    line_start = false;
    bufrem -= q - p;
    p = q;
    ++rep; // count replacements
  }
  return rep;
}

/*
  returns false if ';' was inserted/found else true
*/
bool count_braces(char *s, bool first_call)
{
  char *p;
  bool ret = true;
  static int brc_cnt = 0;

  if (first_call)
  {
    brc_cnt = 0;
  }
  while (*s)
  {
    if (*s == '{')
    {
      ++brc_cnt;
    }
    if (*s == '}')
    {
      --brc_cnt;
      if (brc_cnt == 0)
      {
        // insert ';' after '}' if not already there
        ++s;
        p = s;
        skip_ws(&p);
        if (*p != ';')
        {
          memmove(s + 1, s, strlen(s) + 1);
          *s = ';';
        }
        ret = false; // notify caller of semicolon insertion
      }
      else if (brc_cnt < 0)
      {
        printf("\nError: brc_cnt < 0 in count_braces\n");
        if (log_fp) fprintf(log_fp, "\nError: brc_cnt < 0 in count_braces\n");
      }
    }
    ++s;
  }
  return ret; // still looking for closing brace
}

/* Find str in str by whole word
*/
char *strstrw(char *str, char *word, bool line_start)
{
  char *p = str;
  int len = strlen(word);

  while (1)
  {
    if (NULL == (p = strstr(p, word))) return NULL; // not found
    if (
      ( (line_start && p == str) || strchr(delimiters, *(p-1)) )
      &&
      ( strchr(delimiters, *(p+len)) || *(p+len)==0 || *(p+len)=='\n' )
    )
    {
      return p;
    }
    p += len;
  }
}

/* Tokenize a string
 Works just like the standard strtok except:
 1. does not modify str
 2. assigns 0, 'P' or 'M' to tok_type
*/
char *str_tok(char *str, char *del, char *tok_type)
{
  char *t, *p;
  static char *s, *so, tok[MAX_NAME_LEN];

  *tok_type = 0;
  tok[0] = 0;
  if (str)
  {
    s = so = str;
  }
  while (*s)
  {
    if (!strchr(del, *s)) // first non-del char is start of token
    {
      // is token preceded by '.'?
      p = s;
      if (p != so)
      {
        do {
          --p;
        } while (p != so && (*p == ' ' || *p == '\t')); // assumes ' ' and '\t' are delimeters!
        if (*p == '.')
        {
          *tok_type = 'P'; // assumes '.' is on same line as token! yuck!
        }
      }
      // get chars of token
      t = tok;
      while (*s && !strchr(del, *s))
      {
        *t++ = *s++;
      }
      *t = 0;
      // is token followed by '('?
      p = s;
      skip_ws(&p);
      if (*tok_type == 'P' && *p == '(')
      {
        *tok_type = 'M'; // assumes '.' and '(' are on same line as token! yuck!
      }
      return tok; // return pointer to token
    }
    ++s;
  } // end while (*s)
  return NULL; // no token found
}

/*
 This is the comparison function passed to 'qsort' when sorting the
 symbol table. Symbols are sorted by type and then by id. The type
 precedence is: V, O, P, M, F.
*/
int compare_fn(const void *ele1, const void *ele2)
{
  int ret = 0;
  struct tag_symbol *s1, *s2;

  s1 = (struct tag_symbol *)ele1;
  s2 = (struct tag_symbol *)ele2;
  ret = strcmp(s1->id, s2->id);
  // Variables come before all other types.
  if (s1->type == 'V')
  {
    if (s2->type != 'V') ret = -1;
  }
  else if (s2->type == 'V')
  {
    if (s1->type != 'V') ret = 1;
  }
  // Objects come next.
  else if (s1->type == 'O')
  {
    if (s2->type != 'O') ret = -1;
  }
  else if (s2->type == 'O')
  {
    if (s1->type != 'O') ret = 1;
  }
  // Properties come next.
  else if (s1->type == 'P')
  {
    if (s2->type != 'P') ret = -1;
  }
  else if (s2->type == 'P')
  {
    if (s1->type != 'P') ret = 1;
  }
  // Methods come next.
  else if (s1->type == 'M')
  {
    if (s2->type != 'M') ret = -1;
  }
  else if (s2->type == 'M')
  {
    if (s1->type != 'M') ret = 1;
  }
  // Functions come last.
  // Return the comparison result:
  return ret;
}

// end xc.c
