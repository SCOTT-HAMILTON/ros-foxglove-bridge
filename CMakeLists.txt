cmake_minimum_required(VERSION 3.10.2)

if(POLICY CMP0048)
  cmake_policy(SET CMP0048 NEW)
  set(CMAKE_POLICY_DEFAULT_CMP0048 NEW)
endif()
if(POLICY CMP0024)
  cmake_policy(SET CMP0024 NEW)
  set(CMAKE_POLICY_DEFAULT_CMP0024 NEW)
endif()

project(foxglove_bridge LANGUAGES CXX VERSION 0.8.5)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

macro(enable_strict_compiler_warnings target)
  if (MSVC)
    target_compile_options(${target} PRIVATE /WX /W4)
  elseif(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic -Werror -Wold-style-cast -Wfloat-equal -Wmost -Wunused-exception-parameter)
  else()
    target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic -Werror -Wold-style-cast -Wfloat-equal)
  endif()
endmacro()

find_package(nlohmann_json QUIET)
find_package(OpenSSL REQUIRED)
find_package(Threads REQUIRED)
find_package(websocketpp REQUIRED)
find_package(ZLIB REQUIRED)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE RelWithDebInfo)
endif()

option(USE_FOXGLOVE_SDK "Build with Foxglove SDK" OFF)
add_definitions(-DUSE_FOXGLOVE_SDK=${USE_FOXGLOVE_SDK})

# Determine wheter to use standalone or boost asio
option(USE_ASIO_STANDALONE "Build with standalone ASIO" ON)
if(USE_ASIO_STANDALONE)
  message(STATUS "Using standalone ASIO")
  add_definitions(-DASIO_STANDALONE)
else()
  message(STATUS "Using Boost ASIO")
  find_package(Boost REQUIRED)
endif(USE_ASIO_STANDALONE)

# Detect big-endian architectures
include(TestBigEndian)
TEST_BIG_ENDIAN(ENDIAN)
if (ENDIAN)
  add_compile_definitions(ARCH_IS_BIG_ENDIAN=1)
endif()

if(USE_FOXGLOVE_SDK)
  # if (CMAKE_SYSTEM_NAME STREQUAL "Linux" AND CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64")
  #   set(FOXGLOVE_SDK_RELEASES "https://github.com/foxglove/foxglove-sdk/releases/download/sdk%2Fv0.9.0/foxglove-v0.9.0-cpp-aarch64-unknown-linux-gnu.zip" "a554f82b3d1c3096457887bccee7088646b729494ec18909846ac7fcdd06ee1d")
  # elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND CMAKE_SYSTEM_PROCESSOR STREQUAL "x86_64")
  #   set(FOXGLOVE_SDK_RELEASES "https://github.com/foxglove/foxglove-sdk/releases/download/sdk%2Fv0.9.0/foxglove-v0.9.0-cpp-x86_64-unknown-linux-gnu.zip" "48ea17c348583154d7c1934c9f7e82f57067e2afa76b586e1f7ac14cc6b6c1d0")
  # else()
  #   message(FATAL_ERROR "Unsupported platform: ${CMAKE_SYSTEM_PROCESSOR}-${CMAKE_SYSTEM_NAME}")
  # endif()

  # list(GET FOXGLOVE_SDK_RELEASES 0 url)
  # list(GET FOXGLOVE_SDK_RELEASES 1 hash)

  if (CMAKE_SYSTEM_NAME STREQUAL "Linux" AND CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64")
    set(FOXGLOVE_SDK_ZIP_PATH ${CMAKE_CURRENT_SOURCE_DIR}/tmp/foxglove-aarch64.zip)
  elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND CMAKE_SYSTEM_PROCESSOR STREQUAL "x86_64")
    set(FOXGLOVE_SDK_ZIP_PATH ${CMAKE_CURRENT_SOURCE_DIR}/tmp/foxglove-x86_64.zip)
  else()
    message(FATAL_ERROR "Unsupported platform: ${CMAKE_SYSTEM_PROCESSOR}-${CMAKE_SYSTEM_NAME}")
  endif()


  # Download Foxglove SDK shared lib
  include(FetchContent)
  FetchContent_Declare(
    foxglove_sdk
    # URL ${url}
    # URL_HASH SHA256=${hash}
    URL ${FOXGLOVE_SDK_ZIP_PATH}
  )
  FetchContent_MakeAvailable(foxglove_sdk)

  add_library(foxglove_sdk SHARED)
  target_include_directories(foxglove_sdk SYSTEM
    PUBLIC
      $<BUILD_INTERFACE:${foxglove_sdk_SOURCE_DIR}/include>
      $<INSTALL_INTERFACE:include>
  )
  file(GLOB_RECURSE FOXGLOVE_SDK_SOURCES CONFIGURE_DEPENDS "${foxglove_sdk_SOURCE_DIR}/src/*.cpp")
  target_sources(foxglove_sdk PRIVATE ${FOXGLOVE_SDK_SOURCES})
  target_link_libraries(foxglove_sdk PRIVATE ${foxglove_sdk_SOURCE_DIR}/lib/libfoxglove.a)
