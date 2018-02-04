#!/usr/bin/env bash

readonly SPORTS1M_DIR="sports-1m-dataset"
readonly OUTPUT_DIR="data"
readonly SECONDS_PER_CLIP=2
readonly N_CLIPS=5
readonly URL_LIST_DIR="${SPORTS1M_DIR}/original"
readonly URL_LIST_SUFFIX="_partition.txt"
readonly OUTPUT_VIDEO_SCALE="171:128"

readonly ERRFILE=err.log
readonly TMPDIR=$(mktemp -d)

set -xeuo pipefail 

function cleanup() {
    rm -r "$TMPDIR"
}
trap cleanup EXIT

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
            return 1
        fi
    fi
    echo $fps
}

function download_video() {
    local url="$1"

    you-get --force --no-caption -o "$TMPDIR" -O video "$url" 2>"$ERRFILE" || {
        if grep -Eq "unavailable|copyright infringement|no longer available" "$ERRFILE"; then
            return 2
        fi
        return 1
    }
    echo "${TMPDIR}/video."*
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

    set +e
    env python3 extract_clips.py "$frame_dir" "$clip_dir" $frames_per_clip $N_CLIPS
    res=$?
    set -e

    # clean up frame files
    find "${TMPDIR}" -name "frame*" -print0 | xargs -0 rm
    return $res
}

function skip_video() {
    local res=${2:-$?}
    case $res in
        2) touch "$1"; continue ;;
        *) exit 1
    esac
}

function process_url_list() {
    local url_list="$1"
    local dataset_dir="$2"
    local file_no=0

    cut -d' ' -f2 "$url_list" > "${dataset_dir}/labels.txt"
    while read -u 3 -r url; do
        local clip_dir="$dataset_dir/$(printf %06d $file_no)"
        let ++file_no
        if [ ! -e "$clip_dir" ]; then
            set +e
            # you-get behaves oddly in a subshell
            download_video "$url" || skip_video "$clip_dir"
            local video=$(echo "${TMPDIR}/video."*)
            set -e
            local fps=$(get_fps "$video") # XXX: this always has exit code 0?
            valid_fps "$fps"
            set +e
            split_video_into_clips "$video" "$fps" "$clip_dir"
            set -e
            local res=$?
            rm "$video"
            [ $res -eq 0 ] || skip_video "$clip_dir" $res
        fi
    done 3<<<"$(cut -d' ' -f1 "$url_list")"
    #done 3<"$TMPDIR/vidlist"
}


! mkdir "$OUTPUT_DIR" 2>&-
! mkdir "$TMPDIR" 2>&-

#for dataset in train test; do
for dataset in train; do
    url_list="${URL_LIST_DIR}/${dataset}${URL_LIST_SUFFIX}"
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
