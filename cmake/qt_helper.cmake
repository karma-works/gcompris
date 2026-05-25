#=============================================================================
# SPDX-FileCopyrightText: 2014 Thibaut ROMAIN <thibrom@gmail.com>
#
# SPDX-License-Identifier: BSD-3-Clause
#=============================================================================
function(getQtPluginPaths _plugin_target _absolute_path _subdir _file)
  getQtPluginsPath(_qt_plugins_path)
  get_target_property(_plugin_path ${_plugin_target} LOCATION)
  if(NOT _plugin_path)
    message(FATAL_ERROR "Could not find ${_plugin_target} plugin path")
  endif()
  get_filename_component(_plugin_file ${_plugin_path} NAME)
  get_filename_component(_plugin_dir ${_plugin_path} PATH)
  file(RELATIVE_PATH _plugin_subdir ${_qt_plugins_path} ${_plugin_dir})
  get_filename_component(_plugin_install_path ${_plugin_path} REALPATH)
  set(${_absolute_path} ${_plugin_install_path} PARENT_SCOPE)
  set(${_subdir} ${_plugin_subdir} PARENT_SCOPE)
  set(${_file} ${_plugin_file} PARENT_SCOPE)
endfunction()

# Determine Qt5's plugin-path deriving from lib-dir and trying different
# locations corresponding to different directory layouts, e.g.:
#
# Debian:
#   /usr/lib/i386-linux-gnu/libQt5Qml.so.5.4.1
#   /usr/lib/i386-linux-gnu/qt5/plugins/
# Opensuse:
#   /usr/lib64/libQt5Multimedia.so.5
#   /usr/lib64/qt5/plugins/
# Archlinux:
#   /usr/lib/libQt5Qml.so.5.15
#   /usr/lib/qt/plugins/
# Qt installer:
#   /opt/Qt5.5.1/5.5/gcc/lib/libQt5Qml.so.5.5.1
#   /opt/Qt5.5.1/5.5/gcc/plugins/
#
# The qml/-dir is always a sibling of the plugins/ dir.
function(getQtPluginsPath _path)
  get_target_property(_lib_file ${QT_MAJOR}::Qml LOCATION)
  get_filename_component(_lib_dir ${_lib_file} PATH)
  # try $_lib_dir/qt5/plugins (Debian/Opensuse)
  set(_plugin_root ${_lib_dir}/qt5/plugins)
  if(NOT IS_DIRECTORY ${_plugin_root})
    # try $_lib_dir/qt/plugins (Archlinux)
    set(_plugin_root ${_lib_dir}/qt/plugins)
    if(NOT IS_DIRECTORY ${_plugin_root})
      # try $_lib_dir/../plugins (Qt installer)
      get_filename_component(_lib_dir_base ${_lib_dir} PATH)
      if(APPLE)
        set(_plugin_root ${_lib_dir_base}/../plugins)
      else()
        set(_plugin_root ${_lib_dir_base}/plugins)
      endif()
    endif()
  endif()
  if(NOT IS_DIRECTORY ${_plugin_root})
    find_program(QMAKE_EXECUTABLE
      NAMES qmake6 qmake
      HINTS
        ${CMAKE_PREFIX_PATH}/bin
        ${CMAKE_PREFIX_PATH}/opt/qt/bin
        /opt/homebrew/opt/qt/bin
        /opt/homebrew/bin)
    if(QMAKE_EXECUTABLE)
      execute_process(
        COMMAND ${QMAKE_EXECUTABLE} -query QT_INSTALL_PLUGINS
        OUTPUT_VARIABLE _qmake_plugin_root
        OUTPUT_STRIP_TRAILING_WHITESPACE)
      if(IS_DIRECTORY ${_qmake_plugin_root})
        set(_plugin_root ${_qmake_plugin_root})
      endif()
    endif()
  endif()
  set(${_path} ${_plugin_root} PARENT_SCOPE)
endfunction()

function(getQtQmlPath _path)
  getQtPluginsPath(_qt_plugins_path)
  get_filename_component(_root ${_qt_plugins_path} PATH)
  set(${_path} ${_root}/qml PARENT_SCOPE)
endfunction()

function(installQtPlugin _plugin _dest_dir _lib)
  getQtPluginPaths(${_plugin} _absolute_path _plugin_subdir _plugin_file)
  #needed to build with msys2
  if(MINGW)
    string(REGEX REPLACE "share/qt5/" "" _plugin_subdir ${_plugin_subdir})
  endif()
  install(FILES ${_absolute_path} DESTINATION ${_dest_dir}/${_plugin_subdir})
  set(_lib "\${CMAKE_INSTALL_PREFIX}/${_dest_dir}/${_plugin_subdir}/${_plugin_file}" PARENT_SCOPE)
endfunction()

