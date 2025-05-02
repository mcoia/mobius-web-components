## Summary

These bash scripts automate the drupal cache refresh when the label maker table is updated.

## Installation

refresh_drupal_prod_cache.sh needs to be in your home folder

cp refresh_drupal_prod_cache.sh ~/
chmod 755 ~/refresh_drupal_prod_cache.sh

mkdir ~/label_maker_diff_detector
cp label_maker_diff_detector.sh ~/label_maker_diff_detector/
chmod 755 ~/label_maker_diff_detector/label_maker_diff_detector.sh

setup a cron job to run every minute to see if the table has been updated, if it has, it will refresh the drupal cache

* * * * * cd ~/label_maker_diff_detector/ && ./label_maker_diff_detector.sh > /dev/null 2>&1


## .my.cnf

You will need to be sure and edit your user's default .my.cnf so that it can connect without a password

example:

vi .my.cnf

[client]
user=dbuser
password=dbpassword
database=databasename
host=127.0.0.1
port=3306
prompt=drupal PRODUCTION:\d >

