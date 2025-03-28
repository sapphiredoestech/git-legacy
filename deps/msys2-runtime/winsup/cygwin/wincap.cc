/* wincap.cc -- figure out on which OS we're running. Set the
		capability class to the appropriate values.

This file is part of Cygwin.

This software is a copyrighted work licensed under the terms of the
Cygwin license.  Please consult the file "CYGWIN_LICENSE" for
details. */

#include "winsup.h"
#include "miscfuncs.h"
#include "security.h"
#include "ntdll.h"
#include "memory_layout.h"

static const wincaps wincap_7 = {
  def_guard_pages:2,
  mmap_storage_high:__MMAP_STORAGE_HIGH_LEGACY,
  {
    has_new_pebteb_region:false,
    has_unprivileged_createsymlink:false,
    has_precise_interrupt_time:false,
    has_posix_unlink_semantics:false,
    has_posix_unlink_semantics_with_ignore_readonly:false,
    has_case_sensitive_dirs:false,
    has_posix_rename_semantics:false,
    has_con_24bit_colors:false,
    has_con_broken_csi3j:false,
    has_con_broken_il_dl:false,
    has_con_esc_rep:false,
    has_extended_mem_api:false,
    has_tcp_fastopen:false,
    has_linux_tcp_keepalive_sockopts:false,
    has_tcp_maxrtms:false,
    has_con_broken_tabs:false,
    has_user_shstk:false,
  },
};

static const wincaps wincap_8 = {
  mmap_storage_high:__MMAP_STORAGE_HIGH_LEGACY,
  def_guard_pages:3,
  {
    has_new_pebteb_region:false,
    has_unprivileged_createsymlink:false,
    has_precise_interrupt_time:false,
    has_posix_unlink_semantics:false,
    has_posix_unlink_semantics_with_ignore_readonly:false,
    has_case_sensitive_dirs:false,
    has_posix_rename_semantics:false,
    has_con_24bit_colors:false,
    has_con_broken_csi3j:false,
    has_con_broken_il_dl:false,
    has_con_esc_rep:false,
    has_extended_mem_api:false,
    has_tcp_fastopen:false,
    has_linux_tcp_keepalive_sockopts:false,
    has_tcp_maxrtms:false,
    has_con_broken_tabs:false,
    has_user_shstk:false,
  },
};

static const wincaps wincap_8_1 = {
  mmap_storage_high:__MMAP_STORAGE_HIGH,
  def_guard_pages:3,
  {
    has_new_pebteb_region:false,
    has_unprivileged_createsymlink:false,
    has_precise_interrupt_time:false,
    has_posix_unlink_semantics:false,
    has_posix_unlink_semantics_with_ignore_readonly:false,
    has_case_sensitive_dirs:false,
    has_posix_rename_semantics:false,
    has_con_24bit_colors:false,
    has_con_broken_csi3j:false,
    has_con_broken_il_dl:false,
    has_con_esc_rep:false,
    has_extended_mem_api:false,
    has_tcp_fastopen:false,
    has_linux_tcp_keepalive_sockopts:false,
    has_tcp_maxrtms:false,
    has_con_broken_tabs:false,
    has_user_shstk:false,
  },
};

static const wincaps  wincap_10_1507 = {
  mmap_storage_high:__MMAP_STORAGE_HIGH,
  def_guard_pages:3,
  {
    has_new_pebteb_region:false,
    has_unprivileged_createsymlink:false,
    has_precise_interrupt_time:true,
    has_posix_unlink_semantics:false,
    has_posix_unlink_semantics_with_ignore_readonly:false,
    has_case_sensitive_dirs:false,
    has_posix_rename_semantics:false,
    has_con_24bit_colors:false,
    has_con_broken_csi3j:false,
    has_con_broken_il_dl:false,
    has_con_esc_rep:false,
    has_extended_mem_api:false,
    has_tcp_fastopen:false,
    has_linux_tcp_keepalive_sockopts:false,
    has_tcp_maxrtms:false,
    has_con_broken_tabs:false,
    has_user_shstk:false,
  },
};

static const wincaps  wincap_10_1607 = {
  mmap_storage_high:__MMAP_STORAGE_HIGH,
  def_guard_pages:3,
  {
    has_new_pebteb_region:false,
    has_unprivileged_createsymlink:false,
    has_precise_interrupt_time:true,
    has_posix_unlink_semantics:false,
    has_posix_unlink_semantics_with_ignore_readonly:false,
    has_case_sensitive_dirs:false,
    has_posix_rename_semantics:false,
    has_con_24bit_colors:false,
    has_con_broken_csi3j:false,
    has_con_broken_il_dl:false,
    has_con_esc_rep:false,
    has_extended_mem_api:false,
    has_tcp_fastopen:true,
    has_linux_tcp_keepalive_sockopts:false,
    has_tcp_maxrtms:true,
    has_con_broken_tabs:false,
    has_user_shstk:false,
  },
};

