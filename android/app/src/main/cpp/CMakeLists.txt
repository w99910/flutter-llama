cmake_minimum_required(VERSION 3.10)
project(llamacpp_project)

# --- Enable Vulkan for GPU acceleration on Android ---
find_package(Vulkan)

# --- 1. Define the Source Files ---
# Point to the new 'src' directory for all source files.
set(LLAMA_SOURCES
    llama.cpp/src/llama.cpp
    llama.cpp/src/ggml.c
    llama.cpp/src/ggml-alloc.c
    llama.cpp/src/ggml-backend.c
    llama.cpp/src/ggml-quants.c
)

# Add Vulkan backend source if Vulkan is found
if(Vulkan_FOUND)
    message(STATUS "Vulkan found! Enabling GPU acceleration")
    list(APPEND LLAMA_SOURCES llama.cpp/ggml/src/ggml-vulkan/ggml-vulkan.cpp)
else()
    message(WARNING "Vulkan NOT found. GPU acceleration will be disabled.")
endif()

# --- 2. Create the Library ---
# This creates the final libllamacpp.so file.
add_library(
    llamacpp
    SHARED
    ${LLAMA_SOURCES}
)

# --- 3. Define and Add Include Directories ---
# Add the new 'include' and 'src' directories so the compiler can find headers.
target_include_directories(llamacpp PUBLIC
    # For public headers like llama.h
    llama.cpp/include

    # For internal ggml headers
    llama.cpp/src/ggml

    # For common utility headers
    llama.cpp/common
)

# Add Vulkan include directories if found
if(Vulkan_FOUND)
    target_include_directories(llamacpp PRIVATE ${Vulkan_INCLUDE_DIRS})
endif()

# --- 4. Set Compiler Flags and Properties ---
target_compile_definitions(llamacpp PRIVATE -DGGML_USE_K_QUANTS)

# Enable Vulkan if available
if(Vulkan_FOUND)
    target_compile_definitions(llamacpp PRIVATE -DGGML_USE_VULKAN)
    message(STATUS "GGML_USE_VULKAN enabled")
endif()

set_target_properties(llamacpp PROPERTIES CXX_STANDARD 11)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -static-libstdc++")

# --- 5. Link Against Android Libraries ---
find_library(log-lib log)
target_link_libraries(llamacpp ${log-lib})

# Link Vulkan library if found
if(Vulkan_FOUND)
    target_link_libraries(llamacpp ${Vulkan_LIBRARIES})
    message(STATUS "Linking Vulkan libraries: ${Vulkan_LIBRARIES}")
endif()