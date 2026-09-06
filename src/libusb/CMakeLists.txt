cmake_minimum_required(VERSION 3.13)
project(flipperlib_libusb LANGUAGES C)

# libusb 1.0.30 built from the vendored sources for Windows (MSVC, WinUSB
# backend) and Android (usbfs backend, opened through a file descriptor handed
# over by UsbManager). macOS compiles the same tree through CocoaPods
# (../../macos/flipperlib.podspec, darwin/config.h); Linux uses the system
# library. Source lists and config headers mirror upstream libusb/Makefile.am,
# msvc/config.h and android/config.h.

set(LIBUSB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/libusb")

set(LIBUSB_COMMON_SRC
  "${LIBUSB_DIR}/core.c"
  "${LIBUSB_DIR}/descriptor.c"
  "${LIBUSB_DIR}/hotplug.c"
  "${LIBUSB_DIR}/io.c"
  "${LIBUSB_DIR}/strerror.c"
  "${LIBUSB_DIR}/sync.c"
)

if(WIN32)
  set(LIBUSB_OS_SRC
    "${LIBUSB_DIR}/os/events_windows.c"
    "${LIBUSB_DIR}/os/threads_windows.c"
    "${LIBUSB_DIR}/os/windows_common.c"
    "${LIBUSB_DIR}/os/windows_usbdk.c"
    "${LIBUSB_DIR}/os/windows_winusb.c"
    "${LIBUSB_DIR}/libusb-1.0.def"
  )
  set(LIBUSB_CONFIG_DIR "${CMAKE_CURRENT_SOURCE_DIR}/msvc")
elseif(ANDROID)
  set(LIBUSB_OS_SRC
    "${LIBUSB_DIR}/os/events_posix.c"
    "${LIBUSB_DIR}/os/threads_posix.c"
    "${LIBUSB_DIR}/os/linux_usbfs.c"
    "${LIBUSB_DIR}/os/linux_netlink.c"
  )
  set(LIBUSB_CONFIG_DIR "${CMAKE_CURRENT_SOURCE_DIR}/android")
else()
  message(FATAL_ERROR "flipperlib_libusb is only built for Windows and Android")
endif()

add_library(flipperlib_libusb SHARED ${LIBUSB_COMMON_SRC} ${LIBUSB_OS_SRC})

target_include_directories(flipperlib_libusb PRIVATE
  "${LIBUSB_CONFIG_DIR}"
  "${LIBUSB_DIR}"
  "${LIBUSB_DIR}/os"
)
target_include_directories(flipperlib_libusb INTERFACE "${LIBUSB_DIR}")

if(WIN32)
  # Same file name the Dart loader and every other libusb consumer expect.
  set_target_properties(flipperlib_libusb PROPERTIES
    OUTPUT_NAME "libusb-1.0"
    PREFIX ""
  )
  if(MSVC)
    target_compile_definitions(flipperlib_libusb PRIVATE _CRT_SECURE_NO_WARNINGS)
    target_compile_options(flipperlib_libusb PRIVATE /W3)
  endif()
  target_link_libraries(flipperlib_libusb PRIVATE kernel32)
else()
  # Upstream android/jni/libusb.mk: module libusb1.0 → libusb1.0.so.
  set_target_properties(flipperlib_libusb PROPERTIES OUTPUT_NAME "usb1.0")
  target_compile_options(flipperlib_libusb PRIVATE -fvisibility=hidden -pthread)
  target_link_libraries(flipperlib_libusb PRIVATE log)
endif()
