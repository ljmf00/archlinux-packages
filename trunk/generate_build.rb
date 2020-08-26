#!/usr/bin/ruby

# Android has a huge and monolithic build system that does not allow to build
# components separately.
# This script tries to mimic Android build system for a small subset of source.

def expand(dir, files)
  files.map { |f| File.join(dir, f) }
end

# Compiles sources to *.o files.
# Returns array of output *.o filenames
def compile(sources, cflags = '', params = {})
  outputs = []
  for s in sources
    ext = File.extname(s)

    case ext
    when ".c"
      cc = "cc"
    when ".cpp", ".cc"
      cc = "cxx"
    else
      raise "Unknown extension #{ext}"
    end

    output = s + ".o"
    outputs << output
    order_deps = if params[:order_deps]
        " || " + params[:order_deps].join(" ")
      else
        ""
      end

    # TODO: try to build the tools with LLVM libc: -stdlib=libc++
    puts "build #{output}: #{cc} #{s}#{order_deps}\n    cflags = #{cflags}"
  end

  return outputs
end

def generate(sources)
  outputs = []
  for s in sources
    ext = File.extname(s)

    case ext
    when ".l", ".ll"
      generator = "lex"
    when ".y", ".yy"
      generator = "yacc"
    else
      raise "Unknown extension #{ext}"
    end

    base_output = File.dirname(s) + File::SEPARATOR + File.basename(s, ext)
    src_output = base_output + ".cpp"
    hdr_output = base_output + ".h"
    outputs << src_output

    puts "build #{src_output} #{hdr_output}: #{generator} #{s}\n    outsrc = #{src_output}\n    outhdr = #{hdr_output}"
  end

  return outputs
end

# Generate proto and compile it
def protoc(source)
  basename = File.join(File.dirname(source), File.basename(source, ".proto"))
  cfile = basename + ".pb.cc"
  hfile = basename + ".pb.h"
  ofile = cfile + ".o"
  puts "build #{cfile} #{hfile}: protoc #{source}"
  puts "build #{ofile}: cxx #{cfile}\n    cflags = -I."

  return hfile, cfile, ofile
end

# dir - directory where ninja file is located
# lib - static library path relative to dir
def subninja(dir, lib)
  puts "subninja #{dir}build.ninja"
  return lib.each { |l| dir + l }
end

# Links object files
def link(output, objects, ldflags)
  # TODO: try to build the tools with LLVM libc: -stdlib=libc++
  puts "build #{output}: link #{objects.join(" ")}\n    ldflags = #{ldflags}"
end

def genheader(input, variable, output)
  puts "build #{output}: genheader #{input}\n    var = #{variable}"
end

puts "# This set of commands generated by generate_build.rb script\n\n"
puts "CC = #{ENV["CC"] || "clang"}"
puts "CXX = #{ENV["CXX"] || "clang++"}"
puts "FLEX = #{ENV["FLEX"] || "flex"}"
puts "BISON = #{ENV["BISON"] || "bison"}\n\n"
puts "CFLAGS = #{ENV["CFLAGS"]}"
puts "CPPFLAGS = #{ENV["CPPFLAGS"]}"
puts "CXXFLAGS = #{ENV["CXXFLAGS"]}"
puts "LDFLAGS = #{ENV["LDFLAGS"]}"
puts "PLATFORM_TOOLS_VERSION = #{ENV["PLATFORM_TOOLS_VERSION"]}"
puts "PLATFORM_SDK_VERSION = #{ENV["PLATFORM_SDK_VERSION"] || "<UNKNOWN>"}\n\n"

puts "" "
rule cc
  description = CC $out
  command = $CC -std=gnu11 $CFLAGS $CPPFLAGS $cflags -c $in -o $out

rule cxx
  description = CXX $out
  command = $CXX -std=gnu++2a $CXXFLAGS $CPPFLAGS $cflags -c $in -o $out

