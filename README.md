MythTV transcode to MP4
=======

This is a simple and dirty shell script to transcode recordings to MP4 format and move them to
the 'Videos' folder. This script will not alter your Recordings or database data.
You will need to create or use another script for that purpose.

Additional Information
----------------------

I use [Schedules Direct](http://www.schedulesdirect.org/) to generate Guide data.
This script will attempt to find the proper Season and Episode numbers from the 'mythconverg'
database and create the proper folder tree. If your guide data is not correct then there's
a chance the Season and Episode numbers will not exist or contain the wrong data. If a recordings
Season and Episode number are both 0 then the script defaults to using only the Show Name and
Episode Title for naming convention. In the event that the Episode Title is also blank then it will
use the CHANID and STARTTIME information instead.


Using the script
----------------

Upload this script to a directory that is accessible by MythTV.

    Change the DATABASEPASSWORD variable with your mythtv database password.

Make the script executable:

    chmod  +x my_mp4_transcode.sh

For MythTV 0.25 and below, assign the script to a user job using the following format:

    /path/to/script/my_mp4_transcode.sh "%CHANID%" "%STARTTIME%"

For MythTV 0.26 and above, assign the script to a user job using the following format:

    /path/to/script/my_mp4_transcode.sh "%CHANID%" "%STARTTIMEUTC%"

Recommendations
---------------

If you do not want to run an additional script to delete your original recordings then you can set
them to automatically expire and also set the maximum recordings to a low number. You can also set
the database entry "AutoRunUserJob1" to 1 in order to allow the transcode job to run automatically.

Credit
------

This script is heavily modified from the following source:
http://tech.surveypoint.com/blog/mythtv-transcoding-with-handbrake/
