# Unicode 15.0 zero-width and East Asian wide/full-width intervals. The raw
# data is split lazily so ASCII-only prompts do not pay the table setup cost.
typeset -ga _AI_CANDY_PROMPT_ZERO_WIDTH_DATA=(
  '300-36f,483-489,591-5bd,5bf-5bf,5c1-5c2,5c4-5c5,5c7-5c7,610-61a,64b-65f,670-670,6d6-6dc,'\
  '6df-6e4,6e7-6e8,6ea-6ed,711-711,730-74a,7a6-7b0,7eb-7f3,7fd-7fd,816-819,81b-823,825-827,'\
  '829-82d,859-85b,898-89f,8ca-8e1,8e3-902,93a-93a,93c-93c,941-948,94d-94d,951-957,962-963,'\
  '981-981,9bc-9bc,9c1-9c4,9cd-9cd,9e2-9e3,9fe-9fe,a01-a02,a3c-a3c,a41-a42,a47-a48,a4b-a4d,'\
  'a51-a51,a70-a71,a75-a75,a81-a82,abc-abc,ac1-ac5,ac7-ac8,acd-acd,ae2-ae3,afa-aff,b01-b01,'\
  'b3c-b3c,b3f-b3f,b41-b44,b4d-b4d,b55-b56,b62-b63,b82-b82,bc0-bc0,bcd-bcd,c00-c00,c04-c04,'\
  'c3c-c3c,c3e-c40,c46-c48,c4a-c4d,c55-c56,c62-c63,c81-c81,cbc-cbc,cbf-cbf,cc6-cc6,ccc-ccd,'\
  'ce2-ce3,d00-d01,d3b-d3c,d41-d44,d4d-d4d,d62-d63,d81-d81,dca-dca,dd2-dd4,dd6-dd6,e31-e31,'\
  'e34-e3a,e47-e4e,eb1-eb1,eb4-ebc,ec8-ece,f18-f19,f35-f35,f37-f37,f39-f39,f71-f7e,f80-f84,'\
  'f86-f87,f8d-f97,f99-fbc,fc6-fc6,102d-1030,1032-1037,1039-103a,103d-103e,1058-1059,105e-1060,'\
  '1071-1074,1082-1082,1085-1086,108d-108d,109d-109d,135d-135f,1712-1714,1732-1733,1752-1753,'\
  '1772-1773,17b4-17b5,17b7-17bd,17c6-17c6,17c9-17d3,17dd-17dd,180b-180d,180f-180f,1885-1886,'\
  '18a9-18a9,1920-1922,1927-1928,1932-1932,1939-193b,1a17-1a18,1a1b-1a1b,1a56-1a56,1a58-1a5e,'\
  '1a60-1a60,1a62-1a62,1a65-1a6c,1a73-1a7c,1a7f-1a7f,1ab0-1ace,1b00-1b03,1b34-1b34,1b36-1b3a,'\
  '1b3c-1b3c,1b42-1b42,1b6b-1b73,1b80-1b81,1ba2-1ba5,1ba8-1ba9,1bab-1bad,1be6-1be6,1be8-1be9,'\
  '1bed-1bed,1bef-1bf1,1c2c-1c33,1c36-1c37,1cd0-1cd2,1cd4-1ce0,1ce2-1ce8,1ced-1ced,1cf4-1cf4,'\
  '1cf8-1cf9,1dc0-1dff,20d0-20f0,2cef-2cf1,2d7f-2d7f,2de0-2dff,302a-302d,3099-309a,a66f-a672,'\
  'a674-a67d,a69e-a69f,a6f0-a6f1,a802-a802,a806-a806,a80b-a80b,a825-a826,a82c-a82c,a8c4-a8c5,'\
  'a8e0-a8f1,a8ff-a8ff,a926-a92d,a947-a951,a980-a982,a9b3-a9b3,a9b6-a9b9,a9bc-a9bd,a9e5-a9e5,'\
  'aa29-aa2e,aa31-aa32,aa35-aa36,aa43-aa43,aa4c-aa4c,aa7c-aa7c,aab0-aab0,aab2-aab4,aab7-aab8,'\
  'aabe-aabf,aac1-aac1,aaec-aaed,aaf6-aaf6,abe5-abe5,abe8-abe8,abed-abed,fb1e-fb1e,fe00-fe0f,'\
  'fe20-fe2f,101fd-101fd,102e0-102e0,10376-1037a,10a01-10a03,10a05-10a06,10a0c-10a0f,'\
  '10a38-10a3a,10a3f-10a3f,10ae5-10ae6,10d24-10d27,10eab-10eac,10efd-10eff,10f46-10f50,'\
  '10f82-10f85,11001-11001,11038-11046,11070-11070,11073-11074,1107f-11081,110b3-110b6,'\
  '110b9-110ba,110c2-110c2,11100-11102,11127-1112b,1112d-11134,11173-11173,11180-11181,'\
  '111b6-111be,111c9-111cc,111cf-111cf,1122f-11231,11234-11234,11236-11237,1123e-1123e,'\
  '11241-11241,112df-112df,112e3-112ea,11300-11301,1133b-1133c,11340-11340,11366-1136c,'\
  '11370-11374,11438-1143f,11442-11444,11446-11446,1145e-1145e,114b3-114b8,114ba-114ba,'\
  '114bf-114c0,114c2-114c3,115b2-115b5,115bc-115bd,115bf-115c0,115dc-115dd,11633-1163a,'\
  '1163d-1163d,1163f-11640,116ab-116ab,116ad-116ad,116b0-116b5,116b7-116b7,1171d-1171f,'\
  '11722-11725,11727-1172b,1182f-11837,11839-1183a,1193b-1193c,1193e-1193e,11943-11943,'\
  '119d4-119d7,119da-119db,119e0-119e0,11a01-11a0a,11a33-11a38,11a3b-11a3e,11a47-11a47,'\
  '11a51-11a56,11a59-11a5b,11a8a-11a96,11a98-11a99,11c30-11c36,11c38-11c3d,11c3f-11c3f,'\
  '11c92-11ca7,11caa-11cb0,11cb2-11cb3,11cb5-11cb6,11d31-11d36,11d3a-11d3a,11d3c-11d3d,'\
  '11d3f-11d45,11d47-11d47,11d90-11d91,11d95-11d95,11d97-11d97,11ef3-11ef4,11f00-11f01,'\
  '11f36-11f3a,11f40-11f40,11f42-11f42,13440-13440,13447-13455,16af0-16af4,16b30-16b36,'\
  '16f4f-16f4f,16f8f-16f92,16fe4-16fe4,1bc9d-1bc9e,1cf00-1cf2d,1cf30-1cf46,1d167-1d169,'\
  '1d17b-1d182,1d185-1d18b,1d1aa-1d1ad,1d242-1d244,1da00-1da36,1da3b-1da6c,1da75-1da75,'\
  '1da84-1da84,1da9b-1da9f,1daa1-1daaf,1e000-1e006,1e008-1e018,1e01b-1e021,1e023-1e024,'\
  '1e026-1e02a,1e08f-1e08f,1e130-1e136,1e2ae-1e2ae,1e2ec-1e2ef,1e4ec-1e4ef,1e8d0-1e8d6,'\
  '1e944-1e94a,e0100-e01ef'
)

