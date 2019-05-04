# Script to inject dynamic libraries to ipa files
# Comes under GNU Affero General Public License v3.0
# Copyright (C) 2019 iPAWiND - All Rights Reserved
# https://ipawind.com

ipaFile=$1
dylibFolder=$2
profilePath=$3
savedProfilePath="./embedded.mobileprovision"

printf "\n"

function showUsage {
    printf "\n"
    echo "Usage:"
    echo "patch.sh 'path_to_ipa_file' 'path_to_dylibs_folder' 'path_to_mobile_provision(optional)'"
    printf "\n"
}

if [ -z "$ipaFile" ]; then
    echo "iPA file path not specified"
    showUsage
    exit 1
elif [ -z "$dylibFolder" ]; then
    echo "Dylibs folder not specified"
    showUsage
    exit 1
fi

#all work is done in temporary directoy
#nothing happens outside it
tmpDir="/tmp/"$RANDOM

mkdir "$tmpDir"

# Unzip ipa to tmpDir
unzip "$ipaFile" -d "$tmpDir" &> /dev/null

payloadDir="$tmpDir/Payload"
appPath=$( echo "$payloadDir"/*.app )

if ! [ -e "$appPath" ]; then
    echo "Invalid iPA File"
    exit 1
fi

# Copy dylib folder contents to app dir
cp "$dylibFolder"/* "$appPath/"

# Find all dylibs and inject them
dylibs=$( find "$appPath" -name '*.dylib' -maxdepth 1 )

if [ -z "$dylibs" ]; then
    echo "Dylibs not found, make sure they're in folder root"
    exit 1
fi

#inject
for dylibPath in "$dylibs"; do

    dylibName=$( basename "$dylibPath" )

    echo "Injecting $dylibName"

    ./optool install -c load -p "@executable_path/$dylibName" -t "$appPath" &> /dev/null

done

#if no profile specified, and saved profile exists, use it
if [ -z "$profilePath" ] && [ -e "$savedProfilePath" ]; then
    profilePath="$savedProfilePath"
fi

if ! [ -e "$profilePath" ]; then
    echo "Profile not found, skipping codesign"
else

    #copy profile to app
    cp "$profilePath" "$appPath/embedded.mobileprovision"

    #save profile
    cp "$profilePath" "$savedProfilePath" &> /dev/null

    #profile
    profilePlistPath="$tmpDir/embedded.plist"
    security cms -D -i "$profilePath" > "$profilePlistPath"

    teamName=$( /usr/libexec/PlistBuddy -c "Print TeamName" "$profilePlistPath")

    #entitlements
    entitlementsPath="$tmpDir/entitlements.plist"
    /usr/libexec/PlistBuddy -x -c 'Print:Entitlements' "$profilePlistPath" > "$entitlementsPath"

    echo "CodeSign With Team: $teamName"

    #codesign binaries
    find "$appPath" \( -name "*.app" -o -name "*.framework" -o -name "*.appex" -o -name "*.dylib" \) -mindepth 1 -exec codesign -fs "$teamName" {} \; 2> /dev/null

    #codesign main app
    codesign -fs "$teamName" --entitlements "$entitlementsPath" "$appPath" 2> /dev/null
fi

echo "Zipping iPA"

#zip
cd "$tmpDir" && zip -r "$tmpDir/app-modified.ipa" "Payload" &> /dev/null

echo "All Done"

#open dir
open ./
