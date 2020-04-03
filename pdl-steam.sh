#!/bin/sh
# pdl-steam.sh (0.79++)
# Copyright (c) 2008-2013 primarydataloop

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>

# change the present working directory to that of this script
DIR="$( cd "$( dirname "$0" )" && pwd )"
if [ -L "${DIR}" ]; then
  DIR=$(readlink "${DIR}")
fi
cd "${DIR}"

function steam_start()
{
  # startup checks
  for DEP in screen sudo mysql wget; do
    if ! which ${DEP} > /dev/null 2>&1; then
      echo "${DEP} not installed"
      exit 1
    fi
  done
  if [ -e pdl-steam.pid ]; then
    echo "fatal, pdl-steam is already running"
    exit 1
  fi
  touch pdl-steam.pid
  source ./pdl-steam.conf || exit 1
  chmod 600 pdl-steam.conf
  mkdir -p configs plugins

  # get network device ip
  for DEV in $(cat /proc/net/dev | grep : | cut -d ':' -f 1); do
    if [ ${DEV} != lo ]; then
      IP=$(/sbin/ip addr show ${DEV} | grep "inet " | awk '{print $2}' \
        | sed -e "s/\/.*//")
      if [ ! -z ${IP} ]; then
        break
      fi
    fi
  done

  # process server definitions
  USED_NAME=,
  USED_PORT=,
  USED_HGAM=,
  USED_SGAM=,
  for ((x=0; x < ${#NAME[*]}; x++)); do
    NAME[$x]=$(echo ${NAME[$x]} | sed -e "s/ /_/g" -e "s/,/ /g")
    if [ -z ${NAME[$x]} ]; then
      echo "error, empty \$NAME"
      continue
    elif [[ ${USED_NAME} == *,${NAME[$x]},* ]]; then
      echo "error, name in use, skipping ${NAME[$x]}"
      continue
    elif [ -z ${SERV[$x]} ]; then
      echo "error, missing \$SERV, skipping ${NAME[$x]}"
      continue
    elif [ -z ${PORT[$x]} ]; then
      echo "error, missing \$PORT, skipping ${NAME[$x]}"
      continue
    elif [[ ${USED_PORT} == *,${PORT[$x]},* ]]; then
      echo "error, port ${PORT[$x]} in use, skipping ${NAME[$x]}"
      continue
    elif [ -z ${GAME[$x]} ]; then
      echo "error, missing \$GAME, skipping ${NAME[$x]}"
      continue
    fi

    # install/update hlstatsx
    if [ ${HLXC[$x]} = yes ]; then
      mkdir -p hlstatsx
      HLX=1.6.19
      if [ ! -e hlstatsx/HLXCE-${HLX}-FULL.zip ]; then
        if [ -e hlstatsx/HLXCE-*-FULL.zip ]; then
          OLD_HLX=yes
        fi
        rm -fr hlstatsx/*
        wget -nv bitbucket.org/psychonic/hlstatsxce/downloads/HLXCE-${HLX}-FULL.zip \
          -O hlstatsx/HLXCE-${HLX}-FULL.zip || exit 1
        unzip -q hlstatsx/HLXCE-${HLX}-FULL.zip -d hlstatsx
        mv hlstatsx/hlxce-${HLX}/* hlstatsx
        rmdir hlstatsx/hlxce-${HLX}
        chmod +x hlstatsx/scripts/*.pl
        chmod +x hlstatsx/scripts/run_hlstats
        cp hlstatsx/sourcemod/plugins/hlstatsx.smx plugins
      fi

      # configure hlstatsx
      sed -i -e "s/^DBHost \".*\"/DBHost \"${DB_HOST}\"/" \
        -e "s/^DBUsername \".*\"/DBUsername \"${DB_USER}\"/" \
        -e "s/^DBPassword \".*\"/DBPassword \"${DB_PASS}\"/" \
        -e "s/^DBName \".*\"/DBName \"${DB_NAME}\"/" \
        hlstatsx/scripts/hlstats.conf
      chmod 600 hlstatsx/scripts/hlstats.conf
      sed -i -e "s/DBHOST=\".*\"/DBHOST=\"\"/" \
        -e "s/DBHOST=\".*\"/DBHOST=\"${DB_HOST}\"/" \
        -e "s/DBNAME=\".*\"/DBNAME=\"${DB_NAME}\"/" \
        -e "s/DBUSER=\".*\"/DBUSER=\"${DB_USER}\"/" \
        -e "s/DBPASS=\".*\"/DBPASS=\"${DB_PASS}\"/" \
        hlstatsx/scripts/GeoLiteCity/GeoLite_Import.sh
      sed -i -e "s/^TODAY_MONTH=\$( date +%m )/let &-1/" \
        hlstatsx/scripts/GeoLiteCity/GeoLite_Import.sh
      chmod 700 hlstatsx/scripts/GeoLiteCity/GeoLite_Import.sh
      cp hlstatsx/web/config.php hlstatsx/web/config.php.tmp
      sed -e "s/(\"DB_ADDR\", \".*\");/(\"DB_ADDR\", \"${DB_HOST}\");/" \
        -e "s/(\"DB_NAME\", \".*\");/(\"DB_NAME\", \"${DB_NAME}\");/" \
        -e "s/(\"DB_USER\", \".*\");/(\"DB_USER\", \"${DB_USER}\");/" \
        -e "s/(\"DB_PASS\", \".*\");/(\"DB_PASS\", \"${DB_PASS}\");/" \
        hlstatsx/web/config.php.tmp > hlstatsx/web/config.php
      rm hlstatsx/web/config.php.tmp
      chmod 640 hlstatsx/web/config.php

      # handle hlstatsx web link and permissions
      if [ ! -e /var/www/htdocs/hlstatsx ]; then
        echo "ENTER ROOT PASSWORD TO CREATE HLSTATSX WEB LINK"
        sudo ln -sf "${DIR}"/hlstatsx/web /var/www/htdocs/hlstatsx
      fi
      if [ $(stat -c %G hlstatsx/web/config.php) != apache ] ; then
        echo "ENTER ROOT PASSWORD TO PROTECT HLSTATSX WEB CONFIGURATION"
        sudo chown ${USER}:apache "${DIR}"/hlstatsx/web/config.php
      fi

      function backup_database()
      {
        # dump database contents to a backup file
        for FILE in hlstatsx/20*_backup.sql; do
          mv ${FILE} ${FILE}.last
        done
        echo "backing up hlstatsx database..."
        mysqldump -h ${DB_HOST} -u ${DB_USER} -p${DB_PASS} ${DB_NAME} \
          > hlstatsx/$(date +%Y%m%d)_backup.sql
        chmod 600 hlstatsx/$(date +%Y%m%d)_backup.sql
      }

      # update/create hlstatsx database
      if [ -d hlstatsx/web/updater ]; then
        if [ ! -z ${OLD_HLX} ]; then
          backup_database
          echo "UPDATE DB AT 'http://<webserver>/hlstatsx/updater' AND HIT [ENTER]"
          read PAUSE
          rm -fr hlstatsx/web/updater
        else
          echo "INPUT MYSQL ROOT PASSWORD:"
          read -s MYSQL_PASS
          mysql -h ${DB_HOST} -u root -p${MYSQL_PASS} \
            -e "CREATE DATABASE ${DB_NAME}"
          mysql -h ${DB_HOST} -u root -p${MYSQL_PASS} ${DB_NAME} \
            < hlstatsx/sql/install.sql
          mysql -h ${DB_HOST} -u root -p${MYSQL_PASS} -e \
            "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'${DB_HOST}' IDENTIFIED BY '${DB_PASS}'"
          unset MYSQL_PASS
          backup_database
          rm -fr hlstatsx/web/updater
          sh hlstatsx/scripts/GeoLiteCity/GeoLite_Import.sh
          echo "DO THE FOLLOWING MANUALLY AND HIT [ENTER]"
          echo "(web) change admin pw from the default \"123456\""
          echo "(web) set to geoip lookup via database"
          read PAUSE
        fi
      fi

      # add hlstatsx awards crontab entry
      if ! crontab -l | grep -q hlstatsx; then
        echo hlstat | crontab -
      fi
      crontab -l | sed -e \
        's!.*hlstat.*!00 00 * * * cd '${DIR}'/hlstatsx/scripts \&\& ./hlstats-awards.pl \&\& touch hlstats-awards.pl!' \
        | crontab -

      # backup hlstatsx database weekly
      if [ ! -z $(find hlstatsx/ -maxdepth 1 -name 20*_backup.sql -mtime +7) ] \
      || [ ! -e hlstatsx/20*_backup.sql ]; then
        backup_database
      fi

      # run hlstatsx awards script if it hasn't already today
      ( cd hlstatsx/scripts
        if [ $(stat -c %Y hlstats-awards.pl) -lt $(date -d 00:00 +%s) ]; then
          echo "running hlstatsx awards script..."
          ./hlstats-awards.pl > /dev/null
          touch hlstats-awards.pl
        fi
      )

      # update hlstatsx geoip data monthy
      if [ ! -z $(find hlstatsx/ -name GeoLite_Import.sh -mtime +28) ]; then
        echo "upgrading hlstatsx geoip data..."
        sh hlstatsx/scripts/GeoLiteCity/GeoLite_Import.sh > /dev/null 2>&1
        touch hlstatsx/scripts/GeoLiteCity/GeoLite_Import.sh
      fi

      # clean hlstatsx logs
      rm -f hlstatsx/scripts/logs/*

      # start hlstatsx daemon
      ( cd hlstatsx/scripts
        echo "starting hlstatsx daemon..."
        ./run_hlstats start > /dev/null
      )
    fi

    # install steamcmd
    if [ ! -e steamcmd/steamcmd.sh ]; then
      echo "installing steamcmd..."
      mkdir -p steamcmd
      rm -fr steamcmd/*
      wget -q media.steampowered.com/client/steamcmd_linux.tar.gz || exit 1
      tar xzf steamcmd_linux.tar.gz -C steamcmd
      rm steamcmd_linux.tar.gz
    fi
    if [ -e ${HOME}/Steam ] \
    && [ "$(readlink ${HOME}/Steam)" != "${DIR}"/steamcmd ]; then
      echo "fatal, ${HOME}/Steam claimed"
      exit 1
    fi
    rm -f ${HOME}/Steam
    ln -sf "${DIR}"/steamcmd ${HOME}/Steam
    STEAM="-steam_dir "${DIR}"/steamcmd -steamcmd_script \
      "${DIR}"/steamcmd/update_${GAME[$x]}.txt"

    # check hlds used servers
    if [ ${SERV[$x]} = hlds ]; then
      if [[ ${USED_HGAM} == *,${GAME[$x]},* ]]; then
        echo "error, a ${GAME[$x]} server is already up, skipping ${NAME[$x]}"
        continue
      fi

      # install/update hlds game content
      GAMEDIR=hlds-${GAME[$x]}/${GAME[$x]}
      if [ ! -d ${GAMEDIR} ]; then
        if [[ cstrike,dod,tfc,valve != *${GAME[$x]}* ]]; then
          echo "error, \"${GAME[$x]}\" not valid game for hlds"
          continue
        fi
        for I in {1..3}; do
          sh steamcmd/steamcmd.sh +login anonymous +force_install_dir \
            ../hlds-${GAME[$x]} +app_set_config 90 mod ${GAME[$x]} \
            +app_update 90 validate +quit
        done
      fi
      sed -i -e "s/\"steamcmd\/steamcmd.sh/\"..\/steamcmd\/steamcmd.sh/" \
        -e "s/stall_dir .. /stall_dir ..\/hlds-${GAME[$x]} +app_set_config 90 mod ${GAME[$x]} /" \
        hlds-${GAME[$x]}/hlds_run
      find ${GAMEDIR} -type l -exec rm {} \;

      # install/update metamod and amxmodx
      MM=http://y4kstudios.com/sourcemod/mirror/metamod-1.21.1-am.zip
      if [ ! -e ${GAMEDIR}/${MM##*/} ]; then
        echo "installing/upgrading metamod..."
        rm -f ${GAMEDIR}/metamod-*-am.zip
        wget -q ${MM} -O ${GAMEDIR}/${MM##*/} || exit 1
        mkdir -p ${GAMEDIR}/addons/metamod/dlls
        unzip -q ${GAMEDIR}/${MM##*/} -d ${GAMEDIR}
        sed -i -e "s/\"dlls\/[a-z]*/\"addons\/metamod\/dlls\/metamod/" \
          ${GAMEDIR}/liblist.gam
      fi
      AM=http://y4kstudios.com/sourcemod/mirror/amxmodx-1.8.2-base-linux.tar.gz
      PCFG=${GAMEDIR}/addons/amxmodx/configs/amxx.cfg
      if [ ! -e ${GAMEDIR}/${AM##*/} ]; then
        echo "installing/upgrading amxmodx..."
        rm -rf ${GAMEDIR}/amxmodx-*-*.tar.gz ${GAMEDIR}/addons/amxmodx
        wget -q ${AM} -O ${GAMEDIR}/${AM##*/} || exit 1
        tar -xzf ${GAMEDIR}/${AM##*/} -C ${GAMEDIR}
        echo "linux addons/amxmodx/dlls/amxmodx_mm_i386.so" \
          > ${GAMEDIR}/addons/metamod/plugins.ini
        if [ ${GAME[$x]} != valve ]; then
          AM=http://y4kstudios.com/sourcemod/mirror/amxmodx-1.8.2-${GAME[$x]}-linux.tar.gz
          wget -q ${AM} -O ${GAMEDIR}/${AM##*/} || exit 1
          tar -xzf ${GAMEDIR}/${AM##*/} -C ${GAMEDIR}
        fi
        cp ${PCFG} ${PCFG}.def
        cp ${GAMEDIR}/addons/amxmodx/configs/cmds.ini \
          ${GAMEDIR}/addons/amxmodx/configs/cmds.ini.def
        cp ${GAMEDIR}/addons/amxmodx/configs/plugins.ini \
          ${GAMEDIR}/addons/amxmodx/configs/plugins.ini.def
        cp ${GAMEDIR}/addons/amxmodx/configs/sql.cfg \
          ${GAMEDIR}/addons/amxmodx/configs/sql.cfg.def
        cp ${GAMEDIR}/addons/amxmodx/configs/users.ini \
          ${GAMEDIR}/addons/amxmodx/configs/users.ini.def
        if [ ${HLXC[$x]} = yes ]; then
          echo "USE THE HLSTATSX WEB GUI TO DO THE FOLLOWING AND HIT [ENTER]"
          echo "unhide game ${GAME[$x]}"
          echo "add hlds server for ${GAME[$x]}"
          read PAUSE
          ( cd hlstatsx/scripts
            echo "restarting hlstatsx daemon..."
            ./run_hlstats restart > /dev/null
          )
        fi
      fi

      # assemble amxmodx data and configs
      if [ ! -e configs/${NAME[$x]}_admins.ini ]; then
        cp ${GAMEDIR}/addons/amxmodx/configs/users.ini.def \
          configs/${NAME[$x]}_admins.ini
      fi
      if [ ! -e configs/${NAME[$x]}_commands.ini ]; then
        cp ${GAMEDIR}/addons/amxmodx/configs/cmds.ini.def \
          configs/${NAME[$x]}_commands.ini
      fi
      if [ ! -e configs/${NAME[$x]}_database.cfg ]; then
        cp ${GAMEDIR}/addons/amxmodx/configs/sql.cfg.def \
          configs/${NAME[$x]}_database.cfg
      fi
      ln -sf "${DIR}"/configs/${NAME[$x]}_admins.ini \
        ${GAMEDIR}/addons/amxmodx/configs/users.ini
      ln -sf "${DIR}"/configs/${NAME[$x]}_commands.ini \
        ${GAMEDIR}/addons/amxmodx/configs/cmds.ini
      ln -sf "${DIR}"/configs/${NAME[$x]}_database.cfg \
        ${GAMEDIR}/addons/amxmodx/configs/sql.cfg
      cp ${GAMEDIR}/addons/amxmodx/configs/plugins.ini.def \
        ${GAMEDIR}/addons/amxmodx/configs/plugins.ini
      if [ ${GAME[$x]} != valve ] && [ ${HLXC[$x]} = yes ]; then
        cp hlstatsx/amxmodx/plugins/hlstatsx_commands_${GAME[$x]}.amxx plugins
        PLGS[$x]="hlstatsx_commands_${GAME[$x]} ${PLGS[$x]}"
      fi
      find ${GAMEDIR}/addons/amxmodx -depth -not -name compiled \
        -not -name logs -type d -empty -exec rmdir {} \;
      for FILE in ${PLGS[$x]}; do
        if [ -e plugins/${FILE}.sma ]; then
          ln -sf "${DIR}"/plugins/${FILE}.sma \
            ${GAMEDIR}/addons/amxmodx/scripting
        fi
        if [ -e plugins/${FILE}.amxx ]; then
          ln -s "${DIR}"/plugins/${FILE}.amxx ${GAMEDIR}/addons/amxmodx/plugins
          echo "${FILE}.amxx" >> ${GAMEDIR}/addons/amxmodx/configs/plugins.ini
        elif [ -d plugins/${FILE} ]; then
          lndir -silent "${DIR}"/plugins/${FILE} ${GAMEDIR}
        else
          echo "warning, plugins/${FILE}.amxx not found"
        fi
      done
      if [ ${DBUG[$x]} = yes ]; then
        sed -i -e "s/amxx_logging\t0/amxx_logging\t1/" \
          ${GAMEDIR}/addons/amxmodx/configs/core.ini
      else
        sed -i -e "s/amxx_logging\t1/amxx_logging\t0/" \
          ${GAMEDIR}/addons/amxmodx/configs/core.ini
      fi
      chmod 700 ${GAMEDIR}/addons/amxmodx/configs
      BANFILE=banned.cfg
      USED_HGAM=${USED_HGAM}${GAME[$x]},
      echo "logaddress_add ${IP} 27500" > ${GAMEDIR}/server.cfg

    # check srcds used servers
    elif [ ${SERV[$x]} = srcds ]; then
      if [[ ${USED_SGAM} == *,${GAME[$x]},* ]]; then
        echo "error, a ${GAME[$x]} server is already up, skipping ${NAME[$x]}"
        continue
      fi

      # install srcds game content
      if [ ${GAME[$x]} = cstrike ]; then
        INST=232330
      elif [ ${GAME[$x]} = dod ]; then
        INST=232290
      elif [ ${GAME[$x]} = hl2mp ]; then
        INST=232370
      elif [ ${GAME[$x]} = left4dead2 ]; then
        INST=222860
      elif [ ${GAME[$x]} = tf ]; then
        INST=232250
      else
        echo "error, \"${GAME[$x]}\" not valid game for srcds"
        continue
      fi
      GAMEDIR=${SERV[$x]}-${GAME[$x]}/${OB}${GAME[$x]}
      if [ ! -e steamcmd/update_${GAME[$x]}.txt ]; then
        {
          echo "@ShutdownOnFailedCommand 1"
          echo "@NoPromptForPassword 1"
          echo "login anonymous"
          echo "force_install_dir ../srcds-${GAME[$x]}"
          echo "app_update ${INST}"
          echo "quit"
        } > steamcmd/update_${GAME[$x]}.txt
        sh steamcmd/steamcmd.sh +login anonymous +force_install_dir \
          ../srcds-${GAME[$x]} +app_update ${INST} validate +quit
      fi
      find ${GAMEDIR} -type l -exec rm {} \;

      # install/update sourcemod
      MS=newyork.download.maverickservers.com/source/mmsource-1.10.0-linux.tar.gz
      if [ ! -e ${GAMEDIR}/${MS##*/} ]; then
        echo "installing/upgrading metamod:source..."
        rm -fr ${GAMEDIR}/mmsource-*-linux.tar.gz ${GAMEDIR}/addons/metamod/bin
        wget -q ${MS} -O ${GAMEDIR}/${MS##*/} || exit 1
        tar -xzf ${GAMEDIR}/${MS##*/} -C ${GAMEDIR}
        wget -q www.sourcemm.net/vdf?vdf_game=${GAME[$x]} \
          -O ${GAMEDIR}/addons/metamod.vdf || exit 1
      fi
      SM=newyork.download.maverickservers.com/source/sourcemod-1.5.2-linux.tar.gz
      PCFG=${GAMEDIR}/cfg/sourcemod/sourcemod.cfg
      if [ ! -e ${GAMEDIR}/${SM##*/} ]; then
        echo "installing/upgrading sourcemod..."
        rm -fr ${GAMEDIR}/sourcemod-*-linux.tar.gz ${GAMEDIR}/cfg/sourcemod \
          ${GAMEDIR}/addons/sourcemod
        wget -q ${SM} || exit 1
        mv ${SM##*/} ${GAMEDIR}
        tar -xzf ${GAMEDIR}/${SM##*/} -C ${GAMEDIR}
        cp ${PCFG} ${PCFG}.def
        cp ${GAMEDIR}/addons/sourcemod/configs/admins_simple.ini \
          ${GAMEDIR}/addons/sourcemod/configs/admins_simple.ini.def
        cp ${GAMEDIR}/addons/sourcemod/configs/admin_overrides.cfg \
          ${GAMEDIR}/addons/sourcemod/configs/admin_overrides.cfg.def
        cp ${GAMEDIR}/addons/sourcemod/configs/databases.cfg \
          ${GAMEDIR}/addons/sourcemod/configs/databases.cfg.def
        if [ ${HLXC[$x]} = yes ]; then
          echo "USE THE HLSTATSX WEB GUI TO DO THE FOLLOWING AND HIT [ENTER]"
          echo "(web) unhide game ${GAME[$x]}"
          echo "(web) add ${SERV[$x]} server for ${GAME[$x]}"
          read PAUSE
          ( cd hlstatsx/scripts
            echo "restarting hlstatsx daemon..."
            ./run_hlstats restart > /dev/null
          )
        fi
      fi

      # assemble sourcemod data and configs
      if [ ! -e configs/${NAME[$x]}_admins.ini ]; then
        cp ${GAMEDIR}/addons/sourcemod/configs/admins_simple.ini.def \
          configs/${NAME[$x]}_admins.ini
      fi
      if [ ! -e configs/${NAME[$x]}_commands.ini ]; then
        cp ${GAMEDIR}/addons/sourcemod/configs/admin_overrides.cfg.def \
          configs/${NAME[$x]}_commands.ini
      fi
      if [ ! -e configs/${NAME[$x]}_database.cfg ]; then
        cp ${GAMEDIR}/addons/sourcemod/configs/databases.cfg.def \
          configs/${NAME[$x]}_database.cfg
      fi
      ln -sf "${DIR}"/configs/${NAME[$x]}_admins.ini \
        ${GAMEDIR}/addons/sourcemod/configs/admins_simple.ini
      ln -sf "${DIR}"/configs/${NAME[$x]}_commands.ini \
        ${GAMEDIR}/addons/sourcemod/configs/admin_overrides.cfg
      ln -sf "${DIR}"/configs/${NAME[$x]}_database.cfg \
        ${GAMEDIR}/addons/sourcemod/configs/databases.cfg
      find ${GAMEDIR}/addons/sourcemod -depth -not -name compiled \
        -not -name logs -type d -empty -exec rmdir {} \;
      if [ ${HLXC[$x]} = yes ]; then
        PLGS[$x]="hlstatsx ${PLGS[$x]}"
      fi
      for FILE in ${PLGS[$x]}; do
        if [ -e plugins/${FILE}.sp ]; then
          ln -sf "${DIR}"/plugins/${FILE}.sp \
            ${GAMEDIR}/addons/sourcemod/scripting
        fi
        if [ -e plugins/${FILE}.smx ]; then
          ln -sf "${DIR}"/plugins/${FILE}.smx ${GAMEDIR}/addons/sourcemod/plugins
          if [ -e plugins/${FILE}.phrases.txt ]; then
            ln -sf "${DIR}"/plugins/${FILE}.phrases.txt \
              ${GAMEDIR}/addons/sourcemod/translations
          fi
        elif [ -d plugins/${FILE} ]; then
          lndir -silent "${DIR}"/plugins/${FILE} ${GAMEDIR}
        else
          echo "warning, plugins/${FILE}.smx not found"
        fi
      done
      if [ ${DBUG[$x]} = yes ]; then
        sed -i -e "s/Logging\"\t\t\"off\"/Logging\"\t\t\"on\"/" \
          ${GAMEDIR}/addons/sourcemod/configs/core.cfg
      else
        sed -i -e "s/Logging\"\t\t\"on\"/Logging\"\t\t\"off\"/" \
          ${GAMEDIR}/addons/sourcemod/configs/core.cfg
      fi
      chmod 700 ${GAMEDIR}/addons/sourcemod/configs
      BANFILE=banned_user.cfg
      CFGDIR=cfg
      USED_SGAM=${USED_SGAM}${GAME[$x]},
      echo "logaddress_add ${IP}:27500" > ${GAMEDIR}/${CFGDIR}/server.cfg
      if [ ! -e ${GAMEDIR}/cfg/replay.cfg ] && [ ${GAME[$x]} = tf ]; then
        cp ${GAMEDIR}/cfg/replay_example.cfg ${GAMEDIR}/cfg/replay.cfg
      fi
      if [ ! -e ${GAMEDIR}/motd_text.txt.def ]; then
        cp ${GAMEDIR}/motd_text.txt ${GAMEDIR}/motd_text.txt.def 2> /dev/null \
          || touch ${GAMEDIR}/motd_text.txt.def
      fi
      if [ ! -e configs/${NAME[$x]}_motd_text.txt ]; then
        cp ${GAMEDIR}/motd_text.txt.def configs/${NAME[$x]}_motd_text.txt
      fi
      ln -sf "${DIR}"/configs/${NAME[$x]}_motd_text.txt ${GAMEDIR}/motd_text.txt

    else
      echo "error, \"${SERV[$x]}\" is an invalid server, skipping ${NAME[$x]}"
      continue
    fi

    # assemble server configuration
    chmod 700 configs
    if [ ! -e configs/autoexec.cfg ]; then
      echo -e "// autoexec.cfg\n" > configs/autoexec.cfg
    fi
    cp configs/autoexec.cfg ${GAMEDIR}/${CFGDIR}
    if [ ! -e configs/bans.cfg ]; then
      echo -e "// bans.cfg\n" > configs/bans.cfg
    fi
    ln -sf "${DIR}"/configs/bans.cfg ${GAMEDIR}/${CFGDIR}/${BANFILE}
    if [ ${HLXC[$x]} = yes ]; then
      {
        echo "exec ${BANFILE}"
        echo "sv_logbans 1"
        if [ ${DBUG[$x]} = yes ]; then
          echo "sv_logfile 1"
        else
          echo "sv_logfile 0"
        fi
        echo "log on"
      } >> ${GAMEDIR}/${CFGDIR}/server.cfg
    else
      echo "log off" > ${GAMEDIR}/${CFGDIR}/server.cfg
    fi
    cp ${PCFG}.def ${PCFG}
    CFGS[$x]=$(echo ${CFGS[$x]} | sed -e "s/.cfg/ /g")
    for FILE in ${CFGS[$x]}; do
      if [ ${FILE} = autoexec ]; then
        echo "warning, autoexec.cfg is a reserved filename"
        continue
      fi
      if [ ${FILE} = server ]; then
        echo "warning, server.cfg is a reserved filename"
        continue
      fi
      if [ ${FILE:0:1} = + ]; then
        FILE=${FILE:1}
        echo "exec ${FILE}.cfg" >> ${GAMEDIR}/${CFGDIR}/autoexec.cfg
      elif [ ${FILE:0:1} = @ ]; then
        FILE=${FILE:1}
        echo "exec ${FILE}.cfg" >> ${GAMEDIR}/${CFGDIR}/server.cfg
      elif [ ${FILE:0:1} = % ]; then
        FILE=${FILE:1}
        echo "exec ${FILE}.cfg" >> ${PCFG}
      fi
      if [ ! -e configs/${FILE}.cfg ]; then
        echo "//" > configs/${FILE}.cfg
        echo "warning, configs/${FILE}.cfg not found, creating blank file"
      fi
      ln -s "${DIR}"/configs/${FILE}.cfg ${GAMEDIR}/${CFGDIR}
    done
    chmod 700 ${GAMEDIR}/${CFGDIR}
    if [ ! -e ${GAMEDIR}/mapcycle.txt.def ]; then
      cp ${GAMEDIR}/mapcycle.txt ${GAMEDIR}/mapcycle.txt.def 2> /dev/null \
        || echo // > ${GAMEDIR}/mapcycle.txt.def
    fi
    if [ ! -e configs/${NAME[$x]}_mapcycle.txt ]; then
      echo "warning, configs/${NAME[$x]}_mapcycle.txt not found, using default"
      cp ${GAMEDIR}/mapcycle.txt.def configs/${NAME[$x]}_mapcycle.txt
    fi
    ln -sf "${DIR}"/configs/${NAME[$x]}_mapcycle.txt ${GAMEDIR}/mapcycle.txt
    read -r STARTMAP < ${GAMEDIR}/mapcycle.txt
    if [ ! -z "${MOTD[$x]}" ]; then
      echo "${MOTD[$x]}" > ${GAMEDIR}/motd.txt
    else
      echo "warning, motd url not specified, using mapcycle as greeting"
      cp ${GAMEDIR}/mapcycle.txt ${GAMEDIR}/motd.txt
    fi

    # start server
    USED_NAME=${USED_NAME}${NAME[$x]},
    USED_PORT=${USED_PORT}${PORT[$x]},
    if [ ${DBUG[$x]} = yes ]; then
      if [ ${SERV[$x]} = srcds ]; then
        OPTS[$x]="-debug ${OPTS[$x]}"
      fi
    else
      rm -f ${GAMEDIR}/logs/* ${GAMEDIR}/addons/{amxmodx,sourcemod}/logs/*
    fi
    rm -f ${GAMEDIR}/downloads/*
    ( cd ${SERV[$x]}-${GAME[$x]}/${OB}
      screen -dmS steam_${NAME[$x]} ./${SERV[$x]}_run ${STEAM} -autoupdate \
        +ip 0.0.0.0 -port ${PORT[$x]} -game ${GAME[$x]} ${OPTS[$x]} +sv_lan 0 \
        +map ${STARTMAP}
    )
    echo "starting ${GAME[$x]} server ${NAME[$x]}..."
  done
}

function steam_stop()
{
  # kill servers
  killall -qvw hlds_run
  killall -qvw srcds_run

  # stop hlstatsx daemon
  if [ -e hlstatsx/scripts/run_hlstats ]; then
    ( cd hlstatsx/scripts
      ./run_hlstats stop > /dev/null && echo "stopped hlstatsx daemon"
    )
  fi

  # remove hlstatsx crontab entry
  if crontab -l | grep -q hlstatsx; then
    crontab -l | sed -e "/hlstatsx/d" | crontab -
  fi

  # remove pid and steam data link
  rm -f pdl-steam.pid
  if [ -e ${HOME}/Steam ]; then
    if [ "$(readlink ${HOME}/Steam)" = "${DIR}"/steamcmd ]; then
      rm -f ${HOME}/Steam
    else
      echo "warning, ${HOME}/Steam claimed"
    fi
  fi
}

case ${1} in
restart)
  steam_stop
  steam_start
  ;;
start)
  steam_start
  ;;
stop)
  steam_stop
  ;;
*)
  echo "${0} start|restart|status|stop"
  ;;
esac
