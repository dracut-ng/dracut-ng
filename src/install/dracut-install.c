/* dracut-install.c  -- install files and executables

   Copyright (C) 2012 Harald Hoyer
   Copyright (C) 2012 Red Hat, Inc.  All rights reserved.

   This program is free software: you can redistribute it and/or modify
   under the terms of the GNU Lesser General Public License as published by
   the Free Software Foundation; either version 2.1 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful, but
   WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public License
   along with this program; If not, see <http://www.gnu.org/licenses/>.
*/

#define PROGRAM_VERSION_STRING "2"

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <ctype.h>
#include <elf.h>
#include <errno.h>
#include <fcntl.h>
#include <fnmatch.h>
#include <getopt.h>
#include <glob.h>
#include <libgen.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <libkmod.h>
#include <fts.h>
#include <regex.h>
#include <sys/utsname.h>
#include <sys/xattr.h>
#include <sys/mman.h>

#ifdef HAVE_SYSTEMD
#include <systemd/sd-json.h>
#endif

#include "log.h"
#include "hashmap.h"
#include "util.h"
#include "strv.h"

#define _asprintf(strp, fmt, ...) \
        do { \
            if (dracut_asprintf(strp, fmt, __VA_ARGS__) < 0) { \
                    log_error("Out of memory\n"); \
                    exit(EXIT_FAILURE); \
            } \
        } while (0)

static bool arg_hmac = false;
static bool arg_createdir = false;
static int arg_loglevel = -1;
static bool arg_optional = false;
static bool arg_silent = false;
static bool arg_all = false;
static bool arg_module = false;
static bool arg_modalias = false;
static bool arg_dry_run = false;
static bool arg_resolvelazy = false;
static bool arg_resolvedeps = false;
static bool arg_hostonly = false;
static bool arg_kerneldir = false;
static bool no_xattr = false;
static char *destrootdir = NULL;
static char *sysrootdir = NULL;
static size_t sysrootdirlen = 0;
static char *kerneldir = NULL;
static size_t kerneldirlen = 0;
static char **firmwaredirs = NULL;
static char **pathdirs;
static char *logdir = NULL;
static char *logfile = NULL;
FILE *logfile_f = NULL;
static Hashmap *items = NULL;
static Hashmap *items_failed = NULL;
static Hashmap *modules_loaded = NULL;
static Hashmap *modules_suppliers = NULL;
static Hashmap *processed_suppliers = NULL;
static Hashmap *modalias_to_kmod = NULL;
static Hashmap *add_dlopen_features = NULL;
static Hashmap *omit_dlopen_features = NULL;
static Hashmap *dlopen_features[2] = {NULL};
static regex_t mod_filter_path;
static regex_t mod_filter_nopath;
static regex_t mod_filter_symbol;
static regex_t mod_filter_nosymbol;
static regex_t mod_filter_noname;
static bool arg_mod_filter_path = false;
static bool arg_mod_filter_nopath = false;
static bool arg_mod_filter_symbol = false;
static bool arg_mod_filter_nosymbol = false;
static bool arg_mod_filter_noname = false;

static int dracut_install(const char *src, const char *dst, bool isdir, bool resolvedeps, bool hashdst);
static int install_dependent_modules(struct kmod_ctx *ctx, struct kmod_list *modlist, Hashmap *suppliers_paths);

static void item_free(char *i)
{
        assert(i);
        free(i);
}

static inline void kmod_module_unrefp(struct kmod_module **p)
{
        if (*p)
                kmod_module_unref(*p);
}

#define _cleanup_kmod_module_unref_ _cleanup_(kmod_module_unrefp)

static inline void kmod_module_unref_listp(struct kmod_list **p)
{
        if (*p)
                kmod_module_unref_list(*p);
}

#define _cleanup_kmod_module_unref_list_ _cleanup_(kmod_module_unref_listp)

static inline void kmod_module_info_free_listp(struct kmod_list **p)
{
        if (*p)
                kmod_module_info_free_list(*p);
}

#define _cleanup_kmod_module_info_free_list_ _cleanup_(kmod_module_info_free_listp)

static inline void kmod_unrefp(struct kmod_ctx **p)
{
        kmod_unref(*p);
}

#define _cleanup_kmod_unref_ _cleanup_(kmod_unrefp)

static inline void kmod_module_dependency_symbols_free_listp(struct kmod_list **p)
{
        if (*p)
                kmod_module_dependency_symbols_free_list(*p);
}

#define _cleanup_kmod_module_dependency_symbols_free_list_ _cleanup_(kmod_module_dependency_symbols_free_listp)

static inline void fts_closep(FTS **p)
{
        if (*p)
                fts_close(*p);
}

#define _cleanup_fts_close_ _cleanup_(fts_closep)

#define _cleanup_globfree_ _cleanup_(globfree)

static inline void destroy_hashmap(Hashmap **hashmap)
{
        void *i = NULL;

        while ((i = hashmap_steal_first(*hashmap)))
                item_free(i);

        hashmap_free(*hashmap);
}

#define _cleanup_destroy_hashmap_ _cleanup_(destroy_hashmap)

/* Check whether the given key exists in the hash before duplicating and
   inserting it. Assumes the value has already been duplicated and is no longer
   needed if the insertion fails. */
static int hashmap_put_strdup_key(Hashmap *h, const char *key, char *value)
{
        if (hashmap_get(h, key))
                return 0;

        char *nkey = strdup(key);

        if (nkey && hashmap_put(h, nkey, value) != -ENOMEM)
                return 0;

        log_error("Out of memory");
        free(nkey);
        free(value);
        return -ENOMEM;
}

static size_t dir_len(char const *file)
{
        size_t length;

        if (!file)
                return 0;

        /* Strip the basename and any redundant slashes before it.  */
        for (length = strlen(file) - 1; 0 < length; length--)
                if (file[length] == '/' && file[length - 1] != '/')
                        break;
        return length;
}

static char *convert_abs_rel(const char *from, const char *target)
{
        /* we use the 4*MAXPATHLEN, which should not overrun */
        char buf[MAXPATHLEN * 4];
        _cleanup_free_ char *realtarget = NULL, *realfrom = NULL, *from_dir_p = NULL;
        _cleanup_free_ char *target_dir_p = NULL;
        size_t level = 0, fromlevel = 0, targetlevel = 0;
        int l;
        size_t i, rl, dirlen;

        dirlen = dir_len(from);
        from_dir_p = strndup(from, dirlen);
        if (!from_dir_p)
                return strdup(from + strlen(destrootdir));
        if (realpath(from_dir_p, buf) == NULL) {
                log_warning("convert_abs_rel(): from '%s' directory has no realpath: %m", from);
                return strdup(from + strlen(destrootdir));
        }
        /* dir_len() skips double /'s e.g. //lib64, so we can't skip just one
         * character - need to skip all leading /'s */
        for (i = dirlen + 1; from[i] == '/'; ++i)
                ;
        _asprintf(&realfrom, "%s/%s", buf, from + i);

        dirlen = dir_len(target);
        target_dir_p = strndup(target, dirlen);
        if (!target_dir_p)
                return strdup(from + strlen(destrootdir));
        if (realpath(target_dir_p, buf) == NULL) {
                log_warning("convert_abs_rel(): target '%s' directory has no realpath: %m", target);
                return strdup(from + strlen(destrootdir));
        }

        for (i = dirlen + 1; target[i] == '/'; ++i)
                ;
        _asprintf(&realtarget, "%s/%s", buf, target + i);

        /* now calculate the relative path from <from> to <target> and
           store it in <buf>
         */
        rl = 0;

        /* count the pathname elements of realtarget */
        for (targetlevel = 0, i = 0; realtarget[i]; i++)
                if (realtarget[i] == '/')
                        targetlevel++;

        /* count the pathname elements of realfrom */
        for (fromlevel = 0, i = 0; realfrom[i]; i++)
                if (realfrom[i] == '/')
                        fromlevel++;

        /* count the pathname elements, which are common for both paths */
        for (level = 0, i = 0; realtarget[i] && (realtarget[i] == realfrom[i]); i++)
                if (realtarget[i] == '/')
                        level++;

        /* add "../" to the buf path, until the common pathname is
           reached */
        for (i = level; i < targetlevel; i++) {
                if (i != level)
                        buf[rl++] = '/';
                buf[rl++] = '.';
                buf[rl++] = '.';
        }

        /* set l to the next uncommon pathname element in realfrom */
        for (l = 1, i = 1; i < level; i++)
                for (l++; realfrom[l] && realfrom[l] != '/'; l++) ;
        /* skip next '/' */
        l++;

        /* append the uncommon rest of realfrom to the buf path */
        for (i = level; i <= fromlevel; i++) {
                if (rl)
                        buf[rl++] = '/';
                while (realfrom[l] && realfrom[l] != '/')
                        buf[rl++] = realfrom[l++];
                l++;
        }

        buf[rl] = 0;
        return strdup(buf);
}

static int ln_r(const char *src, const char *dst)
{
        if (arg_dry_run)
                return 0;

        int ret;
        _cleanup_free_ const char *points_to = convert_abs_rel(src, dst);

        log_info("ln -s '%s' '%s'", points_to, dst);
        ret = symlink(points_to, dst);

        if (ret != 0) {
                log_error("ERROR: ln -s '%s' '%s': %m", points_to, dst);
                return 1;
        }

        return 0;
}

/* Perform the O(1) btrfs clone operation, if possible.
   Upon success, return 0.  Otherwise, return -1 and set errno.  */
static inline int clone_file(int dest_fd, int src_fd)
{
#undef BTRFS_IOCTL_MAGIC
#define BTRFS_IOCTL_MAGIC 0x94
#undef BTRFS_IOC_CLONE
#define BTRFS_IOC_CLONE _IOW (BTRFS_IOCTL_MAGIC, 9, int)
        return ioctl(dest_fd, BTRFS_IOC_CLONE, src_fd);
}

static int copy_xattr(int dest_fd, int src_fd)
{
        int ret = 0;
        ssize_t name_len = 0, value_len = 0;
        char *name_buf = NULL, *name = NULL, *value = NULL, *value_save = NULL;

        name_len = flistxattr(src_fd, NULL, 0);
        if (name_len < 0)
                return -1;

        name_buf = calloc(1, name_len + 1);
        if (name_buf == NULL)
                return -1;

        name_len = flistxattr(src_fd, name_buf, name_len);
        if (name_len < 0)
                goto out;

        for (name = name_buf; name != name_buf + name_len; name = strchr(name, '\0') + 1) {
                value_len = fgetxattr(src_fd, name, NULL, 0);
                if (value_len < 0) {
                        ret = -1;
                        continue;
                }

                value_save = value;
                value = realloc(value, value_len);
                if (value == NULL) {
                        value = value_save;
                        ret = -1;
                        goto out;
                }

                value_len = fgetxattr(src_fd, name, value, value_len);
                if (value_len < 0) {
                        ret = -1;
                        continue;
                }

                value_len = fsetxattr(dest_fd, name, value, value_len, 0);
                if (value_len < 0)
                        ret = -1;
        }

out:
        free(name_buf);
        free(value);
        return ret;
}

static bool use_clone = true;

static int cp(const char *src, const char *dst)
{
        if (arg_dry_run)
                return 0;

        pid_t pid;
        int ret = 0;

        if (use_clone) {
                struct stat sb;
                _cleanup_close_ int dest_desc = -1, source_desc = -1;

                if (lstat(src, &sb) != 0)
                        goto normal_copy;

                if (S_ISLNK(sb.st_mode))
                        goto normal_copy;

                source_desc = open(src, O_RDONLY | O_CLOEXEC);
                if (source_desc < 0)
                        goto normal_copy;

                dest_desc = open(dst, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, sb.st_mode & ~S_IFMT);
                if (dest_desc < 0)
                        goto normal_copy;

                ret = clone_file(dest_desc, source_desc);

                if (ret == 0) {
                        struct timeval tv[2];
                        if (fchown(dest_desc, sb.st_uid, sb.st_gid) != 0)
                                if (fchown(dest_desc, (uid_t) - 1, sb.st_gid) != 0) {
                                        if (geteuid() == 0)
                                                log_error("Failed to chown %s: %m", dst);
                                        else
                                                log_info("Failed to chown %s: %m", dst);
                                }

                        if (geteuid() == 0 && no_xattr == false) {
                                if (copy_xattr(dest_desc, source_desc) != 0)
                                        log_error("Failed to copy xattr %s: %m", dst);
                        }

                        tv[0].tv_sec = sb.st_atime;
                        tv[0].tv_usec = 0;
                        tv[1].tv_sec = sb.st_mtime;
                        tv[1].tv_usec = 0;
                        futimes(dest_desc, tv);
                        return ret;
                }
                /* clone did not work, remove the file */
                unlink(dst);
                /* do not try clone again */
                use_clone = false;
        }

normal_copy:
        pid = fork();
        const char *preservation = (geteuid() == 0
                                    && no_xattr == false) ? "--preserve=mode,xattr,timestamps,ownership" : "--preserve=mode,timestamps,ownership";
        if (pid == 0) {
                execlp("cp", "cp", "--reflink=auto", "--sparse=auto", preservation, "-fL", src, dst, NULL);
                _exit(errno == ENOENT ? 127 : 126);
        }

        while (waitpid(pid, &ret, 0) == -1) {
                if (errno != EINTR) {
                        log_error("ERROR: waitpid() failed: %m");
                        return 1;
                }
        }
        ret = WIFSIGNALED(ret) ? 128 + WTERMSIG(ret) : WEXITSTATUS(ret);
        if (ret != 0)
                log_error("ERROR: 'cp --reflink=auto --sparse=auto %s -fL %s %s' failed with %d", preservation, src, dst, ret);
        log_debug("cp ret = %d", ret);
        return ret;
}

