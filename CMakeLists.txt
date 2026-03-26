# Credit => https://github.com/napi-bindings/quickjs-build/blob/master/CMakeLists.txt

cmake_minimum_required(VERSION 3.16)

project(quickjs LANGUAGES C)

if(WIN32)
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -static")
endif()

set(DEFAULT_QUICKJS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/quickjs")
if(NOT EXISTS "${DEFAULT_QUICKJS_DIR}/quickjs.c")
  set(DEFAULT_QUICKJS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../quickjs")
endif()

set(QUICKJS_DIR "${DEFAULT_QUICKJS_DIR}" CACHE PATH "Path to a QuickJS source checkout")

if(NOT EXISTS "${QUICKJS_DIR}/quickjs.c")
  message(
    FATAL_ERROR
      "QuickJS source not found. Set QUICKJS_DIR to a checkout containing quickjs.c.")
endif()

set(qjs_cflags -Wall -D_GNU_SOURCE)
if(CMAKE_C_COMPILER_ID MATCHES "AppleClang|Clang")
  list(
    APPEND
    qjs_cflags
    -Wextra
    -Wno-sign-compare
    -Wno-missing-field-initializers
    -Wno-unused-parameter
    -Wno-unused-variable
    -funsigned-char)
else()
  list(APPEND qjs_cflags -Wno-array-bounds -Wno-unused-variable
       -Wno-unused-but-set-variable)
endif()

file(READ ${QUICKJS_DIR}/VERSION QJS_VERSION_STR)
string(REGEX REPLACE "\n$" "" QJS_VERSION_STR "${QJS_VERSION_STR}")

message(
  STATUS
    "summary of build options:
    Target system:   ${CMAKE_SYSTEM_NAME}
    Compiler:
      C compiler:    ${CMAKE_C_COMPILER}
      CFLAGS:        ${qjs_cflags}
")

add_library(qjs STATIC ${QUICKJS_DIR}/cutils.c ${QUICKJS_DIR}/libbf.c
                       ${QUICKJS_DIR}/libregexp.c ${QUICKJS_DIR}/libunicode.c
                       ${QUICKJS_DIR}/quickjs.c ${QUICKJS_DIR}/quickjs-libc.c)
set_target_properties(qjs PROPERTIES C_STANDARD 11 C_STANDARD_REQUIRED ON)
target_compile_options(qjs PRIVATE ${qjs_cflags})
target_compile_definitions(qjs PUBLIC QJS_VERSION_STR="${QJS_VERSION_STR}")
target_compile_definitions(qjs PUBLIC CONFIG_BIGNUM
                                      CONFIG_VERSION="${QJS_VERSION_STR}")
if(CMAKE_BUILD_TYPE MATCHES Debug)
  target_compile_definitions(qjs PRIVATE DUMP_LEAKS)
endif()

target_include_directories(qjs PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/libs/include)
target_include_directories(qjs PRIVATE ${QUICKJS_DIR})
if("${CMAKE_CXX_COMPILER_ID}" STREQUAL "GNU")
  target_link_libraries(qjs atomic)
endif()

if(UNIX)
  target_link_libraries(qjs PRIVATE m dl pthread)
endif()

add_executable(qjsc ${QUICKJS_DIR}/qjsc.c)
target_link_libraries(qjsc PUBLIC qjs)

add_custom_command(
    OUTPUT repl.c qjscalc.c
    COMMAND qjsc -c -o ${CMAKE_CURRENT_BINARY_DIR}/repl.c -m
            ${QUICKJS_DIR}/repl.js
    COMMAND qjsc -c -o ${CMAKE_CURRENT_BINARY_DIR}/qjscalc.c -m
            ${QUICKJS_DIR}/qjscalc.js
    DEPENDS qjsc)

add_executable(quickjs ${QUICKJS_DIR}/qjs.c ${CMAKE_CURRENT_BINARY_DIR}/qjscalc.c
                       ${CMAKE_CURRENT_BINARY_DIR}/repl.c)

target_link_libraries(quickjs PUBLIC qjs)

add_executable(run-test262 ${QUICKJS_DIR}/run-test262.c)
target_link_libraries(run-test262 PUBLIC qjs)