endif()

# Get git commit hash and replace variables in version.cpp.in
find_program(GIT_SCM git DOC "Git version control")
if (GIT_SCM)
  execute_process(
    COMMAND ${GIT_SCM} describe --always --dirty --exclude="*"
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    OUTPUT_VARIABLE FOXGLOVE_BRIDGE_GIT_HASH
    OUTPUT_STRIP_TRAILING_WHITESPACE
  )
endif()
set(FOXGLOVE_BRIDGE_VERSION "${CMAKE_PROJECT_VERSION}")
configure_file(foxglove_bridge_base/src/version.cpp.in
               foxglove_bridge_base/src/version.cpp @ONLY)

# Build the foxglove_bridge_base library
add_library(foxglove_bridge_base SHARED
  foxglove_bridge_base/src/base64.cpp
  foxglove_bridge_base/src/foxglove_bridge.cpp
  foxglove_bridge_base/src/parameter.cpp
  foxglove_bridge_base/src/serialization.cpp
  foxglove_bridge_base/src/server_factory.cpp
  foxglove_bridge_base/src/test/test_client.cpp
  # Generated:
  ${CMAKE_CURRENT_BINARY_DIR}/foxglove_bridge_base/src/version.cpp
)
target_include_directories(foxglove_bridge_base
  PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/foxglove_bridge_base/include>
    $<INSTALL_INTERFACE:include>
)
target_link_libraries(foxglove_bridge_base
  OpenSSL::Crypto
  OpenSSL::SSL
  ZLIB::ZLIB
  ${CMAKE_THREAD_LIBS_INIT}
)
if(nlohmann_json_FOUND)
  target_link_libraries(foxglove_bridge_base nlohmann_json::nlohmann_json)
else()
  message(STATUS "nlohmann_json not found, will search at compile time")
endif()
enable_strict_compiler_warnings(foxglove_bridge_base)

message(STATUS "ROS_VERSION: " $ENV{ROS_VERSION})
message(STATUS "ROS_DISTRO: " $ENV{ROS_DISTRO})
message(STATUS "ROS_ROOT: " $ENV{ROS_ROOT})
if("$ENV{ROS_VERSION}" STREQUAL "1")
  # ROS 1
  if(CATKIN_DEVEL_PREFIX OR catkin_FOUND OR CATKIN_BUILD_BINARY_PACKAGE)
    message(STATUS "Building with catkin")
    set(ROS_BUILD_TYPE "catkin")

    find_package(catkin REQUIRED COMPONENTS nodelet resource_retriever ros_babel_fish rosgraph_msgs roslib roscpp)
    find_package(Boost REQUIRED)

    catkin_package(
      INCLUDE_DIRS foxglove_bridge_base/include
      LIBRARIES foxglove_bridge_base foxglove_bridge_nodelet
      CATKIN_DEPENDS nodelet resource_retriever ros_babel_fish rosgraph_msgs roslib roscpp
      DEPENDS Boost
    )

    add_library(foxglove_bridge_nodelet
      ros1_foxglove_bridge/src/ros1_foxglove_bridge_nodelet.cpp
      ros1_foxglove_bridge/src/param_utils.cpp
      ros1_foxglove_bridge/src/service_utils.cpp
    )
    target_include_directories(foxglove_bridge_nodelet
      SYSTEM PRIVATE
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/foxglove_bridge_base/include>
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/ros1_foxglove_bridge/include>
        $<INSTALL_INTERFACE:include>
        ${catkin_INCLUDE_DIRS}
    )
    target_link_libraries(foxglove_bridge_nodelet foxglove_bridge_base ${catkin_LIBRARIES})
    enable_strict_compiler_warnings(foxglove_bridge_nodelet)

    add_executable(foxglove_bridge ros1_foxglove_bridge/src/ros1_foxglove_bridge_node.cpp)
    target_include_directories(foxglove_bridge SYSTEM PRIVATE ${catkin_INCLUDE_DIRS})
    target_link_libraries(foxglove_bridge ${catkin_LIBRARIES})
    enable_strict_compiler_warnings(foxglove_bridge)

    install(DIRECTORY foxglove_bridge_base/include/foxglove_bridge/
        DESTINATION ${CATKIN_PACKAGE_INCLUDE_DESTINATION}
        PATTERN "*.hpp"
        PATTERN ".git" EXCLUDE # ou d'autres motifs à exclure
    )
    install(DIRECTORY ros1_foxglove_bridge/include/foxglove_bridge/
        DESTINATION ${CATKIN_PACKAGE_INCLUDE_DESTINATION}
        PATTERN "*.hpp"
        PATTERN ".git" EXCLUDE # ou d'autres motifs à exclure
    )
  else()
    message(FATAL_ERROR "Could not find catkin")
  endif()
