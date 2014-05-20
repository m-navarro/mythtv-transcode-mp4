#!/bin/sh

# From: http://tech.surveypoint.com/blog/mythtv-transcoding-with-handbrake/
# My MythTV user job to transcode a video to mp4

#------ IF EDITING IN WINDOWS - MAKE SURE EOL IS SET TO UNIX FORMATING ------

# this script expects 2 parameters to identify the recording:
#   4-digit channel ID
#   and 14-digit datetime code (YYYYMMDDDHHMMSS)

# fixes file names so that they do not have any illegal characters.
# passing the second argument as true will replace semicolons with a period
fixFileName() {
    NEWNAME="$1"
    # Replace any semicolon with a period
    if [ ${2:-false} = true ]; then
        NEWNAME=$(echo "$NEWNAME" | sed 's/:/./g')
    fi
    NEWNAME=$(echo "$NEWNAME" | sed "s/[^A-Za-z0-9 _()',.-]//g")
    # Reformat A.M. and P.M. to be am and pm
    NEWNAME=$(echo "$NEWNAME" | sed "s/a.m./am/gI" | sed "s/p.m./pm/gI")
    echo $NEWNAME
}

# MySQL database login information (from mythconverg database)
DATABASEUSER="mythtv"
DATABASEPASSWORD="password"

# path to MythTV transcoding tools
INSTALLPREFIX="/usr/bin"

# path to MythTV folder, where video and recordings folders are located.
MYTHTVFOLDER="/media/mythtvshare"
VIDEOFOLDER="$MYTHTVFOLDER/videos"

# a temporary working directory (must be writable by mythtv user)
TEMPDIR="$MYTHTVFOLDER/tmp"
if [ ! -d "$TEMPDIR" ]; then
    mkdir "$TEMPDIR"
    chmod 777 "$TEMPDIR"
fi

NOW=$(date +"%m-%d-%Y")
LOGFILENAME=$TEMPDIR/log.$NOW
LOGFILE=$LOGFILENAME.txt

echo $(date +"%m-%d-%Y %r") >> $LOGFILE
echo "Started transcode for $1 $2" >> $LOGFILE

if [ -z "$1" ]; then
    echo "Argument not valid!. Exiting with code: $?" >> $LOGFILE
    exit $?;
fi

# PID of this process. We'll create a working directory named with this ID
MYPID=$$

# play nice with other processes
renice 19 $MYPID
ionice -c 3 -p $MYPID

MPDIR="$TEMPDIR/mythtmp-$MYPID"
# make temporary working directory, go inside
mkdir "$MPDIR"
#chmod 777 "$MPDIR"
cd "$MPDIR"

SQL="get-tv-title_$MYPID.sql"
# create and save an SQL query to get the specific title and subtitle of the show
echo "select distinct CONCAT(season,';',episode,';',title,';',subtitle) details from recorded where chanid='$1' and starttime='$2';" > $SQL
# run the SQL query and capture the output
DETAILS=$(mysql --user=$DATABASEUSER --password=$DATABASEPASSWORD mythconverg < $SQL | grep -v details)

# get the show season and episode numbers using ; as a delimiter
SEASON=$(echo "$DETAILS" | cut -d';' -f 1)
EPISODE=$(echo "$DETAILS" | cut -d';' -f 2)

# get the show name using ; as a delimiter
SHOWNAME=$(echo "$DETAILS" | cut -d';' -f 3)
SHOWNAME=$(fixFileName "$SHOWNAME")
# If show name is empty then just set it as Other
if [ -z "$SHOWNAME" ]; then
    SHOWNAME="Other"
fi

# get the episode name
EPISODENAME=$(echo "$DETAILS" | cut -d';' -f 4-)
EPISODENAME=$(fixFileName "$EPISODENAME" true)

# print the title_subtitle for logging purposes
echo "Details = '$DETAILS'" >> $LOGFILE
echo "Season = '$SEASON'" >> $LOGFILE
echo "Episode = '$EPISODE'" >> $LOGFILE
echo "Show Name = '$SHOWNAME'" >> $LOGFILE
echo "Episode Name = '$EPISODENAME'" >> $LOGFILE

# Remove period's from the folder name
FOLDERSHOWNAME=$(echo "$SHOWNAME" | sed 's/[.]//g')
# create a new output directory under video/[tv_title]. Example: video/Game of Thrones
OUTDIR="$VIDEOFOLDER/$FOLDERSHOWNAME"

