#!/usr/bin/env bash

: ${SPORTS1M_DIR:="sports-1m-dataset"}
: ${OUTPUT_DIR:="data"}
: ${SECONDS_PER_CLIP:=2}
: ${N_CLIPS:=5}
: ${URL_LIST_DIR:="${SPORTS1M_DIR}/original"}
: ${URL_LIST_SUFFIX:="_partition.txt"}
: ${OUTPUT_VIDEO_SCALE:="171:128"}

: ${ERRFILE:=err.log}
: ${TMPDIR:=$(mktemp -d)}

: ${MAX_FILES:=}

readonly SPORTS1M_DIR OUTPUT_DIR SECONDS_PER_CLIP N_CLIPS URL_LIST_DIR\
    URL_LIST_SUFFIX OUTPUT_VIDEO_SCALE ERRFILE TMPDIR

readonly YOUTUBE_ERRORS="payment|content|copyright grounds|removed|in your country|duplicate|unavailable|copyright infringement|available"

set -euo pipefail 

function cleanup() {
    if [ $? -ne 0 ]; then
        echo "Abnormal exit"
    fi
    rm -r "$TMPDIR"
}
trap cleanup EXIT

function is_video() {
    ffprobe -i "$1" -hide_banner 2>&1 | grep -q "Stream .*: Video"
}
function valid_fps() {
    local fps="$1"
    local re='^[0-9]+$'
    [[ $fps != 0 && ( $fps =~ $re ) ]]
}
function fps_method_1() {
    ffmpeg -i "$1" 2>&1 | sed -nE '/Input #0/,$s/.* ([0-9]+)(\.[0-9]+)? fps.*/\1/p' ||:
}

function fps_method_2() {
    # from
    # https://askubuntu.com/questions/110264/how-to-find-frames-per-second-of-any-video-file
    # also relevant
    # https://stackoverflow.com/questions/2017843/fetch-frame-count-with-ffmpeg
    # https://superuser.com/questions/650291/how-to-get-video-duration-in-seconds
    local fps=$(ffprobe -v 0 -of csv=p=0 -select_streams V:0 -show_entries stream=r_frame_rate "$1")
    perl -e "print int($fps+0.5)"
}

function get_fps() {
    local fps=$(fps_method_1 "$video")
    if ! valid_fps "$fps"; then
        fps=$(fps_method_2 "$video")
        if ! valid_fps "$fps"; then
            ffmpeg -i "$video"
            echo "$fps"
            exit 1
        fi
    fi
    echo $fps
}

function get_length() {
    # from
    # https://superuser.com/questions/650291/how-to-get-video-duration-in-seconds
    ffprobe -v error \
            -show_entries format=duration \
            -of default=noprint_wrappers=1:nokey=1\
            "$1"
}

function _dl_command() {
    you-get --force --no-caption -o "$TMPDIR" -O video "$1"
}

function download_video() {
    local url="$1"
    echo $url


    if ! _dl_command "$url" 2>"$ERRFILE"; then
        if grep -Eiq "$YOUTUBE_ERRORS" "$ERRFILE"; then
            return 1
        elif grep -Eq " oops," "$ERRFILE"; then
            local retries=1
            while ! _dl_command "$url" 2>/dev/null; do
                echo "Attempt $((2 - retries))"
                let --retries || return 1
            done
        else
            exit 1
        fi
    fi
    #echo "${TMPDIR}/video."*
}

function split_video_into_clips() {
    local video="$1"
    local fps="$2"
    local clip_dir="$3"
    local frames_per_clip=$((SECONDS_PER_CLIP * fps))
    local frame_dir="${TMPDIR}"
    local frame_format="frame%06d.jpg"

    ffmpeg -v error\
           -i "$video"\
           -vf scale="$OUTPUT_VIDEO_SCALE"\
           "${frame_dir}/$frame_format"

    env python3 extract_clips.py "$frame_dir" "$clip_dir" $frames_per_clip $N_CLIPS
    res=$?

    # clean up frame files
    find "${TMPDIR}" -name "frame*" -print0 | xargs -0 rm
    [ $res -eq 0 -o $res -eq 2 ] || exit 1

    return $res
}

