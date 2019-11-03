#!/bin/bash

#
# Copyright (C) 2016-2018 The halogenOS Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

echo -e "\033[0mincluding \033[1m\033[38;5;39mXOS\033[0m\033[1m Tools\033[0m"

# Get the CPU count
# CPU count is either your virtual cores when using Hyperthreading
# or your physical core count when not using Hyperthreading
# Here the virtual cores are always counted, which can be the same as
# physical cores if not using Hyperthreading or a similar feature.
CPU_COUNT=$(nproc --all)
# Use 2 times the CPU count to build
THREAD_COUNT_BUILD=$(($CPU_COUNT * 2))
# Use doubled CPU count to sync (auto)
THREAD_COUNT_N_BUILD=$(($CPU_COUNT * 2))

# Save the current directory before continuing the script.
# The working directory might change during the execution of specific
# functions, which should be set back to the beginning directory
# so the user does not need to do that manually.
BEGINNING_DIR="$(pwd)"

### BASIC FUNCTIONS START

# Echo with halogen color without new line
function echoxcc() {
    echo -en "\033[1;38;5;39m$@\033[0m"
}

# Echo with halogen color with new line
function echoxc() {
    echoxcc "\033[1;38;5;39m$@\033[0m\n"
}

# Echo with new line and respect escape characters
function echoe() {
    echo -e "$@"
}

# Echo with line, respect escape characters and print in bold font
function echob() {
    echo -e "\033[1m$@\033[0m"
}

# Echo without new line
function echon() {
    echo -n "$@"
}

# Echo without new line and respect escape characters
function echoen() {
    echo -en "$@"
}

### BASIC FUNCTIONS END

# Import help functions
source $(gettop)/external/xos/xostools/xostoolshelp.sh

# Handle the kitchen and automatically eat lunch if hungry
function lunchauto() {
    echo "Eating breakfast..."
    local devicename_extracted=$(echo -n "${1/aosp_/}" | cut -d '-' -f1)
    breakfast $devicename_extracted || :
    if ! find device -mindepth 2 -maxdepth 2 -name $devicename_extracted -type d 2>&1 >/dev/null; then
      return 1
    fi
    echo "Lunching..."
    lunch $@
}

# Build function
function build() {
    buildarg="$1"
    target="$2"
    cleanarg="$3 $4"
    module="${cleanarg//noclean/}"
    module="${module// /}"
    cleanarg="${cleanarg/$module/}"
    cleanarg="${cleanarg// /}"

    # Display help if no argument passed
    if [ -z "$buildarg" ]; then
        xostools_help_build
        return 0
    fi

    # Notify that no target device could be found
    if [ -z "$target" ]; then
        xostools_build_no_target_device
    else
        # Handle the first argument
        case "$buildarg" in

            full | module | mm)
                echob "Starting build..."
                [ -z "$module" ] && module="bacon" || \
                    echo "You have decided to build $module"
                # Of course let's check the kitchen
                lunchauto $target
                # Clean if desired
                [[ "$cleanarg" == "noclean" ]] || make clean
                # Now start building
                echo "Using $THREAD_COUNT_BUILD threads for build."
                if [ "$buildarg" != "mm" ]; then
                    make -j$THREAD_COUNT_BUILD $module
                    return $?
                else
                    mmma -j$THREAD_COUNT_BUILD $module
                    return $?
                fi
            ;;

            module-list)
                local bm_result
                echob "Starting batch build..."
                shift
                ALL_MODULES_TO_BUILD="$@"
                [[ "$@" == *"noclean"* ]] || make clean
                for module in $ALL_MODULES_TO_BUILD; do
                    [[ "$module" == "noclean" ]] && continue
                    echo
                    echob "Building module $module"
                    echo
                    build module $TOOL_THIRDARG $module noclean
                    local bm_result=$?
                done
                echob "Finished batch build"
                [ $bm_result -ne 0 ] && return $bm_result
            ;;

            # Oops.
            *) echo "Unknown build command \"$TOOL_SUBARG\"." ;;

        esac
    fi
    return 0
}

