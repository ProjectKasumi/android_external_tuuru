#!/bin/bash

mergeUpstream() {
    TOP="$(gettop)" bash -i "$(gettop)/external/tuuru/kasumi-no-tuuru/scripts/merge_upstream.sh" $@
}
