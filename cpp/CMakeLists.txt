cmake_minimum_required(VERSION 3.16)
project(workshop_agent LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ---- Locate the SignalWire Agents C++ SDK ----
# Set SIGNALWIRE_SDK_DIR to the root of the cloned signalwire-agents-cpp repo.
# Example:  cmake .. -DSIGNALWIRE_SDK_DIR=$HOME/signalwire-agents-cpp
if(NOT DEFINED SIGNALWIRE_SDK_DIR)
    # Default: assume the SDK lives next to the workshop repo
    set(SIGNALWIRE_SDK_DIR "${CMAKE_SOURCE_DIR}/../sdks/signalwire-agents-cpp"
        CACHE PATH "Path to signalwire-agents-cpp repo root")
endif()

# Resolve to absolute so the message is unambiguous
get_filename_component(SIGNALWIRE_SDK_DIR "${SIGNALWIRE_SDK_DIR}" ABSOLUTE)
message(STATUS "Using SignalWire SDK at: ${SIGNALWIRE_SDK_DIR}")

if(NOT EXISTS "${SIGNALWIRE_SDK_DIR}/include/signalwire/agent/agent_base.hpp")
    message(FATAL_ERROR
        "Cannot find SignalWire SDK headers at ${SIGNALWIRE_SDK_DIR}.\n"
        "Clone the repo and pass -DSIGNALWIRE_SDK_DIR=/path/to/signalwire-agents-cpp")
endif()

# SDK headers + vendored deps (nlohmann/json, cpp-httplib)
include_directories(${SIGNALWIRE_SDK_DIR}/include)
include_directories(${SIGNALWIRE_SDK_DIR}/deps)

# Pre-built SDK library
# After building the SDK (cd signalwire-agents-cpp/build && cmake .. && make),
# the static library lives at signalwire-agents-cpp/build/libsignalwire_agents.a
set(SIGNALWIRE_SDK_LIB "${SIGNALWIRE_SDK_DIR}/build/libsignalwire_agents.a"
    CACHE FILEPATH "Path to libsignalwire_agents.a")

if(NOT EXISTS "${SIGNALWIRE_SDK_LIB}")
    message(FATAL_ERROR
        "Cannot find ${SIGNALWIRE_SDK_LIB}.\n"
        "Build the SDK first:  cd ${SIGNALWIRE_SDK_DIR} && mkdir -p build && cd build && cmake .. && make -j$(nproc)")
endif()

# System dependencies
find_package(OpenSSL REQUIRED)
find_package(Threads REQUIRED)

# ---- Workshop agent executable ----
# Point this at whichever step file you're working on.
# Default: agent.cpp in the project root (copy a step file there).
set(AGENT_SOURCE "${CMAKE_SOURCE_DIR}/agent.cpp"
    CACHE FILEPATH "Source file to compile")

if(NOT EXISTS "${AGENT_SOURCE}")
    message(FATAL_ERROR
        "No agent source found at ${AGENT_SOURCE}.\n"
        "Copy a step file:  cp steps/step04_hello_agent.cpp agent.cpp")
endif()

add_executable(agent ${AGENT_SOURCE})
target_link_libraries(agent
    ${SIGNALWIRE_SDK_LIB}
    OpenSSL::SSL OpenSSL::Crypto
    Threads::Threads
)