rule lex
  description = LEX $outsrc
  command = $FLEX -o $outsrc --header-file=$outhdr $in

rule yacc
  description = YACC $outsrc
  command = $BISON -o $outsrc --defines=$outhdr $in

rule link
  description = LD $out
  command = $CXX $ldflags $LDFLAGS $in -o $out

rule protoc
  description = PROTOC $in
  command = protoc --cpp_out=. $in

rule genheader
  description = GENHEADER $out
  command = (echo 'unsigned char $var[] = {' && xxd -i <$in && echo '};') > $out

rule javac
  description = JAVAC $in
  command = javac -d $outdir $flags $in

" ""

key_type_h, key_type_c, key_type_o = protoc("core/adb/proto/key_type.proto")

adbdfiles = %w(
  adb.cpp
  adb_io.cpp
  adb_listeners.cpp
  adb_trace.cpp
  adb_utils.cpp
  fdevent/fdevent.cpp
  fdevent/fdevent_poll.cpp
  fdevent/fdevent_epoll.cpp
  shell_service_protocol.cpp
  sockets.cpp
  transport.cpp
  types.cpp
)
libadbd = compile(expand("core/adb", adbdfiles), '-DPLATFORM_TOOLS_VERSION="\"$PLATFORM_TOOLS_VERSION\"" -DADB_HOST=1 -Icore/include -Ilibbase/include -Icore/adb -Icore/libcrypto_utils/include -Iboringssl/src/include -Icore/diagnose_usb/include -Icore/adb/crypto/include -Icore/adb/proto -Icore/adb/tls/include', :order_deps => [key_type_h])

apkent_h, apkent_c, apkent_o = protoc("core/adb/fastdeploy/proto/ApkEntry.proto")
app_processes_h, app_processes_c, app_processes_o = protoc("core/adb/proto/app_processes.proto")
adb_known_hosts_h, adb_known_hosts_c, adb_known_hosts_o = protoc("core/adb/proto/adb_known_hosts.proto")
pairing_h, pairing_c, pairing_o = protoc("core/adb/proto/pairing.proto")

deployagent_inc = "core/adb/client/deployagent.inc"
genheader("deployagent.jar", "kDeployAgent", deployagent_inc)

deployagentscript_inc = "core/adb/client/deployagentscript.inc"
genheader("core/adb/fastdeploy/deployagent/deployagent.sh", "kDeployAgentScript", deployagentscript_inc)

adbfiles = %w(
  client/adb_client.cpp
  client/adb_install.cpp
  client/adb_wifi.cpp
  client/auth.cpp
  client/bugreport.cpp
  client/commandline.cpp
  client/console.cpp
  client/fastdeploy.cpp
  client/fastdeploycallbacks.cpp
  client/file_sync_client.cpp
  client/incremental.cpp
  client/incremental_server.cpp
  client/incremental_utils.cpp
  client/line_printer.cpp
  client/main.cpp
  client/pairing/pairing_client.cpp
  client/transport_local.cpp
  client/transport_usb.cpp
  client/usb_dispatch.cpp
  client/usb_libusb.cpp
  client/usb_linux.cpp
  crypto/key.cpp
  crypto/rsa_2048_key.cpp
  crypto/x509_generator.cpp
  fastdeploy/deploypatchgenerator/apk_archive.cpp
  fastdeploy/deploypatchgenerator/deploy_patch_generator.cpp
  fastdeploy/deploypatchgenerator/patch_utils.cpp
  pairing_auth/aes_128_gcm.cpp
  pairing_auth/pairing_auth.cpp
  pairing_connection/pairing_connection.cpp
  services.cpp
  socket_spec.cpp
  sysdeps/errno.cpp
  sysdeps/posix/network.cpp
  sysdeps_unix.cpp
  tls/adb_ca_list.cpp
  tls/tls_connection.cpp
)
libadb = compile(expand("core/adb", adbfiles), "-D_GNU_SOURCE -DADB_HOST=1 -Icore/include -Ilibbase/include -Icore/adb -Icore/libcrypto_utils/include -Iboringssl/src/include -Ibase/libs/androidfw/include -Inative/include -Icore/adb/crypto/include -Icore/adb/proto -Icore/adb/tls/include -Icore/adb/pairing_connection/include -Ilibziparchive/include -Icore/adb/pairing_auth/include",
    :order_deps => [apkent_h, key_type_h, app_processes_h, adb_known_hosts_h, pairing_h, deployagent_inc, deployagentscript_inc])
