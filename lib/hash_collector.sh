# Copyright (C) 2020 IBM Corporation
#
# Licensed under the Apache License, Version 2.0 (the “License”);
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an “AS IS” BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

###############################################################################
# Collector that searches and hashes files.
# Globals:
#   END_DATE_DAYS
#   GLOBAL_EXCLUDE_MOUNT_POINT
#   GLOBAL_EXCLUDE_NAME_PATTERN
#   GLOBAL_EXCLUDE_PATH_PATTERN
#   HASH_ALGORITHM
#   MD5_HASHING_TOOL
#   MOUNT_POINT
#   SHA1_HASHING_TOOL
#   SHA256_HASHING_TOOL
#   START_DATE_DAYS
#   TEMP_DATA_DIR
#   XARGS_REPLACE_STRING_SUPPORT
# Requires:
#   find_wrapper
#   get_mount_point_by_file_system
#   sanitize_filename
#   sanitize_path
#   sort_uniq_file
# Arguments:
#   $1: path
#   $2: is file list (optional) (default: false)
#   $3: path pattern (optional)
#   $4: name pattern (optional)
#   $5: exclude path pattern (optional)
#   $6: exclude name pattern (optional)
#   $7: exclude file system (optional)
#   $8: max depth (optional)
#   $9: file type (optional)
#   $10: min file size (optional)
#   $11: max file size (optional)
#   $12: permissions (optional)
#   $13: ignore date range (optional) (default: false)
#   $14: root output directory
#   $15: output directory (optional)
#   $16: output file
# Exit Status:
#   Exit with status 0 on success.
#   Exit with status greater than 0 if errors occur.
###############################################################################
hash_collector()
{
  # some systems such as Solaris 10 do not support more than 9 parameters
  # on functions, not even using curly braces {} e.g. ${10}
  # so the solution was to use shift
  hc_path="${1:-}"
  shift
  hc_is_file_list="${1:-false}"
  shift
  hc_path_pattern="${1:-}"
  shift
  hc_name_pattern="${1:-}"
  shift
  hc_exclude_path_pattern="${1:-}"
  shift
  hc_exclude_name_pattern="${1:-}"
  shift
  hc_exclude_file_system="${1:-}"
  shift
  hc_max_depth="${1:-}"
  shift
  hc_file_type="${1:-}"
  shift
  hc_min_file_size="${1:-}"
  shift
  hc_max_file_size="${1:-}"
  shift
  hc_permissions="${1:-}"
  shift
  hc_ignore_date_range="${1:-false}"
  shift
  hc_root_output_directory="${1:-}"
  shift
  hc_output_directory="${1:-}"
  shift
  hc_output_file="${1:-}"
  
  # return if path is empty
  if [ -z "${hc_path}" ]; then
    printf %b "hash_collector: missing required argument: 'path'\n" >&2
    return 2
  fi

  # return if root output directory is empty
  if [ -z "${hc_root_output_directory}" ]; then
    printf %b "hash_collector: missing required argument: \
'root_output_directory'\n" >&2
    return 3
  fi

  # return if output file is empty
  if [ -z "${hc_output_file}" ]; then
    printf %b "hash_collector: missing required argument: 'output_file'\n" >&2
    return 4
  fi

  # prepend root output directory to path if it does not start with /
  # (which means local file)
  if regex_not_match "^/" "${hc_path}"; then
    hc_path=`sanitize_path "${TEMP_DATA_DIR}/${hc_root_output_directory}/${hc_path}"`
  fi

  # return if is file list and file list does not exist
  if ${hc_is_file_list} && [ ! -f "${hc_path}" ]; then
    printf %b "hash_collector: file list does not exist: '${hc_path}'\n" >&2
    return 5
  fi

  # sanitize output file name
  hc_output_file=`sanitize_filename "${hc_output_file}"`

  # sanitize output directory
  hc_output_directory=`sanitize_path \
    "${hc_root_output_directory}/${hc_output_directory}"`

  # create output directory if it does not exist
  if [ ! -d  "${TEMP_DATA_DIR}/${hc_output_directory}" ]; then
    mkdir -p "${TEMP_DATA_DIR}/${hc_output_directory}" >/dev/null
  fi

  ${hc_ignore_date_range} && hc_date_range_start_days="" \
    || hc_date_range_start_days="${START_DATE_DAYS}"
  ${hc_ignore_date_range} && hc_date_range_end_days="" \
    || hc_date_range_end_days="${END_DATE_DAYS}"
  
  # local exclude mount points
  if [ -n "${hc_exclude_file_system}" ]; then
    hc_exclude_mount_point=`get_mount_point_by_file_system \
      "${hc_exclude_file_system}"`
    hc_exclude_path_pattern="${hc_exclude_path_pattern},\
${hc_exclude_mount_point}"
  fi
  
  # global exclude mount points
  if [ -n "${GLOBAL_EXCLUDE_MOUNT_POINT}" ]; then
    hc_exclude_path_pattern="${hc_exclude_path_pattern},\
${GLOBAL_EXCLUDE_MOUNT_POINT}"
  fi

  # global exclude path pattern
  if [ -n "${GLOBAL_EXCLUDE_PATH_PATTERN}" ]; then
    hc_exclude_path_pattern="${hc_exclude_path_pattern},\
${GLOBAL_EXCLUDE_PATH_PATTERN}"
  fi

  # global exclude name pattern
  if [ -n "${GLOBAL_EXCLUDE_NAME_PATTERN}" ]; then
    hc_exclude_name_pattern="${hc_exclude_name_pattern},\
${GLOBAL_EXCLUDE_NAME_PATTERN}"
  fi

  # prepend mount point if is not file list
  ${hc_is_file_list} || hc_path=`sanitize_path "${MOUNT_POINT}/${hc_path}"`

  if is_element_in_list "md5" "${HASH_ALGORITHM}" \
    && [ -n "${MD5_HASHING_TOOL}" ]; then
    if ${XARGS_REPLACE_STRING_SUPPORT}; then
      if ${hc_is_file_list}; then
        log_message COMMAND "sort -u \"${hc_path}\" | xargs -I{} ${MD5_HASHING_TOOL} \"{}\""
        sort -u "${hc_path}" \
          | xargs -I{} ${MD5_HASHING_TOOL} "{}" \
            >>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.md5" \
            2>>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.md5.stderr"
      else
        find_wrapper \
          "${hc_path}" \
          "${hc_path_pattern}" \
          "${hc_name_pattern}" \
          "${hc_exclude_path_pattern}" \
          "${hc_exclude_name_pattern}" \
          "${hc_max_depth}" \
          "${hc_file_type}" \
          "${hc_min_file_size}" \
          "${hc_max_file_size}" \
          "${hc_permissions}" \
          "${hc_date_range_start_days}" \
          "${hc_date_range_end_days}" \
            2>>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.md5.stderr" \
          | sort -u \
          | xargs -I{} ${MD5_HASHING_TOOL} "{}" \
            >>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.md5" \
            2>>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.md5.stderr"
        log_message COMMAND "| sort -u | xargs -I{} ${MD5_HASHING_TOOL} \"{}\""
        
      fi
    else
      if ${hc_is_file_list}; then
        log_message COMMAND "sort -u \"${hc_path}\" | while read %line%; do ${MD5_HASHING_TOOL} \"%line%\""
        sort -u "${hc_path}" \
          | while read hc_line || [ -n "${hc_line}" ]; do
              ${MD5_HASHING_TOOL} "${hc_line}"
            done \
              >>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.md5" \
              2>>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.md5.stderr"
      else
        find_wrapper \
          "${hc_path}" \
          "${hc_path_pattern}" \
          "${hc_name_pattern}" \
          "${hc_exclude_path_pattern}" \
          "${hc_exclude_name_pattern}" \
          "${hc_max_depth}" \
          "${hc_file_type}" \
          "${hc_min_file_size}" \
          "${hc_max_file_size}" \
          "${hc_permissions}" \
          "${hc_date_range_start_days}" \
          "${hc_date_range_end_days}" \
            2>>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.md5.stderr" \
          | sort -u \
          | while read hc_line || [ -n "${hc_line}" ]; do
              ${MD5_HASHING_TOOL} "${hc_line}"
            done \
              >>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.md5" \
              2>>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.md5.stderr"
        log_message COMMAND "| sort -u | while read %line%; do ${MD5_HASHING_TOOL} \"%line%\""
      fi
    fi

    # sort and uniq output file
    sort_uniq_file "${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.md5"

    # add output file to the list of files to be archived within the 
    # output file if it is not empty
    if [ -s "${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.md5" ]; then
      echo "${hc_output_directory}/${hc_output_file}.md5" \
        >>"${TEMP_DATA_DIR}/.output_file.tmp"
    fi

    # add stderr file to the list of files to be archived within the 
    # output file if it is not empty
    if [ -s "${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.md5.stderr" ]; then
      echo "${hc_output_directory}/${hc_output_file}.md5.stderr" \
        >>"${TEMP_DATA_DIR}/.output_file.tmp"
    fi

  fi

  if is_element_in_list "sha1" "${HASH_ALGORITHM}" \
    && [ -n "${SHA1_HASHING_TOOL}" ]; then
    if ${XARGS_REPLACE_STRING_SUPPORT}; then
      if ${hc_is_file_list}; then
        log_message COMMAND "sort -u \"${hc_path}\" | xargs -I{} ${SHA1_HASHING_TOOL} \"{}\""
        sort -u "${hc_path}" \
          | xargs -I{} ${SHA1_HASHING_TOOL} "{}" \
            >>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.sha1" \
            2>>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.sha1.stderr"
      else
        find_wrapper \
          "${hc_path}" \
          "${hc_path_pattern}" \
          "${hc_name_pattern}" \
          "${hc_exclude_path_pattern}" \
          "${hc_exclude_name_pattern}" \
          "${hc_max_depth}" \
          "${hc_file_type}" \
          "${hc_min_file_size}" \
          "${hc_max_file_size}" \
          "${hc_permissions}" \
          "${hc_date_range_start_days}" \
          "${hc_date_range_end_days}" \
            2>>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.sha1.stderr" \
          | sort -u \
          | xargs -I{} ${SHA1_HASHING_TOOL} "{}" \
            >>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.sha1" \
            2>>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.sha1.stderr"
        log_message COMMAND "| sort -u | xargs -I{} ${SHA1_HASHING_TOOL} \"{}\""
      fi
    else
      if ${hc_is_file_list}; then
        log_message COMMAND "sort -u \"${hc_path}\" | while read %line%; do ${SHA1_HASHING_TOOL} \"%line%\""
        sort -u "${hc_path}" \
          | while read hc_line || [ -n "${hc_line}" ]; do
              ${SHA1_HASHING_TOOL} "${hc_line}"
            done \
              >>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.sha1" \
              2>>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.sha1.stderr"
      else
        find_wrapper \
          "${hc_path}" \
          "${hc_path_pattern}" \
          "${hc_name_pattern}" \
          "${hc_exclude_path_pattern}" \
          "${hc_exclude_name_pattern}" \
          "${hc_max_depth}" \
          "${hc_file_type}" \
          "${hc_min_file_size}" \
          "${hc_max_file_size}" \
          "${hc_permissions}" \
          "${hc_date_range_start_days}" \
          "${hc_date_range_end_days}" \
            2>>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.sha1.stderr" \
          | sort -u \
          | while read hc_line || [ -n "${hc_line}" ]; do
              ${SHA1_HASHING_TOOL} "${hc_line}"
            done \
              >>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.sha1" \
              2>>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.sha1.stderr"
        log_message COMMAND "| sort -u | while read %line%; do ${SHA1_HASHING_TOOL} \"%line%\""
      fi
    fi

    # sort and uniq output file
    sort_uniq_file "${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.sha1"

    # add output file to the list of files to be archived within the 
    # output file if it is not empty
    if [ -s "${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.sha1" ]; then
      echo "${hc_output_directory}/${hc_output_file}.sha1" \
        >>"${TEMP_DATA_DIR}/.output_file.tmp"
    fi

    # add stderr file to the list of files to be archived within the 
    # output file if it is not empty
    if [ -s "${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.sha1.stderr" ]; then
      echo "${hc_output_directory}/${hc_output_file}.sha1.stderr" \
        >>"${TEMP_DATA_DIR}/.output_file.tmp"
    fi

  fi

  if is_element_in_list "sha256" "${HASH_ALGORITHM}" \
    && [ -n "${SHA256_HASHING_TOOL}" ]; then
    if ${XARGS_REPLACE_STRING_SUPPORT}; then
      if ${hc_is_file_list}; then
        log_message COMMAND "sort -u \"${hc_path}\" | xargs -I{} ${SHA256_HASHING_TOOL} \"{}\""
        sort -u "${hc_path}" \
          | xargs -I{} ${SHA256_HASHING_TOOL} "{}" \
            >>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.sha256" \
            2>>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.sha256.stderr"
      else
        find_wrapper \
          "${hc_path}" \
          "${hc_path_pattern}" \
          "${hc_name_pattern}" \
          "${hc_exclude_path_pattern}" \
          "${hc_exclude_name_pattern}" \
          "${hc_max_depth}" \
          "${hc_file_type}" \
          "${hc_min_file_size}" \
          "${hc_max_file_size}" \
          "${hc_permissions}" \
          "${hc_date_range_start_days}" \
          "${hc_date_range_end_days}" \
            2>>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.sha256.stderr" \
          | sort -u \
          | xargs -I{} ${SHA256_HASHING_TOOL} "{}" \
            >>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.sha256" \
            2>>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.sha256.stderr"
        log_message COMMAND "| sort -u | xargs -I{} ${SHA256_HASHING_TOOL} \"{}\""
      fi
    else
      if ${hc_is_file_list}; then
        log_message COMMAND "sort -u \"${hc_path}\" | while read %line%; do ${SHA256_HASHING_TOOL} \"%line%\""
        sort -u "${hc_path}" \
          | while read hc_line || [ -n "${hc_line}" ]; do
              ${SHA256_HASHING_TOOL} "${hc_line}"
            done \
              >>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.sha256" \
              2>>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.sha256.stderr"
      else
        find_wrapper \
          "${hc_path}" \
          "${hc_path_pattern}" \
          "${hc_name_pattern}" \
          "${hc_exclude_path_pattern}" \
          "${hc_exclude_name_pattern}" \
          "${hc_max_depth}" \
          "${hc_file_type}" \
          "${hc_min_file_size}" \
          "${hc_max_file_size}" \
          "${hc_permissions}" \
          "${hc_date_range_start_days}" \
          "${hc_date_range_end_days}" \
            2>>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.sha256.stderr" \
          | sort -u \
          | while read hc_line || [ -n "${hc_line}" ]; do
              ${SHA256_HASHING_TOOL} "${hc_line}"
            done \
              >>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.sha256" \
              2>>"${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.sha256.stderr"
        log_message COMMAND "| sort -u | while read %line%; do ${SHA256_HASHING_TOOL} \"%line%\""
      fi
    fi

    # sort and uniq output file
    sort_uniq_file "${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.sha256"

    # add output file to the list of files to be archived within the 
    # output file if it is not empty
    if [ -s "${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.sha256" ]; then
      echo "${hc_output_directory}/${hc_output_file}.sha256" \
        >>"${TEMP_DATA_DIR}/.output_file.tmp"
    fi

    # add stderr file to the list of files to be archived within the 
    # output file if it is not empty
    if [ -s "${TEMP_DATA_DIR}/${hc_output_directory}/${hc_output_file}.sha256.stderr" ]; then
      echo "${hc_output_directory}/${hc_output_file}.sha256.stderr" \
        >>"${TEMP_DATA_DIR}/.output_file.tmp"
    fi

  fi

}