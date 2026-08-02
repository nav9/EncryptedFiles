cmake_minimum_required(VERSION 3.13)
project(encrypted_files_core C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(EF_BUILD_SHARED "Build shared library" ON)

set(EF_CORE_SOURCES
  src/secure_mem.c
  src/crypto_engine.c
  src/file_format.c
  src/stream_server.c
  src/ef_api.c
  third_party/monocypher/monocypher.c
)

if(EF_BUILD_SHARED)
  add_library(encrypted_files_core SHARED ${EF_CORE_SOURCES})
else()
  add_library(encrypted_files_core STATIC ${EF_CORE_SOURCES})
endif()

target_include_directories(encrypted_files_core
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
  PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/monocypher
)

if(WIN32)
  target_compile_definitions(encrypted_files_core PRIVATE EF_PLATFORM_WINDOWS _CRT_SECURE_NO_WARNINGS)
  target_link_libraries(encrypted_files_core PRIVATE ws2_32)
elseif(ANDROID)
  target_compile_definitions(encrypted_files_core PRIVATE EF_PLATFORM_ANDROID)
  find_library(log-lib log)
  target_link_libraries(encrypted_files_core PRIVATE ${log-lib})
elseif(APPLE)
  target_compile_definitions(encrypted_files_core PRIVATE EF_PLATFORM_APPLE)
else()
  target_compile_definitions(encrypted_files_core PRIVATE EF_PLATFORM_LINUX)
  target_link_libraries(encrypted_files_core PRIVATE pthread)
endif()

# Size / speed: optimize for size on Release to help low-RAM devices.
target_compile_options(encrypted_files_core PRIVATE
  $<$<CONFIG:Release>:-Os>
  $<$<CONFIG:RelWithDebInfo>:-O2>
  $<$<NOT:$<CONFIG:Debug>>:-ffunction-sections -fdata-sections>
)

if(NOT WIN32 AND NOT APPLE)
  target_link_options(encrypted_files_core PRIVATE
    $<$<NOT:$<CONFIG:Debug>>:-Wl,--gc-sections>
  )
endif()

install(TARGETS encrypted_files_core
  LIBRARY DESTINATION lib
  ARCHIVE DESTINATION lib
  RUNTIME DESTINATION bin
)