androidfwfiles = %w(
  LocaleData.cpp
  ResourceTypes.cpp
  TypeWrappers.cpp
  ZipFileRO.cpp
)
libandroidfw = compile(expand("base/libs/androidfw", androidfwfiles), "-Ilibbase/include -Ibase/libs/androidfw/include -Icore/libutils/include -Icore/liblog/include -Icore/libsystem/include -Inative/include -Icore/libcutils/include -Ilibziparchive/include")

basefiles = %w(
  chrono_utils.cpp
  errors_unix.cpp
  file.cpp
  liblog_symbols.cpp
  logging.cpp
  mapped_file.cpp
  parsebool.cpp
  parsenetaddress.cpp
  stringprintf.cpp
  strings.cpp
  test_utils.cpp
  threads.cpp
)
libbase = compile(expand("libbase", basefiles), "-DADB_HOST=1 -Ilibbase/include -Icore/include")

logfiles = %w(
  log_event_list.cpp
  log_event_write.cpp
  logger_name.cpp
  logger_write.cpp
  logprint.cpp
  properties.cpp
)
liblog = compile(expand("core/liblog", logfiles), "-DLIBLOG_LOG_TAG=1006 -D_XOPEN_SOURCE=700 -DFAKE_LOG_DEVICE=1 -Icore/log/include -Icore/include -Ilibbase/include")

cutilsfiles = %w(
  android_get_control_file.cpp
  canned_fs_config.cpp
  fs_config.cpp
  load_file.cpp
  socket_inaddr_any_server_unix.cpp
  socket_local_client_unix.cpp
  socket_local_server_unix.cpp
  socket_network_client_unix.cpp
  sockets.cpp
  sockets_unix.cpp
  threads.cpp
)
libcutils = compile(expand("core/libcutils", cutilsfiles), "-D_GNU_SOURCE -Icore/libcutils/include -Icore/include -Ilibbase/include")

diagnoseusbfiles = %w(
  diagnose_usb.cpp
)
libdiagnoseusb = compile(expand("core/diagnose_usb", diagnoseusbfiles), "-Icore/include -Ilibbase/include -Icore/diagnose_usb/include")

libcryptofiles = %w(
  android_pubkey.c
)
libcrypto = compile(expand("core/libcrypto_utils", libcryptofiles), "-Icore/libcrypto_utils/include -Iboringssl/src/include")

# TODO: make subninja working
#boringssl = subninja('boringssl/src/build/', ['ssl/libssl.a'])
boringssl = ["boringssl/src/build/crypto/libcrypto.a", "boringssl/src/build/ssl/libssl.a"]
boringssl_ldflags = "-Wl,--whole-archive " + boringssl.join(" ") + " -Wl,--no-whole-archive"

fastbootfiles = %w(
  bootimg_utils.cpp
  fastboot.cpp
  fastboot_driver.cpp
  fs.cpp
  main.cpp
  socket.cpp
  tcp.cpp
  udp.cpp
  usb_linux.cpp
  util.cpp
)
libfastboot = compile(expand("core/fastboot", fastbootfiles), '-DPLATFORM_TOOLS_VERSION="\"$PLATFORM_TOOLS_VERSION\"" -D_GNU_SOURCE -D_XOPEN_SOURCE=700 -DUSE_F2FS -Ilibbase/include -Icore/include -Icore/adb -Icore/libsparse/include -Itools/mkbootimg/include/bootimg -Iextras/ext4_utils/include -Iextras/f2fs_utils -Ilibziparchive/include -Icore/fs_mgr/liblp/include -Icore/diagnose_usb/include -Iavb')

