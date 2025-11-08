cmake_minimum_required(VERSION 3.10)
project(llamacpp_project)

# --- 1. Define the Source Files ---
# Point to the new 'src' directory for all source files.
set(LLAMA_SOURCES
    llama.cpp/src/llama.cpp
    llama.cpp/src/ggml.c
    llama.cpp/src/ggml-alloc.c
    llama.cpp/src/ggml-backend.c
    llama.cpp/src/ggml-quants.c
)

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

# --- 4. Set Compiler Flags and Properties ---
# No changes needed here.
target_compile_definitions(llamacpp PRIVATE -DGGML_USE_K_QUANTS)
set_target_properties(llamacpp PROPERTIES CXX_STANDARD 11)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -static-libstdc++")

# --- 5. Link Against Android Libraries ---
# No changes needed here.
find_library(log-lib log)
target_link_libraries(llamacpp ${log-lib})