typeset -ga _AI_CANDY_PROMPT_WIDE_WIDTH_DATA=(
  '1100-115f,231a-231b,2329-232a,23e9-23ec,23f0-23f0,23f3-23f3,25fd-25fe,2614-2615,2648-2653,'\
  '267f-267f,2693-2693,26a1-26a1,26aa-26ab,26bd-26be,26c4-26c5,26ce-26ce,26d4-26d4,26ea-26ea,'\
  '26f2-26f3,26f5-26f5,26fa-26fa,26fd-26fd,2705-2705,270a-270b,2728-2728,274c-274c,274e-274e,'\
  '2753-2755,2757-2757,2795-2797,27b0-27b0,27bf-27bf,2b1b-2b1c,2b50-2b50,2b55-2b55,2e80-2e99,'\
  '2e9b-2ef3,2f00-2fd5,2ff0-2ffb,3000-303e,3041-3096,3099-30ff,3105-312f,3131-318e,3190-31e3,'\
  '31f0-321e,3220-3247,3250-4dbf,4e00-a48c,a490-a4c6,a960-a97c,ac00-d7a3,f900-faff,fe10-fe19,'\
  'fe30-fe52,fe54-fe66,fe68-fe6b,ff01-ff60,ffe0-ffe6,16fe0-16fe4,16ff0-16ff1,17000-187f7,'\
  '18800-18cd5,18d00-18d08,1aff0-1aff3,1aff5-1affb,1affd-1affe,1b000-1b122,1b132-1b132,'\
  '1b150-1b152,1b155-1b155,1b164-1b167,1b170-1b2fb,1f004-1f004,1f0cf-1f0cf,1f18e-1f18e,'\
  '1f191-1f19a,1f200-1f202,1f210-1f23b,1f240-1f248,1f250-1f251,1f260-1f265,1f300-1f320,'\
  '1f32d-1f335,1f337-1f37c,1f37e-1f393,1f3a0-1f3ca,1f3cf-1f3d3,1f3e0-1f3f0,1f3f4-1f3f4,'\
  '1f3f8-1f43e,1f440-1f440,1f442-1f4fc,1f4ff-1f53d,1f54b-1f54e,1f550-1f567,1f57a-1f57a,'\
  '1f595-1f596,1f5a4-1f5a4,1f5fb-1f64f,1f680-1f6c5,1f6cc-1f6cc,1f6d0-1f6d2,1f6d5-1f6d7,'\
  '1f6dc-1f6df,1f6eb-1f6ec,1f6f4-1f6fc,1f7e0-1f7eb,1f7f0-1f7f0,1f90c-1f93a,1f93c-1f945,'\
  '1f947-1f9ff,1fa70-1fa7c,1fa80-1fa88,1fa90-1fabd,1fabf-1fac5,1face-1fadb,1fae0-1fae8,'\
  '1faf0-1faf8,20000-2fffd,30000-3fffd'
)

