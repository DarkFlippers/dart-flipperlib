cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "flipperlib")
project(${PROJECT_NAME} LANGUAGES CXX)

# libusb-1.0.dll for raw-USB DFU / recovery is built from the vendored sources
# and installed next to the executable (see src/libusb and lib/src/dfu/libusb).
# The Win32 system DLLs the hotplug / serial code needs are resolved from the
# system at runtime.
add_subdirectory(
  "${CMAKE_CURRENT_SOURCE_DIR}/../src/libusb"
  "${CMAKE_CURRENT_BINARY_DIR}/libusb"
)

set(flipperlib_bundled_libraries
  "$<TARGET_FILE:flipperlib_libusb>"
  PARENT_SCOPE
)