function split_video_into_clips_2() {
    local video="$1"
    local clip_dir="$2"
    local frame_dir="${TMPDIR}"

    local length=$(get_length ${video})

    local frame_format="%03d.jpg"

    local counter=0
    starts=$(env python3 gen_clip_times.py $length $SECONDS_PER_CLIP $N_CLIPS)
    [ $? -eq 0 ] || return 1

    
    OFS="$IFS"
    IFS=" "$'\n'
    while read -u 3 -r start; do
        ! mkdir -p "${clip_dir}/${counter}"
        ffmpeg -v error\
               -i "$video"\
               -ss "$start"\
               -t "$SECONDS_PER_CLIP"\
               -vf scale="$OUTPUT_VIDEO_SCALE"\
               "${clip_dir}/${counter}/$frame_format"
        let ++counter
    done 3<<<$starts
    IFS="$OFS"

    if [ ! -d "${clip_dir}/$((N_CLIPS-1))"\
        -o $(find "${clip_dir}/$((N_CLIPS-1))" -iname "*jpg" | wc -l) -eq 0 ]; then
        echo "Failed to convert video"
        exit 1;
    fi
}

function skip_video() {
    touch "$1"
    echo "Skipping video: $2"
}

function process_url_list() {
    local url_list="$1"
    local dataset_dir="$2"
    #local file_no=0


    # find current video
    local file_no=$(find "$dataset_dir" -regextype egrep -regex ".*[0-9]{6}" -print0 |\
        grep --text --perl-regexp --only-matching ".{6}\x00" |\
        tr -d '\n' |\
        sort -zr |\
        cut -c -6 |\
        sed 's/^[^1-9]*//')

    cut -d' ' -f2 "$url_list" > "${dataset_dir}/labels.txt"
    while read -u 3 -r url; do
        let current_file=file_no++ ||:
        local clip_dir="$dataset_dir/$(printf %06d $current_file)"
        if [ ! -e "$clip_dir" ]; then
            echo "Starting video $current_file"

            set +e

            # you-get behaves oddly in a subshell
            download_video "$url"\
                || { skip_video "$clip_dir" "unavailable"; continue; }

            local video=$(echo "${TMPDIR}/video."*)
            is_video "$video"\
                || { skip_video "$clip_dir" "corrupt/missing"; continue; }

            set -e

            #local fps=$(get_fps "$video") # XXX: this always has exit code 0?
            #valid_fps "$fps"

            set +e

            #split_video_into_clips "$video" "$fps" "$clip_dir"

            split_video_into_clips_2 "$video" "$clip_dir"
            local res=$?

            set -e

            rm "$video"
            [ $res -eq 0 ]\
                || { skip_video "$clip_dir" "too short"; continue; }

            echo "Finished video $current_file"
        else
            echo "Video $current_file exists - skipping"
        fi
    done 3<<<"$(tail --lines=+"${file_no:=0}" "$url_list" | cut -d' ' -f1)"
    echo "Finished!"
}


! mkdir "$OUTPUT_DIR" 2>&-
! mkdir "$TMPDIR" 2>&-

#for dataset in train test; do
for dataset in train; do
    url_list="${URL_LIST_DIR}/${dataset}${URL_LIST_SUFFIX}"

    if [ -n "$MAX_FILES" ]; then
        head --lines="$MAX_FILES" "$url_list" > "${TMPDIR}/working_list"
        url_list="${TMPDIR}/working_list"
    fi

    dataset_dir="${OUTPUT_DIR}/$dataset"
    ! mkdir "$dataset_dir" 2>&-
    process_url_list "$url_list" "$dataset_dir"
done


# Alternative method using built-in ffmpeg video splitting. Faster, but less
# accurate and output size is larger.
#
#function download_video() {
#    url="$1"
#    video_dir="$2"
#
#    you-get --no-caption -o "$video_dir" -O video "$url" 2>"$ERRFILE" || {
#        if grep -Eq "unavailable|copyright infringement|no longer available" "$ERRFILE"; then
#            return 2
#        fi
#        return 1
#    }
#
#    video=$(echo "${video_dir}/video."*)
#    format="${video##*.}"
#    clip_output="${video_dir}/clip%04d.${format}"
#    frame_output="${video_dir}/frame%06d.jpg"
#
#    ffmpeg -v error\
#           -i "$video"\
#           -c copy\
#           -map 0\
#           -segment_time 0.1\
#           -f segment\
#           "$clip_output" || return 1
#
#    count=0
#    for clip in $(find ${video_dir} -name "clip*" | shuf | head -$N_CLIPS); do
#        clip_dir="${video_dir}/$count"
#        mkdir "$clip_dir"
#        ffmpeg -v error\
#               -i "$clip"\
#               -vf scale="$SCALE"\
#               "${clip_dir}/%03d.jpg" || return 1
#        let ++count
#    done
#
#    #python extract_vid.py "$video_dir" $frames_per_clip $N_CLIPS || return 1
#
#    set +x
#    rm "$video" "${video_dir}/clip"* 2>&-||:
#    set -x
#}
