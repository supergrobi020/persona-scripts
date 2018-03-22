#!/bin/bash

#set -x

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
#                                                     #
#               Persona Commander Script              #
# 	          developed by tharude 	              #
#		a.k.a The Forging Penguin	      #
#         thanks ViperTKD for the helping hand        #
#                 19/01/2017 ARK Team                 #
#         and modified for Persona by                 #
#               SuperGrobi2.0                         #
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

LOC_SERVER="http://127.0.0.1"
persona_enviroment="testnet"

pause(){
        read -p "   	Press [Enter] key to continue..." fakeEnterKey
}

#PSQL Queries
query() {
    PUBKEY="$(psql -d persona_testnet -t -c 'SELECT ENCODE("publicKey",'"'"'hex'"'"') as "publicKey" FROM mem_accounts WHERE "address" = '"'"$ADDRESS"'"' ;' | xargs)"
    DNAME="$(psql -d persona_testnet -t -c 'SELECT username FROM mem_accounts WHERE "address" = '"'"$ADDRESS"'"' ;' | xargs)"
    PROD_BLOCKS="$(psql -d persona_testnet -t -c 'SELECT producedblocks FROM mem_accounts WHERE "address" = '"'"$ADDRESS"'"' ;' | xargs)"
    MISS_BLOCKS="$(psql -d persona_testnet -t -c 'SELECT missedblocks FROM mem_accounts WHERE "address" = '"'"$ADDRESS"'"' ;' | xargs)"
    #BALANCE="$(psql -d persona_testnet -t -c 'SELECT (balance/100000000.0) as balance FROM mem_accounts WHERE "address" = '"'"$ADDRESS"'"' ;' | sed -e 's/^[[:space:]]*//')"
    BALANCE="$(psql -d persona_testnet -t -c 'SELECT to_char(("balance"/100000000.0), '"'FM 999,999,999,990D00000000'"' ) as balance FROM mem_accounts WHERE "address" = '"'"$ADDRESS"'"' ;' | xargs)"
    HEIGHT="$(psql -d persona_testnet -t -c 'SELECT height FROM blocks ORDER BY HEIGHT DESC LIMIT 1;' | xargs)"
    RANK="$(psql -d persona_testnet -t -c 'WITH RANK AS (SELECT DISTINCT "publicKey", "vote", "round", row_number() over (order by "vote" desc nulls last) as "rownum" FROM mem_delegates where "round" = (select max("round") from mem_delegates) ORDER BY "vote" DESC) SELECT "rownum" FROM RANK WHERE "publicKey" = '"'03cfafb2ca8cf7ce70f848456b1950dc7901946f93908e4533aace997c242ced8a'"';' | xargs)"
}

function net_height {
    local heights=$(curl -s "$LOC_SERVER/api/peers" | jq -r '.peers[] | .height')
    
    highest=$(echo "${heights[*]}" | sort -nr | head -n1)
}

function proc_vars {
        node=`pgrep -a "node" | grep persona-node | awk '{print $1}'`
        if [ "$node" == "" ] ; then
                node=0
        fi

        # Is Postgres running
        pgres=`pgrep -a "postgres" | awk '{print $1}'`

        # Find if forever process manager is runing
        frvr=`pgrep -a "node" | grep forever | awk '{print $1}'`

        # Find the top level process of node
        #top_lvl=$(top_level_parent_pid $node)

        # Looking for ark-node installations and performing actions
        personadir=$(locate -b 'persona-node')

        # Getting the parent of the install path
        parent=`dirname $personadir 2>&1`

        # Forever Process ID
        forever_process=`forever --plain list | grep $node | sed -nr 's/.*\[(.*)\].*/\1/p'`

        # Node process work directory
        nwd=`pwdx $node 2>/dev/null | awk '{print $2}'`
}


# Drop ARK DB
function drop_db {
        # check if it's running and start if not.
        if [ -z "$pgres" ]; then
                sudo service postgresql start
        fi
        echo -e "\n\t✔ Droping the persona database!"
        dropdb --if-exists persona_testnet
}