# Reposync!! Laziness is taking over.
# Sync with special features and traditional repo.
function reposync() {
    # You have slow internet? You don't want to consume the whole bandwidth?
    # Same variable definition stuff as always
    REPO_ARG="$1"
    PATH_ARG="$2"
    QUIET_ARG=""
    THREADS_REPO=$THREAD_COUNT_N_BUILD
    # Automatic!
    [ -z "$REPO_ARG" ] && REPO_ARG="auto"
    # Let's decide how much threads to use
    # Self-explanatory.
    case $REPO_ARG in
        turbo)      THREADS_REPO=$(($CPU_COUNT * 10));;
        faster)     THREADS_REPO=$(($CPU_COUNT * 4)) ;;
        fast)       THREADS_REPO=$(($CPU_COUNT * 2)) ;;
        auto)                               ;;
        slow)       THREADS_REPO=$CPU_COUNT;;
        slower)     THREADS_REPO=$(echo "scale=1; $CPU_COUNT / 2 + 0.5" | bc | cut -d '.' -f1);; # + 0.5 will round
        single)     THREADS_REPO=1          ;;
        easteregg)  THREADS_REPO=384        ;; # Neil's love
        quiet)      QUIET_ARG="-q"          ;;
        # People might want to get some good help
        -h | --help | h | help | man | halp | idk )
            echo "Usage: reposync <speed> [path]"
            echo "Available speeds are:"
            echo -en "  turbo\n  faster\n  fast\n  auto\n  slow\n" \
                      " slower\n  single\n  easteregg\n\n"
            echo "Path is not necessary. If not supplied, defaults to workspace."
            return 0
        ;;
        # Oops...
        *)
          [[ "$REPO_ARG" == */ ]] && REPO_ARG="echo ${REPO_ARG%?}"
          [[ -d "$REPO_ARG" || $(repo manifest | grep "$REPO_ARG") ]] && REPO_ARG="auto" && PATH_ARG="$1"
          [[ -d "$PATH_ARG" ]] || echo "Unknown argument \"$REPO_ARG\" for reposync, Defaulting to workspace." ;;
    esac

    if [[ "$3" == "quiet" ]]; then
    QUIET_ARG="-q"
    fi
    # Sync!! Use the power of shell scripting!
    echo "Using $THREADS_REPO threads for sync."
    repo sync -j$THREADS_REPO $QUIET_ARG --force-sync \
        -c --no-clone-bundle --no-tags $2 $PATH_ARG
    return $?
}

# This is repoREsync. It REsyncs. Self-explanatory?
function reporesync() {
    echo "Preparing..."
    FRSTDIR="$(pwd)"
    # Let's cd to the top of the working tree
    # Hoping that we don't land in the home directory.
    cd $(gettop)
    # Critical security check to prevent deleting home directory if the build
    # directory has been removed from the work tree for whatever reason.
    if [[ "$(pwd)" == "$(ls -d ~)" ]]; then
        # Let's warn the user about this bad state.
        echoe "WARNING: 'gettop' is returning your \033[1;91mhome directory\033[0m!"
        echoe "         In order to protect your data, this process will be aborted now."
        return 1
    else
        # Oh yeah, we passed!
        echob "Security check passed. Continuing."
    fi

    # Now let's handle the first argument as always
    case "$1" in

        # Do a full sync
        #   full:       just delete the working tree directories and sync normally
        #   full-x:     delete everything except manifest and repo tool, means
        #               you need to resync everything again.
        #   full-local: don't update the repositories, only do a full resync locally
        full)
            # Print a very important message
            echoe \
                "WARNING: This process will delete \033[1myour whole source tree!\033[0m"
            # Ask if the girl or guy really wants to continue.
            if [ "$2" != "confident" ]; then
            # Check if shell is ZSH by checking ZSH_NAME var, which is only set for zsh.
            if [[ ! -z "$ZSH_NAME" ]]; then # In use shell is zsh
                read -k 1 -r "?Do you want to continue? [y\N] : "
            else
                # Shell isn't zsh, so assume bash syntax.
                read -p "Do you want to continue? [y\N] : " \
                     -n 1 -r
            fi
            # Check the reply.
            [[ ! $REPLY =~ ^[Yy]$ ]] && echoe "\nAborted." && return 1
            fi
            # Print some lines of words
            echoe "\n"
            echob "Full source tree resync will start now."
            # Just in case...
            echo  "Your current directory is: $(pwd)"
            # ... read the printed lines so you know what's going on.
            echon "If you think that the current directory is wrong, you will "
            echo  "now have time to safely abort this process using CTRL+C."
            echoen "\n"
            echon  "Waiting for interruption..."
            # Wait 4 lovely seconds which can save your life
            sleep 4
            # Wipe out the above line, now it is redundant
            echoen "\r\033[K\r"
            echoen "Got no interruption, continuing now!"
            echoen "\n"
            # Collect all directories found in the top of the working tree
            # like build, abi, art, bionic, cts, dalvik, external, device, ...
            # and then remove them, and show the user the beautiful progress
            echo "Collecting and removing directories..."
            echo -en "\n\r"
            for ff in *; do
                case "$ff" in
                  "." | ".." | ".repo");;
                  *)
                      echo -en "\rRemoving $ff\033[K"
                      rm -rf "$ff"
                  ;;
                esac
            done
            echo -en "\n"
            # And let's sync!
            echo "Starting sync..."
            reposync
        ;;

        repo)
            echob "Resyncing $1..."
            rm -rf $1
            reposync single $1
        ;;

        # Help me!
        "")
            xostools_help_reporesync
            cd $FRSTDIR
            return 0
        ;;

    esac
    cd $FRSTDIR
}

