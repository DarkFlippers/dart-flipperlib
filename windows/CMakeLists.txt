cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "flipperlib")
project(${PROJECT_NAME} LANGUAGES CXX)

# Nothing to bundle on Windows: libusb-1.0.dll and the Win32 system DLLs are
# resolved from the system at runtime (see lib/src/dfu/libusb and
# lib/src/transport/usb).
set(flipperlib_bundled_libraries
  ""
  PARENT_SCOPE
)