typeset -ga _AI_CANDY_PROMPT_EMOJI_MODIFIER_BASE_DATA=(
  '261d-261d,26f9-26f9,270a-270c,270d-270d,1f385-1f385,1f3c2-1f3c4,1f3c7-1f3c7,1f3ca-1f3ca,'
  '1f3cb-1f3cc,1f442-1f443,1f446-1f450,1f466-1f46b,1f46c-1f46d,1f46e-1f478,1f47c-1f47c,'
  '1f481-1f483,1f485-1f487,1f48f-1f48f,1f491-1f491,1f4aa-1f4aa,1f574-1f575,1f57a-1f57a,'
  '1f590-1f590,1f595-1f596,1f645-1f647,1f64b-1f64f,1f6a3-1f6a3,1f6b4-1f6b5,1f6b6-1f6b6,'
  '1f6c0-1f6c0,1f6cc-1f6cc,1f90c-1f90c,1f90f-1f90f,1f918-1f918,1f919-1f91e,1f91f-1f91f,'
  '1f926-1f926,1f930-1f930,1f931-1f932,1f933-1f939,1f93c-1f93e,1f977-1f977,1f9b5-1f9b6,'
  '1f9b8-1f9b9,1f9bb-1f9bb,1f9cd-1f9cf,1f9d1-1f9dd,1fac3-1fac5,1faf0-1faf6,1faf7-1faf8'
)

typeset -g _AI_CANDY_PROMPT_WIDTH_TABLES_READY=0
typeset -ga _AI_CANDY_PROMPT_ZERO_WIDTH_RANGES=()
typeset -ga _AI_CANDY_PROMPT_WIDE_WIDTH_RANGES=()
typeset -ga _AI_CANDY_PROMPT_EMOJI_MODIFIER_BASE_RANGES=()
typeset -ga _AI_CANDY_PROMPT_MEASURED_CHARACTERS=()
typeset -ga _AI_CANDY_PROMPT_MEASURED_WIDTHS=()
typeset -ga _AI_CANDY_PROMPT_TEXT_WIDTH_CACHE_TEXTS=()
typeset -ga _AI_CANDY_PROMPT_TEXT_WIDTH_CACHE_WIDTHS=()
typeset -g _AI_CANDY_PROMPT_TEXT_WIDTH_CACHE_LIMIT=64

function _ai_candy_prompt_width_tables_init() {
  (( _AI_CANDY_PROMPT_WIDTH_TABLES_READY )) && return 0
  local zero_data="${(j::)_AI_CANDY_PROMPT_ZERO_WIDTH_DATA}"
  local wide_data="${(j::)_AI_CANDY_PROMPT_WIDE_WIDTH_DATA}"
  local modifier_base_data="${(j::)_AI_CANDY_PROMPT_EMOJI_MODIFIER_BASE_DATA}"
  _AI_CANDY_PROMPT_ZERO_WIDTH_RANGES=("${(@s:,:)zero_data}")
  _AI_CANDY_PROMPT_WIDE_WIDTH_RANGES=("${(@s:,:)wide_data}")
  _AI_CANDY_PROMPT_EMOJI_MODIFIER_BASE_RANGES=("${(@s:,:)modifier_base_data}")
  _AI_CANDY_PROMPT_WIDTH_TABLES_READY=1
}