function strtrim() {
  sed -e 's/^ *//g' -e 's/ *$//g'
}

function strsplit() {
  cut -d "$1" -f$2
}

function splitix_and_trim() {
  local ix=$1
  local split="$2"
  shift 2
  echo "$@" | strsplit "$split" $ix | strtrim
}

# Resets all repositories to their corresponding remote state
# as defined in the manifest
function reporeset() {
  echo 'Resetting source tree back to remote state.' \
       'Any unsaved work will be gone.'
  cd .repo/manifests && git reset --hard m/XOS-10.0

  repomanifest=$(repo manifest)
  function repomanifest() {
    cat <<EOF
$repomanifest
EOF
  }

  while read line; do
    local repodir=$(splitix_and_trim 1 ':' "$line")
    if [ ! -d "$(gettop)/$repodir" ]; then
      continue
    fi
    local reponame=$(splitix_and_trim 2 ':' "$line")
    local usekey="path"
    local usevalue="$repodir"
    if [ "$(repomanifest | xmlstarlet sel -t -v "//project[@path='$repodir']/@path")" != \
          "$repodir" ]; then
      local usekey="name"
      local usevalue="$reponame"
    fi
    local remote="m"
    local revision="XOS-10.0"
    local remote="$remote/"
    cd $(gettop)/$repodir
    echo "$repodir: resetting and cleaning up untracked files/folders"
    # Abort cherry-picks, merges, rebases and reverts
    git rebase --abort 2>/dev/null >/dev/null || \
    git merge --abort 2>/dev/null >/dev/null || \
    git revert --abort 2>/dev/null >/dev/null || \
    git cherry-pick --abort 2>/dev/null >/dev/null || :
    git reset --hard $remote$revision || git reset --hard $revision
    git clean -fdx
    cd $(gettop)
    echo
  done < <(repo list)

  unset repomanifest
}

# Completely cleans everything and deletes all untracked files
# Deprecated.
function reposterilize() {
  echo -e '\033[1mNote: This function is deprecated.' \
           'It might end up getting removed in the future.' \
           '\nUse reporeset instead.\033[0m'
  if [[ "$(pwd)" == "$(realpath ~)" ]]; then
    echo "Aborted because you are in your home dir"
    return 1
  elif [[ "$(gettop)" == "" ]]; then
    echo "Aborted, top is not set"
    return 1
  fi
  echo "Warning: Any unsaved work will be gone! Press CTRL+C to abort."
  for i in {5..0}; do
    echo -en "\r\033[K\rStarting sterilization in $i seconds"
    sleep 1
  done
  local startdir="$(gettop)"
  echo
  set +e
  while read dir; do
    cd $startdir
    if [[ "$dir" == *"${startdir}/.repo/"* ]]; then continue; fi
    cd "$dir/../"
    nogitdir="$(realpath $dir/..)"
    reladir="${nogitdir/$startdir\//}"
    echo " - $reladir"
    if [[ "$reladir" == "hardware/"* ]]; then
      echo "  This is a hardware repository. Only resetting."
      git reset
      git reset --hard
      git clean -fd
      continue
    fi
    if [[ "$reladir" == "prebuilts/"* ]]; then
      echo "  This is a prebuilts repository. Only resetting."
      git reset
      git reset --hard
      git clean -fd
      continue
    fi
    git revert --abort 2>/dev/null
    git rebase --abort 2>/dev/null
    git cherry-pick --abort 2>/dev/null
    git reset 2>/dev/null
    git reset --hard XOS/XOS-10.0 2>/dev/null \
 || git reset --hard github/XOS-10.0 2>/dev/null \
 || git reset --hard gerrit/XOS-10.0 2>/dev/null \
 || git reset --hard 2>/dev/null
    git clean -fd
  done < <(find "$startdir/" -name ".git" -type d)
  cd "$startdir"
  unset startdir
  set -e
  return 0
}

function resetmanifest() {
  cd $(gettop)/.repo/manifests
  git fetch origin XOS-10.0 2>&1 >/dev/null
  git reset --hard origin/XOS-10.0 2>&1 >/dev/null
  cd $(gettop)
}

source $(gettop)/external/xos/xostools/mergetools.sh

function reticulateOurSplines() {
    TOP="$(gettop)" bash -i "$(gettop)/external/xos/xostools/scripts/reticulate_our_splines.sh" $@
}

return 0