fsmgrfiles = %w(
  liblp/images.cpp
  liblp/partition_opener.cpp
  liblp/reader.cpp
  liblp/utility.cpp
  liblp/writer.cpp
)
libfsmgr = compile(expand("core/fs_mgr", fsmgrfiles), "-Icore/fs_mgr/liblp/include -Ilibbase/include -Iextras/ext4_utils/include -Icore/libsparse/include")

sparsefiles = %w(
  backed_block.cpp
  output_file.cpp
  sparse.cpp
  sparse_crc32.cpp
  sparse_err.cpp
  sparse_read.cpp
)
libsparse = compile(expand("core/libsparse", sparsefiles), "-Icore/libsparse/include -Ilibbase/include")

f2fsfiles = %w(
)
f2fs = compile(expand("extras/f2fs_utils", f2fsfiles), "-DHAVE_LINUX_TYPES_H -If2fs-tools/include -Icore/liblog/include")

zipfiles = %w(
  zip_archive.cc
  zip_error.cpp
  zip_cd_entry_map.cc
)
# we use -std=c++17 as this lib currently does not compile with c++20 standard due to
# https://stackoverflow.com/questions/37618213/when-is-a-private-constructor-not-a-private-constructor/57430419#57430419
libzip = compile(expand("libziparchive", zipfiles), "-std=c++17 -Ilibbase/include -Icore/include -Ilibziparchive/include")

utilfiles = %w(
  FileMap.cpp
  SharedBuffer.cpp
  String16.cpp
  String8.cpp
  VectorImpl.cpp
  Unicode.cpp
)
libutil = compile(expand("core/libutils", utilfiles), "-Icore/include -Ilibbase/include")

ext4files = %w(
  ext4_utils.cpp
  wipe.cpp
  ext4_sb.cpp
)
libext4 = compile(expand("extras/ext4_utils", ext4files), "-D_GNU_SOURCE -Icore/libsparse/include -Icore/include -Iselinux/libselinux/include -Iextras/ext4_utils/include -Ilibbase/include")

selinuxfiles = %w(
  booleans.c
  callbacks.c
  canonicalize_context.c
  check_context.c
  disable.c
  enabled.c
  freecon.c
  getenforce.c
  init.c
  label_backends_android.c
  label.c
  label_file.c
  label_support.c
  lgetfilecon.c
  load_policy.c
  lsetfilecon.c
  matchpathcon.c
  policyvers.c
  regex.c
  selinux_config.c
  setenforce.c
  setrans_client.c
  seusers.c
  sha1.c
)
libselinux = compile(expand("selinux/libselinux/src", selinuxfiles), "-DAUDITD_LOG_TAG=1003 -D_GNU_SOURCE -DHOST -DUSE_PCRE2 -DNO_PERSISTENTLY_STORED_PATTERNS -DDISABLE_SETRANS -DDISABLE_BOOL -DNO_MEDIA_BACKEND -DNO_X_BACKEND -DNO_DB_BACKEND -DPCRE2_CODE_UNIT_WIDTH=8 -Iselinux/libselinux/include -Iselinux/libsepol/include")

libsepolfiles = %w(
  assertion.c
  avrule_block.c
  avtab.c
  conditional.c
  constraint.c
  context.c
  context_record.c
  debug.c
  ebitmap.c
  expand.c
  hashtab.c
  hierarchy.c
  kernel_to_common.c
  mls.c
  optimize.c
  policydb.c
  policydb_convert.c
  policydb_public.c
  services.c
  sidtab.c
  symtab.c
  util.c
  write.c
)
libsepol = compile(expand("selinux/libsepol/src", libsepolfiles), "-Iselinux/libsepol/include -Iselinux/libsepol/src")