static int library_install(const char *src, const char *lib)
{
        _cleanup_free_ char *p = NULL;
        _cleanup_free_ char *pdir = NULL, *ppdir = NULL, *pppdir = NULL, *clib = NULL;
        char *q, *clibdir;
        int r, ret = 0;

        r = dracut_install(lib, lib, false, false, true);
        if (r != 0)
                log_error("ERROR: failed to install '%s' for '%s'", lib, src);
        else
                log_debug("Lib install: '%s'", lib);
        ret += r;

        /* also install lib.so for lib.so.* files */
        q = strstr(lib, ".so.");
        if (q) {
                p = strndup(lib, q - lib + 3);

                /* ignore errors for base lib symlink */
                if (dracut_install(p, p, false, false, true) == 0)
                        log_debug("Lib install: '%s'", p);

                free(p);
        }

        /* Also try to install the same library from one directory above
         * or from one directory above glibc-hwcaps.
           This fixes the case, where only the HWCAP lib would be installed
           # ldconfig -p|grep -F libc.so
           libc.so.6 (libc6,64bit, hwcap: 0x0000001000000000, OS ABI: Linux 2.6.32) => /lib64/power6/libc.so.6
           libc.so.6 (libc6,64bit, hwcap: 0x0000000000000200, OS ABI: Linux 2.6.32) => /lib64/power6x/libc.so.6
           libc.so.6 (libc6,64bit, OS ABI: Linux 2.6.32) => /lib64/libc.so.6
         */

        p = strdup(lib);

        pdir = dirname_malloc(p);
        if (!pdir)
                return ret;

        ppdir = dirname_malloc(pdir);
        /* only one parent directory, not HWCAP library */
        if (!ppdir || streq(ppdir, "/"))
                return ret;

        pppdir = dirname_malloc(ppdir);
        if (!pppdir)
                return ret;

        clibdir = streq(basename(ppdir), "glibc-hwcaps") ? pppdir : ppdir;
        clib = strjoin(clibdir, "/", basename(p), NULL);
        if (dracut_install(clib, clib, false, false, true) == 0)
                log_debug("Lib install: '%s'", clib);
        /* also install lib.so for lib.so.* files */
        q = strstr(clib, ".so.");
        if (q) {
                q[3] = '\0';

                /* ignore errors for base lib symlink */
                if (dracut_install(clib, clib, false, false, true) == 0)
                        log_debug("Lib install: '%s'", p);
        }

        return ret;
}

static char *get_real_file(const char *src, bool fullyresolve)
{
        struct stat sb;
        ssize_t linksz;
        char linktarget[PATH_MAX + 1];
        _cleanup_free_ char *fullsrcpath_a = NULL;
        const char *fullsrcpath;
        _cleanup_free_ char *abspath = NULL;

        if (sysrootdirlen) {
                if (strncmp(src, sysrootdir, sysrootdirlen) == 0) {
                        fullsrcpath = src;
                } else {
                        _asprintf(&fullsrcpath_a, "%s/%s",
                                  (sysrootdirlen ? sysrootdir : ""),
                                  (src[0] == '/' ? src + 1 : src));
                        fullsrcpath = fullsrcpath_a;
                }
        } else {
                fullsrcpath = src;
        }

        log_debug("get_real_file('%s')", fullsrcpath);

        if (lstat(fullsrcpath, &sb) < 0)
                return NULL;

        switch (sb.st_mode &S_IFMT) {
        case S_IFDIR:
        case S_IFREG:
                return strdup(fullsrcpath);
        case S_IFLNK:
                break;
        default:
                return NULL;
        }

        linksz = readlink(fullsrcpath, linktarget, sizeof(linktarget));
        if (linksz < 0)
                return NULL;
        linktarget[linksz] = '\0';

        log_debug("get_real_file: readlink('%s') returns '%s'", fullsrcpath, linktarget);

        if (streq(fullsrcpath, linktarget)) {
                log_error("ERROR: '%s' is pointing to itself", fullsrcpath);
                return NULL;
        }

        if (linktarget[0] == '/') {
                _asprintf(&abspath, "%s%s", (sysrootdirlen ? sysrootdir : ""), linktarget);
        } else {
                _asprintf(&abspath, "%.*s/%s", (int)dir_len(fullsrcpath), fullsrcpath, linktarget);
        }

        if (fullyresolve) {
                struct stat st;
                if (lstat(abspath, &st) < 0) {
                        if (errno != ENOENT) {
                                return NULL;
                        }
                }
                if (S_ISLNK(st.st_mode)) {
                        return get_real_file(abspath, fullyresolve);
                }
        }

        log_debug("get_real_file('%s') => '%s'", src, abspath);
        return TAKE_PTR(abspath);
}

/* Check that the ELF header (ehdr) matches the other given ELF header in bits,
   endianness, OS ABI, and soname, where B is 64 or 32 bit. The SYSV and GNU OS
   ABIs are compatible, so allow either. Returns libpath if there is a match. */
#define CHECK_LIB_MATCH_FOR_BITS(B, match) do { \
        if (!match) \
                goto finish; \
\
        Elf##B##_Ehdr *ehdr = (Elf##B##_Ehdr *)map; \
        if (ehdr->e_ident[EI_CLASS] == match->e_ident[EI_CLASS] && \
            ehdr->e_ident[EI_DATA] == match->e_ident[EI_DATA] && \
            (ehdr->e_ident[EI_OSABI] == match->e_ident[EI_OSABI] || \
             ehdr->e_ident[EI_OSABI] == ELFOSABI_SYSV || \
             ehdr->e_ident[EI_OSABI] == ELFOSABI_GNU) && \
            ehdr->e_machine == match->e_machine) { \
                if (strcmp(basename, soname) == 0) { \
                        munmap(map, sb.st_size); \
                        return libpath; \
                } \
        } \
} while (0)

/* Check that the given path (dirname + basename) with the given soname matches
   the given (64 or 32 bit) ELF header. Returns the path if there is a match. */