function create_db {
        #check if PG is running here if not Start.
        if [ -z "$pgres" ]; then
                sudo service postgresql start
        fi
        echo -e "\n\t✔ Creating the persona database!"
         sudo -u postgres psql -c "update pg_database set encoding = 6, datcollate = 'en_US.UTF8', datctype = 'en_US.UTF8' where datname = 'template0';"
         sudo -u postgres psql -c "update pg_database set encoding = 6, datcollate = 'en_US.UTF8', datctype = 'en_US.UTF8' where datname = 'template1';"
         sudo -u postgres dropuser --if-exists $USER
         sudo -u postgres psql -c "CREATE USER $USER WITH PASSWORD 'password' CREATEDB;"

        createdb persona_${persona_enviroment}
}

### Dan on 24.02.2018
function promptyn () {
    while true; do
        read -p "$1 " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo -e "\nPlease answer yes or no.\n";;
        esac
    done
}

# Check if program is installed
function node_check {
        # defaulting to 1
        return_=1
        # changing to 0 if not found
        type $1 >/dev/null 2>&1 || { return_=0; }
        # return value
        # echo "$return_"
}

function os_up {
    echo -e "Checking for system updates...\n"
    sudo apt-get update >&- 2>&-
    avail_upd=`/usr/lib/update-notifier/apt-check 2>&1 | cut -d ';' -f 1`
        if [ "$avail_upd" == 0 ]; then
                echo -e "There are no updates available\n"
                sleep 1
        else
	     if promptyn "There are $avail_upd updates available for your system. Would you like to install them now? [y/N]: "; then
            echo -e "Updating the system...\n"

            sudo apt-get upgrade -yqq
            sudo apt-get dist-upgrade -yq
            
			echo -e "Do some cleanup..."

			sudo apt-get autoremove -yyq
            sudo apt-get autoclean -yq
            
			echo -e "\nThe system was updated!"
            echo -e "\nSystem restart is recommended!"
            
         else
            echo -e "\nSystem update canceled. We strongly recommend that you update your operating system on a regular basis."
         fi
        fi
}

function check_dependencies()
{
    local -a dependencies="postgresql postgresql-contrib libpq-dev build-essential python git curl jq libtool autoconf locales automake locate zip unzip htop nmon iftop pkg-config libcairo2-dev libgif-dev ntp"

    DEPS_TO_INSTALL=""
    for dependency in ${dependencies[@]}; do
        PKG_INSTALLED=$(dpkg -l "$dependency" 2>/dev/null | fgrep "$dependency" | egrep "^[a-zA-Z]" | awk '{print $2}') || true
        if [[ "$PKG_INSTALLED" != "$dependency" ]]; then
            DEPS_TO_INSTALL="$DEPS_TO_INSTALL$dependency "
        fi
    done

    if [[ ! -z "$DEPS_TO_INSTALL" ]]; then
	     if promptyn "Dependencies [ ${DEPS_TO_INSTALL}] are not installed. Do you want to install them? [y/N]: "; then
            echo -e "Installing Program Dependencies...\n"
            sudo sh -c "sudo apt-get install ${DEPS_TO_INSTALL}"
            echo -e "Program Dependencies Installed!\n"
         else
            echo -e "\nPlease ensure that the following packages are installed and try again:\n${DEPS_TO_INSTALL}"
         fi
	fi
}

