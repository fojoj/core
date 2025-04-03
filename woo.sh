#!/bin/bash

# This script automates setup for a new Ubuntu install with vmangos:
# - Updates and upgrades the system
# - Installs required packages
# - Downloads and sets up vmangos database and core
# - Configures MySQL for the 'mangos' user

# Colors for readability
GREEN='\e[32m'
RED='\e[31m'
NC='\e[0m' # No Color

echo -e "${GREEN}Starting setup for your new vmangos Ubuntu install.${NC}"

# Prompt for Inputs
echo -e "${GREEN}Please enter the MariaDB password for the vmangos 'mangos' user:${NC}"
read -s MYSQL_PASS
export MYSQL_PASS

echo -e "${GREEN}Please enter the hostname for the server (Leave blank for 127.0.0.1) if hosting locally, otherwise your external IP):${NC}"
read ExtIP
export ExtIP="${ExtIP:-127.0.0.1}"

echo -e "${GREEN}Please enter your vmangos realm name:${NC}"
read RealmName
export RealmName

echo -e "${GREEN}Where should we install the vmangos folder? ${NC} (leave blank for /home/): "
read VmDir
export VmDir="${VmDir:-$HOME}"

# Ensure VmDir is set and exists
if [ -z "$VmDir" ]; then
    echo -e "${RED}Error: VmDir cannot be empty. Exiting.${NC}"
    exit 1
fi
mkdir -p "$VmDir" || { echo -e "${RED}Error: Failed to create $VmDir.${NC}"; exit 1; }

# Prompt for downloading the client and compiling extractors
while true; do
    echo -e "${GREEN}Do you need to download the client and compile extractors for map files?${NC}"
    echo " (This is a time-intensive process and is best done once, if possible) (yes/no)"
    read DlAns
    case "$DlAns" in
        [Yy]|[Yy][Ee][Ss])
            export DlAns="yes"
            break
            ;;
        [Nn]|[Nn][Oo])
            export DlAns="no"
            break
            ;;
        *)
            echo "Please answer 'yes' or 'no'."
            ;;
    esac
done

# Download game client files in background if DlAns is "yes"
if [ "$DlAns" == "yes" ]; then
    echo -e "${GREEN}Starting download of the client for extractors. This will run in the background and pause the installer if not finished after compiling.${NC}"
    cd $VmDir || { echo -e "${RED}Error: Cannot cd to $VmDir.${NC}"; exit 1; }
    wget -b "http://cdn.twinstar-wow.com/WoW_Vanilla.zip" > "$VmDir/wget-download.log" 2>&1 &
    echo "Download progress is being logged to $VmDir/wget-download.log"
fi

# Update and Upgrade Ubuntu
echo -e "${GREEN}Updating package lists...${NC}"
sudo apt update || { echo -e "${RED}Error: Failed to update package lists.${NC}"; exit 1; }
echo -e "${GREEN}Upgrading installed packages...${NC}"
sudo apt upgrade -y || { echo -e "${RED}Error: Failed to upgrade packages.${NC}"; exit 1; }

# Install required packages
echo -e "${GREEN}Installing required packages...${NC}"
sudo apt install -y \
    ssh \
    ubuntu-drivers-common \
    git \
    cmake \
    g++ \
    clang \
    mariadb-server \
    libmariadb-dev \
    openssl \
    libssl-dev \
    libreadline-dev \
    build-essential \
    checkinstall \
    zlib1g-dev \
    libtbb-dev \
    libace-dev \
    unzip \
    python3 \
    || { echo -e "${RED}Error: Failed to install packages.${NC}"; exit 1; }
echo -e "${GREEN}Packages installed successfully!${NC}"

# Set environment variables
export TBB_ROOT_DIR=/usr/include/tbb
export ACE_ROOT=/usr/include/ace
echo -e "${GREEN}Environment variables set: TBB_ROOT_DIR and ACE_ROOT.${NC}"

# Download vmangos core
echo -e "${GREEN}Downloading vmangos core repository...${NC}"
cd "$VmDir" || { echo -e "${RED}Error: Cannot cd to $VmDir.${NC}"; exit 1; }
mkdir -p $VmDir/vmangos && cd $VmDir/vmangos || { echo -e "${RED}Error: Failed to create vmangos directory.${NC}"; exit 1; }
git clone https://github.com/fojoj/core.git || { echo -e "${RED}Error: Failed to clone vmangos core.${NC}"; exit 1; }