elseif("$ENV{ROS_VERSION}" STREQUAL "2")
  # ROS 2
  if(DEFINED ENV{AMENT_PREFIX_PATH})
    message(STATUS "Building with ament_cmake")
    set(ROS_BUILD_TYPE "ament_cmake")


    find_package(ament_cmake REQUIRED)
    find_package(rosgraph_msgs REQUIRED)
    find_package(rclcpp REQUIRED)
    find_package(rclcpp_components REQUIRED)
    find_package(resource_retriever REQUIRED)
    find_package(rosx_introspection REQUIRED)

    if(USE_FOXGLOVE_SDK)
      set(ros2_foxglove_bridge_src_dir ros2_foxglove_bridge_sdk)
    else()
      set(ros2_foxglove_bridge_src_dir ros2_foxglove_bridge)
    endif()

    add_library(foxglove_bridge_component SHARED
      ${ros2_foxglove_bridge_src_dir}/src/message_definition_cache.cpp
      ${ros2_foxglove_bridge_src_dir}/src/param_utils.cpp
      ${ros2_foxglove_bridge_src_dir}/src/ros2_foxglove_bridge.cpp
      ${ros2_foxglove_bridge_src_dir}/src/parameter_interface.cpp
      ${ros2_foxglove_bridge_src_dir}/src/generic_client.cpp
    )

    target_compile_definitions(foxglove_bridge_component
      PRIVATE
        RESOURCE_RETRIEVER_VERSION_MAJOR=${resource_retriever_VERSION_MAJOR}
        RESOURCE_RETRIEVER_VERSION_MINOR=${resource_retriever_VERSION_MINOR}
        RESOURCE_RETRIEVER_VERSION_PATCH=${resource_retriever_VERSION_PATCH}
    )

    target_include_directories(foxglove_bridge_component
      PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/foxglove_bridge_base/include>
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/${ros2_foxglove_bridge_src_dir}/include>
        $<INSTALL_INTERFACE:include>
    )

    target_link_libraries(foxglove_bridge_component
      foxglove_bridge_base
      ${rosgraph_msgs_TARGETS}
      ament_index_cpp::ament_index_cpp
      rclcpp::rclcpp
      rclcpp_components::component
      rclcpp_components::component_manager
      resource_retriever::resource_retriever
      rosx_introspection::rosx_introspection
    )

    if (USE_FOXGLOVE_SDK)
      target_link_libraries(foxglove_bridge_component foxglove_sdk)
    endif()

    rclcpp_components_register_nodes(foxglove_bridge_component "foxglove_bridge::FoxgloveBridge")
    enable_strict_compiler_warnings(foxglove_bridge_component)

    add_executable(foxglove_bridge
      ${ros2_foxglove_bridge_src_dir}/src/ros2_foxglove_bridge_node.cpp
    )
    target_include_directories(foxglove_bridge SYSTEM PRIVATE ${rclcpp_INCLUDE_DIRS})
    target_link_libraries(foxglove_bridge
      foxglove_bridge_component
      rclcpp::rclcpp
      rclcpp_components::component
      rclcpp_components::component_manager
    )
    enable_strict_compiler_warnings(foxglove_bridge)
  else()
    message(FATAL_ERROR "Could not find ament_cmake")
  endif()
else()
  message(FATAL_ERROR "ROS_VERSION environment variable must be 1 or 2")
endif()

#### TESTS #####################################################################