static const wincaps wincap_10_1703 = {
  mmap_storage_high:__MMAP_STORAGE_HIGH,
  def_guard_pages:3,
  {
    has_new_pebteb_region:true,
    has_unprivileged_createsymlink:true,
    has_precise_interrupt_time:true,
    has_posix_unlink_semantics:false,
    has_posix_unlink_semantics_with_ignore_readonly:false,
    has_case_sensitive_dirs:false,
    has_posix_rename_semantics:false,
    has_con_24bit_colors:true,
    has_con_broken_csi3j:false,
    has_con_broken_il_dl:false,
    has_con_esc_rep:false,
    has_extended_mem_api:false,
    has_tcp_fastopen:true,
    has_linux_tcp_keepalive_sockopts:false,
    has_tcp_maxrtms:true,
    has_con_broken_tabs:true,
    has_user_shstk:false,
  },
};

static const wincaps wincap_10_1709 = {
  mmap_storage_high:__MMAP_STORAGE_HIGH,
  def_guard_pages:3,
  {
    has_new_pebteb_region:true,
    has_unprivileged_createsymlink:true,
    has_precise_interrupt_time:true,
    has_posix_unlink_semantics:true,
    has_posix_unlink_semantics_with_ignore_readonly:false,
    has_case_sensitive_dirs:false,
    has_posix_rename_semantics:false,
    has_con_24bit_colors:true,
    has_con_broken_csi3j:false,
    has_con_broken_il_dl:false,
    has_con_esc_rep:false,
    has_extended_mem_api:false,
    has_tcp_fastopen:true,
    has_linux_tcp_keepalive_sockopts:true,
    has_tcp_maxrtms:true,
    has_con_broken_tabs:true,
    has_user_shstk:false,
  },
};

static const wincaps wincap_10_1803 = {
  mmap_storage_high:__MMAP_STORAGE_HIGH,
  def_guard_pages:3,
  {
    has_new_pebteb_region:true,
    has_unprivileged_createsymlink:true,
    has_precise_interrupt_time:true,
    has_posix_unlink_semantics:true,
    has_posix_unlink_semantics_with_ignore_readonly:false,
    has_case_sensitive_dirs:true,
    has_posix_rename_semantics:false,
    has_con_24bit_colors:true,
    has_con_broken_csi3j:false,
    has_con_broken_il_dl:false,
    has_con_esc_rep:false,
    has_extended_mem_api:true,
    has_tcp_fastopen:true,
    has_linux_tcp_keepalive_sockopts:true,
    has_tcp_maxrtms:true,
    has_con_broken_tabs:true,
    has_user_shstk:false,
  },
};

static const wincaps wincap_10_1809 = {
  mmap_storage_high:__MMAP_STORAGE_HIGH,
  def_guard_pages:3,
  {
    has_new_pebteb_region:true,
    has_unprivileged_createsymlink:true,
    has_precise_interrupt_time:true,
    has_posix_unlink_semantics:true,
    has_posix_unlink_semantics_with_ignore_readonly:true,
    has_case_sensitive_dirs:true,
    has_posix_rename_semantics:true,
    has_con_24bit_colors:true,
    has_con_broken_csi3j:true,
    has_con_broken_il_dl:false,
    has_con_esc_rep:false,
    has_extended_mem_api:true,
    has_tcp_fastopen:true,
    has_linux_tcp_keepalive_sockopts:true,
    has_tcp_maxrtms:true,
    has_con_broken_tabs:true,
    has_user_shstk:false,
  },
};

static const wincaps wincap_10_1903 = {
  mmap_storage_high:__MMAP_STORAGE_HIGH,
  def_guard_pages:3,
  {
    has_new_pebteb_region:true,
    has_unprivileged_createsymlink:true,
    has_precise_interrupt_time:true,
    has_posix_unlink_semantics:true,
    has_posix_unlink_semantics_with_ignore_readonly:true,
    has_case_sensitive_dirs:true,
    has_posix_rename_semantics:true,
    has_con_24bit_colors:true,
    has_con_broken_csi3j:false,
    has_con_broken_il_dl:true,
    has_con_esc_rep:true,
    has_extended_mem_api:true,
    has_tcp_fastopen:true,
    has_linux_tcp_keepalive_sockopts:true,
    has_tcp_maxrtms:true,
    has_con_broken_tabs:true,
    has_user_shstk:false,
  },
};