link("fastboot", libfsmgr + libsparse + libzip + libcutils + liblog + libutil + libbase + libext4 + f2fs + libselinux + libsepol + libfastboot + libdiagnoseusb, boringssl_ldflags + " -lz -lpcre2-8 -lpthread")

# mke2fs.android - a ustom version of mke2fs that supports --android_sparse (FS#56955)
libext2fsfiles = %w(
  lib/blkid/cache.c
  lib/blkid/dev.c
  lib/blkid/devname.c
  lib/blkid/devno.c
  lib/blkid/getsize.c
  lib/blkid/llseek.c
  lib/blkid/probe.c
  lib/blkid/read.c
  lib/blkid/resolve.c
  lib/blkid/save.c
  lib/blkid/tag.c
  lib/e2p/encoding.c
  lib/e2p/feature.c
  lib/e2p/hashstr.c
  lib/e2p/mntopts.c
  lib/e2p/ostype.c
  lib/e2p/parse_num.c
  lib/e2p/uuid.c
  lib/et/com_err.c
  lib/et/error_message.c
  lib/et/et_name.c
  lib/ext2fs/alloc.c
  lib/ext2fs/alloc_sb.c
  lib/ext2fs/alloc_stats.c
  lib/ext2fs/alloc_tables.c
  lib/ext2fs/atexit.c
  lib/ext2fs/badblocks.c
  lib/ext2fs/bb_inode.c
  lib/ext2fs/bitmaps.c
  lib/ext2fs/bitops.c
  lib/ext2fs/blkmap64_ba.c
  lib/ext2fs/blkmap64_rb.c
  lib/ext2fs/blknum.c
  lib/ext2fs/block.c
  lib/ext2fs/bmap.c
  lib/ext2fs/closefs.c
  lib/ext2fs/crc16.c
  lib/ext2fs/crc32c.c
  lib/ext2fs/csum.c
  lib/ext2fs/dirblock.c
  lib/ext2fs/dir_iterate.c
  lib/ext2fs/expanddir.c
  lib/ext2fs/ext2_err.c
  lib/ext2fs/ext_attr.c
  lib/ext2fs/extent.c
  lib/ext2fs/fallocate.c
  lib/ext2fs/fileio.c
  lib/ext2fs/freefs.c
  lib/ext2fs/gen_bitmap64.c
  lib/ext2fs/gen_bitmap.c
  lib/ext2fs/get_num_dirs.c
  lib/ext2fs/getsectsize.c
  lib/ext2fs/getsize.c
  lib/ext2fs/hashmap.c
  lib/ext2fs/i_block.c
  lib/ext2fs/ind_block.c
  lib/ext2fs/initialize.c
  lib/ext2fs/inline.c
  lib/ext2fs/inline_data.c
  lib/ext2fs/inode.c
  lib/ext2fs/io_manager.c
  lib/ext2fs/ismounted.c
  lib/ext2fs/link.c
  lib/ext2fs/llseek.c
  lib/ext2fs/lookup.c
  lib/ext2fs/mkdir.c
  lib/ext2fs/mkjournal.c
  lib/ext2fs/mmp.c
  lib/ext2fs/namei.c
  lib/ext2fs/newdir.c
  lib/ext2fs/nls_utf8.c
  lib/ext2fs/openfs.c
  lib/ext2fs/progress.c
  lib/ext2fs/punch.c
  lib/ext2fs/rbtree.c
  lib/ext2fs/read_bb.c
  lib/ext2fs/read_bb_file.c
  lib/ext2fs/res_gdt.c
  lib/ext2fs/rw_bitmaps.c
  lib/ext2fs/sha512.c
  lib/ext2fs/sparse_io.c
  lib/ext2fs/symlink.c
  lib/ext2fs/undo_io.c
  lib/ext2fs/unix_io.c
  lib/ext2fs/valid_blk.c
  lib/support/dict.c
  lib/support/mkquota.c
  lib/support/parse_qtype.c
  lib/support/plausible.c
  lib/support/prof_err.c
  lib/support/profile.c
  lib/support/quotaio.c
  lib/support/quotaio_tree.c
  lib/support/quotaio_v2.c
  lib/uuid/clear.c
  lib/uuid/gen_uuid.c
  lib/uuid/isnull.c
  lib/uuid/pack.c
  lib/uuid/parse.c
  lib/uuid/unpack.c
  lib/uuid/unparse.c
  misc/create_inode.c
)
libext2fs = compile(expand("e2fsprogs", libext2fsfiles), "-Ie2fsprogs/lib -Ie2fsprogs/lib/ext2fs -Icore/libsparse/include")

