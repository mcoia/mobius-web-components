#!/bin/bash

BASELINE=label_base
DIFFFILE=label_diff
DIFFACTION="cd ~/ && ./refresh_drupal_prod_cache.sh"

mysql -e 'select * from label_maker_nodes order by id;'|md5sum > $DIFFFILE

diff $BASELINE $DIFFFILE
RESULT=$?
if [ $RESULT -eq 0 ]; then
  echo files are the same
else
  mysql -e 'select * from label_maker_nodes order by id;'|md5sum > $BASELINE
  echo executing: $DIFFACTION
  echo "$DIFFACTION" |bash
fi