function(installQtPlugin2 _plugin _dest_dir _lib)
  get_filename_component(_plugin_file ${_plugin} NAME)
  set(_ext ${CMAKE_SHARED_LIBRARY_SUFFIX})
  get_filename_component(_plugin_subdir ${_plugin} PATH)
  getQtPluginsPath(_qt_plugin_path)
  set(_requested_plugin_path "${_qt_plugin_path}/${_plugin_subdir}/${_plugin_file}${_ext}")
  if(NOT EXISTS ${_requested_plugin_path})
    message(STATUS "Skipping optional Qt plugin ${_plugin}: ${_requested_plugin_path} was not found")
    set(_lib "" PARENT_SCOPE)
    return()
  endif()
  file(GLOB plugin_files LIST_DIRECTORIES false "${_qt_plugin_path}/${_plugin_subdir}/*")
  set(_resolved_plugin_files)
  foreach(_plugin_file_path ${plugin_files})
    get_filename_component(_resolved_plugin_file_path ${_plugin_file_path} REALPATH)
    list(APPEND _resolved_plugin_files ${_resolved_plugin_file_path})
  endforeach()
  install(FILES ${_resolved_plugin_files} DESTINATION ${_dest_dir}/${_plugin_subdir})
  if(CMAKE_HOST_WIN32)
    set(_dbg_suffix "d")
  else()
    set(_dbg_suffix "_debug")
  endif()
  set(_install_path \${CMAKE_INSTALL_PREFIX}/${_dest_dir}/${_plugin_subdir})
  if("${CMAKE_BUILD_TYPE}" STREQUAL "Debug")
    install(CODE "file(REMOVE \"${_install_path}/${_plugin_file}${_ext}\")")
    set(_plugin_file ${_plugin_file}${_dbg_suffix}${_ext})
  else()
    install(CODE "file(REMOVE \"${_install_path}/${_plugin_file}${_dbg_suffix}${_ext}\")")
    set(_plugin_file ${_plugin_file}${_ext})
  endif()
  set(_lib "${_install_path}/${_plugin_file}" PARENT_SCOPE)
endfunction()

function(installQmlPlugin _plugin _dest_dir _lib)
  get_filename_component(_plugin_file ${_plugin} NAME)
  set(_ext ${CMAKE_SHARED_LIBRARY_SUFFIX})
  get_filename_component(_qml_subdir ${_plugin} PATH)
  get_filename_component(_qml_subdir_root ${_qml_subdir} PATH)
  getQtQmlPath(_qt_qml_path)
  file(GLOB plugin_files LIST_DIRECTORIES false "${_qt_qml_path}/${_qml_subdir}/*")
  # Usually, a plugin is a qmldir, plugins.qmltypes and a library
  # For QtQuick.Controls.Basic, there are also .qml we don't need to package, so ignore them
  list(FILTER plugin_files EXCLUDE REGEX "\.qml$")

  set(_resolved_plugin_files)
  foreach(_plugin_file_path ${plugin_files})
    get_filename_component(_resolved_plugin_file_path ${_plugin_file_path} REALPATH)
    list(APPEND _resolved_plugin_files ${_resolved_plugin_file_path})
  endforeach()
  install(FILES ${_resolved_plugin_files} DESTINATION ${_dest_dir}/${_qml_subdir})
  if(CMAKE_HOST_WIN32)
    set(_dbg_suffix "d")
  else()
    set(_dbg_suffix "_debug")
  endif()
  set(_install_path \${CMAKE_INSTALL_PREFIX}/${_dest_dir}/${_qml_subdir})
  if("${CMAKE_BUILD_TYPE}" STREQUAL "Debug")
    install(CODE "file(REMOVE \"${_install_path}/${_plugin_file}${_ext}\")")
    set(_plugin_file ${_plugin_file}${_dbg_suffix}${_ext})
  else()
    install(CODE "file(REMOVE \"${_install_path}/${_plugin_file}${_dbg_suffix}${_ext}\")")
    set(_plugin_file ${_plugin_file}${_ext})
  endif()
  set(_lib "${_install_path}/${_plugin_file}" PARENT_SCOPE)
endfunction()

#install_with_symlinks(FILE ${OPENSSL_CRYPTO_LIBRARY} DESTINATION bin)
function(install_with_symlinks)
    set(oneValueArgs FILE DESTINATION)
    cmake_parse_arguments(ARGS "" "${oneValueArgs}"
                          "" ${ARGN})

    if(IS_SYMLINK ${ARGS_FILE})
      set(SYMLINK_LIB)
      file(READ_SYMLINK "${ARGS_FILE}" SYMLINK_LIB)
      if(NOT IS_ABSOLUTE "${SYMLINK_LIB}")
        get_filename_component(dir "${ARGS_FILE}" DIRECTORY)
        set(SYMLINK_LIB "${dir}/${SYMLINK_LIB}")
      endif()
      install_with_symlinks(FILE ${SYMLINK_LIB} DESTINATION ${ARGS_DESTINATION})

      # On some unix (ubuntu 18.04 at least), we can have things like
      # libprotobuf.so -> libprotobuf.so.10.0.0
      # libprotobuf.so.10 -> libprotobuf.so.10.0.0
      # (where we would have expected libprotobuf.so -> libprotobuf.so.10 -> libprotobuf.so.10.0.0)
      # in this case, we do a workaround to get the libprotobuf.so.10 using objdump
      if(UNIX)
  execute_process(COMMAND ${CMAKE_OBJDUMP} -p ${ARGS_FILE}
    OUTPUT_VARIABLE OBJDUMP_OUTPUT)
  string(REGEX REPLACE ".*SONAME *([A-Za-z0-9\.]*).*" "\\1"
    LIB_SO_VAR ${OBJDUMP_OUTPUT})
        get_filename_component(dir "${ARGS_FILE}" DIRECTORY)
        set(LIB_SO_VAR "${dir}/${LIB_SO_VAR}")
  if(NOT LIB_SO_VAR STREQUAL ARGS_FILE AND NOT LIB_SO_VAR STREQUAL ${SYMLINK_LIB})
    install_with_symlinks(FILE ${LIB_SO_VAR} DESTINATION bin)
  endif()
  # end of workaround
      endif()
    endif()
    message(STATUS "Install ${ARGS_FILE} in ${ARGS_DESTINATION}")
    install(FILES ${ARGS_FILE} DESTINATION ${ARGS_DESTINATION})
endfunction()