mke2fsfiles = %w(
  misc/default_profile.c
  misc/mke2fs.c
  misc/mk_hugefiles.c
  misc/util.c
)
mke2fs = compile(expand("e2fsprogs", mke2fsfiles), "-Ie2fsprogs/lib")

link("mke2fs.android", mke2fs + libext2fs + libsparse + libbase + libzip + liblog + libutil, "-lpthread -lz")

e2fsdroidfiles = %w(
  contrib/android/basefs_allocator.c
  contrib/android/base_fs.c
  contrib/android/block_list.c
  contrib/android/block_range.c
  contrib/android/e2fsdroid.c
  contrib/android/fsmap.c
  contrib/android/perms.c
)
e2fsdroid = compile(expand("e2fsprogs", e2fsdroidfiles), "-Ie2fsprogs/lib -Ie2fsprogs/lib/ext2fs -Iselinux/libselinux/include -Icore/libcutils/include -Ie2fsprogs/misc")

link("e2fsdroid", e2fsdroid + libext2fs + libsparse + libbase + libzip + liblog + libutil + libselinux + libsepol + libcutils, "-lz -lpthread -lpcre2-8")

ext2simgfiles = %w(
  contrib/android/ext2simg.c
)
ext2simg = compile(expand("e2fsprogs", ext2simgfiles), "-Ie2fsprogs/lib -Icore/libsparse/include")

link("ext2simg", ext2simg + libext2fs + libsparse + libbase + libzip + liblog + libutil, "-lz -lpthread")

link("adb", libbase + liblog + libcutils + libutil + libadbd + libadb + libdiagnoseusb + libcrypto + libandroidfw + libzip + [apkent_o, key_type_o, app_processes_o, adb_known_hosts_o, pairing_o], boringssl_ldflags + " -lpthread -lusb-1.0 -lprotobuf -lz -llz4 -lbrotlidec -lbrotlienc")

aidllexerfiles = %w(
  aidl_language_l.ll
  aidl_language_y.yy
)
aidllexer = generate(expand("tools/aidl", aidllexerfiles))

aidlfiles = %w(
  main.cpp
  aidl.cpp
  aidl_checkapi.cpp
  aidl_const_expressions.cpp
  aidl_language.cpp
  aidl_typenames.cpp
  aidl_to_cpp.cpp
  aidl_to_java.cpp
  aidl_to_ndk.cpp
  ast_cpp.cpp
  ast_java.cpp
  code_writer.cpp
  generate_cpp.cpp
  aidl_to_cpp_common.cpp
  generate_ndk.cpp
  generate_java.cpp
  generate_java_binder.cpp
  generate_aidl_mappings.cpp
  import_resolver.cpp
  line_reader.cpp
  io_delegate.cpp
  options.cpp
)
libaidl = compile(expand("tools/aidl", aidlfiles) + aidllexer, '-DPLATFORM_SDK_VERSION="\"$PLATFORM_SDK_VERSION\"" -Icore/liblog/include -Icore/libcutils/include -Ilibbase/include -Itools/aidl/')

link("aidl", liblog + libcutils + libbase + libaidl, "-lpthread")