# Install Node Version Manager (NVM)
function nvm {
        node_check node
        if [ "$return_" == 0 ]; then
                echo -e "Node is not installed, installing..."
                curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.32.0/install.sh 2>/dev/null | bash >>install.log
                export NVM_DIR="$HOME/.nvm"
                [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

                ### Installing node ###
                nvm install 8.9.4 >>install.log
                nvm use 8.9.4 >>install.log
                nvm alias default 8.9.4 >>install.log
				npm install -g npm >>install.log 2>&1
                echo -e "Node `node -v` has been installed.)"
        else
                echo -e "Node `node -v` is  already installed.)"
        fi

        node_check forever
        if [ "$return_" == 0 ]; then
                echo -e "(Forever is not installed, installing...)"
                ### Install forever ###
                sudo npm install forever -g >>install.log 2>&1
                echo -e "(Forever has been installed.)"
        else
                echo -e "(Forever is alredy installed.)"
        fi
        # Setting fs.notify.max_user_watches
        if grep -qi 'fs.inotify' /etc/sysctl.conf ; then
                echo -e "\n(fs.inotify.max_user_watches is already set.)"
        else
                echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf && sudo sysctl -p
        fi
        echo -e "\n(Check install.log for reported install errors.)"
}
### End Dan


# Start Persona Node
start(){
        proc_vars
        if [ -e $personadir/app.js ]; then
                echo -e "\n\t✔ Persona Node installation found!"
                if [ "$node" != "" ] && [ "$node" != "0" ]; then
                        echo -e "\tA working instance of ARK Node was found with:"
                        echo -e "\tSystem PID: $node, Forever PID $forever_process"
                        echo -e "\tand Work Directory: $personadir\n"
        else
            echo -e "\n\tStarting Persona Node..."
            cd $personadir
            forever start app.js --genesis genesisBlock.testnet.json --config config.testnet.json >&- 2>&-
            cd $parent
            echo -e "\t✔ Persona Node was successfully started"
            sleep 1
            proc_vars
            echo -e "\n\tPersona Node started with:"
            echo -e "\tSystem PID: $node, Forever PID $forever_process"
            echo -e "\tand Work Directory: $personadir\n"
                fi
    else
        echo -e "\n✘ No Persona Node installation is found\n"
    fi
}


# Node Status
status(){
        proc_vars
        if [ -e $personadir/app.js ]; then
		echo -e "\n\tStatus Persona Node..."
                echo -e "\t✔ Persona Node installation found!"
                if [ "$node" != "" ] && [ "$node" != "0" ]; then
                        echo -e "\tPersona Node process is working with:"
                        echo -e "\tSystem PID: $node, Forever PID $forever_process"
                        echo -e "\tand Work Directory: $personadir"
            			query
			            echo -e "\tBlock height: $HEIGHT"
                        echo -e "\tPeer table: $net_height\t"
                else
                        echo -e "\t✘ No Persona Node process is running"
                fi
        else
                echo -e "\n\t✘ No Persona Node installation is found\n"
        fi
}


# Install Persona node
inst_persona(){
        cd $HOME
        check_dependencies
        nvm
        git clone https://github.com/PersonaIam/personatestnet persona-node
        cd persona-node
        npm install libpq 2>/dev/null
        npm install secp256k1 2>/dev/null
        npm install bindings 2>/dev/null
        npm install 2>/dev/null
        echo -e "(Drink a beer. We need up upgrade the file system database. This is making us faster.)"
        sudo updatedb
        cp $HOME/persona.sh $HOME/persona-node/
}

# Restart Node
restart(){
    proc_vars
    #echo -e "\n\tRestarting Pesona Node..."
    if [ "$node" != "" ] && [ "$node" != "0" ]; then
                echo -e "\tInstance of Persona Node found with:"
                echo -e "\tSystem PID: $node, Forever PID $forever_process"
                echo -e "\tDirectory: $personadir\n"
        forever restart $forever_process >&- 2>&-
        echo -e "\t✔ Persona Node was successfully restarted\n"
    else
        echo -e "\n\t✘ Persona Node process is not running\n"
    fi
}


# Stop Node
killit(){
        proc_vars
        if [ -e $personadir/app.js ]; then
		echo -e "\n\tKillin Persona Node..."
                echo -e "\t✔ Persona Node installation found!"
                if [ "$node" != "" ] && [ "$node" != "0" ]; then
                        echo -e "\tA working instance of Pesona Node was found with:"
                        echo -e "\tSystem PID: $node, Forever PID $forever_process"
                        echo -e "\tand Work Directory: $personadir\n"
            echo -e "\n\tStopping Pesona Node..."
            cd $personadir
            forever stop $forever_process >&- 2>&-
            cd $parent
            echo -e "\t✔ Persona Node was successfully stopped"
                else
            echo -e "\t✘ No Persona Node process is running"
                fi
        else
                echo -e "\t✘ No Persona Node installation is found"
        fi
}


case $1 in
    "reload")
      killit
      sleep 2
      start
      #show_blockHeight
      ;;
    "status")
      status
    ;;
    "start")
      start
    ;;
    "stop")
      killit
    ;;
    "clean_db")
      killit
      drop_db
      create_db
    ;;
    "install")
      inst_persona
    ;;
    "os_update")
      os_up
      ;;
    "persona_dependencies")
      check_dependencies
    ;;
    "node_dependencies")
      nvm
    ;;
*)
    echo 'Available options: reload (stop/start), start, stop, clean_db install, os_update, persona_dependencies, node_dependencies'
    echo "Usage: ${0}"
    exit 1
    ;;
esac
exit 0