static char *check_lib_match(const char *dirname, const char *basename, const char *soname, const Elf64_Ehdr *match64,
                             const Elf32_Ehdr *match32)
{
        char *libpath = NULL;
        _asprintf(&libpath, "%s/%s", dirname, basename);

        _cleanup_close_ int fd = open(libpath, O_RDONLY | O_CLOEXEC);
        if (fd < 0)
                goto finish2;

        struct stat sb;
        if (fstat(fd, &sb) < 0)
                goto finish2;

        void *map = mmap(NULL, sb.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
        if (map == MAP_FAILED)
                goto finish2;

        unsigned char *e_ident = (unsigned char *)map;
        if (e_ident[EI_MAG0] != ELFMAG0 ||
            e_ident[EI_MAG1] != ELFMAG1 ||
            e_ident[EI_MAG2] != ELFMAG2 ||
            e_ident[EI_MAG3] != ELFMAG3)
                goto finish;

        switch (e_ident[EI_CLASS]) {
        case ELFCLASS32:
                CHECK_LIB_MATCH_FOR_BITS(32, match32);
                break;
        case ELFCLASS64:
                CHECK_LIB_MATCH_FOR_BITS(64, match64);
                break;
        }

finish:
        munmap(map, sb.st_size);
finish2:
        free(libpath);
        return NULL;
}

/* Search the given library directory (within the sysroot) for a library
   matching the given soname and (64 or 32 bit) ELF header. Returns the path
   (with the sysroot) if there is a match. */
static char *search_libdir(const char *libdir, const char *soname, const Elf64_Ehdr *match64, const Elf32_Ehdr *match32)
{
        _cleanup_free_ char *sysroot_libdir;
        _asprintf(&sysroot_libdir, "%s%s", sysrootdir ?: "", libdir);
        log_debug("Searching '%s' to find %s", sysroot_libdir, soname);

        /* First check for a filename matching the soname. This is likely to
           succeed and is very much faster than checking the sonames of every
           library in the directory below. */
        char *res = check_lib_match(sysroot_libdir, soname, soname, match64, match32);
        if (res)
                return res;

        _cleanup_closedir_ DIR *dirp = opendir(sysroot_libdir);
        if (!dirp)
                return NULL;

        struct dirent *entry;
        while ((entry = readdir(dirp)) != NULL) {
                if (entry->d_type != DT_REG && entry->d_type != DT_LNK)
                        continue;

                if (fnmatch("*.so*", entry->d_name, 0) != 0)
                        continue;

                res = check_lib_match(sysroot_libdir, entry->d_name, soname, match64, match32);
                if (res)
                        return res;
        }

        return NULL;
}

/* Read the given ldconf file(s) (within the sysroot, can be a glob pattern) to
   search for a library matching the given soname and (64 or 32 bit) ELF header.
   Returns the path (with the sysroot) if there is a match. */
static char *search_via_ldconf(const char *conf_pattern, const char *soname, const Elf64_Ehdr *match64,
                               const Elf32_Ehdr *match32)
{
        char line[PATH_MAX];
        const char *include_prefix = "include ";
        size_t include_prefix_len = strlen(include_prefix);

        _cleanup_free_ char *sysroot_conf_pattern = NULL;
        _asprintf(&sysroot_conf_pattern, "%s%s", sysrootdir ?: "", conf_pattern);
        log_debug("Reading '%s' to find %s", sysroot_conf_pattern, soname);

        _cleanup_globfree_ glob_t globbuf;
        if (glob(sysroot_conf_pattern, 0, NULL, &globbuf) == 0) {
                for (size_t i = 0; i < globbuf.gl_pathc; i++) {
                        char *conf_path = globbuf.gl_pathv[i];
                        _cleanup_fclose_ FILE *file = fopen(conf_path, "r");
                        if (!file) {
                                log_error("ERROR: cannot open '%s': %m", conf_path);
                                return NULL;
                        }

                        const char *conf_dir = dirname(conf_path);

                        while (fgets(line, sizeof(line), file)) {
                                /* glibc and musl separate with newlines. */
                                char *newline = strchr(line, '\n');
                                if (newline)
                                        *newline = '\0';

                                /* musl also separates with colons. Do the same
                                   with glibc for simplicity. */
                                char *colon = strchr(line, ':');
                                if (colon)
                                        *colon = '\0';

                                /* Ignore any comments. */
                                char *comment = strchr(line, '#');
                                if (comment)
                                        *comment = '\0';

                                /* Skip empty lines. */
                                if (line[0] == '\0')
                                        continue;

                                char *result;
                                if (strncmp(line, include_prefix, include_prefix_len) == 0) {
                                        const char *include_path = line + include_prefix_len;
                                        /* include directives can be absolute or
                                           relative. Prepend the current file's
                                           directory if relative. */
                                        if (include_path[0] == '/') {
                                                result = search_via_ldconf(include_path, soname, match64, match32);
                                        } else {
                                                _cleanup_free_ char *abs_include_path = NULL;
                                                _asprintf(&abs_include_path, "%s/%s", conf_dir + sysrootdirlen, include_path);
                                                result = search_via_ldconf(abs_include_path, soname, match64, match32);
                                        }
                                } else {
                                        result = search_libdir(line, soname, match64, match32);
                                }
                                if (result)
                                        return result;
                        }
                }
        }

        return NULL;
}

/* Expand $ORIGIN and $LIB variables in the given R(UN)PATH entry. $ORIGIN
   expands to the directory of the given src path. $LIB expands to lib if
   match64 is NULL or lib64 otherwise. Returns a newly allocated string even if
   no expansion was necessary. */
static char *expand_runpath(char *input, const char *src, const Elf64_Ehdr *match64)
{
        regex_t regex;
        regmatch_t rmatch[3]; /* 0: full match, 1: without brackets, 2: with brackets */

        if (regcomp(&regex, "\\$([A-Z]+|\\{([A-Z]+)\\})", REG_EXTENDED) != 0) {
                log_error("ERROR: Could not compile RUNPATH regex");
                return NULL;
        }

        char *result = NULL, *current = input;
        int offset = 0;

        while (regexec(&regex, current + offset, 3, rmatch, 0) == 0) {
                char *varname = NULL;
                _cleanup_free_ char *varval = NULL;
                size_t varname_len, varval_len;

                /* Determine which group matched, with or without brackets. */
                int rgroup = rmatch[1].rm_so != -1 ? 1 : 2;
                varname_len = rmatch[rgroup].rm_eo - rmatch[rgroup].rm_so;
                varname = current + offset + rmatch[rgroup].rm_so;

                if (strncmp(varname, "ORIGIN", varname_len) == 0) {
                        varval = dirname_malloc(src);
                } else if (strncmp(varname, "LIB", varname_len) == 0) {
                        varval = strdup(match64 ? "lib64" : "lib");
                } else {
                        /* If the variable is unrecognised, leave it as-is. */
                        offset += rmatch[0].rm_eo;
                        continue;
                }

                if (!varval)
                        goto oom;

                varval_len = strlen(varval);
                size_t prefix_len = offset + rmatch[0].rm_so;
                size_t suffix_len = strlen(current) - (offset + rmatch[0].rm_eo);

                char *replaced = realloc(result, prefix_len + varval_len + suffix_len + 1);
                if (!replaced)
                        goto oom;

                result = replaced;
                strcpy(result + prefix_len, varval);
                strcpy(result + prefix_len + varval_len, current + offset + rmatch[0].rm_eo);

                current = result;
                offset = prefix_len + varval_len;
        }

        regfree(&regex);
        return result ?: strdup(current);

oom:
        log_error("Out of memory");
        free(result);
        regfree(&regex);
        return NULL;
}

/* Adjust the endianness of the given value of the given SIZE using ELF header
   ehdr. The size sadly cannot be determined automatically using sizeof because
   that is expanded using the C compiler rather than the preprocessor. */
#define ELF_BYTESWAP(SIZE, value) (ehdr->e_ident[EI_DATA] == ELFDATA2MSB ? be##SIZE##toh(value) : le##SIZE##toh(value))

/* Get a pointer to the ELF header map's section header string table, where B is
   64 or 32 bit. Sanity checks the ELF structure to avoid crashes. */
#define PARSE_ELF_START(B, map) \
        Elf##B##_Ehdr *ehdr = (Elf##B##_Ehdr *)map; \
\
        if (sizeof(Elf##B##_Ehdr) > src_len || \
            ELF_BYTESWAP(B, ehdr->e_shoff) > src_len || \
            ELF_BYTESWAP(16, ehdr->e_shstrndx) >= ELF_BYTESWAP(16, ehdr->e_shnum)) \
                break; \
\
        Elf##B##_Shdr *shdr = (Elf##B##_Shdr *)((char *)map + ELF_BYTESWAP(B, ehdr->e_shoff)); \
        const char *shstrtab = (char *)map + ELF_BYTESWAP(B, shdr[ELF_BYTESWAP(16, ehdr->e_shstrndx)].sh_offset);

/* Expand the R(UN)PATH of the ELF header map and search it for a library
   matching soname and match64/match32. map must point to the same header as
   match64/match32. Returns the path (with the sysroot) if there is a match. */
#define FIND_LIBRARY_RUNPATH_FOR_BITS(B, map) do { \
        PARSE_ELF_START(B, map); \
        bool seen_runpath = false; \
\
        for (size_t i = 0; i < ELF_BYTESWAP(16, ehdr->e_shnum); i++) { \
                if (strcmp(&shstrtab[ELF_BYTESWAP(32, shdr[i].sh_name)], ".dynamic") != 0) \
                        continue; \
\
                Elf##B##_Dyn *dyn = (Elf##B##_Dyn *)((char *)map + ELF_BYTESWAP(B, shdr[i].sh_offset)); \
                for (Elf##B##_Dyn *d = dyn; ELF_BYTESWAP(32, d->d_tag) != DT_NULL; d++) { \
                        if (ELF_BYTESWAP(B, d->d_tag) == DT_RUNPATH) \
                                seen_runpath = true; /* RUNPATH has precedence over RPATH. */ \
                        else if (seen_runpath || ELF_BYTESWAP(B, d->d_tag) != DT_RPATH) \
                                continue; \
\
                        char *runpath = (char *)map + ELF_BYTESWAP(B, shdr[ELF_BYTESWAP(32, shdr[i].sh_link)].sh_offset) + ELF_BYTESWAP(B, d->d_un.d_val); \
                        _cleanup_free_ char *expanded = expand_runpath(runpath, src, match64); \
                        if (!expanded) \
                                continue; \
\
                        for (char *token = strtok(expanded, ":"); token; token = strtok(NULL, ":")) { \
                                char *res = search_libdir(token, soname, match64, match32); \
                                if (res) \
                                        return res; \
                        } \
                } \
        } \
} while (0)

/* Given an soname and (64 or 32 bit) ELF header, search for a matching library
   in the R(UN)PATH of that header, the directories referenced by ldconf files,
   and some default locations. src must be the path (with the sysroot) to the
   ELF file and src_len must be that file's length in bytes. Returns the path
   (with the sysroot) if there is a match. */
static char *find_library(const char *soname, const char *src, size_t src_len, const Elf64_Ehdr *match64,
                          const Elf32_Ehdr *match32)
{
        if (match64)
                FIND_LIBRARY_RUNPATH_FOR_BITS(64, match64);
        else if (match32)
                FIND_LIBRARY_RUNPATH_FOR_BITS(32, match32);

        /* There is no definitive way to determine the libc so just check for
           musl and glibc ldconf files. musl hardcodes its default locations. It
           is impossible to determine glibc's default locations, but this set is
           practically universal. It is safe to check lib64 for 32-bit libraries
           because we include the class (64-bit or 32-bit) when matching. */
        return search_via_ldconf("/etc/ld-musl-*.path", soname, match64, match32) ?:
               search_via_ldconf("/etc/ld.so.conf", soname, match64, match32) ?:
               search_libdir("/lib64", soname, match64, match32) ?:
               search_libdir("/usr/lib64", soname, match64, match32) ?:
               search_libdir("/usr/local/lib64", soname, match64, match32) ?:
               search_libdir("/lib", soname, match64, match32) ?:
               search_libdir("/usr/lib", soname, match64, match32) ?:
               search_libdir("/usr/local/lib", soname, match64, match32);
}

#ifdef HAVE_SYSTEMD

/* Parse the given .note.dlopen JSON (https://systemd.io/ELF_DLOPEN_METADATA/)
   in the given note index and find each dependent library, ensuring it matches
   the given (64 or 32 bit) ELF header. Dependencies are skipped if the
   corresponding feature is present in omit_dlopen_features or missing from
   add_dlopen_features. Those hashmaps are keyed by wildcard patterns, which are
   compared against the source's soname or filename. Each library found is added
   to deps. Dependencies already found in this chain must be given in pdeps.
   Failure to parse the JSON or find a library is considered non-fatal. */
static void resolve_deps_dlopen_parse_json(Hashmap *pdeps, Hashmap *deps, const char *src_soname, char *fullsrcpath,
                                           size_t src_len, const char *json, size_t note_idx, const Elf64_Ehdr *match64, const Elf32_Ehdr *match32)
{
        _cleanup_(sd_json_variant_unrefp) sd_json_variant *dlopen_json = NULL;
        if (sd_json_parse(json, 0, &dlopen_json, NULL, NULL) != 0 || !sd_json_variant_is_array(dlopen_json)) {
                log_warning("WARNING: .note.dlopen entry #%zd is not a JSON array in '%s'", note_idx, fullsrcpath);
                return;
        }

        for (size_t entry_idx = 0; entry_idx < sd_json_variant_elements(dlopen_json); entry_idx++) {
                sd_json_variant *entry = sd_json_variant_by_index(dlopen_json, entry_idx);
                sd_json_variant *feature_json = sd_json_variant_by_key(entry, "feature");

                if (feature_json && sd_json_variant_is_string(feature_json)) {
                        const char *feature = sd_json_variant_string(feature_json);
                        const char *name = src_soname ?: basename(fullsrcpath);

                        Iterator i;
                        char ***features;
                        const char *pattern;
                        HASHMAP_FOREACH_KEY(features, pattern, omit_dlopen_features, i) {
                                if (fnmatch(pattern, name, 0) == 0 && strv_contains(*features, feature))
                                        goto skip;
                        }
                        int skip = 1;
                        HASHMAP_FOREACH_KEY(features, pattern, add_dlopen_features, i) {
                                if (fnmatch(pattern, name, 0) == 0 && strv_contains(*features, feature))
                                        skip = 0;
                        }
                        if (skip)
                                goto skip;
                }

                sd_json_variant *sonames = sd_json_variant_by_key(entry, "soname");
                if (!sonames || !sd_json_variant_is_array(sonames)) {
                        log_warning("WARNING: soname array missing from .note.dlopen entry #%zd.%zd in '%s'", note_idx, entry_idx, fullsrcpath);
                        return;
                }

                for (size_t soname_idx = 0; soname_idx < sd_json_variant_elements(sonames); soname_idx++) {
                        sd_json_variant *soname_json = sd_json_variant_by_index(sonames, soname_idx);
                        if (!sd_json_variant_is_string(soname_json)) {
                                log_warning("WARNING: soname #%zd of .note.dlopen entry #%zd.%zd is not a string in '%s'", soname_idx, note_idx,
                                            entry_idx, fullsrcpath);
                                return;
                        }

                        const char *soname = sd_json_variant_string(soname_json);
                        if (hashmap_get(pdeps, soname))
                                continue;

                        char *library = find_library(soname, fullsrcpath, src_len, match64, match32);
                        if (!library || hashmap_put_strdup_key(deps, soname, library) < 0)
                                log_warning("WARNING: could not locate dlopen dependency %s requested by '%s'", soname, fullsrcpath);
                }
skip:
        }
}

/* Given the ELF header map, also represented by match64/match32 and where B is
   64 or 32 bit, check .note.dlopen entries for dependencies. See above. */
#define RESOLVE_DEPS_DLOPEN_FOR_BITS(B, match64, match32) do { \
        PARSE_ELF_START(B, map); \
        const char *soname = NULL; \
        size_t note_idx = -1; \
\
        for (size_t i = 0; !soname && i < ELF_BYTESWAP(16, ehdr->e_shnum); i++) { \
                if ((char*)&shdr[i] < (char*)map || (char*)&shdr[i] + sizeof(Elf##B##_Shdr) > (char*)map + src_len) \
                        break; \
                if (strcmp(&shstrtab[ELF_BYTESWAP(32, shdr[i].sh_name)], ".dynamic") != 0) \
                        continue; \
\
                Elf##B##_Dyn *dyn = (Elf##B##_Dyn *)((char *)map + ELF_BYTESWAP(B, shdr[i].sh_offset)); \
                if ((char *)dyn < (char *)map || (char *)dyn > (char *)map + src_len) \
                        break; \
\
                for (Elf##B##_Dyn *d = dyn; !soname && ELF_BYTESWAP(32, d->d_tag) != DT_NULL; d++) { \
                        if ((char *)d < (char *)map || (char *)d + sizeof(Elf##B##_Dyn) > (char *)map + src_len) \
                                break; \
                        if (ELF_BYTESWAP(B, d->d_tag) != DT_SONAME) \
                                continue; \
\
                        soname = (char *)map + ELF_BYTESWAP(B, shdr[ELF_BYTESWAP(32, shdr[i].sh_link)].sh_offset) + ELF_BYTESWAP(B, d->d_un.d_val); \
                        if ((char *)soname < (char *)map || (char *)soname > (char *)map + src_len) { \
                                soname = NULL; \
                                break; \
                        } \
                } \
        } \
\
        for (size_t i = 0; i < ELF_BYTESWAP(16, ehdr->e_shnum); i++) { \
                if ((char*)shdr + i * sizeof(Elf##B##_Shdr) > (char*)map + src_len) \
                        break; \
                if (strcmp(&shstrtab[ELF_BYTESWAP(32, shdr[i].sh_name)], ".note.dlopen") != 0) \
                        continue; \
\
                const char *note_offset = (char *)map + ELF_BYTESWAP(B, shdr[i].sh_offset); \
                const char *note_end = note_offset + ELF_BYTESWAP(32, shdr[i].sh_size); \
\
                if (note_offset < (char*)map || note_end > (char*)map + src_len || note_end < note_offset) \
                        continue; \
\
                while (note_offset < note_end) { \
                        Elf##B##_Nhdr *nhdr = (Elf##B##_Nhdr *)note_offset; \
                        note_offset += sizeof(Elf##B##_Nhdr); \
\
                        /* We don't need the name, checking the type is enough. */ \
                        note_offset += (ELF_BYTESWAP(32, nhdr->n_namesz) + 3) & ~3; /* Align to 4 bytes */ \
\
                        const char *note_desc = note_offset; \
                        note_offset += (ELF_BYTESWAP(32, nhdr->n_descsz) + 3) & ~3; /* Align to 4 bytes */ \
                        if (note_offset > (char*)map + src_len) \
                                break; \
\
                        if (ELF_BYTESWAP(32, nhdr->n_type) != 0x407c0c0a) \
                                continue; \
\
                        note_idx++; \
                        resolve_deps_dlopen_parse_json(pdeps, deps, soname, fullsrcpath, src_len, note_desc, note_idx, match64, match32); \
                } \
        } \
} while (0)

#endif

/* Given the ELF header map, also represented by match64/match32 and where B is
   64 or 32 bit, check PT_INTERP and DT_NEEDED entries for dependencies. */
#define RESOLVE_DEPS_NEEDED_FOR_BITS(B, match64, match32) do { \
        PARSE_ELF_START(B, map); \
\
        if (ELF_BYTESWAP(16, ehdr->e_type) == ET_EXEC || ELF_BYTESWAP(16, ehdr->e_type) == ET_DYN) { \
                for (size_t ph_idx = 0; ph_idx < ELF_BYTESWAP(16, ehdr->e_phnum); ph_idx++) { \
                        Elf##B##_Phdr *phdr = (Elf##B##_Phdr *)((char *)map + ELF_BYTESWAP(B, ehdr->e_phoff) + ph_idx * ELF_BYTESWAP(16, ehdr->e_phentsize)); \
                        if ((char *)phdr < (char *)map || (char *)phdr + sizeof(Elf##B##_Phdr) > (char *)map + src_len) \
                                break; \
                        if (ELF_BYTESWAP(32, phdr->p_type) != PT_INTERP) \
                                continue; \
\
                        const char *interpreter = (const char *)map + ELF_BYTESWAP(B, phdr->p_offset); \
                        if (interpreter < (char *)map || interpreter > (char *)map + src_len) \
                                break; \
                        if (hashmap_get(pdeps, interpreter)) \
                                continue; \
\
                        char *value = strdup(interpreter); \
                        if (!value || hashmap_put_strdup_key(deps, interpreter, value) < 0) { \
                                log_error("ERROR: could not handle interpreter for '%s'", fullsrcpath); \
                                ret = -1; \
                        } \
                        break; \
                } \
        } \
\
        for (size_t i = 0; i < ELF_BYTESWAP(16, ehdr->e_shnum); i++) { \
                if ((char*)&shdr[i] < (char*)map || (char*)&shdr[i] + sizeof(Elf##B##_Shdr) > (char*)map + src_len) \
                        break; \
                if (strcmp(&shstrtab[ELF_BYTESWAP(32, shdr[i].sh_name)], ".dynamic") != 0) \
                        continue; \
\
                Elf##B##_Dyn *dyn = (Elf##B##_Dyn *)((char *)map + ELF_BYTESWAP(B, shdr[i].sh_offset)); \
                if ((char *)dyn < (char *)map || (char *)dyn > (char *)map + src_len) \
                        break; \
\
                for (Elf##B##_Dyn *d = dyn; ELF_BYTESWAP(32, d->d_tag) != DT_NULL; d++) { \
                        if ((char *)d < (char *)map || (char *)d + sizeof(Elf##B##_Dyn) > (char *)map + src_len) \
                                break; \
                        if (ELF_BYTESWAP(B, d->d_tag) != DT_NEEDED) \
                                continue; \
\
                        const char *soname = (char *)map + ELF_BYTESWAP(B, shdr[ELF_BYTESWAP(32, shdr[i].sh_link)].sh_offset) + ELF_BYTESWAP(B, d->d_un.d_val); \
                        if ((char *)soname < (char *)map || (char *)soname > (char *)map + src_len) \
                                break; \
                        if (hashmap_get(pdeps, soname)) \
                                continue; \
\
                        char* library = find_library(soname, fullsrcpath, src_len, match64, match32); \
                        if (!library || hashmap_put_strdup_key(deps, soname, library) < 0) { \
                                log_error("ERROR: could not locate dependency %s requested by '%s'", soname, fullsrcpath); \
                                ret = -1; \
                        } \
                } \
        } \
} while (0)

/* Recursively check the given file for dependencies and install them. pdeps is
   for dependencies already found in this chain and should initially be NULL.
   Both ELF binaries and scripts with shebangs are handled. */
static int resolve_deps(const char *src, Hashmap *pdeps)
{
        _cleanup_free_ char *fullsrcpath = NULL;

        fullsrcpath = get_real_file(src, true);
        log_debug("resolve_deps('%s') -> get_real_file('%s', true) = '%s'", src, src, fullsrcpath);
        if (!fullsrcpath)
                return 0;

        _cleanup_close_ int fd = open(fullsrcpath, O_RDONLY | O_CLOEXEC);
        if (fd < 0) {
                log_error("ERROR: cannot open '%s': %m", fullsrcpath);
                return -errno;
        }

        struct stat sb;
        if (fstat(fd, &sb) < 0) {
                log_error("ERROR: cannot stat '%s': %m", fullsrcpath);
                return -errno;
        }

        size_t src_len = sb.st_size;
        void *map = mmap(NULL, src_len, PROT_READ, MAP_PRIVATE, fd, 0);
        if (map == MAP_FAILED) {
                log_error("ERROR: cannot mmap '%s': %m", fullsrcpath);
                return -errno;
        }

        /* It would be easiest to blindly install dependencies as we find them
           depth-first, but this does not work in practise. We need to track
           which dependencies are already found to avoid loops. We also need to
           install them breadth-first because of how RUNPATH works. systemd is a
           good example. libsystemd-core depends on libsystemd-shared. Neither
           is in the default library path, but libsystemd-core lacks a RUNPATH,
           so it cannot find libsystemd-shared by itself. See for yourself with
           ldd. It must be found in the context of an executable with a RUNPATH
           that also depends on libsystemd-shared, such as systemd-executor. The
           RUNPATH only applies to direct dependencies, not subdependencies, so
           libsystemd-shared needs to be found as a direct dependency of
           systemd-executor before we check libsystemd-core's dependencies.
           Therefore, pdeps above holds the dependencies we have already found,
           deps holds the dependencies found in this iteration, and ndeps is
           used to combine them into the next iteration's pdeps. */
        Hashmap *ndeps = hashmap_new(string_hash_func, string_compare_func);
        Hashmap  *deps = hashmap_new(string_hash_func, string_compare_func);
        int ret = 0;

        if (!ndeps || !deps) {
                ret = -1;
                goto finish;
        }

        char *shebang = (char *)map;
        if (shebang[0] == '#' && shebang[1] == '!') {
                char *p, *q;
                for (p = &shebang[2]; *p && isspace(*p); p++) ;
                for (q = p; *q && (!isspace(*q)); q++) ;
                char *interpreter = strndup(p, q - p);
                log_debug("Script install: '%s'", interpreter);
                ret = dracut_install(interpreter, interpreter, false, true, false);
                free(interpreter);
                goto finish;
        }

        unsigned char *e_ident = (unsigned char *)map;
        if (e_ident[EI_MAG0] != ELFMAG0 ||
            e_ident[EI_MAG1] != ELFMAG1 ||
            e_ident[EI_MAG2] != ELFMAG2 ||
            e_ident[EI_MAG3] != ELFMAG3)
                goto finish;

        switch (e_ident[EI_CLASS]) {
        case ELFCLASS32:
                RESOLVE_DEPS_NEEDED_FOR_BITS(32, NULL, ehdr);
#ifdef HAVE_SYSTEMD
                RESOLVE_DEPS_DLOPEN_FOR_BITS(32, NULL, ehdr);
#endif
                break;
        case ELFCLASS64:
                RESOLVE_DEPS_NEEDED_FOR_BITS(64, ehdr, NULL);
#ifdef HAVE_SYSTEMD
                RESOLVE_DEPS_DLOPEN_FOR_BITS(64, ehdr, NULL);
#endif
                break;
        default:
                log_error("ERROR: '%s' has an unknown ELF class", fullsrcpath);
                ret = -1;
        }

        if (hashmap_merge(ndeps, pdeps) < 0 || hashmap_merge(ndeps, deps) < 0) {
                ret = -1;
                goto finish;
        }

        char *key, *library;
        Iterator i;
        HASHMAP_FOREACH(library, deps, i) {
                ret += library_install(src, library);
                ret += resolve_deps(library, ndeps);
        }

finish:
        munmap(map, src_len);
        hashmap_free(ndeps);

        HASHMAP_FOREACH(library, deps, i) {
                item_free(library);
        }

        while ((key = hashmap_steal_first_key(deps)))
                item_free(key);

        hashmap_free(deps);
        return ret;
}

/* Install ".<filename>.hmac" file for FIPS self-checks */
static int hmac_install(const char *src, const char *dst, const char *hmacpath)
{
        _cleanup_free_ char *srchmacname = NULL;
        _cleanup_free_ char *dsthmacname = NULL;

        size_t dlen = dir_len(src);

        if (endswith(src, ".hmac"))
                return 0;

        if (!hmacpath) {
                hmac_install(src, dst, "/lib/fipscheck");
                hmac_install(src, dst, "/lib64/fipscheck");
                hmac_install(src, dst, "/lib/hmaccalc");
                hmac_install(src, dst, "/lib64/hmaccalc");
        }

        if (hmacpath) {
                _asprintf(&srchmacname, "%s/%s.hmac", hmacpath, &src[dlen + 1]);
                _asprintf(&dsthmacname, "%s/%s.hmac", hmacpath, &src[dlen + 1]);
        } else {
                _asprintf(&srchmacname, "%.*s/.%s.hmac", (int)dlen,         src, &src[dlen + 1]);
                _asprintf(&dsthmacname, "%.*s/.%s.hmac", (int)dir_len(dst), dst, &src[dlen + 1]);
        }
        log_debug("hmac cp '%s' '%s'", srchmacname, dsthmacname);
        dracut_install(srchmacname, dsthmacname, false, false, true);
        return 0;
}

void mark_hostonly(const char *path)
{
        if (arg_dry_run)
                return;

        _cleanup_free_ char *fulldstpath = NULL;
        _cleanup_fclose_ FILE *f = NULL;

        _asprintf(&fulldstpath, "%s/lib/dracut/hostonly-files", destrootdir);

        f = fopen(fulldstpath, "a");

        if (f == NULL) {
                log_error("Could not open '%s' for writing.", fulldstpath);
                return;
        }

        fprintf(f, "%s\n", path);
}

void dracut_log_cp(const char *path)
{
        int ret;
        ret = fprintf(logfile_f, "%s\n", path);
        if (ret < 0)
                log_error("Could not append '%s' to logfile '%s': %m", path, logfile);
}

static bool check_hashmap(Hashmap *hm, const char *item)
{
        char *existing;
        existing = hashmap_get(hm, item);
        if (existing) {
                if (strcmp(existing, item) == 0) {
                        return true;
                }
        }
        return false;
}

static int dracut_mkdir(const char *src)
{
        if (arg_dry_run)
                return 0;

        _cleanup_free_ char *parent = NULL;
        char *path;
        struct stat sb;

        parent = strdup(src);
        if (!parent)
                return 1;

        path = parent[0] == '/' ? parent + 1 : parent;
        while (path) {
                path = strstr(path, "/");
                if (path)
                        *path = '\0';

                if (stat(parent, &sb) == 0) {
                        if (!S_ISDIR(sb.st_mode)) {
                                log_error("%s exists but is not a directory!", parent);
                                return 1;
                        }
                } else if (errno != ENOENT) {
                        log_error("ERROR: stat '%s': %m", parent);
                        return 1;
                } else {
                        if (mkdir(parent, 0755) < 0) {
                                log_error("ERROR: mkdir '%s': %m", parent);
                                return 1;
                        }
                }

                if (path) {
                        *path = '/';
                        path++;
                }
        }

        return 0;
}

static int dracut_install(const char *orig_src, const char *orig_dst, bool isdir, bool resolvedeps, bool hashdst)
{
        struct stat sb;
        _cleanup_free_ char *fullsrcpath = NULL;
        _cleanup_free_ char *fulldstpath = NULL;
        _cleanup_free_ char *fulldstdir = NULL;
        int ret;
        bool src_islink = false;
        bool src_isdir = false;
        mode_t src_mode = 0;
        char *hash_path = NULL;
        const char *src, *dst;

        if (sysrootdirlen) {
                if (strncmp(orig_src, sysrootdir, sysrootdirlen) == 0) {
                        src = orig_src + sysrootdirlen;
                        fullsrcpath = strdup(orig_src);
                } else {
                        src = orig_src;
                        _asprintf(&fullsrcpath, "%s%s", sysrootdir, src);
                }
                if (strncmp(orig_dst, sysrootdir, sysrootdirlen) == 0)
                        dst = orig_dst + sysrootdirlen;
                else
                        dst = orig_dst;
        } else {
                src = orig_src;
                fullsrcpath = strdup(src);
                dst = orig_dst;
        }

        log_debug("dracut_install('%s', '%s', %d, %d, %d)", src, dst, isdir, resolvedeps, hashdst);

        if (check_hashmap(items_failed, src)) {
                log_debug("hash hit items_failed for '%s'", src);
                return 1;
        }

        if (hashdst && check_hashmap(items, dst)) {
                log_debug("hash hit items for '%s'", dst);
                return 0;
        }

        if (lstat(fullsrcpath, &sb) < 0) {
                if (!isdir) {
                        hash_path = strdup(src);
                        if (!hash_path)
                                return -ENOMEM;
                        hashmap_put(items_failed, hash_path, hash_path);
                        /* src does not exist */
                        return 1;
                }
        } else {
                src_islink = S_ISLNK(sb.st_mode);
                src_isdir = S_ISDIR(sb.st_mode);
                src_mode = sb.st_mode;
        }

        /* The install hasn't succeeded yet, but mark this item as successful
           now. If it fails once, it will probably fail every time. Doing this
           could avoid dependency loops, but this is actually handled elsewhere.
           It also avoids an elusive memory leak detected by valgrind. */
        hash_path = strdup(dst);
        if (!hash_path)
                return -ENOMEM;
        hashmap_put(items, hash_path, hash_path);

        _asprintf(&fulldstpath, "%s/%s", destrootdir, (dst[0] == '/' ? (dst + 1) : dst));

        errno = ENOENT;
        ret = arg_dry_run ? -1 : stat(fulldstpath, &sb);

        if (ret == 0) {
                if (src_isdir && !S_ISDIR(sb.st_mode)) {
                        log_error("dest dir '%s' already exists but is not a directory", fulldstpath);
                        return 1;
                }

                if (resolvedeps && S_ISREG(sb.st_mode) && (sb.st_mode & (S_IXUSR | S_IXGRP | S_IXOTH))) {
                        log_debug("'%s' already exists, but checking for any deps", fulldstpath);
                        if (sysrootdirlen && (strncmp(fulldstpath, sysrootdir, sysrootdirlen) == 0))
                                ret = resolve_deps(fulldstpath + sysrootdirlen, NULL);
                        else
                                ret = resolve_deps(fullsrcpath, NULL);
                } else
                        log_debug("'%s' already exists", fulldstpath);
        } else {
                if (errno != ENOENT) {
                        log_error("ERROR: stat '%s': %m", fulldstpath);
                        return 1;
                }

                /* check destination directory */
                fulldstdir = strndup(fulldstpath, dir_len(fulldstpath));
                if (!fulldstdir) {
                        log_error("Out of memory!");
                        return 1;
                }

                ret = arg_dry_run ? 0 : access(fulldstdir, F_OK);

                if (ret < 0) {
                        _cleanup_free_ char *dname = NULL;

                        if (errno != ENOENT) {
                                log_error("ERROR: stat '%s': %m", fulldstdir);
                                return 1;
                        }
                        /* create destination directory */
                        log_debug("dest dir '%s' does not exist", fulldstdir);

                        dname = strndup(dst, dir_len(dst));
                        if (!dname)
                                return 1;
                        ret = dracut_install(dname, dname, true, false, true);

                        if (ret != 0) {
                                log_error("ERROR: failed to create directory '%s'", fulldstdir);
                                return 1;
                        }
                }

                if (src_isdir) {
                        log_info("mkdir '%s'", fulldstpath);
                        return dracut_mkdir(fulldstpath);
                }

                /* ready to install src */

                if (src_islink) {
                        _cleanup_free_ char *abspath = NULL;

                        abspath = get_real_file(src, false);

                        if (abspath == NULL)
                                return 1;

                        if (dracut_install(abspath, abspath, false, resolvedeps, hashdst)) {
                                log_debug("'%s' install error", abspath);
                                return 1;
                        }

                        if (!arg_dry_run && faccessat(AT_FDCWD, abspath, F_OK, AT_SYMLINK_NOFOLLOW) != 0) {
                                log_debug("lstat '%s': %m", abspath);
                                return 1;
                        }

                        if (!arg_dry_run && faccessat(AT_FDCWD, fulldstpath, F_OK, AT_SYMLINK_NOFOLLOW) != 0) {
                                _cleanup_free_ char *absdestpath = NULL;

                                _asprintf(&absdestpath, "%s/%s", destrootdir,
                                          (abspath[0] == '/' ? (abspath + 1) : abspath) + sysrootdirlen);

                                ln_r(absdestpath, fulldstpath);
                        }

                        if (arg_hmac) {
                                /* copy .hmac files also */
                                hmac_install(src, dst, NULL);
                        }

                        return 0;
                }

                if (src_mode & (S_IXUSR | S_IXGRP | S_IXOTH)) {
                        if (resolvedeps) {
                                /* ensure fullsrcpath contains sysrootdir */
                                if (sysrootdirlen && (strncmp(fullsrcpath, sysrootdir, sysrootdirlen) == 0))
                                        ret += resolve_deps(fullsrcpath + sysrootdirlen, NULL);
                                else
                                        ret += resolve_deps(fullsrcpath, NULL);
                        }
                        if (arg_hmac) {
                                /* copy .hmac files also */
                                hmac_install(src, dst, NULL);
                        }
                }

                log_debug("dracut_install ret = %d", ret);

                if (arg_hostonly && !arg_module)
                        mark_hostonly(dst);

                if (isdir) {
                        log_info("mkdir '%s'", fulldstpath);
                        ret += dracut_mkdir(fulldstpath);
                } else {
                        log_info("cp '%s' '%s'", fullsrcpath, fulldstpath);
                        ret += cp(fullsrcpath, fulldstpath);
                }
        }

        if (ret == 0) {
                if (arg_dry_run)
                        puts(src);

                if (logfile_f)
                        dracut_log_cp(src);
        }

        log_debug("dracut_install ret = %d", ret);

        return ret;
}

static void usage(int status)
{
        /*                                                                                */
        printf("Usage: %s -D DESTROOTDIR [-r SYSROOTDIR] [OPTION]... -a SOURCE...\n"
               "or: %s -D DESTROOTDIR [-r SYSROOTDIR] [OPTION]... SOURCE DEST\n"
               "or: %s -D DESTROOTDIR [-r SYSROOTDIR] [OPTION]... -m KERNELMODULE [KERNELMODULE …]\n"
               "\n"
               "Install SOURCE (from rootfs or SYSROOTDIR) to DEST in DESTROOTDIR with all needed dependencies.\n"
               "\n"
               "  KERNELMODULE can have the format:\n"
               "     <absolute path> with a leading /\n"
               "     =<kernel subdir>[/<kernel subdir>…] like '=drivers/hid'\n"
               "     <module name>\n"
               "\n"
               "  -D --destrootdir  Install all files to DESTROOTDIR as the root\n"
               "  -r --sysrootdir   Install all files from SYSROOTDIR\n"
               "  -a --all          Install all SOURCE arguments to DESTROOTDIR\n"
               "  -o --optional     If SOURCE does not exist, do not fail\n"
               "  -d --dir          SOURCE is a directory\n"
               "  -l --ldd          Also install shebang executables and libraries\n"
               "  -L --logdir <DIR> Log files, which were installed from the host to <DIR>\n"
               "  -n --dry-run      Don't actually copy files, just show what would be installed\n"
               "  -R --resolvelazy  Only install shebang executables and libraries\n"
               "                     for all SOURCE files\n"
               "  -H --hostonly     Mark all SOURCE files as hostonly\n\n"
               "  -f --fips         Also install all '.SOURCE.hmac' files\n"
               "\n"
               "  --module,-m       Install kernel modules, instead of files\n"
               "  --kerneldir       Specify the kernel module directory\n"
               "                     (default: /lib/modules/$(uname -r))\n"
               "  --firmwaredirs    Specify the firmware directory search path with : separation\n"
               "                     (default: $DRACUT_FIRMWARE_PATH, otherwise kernel-compatible\n"
               "                      $(</sys/module/firmware_class/parameters/path),\n"
               "                      /lib/firmware/updates/$(uname -r), /lib/firmware/updates\n"
               "                      /lib/firmware/$(uname -r), /lib/firmware)\n"
               "  --silent          Don't display error messages for kernel module install\n"
               "  --modalias        Only generate module list from /sys/devices modalias list\n"
               "  -o --optional     If kernel module does not exist, do not fail\n"
               "  -p --mod-filter-path      Filter kernel modules by path regexp\n"
               "  -P --mod-filter-nopath    Exclude kernel modules by path regexp\n"
               "  -s --mod-filter-symbol    Filter kernel modules by symbol regexp\n"
               "  -S --mod-filter-nosymbol  Exclude kernel modules by symbol regexp\n"
               "  -N --mod-filter-noname    Exclude kernel modules by name regexp\n"
               "\n"
               "     --json-supported  Show whether this build supports JSON\n"
               "  -v --verbose         Show more output\n"
               "     --debug           Show debug output\n"
               "     --version         Show package version\n"
               "  -h --help            Show this help\n"
               "\n", program_invocation_short_name, program_invocation_short_name, program_invocation_short_name);
        exit(status);
}

static int parse_argv(int argc, char *argv[])
{
        int c;

        enum {
                ARG_VERSION = 0x100,
                ARG_SILENT,
                ARG_MODALIAS,
                ARG_KERNELDIR,
                ARG_FIRMWAREDIRS,
                ARG_DEBUG,
                ARG_JSON_SUPPORTED,
        };

        static struct option const options[] = {
                {"help", no_argument, NULL, 'h'},
                {"version", no_argument, NULL, ARG_VERSION},
                {"dir", no_argument, NULL, 'd'},
                {"debug", no_argument, NULL, ARG_DEBUG},
                {"verbose", no_argument, NULL, 'v'},
                {"ldd", no_argument, NULL, 'l'},
                {"resolvelazy", no_argument, NULL, 'R'},
                {"optional", no_argument, NULL, 'o'},
                {"hostonly", no_argument, NULL, 'H'},
                {"all", no_argument, NULL, 'a'},
                {"module", no_argument, NULL, 'm'},
                {"fips", no_argument, NULL, 'f'},
                {"destrootdir", required_argument, NULL, 'D'},
                {"sysrootdir", required_argument, NULL, 'r'},
                {"logdir", required_argument, NULL, 'L'},
                {"mod-filter-path", required_argument, NULL, 'p'},
                {"mod-filter-nopath", required_argument, NULL, 'P'},
                {"mod-filter-symbol", required_argument, NULL, 's'},
                {"mod-filter-nosymbol", required_argument, NULL, 'S'},
                {"mod-filter-noname", required_argument, NULL, 'N'},
                {"modalias", no_argument, NULL, ARG_MODALIAS},
                {"silent", no_argument, NULL, ARG_SILENT},
                {"kerneldir", required_argument, NULL, ARG_KERNELDIR},
                {"firmwaredirs", required_argument, NULL, ARG_FIRMWAREDIRS},
                {"json-supported", no_argument, NULL, ARG_JSON_SUPPORTED},
                {"dry-run", no_argument, NULL, 'n'},
                {NULL, 0, NULL, 0}
        };

        while ((c = getopt_long(argc, argv, "madfhlL:oD:Hr:Rp:P:s:S:N:v", options, NULL)) != -1) {
                switch (c) {
                case ARG_VERSION:
                        puts(PROGRAM_VERSION_STRING);
                        return 0;
                case 'd':
                        arg_createdir = true;
                        break;
                case ARG_DEBUG:
                        arg_loglevel = LOG_DEBUG;
                        break;
                case ARG_SILENT:
                        arg_silent = true;
                        break;
                case ARG_MODALIAS:
                        arg_modalias = true;
                        return 1;
                        break;
                case 'v':
                        arg_loglevel = LOG_INFO;
                        break;
                case 'o':
                        arg_optional = true;
                        break;
                case 'l':
                        arg_resolvedeps = true;
                        break;
                case 'R':
                        arg_resolvelazy = true;
                        break;
                case 'a':
                        arg_all = true;
                        break;
                case 'm':
                        arg_module = true;
                        break;
                case 'D':
                        destrootdir = optarg;
                        break;
                case 'r':
                        sysrootdir = optarg;
                        sysrootdirlen = strlen(sysrootdir);
                        /* ignore trailing '/' */
                        if (sysrootdir[sysrootdirlen-1] == '/')
                                sysrootdirlen--;
                        break;
                case 'p':
                        if (regcomp(&mod_filter_path, optarg, REG_NOSUB | REG_EXTENDED) != 0) {
                                log_error("Module path filter %s is not a regular expression", optarg);
                                exit(EXIT_FAILURE);
                        }
                        arg_mod_filter_path = true;
                        break;
                case 'P':
                        if (regcomp(&mod_filter_nopath, optarg, REG_NOSUB | REG_EXTENDED) != 0) {
                                log_error("Module path filter %s is not a regular expression", optarg);
                                exit(EXIT_FAILURE);
                        }
                        arg_mod_filter_nopath = true;
                        break;
                case 's':
                        if (regcomp(&mod_filter_symbol, optarg, REG_NOSUB | REG_EXTENDED) != 0) {
                                log_error("Module symbol filter %s is not a regular expression", optarg);
                                exit(EXIT_FAILURE);
                        }
                        arg_mod_filter_symbol = true;
                        break;
                case 'S':
                        if (regcomp(&mod_filter_nosymbol, optarg, REG_NOSUB | REG_EXTENDED) != 0) {
                                log_error("Module symbol filter %s is not a regular expression", optarg);
                                exit(EXIT_FAILURE);
                        }
                        arg_mod_filter_nosymbol = true;
                        break;
                case 'N':
                        if (regcomp(&mod_filter_noname, optarg, REG_NOSUB | REG_EXTENDED) != 0) {
                                log_error("Module symbol filter %s is not a regular expression", optarg);
                                exit(EXIT_FAILURE);
                        }
                        arg_mod_filter_noname = true;
                        break;
                case 'L':
                        logdir = optarg;
                        break;
                case ARG_KERNELDIR:
                        kerneldir = optarg;
                        arg_kerneldir = true;
                        break;
                case ARG_FIRMWAREDIRS:
                        firmwaredirs = strv_split(optarg, ":");
                        break;
                case 'f':
                        arg_hmac = true;
                        break;
                case 'H':
                        arg_hostonly = true;
                        break;
                case 'h':
                        usage(EXIT_SUCCESS);
                        break;
                case ARG_JSON_SUPPORTED:
#ifdef HAVE_SYSTEMD
                        puts("JSON is supported");
                        return 0;
#else
                        puts("JSON is not supported");
                        return -1;
#endif
                case 'n':
                        arg_dry_run = true;
                        break;
                default:
                        usage(EXIT_FAILURE);
                }
        }

        if (arg_loglevel >= 0) {
                log_set_max_level(arg_loglevel);
        }

        struct utsname buf = {0};
        if (!kerneldir) {
                uname(&buf);
                _asprintf(&kerneldir, "/lib/modules/%s", buf.release);
        }

        if (arg_modalias) {
                return 1;
        }

        if (arg_module) {
                if (!firmwaredirs) {
                        char *path = getenv("DRACUT_FIRMWARE_PATH");

                        if (path) {
                                log_debug("DRACUT_FIRMWARE_PATH=%s", path);
                                firmwaredirs = strv_split(path, ":");
                        } else {
                                if (!*buf.release)
                                        uname(&buf);

                                char fw_path_para[PATH_MAX + 1] = "";
                                int path = open("/sys/module/firmware_class/parameters/path", O_RDONLY | O_CLOEXEC);
                                if (path != -1) {
                                        ssize_t rd = read(path, fw_path_para, PATH_MAX);
                                        if (rd != -1)
                                                fw_path_para[rd - 1] = '\0';
                                        close(path);
                                }
                                char uk[22 + sizeof(buf.release)], fk[14 + sizeof(buf.release)];
                                sprintf(uk, "/lib/firmware/updates/%s", buf.release);
                                sprintf(fk, "/lib/firmware/%s", buf.release);
                                firmwaredirs = strv_new(STRV_IFNOTNULL(*fw_path_para ? fw_path_para : NULL),
                                                        uk,
                                                        "/lib/firmware/updates",
                                                        fk,
                                                        "/lib/firmware",
                                                        NULL);
                        }
                }
        }

        if (!optind || optind == argc) {
                if (!arg_optional) {
                        log_error("No SOURCE argument given");
                        usage(EXIT_FAILURE);
                } else {
                        exit(EXIT_SUCCESS);
                }
        }

        return 1;
}

static int resolve_lazy(int argc, char **argv)
{
        int i;
        size_t destrootdirlen = strlen(destrootdir);
        int ret = 0;
        char *item;
        for (i = 0; i < argc; i++) {
                const char *src = argv[i];
                char *p = argv[i];

                log_debug("resolve_deps('%s')", src);

                if (strstr(src, destrootdir)) {
                        p = &argv[i][destrootdirlen];
                }

                if (check_hashmap(items, p)) {
                        continue;
                }

                item = strdup(p);
                hashmap_put(items, item, item);

                ret += resolve_deps(src, NULL);
        }
        return ret;
}

static char **find_binary(const char *src)
{
        char **ret = NULL;
        char **q;
        char *newsrc = NULL;

        STRV_FOREACH(q, pathdirs) {
                char *fullsrcpath;

                _asprintf(&newsrc, "%s/%s", *q, src);

                fullsrcpath = get_real_file(newsrc, false);
                if (!fullsrcpath) {
                        log_debug("get_real_file(%s) not found", newsrc);
                        free(newsrc);
                        newsrc = NULL;
                        continue;
                }

                if (faccessat(AT_FDCWD, fullsrcpath, F_OK, AT_SYMLINK_NOFOLLOW) != 0) {
                        log_debug("lstat(%s) != 0", fullsrcpath);
                        free(newsrc);
                        newsrc = NULL;
                        free(fullsrcpath);
                        fullsrcpath = NULL;
                        continue;
                }

                strv_push(&ret, newsrc);

                free(fullsrcpath);
                fullsrcpath = NULL;
        };

        if (ret) {
                STRV_FOREACH(q, ret) {
                        log_debug("find_binary(%s) == %s", src, *q);
                }
        }

        return ret;
}

static int install_one(const char *src, const char *dst)
{
        int r = EXIT_SUCCESS;
        int ret = 0;

        if (strchr(src, '/') == NULL) {
                char **p = find_binary(src);
                if (p) {
                        char **q = NULL;
                        STRV_FOREACH(q, p) {
                                char *newsrc = *q;
                                log_debug("dracut_install '%s' '%s'", newsrc, dst);
                                ret = dracut_install(newsrc, dst, arg_createdir, arg_resolvedeps, true);
                                if (ret == 0) {
                                        log_debug("dracut_install '%s' '%s' OK", newsrc, dst);
                                }
                        }
                        strv_free(p);
                } else {
                        ret = -1;
                }
        } else {
                ret = dracut_install(src, dst, arg_createdir, arg_resolvedeps, true);
        }

        if ((ret != 0) && (!arg_optional)) {
                log_error("ERROR: installing '%s' to '%s'", src, dst);
                r = EXIT_FAILURE;
        }

        return r;
}

static int install_all(int argc, char **argv)
{
        int r = EXIT_SUCCESS;
        int i;
        for (i = 0; i < argc; i++) {
                int ret = 0;
                log_debug("Handle '%s'", argv[i]);

                if (strchr(argv[i], '/') == NULL) {
                        char **p = find_binary(argv[i]);
                        if (p) {
                                char **q = NULL;
                                STRV_FOREACH(q, p) {
                                        char *newsrc = *q;
                                        log_debug("dracut_install '%s'", newsrc);
                                        ret = dracut_install(newsrc, newsrc, arg_createdir, arg_resolvedeps, true);
                                        if (ret == 0) {
                                                log_debug("dracut_install '%s' OK", newsrc);
                                        }
                                }
                                strv_free(p);
                        } else {
                                ret = -1;
                        }

                } else {
                        if (strchr(argv[i], '*') == NULL) {
                                ret = dracut_install(argv[i], argv[i], arg_createdir, arg_resolvedeps, true);
                        } else {
                                _cleanup_free_ char *realsrc = NULL;
                                _cleanup_globfree_ glob_t globbuf;

                                _asprintf(&realsrc, "%s%s", sysrootdir ? sysrootdir : "", argv[i]);

                                ret = glob(realsrc, 0, NULL, &globbuf);
                                if (ret == 0) {
                                        size_t j;

                                        for (j = 0; j < globbuf.gl_pathc; j++) {
                                                ret |= dracut_install(globbuf.gl_pathv[j] + sysrootdirlen,
                                                                      globbuf.gl_pathv[j] + sysrootdirlen,
                                                                      arg_createdir, arg_resolvedeps, true);
                                        }
                                }
                        }
                }

                if ((ret != 0) && (!arg_optional)) {
                        log_error("ERROR: installing '%s'", argv[i]);
                        r = EXIT_FAILURE;
                }
        }
        return r;
}

static int install_firmware_fullpath(const char *fwpath, bool maybe_compressed)
{
        const char *fw = fwpath;
        _cleanup_free_ char *fwpath_compressed = NULL;
        int ret;
        if (access(fwpath, F_OK) != 0) {
                if (!maybe_compressed)
                        return 1;

                _asprintf(&fwpath_compressed, "%s.zst", fwpath);
                if (access(fwpath_compressed, F_OK) != 0) {
                        strcpy(fwpath_compressed + strlen(fwpath) + 1, "xz");
                        if (access(fwpath_compressed, F_OK) != 0) {
                                log_debug("stat(%s) != 0", fwpath);
                                return 1;
                        }
                }
                fw = fwpath_compressed;
        }
        ret = dracut_install(fw, fw, false, false, true);
        if (ret == 0) {
                log_debug("dracut_install '%s' OK", fwpath);
        }
        return ret;
}

static bool install_firmware_glob(const char *fwpath)
{
        size_t i;
        _cleanup_globfree_ glob_t globbuf;
        bool found = false;
        int ret;

        glob(fwpath, 0, NULL, &globbuf);
        for (i = 0; i < globbuf.gl_pathc; i++) {
                ret = install_firmware_fullpath(globbuf.gl_pathv[i], false);
                if (ret == 0)
                        found = true;
        }

        return found;
}

static int install_firmware(struct kmod_module *mod)
{
        struct kmod_list *l = NULL;
        _cleanup_kmod_module_info_free_list_ struct kmod_list *list = NULL;
        int ret;
        char **q;

        ret = kmod_module_get_info(mod, &list);
        if (ret < 0) {
                log_error("could not get modinfo from '%s': %s\n", kmod_module_get_name(mod), strerror(-ret));
                return ret;
        }
        kmod_list_foreach(l, list) {
                const char *key = kmod_module_info_get_key(l);
                const char *value = NULL;
                bool found_this = false;

                if (!streq("firmware", key))
                        continue;

                value = kmod_module_info_get_value(l);
                log_debug("Firmware %s", value);
                STRV_FOREACH(q, firmwaredirs) {
                        _cleanup_free_ char *fwpath = NULL;

                        _asprintf(&fwpath, "%s/%s", *q, value);

                        if (strpbrk(value, "*?[") != NULL
                            && access(fwpath, F_OK) != 0) {
                                found_this = install_firmware_glob(fwpath);
                                if (!found_this) {
                                        _cleanup_free_ char *fwpath_compressed = NULL;

                                        _asprintf(&fwpath_compressed, "%s.zst", fwpath);
                                        found_this = install_firmware_glob(fwpath_compressed);
                                        if (!found_this) {
                                                strcpy(fwpath_compressed + strlen(fwpath) + 1, "xz");
                                                found_this = install_firmware_glob(fwpath_compressed);
                                        }
                                }
                        } else {
                                ret = install_firmware_fullpath(fwpath, true);
                                if (ret == 0)
                                        found_this = true;
                        }
                }
                if (!found_this) {
                        /* firmware path was not found in any firmwaredirs */
                        log_info("Missing firmware %s for kernel module %s",
                                 value, kmod_module_get_name(mod));
                }
        }
        return 0;
}

static bool check_module_symbols(struct kmod_module *mod)
{
        struct kmod_list *itr = NULL;
        _cleanup_kmod_module_dependency_symbols_free_list_ struct kmod_list *deplist = NULL;

        if (!arg_mod_filter_symbol && !arg_mod_filter_nosymbol)
                return true;

        if (kmod_module_get_dependency_symbols(mod, &deplist) < 0) {
                log_debug("kmod_module_get_dependency_symbols failed");
                if (arg_mod_filter_symbol)
                        return false;
                return true;
        }

        if (arg_mod_filter_nosymbol) {
                kmod_list_foreach(itr, deplist) {
                        const char *symbol = kmod_module_symbol_get_symbol(itr);
                        // log_debug("Checking symbol %s", symbol);
                        if (regexec(&mod_filter_nosymbol, symbol, 0, NULL, 0) == 0) {
                                log_debug("Module %s: symbol %s matched exclusion filter", kmod_module_get_name(mod),
                                          symbol);
                                return false;
                        }
                }
        }

        if (arg_mod_filter_symbol) {
                kmod_list_foreach(itr, deplist) {
                        const char *symbol = kmod_module_dependency_symbol_get_symbol(itr);
                        // log_debug("Checking symbol %s", symbol);
                        if (regexec(&mod_filter_symbol, symbol, 0, NULL, 0) == 0) {
                                log_debug("Module %s: symbol %s matched inclusion filter", kmod_module_get_name(mod),
                                          symbol);
                                return true;
                        }
                }
                return false;
        }

        return true;
}

static bool check_module_path(const char *path)
{
        if (arg_mod_filter_nopath && (regexec(&mod_filter_nopath, path, 0, NULL, 0) == 0)) {
                log_debug("Path %s matched exclusion filter", path);
                return false;
        }

        if (arg_mod_filter_path && (regexec(&mod_filter_path, path, 0, NULL, 0) != 0)) {
                log_debug("Path %s matched inclusion filter", path);
                return false;
        }
        return true;
}

static int find_kmod_module_from_sysfs_driver(struct kmod_ctx *ctx, const char *sysfs_node, int sysfs_node_len,
                                              struct kmod_module **module)
{
        char mod_path[PATH_MAX], mod_realpath[PATH_MAX];
        const char *mod_name;
        if ((size_t)snprintf(mod_path, sizeof(mod_path), "%.*s/driver/module",
                             sysfs_node_len, sysfs_node) >= sizeof(mod_path))
                return -1;

        if (realpath(mod_path, mod_realpath) == NULL)
                return -1;

        if ((mod_name = basename(mod_realpath)) == NULL)
                return -1;

        return kmod_module_new_from_name(ctx, mod_name, module);
}

static int find_kmod_module_from_sysfs_modalias(struct kmod_ctx *ctx, const char *sysfs_node, int sysfs_node_len,
                                                struct kmod_list **modules)
{
        char modalias_path[PATH_MAX];
        if ((size_t)snprintf(modalias_path, sizeof(modalias_path), "%.*s/modalias", sysfs_node_len,
                             sysfs_node) >= sizeof(modalias_path))
                return -1;

        _cleanup_close_ int modalias_file = -1;
        if ((modalias_file = open(modalias_path, O_RDONLY | O_CLOEXEC)) == -1)
                return 0;

        char alias[page_size()];
        ssize_t len = read(modalias_file, alias, sizeof(alias));
        alias[len - 1] = '\0';

        void *list;

        if (hashmap_get_exists(modalias_to_kmod, alias, &list) == 1) {
                *modules = list;
                return 0;
        }

        int ret = kmod_module_new_from_lookup(ctx, alias, modules);
        if (!ret) {
                hashmap_put(modalias_to_kmod, strdup(alias), *modules);
        }

        return ret;
}

static int find_modules_from_sysfs_node(struct kmod_ctx *ctx, const char *sysfs_node, Hashmap *modules)
{
        _cleanup_kmod_module_unref_ struct kmod_module *drv = NULL;
        struct kmod_list *list = NULL;
        struct kmod_list *l = NULL;

        if (find_kmod_module_from_sysfs_driver(ctx, sysfs_node, strlen(sysfs_node), &drv) >= 0) {
                char *module = strdup(kmod_module_get_name(drv));
                if (hashmap_put(modules, module, module) < 0)
                        free(module);
                return 0;
        }

        if (find_kmod_module_from_sysfs_modalias(ctx, sysfs_node, strlen(sysfs_node), &list) >= 0) {
                kmod_list_foreach(l, list) {
                        struct kmod_module *mod = kmod_module_get_module(l);
                        char *module = strdup(kmod_module_get_name(mod));
                        kmod_module_unref(mod);

                        if (hashmap_put(modules, module, module) < 0)
                                free(module);
                }
        }

        return 0;
}

static void find_suppliers_for_sys_node(Hashmap *suppliers, const char *node_path_raw,
                                        size_t node_path_len)
{
        char node_path[PATH_MAX];
        char real_path[PATH_MAX];

        memcpy(node_path, node_path_raw, node_path_len);
        node_path[node_path_len] = '\0';

        DIR *d;
        struct dirent *dir;
        while (realpath(node_path, real_path) != NULL && strcmp(real_path, "/sys/devices")) {
                d = opendir(node_path);
                if (d) {
                        size_t real_path_len = strlen(real_path);
                        while ((dir = readdir(d)) != NULL) {
                                if (strstr(dir->d_name, "supplier:platform") != NULL) {
                                        if ((size_t)snprintf(real_path + real_path_len, sizeof(real_path) - real_path_len, "/%s/supplier",
                                                             dir->d_name) < sizeof(real_path) - real_path_len) {
                                                char *real_supplier_path = realpath(real_path, NULL);
                                                if (real_supplier_path != NULL)
                                                        if (hashmap_put(suppliers, real_supplier_path, real_supplier_path) < 0)
                                                                free(real_supplier_path);
                                        }
                                }
                        }
                        closedir(d);
                }
                strcat(node_path, "/.."); // Also find suppliers of parents
                char *parent_path = realpath(node_path, NULL);
                if (parent_path != NULL)
                        if (hashmap_put(suppliers, parent_path, parent_path) < 0)
                                free(parent_path);
        }
}

static void find_suppliers(struct kmod_ctx *ctx)
{
        _cleanup_fts_close_ FTS *fts;
        char *paths[] = { "/sys/devices/platform", NULL };
        fts = fts_open(paths, FTS_NOSTAT | FTS_PHYSICAL, NULL);

        for (FTSENT *ftsent = fts_read(fts); ftsent != NULL; ftsent = fts_read(fts)) {
                if (strcmp(ftsent->fts_name, "modalias") == 0) {
                        _cleanup_kmod_module_unref_ struct kmod_module *drv = NULL;
                        struct kmod_list *list = NULL;
                        struct kmod_list *l;

                        if (find_kmod_module_from_sysfs_driver(ctx, ftsent->fts_parent->fts_path, ftsent->fts_parent->fts_pathlen, &drv) >= 0) {
                                const char *name = kmod_module_get_name(drv);
                                Hashmap *suppliers = hashmap_get(modules_suppliers, name);
                                if (suppliers == NULL) {
                                        suppliers = hashmap_new(string_hash_func, string_compare_func);
                                        hashmap_put(modules_suppliers, strdup(name), suppliers);
                                }

                                find_suppliers_for_sys_node(suppliers, ftsent->fts_parent->fts_path, ftsent->fts_parent->fts_pathlen);

                                /* Skip modalias check */
                                continue;
                        }

                        if (find_kmod_module_from_sysfs_modalias(ctx, ftsent->fts_parent->fts_path, ftsent->fts_parent->fts_pathlen, &list) < 0)
                                continue;

                        kmod_list_foreach(l, list) {
                                _cleanup_kmod_module_unref_ struct kmod_module *mod = kmod_module_get_module(l);
                                const char *name = kmod_module_get_name(mod);
                                Hashmap *suppliers = hashmap_get(modules_suppliers, name);
                                if (suppliers == NULL) {
                                        suppliers = hashmap_new(string_hash_func, string_compare_func);
                                        hashmap_put(modules_suppliers, strdup(name), suppliers);
                                }

                                find_suppliers_for_sys_node(suppliers, ftsent->fts_parent->fts_path, ftsent->fts_parent->fts_pathlen);
                        }
                }
        }
}

static Hashmap *find_suppliers_paths_for_module(const char *module)
{
        return hashmap_get(modules_suppliers, module);
}

static int install_dependent_module(struct kmod_ctx *ctx, struct kmod_module *mod, Hashmap *suppliers_paths, int *err)
{
        const char *path = NULL;
        const char *name = NULL;

        path = kmod_module_get_path(mod);

        if (path == NULL)
                return 0;

        if (check_hashmap(items_failed, path))
                return -1;

        if (check_hashmap(items, &path[kerneldirlen])) {
                return 0;
        }

        name = kmod_module_get_name(mod);

        if (arg_mod_filter_noname && (regexec(&mod_filter_noname, name, 0, NULL, 0) == 0)) {
                return 0;
        }

        *err = dracut_install(path, &path[kerneldirlen], false, false, true);
        if (*err == 0) {
                _cleanup_kmod_module_unref_list_ struct kmod_list *modlist = NULL;
                _cleanup_kmod_module_unref_list_ struct kmod_list *modpre = NULL;
                _cleanup_kmod_module_unref_list_ struct kmod_list *modpost = NULL;
#ifdef CONFIG_WEAKDEP
                _cleanup_kmod_module_unref_list_ struct kmod_list *modweak = NULL;
#endif
                log_debug("dracut_install '%s' '%s' OK", path, &path[kerneldirlen]);
                install_firmware(mod);
                modlist = kmod_module_get_dependencies(mod);
                *err = install_dependent_modules(ctx, modlist, suppliers_paths);
                if (*err == 0) {
                        *err = kmod_module_get_softdeps(mod, &modpre, &modpost);
                        if (*err == 0) {
                                int r;
                                *err = install_dependent_modules(ctx, modpre, NULL);
                                r = install_dependent_modules(ctx, modpost, NULL);
                                *err = *err ? : r;
                        }
                }
#ifdef CONFIG_WEAKDEP
                if (*err == 0) {
                        *err = kmod_module_get_weakdeps(mod, &modweak);
                        if (*err == 0)
                                *err = install_dependent_modules(ctx, modweak, NULL);
                }
#endif
        } else {
                log_error("dracut_install '%s' '%s' ERROR", path, &path[kerneldirlen]);
        }

        return 0;
}

static int install_dependent_modules(struct kmod_ctx *ctx, struct kmod_list *modlist, Hashmap *suppliers_paths)
{
        struct kmod_list *itr = NULL;
        int ret = 0;

        kmod_list_foreach(itr, modlist) {
                _cleanup_kmod_module_unref_ struct kmod_module *mod = NULL;
                mod = kmod_module_get_module(itr);
                if (install_dependent_module(ctx, mod, find_suppliers_paths_for_module(kmod_module_get_name(mod)), &ret))
                        return -1;
        }

        const char *supplier_path;
        Iterator i;
        HASHMAP_FOREACH(supplier_path, suppliers_paths, i) {
                if (check_hashmap(processed_suppliers, supplier_path))
                        continue;

                char *path = strdup(supplier_path);
                hashmap_put(processed_suppliers, path, path);

                _cleanup_destroy_hashmap_ Hashmap *modules = hashmap_new(string_hash_func, string_compare_func);
                find_modules_from_sysfs_node(ctx, supplier_path, modules);

                _cleanup_destroy_hashmap_ Hashmap *suppliers = hashmap_new(string_hash_func, string_compare_func);
                find_suppliers_for_sys_node(suppliers, supplier_path, strlen(supplier_path));

                if (!hashmap_isempty(modules)) { // Supplier is a module
                        const char *module;
                        Iterator j;
                        HASHMAP_FOREACH(module, modules, j) {
                                _cleanup_kmod_module_unref_ struct kmod_module *mod = NULL;
                                if (!kmod_module_new_from_name(ctx, module, &mod)) {
                                        if (install_dependent_module(ctx, mod, suppliers, &ret))
                                                return -1;
                                }
                        }
                } else { // Supplier is builtin
                        install_dependent_modules(ctx, NULL, suppliers);
                }
        }

        return ret;
}

static int install_module(struct kmod_ctx *ctx, struct kmod_module *mod)
{
        int ret = 0;
        _cleanup_kmod_module_unref_list_ struct kmod_list *modlist = NULL;
        _cleanup_kmod_module_unref_list_ struct kmod_list *modpre = NULL;
        _cleanup_kmod_module_unref_list_ struct kmod_list *modpost = NULL;
#ifdef CONFIG_WEAKDEP
        _cleanup_kmod_module_unref_list_ struct kmod_list *modweak = NULL;
#endif
        const char *path = NULL;
        const char *name = NULL;

        name = kmod_module_get_name(mod);

        path = kmod_module_get_path(mod);
        if (!path) {
                log_debug("dracut_install '%s' is a builtin kernel module", name);
                return 0;
        }

        if (arg_mod_filter_noname && (regexec(&mod_filter_noname, name, 0, NULL, 0) == 0)) {
                log_debug("dracut_install '%s' is excluded", name);
                return 0;
        }

        if (arg_hostonly && !check_hashmap(modules_loaded, name)) {
                log_debug("dracut_install '%s' not hostonly", name);
                return 0;
        }

        if (check_hashmap(items_failed, path))
                return -1;

        if (check_hashmap(items, path))
                return 0;

        if (!check_module_path(path) || !check_module_symbols(mod)) {
                log_debug("No symbol or path match for '%s'", path);
                return 1;
        }

        log_debug("dracut_install '%s' '%s'", path, &path[kerneldirlen]);

        ret = dracut_install(path, &path[kerneldirlen], false, false, true);
        if (ret == 0) {
                log_debug("dracut_install '%s' OK", kmod_module_get_name(mod));
        } else if (!arg_optional) {
                if (!arg_silent)
                        log_error("dracut_install '%s' ERROR", kmod_module_get_name(mod));
                return ret;
        }
        install_firmware(mod);

        Hashmap *suppliers = find_suppliers_paths_for_module(name);
        modlist = kmod_module_get_dependencies(mod);
        ret = install_dependent_modules(ctx, modlist, suppliers);

        if (ret == 0) {
                ret = kmod_module_get_softdeps(mod, &modpre, &modpost);
                if (ret == 0) {
                        int r;
                        ret = install_dependent_modules(ctx, modpre, NULL);
                        r = install_dependent_modules(ctx, modpost, NULL);
                        ret = ret ? : r;
                }
        }
#ifdef CONFIG_WEAKDEP
        if (ret == 0) {
                ret = kmod_module_get_weakdeps(mod, &modweak);
                if (ret == 0)
                        ret = install_dependent_modules(ctx, modweak, NULL);
        }
#endif

        return ret;
}

static int modalias_list(struct kmod_ctx *ctx)
{
        int err;
        struct kmod_list *loaded_list = NULL;
        struct kmod_list *l = NULL;
        struct kmod_list *itr = NULL;
        _cleanup_fts_close_ FTS *fts = NULL;

        {
                char *paths[] = { "/sys/devices", NULL };
                fts = fts_open(paths, FTS_NOCHDIR | FTS_NOSTAT, NULL);
        }
        for (FTSENT *ftsent = fts_read(fts); ftsent != NULL; ftsent = fts_read(fts)) {
                _cleanup_fclose_ FILE *f = NULL;
                _cleanup_kmod_module_unref_list_ struct kmod_list *list = NULL;

                int err;

                char alias[2048] = {0};
                size_t len;

                if (strncmp("modalias", ftsent->fts_name, 8) != 0)
                        continue;
                if (!(f = fopen(ftsent->fts_accpath, "r")))
                        continue;

                if (!fgets(alias, sizeof(alias), f))
                        continue;

                len = strlen(alias);

                if (len == 0)
                        continue;

                if (alias[len - 1] == '\n')
                        alias[len - 1] = 0;

                err = kmod_module_new_from_lookup(ctx, alias, &list);
                if (err < 0)
                        continue;

                kmod_list_foreach(l, list) {
                        struct kmod_module *mod = kmod_module_get_module(l);
                        char *name = strdup(kmod_module_get_name(mod));
                        kmod_module_unref(mod);
                        hashmap_put(modules_loaded, name, name);
                }
        }

        err = kmod_module_new_from_loaded(ctx, &loaded_list);
        if (err < 0) {
                errno = err;
                log_error("Could not get list of loaded modules: %m. Switching to non-hostonly mode.");
                arg_hostonly = false;
        } else {
                kmod_list_foreach(itr, loaded_list) {
                        _cleanup_kmod_module_unref_list_ struct kmod_list *modlist = NULL;

                        struct kmod_module *mod = kmod_module_get_module(itr);
                        char *name = strdup(kmod_module_get_name(mod));
                        hashmap_put(modules_loaded, name, name);
                        kmod_module_unref(mod);

                        /* also put the modules from the new kernel in the hashmap,
                         * which resolve the name as an alias, in case a kernel module is
                         * renamed.
                         */
                        err = kmod_module_new_from_lookup(ctx, name, &modlist);
                        if (err < 0)
                                continue;
                        if (!modlist)
                                continue;
                        kmod_list_foreach(l, modlist) {
                                mod = kmod_module_get_module(l);
                                char *name = strdup(kmod_module_get_name(mod));
                                hashmap_put(modules_loaded, name, name);
                                kmod_module_unref(mod);
                        }
                }
                kmod_module_unref_list(loaded_list);
        }
        return 0;
}

static int install_modules(int argc, char **argv)
{
        _cleanup_kmod_unref_ struct kmod_ctx *ctx = NULL;
        struct kmod_list *itr = NULL;

        struct kmod_module *mod = NULL, *mod_o = NULL;

        const char *abskpath = NULL;
        char *p;
        int i;
        int modinst = 0;

        ctx = kmod_new(kerneldir, NULL);
        kmod_load_resources(ctx);
        abskpath = kmod_get_dirname(ctx);

        p = strstr(abskpath, "/lib/modules/");
        if (p != NULL)
                kerneldirlen = p - abskpath;

        modules_suppliers = hashmap_new(string_hash_func, string_compare_func);
        find_suppliers(ctx);

        if (arg_hostonly) {
                char *modalias_file;
                modalias_file = getenv("DRACUT_KERNEL_MODALIASES");

                if (modalias_file == NULL) {
                        modalias_list(ctx);
                } else {
                        _cleanup_fclose_ FILE *f = NULL;
                        if ((f = fopen(modalias_file, "r"))) {
                                char name[2048];

                                while (!feof(f)) {
                                        size_t len;
                                        char *dupname = NULL;

                                        if (!(fgets(name, sizeof(name), f)))
                                                continue;
                                        len = strlen(name);

                                        if (len == 0)
                                                continue;

                                        if (name[len - 1] == '\n')
                                                name[len - 1] = 0;

                                        log_debug("Adding module '%s' to hostonly module list", name);
                                        dupname = strdup(name);
                                        hashmap_put(modules_loaded, dupname, dupname);
                                }
                        }
                }

        }

        for (i = 0; i < argc; i++) {
                int r = 0;
                int ret = -1;
                log_debug("Handle module '%s'", argv[i]);

                if (argv[i][0] == '/') {
                        _cleanup_kmod_module_unref_list_ struct kmod_list *modlist = NULL;
                        _cleanup_free_ const char *modname = NULL;

                        r = kmod_module_new_from_path(ctx, argv[i], &mod_o);
                        if (r < 0) {
                                log_debug("Failed to lookup modules path '%s': %m", argv[i]);
                                if (!arg_optional)
                                        return -ENOENT;
                                continue;
                        }
                        /* Check, if we have to load another module with that name instead */
                        modname = strdup(kmod_module_get_name(mod_o));

                        if (!modname) {
                                if (!arg_optional) {
                                        if (!arg_silent)
                                                log_error("Failed to get name for module '%s'", argv[i]);
                                        return -ENOENT;
                                }
                                log_info("Failed to get name for module '%s'", argv[i]);
                                continue;
                        }

                        r = kmod_module_new_from_lookup(ctx, modname, &modlist);
                        kmod_module_unref(mod_o);
                        mod_o = NULL;

                        if (r < 0) {
                                if (!arg_optional) {
                                        if (!arg_silent)
                                                log_error("3 Failed to lookup alias '%s': %d", modname, r);
                                        return -ENOENT;
                                }
                                log_info("3 Failed to lookup alias '%s': %d", modname, r);
                                continue;
                        }
                        if (!modlist) {
                                if (!arg_optional) {
                                        if (!arg_silent)
                                                log_error("Failed to find module '%s' %s", modname, argv[i]);
                                        return -ENOENT;
                                }
                                log_info("Failed to find module '%s' %s", modname, argv[i]);
                                continue;
                        }
                        kmod_list_foreach(itr, modlist) {
                                mod = kmod_module_get_module(itr);
                                r = install_module(ctx, mod);
                                kmod_module_unref(mod);
                                if ((r < 0) && !arg_optional) {
                                        if (!arg_silent)
                                                log_error("ERROR: installing module '%s'", modname);
                                        return -ENOENT;
                                };
                                ret = (ret == 0 ? 0 : r);
                                modinst = 1;
                        }
                } else if (argv[i][0] == '=') {
                        _cleanup_free_ char *path1 = NULL, *path2 = NULL, *path3 = NULL;
                        _cleanup_fts_close_ FTS *fts = NULL;

                        log_debug("Handling =%s", &argv[i][1]);
                        /* FIXME and add more paths */
                        _asprintf(&path2, "%s/kernel/%s", kerneldir, &argv[i][1]);
                        _asprintf(&path1, "%s/extra/%s", kerneldir, &argv[i][1]);
                        _asprintf(&path3, "%s/updates/%s", kerneldir, &argv[i][1]);

                        {
                                char *paths[] = { path1, path2, path3, NULL };
                                fts = fts_open(paths, FTS_COMFOLLOW | FTS_NOCHDIR | FTS_NOSTAT | FTS_LOGICAL, NULL);
                        }

                        for (FTSENT *ftsent = fts_read(fts); ftsent != NULL; ftsent = fts_read(fts)) {
                                _cleanup_kmod_module_unref_list_ struct kmod_list *modlist = NULL;
                                _cleanup_free_ const char *modname = NULL;

                                if ((ftsent->fts_info == FTS_D) && !check_module_path(ftsent->fts_accpath)) {
                                        fts_set(fts, ftsent, FTS_SKIP);
                                        log_debug("Skipping %s", ftsent->fts_accpath);
                                        continue;
                                }
                                if ((ftsent->fts_info != FTS_F) && (ftsent->fts_info != FTS_SL)) {
                                        log_debug("Ignoring %s", ftsent->fts_accpath);
                                        continue;
                                }
                                log_debug("Handling %s", ftsent->fts_accpath);
                                r = kmod_module_new_from_path(ctx, ftsent->fts_accpath, &mod_o);
                                if (r < 0) {
                                        log_debug("Failed to lookup modules path '%s': %m", ftsent->fts_accpath);
                                        if (!arg_optional) {
                                                return -ENOENT;
                                        }
                                        continue;
                                }

                                /* Check, if we have to load another module with that name instead */
                                modname = strdup(kmod_module_get_name(mod_o));

                                if (!modname) {
                                        log_error("Failed to get name for module '%s'", ftsent->fts_accpath);
                                        if (!arg_optional) {
                                                return -ENOENT;
                                        }
                                        continue;
                                }
                                r = kmod_module_new_from_lookup(ctx, modname, &modlist);
                                kmod_module_unref(mod_o);
                                mod_o = NULL;

                                if (r < 0) {
                                        log_error("Failed to lookup alias '%s': %m", modname);
                                        if (!arg_optional) {
                                                return -ENOENT;
                                        }
                                        continue;
                                }

                                if (!modlist) {
                                        log_error("Failed to find module '%s' %s", modname, ftsent->fts_accpath);
                                        if (!arg_optional) {
                                                return -ENOENT;
                                        }
                                        continue;
                                }
                                kmod_list_foreach(itr, modlist) {
                                        mod = kmod_module_get_module(itr);
                                        r = install_module(ctx, mod);
                                        kmod_module_unref(mod);
                                        if ((r < 0) && !arg_optional) {
                                                if (!arg_silent)
                                                        log_error("ERROR: installing module '%s'", modname);
                                                return -ENOENT;
                                        };
                                        ret = (ret == 0 ? 0 : r);
                                        modinst = 1;
                                }
                        }
                        if (errno) {
                                log_error("FTS ERROR: %m");
                        }
                } else {
                        _cleanup_kmod_module_unref_list_ struct kmod_list *modlist = NULL;
                        char *modname = argv[i];

                        if (endswith(modname, ".ko")) {
                                int len = strlen(modname);
                                modname[len - 3] = 0;
                        }
                        if (endswith(modname, ".ko.xz") || endswith(modname, ".ko.gz")) {
                                int len = strlen(modname);
                                modname[len - 6] = 0;
                        }
                        if (endswith(modname, ".ko.zst")) {
                                int len = strlen(modname);
                                modname[len - 7] = 0;
                        }
                        r = kmod_module_new_from_lookup(ctx, modname, &modlist);
                        if (r < 0) {
                                if (!arg_optional) {
                                        if (!arg_silent)
                                                log_error("Failed to lookup alias '%s': %m", modname);
                                        return -ENOENT;
                                }
                                log_info("Failed to lookup alias '%s': %m", modname);
                                continue;
                        }
                        if (!modlist) {
                                if (!arg_optional) {
                                        if (!arg_silent)
                                                log_error("Failed to find module '%s'", modname);
                                        return -ENOENT;
                                }
                                log_info("Failed to find module '%s'", modname);
                                continue;
                        }
                        kmod_list_foreach(itr, modlist) {
                                mod = kmod_module_get_module(itr);
                                r = install_module(ctx, mod);
                                kmod_module_unref(mod);
                                if ((r < 0) && !arg_optional) {
                                        if (!arg_silent)
                                                log_error("ERROR: installing '%s'", argv[i]);
                                        return -ENOENT;
                                };
                                ret = (ret == 0 ? 0 : r);
                                modinst = 1;
                        }
                }

                if ((modinst != 0) && (ret != 0) && (!arg_optional)) {
                        if (!arg_silent)
                                log_error("ERROR: installing '%s'", argv[i]);
                        return EXIT_FAILURE;
                }
        }

        return EXIT_SUCCESS;
}

/* Parse the add_dlopen_features and omit_dlopen_features environment variables,
   and store their contents in the corresponding char* -> char*** hashmaps. Each
   variable holds multiple entries, separated by whitespace, and each entry
   takes the form "libfoo.so.*:feature1,feature2". */
static int parse_dlopen_features()
{
        const char *add_env = getenv("add_dlopen_features");
        const char *omit_env = getenv("omit_dlopen_features");
        const char *envs[] = {add_env, omit_env};

        char *nkey;
        char **features_array;
        char ***features_arrayp;

        for (size_t i = 0; i < 2; i++) {
                if (!envs[i])
                        continue;

                /* We cannot let strtok modify the environment. */
                _cleanup_free_ char *env_copy = strdup(envs[i]);
                if (!env_copy)
                        return -ENOMEM;

                for (char *token = strtok(env_copy, " \t\n"); token; token = strtok(NULL, " \t\n")) {
                        char *colon = strchr(token, ':');
                        if (!colon) {
                                log_warning("Invalid format in dlopen features: '%s'", token);
                                continue;
                        }

                        *colon = '\0';
                        const char *key = token;
                        const char *features = colon + 1;

                        features_array = strv_split(features, ",");
                        if (!features_array)
                                return -ENOMEM;

                        /* There may be entries with the same name/pattern. */
                        char ***existing = hashmap_get(dlopen_features[i], key);

                        if (existing) {
                                char **feature;
                                STRV_FOREACH(feature, features_array) {
                                        /* Free feature if already present. */
                                        if (strv_contains(*existing, *feature))
                                                free(*feature);
                                        /* Otherwise push onto existing array
                                           without duplicating the string. */
                                        else if (strv_push(existing, *feature) == -ENOMEM)
                                                goto oom2;
                                }
                                /* All features have been freed or pushed to the
                                   existing array, so just free array itself. */
                                free(features_array);
                        } else {
                                /* The hashmaps store strvs as char*** rather
                                   than char** because strv_push above calls
                                   realloc. The latter would then leave the
                                   hashmap with a stale pointer. */
                                features_arrayp = (char ***) malloc(sizeof(char **));
                                nkey = strdup(key);
                                if (!features_arrayp || !nkey)
                                        goto oom1;
                                *features_arrayp = features_array;
                                if (hashmap_put(dlopen_features[i], nkey, features_arrayp) == -ENOMEM)
                                        goto oom1;
                        }
                }
        }

        return 0;

oom1:
        free(features_arrayp);
        free(nkey);
oom2:
        log_error("Out of memory");
        strv_free(features_array);
        return -ENOMEM;
}

int main(int argc, char **argv)
{
        int r;
        char *i;
        char *path = NULL;
        char *env_no_xattr = NULL;

        log_set_target(LOG_TARGET_CONSOLE);
        log_parse_environment();
        log_open();

        r = parse_argv(argc, argv);
        if (r <= 0)
                return r < 0 ? EXIT_FAILURE : EXIT_SUCCESS;

        modules_loaded = hashmap_new(string_hash_func, string_compare_func);
        if (arg_modalias) {
                Iterator i;
                char *name;
                _cleanup_kmod_unref_ struct kmod_ctx *ctx = NULL;
                ctx = kmod_new(kerneldir, NULL);

                modalias_list(ctx);
                HASHMAP_FOREACH(name, modules_loaded, i) {
                        printf("%s\n", name);
                }
                exit(0);
        }

        log_debug("Program arguments:");
        for (r = 0; r < argc; r++)
                log_debug("%s", argv[r]);

        path = getenv("DRACUT_INSTALL_PATH");
        if (path == NULL)
                path = getenv("PATH");

        if (path == NULL) {
                log_error("PATH is not set");
                exit(EXIT_FAILURE);
        }

        log_debug("PATH=%s", path);

        env_no_xattr = getenv("DRACUT_NO_XATTR");
        if (env_no_xattr != NULL)
                no_xattr = true;

        pathdirs = strv_split(path, ":");

        umask(0022);

        if (arg_dry_run) {
                destrootdir = "/nonexistent";
        } else {
                if (destrootdir == NULL || strlen(destrootdir) == 0) {
                        destrootdir = getenv("DESTROOTDIR");
                        if (destrootdir == NULL || strlen(destrootdir) == 0) {
                                log_error("Environment DESTROOTDIR or argument -D is not set!");
                                usage(EXIT_FAILURE);
                        }
                }

                if (strcmp(destrootdir, "/") == 0) {
                        log_error("Environment DESTROOTDIR or argument -D is set to '/'!");
                        usage(EXIT_FAILURE);
                }

                i = destrootdir;
                if (!(destrootdir = realpath(i, NULL))) {
                        log_error("Environment DESTROOTDIR or argument -D is set to '%s': %m", i);
                        r = EXIT_FAILURE;
                        goto finish2;
                }
        }

        items = hashmap_new(string_hash_func, string_compare_func);
        items_failed = hashmap_new(string_hash_func, string_compare_func);
        processed_suppliers = hashmap_new(string_hash_func, string_compare_func);
        modalias_to_kmod = hashmap_new(string_hash_func, string_compare_func);

        dlopen_features[0] = add_dlopen_features = hashmap_new(string_hash_func, string_compare_func);
        dlopen_features[1] = omit_dlopen_features = hashmap_new(string_hash_func, string_compare_func);

        if (!items || !items_failed || !processed_suppliers || !modules_loaded ||
            !add_dlopen_features || !omit_dlopen_features) {
                log_error("Out of memory");
                r = EXIT_FAILURE;
                goto finish1;
        }

        if (logdir) {
                _asprintf(&logfile, "%s/%d.log", logdir, getpid());

                logfile_f = fopen(logfile, "a");
                if (logfile_f == NULL) {
                        log_error("Could not open %s for logging: %m", logfile);
                        r = EXIT_FAILURE;
                        goto finish1;
                }
        }

        if (((optind + 1) < argc) && (strcmp(argv[optind + 1], destrootdir) == 0)) {
                /* ugly hack for compat mode "inst src $destrootdir" */
                if ((optind + 2) == argc) {
                        argc--;
                } else {
                        /* ugly hack for compat mode "inst src $destrootdir dst" */
                        if ((optind + 3) == argc) {
                                argc--;
                                argv[optind + 1] = argv[optind + 2];
                        }
                }
        }

        if (parse_dlopen_features() < 0) {
                r = EXIT_FAILURE;
                goto finish1;
        }

        if (arg_module) {
                r = install_modules(argc - optind, &argv[optind]);
        } else if (arg_resolvelazy) {
                r = resolve_lazy(argc - optind, &argv[optind]);
        } else if (arg_all || (argc - optind > 2) || ((argc - optind) == 1)) {
                r = install_all(argc - optind, &argv[optind]);
        } else {
                /* simple "inst src dst" */
                r = install_one(argv[optind], argv[optind + 1]);
        }

        if (arg_optional)
                r = EXIT_SUCCESS;

finish1:
        if (!arg_dry_run)
                free(destrootdir);
finish2:
        if (!arg_kerneldir)
                free(kerneldir);

        if (logfile_f)
                fclose(logfile_f);

        while ((i = hashmap_steal_first(modules_loaded)))
                item_free(i);

        while ((i = hashmap_steal_first(items)))
                item_free(i);

        while ((i = hashmap_steal_first(items_failed)))
                item_free(i);

        Hashmap *h;
        while ((h = hashmap_steal_first(modules_suppliers))) {
                while ((i = hashmap_steal_first(h))) {
                        item_free(i);
                }
                hashmap_free(h);
        }

        while ((i = hashmap_steal_first(processed_suppliers)))
                item_free(i);

        for (size_t j = 0; j < 2; j++) {
                char ***array;
                Iterator it;

                HASHMAP_FOREACH(array, dlopen_features[j], it) {
                        strv_free(*array);
                        free(array);
                }

                while ((i = hashmap_steal_first_key(dlopen_features[j])))
                        item_free(i);

                hashmap_free(dlopen_features[j]);
        }

        /*
         * Note: modalias_to_kmod's values are freed implicitly by the kmod context destruction
         * in kmod_unref().
         */

        hashmap_free(items);
        hashmap_free(items_failed);
        hashmap_free(modules_loaded);
        hashmap_free(modules_suppliers);
        hashmap_free(processed_suppliers);
        hashmap_free(modalias_to_kmod);

        if (arg_mod_filter_path)
                regfree(&mod_filter_path);
        if (arg_mod_filter_nopath)
                regfree(&mod_filter_nopath);
        if (arg_mod_filter_symbol)
                regfree(&mod_filter_symbol);
        if (arg_mod_filter_nosymbol)
                regfree(&mod_filter_nosymbol);
        if (arg_mod_filter_noname)
                regfree(&mod_filter_noname);

        strv_free(firmwaredirs);
        strv_free(pathdirs);
        return r;
}