if(ROS_BUILD_TYPE STREQUAL "catkin")
  if (CATKIN_ENABLE_TESTING)
    message(STATUS "Building tests with catkin")

    find_package(catkin REQUIRED COMPONENTS roscpp std_msgs std_srvs)
    if(NOT "$ENV{ROS_DISTRO}" STREQUAL "melodic")
      find_package(GTest REQUIRED)
    endif()
    find_package(rostest REQUIRED)
    find_package(Boost REQUIRED COMPONENTS system)

    catkin_add_gtest(version_test foxglove_bridge_base/tests/version_test.cpp)
    target_link_libraries(version_test foxglove_bridge_base ${Boost_LIBRARIES})
    enable_strict_compiler_warnings(version_test)

    catkin_add_gtest(serialization_test foxglove_bridge_base/tests/serialization_test.cpp)
    target_link_libraries(serialization_test foxglove_bridge_base ${Boost_LIBRARIES})
    enable_strict_compiler_warnings(foxglove_bridge)

    catkin_add_gtest(base64_test foxglove_bridge_base/tests/base64_test.cpp)
    target_link_libraries(base64_test foxglove_bridge_base ${Boost_LIBRARIES})
    enable_strict_compiler_warnings(foxglove_bridge)

    add_rostest_gtest(smoke_test ros1_foxglove_bridge/tests/smoke.test ros1_foxglove_bridge/tests/smoke_test.cpp)
    target_include_directories(smoke_test SYSTEM PRIVATE
      $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/foxglove_bridge_base/include>
      ${catkin_INCLUDE_DIRS}
      $<INSTALL_INTERFACE:include>
    )
    target_link_libraries(smoke_test foxglove_bridge_base ${catkin_LIBRARIES})
    enable_strict_compiler_warnings(smoke_test)
  endif()
elseif(ROS_BUILD_TYPE STREQUAL "ament_cmake")
  if(BUILD_TESTING)
    message(STATUS "Building tests with ament_cmake")

    find_package(ament_cmake_gtest REQUIRED)
    find_package(ament_lint_auto REQUIRED)
    ament_lint_auto_find_test_dependencies()

    ament_add_gtest(version_test foxglove_bridge_base/tests/version_test.cpp)
    target_link_libraries(version_test foxglove_bridge_base)
    enable_strict_compiler_warnings(version_test)

    ament_add_gtest(serialization_test foxglove_bridge_base/tests/serialization_test.cpp)
    target_link_libraries(serialization_test foxglove_bridge_base)
    enable_strict_compiler_warnings(serialization_test)

    ament_add_gtest(base64_test foxglove_bridge_base/tests/base64_test.cpp)
    target_link_libraries(base64_test foxglove_bridge_base)
    enable_strict_compiler_warnings(base64_test)

    # Repeat tests several times to catch nondeterministic issues
    ament_add_gtest(smoke_test ${ros2_foxglove_bridge_src_dir}/tests/smoke_test.cpp ENV GTEST_REPEAT=50 TIMEOUT 600)
    target_link_libraries(smoke_test
      foxglove_bridge_component
      ${std_msgs_TARGETS}
      ${std_srvs_TARGETS}
      rclcpp::rclcpp
      rclcpp_components::component
      rclcpp_components::component_manager
    )
    enable_strict_compiler_warnings(smoke_test)

    ament_add_gtest(utils_test ${ros2_foxglove_bridge_src_dir}/tests/utils_test.cpp)
    target_link_libraries(utils_test foxglove_bridge_component)
    enable_strict_compiler_warnings(utils_test)
  endif()
endif()

#### INSTALL ###################################################################

if(ROS_BUILD_TYPE STREQUAL "catkin")
    install(TARGETS foxglove_bridge
      RUNTIME DESTINATION ${CATKIN_PACKAGE_BIN_DESTINATION}
    )
    install(TARGETS foxglove_bridge_base foxglove_bridge_nodelet
      ARCHIVE DESTINATION ${CATKIN_PACKAGE_LIB_DESTINATION}
      LIBRARY DESTINATION ${CATKIN_PACKAGE_LIB_DESTINATION}
      RUNTIME DESTINATION ${CATKIN_GLOBAL_BIN_DESTINATION}
    )
    install(FILES nodelets.xml
      DESTINATION ${CATKIN_PACKAGE_SHARE_DESTINATION}
    )
    install(DIRECTORY ros1_foxglove_bridge/launch/
      DESTINATION ${CATKIN_PACKAGE_SHARE_DESTINATION}/launch
    )
elseif(ROS_BUILD_TYPE STREQUAL "ament_cmake")
    install(FILES ros2_foxglove_bridge/include/foxglove_bridge/ros2_foxglove_bridge.hpp
      DESTINATION include/${PROJECT_NAME}/
    )
    install(TARGETS foxglove_bridge
      DESTINATION lib/${PROJECT_NAME}
    )
    install(TARGETS foxglove_bridge_base foxglove_bridge_component
      ARCHIVE DESTINATION lib
      LIBRARY DESTINATION lib
      RUNTIME DESTINATION bin
    )
    install(DIRECTORY ros2_foxglove_bridge/launch
      DESTINATION share/${PROJECT_NAME}/
    )
    install(FILES ros2_foxglove_bridge/include/foxglove_bridge/utils.hpp
      DESTINATION include/${PROJECT_NAME}/
    )
    ament_export_libraries(foxglove_bridge_base foxglove_bridge_component)
    ament_package()
endif()