static const wincaps wincap_10_2004 = {
  mmap_storage_high:__MMAP_STORAGE_HIGH,
  def_guard_pages:3,
  {
    has_new_pebteb_region:true,
    has_unprivileged_createsymlink:true,
    has_precise_interrupt_time:true,
    has_posix_unlink_semantics:true,
    has_posix_unlink_semantics_with_ignore_readonly:true,
    has_case_sensitive_dirs:true,
    has_posix_rename_semantics:true,
    has_con_24bit_colors:true,
    has_con_broken_csi3j:false,
    has_con_broken_il_dl:false,
    has_con_esc_rep:true,
    has_extended_mem_api:true,
    has_tcp_fastopen:true,
    has_linux_tcp_keepalive_sockopts:true,
    has_tcp_maxrtms:true,
    has_con_broken_tabs:true,
    has_user_shstk:true,
  },
};

static const wincaps wincap_11 = {
  mmap_storage_high:__MMAP_STORAGE_HIGH,
  def_guard_pages:3,
  {
    has_new_pebteb_region:true,
    has_unprivileged_createsymlink:true,
    has_precise_interrupt_time:true,
    has_posix_unlink_semantics:true,
    has_posix_unlink_semantics_with_ignore_readonly:true,
    has_case_sensitive_dirs:true,
    has_posix_rename_semantics:true,
    has_con_24bit_colors:true,
    has_con_broken_csi3j:false,
    has_con_broken_il_dl:false,
    has_con_esc_rep:true,
    has_extended_mem_api:true,
    has_tcp_fastopen:true,
    has_linux_tcp_keepalive_sockopts:true,
    has_tcp_maxrtms:true,
    has_con_broken_tabs:false,
    has_user_shstk:true,
  },
};

wincapc wincap __attribute__((section (".cygwin_dll_common"), shared));

extern IMAGE_DOS_HEADER
__image_base__;

void
wincapc::init ()
{
  PIMAGE_NT_HEADERS ntheader;
  USHORT emul_mach;

  if (caps)
    return;		// already initialized

  GetSystemInfo (&system_info);
  version.dwOSVersionInfoSize = sizeof (RTL_OSVERSIONINFOEXW);
  RtlGetVersion (&version);
  /* Overwrite unreliable kernel version with correct values returned by
     RtlGetNtVersionNumbers.  See git log of this change for a description. */
  RtlGetNtVersionNumbers (&version.dwMajorVersion,
			  &version.dwMinorVersion,
			  &version.dwBuildNumber);
  version.dwBuildNumber &= 0xffff;

  switch (version.dwMajorVersion)
    {
      case 6:
	switch (version.dwMinorVersion)
	  {
	    case 1:
	      caps = &wincap_7;
	      break;
	    case 2:
	      caps = &wincap_8;
	      break;
	    case 3:
	    default:
	      caps = &wincap_8_1;
	      break;
	  }
      case 10:
      default:
	if (likely (version.dwBuildNumber >= 22000))
	  caps = &wincap_11;
	else if (version.dwBuildNumber >= 19041)
	  caps = &wincap_10_2004;
	else if (version.dwBuildNumber >= 18362)
	  caps = &wincap_10_1903;
	else if (version.dwBuildNumber >= 17763)
	  caps = &wincap_10_1809;
	else if (version.dwBuildNumber >= 17134)
	  caps = &wincap_10_1803;
	else if (version.dwBuildNumber >= 16299)
	  caps = &wincap_10_1709;
	else if (version.dwBuildNumber >= 15063)
	  caps = &wincap_10_1703;
	else if (version.dwBuildNumber >= 14393)
	  caps = &wincap_10_1607;
	else
	  caps = & wincap_10_1507;
    }

  _is_server = (version.wProductType != VER_NT_WORKSTATION);

  __small_sprintf (osnam, "NT-%d.%d", version.dwMajorVersion,
		   version.dwMinorVersion);

  if (!IsWow64Process2 (GetCurrentProcess (), &emul_mach, &host_mach))
    {
      /* If IsWow64Process2 succeeded, it filled in host_mach.  Assume the only
	 way it fails for the current process is that we're running on an OS
	 version where it's not implemented yet.  As such, the only realistic
	 option for host_mach is AMD64 */
      host_mach = IMAGE_FILE_MACHINE_AMD64;
    }

  ntheader = (PIMAGE_NT_HEADERS)((LPBYTE) &__image_base__
				 + __image_base__.e_lfanew);
  cygwin_mach = ntheader->FileHeader.Machine;
}
