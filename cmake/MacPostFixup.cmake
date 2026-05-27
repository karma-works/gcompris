if(APPLE)
  set(APP_DIR "${CMAKE_INSTALL_PREFIX}/gcompris-qt.app")
  set(SCRIPT_FILE "/tmp/gcompris_post_fixup_mac.sh")

  set(SCRIPT_CONTENT [=[#!/bin/bash
set -e

APP_DIR="__APP_DIR__"

echo "Patching Homebrew references in ${APP_DIR}..."
rm -rf "${APP_DIR}/Contents/MacOS/rcc" \
       "${APP_DIR}/Contents/MacOS/translations"
find "${APP_DIR}" -type f | while IFS= read -r file; do
  if file "$file" | grep -q 'Mach-O'; then
    otool -L "$file" | grep '/opt/homebrew' | awk '{print $1}' | while IFS= read -r dep; do
      libname=$(basename "$dep")
      if [[ "$file" == */MacOS/gcompris-qt ]]; then
        if [[ "$dep" == *.framework* ]]; then
          suffix=$(echo "$dep" | sed -E 's|.*/([^/]+\.framework/.*)|\1|')
          new_ref="@executable_path/../Frameworks/${suffix}"
        else
          new_ref="@executable_path/../Frameworks/${libname}"
        fi
      else
        dir_path=$(dirname "$file")
        rel_path=""
        temp_dir="$dir_path"
        while [[ "$temp_dir" != */Contents && "$temp_dir" != '/' && "$temp_dir" != '.' ]]; do
          rel_path="../${rel_path}"
          temp_dir=$(dirname "$temp_dir")
        done
        if [[ "$dep" == *.framework* ]]; then
          suffix=$(echo "$dep" | sed -E 's|.*/([^/]+\.framework/.*)|\1|')
          new_ref="@loader_path/${rel_path}Frameworks/${suffix}"
        else
          new_ref="@loader_path/${rel_path}Frameworks/${libname}"
        fi
      fi
      echo "  Patching $file: changing $dep to $new_ref"
      install_name_tool -change "$dep" "$new_ref" "$file"
    done
  fi
done

echo "Recursively signing Mach-O files..."
find "${APP_DIR}" -type f | sort -r | while IFS= read -r file; do
  if file "$file" | grep -q 'Mach-O'; then
    echo "  Signing $file..."
    codesign -s - --force --preserve-metadata=entitlements "$file"
  fi
done

echo "Signing the bundle itself..."
codesign -s - --force --deep "${APP_DIR}"
echo "Done!"
]=])

  string(REPLACE "__APP_DIR__" "${APP_DIR}" SCRIPT_CONTENT "${SCRIPT_CONTENT}")
  file(WRITE "${SCRIPT_FILE}" "${SCRIPT_CONTENT}")
  execute_process(COMMAND chmod +x "${SCRIPT_FILE}")
  execute_process(COMMAND "${SCRIPT_FILE}")
endif()
