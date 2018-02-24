#!/usr/bin/env bash

array_vals_equal() {
    [ $(tr ' ' $'\n' <<<$@ | sort -u | wc -l) -eq 1 ]
}

for video in $@; do
    # skip empty files
    [ -d $video ] || continue;

    # want to check each clip exists

    for clip in {0..4}; do
        # want to check no clip is empty
        if [ ! -d "$video"/$clip ]; then
            echo "$video is missing $clip"
            continue
        fi

        length[$clip]=$(find "$video/$clip" -type f | wc -l)
        if [ ${length[$clip]} -eq 0 ]; then
            echo "$video clip $clip is empty"
        fi
    done

    # want to check each clip has same number of files
    for clip in {0..3}; do
        if [[ ${length[$clip]} != ${length[$((clip+1))]} ]]; then
            equal=false
        fi
    done
    if ! array_vals_equal "${length[@]}"; then
        echo "$video clip lengths not equal:"
        echo $'\t'"${length[@]}"
    fi

    echo $(basename $video)$'\t'${length[0]}
done