# Download and set up vmangos database
echo -e "${GREEN}Downloading and setting up vmangos database...${NC}"
cd ~ || { echo -e "${RED}Error: Cannot cd to home directory.${NC}"; exit 1; }
curl -s https://api.github.com/repos/vmangos/core/releases/tags/db_latest | \
    grep "browser_download_url.*zip" | \
    grep -v "sqlite" | \
    cut -d'"' -f4 | \
    wget -i - -O vmangos-db-latest.zip || { echo -e "${RED}Error: Failed to download database.${NC}"; exit 1; }
unzip vmangos-db-latest.zip || { echo -e "${RED}Error: Failed to unzip database.${NC}"; exit 1; }
rm vmangos-db-latest.zip
cd db_dump || { echo -e "${RED}Error: Cannot cd to db_dump.${NC}"; exit 1; }

# Create mangos user in MySQL, replacing if it exists
echo -e "${GREEN}Configuring MySQL user 'mangos'...${NC}"
sudo mysql << EOF || { echo -e "${RED}Error: Failed to configure MySQL user.${NC}"; exit 1; }
DROP USER IF EXISTS 'mangos'@'localhost';
CREATE USER 'mangos'@'localhost' IDENTIFIED BY '$MYSQL_PASS';
GRANT ALL PRIVILEGES ON realmd.* TO 'mangos'@'localhost' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON characters.* TO 'mangos'@'localhost' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON logs.* TO 'mangos'@'localhost' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON mangos.* TO 'mangos'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

# Import SQL files into MySQL
echo -e "${GREEN}Importing database files...${NC}"

# Create databases if they don’t exist
sudo mysql -u mangos -p"$MYSQL_PASS" << EOF || { echo -e "${RED}Error: Failed to create databases.${NC}"; exit 1; }
CREATE DATABASE IF NOT EXISTS realmd;
CREATE DATABASE IF NOT EXISTS characters;
CREATE DATABASE IF NOT EXISTS logs;
CREATE DATABASE IF NOT EXISTS mangos;
EOF

# Import SQL files into the respective databases
sudo mysql -u mangos -p"$MYSQL_PASS" realmd < logon.sql || { echo -e "${RED}Error: Failed to import logon.sql.${NC}"; exit 1; }
sudo mysql -u mangos -p"$MYSQL_PASS" characters < characters.sql || { echo -e "${RED}Error: Failed to import characters.sql.${NC}"; exit 1; }
sudo mysql -u mangos -p"$MYSQL_PASS" logs < logs.sql || { echo -e "${RED}Error: Failed to import logs.sql.${NC}"; exit 1; }
sudo mysql -u mangos -p"$MYSQL_PASS" mangos < mangos.sql || { echo -e "${RED}Error: Failed to import mangos.sql.${NC}"; exit 1; }
# Clean up db_dump
cd "$VmDir" || { echo -e "${RED}Error: Cannot cd to $VmDir.${NC}"; exit 1; }
rm -rf db_dump

# Configure MySQL realmlist
echo -e "${GREEN}Configuring MySQL realmlist...${NC}"
mysql -u mangos -p"$MYSQL_PASS" realmd << EOF || { echo -e "${RED}Error: Failed to configure realmlist.${NC}"; exit 1; }
DELETE FROM realmlist WHERE id=1;
INSERT INTO realmlist (id, name, address, port, icon, realmflags, timezone, allowedSecurityLevel)
VALUES ('1', '$RealmName', '$ExtIP', '8085', '1', '0', '1', '0');
EOF

# Compile the server
echo -e "${GREEN}Preparing to compile vmangos core...${NC}"
cd "$VmDir/vmangos/" || { echo -e "${RED}Error: Cannot cd to $VmDir.${NC}"; exit 1; }
mkdir -p build && cd build || { echo -e "${RED}Error: Failed to create build directory.${NC}"; exit 1; }

NUM_CORES=$(nproc)
echo -e "${GREEN}Detected $NUM_CORES CPU cores for compilation.${NC}"

if [ "$DlAns" == "yes" ]; then
    echo -e "${GREEN}Compiling server files with extractors...${NC}"
    cmake ../core -DCMAKE_INSTALL_PREFIX="$VmDir/vmangos/run" -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DUSE_SCRIPTS=yes -DUSE_EXTRACTORS=yes \
        || { echo -e "${RED}Error: CMake configuration failed with extractors.${NC}"; exit 1; }
