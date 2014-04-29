#!/bin/sh

# From: http://tech.surveypoint.com/blog/mythtv-transcoding-with-handbrake/
# My MythTV user job to transcode a video to mp4

# this script expects 2 parameters to identify the recording:
#   4-digit channel ID
#   and 14-digit datetime code (YYYYMMDDDHHMMSS)

# fixes file names so that they do not have any illegal characters.
# passing the second argument as true will replace spaces with underscores
fixFileName() {
    NEWNAME=$(echo "$1" | awk -F/ '{print $NF}' | sed 's/://g' | sed 's/?//g' | sed s/"'"/""/g | sed 's/,//g')
    if [ ${2:-false} = true ]; then
        NEWNAME=$(echo "$NEWNAME" | sed 's/ /_/g')
    fi
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
echo "Started transcode for $1_$2" >> $LOGFILE

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

# ignore the first line (column heading);  parse only the second line (result)
#DETAILS=$(sed -n '2,2p' tv-title_$MYPID.txt)

# get the show season and episode numbers using ; as a delimiter
SEASON=$(echo "$DETAILS" | cut -d';' -f 1)
EPISODE=$(echo "$DETAILS" | cut -d';' -f 2)

# get the show name using ; as a delimiter
SHOWNAME=$(echo "$DETAILS" | cut -d';' -f 3)
SHOWNAME=$(fixFileName "$SHOWNAME")
if [ -z "$SHOWNAME" ]; then
    SHOWNAME="Other"
fi

# get the episode name
EPISODENAME=$(echo "$DETAILS" | cut -d';' -f 4-)
EPISODENAME=$(fixFileName "$EPISODENAME")

# print the title_subtitle for logging purposes
echo "Details = '$DETAILS'" >> $LOGFILE
echo "Season = '$SEASON'" >> $LOGFILE
echo "Episode = '$EPISODE'" >> $LOGFILE
echo "Show Name = '$SHOWNAME'" >> $LOGFILE
echo "Episode Name = '$EPISODENAME'" >> $LOGFILE

# create a new output directory under video/[tv_title]. Example: video/game_of_thrones
OUTDIR="$VIDEOFOLDER/$SHOWNAME"

# should end up being something like Archer - s05e02 - Archer Vice A Kiss While Dying
# or if Season and Episode are missing then: Archer - Archer Vice A Kiss While Dying - 1401_20140427203000
# or if Episode name is missing then: Archer - 1401_20140427203000
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

# add episode name or chanid and starttime to the end of the filename
if [ ! -z "$EPISODENAME" ]; then
    NEWFILENAME="$NEWFILENAME - $EPISODENAME"
else
    NEWFILENAME="$NEWFILENAME - $1_$2"
fi

echo "Output Directory = '$OUTDIR'" >> $LOGFILE
echo "New File Name = '$NEWFILENAME'" >> $LOGFILE

cd "$OUTDIR"

# FOR TESTING ONLY
#echo "Exit status: $?" >> $LOGFILE
echo "============================================================================" >> $LOGFILE
#exit $?;

# flag the commercials in the MythTV (.mpg) recording: build  a cutlist)
$INSTALLPREFIX/mythutil --chanid "$1" --starttime "$2" --gencutlist
# transcode #1: remove the commercials, using the cut list (lossless transcode to MPEG2)
$INSTALLPREFIX/mythtranscode --chanid "$1" --starttime "$2" --mpeg2 --honorcutlist -o "$MPDIR/$NEWFILENAME.mpg"
# transcode #2: re-encode the MPEG2 video to MP4, using Handbrake command-line app
$INSTALLPREFIX/HandBrakeCLI -i "$MPDIR/$NEWFILENAME.mpg" -o "$NEWFILENAME.m4v" --audio 1 --aencoder copy:aac --audio-fallback faac --audio-copy-mask aac --large-file --preset="Normal"

# delete the temporary working directory
rm -rf "$MPDIR"

echo "Transcode status for '$NEWFILENAME': $?" >> $LOGFILE

# check if the transcode exited with an error; if not, delete the intermediate MPEG file and map
if [ $? != 0 ]; then
    echo "Error occurred running Handbrake: input=$OUTDIR/$NEWFILENAME.mpg output=$OUTDIR/$NEWFILENAME.m4v" >> $LOGFILE
else
    # only delete the mpg file if there were no errors during the transcoding process.
    rm "$NEWFILENAME.mpg"
fi

# always remove the map file
MAPFILE="$NEWFILENAME.mpg.map"
if [ -e "$MAPFILE" ]; then
    rm "$MAPFILE"
fi

echo "Exit status for '$NEWFILENAME': $?" >> $LOGFILE
echo "============================================================================" >> $LOGFILE

exit $?;