function _ai_candy_prompt_codepoint_in_width_table() {
  integer code="$1"
  local table_name="$2"
  local interval=""
  integer low=1 high=0 midpoint range_start range_end

  case "$table_name" in
    zero) high=${#_AI_CANDY_PROMPT_ZERO_WIDTH_RANGES} ;;
    wide) high=${#_AI_CANDY_PROMPT_WIDE_WIDTH_RANGES} ;;
    modifier-base) high=${#_AI_CANDY_PROMPT_EMOJI_MODIFIER_BASE_RANGES} ;;
    *) return 1 ;;
  esac
  while (( low <= high )); do
    midpoint=$(( (low + high) / 2 ))
    case "$table_name" in
      zero) interval="${_AI_CANDY_PROMPT_ZERO_WIDTH_RANGES[midpoint]}" ;;
      wide) interval="${_AI_CANDY_PROMPT_WIDE_WIDTH_RANGES[midpoint]}" ;;
      modifier-base)
        interval="${_AI_CANDY_PROMPT_EMOJI_MODIFIER_BASE_RANGES[midpoint]}"
        ;;
    esac
    range_start=$(( 16#${interval%%-*} ))
    range_end=$(( 16#${interval##*-} ))
    if (( code < range_start )); then
      high=$(( midpoint - 1 ))
    elif (( code > range_end )); then
      low=$(( midpoint + 1 ))
    else
      return 0
    fi
  done
  return 1
}

function _ai_candy_prompt_decode_utf8_at() {
  emulate -L zsh
  local LC_ALL=C
  local text="$1"
  integer index="$2"
  local first_byte="${text[index]}"
  local second_byte="" third_byte="" fourth_byte=""
  integer first=$(( #first_byte ))
  integer second=0 third=0 fourth=0 codepoint=63 byte_count=1

  if (( first < 128 )); then
    codepoint="$first"
  elif (( first >= 194 && first <= 223 )); then
    second_byte="${text[index+1]}"
    second=$(( #second_byte ))
    codepoint=$(( (first - 192) * 64 + second - 128 ))
    byte_count=2
  elif (( first >= 224 && first <= 239 )); then
    second_byte="${text[index+1]}"
    third_byte="${text[index+2]}"
    second=$(( #second_byte ))
    third=$(( #third_byte ))
    codepoint=$(( (first - 224) * 4096 + \
      (second - 128) * 64 + third - 128 ))
    byte_count=3
  elif (( first >= 240 && first <= 244 )); then
    second_byte="${text[index+1]}"
    third_byte="${text[index+2]}"
    fourth_byte="${text[index+3]}"
    second=$(( #second_byte ))
    third=$(( #third_byte ))
    fourth=$(( #fourth_byte ))
    codepoint=$(( (first - 240) * 262144 + \
      (second - 128) * 4096 + (third - 128) * 64 + fourth - 128 ))
    byte_count=4
  fi
  reply=("$codepoint" "$byte_count" "${text[index,index+byte_count-1]}")
}

function _ai_candy_prompt_codepoint_width() {
  integer code="$1"

  if (( code == 0 || code < 32 || (code >= 127 && code < 160) )); then
    REPLY=0
  elif (( code < 0x0300 )); then
    REPLY=1
  elif (( (code >= 0x200b && code <= 0x200d) || \
          (code >= 0x2028 && code <= 0x202e) || \
          (code >= 0x2060 && code <= 0x2063) || \
          (code >= 0xe0020 && code <= 0xe007f) )); then
    REPLY=0
  else
    _ai_candy_prompt_width_tables_init
    if _ai_candy_prompt_codepoint_in_width_table "$code" zero; then
      REPLY=0
    elif _ai_candy_prompt_codepoint_in_width_table "$code" wide; then
      REPLY=2
    else
      REPLY=1
    fi
  fi
}

function _ai_candy_prompt_measure_text() {
  emulate -L zsh
  _ai_candy_sanitize_terminal_text "$1"
  local text="$REPLY"
  integer capture_characters="${2:-0}"
  local LC_ALL=C
  local character=""
  integer index=1 length=${#text} byte_count codepoint codepoint_width
  integer width=0 join_next=0 continuation=0 regional_pending=0
  integer last_base_width=0 last_base_codepoint=0 character_index=0
  integer cluster_width=0 cluster_last_index=0 cluster_width_increment=0

  if (( capture_characters )); then
    _AI_CANDY_PROMPT_MEASURED_CHARACTERS=()
    _AI_CANDY_PROMPT_MEASURED_WIDTHS=()
  fi
  while (( index <= length )); do
    _ai_candy_prompt_decode_utf8_at "$text" "$index"
    codepoint="${reply[1]}"
    byte_count="${reply[2]}"
    character="${reply[3]}"
    _ai_candy_prompt_codepoint_width "$codepoint"
    codepoint_width="$REPLY"
    character_index=$(( character_index + 1 ))
    continuation=0
    cluster_width_increment=0

    if (( codepoint == 0xfe0f )); then
      continuation=1
      if (( last_base_width == 1 )); then
        width=$(( width + 1 ))
        last_base_width=2
        cluster_width=2
      fi
      codepoint_width=0
    elif (( join_next && codepoint_width > 0 )); then
      continuation=1
      last_base_codepoint="$codepoint"
      codepoint_width=0
      join_next=0
    elif (( codepoint >= 0x1f3fb && codepoint <= 0x1f3ff )); then
      if _ai_candy_prompt_codepoint_in_width_table \
           "$last_base_codepoint" modifier-base; then
        continuation=1
        codepoint_width=0
        last_base_codepoint=0
      fi
    fi
    if (( codepoint_width == 0 && character_index > 1 )); then
      continuation=1
    fi
    if (( codepoint >= 0x1f1e6 && codepoint <= 0x1f1ff )); then
      if (( regional_pending )); then
        continuation=1
        cluster_width_increment="$codepoint_width"
        regional_pending=0
      else
        regional_pending=1
      fi
    else
      regional_pending=0
    fi

    if (( codepoint == 0x200d )); then
      join_next=1
    elif (( codepoint != 0xfe0f && codepoint_width > 0 )); then
      last_base_width="$codepoint_width"
      last_base_codepoint="$codepoint"
    fi
    width=$(( width + codepoint_width ))
    if (( capture_characters )); then
      _AI_CANDY_PROMPT_MEASURED_CHARACTERS+=("$character")
      if (( continuation && cluster_last_index > 0 )); then
        _AI_CANDY_PROMPT_MEASURED_WIDTHS[cluster_last_index]=0
        cluster_width=$(( cluster_width + cluster_width_increment ))
      else
        cluster_width="$codepoint_width"
      fi
      _AI_CANDY_PROMPT_MEASURED_WIDTHS+=("$cluster_width")
      cluster_last_index="$character_index"
    fi
    index=$(( index + byte_count ))
  done
  REPLY="$width"
}

function _ai_candy_prompt_text_width() {
  emulate -L zsh
  local text="$1"
  integer index

  for (( index=1; index<=${#_AI_CANDY_PROMPT_TEXT_WIDTH_CACHE_TEXTS}; index++ )); do
    if [[ "${_AI_CANDY_PROMPT_TEXT_WIDTH_CACHE_TEXTS[index]}" == "$text" ]]; then
      REPLY="${_AI_CANDY_PROMPT_TEXT_WIDTH_CACHE_WIDTHS[index]}"
      return 0
    fi
  done

  _ai_candy_prompt_measure_text "$text" 0
  local measured_width="$REPLY"
  if (( ${#_AI_CANDY_PROMPT_TEXT_WIDTH_CACHE_TEXTS} >= \
        _AI_CANDY_PROMPT_TEXT_WIDTH_CACHE_LIMIT )); then
    _AI_CANDY_PROMPT_TEXT_WIDTH_CACHE_TEXTS=()
    _AI_CANDY_PROMPT_TEXT_WIDTH_CACHE_WIDTHS=()
  fi
  _AI_CANDY_PROMPT_TEXT_WIDTH_CACHE_TEXTS+=("$text")
  _AI_CANDY_PROMPT_TEXT_WIDTH_CACHE_WIDTHS+=("$measured_width")
  REPLY="$measured_width"
}

function _ai_candy_prompt_text_tail_by_width() {
  emulate -L zsh
  integer target_width="${2:-0}"
  local character result=""
  integer index character_width width=0 visible_characters=0

  (( target_width > 0 )) || {
    REPLY=""
    return 0
  }
  _ai_candy_prompt_measure_text "$1" 1
  for (( index=${#_AI_CANDY_PROMPT_MEASURED_CHARACTERS}; index>=1; index-- )); do
    character="${_AI_CANDY_PROMPT_MEASURED_CHARACTERS[index]}"
    character_width="${_AI_CANDY_PROMPT_MEASURED_WIDTHS[index]}"
    (( width + character_width <= target_width )) || break
    result="${character}${result}"
    width=$(( width + character_width ))
    (( character_width > 0 )) && visible_characters=$(( visible_characters + 1 ))
  done
  (( visible_characters > 0 )) || result=""
  REPLY="$result"
}