else
    echo -e "${GREEN}Compiling server files without extractors...${NC}"
    cmake ../core -DCMAKE_INSTALL_PREFIX="$VmDir/vmangos/run" -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DUSE_SCRIPTS=yes -DUSE_EXTRACTORS=no \
        || { echo -e "${RED}Error: CMake configuration failed without extractors.${NC}"; exit 1; }
fi

echo -e "${GREEN}Building vmangos core...${NC}"
make -j"$NUM_CORES" || { echo -e "${RED}Error: Compilation failed.${NC}"; exit 1; }
make install || { echo -e "${RED}Error: Installation failed.${NC}"; exit 1; }

# Copying server configuration files from .conf.dist to .conf
cp $VmDir/vmangos/run/etc/mangosd.conf.dist $VmDir/vmangos/run/etc/mangosd.conf
cp $VmDir/vmangos/run/etc/realmd.conf.dist $VmDir/vmangos/run/etc/realmd.conf

# Changing hostname in config files (if applicable)
if [ -n "$ExtIP" ] && [ "$ExtIP" != "127.0.0.1" ]; then
    sed -i "s/\"127.0.0.1\"/\"$ExtIP\"/g" "$VmDir/vmangos/run/etc/mangosd.conf"
    sed -i "s/\"127.0.0.1\"/\"$ExtIP\"/g" "$VmDir/vmangos/run/etc/realmd.conf"
fi

# Replace mangos mysql password in configuration files
sed -i "s/\"mangos\"/\"mangos\" \"$MYSQL_PASS\"/g" $VmDir/vmangos/run/etc/mangosd.conf
sed -i "s/\"mangos\"/\"mangos\" \"$MYSQL_PASS\"/g" $VmDir/vmangos/run/etc/realmd.conf

# If DlAns = yes, wait for the download to finish before continuing
if [ "$DlAns" == "yes" ]; then
    echo -e "${GREEN}Waiting for the client download to finish...${NC}"
    wait # Waits for all background processes to finish
    echo -e "${GREEN}Download complete!${NC}"
    cd ~ || { echo -e "${RED}Error: Cannot cd to home directory.${NC}"; exit 1; }
    unzip -o WoW_Vanilla.zip -d "$VmDir" || { echo -e "${RED}Error: Failed to unzip client.${NC}"; exit 1; }
    mv 'WoW_Vanilla' WoW || { echo -e "${RED}Error: Failed to rename client directory.${NC}"; exit 1; }
    mv $VmDir/vmangos/run/bin/Extractors/* $VmDir/WoW || { echo -e "${RED}Error: Failed to move extractors.${NC}"; exit 1; }
    rm -rf $VmDir/vmangos/run/bin/Extractors
    rm -rf WoW_Vanilla.zip
    echo -e "${GREEN}Client files and extractors moved to $VmDir/WoW.${NC}"
    cd WoW || { echo -e "${RED}Error: Cannot cd to WoW directory.${NC}"; exit 1; }
    chmod +x VMapAssembler VmapExtractor MapExtractor MoveMapGenerator
    ./VMapAssembler
    wait # Wait for VMapAssembler to finish
    echo -e "${GREEN}VMapAssembler completed successfully!${NC}"
    ./VmapExtractor
    wait # Wait for VmapExtractor to finish
    echo -e "${GREEN}VmapExtractor completed successfully!${NC}"
    ./MoveMapGenerator
    wait # Wait for MoveMapGenerator to finish
    echo -e "${GREEN}MoveMapGenerator completed successfully!${NC}"
    echo -e "${GREEN}Running mmap_extract.py... this will likely take the longest. Please be patient :) ${NC}"
    python3 mmap_extract.py
    wait # Wait for mmap_extract.py to finish
    echo -e "${GREEN}mmap_extract.py completed successfully!${NC}"
    echo -e "${GREEN}Hard part is over. Copying extracted files to the correct directory for vmangos to use!${NC}"
    mv dbc -R $VmDir/vmangos/data
    mv maps -R $VmDir/vmangos/data
    mv vmaps -R $VmDir/vmangos/data
    mv mmaps -R $VmDir/vmangos/data
fi

# Final message
echo -e "${GREEN}Setup and compilation complete!${NC}"
echo "Check above for any errors. Next steps: Start the server from $VmDir/vmangos/run/bin."