# should end up being something like Archer - s05e02 - Archer Vice A Kiss While Dying
# or if Season and Episode are missing then: Archer - 1401_20140427203000
# or if Season is missing then: Archer - Archer Vice A Kiss While Dying
NEWFILENAME="$SHOWNAME"

if [ "$SEASON" != "0" ] || [ "$EPISODE" != "0" ]; then
    echo "Season and Episode have a valid number." >> $LOGFILE

    OUTDIR="$OUTDIR/Season $SEASON"

    # reformat season and episode numbers
    SEASON=$(printf "%02d" $SEASON)
    EPISODE=$(printf "%02d" $EPISODE)

    NEWFILENAME="$NEWFILENAME - s$SEASON""e$EPISODE"
fi

if [ ! -d "$OUTDIR" ]; then
    mkdir -p "$OUTDIR"
    #chmod 777 "$OUTDIR"
fi

cd "$OUTDIR"

# add episode name or air date to the end of the filename
if [ ! -z "$EPISODENAME" ]; then
    NEWFILENAME="$NEWFILENAME - $EPISODENAME"
else
    ST=$2
    # Convert the Start Time UTC into a Date object we can manipulate
    NEWST=$(date -d "UTC ${ST:0:8} ${ST:8:2}:${ST:10:2}:${ST:12:2}")
    # Format date so it is month_day_year
    NEWFILENAME="$NEWFILENAME - "$(date -d "$NEWST" "+%m_%d_%Y")
    # If the filename already exists then append the Hour, Minute, and Seconds
    if [ -e "$NEWFILENAME.mp4" ]; then
        NEWFILENAME="$NEWFILENAME-"$(date -d "$NEWST" "+%I_%M_%S")
    fi
fi

echo "Output Directory = '$OUTDIR'" >> $LOGFILE
echo "New File Name = '$NEWFILENAME'" >> $LOGFILE

# FOR TESTING ONLY
#echo "Exit status: $?" >> $LOGFILE
echo "============================================================================" >> $LOGFILE
#exit $?;

MPGTRANSCODE="$INSTALLPREFIX/mythtranscode --chanid \"$1\" --starttime \"$2\" --mpeg2";
# Determine if the commercials should be cut
CUTCOMMERCIALS=${3:-false};
if [ $CUTCOMMERCIALS = true ]; then
    echo "Cutting commercials for $NEWFILENAME" >> $LOGFILE
    # flag the commercials in the MythTV (.mpg) recording: build  a cutlist)
    $INSTALLPREFIX/mythutil --chanid "$1" --starttime "$2" --gencutlist
    # add the argument to remove the commercials, using the cut list
    MPGTRANSCODE="$MPGTRANSCODE --honorcutlist";
else
    echo "NOT Cutting commercials for $NEWFILENAME" >> $LOGFILE
fi

MPGTRANSCODE="$MPGTRANSCODE -o \"$MPDIR/$NEWFILENAME.mpg\"";
echo "MPGTRANSCODE = $MPGTRANSCODE" >> $LOGFILE

# transcode #1: lossless transcode to MPEG2
eval "$MPGTRANSCODE";

# transcode #2: re-encode the MPEG2 video to MP4, using Handbrake command-line app
# old audio parameters: -a 1,2 -E copy:ac3,copy:aac --audio-fallback faac --audio-copy-mask ac3,aac
$INSTALLPREFIX/HandBrakeCLI -i "$MPDIR/$NEWFILENAME.mpg" -o "$MPDIR/$NEWFILENAME.mp4" -a 1 -E copy:ac3 --audio-fallback faac --audio-copy-mask ac3 --large-file --preset="Normal"

echo "Transcode status for '$NEWFILENAME': $?" >> $LOGFILE

# check if the transcode exited with an error
if [ $? != 0 ]; then
    echo "Error occurred running Handbrake: input=$MPDIR/$NEWFILENAME.mpg output=$OUTDIR/$NEWFILENAME.mp4" >> $LOGFILE
else
    # If the transcode process did not fail then move the new mp4 file from the temporary directory to OUTDIR
    echo "Moving file '$MPDIR/$NEWFILENAME.mp4'" >> $LOGFILE
    mv "$MPDIR/$NEWFILENAME.mp4" "$NEWFILENAME.mp4"
    # delete the temporary working directory
    rm -rf "$MPDIR"
fi

echo "Exit status for '$NEWFILENAME': $?" >> $LOGFILE
echo "============================================================================" >> $LOGFILE

exit $?;
