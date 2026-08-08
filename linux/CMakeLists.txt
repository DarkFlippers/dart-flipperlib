cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "flipperlib")
project(${PROJECT_NAME} LANGUAGES CXX)

# Nothing to bundle on Linux: libusb-1.0 and libc are resolved from the system
# at runtime (see lib/src/dfu/libusb and lib/src/transport/usb/hotplug).
set(flipperlib_bundled_libraries
  ""
  PARENT_SCOPE
)
