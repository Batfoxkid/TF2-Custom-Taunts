cd build

mkdir -p package/addons/sourcemod/plugins
mkdir -p package/addons/sourcemod/gamedata
mkdir -p package/addons/sourcemod/configs

cp -r addons/sourcemod/plugins/tf2_custom_taunts.smx package/addons/sourcemod/plugins
cp -r addons/sourcemod/gamedata/tf2.tauntem.txt package/addons/sourcemod/gamedata
cp -r addons/sourcemod/configs/customtaunts.cfg package/addons/sourcemod/configs