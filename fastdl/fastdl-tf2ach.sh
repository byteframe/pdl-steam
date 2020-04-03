#!/bin/bash

DIR="$( cd "$( dirname "$0" )" && pwd )"
if [ -L "${DIR}" ]; then
  DIR=$(readlink "${DIR}")
fi
cd "${DIR}"
echo "PASSWORD:"
read -s PASSWORD
mv ../plugins/sourceirc-* .
{
  echo "open -u a1764051,${PASSWORD} primarydataloop.comoj.com"
  echo "cd /public_html/pdl-steam"
  echo "mput *.diff ../pdl-steam.conf ../pdl-steam.sh ../README ../LICENSE items.*"
  echo "mirror -eR ../plugins"
  echo "mirror -eR ../fastdl/tf2ach"
  echo "mkdir tf2ach/replay"
  echo "rm -fr configs"
  echo "mkdir configs"
  echo "cd configs"
  echo "put ../configs/achievement_idle.cfg ../configs/achievement_idle_alpine_v2.cfg"
  echo "put ../configs/tf2ach.cfg ../configs/tf2ach-plugins.cfg"
  echo "exit"
} > lftp-script
lftp -f lftp-script
rm lftp-script
mv sourceirc-* ../plugins
